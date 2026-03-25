# frozen_string_literal: true

require "jwt"
require "faraday"
require "securerandom"
require "json"
require "uri"

module Lti
  module Advantage
    module Services
      # Obtains a short-lived OAuth 2.0 access token from the LMS using the
      # JWT client-credentials grant defined in the LTI 1.3 security framework.
      #
      # The tool signs a JWT assertion with its own private key; the LMS verifies
      # it via the tool's JWKS endpoint and returns a bearer token.
      #
      # @example
      #   token_service = Lti::Advantage::Services::AccessToken.new(
      #     key_pair:       TOOL_KEY_PAIR,
      #     client_id:      CLIENT_ID,
      #     token_endpoint: "https://lms.example.com/login/oauth2/token",
      #     scope:          Lti::Advantage::Services::NamesRoleService::SCOPE,
      #     deployment_id:  launch.deployment_id
      #   )
      #   bearer = token_service.fetch
      class AccessToken
        # @param key_pair [Lti::Advantage::KeyPair] the tool's RSA key pair
        # @param client_id [String] the tool's Client ID registered in the LMS
        # @param token_endpoint [String] the LMS OAuth2 token URL
        # @param scope [String] space-separated list of OAuth2 scopes to request
        # @param deployment_id [String, nil] optional LTI deployment id to bind
        #   the token request to a specific deployment
        def initialize(key_pair:, client_id:, token_endpoint:, scope:, deployment_id: nil)
          @key_pair       = key_pair
          @client_id      = assert_presence("client_id", client_id)
          @token_endpoint = normalize_http_url("token_endpoint", token_endpoint)
          @scope          = assert_presence("scope", scope)
          @deployment_id  = normalize_optional_string(deployment_id)
        end

        # Requests a bearer token from the LMS.
        #
        # @return [String] the raw access token string
        # @raise [Lti::Advantage::Error] on network failure or non-200 response
        def fetch
          response = Faraday.post(@token_endpoint) do |req|
            req.headers["Content-Type"] = "application/x-www-form-urlencoded"
            req.body = URI.encode_www_form(token_request_params)
          end

          raise Error, "Token request failed (#{response.status}): #{response.body}" unless response.status == 200

          parsed = parse_token_response(response.body)
          access_token = required_response_string(parsed, "access_token")
          token_type = required_response_string(parsed, "token_type")

          raise Error, "Expected token_type Bearer, got #{token_type.inspect}" unless token_type.casecmp?("Bearer")

          access_token
        rescue Faraday::Error => e
          raise Error, "Network error fetching access token: #{e.message}"
        rescue JSON::ParserError => e
          raise Error, "Failed to parse access token response: #{e.message}"
        end

        private

        # Builds the POST body params for the client_credentials grant.
        # @return [Hash]
        def token_request_params
          {
            grant_type: "client_credentials",
            client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            client_assertion: build_client_assertion,
            scope: @scope
          }
        end

        # Creates a short-lived JWT signed with the tool's private key.
        # The LMS uses the tool's JWKS to verify this assertion.
        #
        # @return [String] signed JWT
        def build_client_assertion
          now = Time.now.to_i
          payload = {
            iss: @client_id,
            sub: @client_id,
            aud: @token_endpoint,
            iat: now,
            exp: now + 300, # 5 minutes
            jti: SecureRandom.uuid
          }
          payload[Claims::DEPLOYMENT_ID] = @deployment_id if @deployment_id

          JWT.encode(
            payload,
            @key_pair.private_key,
            "RS256",
            { kid: @key_pair.kid }
          )
        end

        def parse_json_body(body)
          case body
          when Hash
            body
          else
            JSON.parse(body.to_s)
          end
        end

        def parse_token_response(body)
          parsed = parse_json_body(body)
          raise Error, "Access token response must be a JSON object" unless parsed.is_a?(Hash)

          parsed
        end

        def required_response_string(parsed, field_name)
          value = parsed[field_name]
          string_value = value.to_s.strip
          raise Error, "No #{field_name} in response: #{parsed.inspect}" if string_value.empty?

          string_value
        end

        def assert_presence(name, value)
          string_value = value.to_s.strip
          raise ConfigurationError, "#{name} is required" if string_value.empty?

          string_value
        end

        def normalize_http_url(name, value)
          string_value = assert_presence(name, value)
          uri = URI.parse(string_value)
          unless uri.is_a?(URI::HTTP) && !uri.host.nil?
            raise ConfigurationError, "#{name} must be an absolute HTTP(S) URL"
          end

          uri.to_s
        rescue URI::InvalidURIError => e
          raise ConfigurationError, "Invalid #{name}: #{e.message}"
        end

        def normalize_optional_string(value)
          return nil if value.nil?

          string_value = value.to_s.strip
          raise ConfigurationError, "deployment_id cannot be blank" if string_value.empty?

          string_value
        end
      end
    end
  end
end
