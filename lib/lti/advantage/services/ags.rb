# frozen_string_literal: true

module Lti
  module Advantage
    module Services
      # Handles sending scores and results back to the LMS.
      class Ags < Base
        # Sends a score for a specific user.
        # @param line_item_url [String] The URL provided in the LTI launch for grading
        # @param score [Float] The student's score
        # @param total [Float] Maximum possible score
        # @param user_id [String] The student's LTI ID
        def post_score(line_item_url:, score:, total:, user_id:)
          token = access_token(["https://purl.imsglobal.org/spec/lti-ags/scope/score"])
          
          score_url = "#{line_item_url}/scores"
          
          payload = {
            timestamp: Time.now.utc.iso8601,
            scoreGiven: score,
            scoreMaximum: total,
            comment: "Graded by LTI Tool",
            activityProgress: "Completed",
            gradingProgress: "FullyGraded",
            userId: user_id
          }

          Faraday.post(score_url) do |req|
            req.headers["Authorization"] = "Bearer #{token}"
            req.headers["Content-Type"] = "application/vnd.ims.lis.v1.score+json"
            req.body = payload.to_json
          end
        end
      end
    end
  end
end
