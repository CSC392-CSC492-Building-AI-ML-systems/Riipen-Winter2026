# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    module AGS
      # Represents a single result from the AGS Result service (read-only gradebook cell).
      # https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service
      class Result
        attr_reader :id, :score_of, :user_id, :result_score, :result_maximum,
                    :scoring_user_id, :comment

        def initialize(
          id: nil, score_of: nil, user_id: nil, result_score: nil, result_maximum: nil,
          scoring_user_id: nil, comment: nil
        )
          @id = id.to_s
          @score_of = score_of.to_s
          @user_id = user_id.to_s
          @result_score = result_score
          @result_maximum = result_maximum.nil? ? 1 : result_maximum
          @scoring_user_id = optional_string(scoring_user_id)
          @comment = optional_string(comment)
        end

        def self.from_json(hash)
          raise ValidationError, "result must be an object" unless hash.is_a?(Hash)

          h = hash.transform_keys(&:to_s)
          raise ValidationError, "id is required" if h["id"].nil? || h["id"].to_s.strip.empty? || !h["id"].is_a?(String)

          validate_url!("id", h["id"])

          if !h["scoringUserId"].nil? && !h["scoringUserId"].is_a?(String)
            raise ValidationError, "scoringUserId must be a string"
          end
          if h["userId"].nil? || h["userId"].to_s.strip.empty? || !h["userId"].is_a?(String)
            raise ValidationError, "userId is required"
          end
          if !h["resultScore"].nil? && !h["resultScore"].is_a?(Numeric)
            raise ValidationError, "resultScore must be numeric"
          end

          if h["scoreOf"].nil? || h["scoreOf"].to_s.strip.empty? || !h["scoreOf"].is_a?(String)
            raise ValidationError, "scoreOf is required"
          end

          validate_url!("scoreOf", h["scoreOf"])

          if !h["resultMaximum"].nil? && !h["resultMaximum"].is_a?(Numeric)
            raise ValidationError, "resultMaximum must be numeric"
          end

          if h["resultMaximum"].is_a?(Numeric) && h["resultMaximum"] <= 0
            raise ValidationError, "resultMaximum must be greater than zero"
          end

          raise ValidationError, "comment must be a string" if !h["comment"].nil? && !h["comment"].is_a?(String)

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

        def self.validate_url!(field_name, value)
          uri = URI.parse(value)
          unless uri.is_a?(URI::HTTP) && !uri.scheme.nil? && !uri.host.nil?
            raise ValidationError, "#{field_name} must be a URL string"
          end
        rescue URI::InvalidURIError
          raise ValidationError, "#{field_name} must be a URL string"
        end
        private_class_method :validate_url!
      end
    end
  end
end
