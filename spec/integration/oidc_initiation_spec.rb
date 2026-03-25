# frozen_string_literal: true

require "spec_helper"
require "json"
require "jwt"
require "openssl"
require_relative "../../demo/app" # Require the demo app for integration testing

PLATFORM_PRIVATE_KEY = OpenSSL::PKey::RSA.generate(2048)
PLATFORM_JWK = JWT::JWK.new(PLATFORM_PRIVATE_KEY.public_key, kid: "platform-kid")

RSpec.describe "OIDC Login Initiation Integration", type: :request do
  def app
    Sinatra::Application
  end

  def extract_hidden_value(name)
    last_response.body[/name="#{name}" value="([^"]+)"/, 1]
  end

  def stub_platform_jwks
    response = instance_double("Net::HTTPOK", body: { keys: [PLATFORM_JWK.export] }.to_json, code: "200")
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:get_response).and_return(response)
  end

  def base_launch_payload(nonce:, nrps_claim: nil)
    payload = {
      "iss" => ENV["LMS_ISSUER"] || "http://127.0.0.1:3000",
      "aud" => [ENV["CLIENT_ID"] || "10000000000001"],
      "azp" => ENV["CLIENT_ID"] || "10000000000001",
      "exp" => Time.now.to_i + 300,
      "iat" => Time.now.to_i,
      "nonce" => nonce,
      "sub" => "user-123",
      Lti::Advantage::Claims::MESSAGE_TYPE => "LtiResourceLinkRequest",
      Lti::Advantage::Claims::VERSION => "1.3.0",
      Lti::Advantage::Claims::DEPLOYMENT_ID => ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123",
      Lti::Advantage::Claims::TARGET_LINK_URI => "http://127.0.0.1:4567/lti/launch",
      Lti::Advantage::Claims::RESOURCE_LINK => { "id" => "resource-42" },
      Lti::Advantage::Claims::ROLES => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
      ]
    }
    payload[Lti::Advantage::Launch::NRPS_CLAIM] = nrps_claim if nrps_claim
    payload
  end

  def launch_with_optional_nrps(memberships_url: nil)
    post "/oidc/init", valid_params

    state = extract_hidden_value("state")
    nonce = extract_hidden_value("nonce")
    stub_platform_jwks

    nrps_claim = if memberships_url
                   {
                     "context_memberships_url" => memberships_url,
                     "service_versions" => ["2.0"]
                   }
                 end

    id_token = JWT.encode(
      base_launch_payload(nonce: nonce, nrps_claim: nrps_claim),
      PLATFORM_PRIVATE_KEY,
      "RS256",
      kid: "platform-kid"
    )

    post "/lti/launch", { id_token: id_token, state: state }
  end

  let(:valid_params) { TestFactories.create_lti_params }

  before do
    header "Host", "127.0.0.1"
  end

  it "responds with success for valid initiation parameters" do
    post "/oidc/init", valid_params

    expect(last_response).to be_ok
    expect(last_response.body).to include("form")
    expect(last_response.body).to include("state")
    expect(last_response.body).to include("nonce")
  end

  it "returns a 400 error for missing parameters" do
    post("/oidc/init", valid_params.reject { |k| k == :iss })

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("Missing required login initiation params")
  end

  it "validates a launch end-to-end through the demo app" do
    launch_with_optional_nrps

    expect(last_response).to be_ok
    expect(last_response.body).to include("Launch successful")
    expect(last_response.body).to include("did not include the NRPS claim")
  end

  it "completes the NRPS happy path through launch, token, and memberships fetch" do
    memberships_url = "https://lms.example.com/sections/2923/memberships"
    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(last_response).to be_ok
    expect(last_response.body).to include("NRPS memberships are available")

    allow(Faraday).to receive(:post).and_return(
      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    )

    allow(Faraday).to receive(:get).and_return(
      double(
        "memberships_resp",
        success?: true,
        body: {
          "id" => memberships_url,
          "context" => { "id" => "ctx-1", "title" => "Roster Demo" },
          "members" => [
            {
              "user_id" => "user-123",
              "name" => "Jane Doe",
              "email" => "jane@example.edu",
              "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"],
              "status" => "Active"
            }
          ]
        }.to_json,
        headers: {
          "link" => "",
          "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
        }
      )
    )

    get "/nrps/members", { role: "Learner", limit: "10" }

    expect(last_response).to be_ok
    body = JSON.parse(last_response.body)
    expect(body.fetch("context").fetch("title")).to eq("Roster Demo")
    expect(body.fetch("members").length).to eq(1)
    expect(body.fetch("members").first.fetch("user_id")).to eq("user-123")
    expect(body.fetch("members").first.fetch("roles")).to include(
      "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
    )
    expect(body.fetch("next_page_path")).to be_nil
    expect(body.fetch("differences_path")).to be_nil
  end

  it "requires a completed launch before fetching memberships" do
    get "/nrps/members"

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("Complete an LTI launch first")
  end

  it "returns 400 when limit is not an integer" do
    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    get "/nrps/members", { limit: "abc" }

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("limit must be an integer")
  end

  it "rejects raw page_url follow-up requests from the browser" do
    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    expect(Faraday).not_to receive(:post)
    expect(Faraday).not_to receive(:get)

    get "/nrps/members", { page_url: "https://attacker.example/steal-token" }

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("page_url cannot be supplied directly")
  end

  it "rejects invalid follow-up cursors before requesting a token" do
    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    expect(Faraday).not_to receive(:post)
    expect(Faraday).not_to receive(:get)

    get "/nrps/members", { cursor: "invalid-cursor" }

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("Invalid or expired NRPS cursor")
  end

  it "returns 500 when access token exchange fails" do
    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    allow(Faraday).to receive(:post).and_return(double("token_resp", status: 401, body: "Unauthorized"))

    get "/nrps/members"

    expect(last_response.status).to eq(500)
    expect(last_response.body).to include("Failed to obtain access token")
  end

  it "returns 500 when memberships fetch fails" do
    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    allow(Faraday).to receive(:post).and_return(
      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    )
    allow(Faraday).to receive(:get).and_return(double("memberships_resp", success?: false, status: 500, body: "boom"))

    get "/nrps/members"

    expect(last_response.status).to eq(500)
    expect(last_response.body).to include("Failed to fetch memberships")
  end

  it "proxies next page URLs back through the tool route" do
    memberships_url = "https://lms.example.com/sections/2923/memberships"
    next_page_url = "#{memberships_url}?page=2"

    launch_with_optional_nrps(memberships_url: memberships_url)

    allow(Faraday).to receive(:post).and_return(
      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    )
    allow(Faraday).to receive(:get) do |url, &_block|
      if url == memberships_url
        double(
          "page_1",
          success?: true,
          body: {
            "id" => memberships_url,
            "context" => { "id" => "ctx-1", "title" => "Roster Demo" },
            "members" => [{ "user_id" => "user-123", "roles" => ["Learner"], "status" => "Active" }]
          }.to_json,
          headers: {
            "link" => "<#{next_page_url}>; rel=\"next\"",
            "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
          }
        )
      else
        double(
          "page_2",
          success?: true,
          body: {
            "id" => next_page_url,
            "context" => { "id" => "ctx-1", "title" => "Roster Demo" },
            "members" => [{ "user_id" => "user-456", "roles" => ["Learner"], "status" => "Active" }]
          }.to_json,
          headers: {
            "link" => "",
            "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
          }
        )
      end
    end

    get "/nrps/members"

    expect(last_response).to be_ok
    page_one = JSON.parse(last_response.body)
    expect(page_one.fetch("next_page_url")).to eq(next_page_url)
    expect(page_one.fetch("next_page_path")).to include("cursor=")
    expect(page_one.fetch("next_page_path")).not_to include("page_url=")

    get page_one.fetch("next_page_path")

    expect(last_response).to be_ok
    page_two = JSON.parse(last_response.body)
    expect(page_two.fetch("members").first.fetch("user_id")).to eq("user-456")

    get page_one.fetch("next_page_path")

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("Invalid or expired NRPS cursor")
  end

  it "clears stored follow-up cursors when a new launch succeeds" do
    memberships_url = "https://lms.example.com/sections/2923/memberships"
    next_page_url = "#{memberships_url}?page=2"

    launch_with_optional_nrps(memberships_url: memberships_url)

    allow(Faraday).to receive(:post).and_return(
      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    )
    allow(Faraday).to receive(:get).and_return(
      double(
        "page_1",
        success?: true,
        body: {
          "id" => memberships_url,
          "context" => { "id" => "ctx-1", "title" => "Roster Demo" },
          "members" => [{ "user_id" => "user-123", "roles" => ["Learner"], "status" => "Active" }]
        }.to_json,
        headers: {
          "link" => "<#{next_page_url}>; rel=\"next\"",
          "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
        }
      )
    )

    get "/nrps/members"
    stale_path = JSON.parse(last_response.body).fetch("next_page_path")

    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(Faraday).not_to receive(:post)
    expect(Faraday).not_to receive(:get)

    get stale_path

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("Invalid or expired NRPS cursor")
  end
end
