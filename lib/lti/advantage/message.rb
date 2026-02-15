# frozen_string_literal: true

require "jwt"

module Lti
  module Advantage
    # This class handles the "ID Token" (the digital badge) sent by the LMS.
    class Message
      attr_reader :jwt_token, :jwt_body

      def initialize(jwt_token)
        @jwt_token = jwt_token
        # Decode without verification first to get the headers/body
        @jwt_body = JWT.decode(jwt_token, nil, false).first
      end

      # Verifies the digital signature of the token.
      # @param keys [Array] The public keys fetched from the LMS
      # @param client_id [String] Your tool's ID
      # @param issuer [String] The LMS's unique ID (e.g., https://canvas.instructure.com)
      def verify!(keys:, client_id:, issuer:)
        # This is the "magic" line that check if the badge is real.
        JWT.decode(
          jwt_token,
          nil,
          true,
          {
            algorithm: "RS256",
            jwks: { keys: keys },
            iss: issuer,
            verify_iss: true,
            aud: client_id,
            verify_aud: true
          }
        )
      rescue JWT::DecodeError => e
        raise Error, "Token verification failed: #{e.message}"
      end

      # Returns the URL for sending grades via AGS.
      def ags_line_item_url
        jwt_body.dig("https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", "lineitem")
      end

      # Checks if this is a standard LTI Resource Link Launch.
      def resource_launch?
        jwt_body["https://purl.imsglobal.org/spec/lti/claim/message_type"] == "LtiResourceLinkRequest"
      end

      def user_id
        jwt_body["sub"]
      end
    end
  end
end
