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
          # user_id must be present
          @id = id.to_s
          @score_of = score_of.to_s
          @user_id = user_id.to_s
          @result_score = result_score
          @result_maximum = result_maximum
          # If no value exists, this attribute may be omitted
          @scoring_user_id = scoring_user_id.to_s
          # The value must be a string. 
          # If no value exists, this attribute may be omitted, blank or have an explicit null value.
          @comment = comment.to_s
        end
      end
    end
  end
end
