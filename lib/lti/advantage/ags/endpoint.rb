# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    # Namespace for Assignment and Grade Services (AGS) helpers.
    module AGS
      # Wrapper for the AGS endpoint claim embedded in a validated launch.
      #
      # The claim advertises which AGS URLs are available and which scopes were
      # granted for the current launch.
      class Endpoint
        # Scope URI required for AGS score publishing.
        SCORE_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/score"

        # Scope URI required for writable AGS line item operations.
        LINEITEM_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"

        # Scope URI required for read-only AGS line item operations.
        LINEITEM_READONLY_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"

        # Scope URI required for AGS result reads.
        RESULT_READONLY_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"

        # Backwards-compatible alias for {RESULT_READONLY_SCOPE}.
        RESULT_SCOPE = RESULT_READONLY_SCOPE

        # Collection URL for line item list and create operations.
        attr_reader :lineitems_url

        # Member URL for a single concrete line item.
        attr_reader :lineitem_url

        # Array of AGS scope URIs granted for the current launch.
        attr_reader :scopes

        # claim:: Raw AGS endpoint claim Hash from the launch token.
        def initialize(claim)
          endpoint_claim = claim.is_a?(Hash) ? claim : {}
          @lineitems_url = optional_string(endpoint_claim["lineitems"] || endpoint_claim[:lineitems])
          @lineitem_url = optional_string(endpoint_claim["lineitem"] || endpoint_claim[:lineitem])
          @scopes = Array(endpoint_claim["scope"] || endpoint_claim[:scope]).map(&:to_s).freeze
        end

        # Returns +true+ when the claim grants scopes and at least one usable AGS
        # URL.
        def available?
          !scopes.empty? && (!lineitems_url.nil? || !lineitem_url.nil?)
        end

        # Returns +true+ when the launch granted +scope+.
        def supports_scope?(scope)
          scopes.include?(scope.to_s)
        end

        # Raises {AuthorizationError} unless +scope+ was granted for this launch.
        def require_scope!(scope)
          return if supports_scope?(scope)

          raise AuthorizationError, "AGS scope #{scope} is not granted for this launch"
        end

        # Returns the score publish URL for a concrete line item.
        #
        # line_item_url:: Optional explicit member URL. Falls back to the launch
        #                 claim's +lineitem+ value.
        def score_url(line_item_url: nil)
          require_scope!(SCORE_SCOPE)

          base = resolve_line_item_url(line_item_url)
          append_member_suffix(base, "/scores")
        end

        # Returns the result collection URL for a concrete line item.
        #
        # line_item_url:: Optional explicit member URL. Falls back to the launch
        #                 claim's +lineitem+ value.
        def results_url(line_item_url: nil)
          require_scope!(RESULT_READONLY_SCOPE)

          base = resolve_line_item_url(line_item_url)
          append_member_suffix(base, "/results")
        end

        # Returns the concrete line item member URL advertised by the claim.
        def line_item_url
          lineitem_url
        end

        # Returns the AGS line item collection URL.
        #
        # lineitems_url:: Optional explicit collection URL override.
        # write:: When +true+, require the writable line item scope.
        def lineitems_url!(lineitems_url: nil, write: false)
          require_line_item_scope!(write: write)

          candidate = optional_string(lineitems_url) || @lineitems_url
          return candidate unless candidate.nil?

          raise ValidationError, "An AGS lineitems URL is required for line item collection operations"
        end

        # Returns the AGS line item member URL.
        #
        # line_item_url:: Optional explicit member URL override.
        # write:: When +true+, require the writable line item scope.
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

    # Backwards-compatible alias for {AGS}.
    Ags = AGS
  end
end
