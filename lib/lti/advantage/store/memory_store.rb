# frozen_string_literal: true

require "thread"

module Lti
  module Advantage
    module Store
      # Thread-safe in-memory key/value store with TTL support.
      #
      # This store is intended for replay-protection material (state and nonce)
      # in development or single-process deployments. Production environments
      # should consider a shared store implementation (for example Redis).
      class MemoryStore
        # clock:: Callable returning current time, used for TTL checks.
        def initialize(clock: -> { Time.now })
          @clock = clock
          @entries = {}
          @mutex = Mutex.new
        end

        # Stores +value+ under +key+ with a time-to-live in seconds.
        #
        # Returns the stored value.
        def write(key, value:, ttl:)
          @mutex.synchronize do
            @entries[key] = {
              value: value,
              expires_at: @clock.call + ttl
            }
          end

          value
        end

        # Reads a value for +key+ without removing it.
        #
        # Returns +nil+ if the key is missing or expired.
        def read(key)
          @mutex.synchronize do
            prune_expired!
            entry = @entries[key]
            entry && entry[:value]
          end
        end

        # Reads and removes a value for +key+ atomically.
        #
        # Returns +nil+ if the key is missing or expired.
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
