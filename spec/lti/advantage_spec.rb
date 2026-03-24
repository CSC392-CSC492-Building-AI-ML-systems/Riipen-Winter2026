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

  it "exposes AGS score and line item primitives" do
    expect(defined?(Lti::Advantage::AGS::Endpoint)).to eq("constant")
    expect(defined?(Lti::Advantage::AGS::LineItem)).to eq("constant")
    expect(defined?(Lti::Advantage::AGS::LineItemService)).to eq("constant")
    expect(defined?(Lti::Advantage::AGS::ScoreService)).to eq("constant")
  end
end
