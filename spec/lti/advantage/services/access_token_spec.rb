# frozen_string_literal: true

require "jwt"
require "uri"

RSpec.describe Lti::Advantage::Services::AccessToken do
  let(:key_pair) { Lti::Advantage::KeyPair.new }
  let(:client_id) { "tool-client-id-12345" }
  let(:token_endpoint) { "https://lms.example.com/login/oauth2/token" }
  let(:scope) { Lti::Advantage::Services::NamesRoleService::SCOPE }
  let(:deployment_id) { nil }

  subject do
    described_class.new(
      key_pair: key_pair,
      client_id: client_id,
      token_endpoint: token_endpoint,
      scope: scope,
      deployment_id: deployment_id
    )
  end

  describe "#fetch" do
    it "returns the access token string" do
      response_double = double(
        "resp",
        success?: true,
        body: { "access_token" => "lms-issued-token-xyz", "token_type" => "Bearer", "expires_in" => 3600 }.to_json
      )
      allow(Faraday).to receive(:post).and_return(response_double)

      expect(subject.fetch).to eq("lms-issued-token-xyz")
    end

    it "sends a form-encoded client_credentials request with a JWT assertion" do
      captured_headers = nil
      captured_body = nil
      response_double = double("resp", success?: true, body: { "access_token" => "tok" }.to_json)

      allow(Faraday).to receive(:post) do |_url, &block|
        headers = {}
        request = double("req")
        allow(request).to receive(:headers).and_return(headers)
        allow(request).to receive(:body=) { |value| captured_body = value }
        block.call(request)
        captured_headers = headers
        response_double
      end

      subject.fetch

      params = URI.decode_www_form(captured_body).to_h
      payload, header = JWT.decode(params.fetch("client_assertion"), nil, false)

      expect(captured_headers).to include("Content-Type" => "application/x-www-form-urlencoded")
      expect(params).to include(
        "grant_type" => "client_credentials",
        "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "scope" => scope
      )
      expect(payload).to include(
        "iss" => client_id,
        "sub" => client_id,
        "aud" => token_endpoint
      )
      expect(payload["exp"]).to be > payload["iat"]
      expect(payload["jti"]).to be_a(String)
      expect(header).to include("kid" => key_pair.kid, "alg" => "RS256")
    end

    context "when deployment_id is provided" do
      let(:deployment_id) { "deployment-123" }

      it "includes deployment_id in the JWT assertion" do
        captured_body = nil
        response_double = double("resp", success?: true, body: { "access_token" => "tok" }.to_json)

        allow(Faraday).to receive(:post) do |_url, &block|
          request = double("req")
          allow(request).to receive(:headers).and_return({})
          allow(request).to receive(:body=) { |value| captured_body = value }
          block.call(request)
          response_double
        end

        subject.fetch

        params = URI.decode_www_form(captured_body).to_h
        payload, = JWT.decode(params.fetch("client_assertion"), nil, false)
        expect(payload[Lti::Advantage::Claims::DEPLOYMENT_ID]).to eq("deployment-123")
      end
    end

    it "raises Lti::Advantage::Error on a non-200 response" do
      allow(Faraday).to receive(:post).and_return(
        double("resp", success?: false, status: 401, body: "Unauthorized")
      )

      expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /Token request failed.*401/)
    end

    it "raises Lti::Advantage::Error when the response is missing access_token" do
      allow(Faraday).to receive(:post).and_return(
        double("resp", success?: true, body: { "error" => "invalid_scope" }.to_json)
      )

      expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /No access_token/)
    end

    it "raises Lti::Advantage::Error on invalid JSON" do
      allow(Faraday).to receive(:post).and_return(
        double("resp", success?: true, body: "not json")
      )

      expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /Failed to parse access token response/)
    end

    it "raises Lti::Advantage::Error when a network error occurs" do
      allow(Faraday).to receive(:post).and_raise(Faraday::ConnectionFailed.new("refused"))

      expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /Network error/)
    end
  end
end
