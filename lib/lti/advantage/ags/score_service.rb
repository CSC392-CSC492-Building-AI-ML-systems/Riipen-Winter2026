# frozen_string_literal: true

module Lti
  module Advantage
    module AGS
      class ScoreService
        SCORE_CONTENT_TYPE = "application/vnd.ims.lis.v1.score+json"

        def initialize(service_client:)
          @service_client = service_client
          @last_published_timestamps = {}
        end

        def publish(score:, line_item_url: nil)
          score_record = score.is_a?(Score) ? score : Score.new(**score)
          score_record.validate!

          score_url = @service_client.endpoint.score_url(line_item_url: line_item_url)
          validate_publish_timestamp!(score_record: score_record, score_url: score_url)

          @service_client.post_json(
            url: score_url,
            body: score_record.to_h,
            content_type: SCORE_CONTENT_TYPE,
            accept: SCORE_CONTENT_TYPE,
            scopes: [Endpoint::SCORE_SCOPE]
          )

          remember_publish_timestamp(score_record: score_record, score_url: score_url)
        end

        private

        def validate_publish_timestamp!(score_record:, score_url:)
          cache_key = timestamp_cache_key(score_record: score_record, score_url: score_url)
          previous_timestamp = @last_published_timestamps[cache_key]
          return if previous_timestamp.nil?

          current_timestamp = Time.iso8601(score_record.timestamp)
          return if current_timestamp > previous_timestamp

          raise ValidationError,
                "timestamp must be strictly increasing for each line item and user"
        end

        def remember_publish_timestamp(score_record:, score_url:)
          cache_key = timestamp_cache_key(score_record: score_record, score_url: score_url)
          @last_published_timestamps[cache_key] = Time.iso8601(score_record.timestamp)
        end

        def timestamp_cache_key(score_record:, score_url:)
          [score_url, score_record.user_id]
        end
      end
    end
  end
end
