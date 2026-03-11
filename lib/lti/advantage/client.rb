# frozen_string_literal: true

require "securerandom"

module Lti
  module Advantage
    # High-level tool-side API for the LTI 1.3 core launch lifecycle.
    #
    # Typical usage:
    #
    # 1. Configure one or more {Registration} instances
    # 2. Build a {Client}
    # 3. Call {#authentication_request} for login initiation callbacks
    # 4. Call {#validate_launch!} for launch callbacks containing +id_token+
    class Client
      # Default state TTL (seconds).
      DEFAULT_STATE_TTL = 300

      # Default nonce TTL (seconds).
      DEFAULT_NONCE_TTL = 300

      # Stores used for state and nonce replay-protection material.
      attr_reader :state_store, :nonce_store

      # registrations:: Enumerable collection of {Registration} objects.
      # state_store:: Store object supporting +write+, +read+, and +consume+.
      # nonce_store:: Store object supporting +write+, +read+, and +consume+.
      # jwks_repository:: Source used by {LaunchValidator} for platform JWKS.
      # state_generator:: Callable used to create one-time state values.
      # nonce_generator:: Callable used to create one-time nonce values.
      # state_ttl:: TTL (seconds) for stored state entries.
      # nonce_ttl:: TTL (seconds) for stored nonce entries.
      def initialize(
        registrations:, state_store: Store::MemoryStore.new, nonce_store: Store::MemoryStore.new,
        jwks_repository: JwksRepository.new,
        state_generator: -> { SecureRandom.urlsafe_base64(24) },
        nonce_generator: -> { SecureRandom.urlsafe_base64(24) },
        state_ttl: DEFAULT_STATE_TTL,
        nonce_ttl: DEFAULT_NONCE_TTL
      )
        @registration_store = RegistrationStore.new(registrations)
        @state_store = state_store
        @nonce_store = nonce_store
        @state_generator = state_generator
        @nonce_generator = nonce_generator
        @state_ttl = state_ttl
        @nonce_ttl = nonce_ttl
        @launch_validator = LaunchValidator.new(
          registration_store: @registration_store,
          state_store: @state_store,
          nonce_store: @nonce_store,
          jwks_repository: jwks_repository
        )
      end

      # Builds an OIDC authentication request URL from login initiation params.
      #
      # login_params:: Hash-like request params received at tool login endpoint.
      # redirect_uri:: Tool endpoint that receives form_post launch responses.
      #
      # Returns an {OIDC::AuthenticationRequest}.
      # Raises {ValidationError} when platform or deployment values are invalid.
      def authentication_request(login_params:, redirect_uri:)
        login = OIDC::LoginInitiation.new(login_params)
        registration = @registration_store.resolve!(issuer: login.issuer, client_id: login.client_id)

        if login.lti_deployment_id && !registration.supports_deployment?(login.lti_deployment_id)
          raise ValidationError,
                "Deployment #{login.lti_deployment_id} is not allowed for issuer #{login.issuer}"
        end

        state = @state_generator.call.to_s
        nonce = @nonce_generator.call.to_s

        @state_store.write(
          state,
          value: {
            issuer: login.issuer,
            client_id: registration.client_id,
            target_link_uri: login.target_link_uri,
            deployment_id: login.lti_deployment_id,
            nonce: nonce
          },
          ttl: @state_ttl
        )
        @nonce_store.write(nonce, value: true, ttl: @nonce_ttl)

        OIDC::AuthenticationRequest.new(
          authorization_endpoint: registration.authorization_endpoint,
          client_id: registration.client_id,
          redirect_uri: redirect_uri,
          login_hint: login.login_hint,
          state: state,
          nonce: nonce,
          target_link_uri: login.target_link_uri,
          lti_message_hint: login.lti_message_hint,
          lti_deployment_id: login.lti_deployment_id
        )
      end

      # Validates a posted +id_token+ and returns a parsed {Launch} object.
      #
      # id_token:: Signed JWT from platform launch callback.
      # state:: One-time state value from launch callback.
      def validate_launch!(id_token:, state:)
        @launch_validator.validate!(id_token: id_token, state: state)
      end

      def ags_service_client(launch:, key_pair:, clock: -> { Time.now }, http_request: nil)
        AGS::ServiceClient.new(
          launch: launch,
          key_pair: key_pair,
          clock: clock,
          http_request: http_request
        )
      end
    end
  end
end
