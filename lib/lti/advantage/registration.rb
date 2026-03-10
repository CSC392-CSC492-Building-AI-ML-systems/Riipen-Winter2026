# frozen_string_literal: true

module Lti
  module Advantage
    class Registration
      attr_reader :issuer, :client_id, :authorization_endpoint, :jwks_url, :deployment_ids, :algorithms

      def initialize(issuer:, client_id:, authorization_endpoint:, jwks_url:, deployment_ids: [], algorithms: ["RS256"])
        @issuer = assert_presence("issuer", issuer)
        @client_id = assert_presence("client_id", client_id)
        @authorization_endpoint = assert_presence("authorization_endpoint", authorization_endpoint)
        @jwks_url = assert_presence("jwks_url", jwks_url)
        @deployment_ids = Array(deployment_ids).map(&:to_s).freeze
        @algorithms = Array(algorithms).map(&:to_s).freeze
      end

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
    end
  end
end
