# frozen_string_literal: true

RSpec.describe Lti::Advantage::AGS::LineItem do
  it "serializes a valid line item payload" do
    line_item = described_class.new(
      id: "https://platform.example/line_items/42",
      label: "Homework 1",
      score_maximum: 100,
      resource_id: "resource-123",
      tag: "homework",
      resource_link_id: "link-123",
      start_date_time: "2026-03-11T20:10:06Z",
      end_date_time: "2026-03-12T20:10:06+00:00",
      grades_released: true,
      extensions: { "https://example.com/ext" => "value" }
    )

    expect(line_item.to_h).to include(
      "id" => "https://platform.example/line_items/42",
      "label" => "Homework 1",
      "scoreMaximum" => 100,
      "resourceId" => "resource-123",
      "tag" => "homework",
      "resourceLinkId" => "link-123",
      "startDateTime" => "2026-03-11T20:10:06Z",
      "endDateTime" => "2026-03-12T20:10:06+00:00",
      "gradesReleased" => true,
      "https://example.com/ext" => "value"
    )
  end

  it "accepts wire-format hashes in from_h" do
    line_item = described_class.from_h(
      "label" => "Homework 1",
      "scoreMaximum" => 100,
      "resourceId" => "resource-123",
      "resourceLinkId" => "link-123"
    )

    expect(line_item.score_maximum).to eq(100)
    expect(line_item.resource_id).to eq("resource-123")
    expect(line_item.resource_link_id).to eq("link-123")
  end

  it "accepts snake_case hashes in from_h" do
    line_item = described_class.from_h(
      label: "Homework 1",
      score_maximum: 100,
      resource_id: "resource-123",
      resource_link_id: "link-123"
    )

    expect(line_item.score_maximum).to eq(100)
    expect(line_item.resource_id).to eq("resource-123")
    expect(line_item.resource_link_id).to eq("link-123")
  end

  it "raises ValidationError when from_h payload is not an object" do
    expect do
      described_class.from_h("not-a-hash")
    end.to raise_error(Lti::Advantage::ValidationError, /line item must be an object/)
  end

  it "accepts line item timestamps with RFC3339 offsets" do
    line_item = described_class.new(
      label: "Homework 1",
      score_maximum: 100,
      start_date_time: "2026-03-11T20:10:06+00:00",
      end_date_time: "2026-03-12T20:10:06+00:00"
    )

    expect(line_item.to_h).to include(
      "startDateTime" => "2026-03-11T20:10:06+00:00",
      "endDateTime" => "2026-03-12T20:10:06+00:00"
    )
  end

  it "rejects line item timestamps without RFC3339 offsets" do
    line_item = described_class.new(
      label: "Homework 1",
      score_maximum: 100,
      start_date_time: "2026-03-11T20:10:06+0000"
    )

    expect { line_item.to_h }.to raise_error(Lti::Advantage::ValidationError, /ISO8601 timestamp/)
  end

  it "rejects missing labels" do
    line_item = described_class.new(label: " ", score_maximum: 10)

    expect { line_item.to_h }.to raise_error(Lti::Advantage::ValidationError, /label is required/)
  end

  it "rejects invalid scoreMaximum values" do
    line_item = described_class.new(label: "Homework 1", score_maximum: 0)

    expect { line_item.to_h }.to raise_error(Lti::Advantage::ValidationError, /greater than zero/)
  end

  it "omits id when serializing a create payload" do
    line_item = described_class.new(
      id: "https://platform.example/line_items/42",
      label: "Homework 1",
      score_maximum: 10
    )

    expect(line_item.to_h(include_id: false)).not_to have_key("id")
  end

  it "preserves unknown extension fields from platform responses" do
    line_item = described_class.from_h(
      "id" => "https://platform.example/line_items/42",
      "label" => "Homework 1",
      "scoreMaximum" => 10,
      "https://example.com/ext" => "value"
    )

    expect(line_item.extensions).to eq("https://example.com/ext" => "value")
    expect(line_item.to_h).to include("https://example.com/ext" => "value")
  end
end
