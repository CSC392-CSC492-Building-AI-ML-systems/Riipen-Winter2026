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
          @memberships_url = normalize_memberships_url(memberships_url)
          @memberships_origin = request_origin(@memberships_url)
          @access_token = access_token
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
          request_url = normalize_request_url(url)

          response = Faraday.get(request_url) do |req|
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
          validate_content_type!(response)
          body = parse_json_body(response.body)
          validate_membership_container!(body)

          members = body.fetch("members").each_with_index.map do |raw, index|
            raise Error, "NRPS member at index #{index} must be an object" unless raw.is_a?(Hash)

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
          parse_link_header(header).each do |link|
            relation_types = link.fetch(:params).fetch("rel", "").split(/\s+/)
            return link.fetch(:url) if relation_types.include?(rel)
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

        def normalize_memberships_url(url)
          uri = parse_uri(url, field_name: "memberships_url")
          raise Error, "memberships_url must be an absolute HTTP(S) URL" unless absolute_http_uri?(uri)

          uri.to_s
        end

        def normalize_request_url(url)
          uri = parse_uri(url, field_name: "request URL")
          raise Error, "NRPS request URL must be an absolute HTTP(S) URL" unless absolute_http_uri?(uri)

          if request_origin(uri.to_s) != @memberships_origin
            raise Error, "Refusing to send NRPS token to a different origin"
          end

          uri.to_s
        end

        def parse_uri(value, field_name:)
          URI.parse(value.to_s)
        rescue URI::InvalidURIError => e
          raise Error, "Invalid #{field_name}: #{e.message}"
        end

        def absolute_http_uri?(uri)
          uri.is_a?(URI::HTTP) && !uri.host.nil?
        end

        def request_origin(url)
          uri = URI.parse(url)
          "#{uri.scheme}://#{uri.host}:#{uri.port}"
        end

        def validate_content_type!(response)
          content_type = header_value(response.headers, "content-type")
          expected_type = MEDIA_TYPE
          actual_type = content_type.to_s.split(";", 2).first.to_s.strip

          return if actual_type == expected_type

          raise Error, "Unexpected NRPS content type: #{content_type || "missing"}"
        end

        def validate_membership_container!(body)
          raise Error, "NRPS response body must be a JSON object" unless body.is_a?(Hash)

          members = body["members"]
          raise Error, "NRPS response members must be an array" unless members.is_a?(Array)

          context = body["context"]
          return if context.nil? || context.is_a?(Hash)

          raise Error, "NRPS response context must be an object"
        end

        def header_value(headers, name)
          return nil unless headers.respond_to?(:each)

          pair = headers.find do |key, _value|
            key.to_s.casecmp?(name)
          end
          pair&.last
        end

        def parse_link_header(header)
          return [] if header.nil? || header.empty?

          entries = []
          index = 0

          while index < header.length
            index = skip_link_delimiters(header, index)
            break if index >= header.length
            return [] unless header[index] == "<"

            url, index = parse_link_url(header, index)
            params, index = parse_link_params(header, index)
            entries << { url: url, params: params }
          end

          entries
        rescue ArgumentError
          []
        end

        def skip_link_delimiters(header, index)
          index += 1 while index < header.length && [",", " ", "\t"].include?(header[index])

          index
        end

        def parse_link_url(header, index)
          closing_index = header.index(">", index + 1)
          raise ArgumentError, "Malformed Link header" if closing_index.nil?

          [header[(index + 1)...closing_index], closing_index + 1]
        end

        def parse_link_params(header, index)
          params = {}

          loop do
            index = skip_optional_whitespace(header, index)
            break unless index < header.length && header[index] == ";"

            index += 1
            index = skip_optional_whitespace(header, index)
            name, value, index = parse_link_param(header, index)
            params[name] = value
          end

          [params, index]
        end

        def skip_optional_whitespace(header, index)
          index += 1 while index < header.length && [" ", "\t"].include?(header[index])

          index
        end

        def parse_link_param(header, index)
          name_start = index
          index += 1 while index < header.length && !["=", ";", ","].include?(header[index])

          name = header[name_start...index].to_s.strip.downcase
          raise ArgumentError, "Malformed Link header" if name.empty?

          return [name, "", index] unless index < header.length && header[index] == "="

          index += 1
          index = skip_optional_whitespace(header, index)
          value, index = parse_link_param_value(header, index)
          [name, value, index]
        end

        def parse_link_param_value(header, index)
          return ["", index] if index >= header.length

          if header[index] == '"'
            parse_quoted_link_param_value(header, index + 1)
          else
            value_start = index
            index += 1 while index < header.length && ![";", ","].include?(header[index])

            [header[value_start...index].to_s.strip, index]
          end
        end

        def parse_quoted_link_param_value(header, index)
          value = +""

          while index < header.length
            char = header[index]
            if char == "\\"
              index += 1
              raise ArgumentError, "Malformed Link header" if index >= header.length

              value << header[index]
            elsif char == '"'
              return [value, index + 1]
            else
              value << char
            end

            index += 1
          end

          raise ArgumentError, "Malformed Link header"
        end
      end
    end
  end
end
