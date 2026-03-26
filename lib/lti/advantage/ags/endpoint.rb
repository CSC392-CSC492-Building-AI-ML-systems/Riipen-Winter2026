# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    module AGS
      class Endpoint
        SCORE_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/score"
        LINEITEM_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
        LINEITEM_READONLY_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
        RESULT_READONLY_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
        RESULT_SCOPE = RESULT_READONLY_SCOPE

        attr_reader :lineitems_url, :lineitem_url, :scopes

        def initialize(claim)
          endpoint_claim = claim.is_a?(Hash) ? claim : {}
          @lineitems_url = optional_string(endpoint_claim["lineitems"] || endpoint_claim[:lineitems])
          @lineitem_url = optional_string(endpoint_claim["lineitem"] || endpoint_claim[:lineitem])
          @scopes = Array(endpoint_claim["scope"] || endpoint_claim[:scope]).map(&:to_s).freeze
        end

        def available?
          !scopes.empty? && (!lineitems_url.nil? || !lineitem_url.nil?)
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
          append_member_suffix(base, "/scores")
        end

        def results_url(line_item_url: nil)
          require_scope!(RESULT_READONLY_SCOPE)

          base = resolve_line_item_url(line_item_url)
          append_member_suffix(base, "/results")
        end

        def line_item_url
          lineitem_url
        end

        def lineitems_url!(lineitems_url: nil, write: false)
          require_line_item_scope!(write: write)

          candidate = optional_string(lineitems_url) || @lineitems_url
          return candidate unless candidate.nil?

          raise ValidationError, "An AGS lineitems URL is required for line item collection operations"
        end

        def line_item_url!(line_item_url: nil, write: false)
          require_line_item_scope!(write: write)
          resolve_line_item_url(line_item_url, purpose: "line item operations")
        end

        private

        def require_line_item_scope!(write:)
          if write
            require_scope!(LINEITEM_SCOPE)
          elsif supports_scope?(LINEITEM_SCOPE) || supports_scope?(LINEITEM_READONLY_SCOPE)
            nil
          else
            raise AuthorizationError,
                  "AGS scope #{LINEITEM_SCOPE} or #{LINEITEM_READONLY_SCOPE} is not granted for this launch"
          end
        end

        def resolve_line_item_url(explicit_line_item_url, purpose: "score publishing")
          candidate = optional_string(explicit_line_item_url) || lineitem_url
          return candidate unless candidate.nil?

          raise ValidationError, "A concrete AGS lineitem URL is required for #{purpose}"
        end

        def append_member_suffix(base, suffix)
          uri = URI.parse(base)
          normalized_suffix = suffix.sub(%r{^/+}, "")
          current_segments = uri.path.split("/").reject(&:empty?)

          unless current_segments.last == normalized_suffix
            uri.path = "/#{(current_segments + [normalized_suffix]).join("/")}"
          end

          uri.query = nil if uri.query == ""
          uri.to_s
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
