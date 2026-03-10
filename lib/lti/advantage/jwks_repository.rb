# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Lti
  module Advantage
    class JwksRepository
      DEFAULT_CACHE_TTL = 300

      def initialize(cache_ttl: DEFAULT_CACHE_TTL, clock: -> { Time.now }, http_get: nil)
        @cache_ttl = cache_ttl
        @clock = clock
        @http_get = http_get || method(:default_http_get)
        @cache = {}
      end

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
