# frozen_string_literal: true

require "spec_helper"
require_relative "../../demo/app" # Require the demo app for integration testing

RSpec.describe "OIDC Login Initiation Integration", type: :request do
  def app
    Sinatra::Application
  end

  let(:valid_params) { TestFactories.create_lti_params }

  it "responds with success for valid initiation parameters" do
    header "Host", "192.168.2.92:4567"
    post "/oidc/init", valid_params
    expect(last_response).to be_ok
    expect(last_response.body).to include("form")
    expect(last_response.body).to include("state")
  end

  it "returns a 400 error for missing parameters" do
    header "Host", "192.168.2.92:4567"
    post "/oidc/init", valid_params.reject { |k| k == :iss }
    expect(last_response.status).to eq(400)
    expect(last_response.body).to include("iss (issuer) is missing")
  end
end
