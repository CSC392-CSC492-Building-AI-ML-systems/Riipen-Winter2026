# frozen_string_literal: true

require "jwt"
require "faraday"
require "securerandom"

module Lti
  module Advantage
    module Services
      # Base class for LTI Advantage services (AGS, NRPS).
      # Handles the OAuth2 Client Credentials grant.
      class Base
        def initialize(access_token_url:, client_id:, key_pair:)
          @access_token_url = access_token_url
          @client_id = client_id
          @key_pair = key_pair
        end

        # Fetches a temporary access token from Canvas.
        def access_token(scopes)
          payload = {
            iss: @client_id,
            sub: @client_id,
            aud: @access_token_url,
            iat: Time.now.to_i,
            exp: Time.now.to_i + 60,
            jti: SecureRandom.hex(16)
          }

          # Sign the request with our private key
          token = JWT.encode(payload, @key_pair.private_key, "RS256", { kid: @key_pair.kid })

          response = Faraday.post(@access_token_url) do |req|
            req.body = {
              grant_type: "client_credentials",
              client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
              client_assertion: token,
              scope: scopes.join(" ")
            }
          end

          JSON.parse(response.body)["access_token"]
        end
      end
    end
  end
end
