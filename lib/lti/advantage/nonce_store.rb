# frozen_string_literal: true

module Lti
  module Advantage
    class NonceStore
      def initialize(clock: -> { Time.now.to_i })
        @clock = clock
        @seen_nonces = {}
      end

      def consume!(nonce, expires_at: nil)
        raise Error, "Nonce cannot be blank" if nonce.to_s.empty?

        cleanup!
        raise Error, "Invalid launch: nonce replay detected" if replay?(nonce)

        @seen_nonces[nonce] = expires_at || (@clock.call + 300)
      end

      private

      def replay?(nonce)
        expiry = @seen_nonces[nonce]
        return false if expiry.nil?

        expiry >= @clock.call
      end

      def cleanup!
        now = @clock.call
        @seen_nonces.delete_if { |_nonce, expiry| expiry < now }
      end
    end
  end
end
