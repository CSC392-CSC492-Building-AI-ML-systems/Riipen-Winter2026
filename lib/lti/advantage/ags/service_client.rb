# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "set"
require "time"
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

        def initialize(
          launch:, key_pair:, clock: -> { Time.now }, http_request: nil,
          enforce_same_origin: true, allowed_origins: nil
        )
          @launch = launch
          @registration = launch.registration
          @endpoint = launch.ags_endpoint
          @key_pair = key_pair
          @clock = clock
          @http_request = http_request || method(:default_http_request)
          @enforce_same_origin = enforce_same_origin
          @allowed_origins = normalize_allowed_origins(allowed_origins)
          @trusted_service_origins = discover_service_origins
          @token_cache = {}
          @published_scores = {}
        end

        def score_service
          ScoreService.new(service_client: self)
        end

        def result_service
          ResultService.new(service_client: self)
        end

        def line_item_service
          LineItemService.new(service_client: self)
        end

        def get_json(url:, accept:, scopes:)
          response = request(
            method: :get,
            url: url,
            scopes: scopes,
            headers: { "Accept" => accept }
          )

          body = response.body.to_s.strip
          return [] if body.empty?

          JSON.parse(body)
        end

        def get_json_with_headers(url:, accept:, scopes:)
          response = request(
            method: :get,
            url: url,
            scopes: scopes,
            headers: { "Accept" => accept }
          )

          body = response.body.to_s.strip
          data = body.empty? ? [] : JSON.parse(body)
          link_header = read_link_header(response)
          content_type = read_content_type(response)
          { data: data, link_header: link_header, content_type: content_type }
        end

        def post_json(url:, body:, content_type:, accept:, scopes:)
          request(
            method: :post,
            url: url,
            body: JSON.generate(body),
            scopes: scopes,
            headers: {
              "Content-Type" => content_type,
              "Accept" => accept
            }
          )
        end

        def put_json(url:, body:, content_type:, accept:, scopes:)
          request(
            method: :put,
            url: url,
            body: JSON.generate(body),
            scopes: scopes,
            headers: {
              "Content-Type" => content_type,
              "Accept" => accept
            }
          )
        end

        def request(method:, url:, scopes:, headers: {}, body: nil)
          token = access_token(scopes)
          normalized_url = normalize_service_request_url(url)

          response = @http_request.call(
            method: method,
            url: normalized_url,
            headers: headers.merge("Authorization" => "Bearer #{token}"),
            body: body
          )

          validate_service_response!(response)
          response
        end

        def follow_up_url(link_header:, relation:, request_url:)
          resolved_url = LinkHeader.relation_url(link_header, relation, base_url: request_url)
          return nil if resolved_url.nil?

          normalize_service_request_url(resolved_url, field_name: "AGS Link header URL")
        rescue ArgumentError, URI::InvalidURIError => e
          raise ServiceError, "Malformed AGS Link header: #{e.message}"
        end

        def access_token(scopes)
          token_scopes = Array(scopes).map(&:to_s).sort.freeze
          raise ConfigurationError, "AGS endpoint claim is missing from this launch" if endpoint.nil?

          if registration.token_endpoint.nil?
            raise ConfigurationError,
                  "Registration token_endpoint is required for AGS"
          end

          token_scopes.each { |scope| endpoint.require_scope!(scope) }

          cache_key = token_scopes.join(" ")
          cached = @token_cache[cache_key]
          return cached[:access_token] if cached && cached[:expires_at] > @clock.call

          token_response = request_access_token!(token_scopes)
          @token_cache[cache_key] = token_response
          token_response[:access_token]
        end

        def validate_score_publish!(score:, score_url:)
          key = published_score_key(score_url: score_url, user_id: score.user_id)
          current_timestamp = Time.iso8601(score.timestamp)
          previous_timestamp = @published_scores[key]
          return if previous_timestamp.nil? || current_timestamp > previous_timestamp

          raise ValidationError,
                "score timestamp must be later than the previous score for this user and line item"
        end

        def remember_score_publish!(score:, score_url:)
          key = published_score_key(score_url: score_url, user_id: score.user_id)
          @published_scores[key] = Time.iso8601(score.timestamp)
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
          payload = {
            "iss" => registration.client_id,
            "sub" => registration.client_id,
            "aud" => registration.token_audience || registration.token_endpoint,
            "iat" => now,
            "exp" => now + DEFAULT_TOKEN_TTL,
            "jti" => SecureRandom.uuid
          }
          payload[Claims::DEPLOYMENT_ID] = launch.deployment_id unless launch.deployment_id.nil?

          JWT.encode(
            payload,
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

        def read_link_header(response)
          return response.link_header if response.respond_to?(:link_header)
          return response["Link"] if response.respond_to?(:[]) && response["Link"]

          nil
        rescue NameError
          nil
        end

        def read_content_type(response)
          return response.content_type if response.respond_to?(:content_type) && !response.content_type.nil?
          return response["Content-Type"] if response.respond_to?(:[]) && response["Content-Type"]

          nil
        rescue NameError
          nil
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

        def normalize_service_request_url(url, field_name: "AGS request URL")
          string_value = url.to_s.strip
          raise ServiceError, "#{field_name} cannot be blank" if string_value.empty?

          uri = URI.parse(string_value)
          raise ServiceError, "#{field_name} must be an absolute HTTP(S) URL" unless absolute_http_uri?(uri)

          normalized_url = uri.to_s
          origin = request_origin(normalized_url)
          return normalized_url unless @enforce_same_origin
          return normalized_url if trusted_service_origin?(origin)
          return normalized_url if @allowed_origins.include?(origin)

          raise ServiceError, "Refusing to send AGS token to a different origin"
        rescue URI::InvalidURIError => e
          raise ServiceError, "Invalid #{field_name}: #{e.message}"
        end

        def normalize_allowed_origins(origins)
          Array(origins).each_with_object(Set.new) do |origin, normalized_origins|
            normalized_url = normalize_origin_source(origin, field_name: "allowed_origins entry")
            normalized_origins << request_origin(normalized_url)
          end
        rescue ServiceError => e
          raise ConfigurationError, e.message
        end

        def discover_service_origins
          Set.new.tap do |origins|
            [endpoint&.lineitems_url, endpoint&.lineitem_url].compact.each do |url|
              origins << request_origin(normalize_origin_source(url, field_name: "AGS endpoint URL"))
            end
          end
        rescue ServiceError
          Set.new
        end

        def normalize_origin_source(url, field_name:)
          string_value = url.to_s.strip
          raise ServiceError, "#{field_name} cannot be blank" if string_value.empty?

          uri = URI.parse(string_value)
          raise ServiceError, "#{field_name} must be an absolute HTTP(S) URL" unless absolute_http_uri?(uri)

          uri.to_s
        rescue URI::InvalidURIError => e
          raise ServiceError, "Invalid #{field_name}: #{e.message}"
        end

        def trusted_service_origin?(origin)
          @trusted_service_origins.include?(origin)
        end

        def absolute_http_uri?(uri)
          uri.is_a?(URI::HTTP) && !uri.host.nil?
        end

        def request_origin(url)
          uri = URI.parse(url)
          "#{uri.scheme}://#{uri.host}:#{uri.port}"
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
                          when :put then Net::HTTP::Put
                          when :delete then Net::HTTP::Delete
                          else
                            raise ArgumentError, "Unsupported HTTP method: #{method}"
                          end

          request = request_class.new(uri)
          headers.each { |name, value| request[name] = value }
          request.body = body unless body.nil?
          request
        end

        def published_score_key(score_url:, user_id:)
          [score_url.to_s, user_id.to_s].freeze
        end
      end
    end
  end
end
