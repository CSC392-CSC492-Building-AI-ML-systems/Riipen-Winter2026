# frozen_string_literal: true

require "securerandom"

module Lti
  module Advantage
    class Client
      DEFAULT_STATE_TTL = 300
      DEFAULT_NONCE_TTL = 300

      attr_reader :state_store, :nonce_store

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

      def validate_launch!(id_token:, state:)
        @launch_validator.validate!(id_token: id_token, state: state)
      end
    end
  end
end
