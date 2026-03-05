# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::KeyStore do
  let(:jwks_url) { "https://lms.example.com/jwks" }
  let(:clock_now) { 1_700_000_000 }
  let(:clock) { -> { clock_now } }

  subject { described_class.new(jwks_url, cache_ttl: 300, clock: clock) }

  it "fetches and returns keys" do
    response = instance_double(Faraday::Response, success?: true, body: { keys: [{ "kid" => "a" }] }.to_json)
    allow(Faraday).to receive(:get).with(jwks_url).and_return(response)

    expect(subject.keys).to eq([{ "kid" => "a" }])
  end

  it "uses cache for repeated keys calls within ttl" do
    response = instance_double(Faraday::Response, success?: true, body: { keys: [{ "kid" => "a" }] }.to_json)
    allow(Faraday).to receive(:get).with(jwks_url).and_return(response)

    subject.keys
    subject.keys

    expect(Faraday).to have_received(:get).with(jwks_url).once
  end

  it "does not fetch when kid is nil" do
    expect(subject.key_for_kid(nil)).to be_nil
  end

  it "refetches once when kid is not in cached jwks" do
    first_response = instance_double(Faraday::Response, success?: true, body: { keys: [{ "kid" => "old" }] }.to_json)
    second_response = instance_double(Faraday::Response, success?: true, body: { keys: [{ "kid" => "new" }] }.to_json)
    allow(Faraday).to receive(:get).with(jwks_url).and_return(first_response, second_response)

    expect(subject.key_for_kid("new")).to eq({ "kid" => "new" })
    expect(Faraday).to have_received(:get).with(jwks_url).twice
  end

  it "raises when jwks response does not include keys array" do
    response = instance_double(Faraday::Response, success?: true, body: { not_keys: [] }.to_json)
    allow(Faraday).to receive(:get).with(jwks_url).and_return(response)

    expect { subject.keys }.to raise_error(Lti::Advantage::Error, /missing keys array/)
  end
end
