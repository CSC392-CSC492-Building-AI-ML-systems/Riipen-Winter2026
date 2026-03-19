require "json"
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
          collection_url = @service_client.endpoint.lineitems_url!(lineitems_url: url, write: false)
          response = @service_client.request(
            method: :get,
            url: with_query(collection_url, resource_link_id:, resource_id:, tag:, limit:),
            scopes: read_scopes,
            headers: { "Accept" => LINE_ITEM_CONTAINER_CONTENT_TYPE }
          )

          parse_line_item_collection(response)
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
            url: @service_client.endpoint.line_item_url!(line_item_url:, write: false),
            scopes: read_scopes,
            headers: { "Accept" => LINE_ITEM_CONTENT_TYPE }
          )

          parse_line_item(response)
        end

        def update(line_item:, line_item_url: nil)
          record = normalize_line_item(line_item)
          url = @service_client.endpoint.line_item_url!(line_item_url:, write: true)
          current = fetch(line_item_url: url)

          if !current.resource_link_id.nil? && !record.resource_link_id.nil? && current.resource_link_id != record.resource_link_id
            raise ValidationError, "resourceLinkId cannot be changed"
          end

          merged_record = LineItem.from_h(current.extensions.merge(record.to_h))
          response = @service_client.put_json(
            url: url,
            body: merged_record.to_h(include_id: false),
            content_type: LINE_ITEM_CONTENT_TYPE,
            accept: LINE_ITEM_CONTENT_TYPE,
            scopes: [Endpoint::LINEITEM_SCOPE]
          )

          parse_line_item(response)
        end

        def delete(line_item_url: nil)
          @service_client.request(
            method: :delete,
            url: @service_client.endpoint.line_item_url!(line_item_url:, write: true),
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

        def parse_line_item(response)
          LineItem.from_h(parse_json_object(response))
        end

        def parse_line_item_collection(response)
          payload = JSON.parse(response.body)
          raise ServiceError, "AGS line item list response must be a JSON array" unless payload.is_a?(Array)

          payload.map { |item| LineItem.from_h(item) }
        rescue JSON::ParserError => e
          raise ServiceError, "AGS line item response is not valid JSON: #{e.message}"
        end

        def parse_json_object(response)
          payload = JSON.parse(response.body)
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
      end
    end
  end
end
