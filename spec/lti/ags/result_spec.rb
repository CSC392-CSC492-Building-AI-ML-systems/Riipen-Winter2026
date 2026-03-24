# frozen_string_literal: true

RSpec.describe Lti::Advantage::AGS::Result do
  describe ".from_json" do
    it "requires id to be present" do
      expect do
        described_class.from_json(
          {
            "scoreOf" => "https://platform.example/line_items/42",
            "userId" => "user-1",
            "resultScore" => 0.8
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /id is required/)
    end

    it "raises ArgumentError when payload is not a hash" do
      expect do
        described_class.from_json(["not-a-hash"])
      end.to raise_error(ArgumentError, /must be built from a Hash/)
    end

    it "requires scoreOf to be present" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "resultScore" => 0.8
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /scoreOf is required/)
    end

    it "requires scoreOf to be non-blank when present" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "scoreOf" => "   ",
            "resultScore" => 0.8
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /scoreOf is required/)
    end

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
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "scoreOf" => "https://platform.example/line_items/42",
            "resultScore" => "0.8"
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /resultScore must be numeric/)
    end

    it "defaults resultMaximum to 1 when omitted or non-positive" do
      omitted = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/1",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => 0.8
        }
      )
      expect(omitted.result_maximum).to eq(1)

      zero = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/2",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => 0.8,
          "resultMaximum" => 0
        }
      )
      expect(zero.result_maximum).to eq(1)

      negative = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/3",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => 0.8,
          "resultMaximum" => -2
        }
      )
      expect(negative.result_maximum).to eq(1)
    end

    it "treats optional string fields as nil when blank" do
      result = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/1",
          "scoreOf" => "https://platform.example/line_items/42",
          "userId" => "user-1",
          "resultScore" => 0.8,
          "scoringUserId" => nil,
          "comment" => "   "
        }
      )

      expect(result.id).to eq("https://platform.example/line_items/42/results/1")
      expect(result.score_of).to eq("https://platform.example/line_items/42")
      expect(result.scoring_user_id).to be_nil
      expect(result.comment).to be_nil
    end

    it "allows resultScore to be null" do
      result = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/1",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => nil
        }
      )

      expect(result.result_score).to be_nil
    end

    it "defaults resultMaximum to 1 when it is non-numeric" do
      result = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/1",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => 0.7,
          "resultMaximum" => "10"
        }
      )
      expect(result.result_maximum).to eq(1)
    end

    it "keeps a positive resultMaximum value as-is" do
      result = described_class.from_json(
        {
          "id" => "https://platform.example/line_items/42/results/1",
          "userId" => "user-1",
          "scoreOf" => "https://platform.example/line_items/42",
          "resultScore" => 7,
          "resultMaximum" => 10
        }
      )
      expect(result.result_maximum).to eq(10)
    end

    it "requires comment to be a string when present" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "scoreOf" => "https://platform.example/line_items/42",
            "resultScore" => 0.7,
            "comment" => 123
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /comment must be a string/)
    end

    it "requires scoringUserId to be a string when present" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "scoreOf" => "https://platform.example/line_items/42",
            "resultScore" => 0.7,
            "scoringUserId" => 456
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /scoringUserId must be a string/)
    end
    it "requires id to be a valid http(s) URL" do
      expect do
        described_class.from_json(
          {
            "id" => "not-a-url",
            "userId" => "user-1",
            "scoreOf" => "https://platform.example/line_items/42"
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /id must be a URL string/)
    end

    it "requires scoreOf to be a valid http(s) URL" do
      expect do
        described_class.from_json(
          {
            "id" => "https://platform.example/line_items/42/results/1",
            "userId" => "user-1",
            "scoreOf" => "line_items/42"
          }
        )
      end.to raise_error(Lti::Advantage::ValidationError, /scoreOf must be a URL string/)
    end
  end

end

