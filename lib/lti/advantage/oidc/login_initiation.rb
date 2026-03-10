# frozen_string_literal: true

module Lti
  module Advantage
    module OIDC
      class LoginInitiation
        REQUIRED_KEYS = %w[iss login_hint target_link_uri].freeze

        attr_reader :issuer, :login_hint, :target_link_uri, :lti_message_hint, :lti_deployment_id, :client_id

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
