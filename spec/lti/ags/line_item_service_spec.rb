# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::AGS::LineItemService do
  response_class = Struct.new(:code, :body)

  let(:registration) do
    Lti::Advantage::Registration.new(
      issuer: "https://platform.example",
      client_id: "client-123",
      authorization_endpoint: "https://platform.example/oidc/auth",
      token_endpoint: "https://platform.example/oauth2/token",
      jwks_url: "https://platform.example/.well-known/jwks.json",
      deployment_ids: ["deployment-123"]
    )
  end

  let(:launch) do
    Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitems" => "https://platform.example/contexts/1/line_items",
          "lineitem" => "https://platform.example/line_items/42",
          "scope" => [Lti::Advantage::AGS::Endpoint::LINEITEM_SCOPE]
        }
      },
      header: {},
      registration: registration
    )
  end

  let(:key_pair) { Lti::Advantage::KeyPair.new(nil, kid: "tool-key") }
  let(:requests) { [] }
  let(:line_item_body) do
    {
      id: "https://platform.example/line_items/42",
      label: "Homework 1",
      scoreMaximum: 100,
      resourceLinkId: "link-123",
      "https://example.com/ext" => "value"
    }.to_json
  end
  let(:http_request) do
    lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case [method, url]
      when [:post, "https://platform.example/oauth2/token"]
        response_class.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=5"]
        response_class.new("200", "[#{line_item_body}]")
      when [:get, "https://platform.example/line_items/42"]
        response_class.new("200", line_item_body)
      when [:post, "https://platform.example/contexts/1/line_items"]
        response_class.new("201", line_item_body)
      when [:put, "https://platform.example/line_items/42"]
        response_class.new("200", body)
      when [:delete, "https://platform.example/line_items/42"]
        response_class.new("204", "")
      else
        response_class.new("404", "not found")
      end
    end
  end

  let(:service_client) do
    Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: http_request
    )
  end

  subject(:line_item_service) { described_class.new(service_client: service_client) }

  it "lists line items from the container url with optional filters" do
    items = line_item_service.list(resource_link_id: "link-123", tag: "homework", limit: 5)

    expect(items.length).to eq(1)
    expect(items.first.label).to eq("Homework 1")

    request = requests.last
    expect(request[:method]).to eq(:get)
    expect(request[:url]).to eq("https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=5")
    expect(request[:headers]["Accept"]).to eq("application/vnd.ims.lis.v2.lineitemcontainer+json")
  end

  it "creates a line item at the container url and omits id from the request" do
    item = line_item_service.create(
      line_item: {
        id: "https://platform.example/line_items/99",
        label: "Homework 1",
        score_maximum: 100,
        resource_link_id: "link-123"
      }
    )

    expect(item.id).to eq("https://platform.example/line_items/42")

    request = requests.last
    expect(request[:method]).to eq(:post)
    expect(request[:url]).to eq("https://platform.example/contexts/1/line_items")
    expect(request[:headers]["Content-Type"]).to eq("application/vnd.ims.lis.v2.lineitem+json")
    expect(JSON.parse(request[:body])).not_to have_key("id")
  end

  it "fetches a line item from the member url" do
    item = line_item_service.fetch

    expect(item.id).to eq("https://platform.example/line_items/42")
    expect(requests.last[:url]).to eq("https://platform.example/line_items/42")
    expect(requests.last[:headers]["Accept"]).to eq("application/vnd.ims.lis.v2.lineitem+json")
  end

  it "updates a line item with full replacement semantics" do
    item = line_item_service.update(
      line_item: {
        id: "https://platform.example/line_items/42",
        label: "Homework 1 - Updated",
        score_maximum: 125,
        resource_link_id: "link-123"
      }
    )

    expect(item.label).to eq("Homework 1 - Updated")

    request = requests.last
    expect(request[:method]).to eq(:put)
    expect(request[:url]).to eq("https://platform.example/line_items/42")
    expect(JSON.parse(request[:body])).to include(
      "label" => "Homework 1 - Updated",
      "scoreMaximum" => 125,
      "resourceLinkId" => "link-123",
      "https://example.com/ext" => "value"
    )
  end

  it "rejects resourceLinkId changes during update" do
    expect do
      line_item_service.update(
        line_item: {
          label: "Homework 1 - Updated",
          score_maximum: 125,
          resource_link_id: "different-link"
        }
      )
    end.to raise_error(Lti::Advantage::ValidationError, /resourceLinkId cannot be changed/)
  end

  it "deletes a line item and treats 204 as success" do
    expect(line_item_service.delete).to eq(true)
    expect(requests.last[:method]).to eq(:delete)
    expect(requests.last[:url]).to eq("https://platform.example/line_items/42")
  end

  it "allows readonly scope for read methods" do
    readonly_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitems" => "https://platform.example/contexts/1/line_items",
          "lineitem" => "https://platform.example/line_items/42",
          "scope" => [Lti::Advantage::AGS::Endpoint::LINEITEM_READONLY_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    readonly_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: readonly_launch,
      key_pair: key_pair,
      http_request: http_request
    )

    item = described_class.new(service_client: readonly_client).fetch
    expect(item.id).to eq("https://platform.example/line_items/42")
  end
end
