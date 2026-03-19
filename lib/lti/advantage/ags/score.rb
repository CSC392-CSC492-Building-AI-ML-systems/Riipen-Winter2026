# frozen_string_literal: true

require "time"

module Lti
  module Advantage
    module AGS
      class Score
        ACTIVITY_PROGRESS_VALUES = %w[Initialized Started InProgress Submitted Completed].freeze
        GRADING_PROGRESS_VALUES = %w[NotReady Failed Pending PendingManual FullyGraded].freeze
        TIMESTAMP_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+(?:Z|[+-]\d{2}(?::?\d{2})?)\z/.freeze

        attr_reader :user_id, :timestamp, :activity_progress, :grading_progress,
                    :score_given, :score_maximum, :comment, :scoring_user_id, :submission

        def initialize(
          user_id:, timestamp:, activity_progress:, grading_progress:, score_given: nil,
          score_maximum: nil, comment: nil, scoring_user_id: nil, submission: nil
        )
          @user_id = user_id.to_s
          @timestamp = timestamp.to_s
          @activity_progress = activity_progress.to_s
          @grading_progress = grading_progress.to_s
          @score_given = score_given
          @score_maximum = score_maximum
          @comment = optional_string(comment)
          @scoring_user_id = optional_string(scoring_user_id)
          @submission = normalize_submission(submission)
        end

        def to_h
          validate!

          {
            "userId" => user_id,
            "timestamp" => timestamp,
            "activityProgress" => activity_progress,
            "gradingProgress" => grading_progress,
            "scoreGiven" => score_given,
            "scoreMaximum" => score_maximum,
            "comment" => comment,
            "scoringUserId" => scoring_user_id,
            "submission" => submission
          }.compact
        end

        def validate!
          raise ValidationError, "userId is required" if user_id.empty?

          parse_timestamp!(timestamp, field: "timestamp")

          unless ACTIVITY_PROGRESS_VALUES.include?(activity_progress)
            raise ValidationError,
                  "activityProgress must be one of: #{ACTIVITY_PROGRESS_VALUES.join(", ")}"
          end

          unless GRADING_PROGRESS_VALUES.include?(grading_progress)
            raise ValidationError,
                  "gradingProgress must be one of: #{GRADING_PROGRESS_VALUES.join(", ")}"
          end

          validate_score_values!
          validate_submission!
        end

        private

        def validate_score_values!
          return if score_given.nil? && score_maximum.nil?

          raise ValidationError, "scoreMaximum is required when scoreGiven is provided" if !score_given.nil? && score_maximum.nil?
          raise ValidationError, "scoreGiven must be numeric" unless score_given.nil? || score_given.is_a?(Numeric)
          raise ValidationError, "scoreMaximum must be numeric" unless score_maximum.nil? || score_maximum.is_a?(Numeric)
          raise ValidationError, "scoreMaximum must be greater than zero" if !score_maximum.nil? && score_maximum <= 0
          raise ValidationError, "scoreGiven cannot be negative" if !score_given.nil? && score_given.negative?
        end

        def validate_submission!
          return if submission.nil?

          %w[startedAt submittedAt].each do |field|
            value = submission[field]
            next if value.nil?

            parse_timestamp!(value, field: "submission.#{field}")
          end

          return if submission["startedAt"].nil? || submission["submittedAt"].nil?

          started_at = Time.iso8601(submission["startedAt"])
          submitted_at = Time.iso8601(submission["submittedAt"])
          return if submitted_at >= started_at

          raise ValidationError, "submission.submittedAt must be equal to or later than submission.startedAt"
        end

        def parse_timestamp!(value, field:)
          unless TIMESTAMP_FORMAT.match?(value)
            raise ValidationError,
                  "#{field} must be an ISO8601 timestamp with sub-second precision and timezone"
          end

          Time.iso8601(value)
        rescue ArgumentError
          raise ValidationError,
                "#{field} must be an ISO8601 timestamp with sub-second precision and timezone"
        end

        def normalize_submission(submission_value)
          return nil if submission_value.nil?

          hash = submission_value.transform_keys(&:to_s)
          {
            "startedAt" => optional_string(hash["startedAt"]),
            "submittedAt" => optional_string(hash["submittedAt"])
          }.compact
        end

        def optional_string(value)
          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end
      end
    end
  end
end
