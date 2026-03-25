# frozen_string_literal: true

require "faraday"
require "json"
require "set"
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
      #   result.members.each { |m| puts "#{m.user_id} - #{m.roles}" }
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

        MEMBERSHIP_ROLE_VOCAB = "http://purl.imsglobal.org/vocab/lis/v2/membership#"

        DEFAULT_MAX_PAGES = 100

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
        # @param enforce_same_origin [Boolean] when +true+, reject follow-up page
        #   and differences URLs whose origin differs from the original
        #   +memberships_url+; defaults to +false+ so platforms may paginate
        #   across multiple origins
        def initialize(memberships_url:, access_token:, enforce_same_origin: false)
          @memberships_url = normalize_memberships_url(memberships_url)
          @memberships_origin = request_origin(@memberships_url)
          @access_token = assert_presence("access_token", access_token)
          @enforce_same_origin = !!enforce_same_origin
        end

        # Fetches memberships from the service.
        #
        # @param role [String, nil] optional role URI or short name to filter by
        #   (e.g. "Learner" or the full URI). Short names are normalized to the
        #   IMS LIS membership vocabulary.
        # @param limit [Integer, nil] hint to the LMS about page size; must be a
        #   positive integer if supplied. The LMS may return more or fewer
        #   members than requested.
        # @param resource_link_id [String, nil] when supplied, appends +rlid+
        #   to scope the request to a specific Resource Link; blank values are
        #   rejected
        # @return [MembershipsResult]
        # @raise [Lti::Advantage::Error] on HTTP or parse failures
        def memberships(role: nil, limit: nil, resource_link_id: nil)
          request_url = build_memberships_url(@memberships_url, query_params(role, limit, resource_link_id))
          memberships_from_url(request_url)
        end

        # Fetches a page of memberships from an arbitrary URL. Use this for
        # pagination when following +next_page_url+ from a previous result.
        #
        # @param url [String] fully-resolved memberships URL (may include query
        #   string from a +rel="next"+ link header). Cross-origin URLs are
        #   allowed unless the service was initialized with
        #   +enforce_same_origin: true+.
        # @return [MembershipsResult]
        # @raise [Lti::Advantage::Error] on HTTP or parse failures
        def memberships_from_url(url)
          request_url = normalize_request_url(url)

          response = Faraday.get(request_url) do |req|
            req.headers["Authorization"] = "Bearer #{@access_token}"
            req.headers["Accept"] = MEDIA_TYPE
          end

          raise Error, "NRPS request failed (#{response.status}): #{response.body}" unless response.success?

          parse_response(response, request_url: request_url)
        rescue Faraday::Error => e
          raise Error, "Network error fetching memberships: #{e.message}"
        end

        # Convenience: fetches ALL members across every page and returns a
        # single flat array. Use with care on large courses.
        #
        # @param role [String, nil] role filter forwarded to each page request
        # @param max_pages [Integer] maximum number of pages to follow before
        #   aborting the pagination loop
        # @return [Array<Lti::Advantage::Membership>]
        def all_members(role: nil, limit: nil, resource_link_id: nil, max_pages: DEFAULT_MAX_PAGES)
          normalized_max_pages = normalize_max_pages(max_pages)
          request_url = build_memberships_url(@memberships_url, query_params(role, limit, resource_link_id))
          visited_urls = Set.new([request_url])
          page_count = 1

          result = memberships_from_url(request_url)
          members = result.members.dup

          while result.next_page_url
            raise Error, "NRPS pagination exceeded #{normalized_max_pages} pages" if page_count >= normalized_max_pages

            if visited_urls.include?(result.next_page_url)
              raise Error,
                    "Detected NRPS pagination cycle at #{result.next_page_url}"
            end

            visited_urls << result.next_page_url
            result = memberships_from_url(result.next_page_url)
            members.concat(result.members)
            page_count += 1
          end

          members
        end

        private

        # Parses the Faraday response into a +MembershipsResult+.
        #
        # @param response [Faraday::Response]
        # @param request_url [String]
        # @return [MembershipsResult]
        def parse_response(response, request_url:)
          validate_content_type!(response)
          body = parse_json_body(response.body)
          validate_membership_container!(body)
          links = parse_link_relations(header_value(response.headers, "link"), request_url)

          members = body.fetch("members").each_with_index.map do |raw, index|
            raise Error, "NRPS member at index #{index} must be an object" unless raw.is_a?(Hash)

            Membership.new(raw)
          end

          MembershipsResult.new(
            context: body["context"],
            members: members,
            next_page_url: links["next"],
            differences_url: links["differences"]
          )
        rescue JSON::ParserError => e
          raise Error, "Failed to parse NRPS response: #{e.message}"
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
          normalize_http_url(url, field_name: "memberships_url")
        end

        def normalize_request_url(url)
          normalized_url = normalize_http_url(url, field_name: "request URL", base_url: @memberships_url)
          if @enforce_same_origin && request_origin(normalized_url) != @memberships_origin
            raise Error, "Refusing to send NRPS token to a different origin"
          end

          normalized_url
        end

        def normalize_http_url(url, field_name:, base_url: nil)
          string_value = url.to_s.strip
          raise Error, "#{field_name} cannot be blank" if string_value.empty?

          uri = base_url ? URI.join(base_url, string_value) : URI.parse(string_value)
          raise Error, "#{field_name} must be an absolute HTTP(S) URL" unless absolute_http_uri?(uri)

          uri.to_s
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
          actual_type = content_type.to_s.split(";", 2).first.to_s.strip
          return if actual_type == MEDIA_TYPE

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

        def parse_link_relations(header, base_url)
          parse_link_header(header).each_with_object({}) do |link, relations|
            relation_types = link.fetch(:params).fetch("rel", "").split(/\s+/).reject(&:empty?)
            next if relation_types.empty?

            resolved_url = normalize_request_url(
              normalize_http_url(link.fetch(:url), field_name: "Link header URL", base_url: base_url)
            )
            relation_types.each do |relation_type|
              relations[relation_type] ||= resolved_url
            end
          end
        end

        def parse_link_header(header)
          return [] if header.nil? || header.empty?

          entries = []
          index = 0

          while index < header.length
            index = skip_link_delimiters(header, index)
            break if index >= header.length
            raise ArgumentError, "Malformed Link header" unless header[index] == "<"

            url, index = parse_link_url(header, index)
            params, index = parse_link_params(header, index)
            entries << { url: url, params: params }
          end

          entries
        rescue ArgumentError => e
          raise Error, "Malformed NRPS Link header: #{e.message}"
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

        def query_params(role, limit, resource_link_id)
          {}.tap do |params|
            normalized_role = normalize_optional_role_filter(role)
            normalized_limit = normalize_optional_positive_integer(limit, field_name: "limit")
            normalized_resource_link_id = normalize_optional_string(resource_link_id, field_name: "resource_link_id")

            params[:role] = normalized_role if normalized_role
            params[:limit] = normalized_limit if normalized_limit
            params[:rlid] = normalized_resource_link_id if normalized_resource_link_id
          end
        end

        def normalize_optional_role_filter(role)
          normalized_role = normalize_optional_string(role, field_name: "role")
          return nil if normalized_role.nil?
          return normalized_role if absolute_uri?(normalized_role)

          unless normalized_role.match?(/\A[A-Za-z][A-Za-z0-9_.-]*\z/)
            raise Error, "role must be a non-empty role URI or short role name"
          end

          "#{MEMBERSHIP_ROLE_VOCAB}#{normalized_role}"
        end

        def normalize_optional_positive_integer(value, field_name:)
          return nil if value.nil?

          normalized_value = value.is_a?(Integer) ? value : Integer(value.to_s, 10)
          raise Error, "#{field_name} must be a positive integer" if normalized_value <= 0

          normalized_value
        rescue ArgumentError, TypeError
          raise Error, "#{field_name} must be a positive integer"
        end

        def normalize_optional_string(value, field_name:)
          return nil if value.nil?

          string_value = value.to_s.strip
          raise Error, "#{field_name} cannot be blank" if string_value.empty?

          string_value
        end

        def absolute_uri?(value)
          uri = URI.parse(value)
          !uri.scheme.nil?
        rescue URI::InvalidURIError
          false
        end

        def normalize_max_pages(max_pages)
          value = max_pages.is_a?(Integer) ? max_pages : Integer(max_pages, 10)
          raise Error, "max_pages must be positive" if value <= 0

          value
        rescue ArgumentError, TypeError
          raise Error, "max_pages must be a positive integer"
        end

        def assert_presence(name, value)
          string_value = value.to_s.strip
          raise ConfigurationError, "#{name} is required" if string_value.empty?

          string_value
        end
      end
    end
  end
end
