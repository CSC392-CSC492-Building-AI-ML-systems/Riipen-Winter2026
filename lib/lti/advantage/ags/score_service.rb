# frozen_string_literal: true

module Lti
  module Advantage
    module AGS
      class ScoreService
        SCORE_CONTENT_TYPE = "application/vnd.ims.lis.v1.score+json"

        def initialize(service_client:)
          @service_client = service_client
        end

        def publish(score:, line_item_url: nil)
          score_record = score.is_a?(Score) ? score : Score.new(**score)
          score_record.validate!
          score_url = @service_client.endpoint.score_url(line_item_url: line_item_url)

          @service_client.validate_score_publish!(score: score_record, score_url: score_url)

          response = @service_client.post_json(
            url: score_url,
            body: score_record.to_h,
            content_type: SCORE_CONTENT_TYPE,
            accept: SCORE_CONTENT_TYPE,
            scopes: [Endpoint::SCORE_SCOPE]
          )

          @service_client.remember_score_publish!(score: score_record, score_url: score_url)
          response
        end
      end
    end
  end
end
