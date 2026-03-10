# frozen_string_literal: true

require "openssl"
require "base64"

module Lti
  module Advantage
    # Generates and publishes the tool's own RSA key material.
    #
    # This class is kept primarily for demo and future service-signing use
    # cases, such as exposing a tool JWKS document at +/lti/jwks+.
    class KeyPair
      # private_key:: Backing RSA private key.
      # kid:: Key identifier published in JWKS and JWT headers.
      attr_reader :private_key, :kid

      # private_key_pem:: Optional PEM-encoded RSA private key.
      # kid:: Key identifier to publish for the generated JWK.
      #
      # When +private_key_pem+ is omitted, a new 2048-bit RSA key is generated.
      def initialize(private_key_pem = nil, kid: "default-key-id")
        @private_key = if private_key_pem
                         OpenSSL::PKey::RSA.new(private_key_pem)
                       else
                         OpenSSL::PKey::RSA.generate(2048)
                       end
        @kid = kid
      end

      # Returns the public key as a JWK Hash for platform consumption.
      def public_jwk
        public_key = @private_key.public_key
        {
          kty: "RSA",
          n: Base64.urlsafe_encode64(public_key.n.to_s(2), padding: false),
          e: Base64.urlsafe_encode64(public_key.e.to_s(2), padding: false),
          kid: @kid,
          alg: "RS256",
          use: "sig"
        }
      end

      # Returns the private key as a PEM string.
      def to_pem
        @private_key.to_pem
      end
    end
  end
end
