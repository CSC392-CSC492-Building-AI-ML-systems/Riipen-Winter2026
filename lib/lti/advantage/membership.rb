# frozen_string_literal: true

module Lti
  module Advantage
    # Represents a single course membership returned by the Names and Role
    # Provisioning Service.  Wraps the raw JSON hash and exposes typed accessors.
    #
    # All fields beyond +user_id+ and +roles+ are optional – the LMS only shares
    # them when the Platform has given explicit consent.
    class Membership
      # Allowed NRPS membership status values.
      ALLOWED_STATUSES = %w[Active Inactive Deleted].freeze

      # The user's platform-scoped unique identifier (+sub+).
      attr_reader :user_id

      # List of LTI role URIs or abbreviated role names.
      attr_reader :roles

      # Membership status: +Active+, +Inactive+, or +Deleted+.
      attr_reader :status

      # Full display name, when consent allows it.
      attr_reader :name

      # Email address, when consent allows it.
      attr_reader :email

      # Given or first name, when consent allows it.
      attr_reader :given_name

      # Family or last name, when consent allows it.
      attr_reader :family_name

      # Middle name, when consent allows it.
      attr_reader :middle_name

      # URL of the user's profile picture, when consent allows it.
      attr_reader :picture

      # SIS person source id, when consent allows it.
      attr_reader :lis_person_sourcedid

      # Legacy LTI 1.1 user id, when consent allows it.
      attr_reader :lti11_legacy_user_id

      # Per-resource-link message data from NRPS resource-link responses.
      attr_reader :message

      # raw:: Single member object from the NRPS JSON response.
      def initialize(raw)
        raise Error, "Membership entry must be an object" unless raw.is_a?(Hash)

        @user_id              = required_string(raw, "user_id")
        @roles                = normalize_roles(raw["roles"])
        @status               = normalize_status(raw.fetch("status", "Active"))
        @name                 = raw["name"]
        @email                = raw["email"]
        @given_name           = raw["given_name"]
        @family_name          = raw["family_name"]
        @middle_name          = raw["middle_name"]
        @picture              = raw["picture"]
        @lis_person_sourcedid = raw["lis_person_sourcedid"]
        @lti11_legacy_user_id = raw["lti11_legacy_user_id"]
        @message              = raw["message"]
      end

      # Returns +true+ when the membership is currently active.
      def active?
        @status == "Active"
      end

      # Returns +true+ when the membership has been deleted.
      # Deleted memberships only appear in diff responses.
      def deleted?
        @status == "Deleted"
      end

      # Returns +true+ when the member holds the given role.
      # Accepts both full URIs and short names such as +Learner+.
      #
      # role:: Role URI or short name.
      def role?(role)
        @roles.any? { |r| r == role || r.end_with?("##{role}") }
      end

      alias has_role? role?

      # Returns a concise debug representation.
      def inspect
        "#<#{self.class.name} user_id=#{@user_id.inspect} " \
          "status=#{@status.inspect} roles=#{@roles.inspect}>"
      end

      private

      def required_string(raw, key)
        value = raw[key].to_s.strip
        raise Error, "Membership #{key} must be a non-empty string" if value.empty?

        value
      end

      def normalize_roles(value)
        raise Error, "Membership roles must be an array" unless value.is_a?(Array)

        value.map.with_index do |role, index|
          normalized_role = role.to_s.strip
          raise Error, "Membership role at index #{index} must be a non-empty string" if normalized_role.empty?

          normalized_role
        end
      end

      def normalize_status(value)
        status = value.to_s.strip
        unless ALLOWED_STATUSES.include?(status)
          raise Error,
                "Membership status must be one of: #{ALLOWED_STATUSES.join(", ")}"
        end

        status
      end
    end
  end
end
