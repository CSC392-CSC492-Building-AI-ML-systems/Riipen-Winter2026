# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    module OIDC
      # Serializable OpenID authentication request for LTI 1.3 launches.
      #
      # The generated URL includes OIDC required parameters and optional LTI
      # hints, ready to use in an HTTP redirect response.
      class AuthenticationRequest
        # Required parameter keys for request construction.
        REQUIRED_PARAMETERS = %w[client_id redirect_uri login_hint state nonce target_link_uri].freeze

        # Default OIDC parameter values required by LTI 1.3.
        DEFAULT_PARAMETERS = {
          "response_type" => "id_token",
          "response_mode" => "form_post",
          "scope" => "openid",
          "prompt" => "none"
        }.freeze

        attr_reader :authorization_endpoint, :state, :nonce

        # authorization_endpoint:: Platform OIDC auth endpoint URL.
        # client_id:: OAuth2 client id assigned by the platform.
        # redirect_uri:: Tool launch endpoint that receives +id_token+.
        # login_hint:: Opaque login hint from initiation request.
        # state:: One-time state token for CSRF/replay protection.
        # nonce:: One-time nonce token for id_token replay protection.
        # target_link_uri:: Tool URL expected in launch claim validation.
        # lti_message_hint:: Optional opaque LTI message hint.
        # lti_deployment_id:: Optional deployment hint.
        #
        # Raises {ValidationError} if required values are blank.
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

        # Returns the full request parameter hash as String keys.
        def parameters
          DEFAULT_PARAMETERS.merge(@params).compact
        end

        # Returns the final redirect URL to the authorization endpoint.
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
