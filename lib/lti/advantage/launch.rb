# frozen_string_literal: true

module Lti
  module Advantage
    # Read-only view over a validated LTI launch token.
    #
    # The object exposes convenience readers for common LTI claims while still
    # preserving access to raw payload/header data.
    class Launch
      # payload:: JWT payload hash after successful validation.
      # header:: JWT header hash after successful validation.
      # registration:: {Registration} selected for this launch.
      attr_reader :payload, :header, :registration

      def initialize(payload:, header:, registration:)
        @payload = payload
        @header = header
        @registration = registration
      end

      # Returns the LTI message type claim value.
      def message_type
        payload[Claims::MESSAGE_TYPE]
      end

      # Returns the LTI version claim value.
      def version
        payload[Claims::VERSION]
      end

      # Returns the deployment id claim value.
      def deployment_id
        payload[Claims::DEPLOYMENT_ID]
      end

      # Returns the target link URI claim value.
      def target_link_uri
        payload[Claims::TARGET_LINK_URI]
      end

      # Returns an Array of role URIs.
      def roles
        payload.fetch(Claims::ROLES, [])
      end

      # Returns the subject (+sub+) claim, or +nil+ for anonymous launches.
      def subject
        payload["sub"]
      end

      # Returns the resource_link claim Hash.
      def resource_link
        payload.fetch(Claims::RESOURCE_LINK, {})
      end

      # Returns +resource_link.id+.
      def resource_link_id
        resource_link["id"]
      end

      # Convenience accessor for any arbitrary claim URI or key.
      def [](claim)
        payload[claim]
      end
    end
  end
end
