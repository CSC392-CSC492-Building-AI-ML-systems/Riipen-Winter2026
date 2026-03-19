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
