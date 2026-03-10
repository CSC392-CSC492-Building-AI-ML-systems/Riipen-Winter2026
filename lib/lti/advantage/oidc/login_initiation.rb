# frozen_string_literal: true

module Lti
  module Advantage
    module OIDC
      # Validates and normalizes OIDC third-party login initiation parameters.
      #
      # Required keys follow the LTI 1.3 core login initiation flow:
      #
      # - +iss+
      # - +login_hint+
      # - +target_link_uri+
      class LoginInitiation
        # Required login initiation parameter keys.
        REQUIRED_KEYS = %w[iss login_hint target_link_uri].freeze

        # Attribute readers:
        #
        # issuer:: Platform issuer from +iss+.
        # login_hint:: Opaque login hint returned to the platform auth endpoint.
        # target_link_uri:: Tool launch URL used for final redirection.
        # lti_message_hint:: Optional opaque LTI message hint.
        # lti_deployment_id:: Optional deployment identifier hint.
        # client_id:: Optional client id used to disambiguate registrations.
        attr_reader :issuer, :login_hint, :target_link_uri, :lti_message_hint, :lti_deployment_id, :client_id

        # params:: Hash-like object containing login initiation params.
        #
        # Raises {ValidationError} when required keys are missing or blank.
        def initialize(params)
          @params = normalize(params)
          assert_required_keys!

          @issuer = @params.fetch("iss")
          @login_hint = @params.fetch("login_hint")
          @target_link_uri = @params.fetch("target_link_uri")
          @lti_message_hint = @params["lti_message_hint"]
          @lti_deployment_id = @params["lti_deployment_id"]
          @client_id = @params["client_id"]
        end

        private

        def normalize(params)
          params.to_h.each_with_object({}) do |(key, value), result|
            next if value.nil?

            result[key.to_s] = value.to_s
          end
        end

        def assert_required_keys!
          missing = REQUIRED_KEYS.reject do |key|
            value = @params[key]
            !value.nil? && !value.empty?
          end

          return if missing.empty?

          raise ValidationError, "Missing required login initiation params: #{missing.join(", ")}"
        end
      end
    end
  end
end
