# frozen_string_literal: true

RSpec.describe Lti::Advantage::OIDC::LoginInitiation do
  it "requires iss, login_hint, and target_link_uri" do
    expect do
      described_class.new("iss" => "https://platform.example")
    end.to raise_error(Lti::Advantage::ValidationError, /login_hint, target_link_uri/)
  end

  it "accepts string or symbol keys and exposes parameter readers" do
    login = described_class.new(
      iss: "https://platform.example",
      login_hint: "opaque-login-hint",
      target_link_uri: "https://tool.example/lti/launch",
      client_id: "client-123"
    )

    expect(login.issuer).to eq("https://platform.example")
    expect(login.login_hint).to eq("opaque-login-hint")
    expect(login.target_link_uri).to eq("https://tool.example/lti/launch")
    expect(login.client_id).to eq("client-123")
  end
end
