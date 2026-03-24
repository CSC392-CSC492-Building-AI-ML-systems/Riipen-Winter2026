# frozen_string_literal: true

RSpec.describe Lti::Advantage::Services::NamesRoleService do
  let(:memberships_url) { "https://lms.example.com/sections/2923/memberships" }
  let(:access_token) { "test-bearer-token-abc123" }

  subject do
    described_class.new(
      memberships_url: memberships_url,
      access_token: access_token
    )
  end

  def build_membership_body(members: [], context: nil)
    {
      "id" => memberships_url,
      "context" => context || { "id" => "ctx-1", "label" => "CPS 435", "title" => "CPS 435 Analytics" },
      "members" => members
    }
  end

  def jane_member
    {
      "user_id" => "user-jane",
      "status" => "Active",
      "name" => "Jane Doe",
      "given_name" => "Jane",
      "email" => "jane@example.edu",
      "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]
    }
  end

  def bob_member
    {
      "user_id" => "user-bob",
      "status" => "Active",
      "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"]
    }
  end

  describe "SCOPE" do
    it "is the correct NRPS readonly scope" do
      expect(described_class::SCOPE).to eq(
        "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
      )
    end
  end

  describe "MEDIA_TYPE" do
    it "is the NRPS v2 media type" do
      expect(described_class::MEDIA_TYPE).to eq(
        "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"
      )
    end
  end

  describe "#memberships" do
    it "sends authorization headers and returns parsed members" do
      captured_headers = nil
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body(members: [jane_member, bob_member]).to_json,
        headers: { "link" => nil }
      )

      allow(Faraday).to receive(:get) do |_url, &block|
        headers = {}
        request = double("req")
        allow(request).to receive(:headers).and_return(headers)
        block.call(request)
        captured_headers = headers
        response_double
      end

      result = subject.memberships

      expect(captured_headers).to include(
        "Authorization" => "Bearer #{access_token}",
        "Accept" => described_class::MEDIA_TYPE
      )
      expect(result).to be_a(described_class::MembershipsResult)
      expect(result.members.length).to eq(2)
      expect(result.members.first).to be_a(Lti::Advantage::Membership)
      expect(result.members.first.user_id).to eq("user-jane")
    end

    it "passes role, limit, and rlid query params" do
      captured_url = nil
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body(members: [jane_member]).to_json,
        headers: { "link" => "" }
      )

      allow(Faraday).to receive(:get) do |url, &_block|
        captured_url = url
        response_double
      end

      subject.memberships(role: "Instructor", limit: 10, resource_link_id: "link-99")

      expect(captured_url).to include("role=Instructor")
      expect(captured_url).to include("limit=10")
      expect(captured_url).to include("rlid=link-99")
    end

    it "merges query params with an existing memberships URL query string" do
      service = described_class.new(
        memberships_url: "https://lms.example.com/sections/2923/memberships?context_id=abc",
        access_token: access_token
      )
      captured_url = nil
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body.to_json,
        headers: { "link" => "" }
      )

      allow(Faraday).to receive(:get) do |url, &_block|
        captured_url = url
        response_double
      end

      service.memberships(limit: 25)

      expect(captured_url).to include("context_id=abc")
      expect(captured_url).to include("limit=25")
      expect(captured_url.scan("?").length).to eq(1)
    end

    it "raises an Error on a non-200 response" do
      allow(Faraday).to receive(:get).and_return(
        double("resp", success?: false, status: 401, body: "Unauthorized")
      )

      expect { subject.memberships }.to raise_error(Lti::Advantage::Error, /401/)
    end

    it "raises an Error on invalid JSON" do
      allow(Faraday).to receive(:get).and_return(
        double("resp", success?: true, body: "not json", headers: { "link" => "" })
      )

      expect { subject.memberships }.to raise_error(Lti::Advantage::Error, /parse/)
    end
  end

  describe "pagination via next_page_url" do
    it "exposes the next_page_url from the Link header" do
      next_url = "#{memberships_url}?p=2"
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body(members: [jane_member]).to_json,
        headers: { "link" => "<#{next_url}>; rel=\"next\"" }
      )
      allow(Faraday).to receive(:get).and_return(response_double)

      result = subject.memberships
      expect(result.next_page_url).to eq(next_url)
    end

    it "returns nil next_page_url when there are no more pages" do
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body(members: [jane_member]).to_json,
        headers: { "link" => "" }
      )
      allow(Faraday).to receive(:get).and_return(response_double)

      result = subject.memberships
      expect(result.next_page_url).to be_nil
    end

    it "exposes the differences_url from the Link header" do
      diff_url = "#{memberships_url}?since=1422554502"
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body.to_json,
        headers: { "link" => "<#{diff_url}>; rel=\"differences\"" }
      )
      allow(Faraday).to receive(:get).and_return(response_double)

      result = subject.memberships
      expect(result.differences_url).to eq(diff_url)
    end
  end

  describe "#all_members" do
    it "collects members across multiple pages" do
      page2_url = "#{memberships_url}?p=2"

      page1_resp = double(
        "resp1",
        success?: true,
        body: build_membership_body(members: [jane_member]).to_json,
        headers: { "link" => "<#{page2_url}>; rel=\"next\"" }
      )
      page2_resp = double(
        "resp2",
        success?: true,
        body: build_membership_body(members: [bob_member]).to_json,
        headers: { "link" => "" }
      )

      call_count = 0
      allow(Faraday).to receive(:get) do
        call_count += 1
        call_count == 1 ? page1_resp : page2_resp
      end

      members = subject.all_members

      expect(members.length).to eq(2)
      expect(members.map(&:user_id)).to match_array(%w[user-jane user-bob])
    end

    it "passes optional filters to the initial page request" do
      captured_url = nil
      response_double = double(
        "resp",
        success?: true,
        body: build_membership_body(members: [jane_member]).to_json,
        headers: { "link" => "" }
      )

      allow(Faraday).to receive(:get) do |url, &_block|
        captured_url = url
        response_double
      end

      subject.all_members(role: "Instructor", limit: 20, resource_link_id: "link-99")

      expect(captured_url).to include("role=Instructor")
      expect(captured_url).to include("limit=20")
      expect(captured_url).to include("rlid=link-99")
    end
  end
end
