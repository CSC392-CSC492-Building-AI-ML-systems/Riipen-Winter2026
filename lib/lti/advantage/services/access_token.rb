# frozen_string_literal: true

require "jwt"
require "faraday"
require "securerandom"
require "json"

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
      #     scope:          Lti::Advantage::Services::NamesRoleService::SCOPE
      #   )
      #   bearer = token_service.fetch
      class AccessToken
        # @param key_pair [Lti::Advantage::KeyPair] the tool's RSA key pair
        # @param client_id [String] the tool's Client ID registered in the LMS
        # @param token_endpoint [String] the LMS OAuth2 token URL
        # @param scope [String] space-separated list of OAuth2 scopes to request
        def initialize(key_pair:, client_id:, token_endpoint:, scope:)
          @key_pair       = key_pair
          @client_id      = client_id
          @token_endpoint = token_endpoint
          @scope          = scope
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

          unless response.success?
            raise Error, "Token request failed (#{response.status}): #{response.body}"
          end

          parsed = JSON.parse(response.body)
          parsed["access_token"] or raise Error, "No access_token in response: #{response.body}"
        rescue Faraday::Error => e
          raise Error, "Network error fetching access token: #{e.message}"
        end

        private

        # Builds the POST body params for the client_credentials grant.
        # @return [Hash]
        def token_request_params
          {
            grant_type:            "client_credentials",
            client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            client_assertion:      build_client_assertion,
            scope:                 @scope
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

          JWT.encode(
            payload,
            @key_pair.private_key,
            "RS256",
            { kid: @key_pair.kid }
          )
        end
      end
    end
  end
end