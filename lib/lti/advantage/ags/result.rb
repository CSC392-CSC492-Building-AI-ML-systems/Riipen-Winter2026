# frozen_string_literal: true

module Lti
  module Advantage
    module AGS
      # Represents a single result from the AGS Result service (read-only gradebook cell).
      # @see https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service
      class Result
        attr_reader :id, :score_of, :user_id, :result_score, :result_maximum,
                    :scoring_user_id, :comment

        def initialize(
          id: nil, score_of: nil, user_id: nil, result_score: nil, result_maximum: nil,
          scoring_user_id: nil, comment: nil
        )
          @id = optional_string(id)
          @score_of = optional_string(score_of)
          @user_id = user_id.to_s
          @result_score = result_score
          # Spec 3.3.4.6: resultMaximum MUST be positive; default 1 if omitted or invalid
          raw_max = result_maximum.nil? ? 1 : result_maximum
          @result_maximum = raw_max.is_a?(Numeric) && raw_max.positive? ? raw_max : 1
          @scoring_user_id = optional_string(scoring_user_id)
          @comment = optional_string(comment)
        end

        # Build a Result from the platform JSON (camelCase keys).
        # Handles optional fields (resultScore, resultMaximum, scoringUserId, comment) per spec 3.3.4.
        # @raise [ArgumentError] when hash is not a Hash
        # @raise [ValidationError] when userId is missing (spec 3.3.4.4) or resultScore is non-numeric (spec 3.3.4.5)
        def self.from_json(hash)
          raise ArgumentError, "Result must be built from a Hash, got #{hash.class}" unless hash.is_a?(Hash)

          h = hash.transform_keys(&:to_s)
          user_id_val = h["userId"]
          if user_id_val.nil? || user_id_val.to_s.strip.empty?
            raise ValidationError, "userId is required"
          end
          result_score_val = h["resultScore"]
          if !result_score_val.nil? && !result_score_val.is_a?(Numeric)
            raise ValidationError, "resultScore must be numeric when present"
          end

          new(
            id: h["id"],
            score_of: h["scoreOf"],
            user_id: h["userId"],
            result_score: h["resultScore"],
            result_maximum: h["resultMaximum"],
            scoring_user_id: h["scoringUserId"],
            comment: h["comment"]
          )
        end

        private

        def optional_string(value)
          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end
      end
    end
  end
end
