# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::Oidc::LoginInitiation do
  let(:params) do
    {
      iss: "https://canvas.instructure.com",
      login_hint: "12345",
      target_link_uri: "https://mytool.com/launch",
      lti_message_hint: "abcde"
    }
  end

  subject { described_class.new(params) }

  it "validates required parameters" do
    expect { subject.validate! }.not_to raise_error
  end

  it "raises an error if iss is missing" do
    invalid_params = params.merge(iss: nil)
    expect { described_class.new(invalid_params).validate! }.to raise_error(Lti::Advantage::Error, /iss/)
  end

  it "generates correct redirect parameters" do
    redirect_params = subject.redirect_params(
      client_id: "my-client-id",
      redirect_uri: "https://mytool.com/callback",
      state: "random-state",
      nonce: "random-nonce"
    )

    expect(redirect_params[:client_id]).to eq("my-client-id")
    expect(redirect_params[:login_hint]).to eq("12345")
    expect(redirect_params[:scope]).to eq("openid")
  end
end
