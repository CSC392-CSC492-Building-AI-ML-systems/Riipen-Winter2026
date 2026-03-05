# frozen_string_literal: true

require "spec_helper"
require "openssl"

RSpec.describe Lti::Advantage::Message do
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:public_key) { private_key.public_key }
  let(:key_id) { "test-key-id" }
  
  # A mock "public key" in the format the LMS would provide
  let(:jwks_key) do
    {
      kty: "RSA",
      n: Base64.urlsafe_encode64(public_key.n.to_s(2), padding: false),
      e: Base64.urlsafe_encode64(public_key.e.to_s(2), padding: false),
      kid: key_id,
      alg: "RS256",
      use: "sig"
    }
  end

  let(:payload) do
    {
      iss: "https://canvas.instructure.com",
      aud: "my-client-id",
      sub: "user-123",
      exp: Time.now.to_i + 3600,
      iat: Time.now.to_i,
      nonce: "random-nonce",
      "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiResourceLinkRequest",
      "https://purl.imsglobal.org/spec/lti/claim/version": "1.3.0",
      "https://purl.imsglobal.org/spec/lti/claim/deployment_id": "test-deployment-123",
      "https://purl.imsglobal.org/spec/lti/claim/target_link_uri": "https://mytool.com/lti/launch",
      "https://purl.imsglobal.org/spec/lti/claim/resource_link": { id: "resource-1" }
    }
  end

  let(:token) { JWT.encode(payload, private_key, "RS256", { kid: key_id }) }
  subject { described_class.new(token) }

  it "extracts the user_id correctly" do
    expect(subject.user_id).to eq("user-123")
  end

  it "extracts the client_id correctly" do
    expect(subject.client_id).to eq("my-client-id")
  end

  it "extracts the deployment_id correctly" do
    expect(subject.deployment_id).to eq("test-deployment-123")
  end

  it "identifies a resource launch" do
    expect(subject.resource_launch?).to be true
  end

  it "extracts the key_id correctly" do
    expect(subject.key_id).to eq("test-key-id")
  end

  it "verifies a valid token" do
    expect {
      subject.verify!(
        keys: [jwks_key],
        client_id: "my-client-id",
        issuer: "https://canvas.instructure.com"
      )
    }.not_to raise_error
  end

  it "raises an error for an invalid issuer" do
    expect {
      subject.verify!(
        keys: [jwks_key],
        client_id: "my-client-id",
        issuer: "https://wrong-lms.com"
      )
    }.to raise_error(Lti::Advantage::Error, /Token verification failed/)
  end

  it "verifies a valid token with key_store and kid resolution" do
    key_store = instance_double(Lti::Advantage::KeyStore)
    allow(key_store).to receive(:key_for_kid).with("test-key-id").and_return(jwks_key)

    expect {
      subject.verify!(
        key_store: key_store,
        client_id: "my-client-id",
        issuer: "https://canvas.instructure.com"
      )
    }.not_to raise_error
  end

  it "validates launch nonce" do
    expect {
      subject.validate_nonce!(expected_nonce: "random-nonce")
    }.not_to raise_error
  end

  it "raises on nonce mismatch" do
    expect {
      subject.validate_nonce!(expected_nonce: "wrong-nonce")
    }.to raise_error(Lti::Advantage::Error, /nonce mismatch/)
  end

  it "validates required resource launch claims" do
    expect {
      subject.validate_resource_link_launch!(
        expected_deployment_id: "test-deployment-123",
        expected_target_link_uri: "https://mytool.com/lti/launch"
      )
    }.not_to raise_error
  end

  it "raises when deployment_id does not match" do
    expect {
      subject.validate_resource_link_launch!(
        expected_deployment_id: "another-deployment",
        expected_target_link_uri: "https://mytool.com/lti/launch"
      )
    }.to raise_error(Lti::Advantage::Error, /deployment_id mismatch/)
  end

  it "verifies token when aud is an array containing client_id" do
    aud_array_payload = payload.merge(aud: ["other-client", "my-client-id"])
    aud_array_token = JWT.encode(aud_array_payload, private_key, "RS256", { kid: key_id })
    aud_array_message = described_class.new(aud_array_token)

    expect {
      aud_array_message.verify!(
        keys: [jwks_key],
        client_id: "my-client-id",
        issuer: "https://canvas.instructure.com"
      )
    }.not_to raise_error
  end

  it "raises for expired token" do
    expired_payload = payload.merge(exp: Time.now.to_i - 60)
    expired_token = JWT.encode(expired_payload, private_key, "RS256", { kid: key_id })
    expired_message = described_class.new(expired_token)

    expect {
      expired_message.verify!(
        keys: [jwks_key],
        client_id: "my-client-id",
        issuer: "https://canvas.instructure.com"
      )
    }.to raise_error(Lti::Advantage::Error, /Token verification failed/)
  end

  it "raises when key_store verification token has no kid" do
    no_kid_token = JWT.encode(payload, private_key, "RS256")
    no_kid_message = described_class.new(no_kid_token)
    key_store = instance_double(Lti::Advantage::KeyStore)

    expect {
      no_kid_message.verify!(
        key_store: key_store,
        client_id: "my-client-id",
        issuer: "https://canvas.instructure.com"
      )
    }.to raise_error(Lti::Advantage::Error, /missing kid header/)
  end

  it "raises when message_type is not resource link" do
    deep_link_payload = payload.merge(
      "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiDeepLinkingRequest"
    )
    deep_link_token = JWT.encode(deep_link_payload, private_key, "RS256", { kid: key_id })
    deep_link_message = described_class.new(deep_link_token)

    expect {
      deep_link_message.validate_resource_link_launch!(
        expected_deployment_id: "test-deployment-123",
        expected_target_link_uri: "https://mytool.com/lti/launch"
      )
    }.to raise_error(Lti::Advantage::Error, /message_type must be LtiResourceLinkRequest/)
  end

  it "raises when version is not 1.3.0" do
    wrong_version_payload = payload.merge("https://purl.imsglobal.org/spec/lti/claim/version": "1.2.0")
    wrong_version_token = JWT.encode(wrong_version_payload, private_key, "RS256", { kid: key_id })
    wrong_version_message = described_class.new(wrong_version_token)

    expect {
      wrong_version_message.validate_resource_link_launch!(
        expected_deployment_id: "test-deployment-123",
        expected_target_link_uri: "https://mytool.com/lti/launch"
      )
    }.to raise_error(Lti::Advantage::Error, /version must be 1.3.0/)
  end

  it "allows anonymous launch when configured" do
    anonymous_payload = payload.merge(sub: nil)
    anonymous_token = JWT.encode(anonymous_payload, private_key, "RS256", { kid: key_id })
    anonymous_message = described_class.new(anonymous_token)

    expect {
      anonymous_message.validate_resource_link_launch!(
        expected_deployment_id: "test-deployment-123",
        expected_target_link_uri: "https://mytool.com/lti/launch",
        allow_anonymous: true
      )
    }.not_to raise_error
  end
end
