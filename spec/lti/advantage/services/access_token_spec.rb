# frozen_string_literal: true

require "spec_helper"
require "openssl"

RSpec.describe Lti::Advantage::Services::AccessToken do
  let(:key_pair)       { Lti::Advantage::KeyPair.new }
  let(:client_id)      { "tool-client-id-12345" }
  let(:token_endpoint) { "https://lms.example.com/login/oauth2/token" }
  let(:scope)          { Lti::Advantage::Services::NamesRoleService::SCOPE }

  subject do
    described_class.new(
      key_pair:       key_pair,
      client_id:      client_id,
      token_endpoint: token_endpoint,
      scope:          scope
    )
  end

  describe "#fetch" do
    context "when the LMS responds successfully" do
      it "returns the access token string" do
        response_double = double("resp",
          success?: true,
          body: { "access_token" => "lms-issued-token-xyz", "token_type" => "Bearer", "expires_in" => 3600 }.to_json
        )
        allow(Faraday).to receive(:post).and_return(response_double)

        token = subject.fetch
        expect(token).to eq("lms-issued-token-xyz")
      end

      it "sends a client_credentials grant_type" do
        captured_body = nil
        response_double = double("resp",
          success?: true,
          body: { "access_token" => "tok" }.to_json
        )
        allow(Faraday).to receive(:post) do |_url, &block|
          req = double("req", headers: {}).tap do |r|
            allow(r).to receive(:headers).and_return({})
            allow(r).to receive(:body=) { |b| captured_body = b }
          end
          block.call(req)
          response_double
        end

        subject.fetch
        expect(captured_body).to include("grant_type=client_credentials")
      end

      it "includes the requested scope" do
        captured_body = nil
        response_double = double("resp",
          success?: true,
          body: { "access_token" => "tok" }.to_json
        )
        allow(Faraday).to receive(:post) do |_url, &block|
          req = double("req").tap do |r|
            allow(r).to receive(:headers).and_return({})
            allow(r).to receive(:body=) { |b| captured_body = b }
          end
          block.call(req)
          response_double
        end

        subject.fetch
        expect(captured_body).to include(URI.encode_www_form_component(scope))
      end
    end

    context "when the LMS returns a non-200 response" do
      it "raises Lti::Advantage::Error" do
        allow(Faraday).to receive(:post).and_return(
          double("resp", success?: false, status: 401, body: "Unauthorized")
        )
        expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /Token request failed.*401/)
      end
    end

    context "when the response is missing access_token" do
      it "raises Lti::Advantage::Error" do
        allow(Faraday).to receive(:post).and_return(
          double("resp", success?: true, body: { "error" => "invalid_scope" }.to_json)
        )
        expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /No access_token/)
      end
    end

    context "when a network error occurs" do
      it "raises Lti::Advantage::Error" do
        allow(Faraday).to receive(:post).and_raise(Faraday::ConnectionFailed.new("refused"))
        expect { subject.fetch }.to raise_error(Lti::Advantage::Error, /Network error/)
      end
    end
  end
end