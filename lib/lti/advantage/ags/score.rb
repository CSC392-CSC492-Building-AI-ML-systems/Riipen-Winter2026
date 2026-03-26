# frozen_string_literal: true

require "time"

module Lti
  module Advantage
    module AGS
      class Score
        ACTIVITY_PROGRESS_VALUES = %w[Initialized Started InProgress Submitted Completed].freeze
        GRADING_PROGRESS_VALUES = %w[NotReady Failed Pending PendingManual FullyGraded].freeze
        TIMEZONE_TIMESTAMP_FORMAT = /\.\d+(?:Z|[+-]\d{2}(?::\d{2})?)\z/
        INPUT_KEYS = {
          user_id: %w[user_id userId],
          timestamp: %w[timestamp],
          activity_progress: %w[activity_progress activityProgress],
          grading_progress: %w[grading_progress gradingProgress],
          score_given: %w[score_given scoreGiven],
          score_maximum: %w[score_maximum scoreMaximum],
          comment: %w[comment],
          scoring_user_id: %w[scoring_user_id scoringUserId],
          submission: %w[submission]
        }.freeze

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

        def self.from_h(payload)
          hash = stringify_keys(payload)

          new(
            user_id: fetch_value(hash, *INPUT_KEYS[:user_id]),
            timestamp: fetch_value(hash, *INPUT_KEYS[:timestamp]),
            activity_progress: fetch_value(hash, *INPUT_KEYS[:activity_progress]),
            grading_progress: fetch_value(hash, *INPUT_KEYS[:grading_progress]),
            score_given: fetch_value(hash, *INPUT_KEYS[:score_given]),
            score_maximum: fetch_value(hash, *INPUT_KEYS[:score_maximum]),
            comment: fetch_value(hash, *INPUT_KEYS[:comment]),
            scoring_user_id: fetch_value(hash, *INPUT_KEYS[:scoring_user_id]),
            submission: fetch_value(hash, *INPUT_KEYS[:submission])
          )
        rescue TypeError
          raise ValidationError, "score must be an object"
        end

        def self.stringify_keys(hash)
          Hash(hash).transform_keys(&:to_s)
        end

        def self.fetch_value(hash, *keys)
          keys.each do |key|
            return hash[key] if hash.key?(key)
          end

          nil
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

          if !score_given.nil? && score_maximum.nil?
            raise ValidationError,
                  "scoreMaximum is required when scoreGiven is provided"
          end
          raise ValidationError, "scoreGiven must be numeric" unless score_given.nil? || score_given.is_a?(Numeric)

          unless score_maximum.nil? || score_maximum.is_a?(Numeric)
            raise ValidationError,
                  "scoreMaximum must be numeric"
          end
          raise ValidationError, "scoreMaximum must be greater than zero" if !score_maximum.nil? && score_maximum <= 0
          raise ValidationError, "scoreGiven cannot be negative" if !score_given.nil? && score_given.negative?

          nil if score_given.nil? || score_maximum.nil? || score_given <= score_maximum
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
          unless TIMEZONE_TIMESTAMP_FORMAT.match?(value)
            raise ValidationError,
                  "#{field} must be an ISO8601 timestamp with timezone and fractional seconds"
          end

          Time.iso8601(value)
        rescue ArgumentError
          raise ValidationError,
                "#{field} must be an ISO8601 timestamp with timezone and fractional seconds"
        end

        def normalize_submission(submission_value)
          return nil if submission_value.nil?

          hash = self.class.stringify_keys(submission_value)
          {
            "startedAt" => optional_string(self.class.fetch_value(hash, "startedAt", "started_at")),
            "submittedAt" => optional_string(self.class.fetch_value(hash, "submittedAt", "submitted_at"))
          }.compact
        rescue TypeError
          raise ValidationError, "submission must be an object"
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
