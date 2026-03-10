# frozen_string_literal: true

require "spec_helper"
require "json"
require "jwt"
require "openssl"
require_relative "../../demo/app" # Require the demo app for integration testing

RSpec.describe "OIDC Login Initiation Integration", type: :request do
  def app
    Sinatra::Application
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
    post "/oidc/init", valid_params

    state = last_response.body[/name="state" value="([^"]+)"/, 1]
    nonce = last_response.body[/name="nonce" value="([^"]+)"/, 1]

    private_key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(private_key.public_key, kid: "platform-kid")
    response = instance_double("Net::HTTPOK", body: { keys: [jwk.export] }.to_json, code: "200")
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:get_response).and_return(response)

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
    id_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    post "/lti/launch", { id_token: id_token, state: state }

    expect(last_response).to be_ok
    expect(last_response.body).to include("Launch successful")
  end
end
