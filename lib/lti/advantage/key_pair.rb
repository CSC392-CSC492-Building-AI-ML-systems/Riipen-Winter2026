# frozen_string_literal: true

require "openssl"
require "base64"

module Lti
  module Advantage
    # Manages the tool's own identity using RSA key pairs.
    class KeyPair
      attr_reader :private_key, :kid

      def initialize(private_key_pem = nil, kid: "default-key-id")
        @private_key = if private_key_pem
                         OpenSSL::PKey::RSA.new(private_key_pem)
                       else
                         OpenSSL::PKey::RSA.generate(2048)
                       end
        @kid = kid
      end

      # Returns the public key in JWK format for Platform (LMS) consumption.
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
