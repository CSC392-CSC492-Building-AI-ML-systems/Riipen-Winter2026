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
      "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiResourceLinkRequest"
    }
  end

  let(:token) { JWT.encode(payload, private_key, "RS256", { kid: key_id }) }
  subject { described_class.new(token) }

  it "extracts the user_id correctly" do
    expect(subject.user_id).to eq("user-123")
  end

  it "identifies a resource launch" do
    expect(subject.resource_launch?).to be true
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
end
