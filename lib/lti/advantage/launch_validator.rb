# frozen_string_literal: true

require "jwt"

module Lti
  module Advantage
    # Validates signed +id_token+ launches for LTI 1.3 resource links.
    #
    # Validation responsibilities include:
    #
    # - JWT signature verification using the platform JWKS
    # - OIDC issuer, audience, +iat+, and +exp+ checks
    # - Required LTI claim presence and shape checks
    # - Deployment, target link, and nonce/state binding checks
    # - Replay protection by consuming one-time +state+ and +nonce+
    class LaunchValidator
      # Required LTI claim URIs for resource-link launches.
      REQUIRED_CLAIMS = [
        Claims::MESSAGE_TYPE,
        Claims::VERSION,
        Claims::DEPLOYMENT_ID,
        Claims::TARGET_LINK_URI,
        Claims::RESOURCE_LINK,
        Claims::ROLES
      ].freeze

      # registration_store:: Resolver for platform registrations.
      # state_store:: One-time store used for state validation.
      # nonce_store:: One-time store used for nonce replay protection.
      # jwks_repository:: Source for platform JWKS documents.
      # allowed_message_types:: Allowed LTI message type values.
      # leeway:: Clock skew leeway (seconds) for JWT timestamp checks.
      def initialize(
        registration_store:, state_store:, nonce_store:, jwks_repository: JwksRepository.new,
        allowed_message_types: ["LtiResourceLinkRequest"], leeway: 5
      )
        @registration_store = registration_store
        @state_store = state_store
        @nonce_store = nonce_store
        @jwks_repository = jwks_repository
        @allowed_message_types = allowed_message_types
        @leeway = leeway
      end

      # Validates an LTI launch token and returns a {Launch} object.
      #
      # id_token:: Signed JWT posted by the platform in the launch request.
      # state:: One-time state value previously issued in auth request.
      #
      # Raises {ValidationError}, {ReplayError}, or {JwtVerificationError} when
      # validation fails.
      def validate!(id_token:, state:)
        state_token = state.to_s
        state_data = @state_store.read(state_token)
        raise ReplayError, "Invalid, expired, or replayed state" if state_data.nil?

        unverified_payload, = JWT.decode(id_token, nil, false)
        issuer = unverified_payload["iss"].to_s

        registration = @registration_store.resolve!(
          issuer: state_data.fetch(:issuer),
          client_id: state_data.fetch(:client_id)
        )

        if registration.issuer != issuer
          raise ValidationError,
                "Token issuer mismatch. Expected #{registration.issuer}, got #{issuer}"
        end

        payload, header = JWT.decode(
          id_token,
          nil,
          true,
          decode_options(registration)
        ) do |jwt_header|
          resolve_verification_key(jwt_header, registration)
        end

        validate_lti_claims!(payload, state_data, registration)
        consume_state!(state_token)
        consume_nonce!(payload["nonce"])

        Launch.new(payload: payload, header: header, registration: registration)
      rescue JWT::DecodeError => e
        raise JwtVerificationError, e.message
      end

      private

      # Builds JWT.decode options derived from registration policy.
      def decode_options(registration)
        {
          algorithms: registration.algorithms,
          verify_iss: true,
          iss: registration.issuer,
          verify_aud: true,
          aud: registration.client_id,
          verify_iat: true,
          verify_expiration: true,
          leeway: @leeway
        }
      end

      # Resolves the OpenSSL public key from JWKS using header +kid+.
      def resolve_verification_key(jwt_header, registration)
        kid = jwt_header["kid"]
        jwk_set = as_jwk_set(@jwks_repository.fetch(registration.jwks_url))

        key = if kid
                jwk_set.find { |candidate| candidate[:kid] == kid }
              else
                jwk_set.first
              end

        raise JwtVerificationError, "Unable to find key with kid #{kid} for issuer #{registration.issuer}" unless key

        key.public_key
      end

      # Normalizes supported JWKS representations into JWT::JWK::Set.
      def as_jwk_set(jwks)
        case jwks
        when JWT::JWK::Set
          jwks
        when Hash
          JWT::JWK::Set.new(jwks)
        when Array
          JWT::JWK::Set.new(jwks)
        else
          raise JwtVerificationError, "Unsupported JWKS structure: #{jwks.class}"
        end
      end

      # Enforces required LTI claims and request-bound consistency checks.
      def validate_lti_claims!(payload, state_data, registration)
        missing_claims = REQUIRED_CLAIMS.reject { |claim| payload.key?(claim) }
        unless missing_claims.empty?
          raise ValidationError,
                "Missing required LTI claims: #{missing_claims.join(", ")}"
        end

        unless @allowed_message_types.include?(payload[Claims::MESSAGE_TYPE])
          raise ValidationError,
                "Unsupported LTI message_type: #{payload[Claims::MESSAGE_TYPE]}"
        end

        validate_non_empty_string_claim!(payload, Claims::MESSAGE_TYPE)
        validate_non_empty_string_claim!(payload, Claims::VERSION)
        validate_non_empty_string_claim!(payload, Claims::DEPLOYMENT_ID)
        validate_non_empty_string_claim!(payload, Claims::TARGET_LINK_URI)

        if payload[Claims::VERSION] != "1.3.0"
          raise ValidationError,
                "Unsupported LTI version: #{payload[Claims::VERSION]}"
        end

        target_link_uri = payload[Claims::TARGET_LINK_URI]
        expected_target_link_uri = state_data[:target_link_uri]
        if expected_target_link_uri && target_link_uri != expected_target_link_uri
          raise ValidationError,
                "Target link URI mismatch. Expected #{expected_target_link_uri}, got #{target_link_uri}"
        end

        deployment_id = payload[Claims::DEPLOYMENT_ID]
        expected_deployment_id = state_data[:deployment_id]
        if expected_deployment_id && deployment_id != expected_deployment_id
          raise ValidationError,
                "Deployment mismatch. Expected #{expected_deployment_id}, got #{deployment_id}"
        end

        unless registration.supports_deployment?(deployment_id)
          raise ValidationError,
                "Deployment #{deployment_id} is not allowed for issuer #{registration.issuer}"
        end

        roles = payload[Claims::ROLES]
        raise ValidationError, "roles claim must be an array" unless roles.is_a?(Array)

        resource_link = payload[Claims::RESOURCE_LINK]
        unless resource_link.is_a?(Hash) && resource_link["id"].to_s != ""
          raise ValidationError, "resource_link.id is required"
        end

        validate_audience_authorized_party!(payload, registration)
        validate_nonce_binding!(payload, state_data)
      end

      # Verifies that a claim exists and is a non-empty String value.
      def validate_non_empty_string_claim!(payload, claim)
        value = payload[claim]
        return unless value.to_s.empty?

        raise ValidationError,
              "#{claim.split("/").last} claim must be a non-empty string"
      end

      # Validates +aud+ and +azp+ relationship according to OIDC rules.
      def validate_audience_authorized_party!(payload, registration)
        audience = payload["aud"]
        audience = [audience] if audience.is_a?(String)
        audience ||= []

        if audience.size > 1 && !payload.key?("azp")
          raise ValidationError, "azp claim is required when aud contains multiple values"
        end

        return unless payload.key?("azp") && payload["azp"] != registration.client_id

        raise ValidationError,
              "azp claim mismatch. Expected #{registration.client_id}, got #{payload["azp"]}"
      end

      # Ensures launch nonce matches the nonce bound to this state value.
      def validate_nonce_binding!(payload, state_data)
        expected_nonce = state_data[:nonce]
        return if expected_nonce.nil?
        return if payload["nonce"] == expected_nonce

        raise ValidationError, "nonce does not match the provided state"
      end

      # Consumes state after successful token and claim validation.
      def consume_state!(state)
        consumed = @state_store.consume(state)
        raise ReplayError, "Invalid, expired, or replayed state" if consumed.nil?
      end

      # Consumes nonce to enforce single-use launch tokens.
      def consume_nonce!(nonce)
        raise ValidationError, "nonce claim is required" if nonce.to_s.empty?

        consumed = @nonce_store.consume(nonce.to_s)
        raise ReplayError, "Invalid, expired, or replayed nonce" if consumed.nil?
      end
    end
  end
end
