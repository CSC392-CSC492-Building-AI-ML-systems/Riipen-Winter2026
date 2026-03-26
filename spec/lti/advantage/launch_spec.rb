# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::Launch do
  let(:nrps_claim_data) do
    {
      "context_memberships_url" => "https://lms.example.com/2344/memberships",
      "service_versions" => ["2.0"]
    }
  end

  let(:payload_with_nrps) do
    {
      "sub" => "user-123",
      Lti::Advantage::Claims::MESSAGE_TYPE => "LtiResourceLinkRequest",
      Lti::Advantage::Claims::VERSION => "1.3.0",
      Lti::Advantage::Claims::DEPLOYMENT_ID => "deployment-123",
      Lti::Advantage::Claims::TARGET_LINK_URI => "https://tool.example/lti/launch",
      Lti::Advantage::Claims::RESOURCE_LINK => { "id" => "resource-42" },
      Lti::Advantage::Claims::ROLES => [],
      Lti::Advantage::Launch::NRPS_CLAIM => nrps_claim_data
    }
  end

  let(:ags_claim_data) do
    {
      "lineitems" => "https://lms.example.com/2344/line_items",
      "lineitem" => "https://lms.example.com/2344/line_items/42",
      "scope" => [
        Lti::Advantage::AGS::Endpoint::LINEITEM_SCOPE,
        Lti::Advantage::AGS::Endpoint::SCORE_SCOPE
      ]
    }
  end

  let(:payload_with_ags) do
    payload_without_nrps.merge(
      Lti::Advantage::Claims::AGS_ENDPOINT => ags_claim_data
    )
  end

  let(:payload_without_nrps) do
    payload_with_nrps.reject { |k, _| k == Lti::Advantage::Launch::NRPS_CLAIM }
  end

  let(:registration) do
    Lti::Advantage::Registration.new(
      issuer: "https://platform.example",
      client_id: "client-123",
      authorization_endpoint: "https://platform.example/oidc/auth",
      jwks_url: "https://platform.example/.well-known/jwks.json",
      deployment_ids: ["deployment-123"]
    )
  end

  describe "#nrps_claim" do
    it "returns the full NRPS claim hash when present" do
      launch = described_class.new(payload: payload_with_nrps, header: {}, registration: registration)
      expect(launch.nrps_claim).to eq(nrps_claim_data)
    end

    it "returns nil when the NRPS claim is absent" do
      launch = described_class.new(payload: payload_without_nrps, header: {}, registration: registration)
      expect(launch.nrps_claim).to be_nil
    end
  end

  describe "#context_memberships_url" do
    it "returns the memberships URL" do
      launch = described_class.new(payload: payload_with_nrps, header: {}, registration: registration)
      expect(launch.context_memberships_url).to eq("https://lms.example.com/2344/memberships")
    end

    it "returns nil when NRPS claim is absent" do
      launch = described_class.new(payload: payload_without_nrps, header: {}, registration: registration)
      expect(launch.context_memberships_url).to be_nil
    end
  end

  describe "#nrps_service_versions" do
    it "returns the supported versions array" do
      launch = described_class.new(payload: payload_with_nrps, header: {}, registration: registration)
      expect(launch.nrps_service_versions).to eq(["2.0"])
    end

    it "ignores non-string service version entries" do
      launch = described_class.new(
        payload: payload_with_nrps.merge(
          described_class::NRPS_CLAIM => nrps_claim_data.merge("service_versions" => ["2.0", 2.1, " "])
        ),
        header: {},
        registration: registration
      )

      expect(launch.nrps_service_versions).to eq(["2.0"])
    end

    it "returns an empty array when NRPS claim is absent" do
      launch = described_class.new(payload: payload_without_nrps, header: {}, registration: registration)
      expect(launch.nrps_service_versions).to eq([])
    end
  end

  describe "#nrps_available?" do
    it "returns true when the memberships URL is present and valid" do
      launch = described_class.new(payload: payload_with_nrps, header: {}, registration: registration)
      expect(launch.nrps_available?).to be true
    end

    it "does not depend on registration token endpoint availability" do
      registration_without_token_endpoint = Lti::Advantage::Registration.new(
        issuer: "https://platform.example",
        client_id: "client-123",
        authorization_endpoint: "https://platform.example/oidc/auth",
        jwks_url: "https://platform.example/.well-known/jwks.json",
        deployment_ids: ["deployment-123"]
      )

      launch = described_class.new(
        payload: payload_with_nrps,
        header: {},
        registration: registration_without_token_endpoint
      )

      expect(launch.nrps_available?).to be true
    end

    it "returns false when the memberships URL is blank" do
      launch = described_class.new(
        payload: payload_with_nrps.merge(
          described_class::NRPS_CLAIM => nrps_claim_data.merge("context_memberships_url" => "   ")
        ),
        header: {},
        registration: registration
      )

      expect(launch.context_memberships_url).to be_nil
      expect(launch.nrps_available?).to be false
    end

    it "returns false when the memberships URL is not an absolute HTTP(S) URL" do
      launch = described_class.new(
        payload: payload_with_nrps.merge(
          described_class::NRPS_CLAIM => nrps_claim_data.merge("context_memberships_url" => "/memberships")
        ),
        header: {},
        registration: registration
      )

      expect(launch.context_memberships_url).to be_nil
      expect(launch.nrps_available?).to be false
    end

    it "returns false when the platform does not advertise a supported NRPS version" do
      launch = described_class.new(
        payload: payload_with_nrps.merge(
          described_class::NRPS_CLAIM => nrps_claim_data.merge("service_versions" => ["1.0"])
        ),
        header: {},
        registration: registration
      )

      expect(launch.nrps_service_versions).to eq(["1.0"])
      expect(launch.nrps_available?).to be false
    end

    it "treats malformed NRPS claims as unavailable" do
      launch = described_class.new(
        payload: payload_with_nrps.merge(described_class::NRPS_CLAIM => "not-an-object"),
        header: {},
        registration: registration
      )

      expect(launch.nrps_claim).to be_nil
      expect(launch.context_memberships_url).to be_nil
      expect(launch.nrps_service_versions).to eq([])
      expect(launch.nrps_available?).to be false
    end

    it "returns false when the NRPS claim is absent" do
      launch = described_class.new(payload: payload_without_nrps, header: {}, registration: registration)
      expect(launch.nrps_available?).to be false
    end
  end

  describe "#ags_endpoint" do
    it "returns an endpoint wrapper when the AGS claim is present" do
      launch = described_class.new(payload: payload_with_ags, header: {}, registration: registration)

      expect(launch.ags_endpoint).to be_a(Lti::Advantage::AGS::Endpoint)
      expect(launch.ags_endpoint.lineitems_url).to eq("https://lms.example.com/2344/line_items")
      expect(launch.ags_endpoint.lineitem_url).to eq("https://lms.example.com/2344/line_items/42")
    end

    it "returns nil when the AGS claim is absent" do
      launch = described_class.new(payload: payload_without_nrps, header: {}, registration: registration)

      expect(launch.ags_endpoint).to be_nil
    end

    it "returns nil when the AGS claim is malformed" do
      launch = described_class.new(
        payload: payload_with_ags.merge(Lti::Advantage::Claims::AGS_ENDPOINT => "not-an-object"),
        header: {},
        registration: registration
      )

      expect(launch.ags_endpoint).to be_nil
    end
  end
end
