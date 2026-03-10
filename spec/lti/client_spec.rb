# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::Client do
  let(:registration) do
    Lti::Advantage::Registration.new(
      issuer: "https://platform.example",
      client_id: "client-123",
      authorization_endpoint: "https://platform.example/oidc/auth",
      jwks_url: "https://platform.example/.well-known/jwks.json",
      deployment_ids: ["deployment-123"]
    )
  end

  let(:client) do
    described_class.new(
      registrations: [registration],
      state_generator: -> { "state-123" },
      nonce_generator: -> { "nonce-456" }
    )
  end

  it "requires at least one platform registration" do
    expect { described_class.new(registrations: []) }
      .to raise_error(ArgumentError, /registration/i)
  end

  it "builds a valid OIDC authentication request URL" do
    request = client.authentication_request(
      login_params: {
        "iss" => "https://platform.example",
        "login_hint" => "opaque-login-hint",
        "target_link_uri" => "https://tool.example/lti/launch"
      },
      redirect_uri: "https://tool.example/lti/launch"
    )

    uri = URI(request.url)
    params = URI.decode_www_form(uri.query).to_h

    expect(uri.scheme).to eq("https")
    expect(uri.host).to eq("platform.example")
    expect(uri.path).to eq("/oidc/auth")
    expect(params).to include(
      "response_type" => "id_token",
      "response_mode" => "form_post",
      "scope" => "openid",
      "prompt" => "none",
      "client_id" => "client-123",
      "redirect_uri" => "https://tool.example/lti/launch",
      "login_hint" => "opaque-login-hint",
      "state" => "state-123",
      "nonce" => "nonce-456",
      "target_link_uri" => "https://tool.example/lti/launch"
    )
  end

  it "returns lti_message_hint and lti_deployment_id unchanged when provided" do
    request = client.authentication_request(
      login_params: {
        iss: "https://platform.example",
        login_hint: "opaque-login-hint",
        target_link_uri: "https://tool.example/lti/launch",
        lti_message_hint: "opaque-message-hint",
        lti_deployment_id: "deployment-123"
      },
      redirect_uri: "https://tool.example/lti/launch"
    )

    params = URI.decode_www_form(URI(request.url).query).to_h

    expect(params["lti_message_hint"]).to eq("opaque-message-hint")
    expect(params["lti_deployment_id"]).to eq("deployment-123")
  end
end
