# frozen_string_literal: true

module Lti
  module Advantage
    class RegistrationStore
      def initialize(registrations)
        @registrations = Array(registrations)
        raise ArgumentError, "At least one registration is required" if @registrations.empty?

        @by_issuer = @registrations.group_by(&:issuer)
      end

      def resolve!(issuer:, client_id: nil)
        registrations = @by_issuer.fetch(issuer.to_s, [])
        raise ValidationError, "Unknown platform issuer: #{issuer}" if registrations.empty?

        return resolve_with_client_id!(issuer, client_id, registrations) if client_id
        return registrations.first if registrations.size == 1

        raise ValidationError,
              "Multiple registrations found for issuer #{issuer}; provide client_id in login initiation"
      end

      private

      def resolve_with_client_id!(issuer, client_id, registrations)
        registration = registrations.find { |candidate| candidate.client_id == client_id.to_s }
        return registration if registration

        raise ValidationError,
              "Unknown client_id #{client_id} for issuer #{issuer}"
      end
    end
  end
end
