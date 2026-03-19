# frozen_string_literal: true

RSpec.describe Lti::Advantage::AGS::Score do
  let(:timestamp) { "2026-03-11T20:10:06.123Z" }

  it "serializes a valid score payload" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Completed",
      grading_progress: "FullyGraded",
      score_given: 8.5,
      score_maximum: 10,
      comment: "Great work"
    )

    expect(score.to_h).to include(
      "userId" => "user-123",
      "timestamp" => timestamp,
      "activityProgress" => "Completed",
      "gradingProgress" => "FullyGraded",
      "scoreGiven" => 8.5,
      "scoreMaximum" => 10,
      "comment" => "Great work"
    )
  end

  it "accepts progress-only scores without score values" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Started",
      grading_progress: "Pending"
    )

    expect(score.to_h).not_to have_key("scoreGiven")
    expect(score.to_h).not_to have_key("scoreMaximum")
  end

  it "requires scoreMaximum when scoreGiven is present" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Completed",
      grading_progress: "FullyGraded",
      score_given: 8.5
    )

    expect { score.to_h }.to raise_error(Lti::Advantage::ValidationError, /scoreMaximum/)
  end

  it "rejects invalid activity progress values" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Done",
      grading_progress: "FullyGraded"
    )

    expect { score.to_h }.to raise_error(Lti::Advantage::ValidationError, /activityProgress/)
  end

  it "rejects invalid timestamps" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: "not-a-time",
      activity_progress: "Completed",
      grading_progress: "FullyGraded"
    )

    expect { score.to_h }.to raise_error(Lti::Advantage::ValidationError, /sub-second precision and timezone/)
  end

  it "accepts scores greater than scoreMaximum" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Completed",
      grading_progress: "FullyGraded",
      score_given: 11,
      score_maximum: 10
    )

    expect(score.to_h).to include(
      "scoreGiven" => 11,
      "scoreMaximum" => 10
    )
  end

  it "rejects timestamps without sub-second precision and timezone" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: "2026-03-11T20:10:06",
      activity_progress: "Completed",
      grading_progress: "FullyGraded"
    )

    expect { score.to_h }.to raise_error(Lti::Advantage::ValidationError, /sub-second precision and timezone/)
  end

  it "rejects submittedAt values earlier than startedAt" do
    score = described_class.new(
      user_id: "user-123",
      timestamp: timestamp,
      activity_progress: "Completed",
      grading_progress: "FullyGraded",
      submission: {
        startedAt: "2026-03-11T20:10:06.123Z",
        submittedAt: "2026-03-11T20:10:05.123Z"
      }
    )

    expect { score.to_h }.to raise_error(Lti::Advantage::ValidationError, /submittedAt must be equal to or later than/)
  end
end
