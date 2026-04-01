# frozen_string_literal: true

require "uri"

ResultServiceResponse = Struct.new(:code, :body)
ResultServiceResponseWithLink = Struct.new(:code, :body, :link_header, :content_type) do
  def initialize(code, body, link_header, content_type = Lti::Advantage::AGS::ResultService::RESULT_CONTAINER_TYPE)
    super(code, body, link_header, content_type)
  end
end
ResultServiceResponseWithLinkAndType = Struct.new(:code, :body, :link_header, :content_type)

RSpec.describe Lti::Advantage::AGS::ResultService do
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

  let(:lineitem_url) { "https://platform.example/line_items/42?foo=bar" }

  let(:launch) do
    Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => lineitem_url,
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE]
        }
      },
      header: {},
      registration: registration
    )
  end

  let(:key_pair) { Lti::Advantage::KeyPair.new(nil, kid: "tool-key") }
  let(:requests) { [] }
  let(:http_request) do
    lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }

      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200",
                                  { access_token: "token-123", token_type: "Bearer",
                                    expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.83,
              "resultMaximum" => 1,
              "scoringUserId" => "instructor-1",
              "comment" => "Nice work"
            }
          ].to_json,
          nil
        )
      when "https://platform.example/line_items/42/results?foo=bar&user_id=user-1&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.5
            }
          ].to_json,
          nil
        )
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
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

  subject(:result_service) { described_class.new(service_client: service_client) }

  it "requests an OAuth token and GETs results with the required Accept media type" do
    results = result_service.list

    expect(requests.size).to eq(2)

    token_request = requests[0]
    token_form = URI.decode_www_form(token_request[:body]).to_h
    expect(token_request[:url]).to eq("https://platform.example/oauth2/token")
    expect(token_request[:headers]["Content-Type"]).to eq("application/x-www-form-urlencoded")
    expect(token_form).to include(
      "grant_type" => "client_credentials",
      "scope" => Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE,
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    )
    expect(token_form["client_assertion"]).not_to be_empty

    results_request = requests[1]
    expect(results_request[:method]).to eq(:get)
    expect(results_request[:url]).to eq("https://platform.example/line_items/42/results?foo=bar")
    expect(results_request[:headers]["Authorization"]).to eq("Bearer token-123")
    expect(results_request[:headers]["Accept"]).to eq(described_class::RESULT_CONTAINER_TYPE)

    expect(results.length).to eq(1)
    expect(results.first).to be_a(Lti::Advantage::AGS::Result)
    expect(results.first.user_id).to eq("user-1")
    expect(results.first.result_score).to eq(0.83)
    expect(results.first.result_maximum).to eq(1)
  end

  it "derives the results endpoint by appending /results and preserving query parameters" do
    result_service.list
    results_request = requests.find { |r| r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/line_items/42/results?foo=bar")
  end

  it "supports container filters user_id and limit while keeping existing query params" do
    results = result_service.list(user_id: "user-1", limit: 1)

    results_request = requests.find { |r| r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/line_items/42/results?foo=bar&user_id=user-1&limit=1")

    expect(results.length).to eq(1)
    expect(results.first.user_id).to eq("user-1")
    expect(results.first.result_score).to eq(0.5)
    expect(results.first.result_maximum).to eq(1) # default when omitted
  end

  it "returns an empty array when filtering by user_id and no result exists" do
    empty_user_filter_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&user_id=user-missing"
        ResultServiceResponseWithLink.new("200", [].to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: empty_user_filter_http
    )

    results = described_class.new(service_client: client).list(user_id: "user-missing")
    expect(results).to eq([])
  end

  it "follows Link rel=next to fetch all pages when using list_all" do
    results = result_service.list_all(limit: 1)

    results_urls = requests.select { |r| r[:url].include?("/results") }.map { |r| r[:url] }
    expect(results_urls).to eq(
      [
        "https://platform.example/line_items/42/results?foo=bar&limit=1",
        "https://platform.example/line_items/42/results?page=2"
      ]
    )

    expect(results.map(&:user_id)).to eq(%w[user-1 user-2])
    expect(results.map(&:result_score)).to eq([0.1, 0.2])
  end

  it "resolves relative next links against the result request URL" do
    relative_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: relative_link_http
    )

    results = described_class.new(service_client: client).list_all(limit: 1)
    expect(results.map(&:user_id)).to eq(%w[user-1 user-2])
  end

  it "rejects next links hosted on a different origin by default" do
    cross_origin_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://cdn.platform.example/line_items/42/results?page=2>; rel="next")
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: cross_origin_link_http
    )

    expect do
      described_class.new(service_client: client).list_all(limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /different origin/)
  end

  it "allows next links hosted on an allowlisted origin" do
    allowlisted_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://cdn.platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://cdn.platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://cdn.platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: allowlisted_link_http,
      allowed_origins: ["https://cdn.platform.example"]
    )

    results = described_class.new(service_client: client).list_all(limit: 1)
    expect(results.map(&:user_id)).to eq(%w[user-1 user-2])
  end

  it "raises when the Link header is malformed" do
    malformed_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          "<https://platform.example/line_items/42/results?page=2; rel=\"next\""
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: malformed_link_http
    )

    expect do
      described_class.new(service_client: client).list_all(limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /Malformed AGS Link header/)
  end

  it "raises when the launch is missing the result.readonly scope" do
    missing_scope_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => lineitem_url,
          "scope" => [Lti::Advantage::AGS::Endpoint::SCORE_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    missing_scope_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: missing_scope_launch,
      key_pair: key_pair,
      http_request: http_request
    )

    expect do
      described_class.new(service_client: missing_scope_client).list
    end.to raise_error(Lti::Advantage::AuthorizationError, /scope/)
  end

  it "returns an empty array when the platform returns an empty body" do
    empty_body_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new("200", "", nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    empty_body_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: empty_body_http
    )

    results = described_class.new(service_client: empty_body_client).list
    expect(results).to eq([])
  end

  it "raises when the result container response is not an array" do
    object_body_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new("200", { "unexpected" => true }.to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    object_body_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: object_body_http
    )

    expect do
      described_class.new(service_client: object_body_client).list
    end.to raise_error(Lti::Advantage::ServiceError, /JSON array/)
  end

  it "raises when user_id filtering returns more than one result" do
    multi_user_filter_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&user_id=user-1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            },
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    multi_user_filter_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: multi_user_filter_http
    )

    expect do
      described_class.new(service_client: multi_user_filter_client).list(user_id: "user-1")
    end.to raise_error(Lti::Advantage::ServiceError, /more than one result/i)
  end

  it "raises when paginated user_id filtering returns more than one total result" do
    multi_page_user_filter_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&user_id=user-1&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: multi_page_user_filter_http
    )

    expect do
      described_class.new(service_client: client).list_all(user_id: "user-1", limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /more than one result/i)
  end

  it "parses Link rel='next' with single quotes" do
    single_quote_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel='next')
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: single_quote_link_http
    )

    results = described_class.new(service_client: client).list_all(limit: 1)
    expect(results.map(&:user_id)).to eq(%w[user-1 user-2])
  end

  it "chooses the next link when multiple Link relations exist" do
    multi_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          [
            '<https://platform.example/line_items/42/results?page=3>; rel="last"',
            '<https://platform.example/line_items/42/results?page=2>; rel="next"'
          ].join(", ")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: multi_link_http
    )

    results = described_class.new(service_client: client).list_all(limit: 1)
    expect(results.map(&:user_id)).to eq(%w[user-1 user-2])
  end

  it "parses next link when a non-rel quoted parameter contains commas" do
    quoted_comma_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next"; title="page, two")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new("200", [].to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: quoted_comma_link_http
    )

    page = described_class.new(service_client: client).list_page(limit: 1)
    expect(page[:next_url]).to eq("https://platform.example/line_items/42/results?page=2")
  end

  it "derives /results correctly when the lineitem url ends with a trailing slash" do
    slash_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => "https://platform.example/line_items/42/?foo=bar",
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    slash_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new("200", [].to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: slash_launch,
      key_pair: key_pair,
      http_request: slash_http
    )

    described_class.new(service_client: client).list
    results_request = requests.find { |r| r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/line_items/42/results?foo=bar")
  end

  it "preserves multiple existing query parameters when adding filters" do
    multi_query_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => "https://platform.example/line_items/42?foo=bar&baz=qux",
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    multi_query_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&baz=qux&user_id=user-1&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: multi_query_launch,
      key_pair: key_pair,
      http_request: multi_query_http
    )

    described_class.new(service_client: client).list(user_id: "user-1", limit: 1)
    results_request = requests.find { |r| r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/line_items/42/results?foo=bar&baz=qux&user_id=user-1&limit=1")
  end

  it "preserves repeated query parameters when adding filters" do
    repeated_query_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => "https://platform.example/line_items/42?foo=bar&foo=baz&qux=1",
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    repeated_query_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&foo=baz&qux=1&user_id=user-1&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: repeated_query_launch,
      key_pair: key_pair,
      http_request: repeated_query_http
    )

    described_class.new(service_client: client).list(user_id: "user-1", limit: 1)
    results_request = requests.find { |r| r[:url].include?("/results") }
    expect(results_request[:url]).to eq(
      "https://platform.example/line_items/42/results?foo=bar&foo=baz&qux=1&user_id=user-1&limit=1"
    )
  end

  it "raises ServiceError when a result entry is not an object" do
    invalid_item_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new("200", ["not-an-object"].to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: invalid_item_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::ServiceError, /invalid result at index 0/i)
  end

  it "raises when result media type is not resultcontainer+json" do
    wrong_type_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLinkAndType.new(
          "200",
          [].to_json,
          nil,
          "application/json"
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: wrong_type_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::ServiceError, /resultcontainer\+json/)
  end

  it "accepts result media type with parameters (e.g., charset)" do
    typed_with_params_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLinkAndType.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.83
            }
          ].to_json,
          nil,
          "#{described_class::RESULT_CONTAINER_TYPE}; charset=utf-8"
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: typed_with_params_http
    )

    results = described_class.new(service_client: client).list
    expect(results.length).to eq(1)
    expect(results.first.user_id).to eq("user-1")
    expect(results.first.result_score).to eq(0.83)
  end

  it "raises when result media type header is missing" do
    missing_type_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLinkAndType.new("200", [].to_json, nil, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: missing_type_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::ServiceError, /Content-Type|resultcontainer\+json/)
  end

  it "raises when scoreOf does not match the resolved line item URL" do
    mismatch_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/999",
              "userId" => "user-1",
              "resultScore" => 0.9
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: mismatch_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::ValidationError, /scoreOf is not equal to line item/)
  end

  it "accepts scoreOf matching line item after normalization" do
    normalized_match_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42/?source=gradebook#fragment",
              "userId" => "user-1",
              "resultScore" => 0.9
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: normalized_match_http
    )

    results = described_class.new(service_client: client).list
    expect(results.length).to eq(1)
    expect(results.first.score_of).to include("/line_items/42/")
  end

  it "returns next_url nil when Link header is blank" do
    blank_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResultServiceResponseWithLink.new("200", [].to_json, "   ")
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: blank_link_http
    )

    page = described_class.new(service_client: client).list_page
    expect(page[:next_url]).to be_nil
  end

  it "parses Link rel=NEXT case-insensitively" do
    uppercase_rel_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="NEXT")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new("200", [].to_json, nil)
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: uppercase_rel_http
    )

    page = described_class.new(service_client: client).list_page(limit: 1)
    expect(page[:next_url]).to eq("https://platform.example/line_items/42/results?page=2")
  end

  it "uses page_url directly in list_page without rebuilding the endpoint URL" do
    page_url_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/paginated/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: page_url_http
    )

    described_class.new(service_client: client).list_page(
      page_url: "https://platform.example/paginated/results?page=2"
    )

    results_request = requests.find { |r| r[:method] == :get && r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/paginated/results?page=2")
  end

  it "uses explicit line_item_url for endpoint and scoreOf validation" do
    override_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/777/results?foo=bar"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/777/results/1",
              "scoreOf" => "https://platform.example/line_items/777",
              "userId" => "user-1",
              "resultScore" => 0.7
            }
          ].to_json,
          nil
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: override_http
    )

    results = described_class.new(service_client: client).list(
      line_item_url: "https://platform.example/line_items/777?foo=bar"
    )

    results_request = requests.find { |r| r[:method] == :get && r[:url].include?("/results") }
    expect(results_request[:url]).to eq("https://platform.example/line_items/777/results?foo=bar")
    expect(results.length).to eq(1)
    expect(results.first.score_of).to eq("https://platform.example/line_items/777")
  end

  it "detects pagination cycles in list_all" do
    cycle_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        ResultServiceResponse.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.1
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResultServiceResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/2",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-2",
              "resultScore" => 0.2
            }
          ].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      else
        ResultServiceResponse.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: cycle_http
    )

    expect do
      described_class.new(service_client: client).list_all(limit: 1)
    end.to raise_error(Lti::Advantage::ServiceError, /cycle/i)
  end
end
