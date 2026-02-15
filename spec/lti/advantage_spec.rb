# frozen_string_literal: true

RSpec.describe Lti::Advantage do
  it "has a version number" do
    expect(Lti::Advantage::VERSION).not_to be nil
  end

  it "defines an Error class" do
    expect(defined?(Lti::Advantage::Error)).to eq("constant")
  end
end
