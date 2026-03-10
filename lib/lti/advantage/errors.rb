# frozen_string_literal: true

module Lti
  module Advantage
    # Base error for all gem-specific exceptions.
    class Error < StandardError; end

    # Raised when static configuration or dependency wiring is invalid.
    class ConfigurationError < Error; end

    # Raised when incoming login or launch data fails validation.
    class ValidationError < Error; end

    # Raised when a one-time state or nonce value is missing, expired, or reused.
    class ReplayError < Error; end

    # Raised when JWT decoding, JWKS retrieval, or signature verification fails.
    class JwtVerificationError < Error; end
  end
end
