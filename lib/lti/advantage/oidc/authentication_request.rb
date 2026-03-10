# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    module OIDC
      class AuthenticationRequest
        REQUIRED_PARAMETERS = %w[client_id redirect_uri login_hint state nonce target_link_uri].freeze

        DEFAULT_PARAMETERS = {
          "response_type" => "id_token",
          "response_mode" => "form_post",
          "scope" => "openid",
          "prompt" => "none"
        }.freeze

        attr_reader :authorization_endpoint, :state, :nonce

        def initialize(
          authorization_endpoint:, client_id:, redirect_uri:, login_hint:,
          state:, nonce:, target_link_uri:, lti_message_hint: nil, lti_deployment_id: nil
        )
          @authorization_endpoint = authorization_endpoint.to_s
          @params = {
            "client_id" => client_id.to_s,
            "redirect_uri" => redirect_uri.to_s,
            "login_hint" => login_hint.to_s,
            "state" => state.to_s,
            "nonce" => nonce.to_s,
            "target_link_uri" => target_link_uri.to_s,
            "lti_message_hint" => to_optional_string(lti_message_hint),
            "lti_deployment_id" => to_optional_string(lti_deployment_id)
          }

          @state = @params.fetch("state")
          @nonce = @params.fetch("nonce")

          assert_required_params!
        end

        def parameters
          DEFAULT_PARAMETERS.merge(@params).compact
        end

        def url
          uri = URI.parse(authorization_endpoint)
          existing_params = uri.query.nil? ? {} : URI.decode_www_form(uri.query).to_h
          uri.query = URI.encode_www_form(existing_params.merge(parameters))
          uri.to_s
        end

        private

        def assert_required_params!
          missing = REQUIRED_PARAMETERS.select do |name|
            value = @params[name]
            value.nil? || value.empty?
          end

          return if missing.empty?

          raise ValidationError, "Missing required authentication request params: #{missing.join(", ")}"
        end

        def to_optional_string(value)
          return nil if value.nil?

          value.to_s
        end
      end
    end
  end
end
