# frozen_string_literal: true

require "json"
require "set"
require "uri"

module Lti
  module Advantage
    module AGS
      class LineItemService
        LINE_ITEM_CONTENT_TYPE = "application/vnd.ims.lis.v2.lineitem+json"
        LINE_ITEM_CONTAINER_CONTENT_TYPE = "application/vnd.ims.lis.v2.lineitemcontainer+json"

        def initialize(service_client:)
          @service_client = service_client
        end

        def list(resource_link_id: nil, resource_id: nil, tag: nil, limit: nil, url: nil)
          page = list_page(
            resource_link_id: resource_link_id,
            resource_id: resource_id,
            tag: tag,
            limit: limit,
            url: url
          )

          page[:line_items]
        end

        def list_page(resource_link_id: nil, resource_id: nil, tag: nil, limit: nil, url: nil, page_url: nil)
          request_url = if page_url
                          page_url
                        else
                          collection_url = @service_client.endpoint.lineitems_url!(lineitems_url: url, write: false)
                          with_query(
                            collection_url,
                            resource_link_id: resource_link_id,
                            resource_id: resource_id,
                            tag: tag,
                            limit: limit
                          )
                        end

          response = @service_client.request(
            method: :get,
            url: request_url,
            scopes: read_scopes,
            headers: { "Accept" => LINE_ITEM_CONTAINER_CONTENT_TYPE }
          )

          parse_line_item_page(response)
        end

        def list_all(resource_link_id: nil, resource_id: nil, tag: nil, limit: nil, url: nil)
          line_items = []
          page_url = nil
          seen_page_urls = Set.new

          loop do
            if page_url
              raise ServiceError, "AGS line item pagination cycle detected" if seen_page_urls.include?(page_url)

              seen_page_urls.add(page_url)
            end

            page = list_page(
              resource_link_id: page_url.nil? ? resource_link_id : nil,
              resource_id: page_url.nil? ? resource_id : nil,
              tag: page_url.nil? ? tag : nil,
              limit: page_url.nil? ? limit : nil,
              url: page_url.nil? ? url : nil,
              page_url: page_url
            )

            line_items.concat(page[:line_items])
            page_url = page[:next_url]
            break if page_url.nil?
          end

          line_items
        end

        def create(line_item:, url: nil)
          record = normalize_line_item(line_item)
          response = @service_client.post_json(
            url: @service_client.endpoint.lineitems_url!(lineitems_url: url, write: true),
            body: record.to_h(include_id: false),
            content_type: LINE_ITEM_CONTENT_TYPE,
            accept: LINE_ITEM_CONTENT_TYPE,
            scopes: [Endpoint::LINEITEM_SCOPE]
          )

          parse_line_item(response)
        end

        def fetch(line_item_url: nil)
          response = @service_client.request(
            method: :get,
            url: @service_client.endpoint.line_item_url!(line_item_url: line_item_url, write: false),
            scopes: read_scopes,
            headers: { "Accept" => LINE_ITEM_CONTENT_TYPE }
          )

          parse_line_item(response)
        end

        def update(line_item:, line_item_url: nil)
          record = normalize_line_item(line_item)
          url = @service_client.endpoint.line_item_url!(line_item_url: line_item_url, write: true)
          current = fetch(line_item_url: url)

          if !current.resource_link_id.nil? &&
             !record.resource_link_id.nil? &&
             current.resource_link_id != record.resource_link_id
            raise ValidationError, "resourceLinkId cannot be changed"
          end

          if !current.id.nil? && !record.id.nil? && current.id != record.id
            raise ValidationError, "line item id cannot be changed"
          end

          merged_payload = current.to_h.merge(record.to_h)
          merged_payload["id"] = current.id unless current.id.nil?
          merged_record = LineItem.from_h(merged_payload)
          response = @service_client.put_json(
            url: url,
            body: merged_record.to_h(include_id: false),
            content_type: LINE_ITEM_CONTENT_TYPE,
            accept: LINE_ITEM_CONTENT_TYPE,
            scopes: [Endpoint::LINEITEM_SCOPE]
          )

          parse_line_item(response, fallback: merged_record)
        end

        def delete(line_item_url: nil)
          @service_client.request(
            method: :delete,
            url: @service_client.endpoint.line_item_url!(line_item_url: line_item_url, write: true),
            scopes: [Endpoint::LINEITEM_SCOPE],
            headers: { "Accept" => LINE_ITEM_CONTENT_TYPE }
          )

          true
        end

        private

        def normalize_line_item(line_item)
          return line_item if line_item.is_a?(LineItem)

          LineItem.new(**line_item)
        end

        def parse_line_item(response, fallback: nil)
          body = response.body.to_s.strip
          return fallback if body.empty? && !fallback.nil?

          raise ServiceError, "AGS line item response must include a JSON object body" if body.empty?

          LineItem.from_h(parse_json_object(body))
        end

        def parse_line_item_page(response)
          payload = JSON.parse(response.body)
          raise ServiceError, "AGS line item list response must be a JSON array" unless payload.is_a?(Array)

          {
            line_items: payload.map { |item| LineItem.from_h(item) },
            next_url: parse_next_url(read_link_header(response))
          }
        rescue JSON::ParserError => e
          raise ServiceError, "AGS line item response is not valid JSON: #{e.message}"
        end

        def parse_json_object(body)
          payload = JSON.parse(body)
          raise ServiceError, "AGS line item response must be a JSON object" unless payload.is_a?(Hash)

          payload
        rescue JSON::ParserError => e
          raise ServiceError, "AGS line item response is not valid JSON: #{e.message}"
        end

        def read_scopes
          if @service_client.endpoint.supports_scope?(Endpoint::LINEITEM_SCOPE)
            [Endpoint::LINEITEM_SCOPE]
          else
            [Endpoint::LINEITEM_READONLY_SCOPE]
          end
        end

        def with_query(url, resource_link_id:, resource_id:, tag:, limit:)
          params = {
            "resource_link_id" => resource_link_id,
            "resource_id" => resource_id,
            "tag" => tag,
            "limit" => limit
          }.compact
          return url if params.empty?

          uri = URI.parse(url)
          existing = URI.decode_www_form(String(uri.query))
          uri.query = URI.encode_www_form(existing + params.to_a)
          uri.to_s
        end

        def parse_next_url(link_header)
          return nil if link_header.nil? || link_header.to_s.strip.empty?

          link_header.to_s.split(",").each do |part|
            url = part.match(/<([^>]+)>/)
            rel = part.match(/rel\s*=\s*["']?next["']?/i)
            return url[1].strip if url && rel
          end

          nil
        end

        def read_link_header(response)
          return response.link_header if response.respond_to?(:link_header)
          return response["Link"] if response.respond_to?(:[]) && response["Link"]

          nil
        rescue NameError
          nil
        end
      end
    end
  end
end
