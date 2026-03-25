# frozen_string_literal: true

require "jwt"
require "openssl"

RSpec.describe "LTI launch validation" do
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(private_key.public_key, kid: "platform-kid") }
  let(:jwks_repository) { instance_double("JwksRepository", fetch: { "keys" => [jwk.export] }) }

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
    Lti::Advantage::Client.new(
      registrations: [registration],
      jwks_repository: jwks_repository,
      state_generator: -> { "state-123" },
      nonce_generator: -> { "nonce-456" }
    )
  end

  let(:login_params) do
    {
      "iss" => "https://platform.example",
      "login_hint" => "opaque-login-hint",
      "target_link_uri" => "https://tool.example/lti/launch",
      "lti_deployment_id" => "deployment-123"
    }
  end

  let(:base_payload) do
    {
      "iss" => "https://platform.example",
      "aud" => ["client-123"],
      "azp" => "client-123",
      "exp" => Time.now.to_i + 300,
      "iat" => Time.now.to_i,
      "nonce" => "nonce-456",
      "sub" => "user-123",
      Lti::Advantage::Claims::MESSAGE_TYPE => "LtiResourceLinkRequest",
      Lti::Advantage::Claims::VERSION => "1.3.0",
      Lti::Advantage::Claims::DEPLOYMENT_ID => "deployment-123",
      Lti::Advantage::Claims::TARGET_LINK_URI => "https://tool.example/lti/launch",
      Lti::Advantage::Claims::RESOURCE_LINK => { "id" => "resource-42" },
      Lti::Advantage::Claims::ROLES => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ]
    }
  end

  let(:nrps_claim) do
    {
      "context_memberships_url" => "https://platform.example/api/lti/courses/42/names_and_roles",
      "service_versions" => ["2.0"]
    }
  end

  let(:id_token) do
    JWT.encode(base_payload, private_key, "RS256", kid: "platform-kid")
  end

  before do
    client.authentication_request(
      login_params: login_params,
      redirect_uri: "https://tool.example/lti/launch"
    )
  end

  it "validates a signed id_token and exposes launch claims" do
    launch = client.validate_launch!(id_token: id_token, state: "state-123")

    expect(launch.message_type).to eq("LtiResourceLinkRequest")
    expect(launch.version).to eq("1.3.0")
    expect(launch.deployment_id).to eq("deployment-123")
    expect(launch.resource_link_id).to eq("resource-42")
    expect(launch.roles).to include("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")
  end

  it "propagates NRPS claim accessors from a validated launch" do
    payload = base_payload.merge(Lti::Advantage::Launch::NRPS_CLAIM => nrps_claim)
    nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    launch = client.validate_launch!(id_token: nrps_token, state: "state-123")

    expect(launch.nrps_claim).to eq(nrps_claim)
    expect(launch.context_memberships_url).to eq(nrps_claim.fetch("context_memberships_url"))
    expect(launch.nrps_service_versions).to eq(["2.0"])
    expect(launch.nrps_available?).to be true
  end

  it "rejects NRPS claims that are not objects" do
    payload = base_payload.merge(Lti::Advantage::Launch::NRPS_CLAIM => "not-an-object")
    malformed_nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_nrps_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /NRPS claim must be an object/)
  end

  it "rejects NRPS claims with invalid memberships URLs" do
    payload = base_payload.merge(
      Lti::Advantage::Launch::NRPS_CLAIM => {
        "context_memberships_url" => "/memberships",
        "service_versions" => ["2.0"]
      }
    )
    malformed_nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_nrps_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /NRPS context_memberships_url/)
  end

  it "rejects NRPS claims with invalid service_versions" do
    payload = base_payload.merge(
      Lti::Advantage::Launch::NRPS_CLAIM => {
        "context_memberships_url" => nrps_claim.fetch("context_memberships_url"),
        "service_versions" => "2.0"
      }
    )
    malformed_nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_nrps_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /NRPS service_versions must be an array/)
  end

  it "allows anonymous launches with no sub claim" do
    payload = base_payload.dup
    payload.delete("sub")
    anonymous_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    launch = client.validate_launch!(id_token: anonymous_token, state: "state-123")

    expect(launch.subject).to be_nil
  end

  it "rejects launches missing required LTI claims" do
    payload = base_payload.dup
    payload.delete(Lti::Advantage::Claims::DEPLOYMENT_ID)
    invalid_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: invalid_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /deployment_id/)
  end

  it "rejects empty deployment_id values" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::DEPLOYMENT_ID => ""
    )
    invalid_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: invalid_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /deployment_id/)
  end

  it "requires azp when aud contains multiple values" do
    payload = base_payload.merge("aud" => %w[client-123 other-client])
    payload.delete("azp")
    invalid_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: invalid_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /azp/)
  end

  it "rejects replayed state values" do
    client.validate_launch!(id_token: id_token, state: "state-123")

    expect do
      client.validate_launch!(id_token: id_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ReplayError, /state/)
  end

  it "rejects replayed nonce values" do
    client.validate_launch!(id_token: id_token, state: "state-123")

    client.state_store.write(
      "state-456",
      value: {
        issuer: registration.issuer,
        client_id: registration.client_id,
        target_link_uri: "https://tool.example/lti/launch",
        deployment_id: "deployment-123"
      },
      ttl: 300
    )

    expect do
      client.validate_launch!(id_token: id_token, state: "state-456")
    end.to raise_error(Lti::Advantage::ReplayError, /nonce/)
  end

  it "binds nonce to state and rejects nonce substitution" do
    client.state_store.write(
      "state-substitute",
      value: {
        issuer: registration.issuer,
        client_id: registration.client_id,
        target_link_uri: "https://tool.example/lti/launch",
        deployment_id: "deployment-123",
        nonce: "nonce-expected"
      },
      ttl: 300
    )
    client.nonce_store.write("nonce-expected", value: true, ttl: 300)
    client.nonce_store.write("nonce-other", value: true, ttl: 300)

    payload = base_payload.merge("nonce" => "nonce-other")
    substituted_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: substituted_token, state: "state-substitute")
    end.to raise_error(Lti::Advantage::ValidationError, /nonce/)
  end

  it "does not consume state when token verification fails" do
    attacker_key = OpenSSL::PKey::RSA.generate(2048)
    invalid_token = JWT.encode(base_payload, attacker_key, "RS256", kid: "unknown-kid")

    expect do
      client.validate_launch!(id_token: invalid_token, state: "state-123")
    end.to raise_error(Lti::Advantage::JwtVerificationError)

    launch = client.validate_launch!(id_token: id_token, state: "state-123")
    expect(launch.resource_link_id).to eq("resource-42")
  end
end
