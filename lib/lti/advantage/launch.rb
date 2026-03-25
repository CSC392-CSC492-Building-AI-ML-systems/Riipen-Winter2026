# frozen_string_literal: true

require "uri"

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

      NRPS_CLAIM = "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"
      SUPPORTED_NRPS_SERVICE_VERSIONS = ["2.0"].freeze

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

      def ags_endpoint
        claim = payload[Claims::AGS_ENDPOINT]
        return nil if claim.nil?

        AGS::Endpoint.new(claim)
      end

      # Convenience accessor for any arbitrary claim URI or key.
      def [](claim)
        payload[claim]
      end

      # Returns the raw Names and Role Provisioning Service claim hash,
      # or nil if the LMS did not include NRPS in the launch token.
      def nrps_claim
        claim = payload[NRPS_CLAIM]
        claim.is_a?(Hash) ? claim : nil
      end

      # Returns the context memberships URL to pass to NamesRoleService.
      # Returns nil if NRPS is not available for this launch.
      def context_memberships_url
        normalize_optional_http_url(nrps_claim&.fetch("context_memberships_url", nil))
      end

      # Returns the NRPS service versions supported by the LMS, e.g. ["2.0"].
      # Returns an empty array if the NRPS claim is absent.
      def nrps_service_versions
        versions = nrps_claim&.fetch("service_versions", nil)
        return [] unless versions.is_a?(Array)

        versions.filter_map do |version|
          next unless version.is_a?(String)

          normalize_optional_string(version)
        end
      end

      # Returns true when the launch advertises NRPS with a valid memberships
      # URL and at least one supported service version.
      #
      # This is intentionally a claim-level availability check only. It does
      # not verify that the selected registration has a token endpoint, that the
      # platform will issue a token, that the tool has the required scope, or
      # that later NRPS HTTP requests will succeed.
      def nrps_available?
        return false if context_memberships_url.nil?

        (nrps_service_versions & SUPPORTED_NRPS_SERVICE_VERSIONS).any?
      end

      private

      def normalize_optional_string(value)
        return nil if value.nil?

        string_value = value.to_s.strip
        return nil if string_value.empty?

        string_value
      end

      def normalize_optional_http_url(value)
        string_value = normalize_optional_string(value)
        return nil if string_value.nil?

        uri = URI.parse(string_value)
        return nil unless uri.is_a?(URI::HTTP) && !uri.host.nil?

        uri.to_s
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
