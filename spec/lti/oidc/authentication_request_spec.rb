# frozen_string_literal: true

require "uri"

RSpec.describe Lti::Advantage::OIDC::AuthenticationRequest do
  it "serializes required OpenID and LTI parameters into a URL" do
    request = described_class.new(
      authorization_endpoint: "https://platform.example/oidc/auth",
      client_id: "client-123",
      redirect_uri: "https://tool.example/lti/launch",
      login_hint: "opaque-login-hint",
      state: "state-123",
      nonce: "nonce-456",
      target_link_uri: "https://tool.example/lti/launch"
    )

    params = URI.decode_www_form(URI(request.url).query).to_h

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
end
