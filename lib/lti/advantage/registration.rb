# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    # Immutable registration details for one LTI platform integration.
    #
    # A registration models the security contract established between a tool and
    # a platform (issuer, OAuth2 client id, authorization endpoint, JWKS
    # endpoint, and optional service token endpoint). A single registration may
    # allow one or many deployment ids.
    class Registration
      # OIDC issuer identifier used for +iss+ claim verification.
      attr_reader :issuer, :client_id, :authorization_endpoint, :token_endpoint,
                  :token_audience, :jwks_url, :deployment_ids, :algorithms

      # Builds a platform registration.
      #
      # issuer:: Platform issuer URL from OIDC/LTI configuration.
      # client_id:: OAuth2 client id assigned to the tool.
      # authorization_endpoint:: Platform OIDC auth endpoint.
      # jwks_url:: Platform JWKS URL used to verify launch signatures.
      # token_endpoint:: Platform OAuth2 token endpoint used for LTI services.
      # deployment_ids:: Allowed deployment ids for this registration. If empty,
      #                  any non-empty deployment id is accepted.
      # algorithms:: Accepted JWT signature algorithms. Defaults to +RS256+.
      def initialize(
        issuer:, client_id:, authorization_endpoint:, jwks_url:, token_endpoint: nil,
        token_audience: nil, deployment_ids: [], algorithms: ["RS256"]
      )
        @issuer = assert_presence("issuer", issuer)
        @client_id = assert_presence("client_id", client_id)
        @authorization_endpoint = assert_presence("authorization_endpoint", authorization_endpoint)
        @jwks_url = assert_presence("jwks_url", jwks_url)
        @token_endpoint = normalize_optional_http_url("token_endpoint", token_endpoint)
        @token_audience = optional_string(token_audience)
        @deployment_ids = Array(deployment_ids).map(&:to_s).freeze
        @algorithms = Array(algorithms).map(&:to_s).freeze
      end

      # Returns +true+ when +deployment_id+ is allowed by this registration.
      #
      # An empty +deployment_ids+ list means the registration does not constrain
      # deployment ids, but the provided +deployment_id+ must still be non-empty.
      def supports_deployment?(deployment_id)
        return false if deployment_id.nil? || deployment_id.empty?
        return true if deployment_ids.empty?

        deployment_ids.include?(deployment_id.to_s)
      end

      private

      def assert_presence(name, value)
        string_value = value.to_s.strip
        raise ArgumentError, "#{name} is required" if string_value.empty?

        string_value
      end

      def normalize_optional_string(name, value)
        return nil if value.nil?

        string_value = value.to_s.strip
        raise ArgumentError, "#{name} cannot be blank" if string_value.empty?

        string_value
      end

      def normalize_optional_http_url(name, value)
        string_value = normalize_optional_string(name, value)
        return nil if string_value.nil?

        uri = URI.parse(string_value)
        raise ArgumentError, "#{name} must be an absolute HTTP(S) URL" unless uri.is_a?(URI::HTTP) && !uri.host.nil?

        uri.to_s
      rescue URI::InvalidURIError => e
        raise ArgumentError, "Invalid #{name}: #{e.message}"

      def optional_string(value)
        stripped = value.to_s.strip
        return nil if stripped.empty?

        stripped
      end
    end
  end
end
