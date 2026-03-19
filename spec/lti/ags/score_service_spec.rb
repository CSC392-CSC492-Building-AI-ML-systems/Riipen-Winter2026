# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::AGS::ScoreService do
  Response = Struct.new(:code, :body)

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
          "lineitem" => "https://platform.example/line_items/42",
          "scope" => [Lti::Advantage::AGS::Endpoint::SCORE_SCOPE]
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
      when "https://platform.example/line_items/42/scores"
        Response.new("201", "")
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

  subject(:score_service) { described_class.new(service_client: service_client) }

  it "requests an OAuth token and posts a score with AGS headers" do
    score_service.publish(
      score: {
        user_id: "user-123",
        timestamp: "2026-03-11T20:10:06.123Z",
        activity_progress: "Completed",
        grading_progress: "FullyGraded",
        score_given: 9,
        score_maximum: 10
      }
    )

    expect(requests.size).to eq(2)

    token_request = requests[0]
    token_form = URI.decode_www_form(token_request[:body]).to_h
    expect(token_request[:url]).to eq("https://platform.example/oauth2/token")
    expect(token_request[:headers]["Content-Type"]).to eq("application/x-www-form-urlencoded")
    expect(token_form).to include(
      "grant_type" => "client_credentials",
      "scope" => Lti::Advantage::AGS::Endpoint::SCORE_SCOPE,
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    )
    expect(token_form["client_assertion"]).not_to be_empty

    score_request = requests[1]
    score_body = JSON.parse(score_request[:body])
    expect(score_request[:url]).to eq("https://platform.example/line_items/42/scores")
    expect(score_request[:headers]["Authorization"]).to eq("Bearer token-123")
    expect(score_request[:headers]["Content-Type"]).to eq("application/vnd.ims.lis.v1.score+json")
    expect(score_body).to include(
      "userId" => "user-123",
      "activityProgress" => "Completed",
      "gradingProgress" => "FullyGraded",
      "scoreGiven" => 9,
      "scoreMaximum" => 10
    )
  end

  it "reuses the cached access token for repeated score publishes" do
    score_payload = {
      user_id: "user-123",
      timestamp: "2026-03-11T20:10:06.123Z",
      activity_progress: "Completed",
      grading_progress: "FullyGraded",
      score_given: 9,
      score_maximum: 10
    }

    score_service.publish(score: score_payload)
    score_service.publish(score: score_payload)

    token_requests = requests.count { |request| request[:url] == "https://platform.example/oauth2/token" }
    expect(token_requests).to eq(1)
  end

  it "raises when the launch is missing score scope" do
    readonly_launch = Lti::Advantage::Launch.new(
      payload: {
        Lti::Advantage::Claims::AGS_ENDPOINT => {
          "lineitem" => "https://platform.example/line_items/42",
          "scope" => [Lti::Advantage::AGS::Endpoint::RESULT_SCOPE]
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

    expect do
      described_class.new(service_client: readonly_client).publish(
        score: {
          user_id: "user-123",
          timestamp: "2026-03-11T20:10:06.123Z",
          activity_progress: "Completed",
          grading_progress: "FullyGraded"
        }
      )
    end.to raise_error(Lti::Advantage::AuthorizationError, /scope/)
  end
end
