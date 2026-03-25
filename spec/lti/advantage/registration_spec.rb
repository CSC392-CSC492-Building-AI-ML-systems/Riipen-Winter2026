# frozen_string_literal: true

RSpec.describe Lti::Advantage::Registration do
  it "stores an optional token_endpoint" do
    registration = described_class.new(
      issuer: "https://platform.example",
      client_id: "client-123",
      authorization_endpoint: "https://platform.example/oidc/auth",
      jwks_url: "https://platform.example/.well-known/jwks.json",
      token_endpoint: "https://platform.example/login/oauth2/token",
      deployment_ids: ["deployment-123"]
    )

    expect(registration.token_endpoint).to eq("https://platform.example/login/oauth2/token")
  end

  it "allows token_endpoint to be omitted" do
    registration = described_class.new(
      issuer: "https://platform.example",
      client_id: "client-123",
      authorization_endpoint: "https://platform.example/oidc/auth",
      jwks_url: "https://platform.example/.well-known/jwks.json",
      deployment_ids: ["deployment-123"]
    )

    expect(registration.token_endpoint).to be_nil
  end

  it "rejects blank token_endpoint values" do
    expect do
      described_class.new(
        issuer: "https://platform.example",
        client_id: "client-123",
        authorization_endpoint: "https://platform.example/oidc/auth",
        jwks_url: "https://platform.example/.well-known/jwks.json",
        token_endpoint: "  ",
        deployment_ids: ["deployment-123"]
      )
    end.to raise_error(ArgumentError, /token_endpoint/)
  end

  it "rejects token_endpoint values that are not absolute HTTP(S) URLs" do
    expect do
      described_class.new(
        issuer: "https://platform.example",
        client_id: "client-123",
        authorization_endpoint: "https://platform.example/oidc/auth",
        jwks_url: "https://platform.example/.well-known/jwks.json",
        token_endpoint: "/login/oauth2/token",
        deployment_ids: ["deployment-123"]
      )
    end.to raise_error(ArgumentError, /absolute HTTP\(S\) URL/)
  end
end
