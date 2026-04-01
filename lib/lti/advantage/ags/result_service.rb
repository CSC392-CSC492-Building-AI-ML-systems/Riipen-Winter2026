# frozen_string_literal: true

require "uri"
require "set"

module Lti
  module Advantage
    module AGS
      # Client for the LTI AGS Result service (read-only grades for a line item).
      # https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service
      class ResultService
        # Media type for AGS result collections.
        RESULT_CONTAINER_TYPE = "application/vnd.ims.lis.v2.resultcontainer+json"

        # service_client:: {ServiceClient} used for authorization and HTTP.
        def initialize(service_client:)
          @service_client = service_client
        end

        # Returns one page of results as an Array.
        #
        # line_item_url:: Optional explicit line item URL override.
        # user_id:: Optional filter for a single user.
        # limit:: Optional positive integer page-size hint.
        def list(line_item_url: nil, user_id: nil, limit: nil)
          url = expected_line_item_url(line_item_url)
          page = list_page(
            line_item_url: line_item_url,
            user_id: user_id,
            limit: limit,
            expected_line_item_url: url
          )
          page[:results]
        end

        # Returns a paginated result response Hash.
        #
        # The returned Hash includes +:results+ and +:next_url+.
        def list_page(line_item_url: nil, user_id: nil, limit: nil, page_url: nil, expected_line_item_url: nil)
          expected_line_item_url ||= expected_line_item_url(line_item_url)
          url = page_url || build_results_url(
            base: @service_client.endpoint.results_url(line_item_url: line_item_url),
            user_id: user_id,
            limit: limit
          )

          response = @service_client.get_json_with_headers(
            url: url,
            accept: RESULT_CONTAINER_TYPE,
            scopes: [Endpoint::RESULT_READONLY_SCOPE]
          )

          validate_media_type!(response[:content_type])
          data = response[:data]
          raise ServiceError, "Result service response must be a JSON array" unless data.is_a?(Array)

          results = parse_results(data)
          results.each do |result|
            validate_score_of!(result: result, expected_url: expected_line_item_url)
          end

          if user_id && results.length > 1
            raise ServiceError, "Result service returned more than one result for user_id filter"
          end

          next_url = parse_next_url(response[:link_header], base_url: url)

          { results: results, next_url: next_url }
        end

        # Follows every available page and returns all results.
        def list_all(line_item_url: nil, user_id: nil, limit: nil)
          all_pages = []
          page_url = nil
          seen_page_urls = Set.new
          expected_line_item_url = expected_line_item_url(line_item_url)

          loop do
            if page_url
              raise ServiceError, "Result service pagination cycle detected" if seen_page_urls.include?(page_url)

              seen_page_urls.add(page_url)
            end

            page = list_page(
              line_item_url: page_url.nil? ? line_item_url : nil,
              user_id: user_id,
              limit: limit,
              page_url: page_url,
              expected_line_item_url: expected_line_item_url
            )

            all_pages.concat(page[:results])
            if user_id && all_pages.length > 1
              raise ServiceError, "Result service returned more than one result for user_id filter"
            end

            page_url = page[:next_url]
            break if page_url.nil?
          end
          all_pages
        end

        private

        def parse_next_url(link_header, base_url:)
          @service_client.follow_up_url(link_header: link_header, relation: "next", request_url: base_url)
        end

        def validate_media_type!(content_type)
          if content_type.nil? || content_type.to_s.strip.empty?
            raise ServiceError, "Result service must return #{RESULT_CONTAINER_TYPE}, got empty Content-Type"
          end

          media_type = content_type.to_s.split(";").first.to_s.strip
          return if media_type.casecmp(RESULT_CONTAINER_TYPE).zero?

          raise ServiceError, "Result service must return #{RESULT_CONTAINER_TYPE}, got #{content_type}"
        end

        def build_results_url(base:, user_id:, limit:)
          uri = URI.parse(base)

          params = URI.decode_www_form(uri.query || "")
          params.reject! { |key, _value| key == "user_id" } if user_id
          params.reject! { |key, _value| key == "limit" } if limit
          params << ["user_id", user_id] if user_id
          params << ["limit", limit.to_s] if limit
          uri.query = params.empty? ? nil : URI.encode_www_form(params)
          uri.to_s
        end

        def parse_results(data)
          data.each_with_index.map do |item, index|
            Result.from_json(item)
          rescue ValidationError => e
            raise ServiceError, "Result service response contains an invalid result at index #{index}: #{e.message}"
          end
        end

        def normalize_url(url:)
          uri = URI.parse(url.to_s)
          uri.query = nil
          uri.fragment = nil
          uri.to_s.sub(%r{/$}, "")
        end

        def validate_score_of!(result:, expected_url:)
          norm_score_of = normalize_url(url: result.score_of)
          norm_line_item = normalize_url(url: expected_url)

          return unless norm_score_of != norm_line_item

          raise ValidationError, "scoreOf is not equal to line item"
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
