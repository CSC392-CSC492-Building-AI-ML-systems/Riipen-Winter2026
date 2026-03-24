# frozen_string_literal: true

RSpec.describe Lti::Advantage::AGS::Endpoint do
  let(:claim) do
    {
      "lineitems" => "https://platform.example/contexts/1/line_items",
      "lineitem" => "https://platform.example/line_items/42",
      "scope" => [
        described_class::SCORE_SCOPE,
        described_class::RESULT_SCOPE
      ]
    }
  end

  subject(:endpoint) { described_class.new(claim) }

  it "extracts line item urls and scopes from the AGS claim" do
    expect(endpoint.lineitems_url).to eq("https://platform.example/contexts/1/line_items")
    expect(endpoint.lineitem_url).to eq("https://platform.example/line_items/42")
    expect(endpoint.scopes).to include(described_class::SCORE_SCOPE)
  end

  it "derives the score endpoint from the lineitem url" do
    expect(endpoint.score_url).to eq("https://platform.example/line_items/42/scores")
  end

  it "derives the results endpoint from nested lineitem paths and preserves query params" do
    nested_endpoint = described_class.new(
      "lineitem" => "https://platform.example/courses/1/line_items/42?resource_link_id=abc123",
      "scope" => [described_class::RESULT_SCOPE]
    )

    expect(nested_endpoint.results_url)
      .to eq("https://platform.example/courses/1/line_items/42/results?resource_link_id=abc123")
  end

  it "raises when score scope is missing" do
    readonly_endpoint = described_class.new(
      "lineitem" => "https://platform.example/line_items/42",
      "scope" => [described_class::RESULT_SCOPE]
    )

    expect { readonly_endpoint.score_url }
      .to raise_error(Lti::Advantage::AuthorizationError, /scope/)
  end

  it "raises when a concrete lineitem url is unavailable" do
    no_lineitem_endpoint = described_class.new(
      "lineitems" => "https://platform.example/contexts/1/line_items",
      "scope" => [described_class::SCORE_SCOPE]
    )

    expect { no_lineitem_endpoint.score_url }
      .to raise_error(Lti::Advantage::ValidationError, /lineitem URL/)
  end
end
