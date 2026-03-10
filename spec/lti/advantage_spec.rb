# frozen_string_literal: true

RSpec.describe Lti::Advantage do
  it "has a version number" do
    expect(Lti::Advantage::VERSION).not_to be nil
  end

  it "exposes the core launch client" do
    expect(defined?(Lti::Advantage::Client)).to eq("constant")
  end

  it "keeps the tool key pair helper" do
    expect(defined?(Lti::Advantage::KeyPair)).to eq("constant")
  end
end
