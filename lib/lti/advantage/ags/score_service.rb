# frozen_string_literal: true

module Lti
  module Advantage
    module AGS
      # Client for AGS score publishing.
      class ScoreService
        # Media type for AGS score publish payloads.
        SCORE_CONTENT_TYPE = "application/vnd.ims.lis.v1.score+json"

        # service_client:: {ServiceClient} used for authorization and HTTP.
        def initialize(service_client:)
          @service_client = service_client
        end

        # Publishes a score to the AGS score endpoint.
        #
        # score:: {Score} instance or Hash accepted by {Score.from_h}.
        # line_item_url:: Optional explicit line item URL override.
        #
        # Returns the underlying HTTP response object.
        def publish(score:, line_item_url: nil)
          score_record = score.is_a?(Score) ? score : Score.from_h(score)
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
