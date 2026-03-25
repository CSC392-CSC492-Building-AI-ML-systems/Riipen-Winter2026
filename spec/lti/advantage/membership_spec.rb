# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lti::Advantage::Membership do
  let(:raw_member) do
    {
      "user_id" => "0ae836b9-7fc9-4060-006f-27b2066ac545",
      "status" => "Active",
      "name" => "Jane Q. Public",
      "picture" => "https://platform.example.edu/jane.jpg",
      "given_name" => "Jane",
      "family_name" => "Doe",
      "middle_name" => "Marie",
      "email" => "jane@platform.example.edu",
      "lis_person_sourcedid" => "59254-6782-12ab",
      "roles" => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ]
    }
  end

  subject { described_class.new(raw_member) }

  it "extracts user_id" do
    expect(subject.user_id).to eq("0ae836b9-7fc9-4060-006f-27b2066ac545")
  end

  it "extracts roles as an array" do
    expect(subject.roles).to eq(["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"])
  end

  it "extracts status" do
    expect(subject.status).to eq("Active")
  end

  it "extracts name, email, given_name, family_name" do
    expect(subject.name).to eq("Jane Q. Public")
    expect(subject.email).to eq("jane@platform.example.edu")
    expect(subject.given_name).to eq("Jane")
    expect(subject.family_name).to eq("Doe")
  end

  it "defaults status to Active when not specified" do
    member = described_class.new("user_id" => "abc", "roles" => [])
    expect(member.active?).to be true
  end

  it "identifies an active membership" do
    expect(subject.active?).to be true
    expect(subject.deleted?).to be false
  end

  it "identifies a deleted membership" do
    deleted = described_class.new(raw_member.merge("status" => "Deleted"))
    expect(deleted.deleted?).to be true
    expect(deleted.active?).to be false
  end

  describe "#has_role?" do
    it "matches a full role URI" do
      expect(subject.has_role?("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")).to be true
    end

    it "matches a short role name" do
      expect(subject.has_role?("Instructor")).to be true
    end

    it "returns false for a non-matching role" do
      expect(subject.has_role?("Learner")).to be false
    end
  end

  it "returns nil for consent-gated fields when absent" do
    minimal = described_class.new("user_id" => "xyz", "roles" => ["Learner"])
    expect(minimal.email).to be_nil
    expect(minimal.name).to be_nil
  end

  it "raises an Error when user_id is missing" do
    expect do
      described_class.new("roles" => ["Learner"])
    end.to raise_error(Lti::Advantage::Error, /user_id/)
  end

  it "raises an Error when roles is not an array" do
    expect do
      described_class.new("user_id" => "xyz", "roles" => "Learner")
    end.to raise_error(Lti::Advantage::Error, /roles must be an array/)
  end

  it "raises an Error when status is invalid" do
    expect do
      described_class.new("user_id" => "xyz", "roles" => ["Learner"], "status" => "Paused")
    end.to raise_error(Lti::Advantage::Error, /status must be one of/)
  end
end
