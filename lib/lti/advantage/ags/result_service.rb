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

        # GET results for line item.
        def list(line_item_url: nil, user_id: nil, limit: nil)
          url = expected_line_item_url(line_item_url)
          # get a page
          page = list_page(
            line_item_url: line_item_url,
            user_id: user_id,
            limit: limit,
            expected_line_item_url: url
          )
          # get a page of results
          page[:results]
        end

        def list_page(line_item_url: nil, user_id: nil, limit: nil, page_url: nil, expected_line_item_url: nil)       
          expected_line_item_url ||= expected_line_item_url(line_item_url)
          url = page_url || build_results_url(
            base: @service_client.endpoint.results_url(line_item_url: line_item_url),
            user_id: user_id,
            limit: limit
          )

          # GET lineitem URL/results
          response = @service_client.get_json_with_headers(
            url: url,
            accept: RESULT_CONTAINER_TYPE,
            scopes: [Endpoint::RESULT_SCOPE]
          )

          validate_media_type!(response[:content_type])
          data = response[:data]
          items = data.is_a?(Array) ? data : []

          results = items.map { |item| Result.from_json(item) }
          # check if scoreOf == line item url
          results.each do |result|
            validate_score_of!(result: result, expected_url: expected_line_item_url)
          end

          if user_id && results.length > 1
            raise ServiceError, "Result service returned more than one result for user_id filter"
          end

          next_url = parse_next_url(response[:link_header])

          { results: results, next_url: next_url }
        end

        # Fetch all pages of results by following the Link rel="next" until none.
        def list_all(line_item_url: nil, user_id: nil, limit: nil)
          all_pages = []
          page_url = nil
          # list of visited pages
          seen_page_urls = Set.new
          expected_line_item_url = expected_line_item_url(line_item_url)

          loop do
            # if not first page and already visited, error
            # if not first page and not visited before, store
            if page_url 
              if seen_page_urls.include?(page_url)
                raise ServiceError, "Result service pagination cycle detected"
              end
              seen_page_urls.add(page_url)
            end

            # get one page
            # first page: pass line_item_url to get /results
            page = list_page(
              line_item_url: page_url.nil? ? line_item_url : nil, 
              user_id: user_id,
              limit: limit,
              page_url: page_url,
              expected_line_item_url: expected_line_item_url
            )

            all_pages.concat(page[:results])
            # get next url
            page_url = page[:next_url]
            # if next does not exist
            break if page_url.nil?
          end
          all_pages
        end

        private

        # Parse RFC 8288 Link header and return the URL for rel="next", or nil.
        def parse_next_url(link_header)
          return nil if link_header.nil? || link_header.to_s.strip.empty?

          link_header.to_s.split(",").each do |part|
            url = part.match(/<([^>]+)>/)
            rel = part.match(/rel\s*=\s*["']?next["']?/i)
            return url[1].strip if url && rel
          end

          nil
        end
        # validate correct RESULT_CONTAINER_TYPE
        def validate_media_type!(content_type)
          if content_type.nil? || content_type.to_s.strip.empty?
            raise ServiceError, "Result service must return #{RESULT_CONTAINER_TYPE}, got empty Content-Type"
          end
          media_type = content_type.to_s.split(";").first.to_s.strip
          unless media_type.casecmp(RESULT_CONTAINER_TYPE).zero?
            raise ServiceError, "Result service must return #{RESULT_CONTAINER_TYPE}, got #{content_type}"
          end
        end

        #  create the url to get the results
        def build_results_url(base:, user_id:, limit:)
          uri = URI.parse(base)

          # include the query 
          params = URI.decode_www_form(uri.query || "").to_h
          # add the user_id and limit to url if exist
          params["user_id"] = user_id if user_id
          params["limit"] = limit.to_s if limit
          # check if params is empty or not
          if !params.empty?
            uri.query = URI.encode_www_form(params)
          end
          uri.to_s
        end

        def normalize_url(url:)
          uri = URI.parse(url.to_s)
          # remove any query and fragments
          uri.query = nil
          uri.fragment = nil
          # remove trailing / if exist
          uri.to_s.sub(%r{/$}, "")
        end

        # check if scoreOf == line item
        def validate_score_of!(result: , expected_url:)
          norm_score_of = normalize_url(url: result.score_of)
          norm_line_item = normalize_url(url: expected_url)

          if norm_score_of != norm_line_item
            raise ValidationError, "scoreOf is not equal to line item"
          end
        end

        def expected_line_item_url(explicit_line_item_url)
          candidate = optional_string(explicit_line_item_url) || @service_client.endpoint.lineitem_url
          return candidate unless candidate.nil?

          raise ValidationError, "A concrete AGS lineitem URL is required for result validation"
        end

        def optional_string(value)
          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end
      end
    end
  end
end
