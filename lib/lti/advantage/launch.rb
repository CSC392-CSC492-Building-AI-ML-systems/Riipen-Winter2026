# frozen_string_literal: true

module Lti
  module Advantage
    class Launch
      attr_reader :payload, :header, :registration

      def initialize(payload:, header:, registration:)
        @payload = payload
        @header = header
        @registration = registration
      end

      def message_type
        payload[Claims::MESSAGE_TYPE]
      end

      def version
        payload[Claims::VERSION]
      end

      def deployment_id
        payload[Claims::DEPLOYMENT_ID]
      end

      def target_link_uri
        payload[Claims::TARGET_LINK_URI]
      end

      def roles
        payload.fetch(Claims::ROLES, [])
      end

      def subject
        payload["sub"]
      end

      def resource_link
        payload.fetch(Claims::RESOURCE_LINK, {})
      end

      def resource_link_id
        resource_link["id"]
      end

      def [](claim)
        payload[claim]
      end
    end
  end
end
