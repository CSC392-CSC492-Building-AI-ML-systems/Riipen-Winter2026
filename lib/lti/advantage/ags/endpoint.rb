# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    module AGS
      class Endpoint
        SCORE_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/score"
        LINEITEM_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
        RESULT_READONLY_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"

        attr_reader :lineitems_url, :lineitem_url, :scopes

        def initialize(claim)
          endpoint_claim = claim.is_a?(Hash) ? claim : {}
          @lineitems_url = optional_string(endpoint_claim["lineitems"] || endpoint_claim[:lineitems])
          @lineitem_url = optional_string(endpoint_claim["lineitem"] || endpoint_claim[:lineitem])
          @scopes = Array(endpoint_claim["scope"] || endpoint_claim[:scope]).map(&:to_s).freeze
        end

        def available?
          !lineitems_url.nil? || !lineitem_url.nil? || !scopes.empty?
        end

        def supports_scope?(scope)
          scopes.include?(scope.to_s)
        end

        def require_scope!(scope)
          return if supports_scope?(scope)

          raise AuthorizationError, "AGS scope #{scope} is not granted for this launch"
        end

        def score_url(line_item_url: nil)
          require_scope!(SCORE_SCOPE)

          base = resolve_line_item_url(line_item_url)
          uri = URI.parse(base)
          uri.path = "#{uri.path.sub(%r{/$}, "")}/scores"
          uri.query = nil if uri.query == ""
          uri.to_s
        end

        def results_url(line_item_url: nil, user_id: nil, limit: nil)
          require_scope!(RESULT_READONLY_SCOPE)

          base = resolve_line_item_url(line_item_url)
          uri = URI.parse(base)
          uri.path = "#{uri.path.sub(%r{/$}, "")}/results"
          query = []
          query << ["user_id", user_id] if user_id.to_s.strip != ""
          query << ["limit", limit] if limit.is_a?(Integer) && limit.positive?
          uri.query = query.empty? ? nil : URI.encode_www_form(query)
          uri.to_s
        end

        private

        def resolve_line_item_url(explicit_line_item_url)
          candidate = optional_string(explicit_line_item_url) || lineitem_url
          return candidate unless candidate.nil?

          raise ValidationError, "A concrete AGS lineitem URL is required for score publishing"
        end

        def optional_string(value)
          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end
      end
    end

    Ags = AGS
  end
end
