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
          # unique for result: required to identify result(?)
          @id = id.to_s
          # must match line item url (required?)
          @score_of = score_of.to_s
          # user_id MUST exist
          @user_id = user_id.to_s
          # optional, numeric
          @result_score = result_score
          # resultMaximum MUST be positive, default 1
          @result_maximum = get_max(result_maximum)
          # optional
          @scoring_user_id = optional_string(scoring_user_id)
          # optional
          @comment = optional_string(comment)
        end

        # read JSON to build Result
        def self.from_json(hash)
          raise ArgumentError, "Result must be built from a Hash, got #{hash.class}" unless hash.is_a?(Hash)
          # transform JSON to string
          h = hash.transform_keys(&:to_s)
          # if id not exist
          if h["id"].nil? || h["id"].to_s.strip.empty? || !h["id"].is_a?(String)
            raise ValidationError, "id is required"
          end
          validate_url!("id", h["id"])

          # if value for scoringUserId provided but not string
          if !h["scoringUserId"].nil? && !h["scoringUserId"].is_a?(String)
            raise ValidationError, "scoringUserId must be a string"
          end
          # if user_id not exist (null or empty)
          if h["userId"].nil? || h["userId"].to_s.strip.empty? || !h["userId"].is_a?(String)
            raise ValidationError, "userId is required"
          end
          # if result_score exist but not numeric
          if !h["resultScore"].nil? && !h["resultScore"].is_a?(Numeric)
            raise ValidationError, "resultScore must be numeric"
          end

          # scoreOf is required
          if h["scoreOf"].nil? || h["scoreOf"].to_s.strip.empty? || !h["scoreOf"].is_a?(String)
            raise ValidationError, "scoreOf is required"
          end
          validate_url!("scoreOf", h["scoreOf"])
          # if value for resultMaximum provided but not numeric, default to 1
          # if !h["resultMaximum"].nil? && !h["resultMaximum"].is_a?(Numeric)
          #   raise ValidationError, "resultMaximum must be numeric"
          # end
          
          # if value for comment provided but not string
          if !h["comment"].nil? && !h["comment"].is_a?(String)
            raise ValidationError, "comment must be a string"
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
        # check if the string value exists
        def optional_string(value)
          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end

        # default result_maximum to 1 if not positive number
        def get_max(value)
          raw_max = value.nil? ? 1.0 : value
          return raw_max.is_a?(Numeric) && raw_max.positive? ? raw_max : 1.0
        end

        # id and scoringUserId must be of URL string
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
