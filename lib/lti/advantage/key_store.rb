# frozen_string_literal: true

require "faraday"
require "json"

module Lti
  module Advantage
    # This class fetches and holds the "Public Keys" from the LMS.
    # Think of it like a public phonebook we use to verify signatures.
    class KeyStore
      def initialize(jwks_url, cache_ttl: 300, clock: -> { Time.now.to_i })
        @jwks_url = jwks_url
        @cache_ttl = cache_ttl
        @clock = clock
        @cached_keys = nil
        @cached_at = nil
      end

      # Fetches the keys from the LMS's URL.
      def keys(force_refresh: false)
        return @cached_keys if !force_refresh && cache_valid?

        fetch_keys!
      end

      def key_for_kid(kid)
        return nil if kid.nil?

        found = find_by_kid(keys, kid)
        return found unless found.nil?

        find_by_kid(keys(force_refresh: true), kid)
      end

      private

      def cache_valid?
        return false if @cached_keys.nil? || @cached_at.nil?

        (@clock.call - @cached_at) <= @cache_ttl
      end

      def fetch_keys!
        response = Faraday.get(@jwks_url)
        raise Error, "Failed to fetch keys from #{@jwks_url}" unless response.success?

        parsed = JSON.parse(response.body)
        keys = parsed["keys"]
        raise Error, "JWKS response missing keys array" unless keys.is_a?(Array)

        @cached_keys = keys
        @cached_at = @clock.call
        @cached_keys
      rescue JSON::ParserError => e
        raise Error, "KeyStore error: invalid JWKS JSON (#{e.message})"
      rescue StandardError => e
        raise Error, "KeyStore error: #{e.message}"
      end

      def find_by_kid(keys, kid)
        keys.find { |key| key["kid"] == kid || key[:kid] == kid }
      end
    end
  end
end
