# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::AGS::LineItemService do
  response_class = Struct.new(:code, :body, :link_header)

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
        Lti::Advantage::Claims::DEPLOYMENT_ID => "deployment-123",
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
      resourceId: "resource-123",
      tag: "homework",
      resourceLinkId: "link-123",
      startDateTime: "2026-03-11T20:10:06Z",
      endDateTime: "2026-03-12T20:10:06+00:00",
      gradesReleased: true,
      "https://example.com/ext" => "value"
    }.to_json
  end
  let(:second_line_item_body) do
    {
      id: "https://platform.example/line_items/43",
      label: "Homework 2",
      scoreMaximum: 50,
      resourceLinkId: "link-123"
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
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=1"]
        response_class.new(
          "200",
          "[#{line_item_body}]",
          %(<https://platform.example/contexts/1/line_items?page=2>; rel="next")
        )
      when [:get, "https://platform.example/contexts/1/line_items?page=2"]
        response_class.new("200", "[#{second_line_item_body}]")
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

  it "exposes list_page and list_all for paginated collections" do
    expect(described_class.public_instance_methods(false))
      .to include(:list, :list_page, :list_all, :create, :fetch, :update, :delete)
  end

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

  it "accepts serialized line item hashes for create" do
    payload = Lti::Advantage::AGS::LineItem.new(
      label: "Homework 1",
      score_maximum: 100,
      resource_id: "resource-123",
      resource_link_id: "link-123",
      start_date_time: "2026-03-11T20:10:06+00:00"
    ).to_h(include_id: false)

    item = line_item_service.create(line_item: payload)

    expect(item.id).to eq("https://platform.example/line_items/42")
    expect(JSON.parse(requests.last[:body])).to include(
      "label" => "Homework 1",
      "scoreMaximum" => 100,
      "resourceId" => "resource-123",
      "resourceLinkId" => "link-123",
      "startDateTime" => "2026-03-11T20:10:06+00:00"
    )
  end

  it "fetches a line item from the member url" do
    item = line_item_service.fetch

    expect(item.id).to eq("https://platform.example/line_items/42")
    expect(requests.last[:url]).to eq("https://platform.example/line_items/42")
    expect(requests.last[:headers]["Accept"]).to eq("application/vnd.ims.lis.v2.lineitem+json")
  end

  it "returns next_url when listing a paginated line item collection" do
    page = line_item_service.list_page(resource_link_id: "link-123", tag: "homework", limit: 1)

    expect(page[:line_items].length).to eq(1)
    expect(page[:next_url]).to eq("https://platform.example/contexts/1/line_items?page=2")
  end

  it "raises ServiceError when a line item entry is not an object" do
    invalid_item_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case [method, url]
      when [:post, "https://platform.example/oauth2/token"]
        response_class.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=1"]
        response_class.new("200", "[\"not-an-object\"]")
      else
        response_class.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: invalid_item_http
    )

    expect do
      described_class.new(service_client: client).list(resource_link_id: "link-123", tag: "homework", limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /invalid item at index 0/i)
  end

  it "follows Link rel=next when collecting all line items" do
    items = line_item_service.list_all(resource_link_id: "link-123", tag: "homework", limit: 1)

    expect(items.map(&:id)).to eq(
      [
        "https://platform.example/line_items/42",
        "https://platform.example/line_items/43"
      ]
    )
  end

  it "resolves relative next links against the collection request URL" do
    relative_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case [method, url]
      when [:post, "https://platform.example/oauth2/token"]
        response_class.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=1"]
        response_class.new("200", "[#{line_item_body}]", %(<?page=2>; rel="next"))
      when [:get, "https://platform.example/contexts/1/line_items?page=2"]
        response_class.new("200", "[#{second_line_item_body}]")
      else
        response_class.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: relative_link_http
    )

    items = described_class.new(service_client: client).list_all(resource_link_id: "link-123", tag: "homework",
                                                                 limit: 1)
    expect(items.map(&:id)).to eq(
      [
        "https://platform.example/line_items/42",
        "https://platform.example/line_items/43"
      ]
    )
  end

  it "rejects next links hosted on a different origin by default" do
    cross_origin_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case [method, url]
      when [:post, "https://platform.example/oauth2/token"]
        response_class.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=1"]
        response_class.new(
          "200",
          "[#{line_item_body}]",
          %(<https://cdn.platform.example/contexts/1/line_items?page=2>; rel="next")
        )
      else
        response_class.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: cross_origin_link_http
    )

    expect do
      described_class.new(service_client: client).list_all(resource_link_id: "link-123", tag: "homework", limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /different origin/)
  end

  it "raises when the Link header is malformed" do
    malformed_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case [method, url]
      when [:post, "https://platform.example/oauth2/token"]
        response_class.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when [:get, "https://platform.example/contexts/1/line_items?resource_link_id=link-123&tag=homework&limit=1"]
        response_class.new(
          "200",
          "[#{line_item_body}]",
          "<https://platform.example/contexts/1/line_items?page=2; rel=\"next\""
        )
      else
        response_class.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: malformed_link_http
    )

    expect do
      described_class.new(service_client: client).list_all(resource_link_id: "link-123", tag: "homework", limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /Malformed AGS Link header/)
  end

  it "merges the current line item state when updating partial attributes" do
    item = line_item_service.update(
      line_item: {
        label: "Homework 1 - Updated"
      }
    )

    expect(item.label).to eq("Homework 1 - Updated")
    expect(item.score_maximum).to eq(100)
    expect(item.resource_id).to eq("resource-123")
    expect(item.tag).to eq("homework")
    expect(item.start_date_time).to eq("2026-03-11T20:10:06Z")
    expect(item.end_date_time).to eq("2026-03-12T20:10:06+00:00")
    expect(item.grades_released).to be(true)

    request = requests.last
    expect(request[:method]).to eq(:put)
    expect(request[:url]).to eq("https://platform.example/line_items/42")
    expect(JSON.parse(request[:body])).to eq(
      "https://example.com/ext" => "value",
      "label" => "Homework 1 - Updated",
      "scoreMaximum" => 100,
      "resourceId" => "resource-123",
      "tag" => "homework",
      "resourceLinkId" => "link-123",
      "startDateTime" => "2026-03-11T20:10:06Z",
      "endDateTime" => "2026-03-12T20:10:06+00:00",
      "gradesReleased" => true
    )
  end

  it "allows explicitly clearing optional fields during update" do
    item = line_item_service.update(
      line_item: {
        label: "Homework 1 - Updated",
        tag: "   ",
        start_date_time: nil,
        grades_released: nil
      }
    )

    expect(item.label).to eq("Homework 1 - Updated")
    expect(item.tag).to be_nil
    expect(item.start_date_time).to be_nil
    expect(item.grades_released).to be_nil
    expect(item.resource_id).to eq("resource-123")
    expect(item.end_date_time).to eq("2026-03-12T20:10:06+00:00")

    expect(JSON.parse(requests.last[:body])).to eq(
      "https://example.com/ext" => "value",
      "label" => "Homework 1 - Updated",
      "scoreMaximum" => 100,
      "resourceId" => "resource-123",
      "resourceLinkId" => "link-123",
      "endDateTime" => "2026-03-12T20:10:06+00:00"
    )
  end

  it "accepts serialized line item hashes for update" do
    serialized = line_item_service.fetch.to_h.merge(
      "label" => "Homework 1 - Wire Update",
      "startDateTime" => "2026-03-11T20:10:06+00:00"
    )

    item = line_item_service.update(line_item: serialized)

    expect(item.label).to eq("Homework 1 - Wire Update")
    expect(item.start_date_time).to eq("2026-03-11T20:10:06+00:00")
    expect(JSON.parse(requests.last[:body])).to include(
      "label" => "Homework 1 - Wire Update",
      "startDateTime" => "2026-03-11T20:10:06+00:00"
    )
  end

  it "rejects line item id changes during update" do
    expect do
      line_item_service.update(
        line_item: {
          id: "https://platform.example/line_items/99",
          label: "Homework 1 - Updated",
          score_maximum: 125,
          resource_link_id: "link-123"
        }
      )
    end.to raise_error(Lti::Advantage::ValidationError, /line item id cannot be changed/)
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
