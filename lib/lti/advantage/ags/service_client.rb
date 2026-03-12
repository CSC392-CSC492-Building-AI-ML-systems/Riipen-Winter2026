# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"
require "jwt"

module Lti
  module Advantage
    module AGS
      class ServiceClient
        CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        TOKEN_GRANT_TYPE = "client_credentials"
        DEFAULT_TOKEN_TTL = 300

        attr_reader :launch, :registration, :endpoint

        def initialize(launch:, key_pair:, clock: -> { Time.now }, http_request: nil)
          @launch = launch
          @registration = launch.registration
          @endpoint = launch.ags_endpoint
          @key_pair = key_pair
          @clock = clock
          @http_request = http_request || method(:default_http_request)
          @token_cache = {}
        end

        def score_service
          ScoreService.new(service_client: self)
        end

        def result_service
          ResultService.new(service_client: self)
        end

        def get_json(url:, accept:, scopes:)
          response = request(
            method: :get,
            url: url,
            scopes: scopes,
            headers: { "Accept" => accept }
          )
          body = response.respond_to?(:body) ? response.body : response[:body]
          return [] if body.nil? || body.to_s.strip.empty?

          JSON.parse(body)
        end

        def post_json(url:, body:, content_type:, accept:, scopes:)
          response = request(
            method: :post,
            url: url,
            body: JSON.generate(body),
            scopes: scopes,
            headers: {
              "Content-Type" => content_type,
              "Accept" => accept
            }
          )

          validate_service_response!(response, success_codes: [200, 201])
          response
        end

        def request(method:, url:, scopes:, headers: {}, body: nil)
          response = @http_request.call(
            method: method,
            url: url,
            headers: headers.merge("Authorization" => "Bearer #{access_token(scopes)}"),
            body: body
          )

          validate_service_response!(response)
          response
        end

        def access_token(scopes)
          token_scopes = Array(scopes).map(&:to_s).sort.freeze
          raise ConfigurationError, "AGS endpoint claim is missing from this launch" if endpoint.nil?
          raise ConfigurationError, "Registration token_endpoint is required for AGS" if registration.token_endpoint.nil?

          token_scopes.each { |scope| endpoint.require_scope!(scope) }

          cache_key = token_scopes.join(" ")
          cached = @token_cache[cache_key]
          return cached[:access_token] if cached && cached[:expires_at] > @clock.call

          token_response = request_access_token!(token_scopes)
          @token_cache[cache_key] = token_response
          token_response[:access_token]
        end

        private

        def request_access_token!(scopes)
          response = @http_request.call(
            method: :post,
            url: registration.token_endpoint,
            headers: {
              "Content-Type" => "application/x-www-form-urlencoded",
              "Accept" => "application/json"
            },
            body: URI.encode_www_form(token_request_body(scopes))
          )

          validate_token_response!(response)
        end

        def token_request_body(scopes)
          {
            "grant_type" => TOKEN_GRANT_TYPE,
            "client_assertion_type" => CLIENT_ASSERTION_TYPE,
            "client_assertion" => client_assertion,
            "scope" => scopes.join(" ")
          }
        end

        def client_assertion
          now = @clock.call.to_i

          JWT.encode(
            {
              "iss" => registration.client_id,
              "sub" => registration.client_id,
              "aud" => registration.token_audience || registration.token_endpoint,
              "iat" => now,
              "exp" => now + DEFAULT_TOKEN_TTL,
              "jti" => SecureRandom.uuid
            },
            @key_pair.private_key,
            "RS256",
            kid: @key_pair.kid
          )
        end

        def validate_token_response!(response)
          code = response.code.to_i
          unless (200..299).cover?(code)
            raise AuthorizationError,
                  "AGS access token request failed with HTTP #{code}: #{response.body}"
          end

          payload = JSON.parse(response.body)
          access_token = payload["access_token"].to_s
          raise AuthorizationError, "AGS access token response is missing access_token" if access_token.empty?

          token_type = payload["token_type"].to_s
          if !token_type.empty? && token_type.casecmp("bearer") != 0
            raise AuthorizationError, "AGS access token response must return Bearer token_type"
          end

          expires_in = payload["expires_in"].to_i
          {
            access_token: access_token,
            expires_at: @clock.call + [expires_in - 30, 1].max
          }
        rescue JSON::ParserError => e
          raise AuthorizationError, "AGS access token response is not valid JSON: #{e.message}"
        end

        def validate_service_response!(response, success_codes: (200..299).to_a)
          code = response.code.to_i
          return if success_codes.include?(code)

          error_class = case code
                        when 401, 403
                          AuthorizationError
                        else
                          ServiceError
                        end

          raise error_class, "AGS service request failed with HTTP #{code}: #{response.body}"
        end

        def default_http_request(method:, url:, headers:, body: nil)
          uri = URI.parse(url)
          request = build_request(method, uri, headers, body)

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.request(request)
          end
        end

        def build_request(method, uri, headers, body)
          request_class = case method.to_sym
                          when :get then Net::HTTP::Get
                          when :post then Net::HTTP::Post
                          else
                            raise ArgumentError, "Unsupported HTTP method: #{method}"
                          end

          request = request_class.new(uri)
          headers.each { |name, value| request[name] = value }
          request.body = body unless body.nil?
          request
        end
      end
    end
  end
end
