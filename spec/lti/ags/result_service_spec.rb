# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::AGS::ResultService do
  Response = Struct.new(:code, :body)
  ResponseWithLink = Struct.new(:code, :body, :link_header)

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
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_SCOPE]
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
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResponseWithLink.new(
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
        ResponseWithLink.new(
          "200",
          [
            {
              "id" => "https://platform.example/line_items/42/results/1",
              "scoreOf" => "https://platform.example/line_items/42",
              "userId" => "user-1",
              "resultScore" => 0.5
              # resultMaximum omitted -> default 1
            }
          ].to_json,
          nil
        )
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResponseWithLink.new(
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
        ResponseWithLink.new(
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
        Response.new("404", "not found")
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
      "scope" => Lti::Advantage::AGS::Endpoint::RESULT_SCOPE,
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
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResponseWithLink.new("200", "", nil)
      else
        Response.new("404", "not found")
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

  it "treats a non-array JSON response as empty (container must be an array)" do
    object_body_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResponseWithLink.new("200", { "unexpected" => true }.to_json, nil)
      else
        Response.new("404", "not found")
      end
    end

    object_body_client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: object_body_http
    )

    results = described_class.new(service_client: object_body_client).list
    expect(results).to eq([])
  end

  it "raises when user_id filtering returns more than one result" do
    multi_user_filter_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&user_id=user-1"
        ResponseWithLink.new(
          "200",
          [
            { "userId" => "user-1", "resultScore" => 0.1 },
            { "userId" => "user-1", "resultScore" => 0.2 }
          ].to_json,
          nil
        )
      else
        Response.new("404", "not found")
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

  it "parses Link rel='next' with single quotes" do
    single_quote_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResponseWithLink.new(
          "200",
          [{ "userId" => "user-1", "resultScore" => 0.1 }].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel='next')
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResponseWithLink.new("200", [{ "userId" => "user-2", "resultScore" => 0.2 }].to_json, nil)
      else
        Response.new("404", "not found")
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
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResponseWithLink.new(
          "200",
          [{ "userId" => "user-1", "resultScore" => 0.1 }].to_json,
          %(<https://platform.example/line_items/42/results?page=3>; rel="last", <https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResponseWithLink.new("200", [{ "userId" => "user-2", "resultScore" => 0.2 }].to_json, nil)
      else
        Response.new("404", "not found")
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

  it "derives /results correctly when the lineitem url ends with a trailing slash" do
    slash_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => "https://platform.example/line_items/42/?foo=bar",
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    slash_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResponseWithLink.new("200", [].to_json, nil)
      else
        Response.new("404", "not found")
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
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_SCOPE]
        }
      },
      header: {},
      registration: registration
    )

    multi_query_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&baz=qux&user_id=user-1&limit=1"
        ResponseWithLink.new("200", [{ "userId" => "user-1", "resultScore" => 0.1 }].to_json, nil)
      else
        Response.new("404", "not found")
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

  it "maps 403 responses to AuthorizationError" do
    forbidden_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        Response.new("403", "forbidden")
      else
        Response.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: forbidden_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::AuthorizationError)
  end

  it "maps 500 responses to ServiceError" do
    error_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        Response.new("500", "oops")
      else
        Response.new("404", "not found")
      end
    end

    client = Lti::Advantage::AGS::ServiceClient.new(
      launch: launch,
      key_pair: key_pair,
      http_request: error_http
    )

    expect do
      described_class.new(service_client: client).list
    end.to raise_error(Lti::Advantage::ServiceError)
  end

  it "returns next_url nil when Link header is blank" do
    blank_link_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar"
        ResponseWithLink.new("200", [].to_json, "   ")
      else
        Response.new("404", "not found")
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

  it "detects pagination cycles in list_all" do
    cycle_http = lambda do |method:, url:, headers:, body: nil|
      requests << { method: method, url: url, headers: headers, body: body }
      case url
      when "https://platform.example/oauth2/token"
        Response.new("200", { access_token: "token-123", token_type: "Bearer", expires_in: 3600 }.to_json)
      when "https://platform.example/line_items/42/results?foo=bar&limit=1"
        ResponseWithLink.new(
          "200",
          [{ "userId" => "user-1", "resultScore" => 0.1 }].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      when "https://platform.example/line_items/42/results?page=2"
        ResponseWithLink.new(
          "200",
          [{ "userId" => "user-2", "resultScore" => 0.2 }].to_json,
          %(<https://platform.example/line_items/42/results?page=2>; rel="next")
        )
      else
        Response.new("404", "not found")
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
