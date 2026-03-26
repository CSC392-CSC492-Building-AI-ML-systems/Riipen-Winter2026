# frozen_string_literal: true

require "spec_helper"
require "json"
require "jwt"
require "openssl"
require "uri"
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

  def memberships_body(memberships_url:, members:, context: { "id" => "ctx-1", "title" => "Roster Demo" })
    {
      "id" => memberships_url,
      "context" => context,
      "members" => members
    }.to_json
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

  it "returns a single public JWK for Canvas manual configuration" do
    get "/lti/jwk"

    expect(last_response).to be_ok
    body = JSON.parse(last_response.body)
    expect(body.fetch("kty")).to eq("RSA")
    expect(body.fetch("alg")).to eq("RS256")
    expect(body.fetch("kid")).not_to be_empty
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
        body: memberships_body(
          memberships_url: memberships_url,
          members: [
            {
              "user_id" => "user-123",
              "name" => "Jane Doe",
              "email" => "jane@example.edu",
              "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"],
              "status" => "Active"
            }
          ]
        ),
        headers: {
          "link" => "",
          "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
        }
      )
    )

    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(last_response).to be_ok
    expect(last_response.body).to include("Launch successful")
    expect(last_response.body).to include("NRPS roster")
    expect(last_response.body).to include("Roster Demo")
    expect(last_response.body).to include("Jane Doe")
    expect(last_response.body).to include("jane@example.edu")
    expect(last_response.body).to include("Learner")
  end

  it "uses registration token_audience for the demo NRPS token exchange" do
    registration_with_audience = Lti::Advantage::Registration.new(
      issuer: LTI_REGISTRATION.issuer,
      client_id: LTI_REGISTRATION.client_id,
      authorization_endpoint: LTI_REGISTRATION.authorization_endpoint,
      jwks_url: LTI_REGISTRATION.jwks_url,
      token_endpoint: LTI_REGISTRATION.token_endpoint,
      token_audience: "https://canvas.docker/login/oauth2/token-audience",
      deployment_ids: LTI_REGISTRATION.deployment_ids,
      algorithms: LTI_REGISTRATION.algorithms
    )
    stub_const("LTI_REGISTRATION", registration_with_audience)
    stub_const("LTI_CLIENT", Lti::Advantage::Client.new(registrations: [registration_with_audience]))

    memberships_url = "https://lms.example.com/sections/2923/memberships"

    allow(Faraday).to receive(:post) do |url, &block|
      expect(url).to eq(registration_with_audience.token_endpoint)

      request = Struct.new(:headers, :body).new({}, nil)
      block.call(request)

      token_form = URI.decode_www_form(request.body).to_h
      token_payload, = JWT.decode(token_form.fetch("client_assertion"), nil, false)
      expect(token_payload["aud"]).to eq(registration_with_audience.token_audience)

      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    end

    allow(Faraday).to receive(:get).and_return(
      double(
        "memberships_resp",
        success?: true,
        body: memberships_body(
          memberships_url: memberships_url,
          members: [
            {
              "user_id" => "user-123",
              "name" => "Jane Doe",
              "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"],
              "status" => "Active"
            }
          ]
        ),
        headers: {
          "link" => "",
          "content-type" => Lti::Advantage::Services::NamesRoleService::MEDIA_TYPE
        }
      )
    )

    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(last_response).to be_ok
    expect(last_response.body).to include("NRPS roster")
  end

  it "renders an NRPS error when access token exchange fails" do
    allow(Faraday).to receive(:post).and_return(double("token_resp", status: 401, body: "Unauthorized"))

    expect(Faraday).not_to receive(:get)

    launch_with_optional_nrps(memberships_url: "https://lms.example.com/sections/2923/memberships")

    expect(last_response).to be_ok
    expect(last_response.body).to include("NRPS roster unavailable")
    expect(last_response.body).to include("Token request failed")
  end

  it "renders an NRPS error when memberships fetch fails" do
    memberships_url = "https://lms.example.com/sections/2923/memberships"

    allow(Faraday).to receive(:post).and_return(
      double(
        "token_resp",
        status: 200,
        body: { "access_token" => "roster-token", "token_type" => "Bearer" }.to_json
      )
    )
    allow(Faraday).to receive(:get).and_return(double("memberships_resp", success?: false, status: 500, body: "boom"))

    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(last_response).to be_ok
    expect(last_response.body).to include("NRPS roster unavailable")
    expect(last_response.body).to include("NRPS request failed")
  end

  it "notes when more NRPS pages are available" do
    memberships_url = "https://lms.example.com/sections/2923/memberships"
    next_page_url = "#{memberships_url}?page=2"

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
          body: memberships_body(
            memberships_url: memberships_url,
            members: [{ "user_id" => "user-123", "roles" => ["Learner"], "status" => "Active" }]
          ),
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

    launch_with_optional_nrps(memberships_url: memberships_url)

    expect(last_response).to be_ok
    expect(last_response.body).to include("renders only the first NRPS page during launch")
  end

  it "returns guidance for the legacy memberships endpoint" do
    get "/nrps/members"

    expect(last_response.status).to eq(410)
    expect(last_response.body).to include("fetches the first NRPS roster page during /lti/launch")
  end
end
