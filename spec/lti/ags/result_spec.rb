# frozen_string_literal: true

RSpec.describe Lti::Advantage::AGS::Result do
  describe ".from_json" do
    it "requires userId to be present" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "scoreOf" => "https://platform.example/line_items/42",
            "resultScore" => 0.8
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /userId is required/)
    end

    it "requires resultScore to be numeric when present" do
      expect do
        described_class.from_json(
          {
            "userId" => "user-1",
            "resultScore" => "0.8"
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /resultScore must be numeric/)
    end

    it "defaults resultMaximum to 1 when omitted or non-positive" do
      omitted = described_class.from_json(
        {
          "userId" => "user-1",
          "resultScore" => 0.8
        }
      )
      expect(omitted.result_maximum).to eq(1)

      zero = described_class.from_json(
        {
          "userId" => "user-1",
          "resultScore" => 0.8,
          "resultMaximum" => 0
        }
      )
      expect(zero.result_maximum).to eq(1)

      negative = described_class.from_json(
        {
          "userId" => "user-1",
          "resultScore" => 0.8,
          "resultMaximum" => -2
        }
      )
      expect(negative.result_maximum).to eq(1)
    end

    it "treats optional string fields as nil when blank" do
      result = described_class.from_json(
        {
          "id" => "  ",
          "scoreOf" => "",
          "userId" => "user-1",
          "resultScore" => 0.8,
          "scoringUserId" => nil,
          "comment" => "   "
        }
      )

      expect(result.id).to be_nil
      expect(result.score_of).to be_nil
      expect(result.scoring_user_id).to be_nil
      expect(result.comment).to be_nil
    end

    it "allows resultScore to be null" do
      result = described_class.from_json(
        {
          "userId" => "user-1",
          "resultScore" => nil
        }
      )

      expect(result.result_score).to be_nil
    end

    it "defaults resultMaximum to 1 when it is non-numeric" do
      result = described_class.from_json(
        {
          "userId" => "user-1",
          "resultScore" => 0.7,
          "resultMaximum" => "10"
        }
      )
      expect(result.result_maximum).to eq(1)
    end
  end
end

