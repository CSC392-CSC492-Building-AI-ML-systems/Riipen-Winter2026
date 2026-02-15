# frozen_string_literal: true

require "faraday"
require "json"

module Lti
  module Advantage
    # This class fetches and holds the "Public Keys" from the LMS.
    # Think of it like a public phonebook we use to verify signatures.
    class KeyStore
      def initialize(jwks_url)
        @jwks_url = jwks_url
      end

      # Fetches the keys from the LMS's URL.
      def keys
        response = Faraday.get(@jwks_url)
        raise Error, "Failed to fetch keys from #{@jwks_url}" unless response.success?

        JSON.parse(response.body)["keys"]
      rescue StandardError => e
        raise Error, "KeyStore error: #{e.message}"
      end
    end
  end
end
