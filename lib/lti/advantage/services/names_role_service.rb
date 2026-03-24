# frozen_string_literal: true

require "faraday"
require "json"
require "uri"

module Lti
  module Advantage
    module Services
      # Client for the LTI 1.3 Names and Role Provisioning Service (NRPS v2).
      #
      # Fetches course rosters from the LMS using the endpoint advertised in the
      # +namesroleservice+ claim of the LTI launch token.
      #
      # @example Fetch all members
      #   service = Lti::Advantage::Services::NamesRoleService.new(
      #     memberships_url: launch.context_memberships_url,
      #     access_token:    bearer_token
      #   )
      #   result = service.memberships
      #   result.members.each { |m| puts "#{m.user_id} – #{m.roles}" }
      #
      # @example Fetch only learners
      #   result = service.memberships(role: "Learner")
      #
      # @example Paginate manually
      #   result = service.memberships(limit: 50)
      #   while result.next_page_url
      #     result = service.memberships_from_url(result.next_page_url)
      #   end
      #
      # @example Resource-link scope
      #   result = service.memberships(resource_link_id: "49566-rkk96")
      class NamesRoleService
        # OAuth2 scope required for all NRPS requests
        SCOPE = "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

        # NRPS media type sent in the Accept header
        MEDIA_TYPE = "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

        # Simple value object returned by every #memberships call.
        class MembershipsResult
          attr_reader :context, :members, :next_page_url, :differences_url

          def initialize(context:, members:, next_page_url:, differences_url:)
            @context = context
            @members = members
            @next_page_url = next_page_url
            @differences_url = differences_url
          end
        end

        # @param memberships_url [String] the +context_memberships_url+ from the
        #   NRPS launch claim
        # @param access_token [String] a valid bearer token with the NRPS scope
        def initialize(memberships_url:, access_token:)
          @memberships_url = memberships_url
          @access_token    = access_token
        end

        # Fetches memberships from the service.
        #
        # @param role [String, nil] optional role URI or short name to filter by
        #   (e.g. "Learner" or the full URI)
        # @param limit [Integer, nil] hint to the LMS about page size; the LMS
        #   may return more or fewer members than requested
        # @param resource_link_id [String, nil] when supplied, appends +rlid+
        #   to scope the request to a specific Resource Link
        # @return [MembershipsResult]
        # @raise [Lti::Advantage::Error] on HTTP or parse failures
        def memberships(role: nil, limit: nil, resource_link_id: nil)
          params = {}
          params[:role]  = role  if role
          params[:limit] = limit if limit
          params[:rlid]  = resource_link_id if resource_link_id

          memberships_from_url(build_memberships_url(@memberships_url, params))
        end

        # Fetches a page of memberships from an arbitrary URL.  Use this for
        # pagination when following +next_page_url+ from a previous result.
        #
        # @param url [String] fully-resolved memberships URL (may include query
        #   string from a +rel="next"+ link header)
        # @return [MembershipsResult]
        # @raise [Lti::Advantage::Error] on HTTP or parse failures
        def memberships_from_url(url)
          response = Faraday.get(url) do |req|
            req.headers["Authorization"] = "Bearer #{@access_token}"
            req.headers["Accept"]        = MEDIA_TYPE
          end

          raise Error, "NRPS request failed (#{response.status}): #{response.body}" unless response.success?

          parse_response(response)
        rescue Faraday::Error => e
          raise Error, "Network error fetching memberships: #{e.message}"
        end

        # Convenience: fetches ALL members across every page and returns a
        # single flat array.  Use with care on large courses.
        #
        # @param role [String, nil] role filter forwarded to each page request
        # @return [Array<Lti::Advantage::Membership>]
        def all_members(role: nil, limit: nil, resource_link_id: nil)
          result  = memberships(role: role, limit: limit, resource_link_id: resource_link_id)
          members = result.members.dup

          while result.next_page_url
            result = memberships_from_url(result.next_page_url)
            members.concat(result.members)
          end

          members
        end

        private

        # Parses the Faraday response into a +MembershipsResult+.
        #
        # @param response [Faraday::Response]
        # @return [MembershipsResult]
        def parse_response(response)
          body = parse_json_body(response.body)

          members = Array(body["members"]).map do |raw|
            Membership.new(raw)
          end

          MembershipsResult.new(
            context: body["context"],
            members: members,
            next_page_url: extract_link(response.headers["link"], "next"),
            differences_url: extract_link(response.headers["link"], "differences")
          )
        rescue JSON::ParserError => e
          raise Error, "Failed to parse NRPS response: #{e.message}"
        end

        # Parses a RFC 8288 Link header and returns the URL for the given rel.
        #
        # @param header [String, nil] raw Link header value
        # @param rel [String] the relation type to look for ("next",
        #   "differences")
        # @return [String, nil]
        def extract_link(header, rel)
          return nil if header.nil? || header.empty?

          # Each entry looks like: <https://...>; rel="next"
          header.split(",").each do |entry|
            url_part, *params = entry.strip.split(";")
            url = url_part.strip.delete_prefix("<").delete_suffix(">")

            params.each do |param|
              key, value = param.strip.split("=", 2)
              return url if key.strip == "rel" && value&.delete('"') == rel
            end
          end

          nil
        end

        def build_memberships_url(url, params)
          return url if params.empty?

          uri = URI.parse(url)
          existing_params = URI.decode_www_form(uri.query.to_s)
          params.each do |key, value|
            existing_params << [key.to_s, value.to_s]
          end
          uri.query = URI.encode_www_form(existing_params)
          uri.to_s
        rescue URI::InvalidURIError => e
          raise Error, "Invalid memberships URL: #{e.message}"
        end

        def parse_json_body(body)
          case body
          when Hash
            body
          else
            JSON.parse(body.to_s)
          end
        end
      end
    end
  end
end
