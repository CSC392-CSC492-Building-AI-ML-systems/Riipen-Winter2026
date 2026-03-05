# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::NonceStore do
  let(:now) { 1_700_000_000 }
  let(:clock) { -> { now } }
  subject { described_class.new(clock: clock) }

  it "accepts a nonce the first time" do
    expect { subject.consume!("nonce-1", expires_at: now + 60) }.not_to raise_error
  end

  it "rejects replayed nonce before expiry" do
    subject.consume!("nonce-1", expires_at: now + 60)

    expect {
      subject.consume!("nonce-1", expires_at: now + 60)
    }.to raise_error(Lti::Advantage::Error, /nonce replay detected/)
  end

  it "allows nonce reuse after expiration" do
    subject.consume!("nonce-1", expires_at: now - 1)

    expect { subject.consume!("nonce-1", expires_at: now + 60) }.not_to raise_error
  end
end
