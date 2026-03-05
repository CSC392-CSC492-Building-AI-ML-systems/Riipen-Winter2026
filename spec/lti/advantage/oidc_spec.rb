# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::Oidc::LoginInitiation do
  let(:params) do
    {
      iss: "https://canvas.instructure.com",
      login_hint: "12345",
      target_link_uri: "https://mytool.com/launch",
      lti_message_hint: "abcde",
      lti_deployment_id: "deployment-1"
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

  it "raises an error if login_hint is blank" do
    invalid_params = params.merge(login_hint: "")
    expect { described_class.new(invalid_params).validate! }.to raise_error(Lti::Advantage::Error, /login_hint/)
  end

  it "raises an error if target_link_uri is blank" do
    invalid_params = params.merge(target_link_uri: "")
    expect { described_class.new(invalid_params).validate! }.to raise_error(Lti::Advantage::Error, /target_link_uri/)
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
    expect(redirect_params[:response_type]).to eq("id_token")
    expect(redirect_params[:response_mode]).to eq("form_post")
    expect(redirect_params[:state]).to eq("random-state")
    expect(redirect_params[:nonce]).to eq("random-nonce")
    expect(redirect_params[:prompt]).to eq("none")
    expect(redirect_params[:lti_message_hint]).to eq("abcde")
    expect(redirect_params[:lti_deployment_id]).to eq("deployment-1")
  end

  it "prefers client_id from initiation params when present" do
    client_bound_subject = described_class.new(params.merge(client_id: "platform-client-id"))

    redirect_params = client_bound_subject.redirect_params(
      client_id: "tool-default-client-id",
      redirect_uri: "https://mytool.com/callback",
      state: "random-state",
      nonce: "random-nonce"
    )

    expect(redirect_params[:client_id]).to eq("platform-client-id")
  end

  it "omits optional hints when not provided" do
    minimal_subject = described_class.new(
      iss: "https://canvas.instructure.com",
      login_hint: "12345",
      target_link_uri: "https://mytool.com/launch"
    )

    redirect_params = minimal_subject.redirect_params(
      client_id: "my-client-id",
      redirect_uri: "https://mytool.com/callback",
      state: "random-state",
      nonce: "random-nonce"
    )

    expect(redirect_params).not_to have_key(:lti_message_hint)
    expect(redirect_params).not_to have_key(:lti_deployment_id)
  end
end
