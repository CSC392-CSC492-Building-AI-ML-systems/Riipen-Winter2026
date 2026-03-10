# frozen_string_literal: true

require "thread"

module Lti
  module Advantage
    module Store
      class MemoryStore
        def initialize(clock: -> { Time.now })
          @clock = clock
          @entries = {}
          @mutex = Mutex.new
        end

        def write(key, value:, ttl:)
          @mutex.synchronize do
            @entries[key] = {
              value: value,
              expires_at: @clock.call + ttl
            }
          end

          value
        end

        def read(key)
          @mutex.synchronize do
            prune_expired!
            entry = @entries[key]
            entry && entry[:value]
          end
        end

        def consume(key)
          @mutex.synchronize do
            prune_expired!
            entry = @entries.delete(key)
            entry && entry[:value]
          end
        end

        private

        def prune_expired!
          now = @clock.call
          @entries.delete_if { |_key, entry| entry[:expires_at] <= now }
        end
      end
    end
  end
end
