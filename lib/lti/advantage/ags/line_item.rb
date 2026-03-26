# frozen_string_literal: true

require "time"

module Lti
  module Advantage
    module AGS
      class LineItem
        TIMEZONE_TIMESTAMP_FORMAT = /(?:Z|[+-]\d{2}:\d{2})\z/

        INPUT_KEYS = {
          id: %w[id],
          label: %w[label],
          score_maximum: %w[scoreMaximum score_maximum],
          resource_id: %w[resourceId resource_id],
          tag: %w[tag],
          resource_link_id: %w[resourceLinkId resource_link_id],
          start_date_time: %w[startDateTime start_date_time],
          end_date_time: %w[endDateTime end_date_time],
          grades_released: %w[gradesReleased grades_released]
        }.freeze
        SERIALIZED_KEYS = INPUT_KEYS.transform_values(&:first).freeze
        KNOWN_FIELDS = INPUT_KEYS.values.flatten.freeze

        attr_reader :id, :label, :score_maximum, :resource_id, :tag, :resource_link_id,
                    :start_date_time, :end_date_time, :grades_released, :extensions

        def self.from_h(payload)
          hash = stringify_keys(payload)
          new(
            id: fetch_value(hash, *INPUT_KEYS[:id]),
            label: fetch_value(hash, *INPUT_KEYS[:label]),
            score_maximum: fetch_value(hash, *INPUT_KEYS[:score_maximum]),
            resource_id: fetch_value(hash, *INPUT_KEYS[:resource_id]),
            tag: fetch_value(hash, *INPUT_KEYS[:tag]),
            resource_link_id: fetch_value(hash, *INPUT_KEYS[:resource_link_id]),
            start_date_time: fetch_value(hash, *INPUT_KEYS[:start_date_time]),
            end_date_time: fetch_value(hash, *INPUT_KEYS[:end_date_time]),
            grades_released: fetch_value(hash, *INPUT_KEYS[:grades_released]),
            extensions: hash.reject { |key, _| KNOWN_FIELDS.include?(key) }
          )
        rescue TypeError
          raise ValidationError, "line item must be an object"
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

        def initialize(
          label:, score_maximum:, id: nil, resource_id: nil, tag: nil, resource_link_id: nil,
          start_date_time: nil, end_date_time: nil, grades_released: nil, extensions: {}
        )
          @id = optional_string(id)
          @label = optional_string(label)
          @score_maximum = score_maximum
          @resource_id = optional_string(resource_id)
          @tag = optional_string(tag)
          @resource_link_id = optional_string(resource_link_id)
          @start_date_time = optional_string(start_date_time)
          @end_date_time = optional_string(end_date_time)
          @grades_released = grades_released
          @extensions = self.class.stringify_keys(extensions)
        end

        def to_h(include_id: true)
          validate!

          extensions.merge(
            {
              "id" => include_id ? id : nil,
              "label" => label,
              "scoreMaximum" => score_maximum,
              "resourceId" => resource_id,
              "tag" => tag,
              "resourceLinkId" => resource_link_id,
              "startDateTime" => start_date_time,
              "endDateTime" => end_date_time,
              "gradesReleased" => grades_released
            }.compact
          )
        end

        def validate!
          raise ValidationError, "label is required" if label.nil?
          raise ValidationError, "scoreMaximum must be numeric" unless score_maximum.is_a?(Numeric)
          raise ValidationError, "scoreMaximum must be greater than zero" unless score_maximum.positive?
          if !grades_released.nil? && ![true, false].include?(grades_released)
            raise ValidationError, "gradesReleased must be boolean"
          end

          validate_timestamp!(start_date_time, field: "startDateTime") unless start_date_time.nil?
          validate_timestamp!(end_date_time, field: "endDateTime") unless end_date_time.nil?
        end

        private

        def validate_timestamp!(value, field:)
          unless TIMEZONE_TIMESTAMP_FORMAT.match?(value)
            raise ValidationError, "#{field} must be an ISO8601 timestamp with timezone"
          end

          Time.iso8601(value)
        rescue ArgumentError
          raise ValidationError, "#{field} must be an ISO8601 timestamp with timezone"
        end

        def optional_string(value)
          return nil if value.nil?

          stripped = value.to_s.strip
          return nil if stripped.empty?

          stripped
        end
      end
    end
  end
end
