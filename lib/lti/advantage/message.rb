# frozen_string_literal: true

require "jwt"

module Lti
  module Advantage
    # This class handles the "ID Token" (the digital badge) sent by the LMS.
    class Message
      MESSAGE_TYPE_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/message_type"
      VERSION_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/version"
      DEPLOYMENT_ID_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/deployment_id"
      TARGET_LINK_URI_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/target_link_uri"
      RESOURCE_LINK_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/resource_link"

      attr_reader :jwt_token, :jwt_body, :jwt_header

      def initialize(jwt_token)
        @jwt_token = jwt_token
        decoded = JWT.decode(jwt_token, nil, false)
        @jwt_body = decoded.first
        @jwt_header = decoded[1]
      end

      # Verifies the digital signature of the token.
      def verify!(keys: nil, key_store: nil, client_id:, issuer:)
        selected_keys = resolve_keys(keys: keys, key_store: key_store)
        raise Error, "No verification keys available for token" if selected_keys.empty?

        JWT.decode(
          jwt_token,
          nil,
          true,
          {
            algorithm: "RS256",
            jwks: { keys: selected_keys },
            iss: issuer,
            verify_iss: true,
            aud: client_id,
            verify_aud: true,
            verify_expiration: true,
            verify_iat: true,
            verify_not_before: true
          }
        )
      rescue JWT::DecodeError => e
        raise Error, "Token verification failed: #{e.message}"
      end

      # Checks if this is a standard LTI Resource Link Launch.
      def resource_launch?
        jwt_body[MESSAGE_TYPE_CLAIM] == "LtiResourceLinkRequest"
      end

      def nonce
        jwt_body["nonce"]
      end

      def target_link_uri
        jwt_body[TARGET_LINK_URI_CLAIM]
      end

      def version
        jwt_body[VERSION_CLAIM]
      end

      def resource_link_id
        resource_link = jwt_body[RESOURCE_LINK_CLAIM]
        return nil unless resource_link.is_a?(Hash)

        resource_link["id"] || resource_link[:id]
      end

      def key_id
        jwt_header["kid"] || jwt_header[:kid]
      end

      def validate_resource_link_launch!(expected_deployment_id:, expected_target_link_uri:, allow_anonymous: false)
        raise Error, "Invalid launch: message_type must be LtiResourceLinkRequest" unless resource_launch?
        raise Error, "Invalid launch: version must be 1.3.0" unless version == "1.3.0"

        if deployment_id.to_s.empty?
          raise Error, "Invalid launch: deployment_id claim is required"
        end

        if deployment_id != expected_deployment_id
          raise Error, "Invalid launch: deployment_id mismatch"
        end

        if target_link_uri.to_s.empty?
          raise Error, "Invalid launch: target_link_uri claim is required"
        end

        if target_link_uri != expected_target_link_uri
          raise Error, "Invalid launch: target_link_uri mismatch"
        end

        if resource_link_id.to_s.empty?
          raise Error, "Invalid launch: resource_link.id claim is required"
        end

        if !allow_anonymous && user_id.to_s.empty?
          raise Error, "Invalid launch: sub claim is required"
        end
      end

      def validate_nonce!(expected_nonce:)
        if expected_nonce.to_s.empty?
          raise Error, "Invalid launch: expected nonce is missing"
        end

        if nonce.to_s.empty?
          raise Error, "Invalid launch: nonce claim is required"
        end

        raise Error, "Invalid launch: nonce mismatch" unless nonce == expected_nonce
      end

      def user_id
        jwt_body["sub"]
      end

      # Identifies the tool (your app)
      def client_id
        jwt_body["aud"]
      end

      # Identifies the specific installation/deployment instance
      def deployment_id
        jwt_body[DEPLOYMENT_ID_CLAIM]
      end

      private

      def resolve_keys(keys:, key_store:)
        if key_store
          kid = key_id
          raise Error, "Token verification failed: missing kid header" if kid.to_s.empty?

          key = key_store.key_for_kid(kid)
          raise Error, "Token verification failed: no JWKS key found for kid #{kid}" if key.nil?

          return [key]
        end

        keys || []
      end
    end
  end
end
