# frozen_string_literal: true

require "uri"
require "set"

module Lti
  module Advantage
    module AGS
      # Client for the LTI AGS Result service (read-only grades for a line item).
      # https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service
      class ResultService
        RESULT_CONTAINER_TYPE = "application/vnd.ims.lis.v2.resultcontainer+json"

        def initialize(service_client:)
          @service_client = service_client
        end

        # GET results for the line item. Optionally filter by user_id and/or limit.
        # Returns only the first page; use #list_page for pagination or #list_all to fetch all pages.
        #
        # @param line_item_url [String, nil] explicit line item URL, or nil to use launch claim
        # @param user_id [String, nil] filter to a single user (at most one result)
        # @param limit [Integer, nil] max number of results to return
        # @return [Array<Result>]
        def list(line_item_url: nil, user_id: nil, limit: nil)
          page = list_page(line_item_url: line_item_url, user_id: user_id, limit: limit)
          page[:results]
        end

        # GET one page of results and the next page URL if present (per RFC 8288 Link header).
        #
        # @param line_item_url [String, nil] explicit line item URL, or nil to use launch claim
        # @param user_id [String, nil] filter to a single user (at most one result)
        # @param limit [Integer, nil] max number of results per page
        # @param page_url [String, nil] when set, GET this URL directly (e.g. next page from previous response)
        # @return [Hash] { results: Array<Result>, next_url: String|nil }
        def list_page(line_item_url: nil, user_id: nil, limit: nil, page_url: nil)
          url = page_url || build_results_url(
            base: @service_client.endpoint.results_url(line_item_url: line_item_url),
            user_id: user_id,
            limit: limit
          )

          response = @service_client.get_json_with_headers(
            url: url,
            accept: RESULT_CONTAINER_TYPE,
            scopes: [Endpoint::RESULT_SCOPE]
          )

          data = response[:data]
          items = data.is_a?(Array) ? data : []
          results = items.map { |item| Result.from_json(item) }
          if user_id && results.length > 1
            raise ServiceError, "Result service returned more than one result for user_id filter"
          end
          next_url = parse_next_url(response[:link_header])

          { results: results, next_url: next_url }
        end

        # Fetch all pages of results by following the Link rel="next" until none.
        #
        # @param line_item_url [String, nil] explicit line item URL, or nil to use launch claim
        # @param user_id [String, nil] filter to a single user
        # @param limit [Integer, nil] max number of results per page (platform may reduce)
        # @return [Array<Result>]
        def list_all(line_item_url: nil, user_id: nil, limit: nil)
          all = []
          page_url = nil
          seen_page_urls = Set.new

          loop do
            if !page_url.nil?
              raise ServiceError, "Result service pagination cycle detected" if seen_page_urls.include?(page_url)

              seen_page_urls.add(page_url)
            end

            page = list_page(
              line_item_url: line_url_for_first_page_only(page_url, line_item_url),
              user_id: user_id,
              limit: limit,
              page_url: page_url
            )
            all.concat(page[:results])
            page_url = page[:next_url]
            break if page_url.nil?
          end

          all
        end

        private

        def line_url_for_first_page_only(page_url, line_item_url)
          page_url.nil? ? line_item_url : nil
        end

        # Parse RFC 8288 Link header and return the URL for rel="next", or nil.
        def parse_next_url(link_header)
          return nil if link_header.nil? || link_header.to_s.strip.empty?

          link_header.to_s.split(",").each do |part|
            segment = part.strip
            next if segment.empty?

            # Match <url> and rel="next" or rel='next'
            url = segment[%r{<([^>]+)>}, 1]
            rel = segment[%r{rel\s*=\s*["']([^"']+)["']}i, 1]
            return url&.strip if rel&.strip&.downcase == "next"
          end

          nil
        end

        def build_results_url(base:, user_id:, limit:)
          uri = URI.parse(base)
          params = URI.decode_www_form(uri.query || "").to_h
          params["user_id"] = user_id if user_id
          params["limit"] = limit.to_s if limit
          uri.query = URI.encode_www_form(params) unless params.empty?
          uri.to_s
        end
      end
    end
  end
end
