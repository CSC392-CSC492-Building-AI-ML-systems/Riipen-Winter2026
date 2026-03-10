# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Lti
  module Advantage
    # Fetches and caches JSON Web Key Sets (JWKS) for platform key material.
    #
    # By default this class performs HTTPS GET requests with +Net::HTTP+ and
    # caches parsed responses in-process for a short TTL.
    class JwksRepository
      # Default cache TTL in seconds.
      DEFAULT_CACHE_TTL = 300

      # cache_ttl:: Cache lifetime in seconds for each JWKS URL.
      # clock:: Callable returning current time for TTL comparisons.
      # http_get:: Optional callable for HTTP fetches, used for testing.
      def initialize(cache_ttl: DEFAULT_CACHE_TTL, clock: -> { Time.now }, http_get: nil)
        @cache_ttl = cache_ttl
        @clock = clock
        @http_get = http_get || method(:default_http_get)
        @cache = {}
      end

      # Retrieves and parses the JWKS payload for +url+.
      #
      # Returns a Hash containing the parsed JSON object.
      # Raises {JwtVerificationError} when retrieval or parsing fails.
      def fetch(url)
        cached = @cache[url]
        return cached[:value] if cached && cached[:expires_at] > @clock.call

        value = @http_get.call(url)
        parsed = parse(value)
        @cache[url] = { value: parsed, expires_at: @clock.call + @cache_ttl }
        parsed
      end

      private

      def default_http_get(url)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)
        unless response.is_a?(Net::HTTPSuccess)
          raise JwtVerificationError, "Unable to fetch JWKS from #{url}: HTTP #{response.code}"
        end

        response.body
      end

      def parse(value)
        case value
        when String
          JSON.parse(value)
        when Hash
          value
        else
          raise JwtVerificationError, "Unsupported JWKS payload type: #{value.class}"
        end
      rescue JSON::ParserError => e
        raise JwtVerificationError, "Invalid JWKS JSON payload: #{e.message}"
      end
    end
  end
end
