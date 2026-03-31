# frozen_string_literal: true

require "time"

module Lti
  module Advantage
    module AGS
      # Value object for AGS line items.
      #
      # Instances can be constructed from Ruby keyword arguments or from a Hash
      # returned by an AGS response. Unknown extension fields are preserved.
      class LineItem
        # Regular expression enforcing timezone-qualified ISO8601 timestamps.
        TIMEZONE_TIMESTAMP_FORMAT = /(?:Z|[+-]\d{2}:\d{2})\z/

        # Accepted input keys for Hash-based construction.
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

        # Canonical AGS key used when serializing each input field.
        SERIALIZED_KEYS = INPUT_KEYS.transform_values(&:first).freeze

        # Flat list of known serialized and snake_case field names.
        KNOWN_FIELDS = INPUT_KEYS.values.flatten.freeze

        # Service-managed line item URL, when present.
        attr_reader :id

        # Human-readable label for the line item.
        attr_reader :label

        # Maximum numeric score for the line item.
        attr_reader :score_maximum

        # Tool-defined resource identifier, when present.
        attr_reader :resource_id

        # Tool-defined tag, when present.
        attr_reader :tag

        # Resource link identifier associated with the line item, when present.
        attr_reader :resource_link_id

        # Opening timestamp for the line item, when present.
        attr_reader :start_date_time

        # Closing timestamp for the line item, when present.
        attr_reader :end_date_time

        # Whether grades have been released, when present.
        attr_reader :grades_released

        # Custom extension fields preserved during round-trips.
        attr_reader :extensions

        # Builds a {LineItem} from a platform response Hash or caller-provided
        # attributes using either serialized AGS keys or snake_case keys.
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

        # Returns a copy of +hash+ with String keys.
        def self.stringify_keys(hash)
          Hash(hash).transform_keys(&:to_s)
        end

        # Returns the first matching value in +hash+ for the provided +keys+.
        def self.fetch_value(hash, *keys)
          keys.each do |key|
            return hash[key] if hash.key?(key)
          end

          nil
        end

        # label:: Human-readable label for the line item.
        # score_maximum:: Maximum numeric score for the line item.
        # id:: Optional service-managed line item URL.
        # resource_id:: Optional tool-defined resource identifier.
        # tag:: Optional tool-defined tag.
        # resource_link_id:: Optional resource link identifier.
        # start_date_time:: Optional ISO8601 timestamp with timezone.
        # end_date_time:: Optional ISO8601 timestamp with timezone.
        # grades_released:: Optional boolean indicating grade release state.
        # extensions:: Additional custom fields to preserve during round-trips.
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

        # Returns the line item serialized in AGS wire format.
        #
        # include_id:: When +false+, omit the service-managed +id+ field.
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

        # Validates the line item fields and raises {ValidationError} on invalid
        # data.
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
