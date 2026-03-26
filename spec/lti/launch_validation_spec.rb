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

  let(:ags_claim) do
    {
      "lineitems" => "https://platform.example/api/lti/courses/42/line_items",
      "lineitem" => "https://platform.example/api/lti/courses/42/line_items/5",
      "scope" => [
        Lti::Advantage::AGS::Endpoint::LINEITEM_SCOPE,
        Lti::Advantage::AGS::Endpoint::SCORE_SCOPE
      ]
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

  it "propagates both NRPS and AGS claim accessors from a validated launch" do
    payload = base_payload.merge(
      Lti::Advantage::Launch::NRPS_CLAIM => nrps_claim,
      Lti::Advantage::Claims::AGS_ENDPOINT => ags_claim
    )
    combined_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    launch = client.validate_launch!(id_token: combined_token, state: "state-123")

    expect(launch.nrps_available?).to be true
    expect(launch.ags_endpoint).not_to be_nil
    expect(launch.ags_endpoint.lineitems_url).to eq(ags_claim.fetch("lineitems"))
    expect(launch.ags_endpoint.lineitem_url).to eq(ags_claim.fetch("lineitem"))
  end

  it "rejects NRPS claims that are not objects" do
    payload = base_payload.merge(Lti::Advantage::Launch::NRPS_CLAIM => "not-an-object")
    malformed_nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_nrps_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /NRPS claim must be an object/)
  end

  it "rejects AGS endpoint claims that are not objects" do
    payload = base_payload.merge(Lti::Advantage::Claims::AGS_ENDPOINT => "not-an-object")
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS endpoint claim must be an object/)
  end

  it "rejects AGS endpoint claims with invalid lineitems URLs" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitems" => "/line_items",
        "scope" => [Lti::Advantage::AGS::Endpoint::LINEITEM_SCOPE]
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS lineitems/)
  end

  it "rejects AGS endpoint claims with invalid lineitem URLs" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => "/line_items/5",
        "scope" => [Lti::Advantage::AGS::Endpoint::SCORE_SCOPE]
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS lineitem/)
  end

  it "allows AGS endpoint claims with blank lineitem URLs when lineitems is present" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitems" => ags_claim.fetch("lineitems"),
        "lineitem" => "   ",
        "scope" => [Lti::Advantage::AGS::Endpoint::SCORE_SCOPE]
      }
    )
    blank_lineitem_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    launch = client.validate_launch!(id_token: blank_lineitem_token, state: "state-123")

    expect(launch.ags_endpoint).not_to be_nil
    expect(launch.ags_endpoint.lineitem_url).to be_nil
  end

  it "rejects AGS endpoint claims without scopes" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => ags_claim.fetch("lineitem")
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS scope must be present/)
  end

  it "rejects AGS endpoint claims with empty scopes" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => ags_claim.fetch("lineitem"),
        "scope" => []
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS scope must include at least one value/)
  end

  it "rejects AGS endpoint claims without any usable endpoints" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => "   ",
        "scope" => [Lti::Advantage::AGS::Endpoint::SCORE_SCOPE]
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /must include lineitems or lineitem/)
  end

  it "rejects AGS endpoint claims with non-array scopes" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => ags_claim.fetch("lineitem"),
        "scope" => Lti::Advantage::AGS::Endpoint::SCORE_SCOPE
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS scope must be an array/)
  end

  it "rejects AGS endpoint claims with blank scope entries" do
    payload = base_payload.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => {
        "lineitem" => ags_claim.fetch("lineitem"),
        "scope" => [" "]
      }
    )
    malformed_ags_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_ags_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError, /AGS scope entry at index 0 must be a non-empty string/)
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

  it "rejects NRPS claims with non-string service_versions entries" do
    payload = base_payload.merge(
      Lti::Advantage::Launch::NRPS_CLAIM => {
        "context_memberships_url" => nrps_claim.fetch("context_memberships_url"),
        "service_versions" => [2.0]
      }
    )
    malformed_nrps_token = JWT.encode(payload, private_key, "RS256", kid: "platform-kid")

    expect do
      client.validate_launch!(id_token: malformed_nrps_token, state: "state-123")
    end.to raise_error(Lti::Advantage::ValidationError,
                       /NRPS service_versions entry at index 0 must be a non-empty string/)
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
