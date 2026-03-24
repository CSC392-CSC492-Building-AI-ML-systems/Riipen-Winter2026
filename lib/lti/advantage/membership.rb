# frozen_string_literal: true

module Lti
  module Advantage
    # Represents a single course membership returned by the Names and Role
    # Provisioning Service.  Wraps the raw JSON hash and exposes typed accessors.
    #
    # All fields beyond +user_id+ and +roles+ are optional – the LMS only shares
    # them when the Platform has given explicit consent.
    class Membership
      # @return [String] the user's platform-scoped unique identifier (sub)
      attr_reader :user_id

      # @return [Array<String>] list of LTI role URIs or abbreviated role names
      attr_reader :roles

      # @return [String] "Active", "Inactive", or "Deleted"
      attr_reader :status

      # @return [String, nil] full display name (consent-gated)
      attr_reader :name

      # @return [String, nil] email address (consent-gated)
      attr_reader :email

      # @return [String, nil] given / first name (consent-gated)
      attr_reader :given_name

      # @return [String, nil] family / last name (consent-gated)
      attr_reader :family_name

      # @return [String, nil] middle name (consent-gated)
      attr_reader :middle_name

      # @return [String, nil] URL of the user's profile picture (consent-gated)
      attr_reader :picture

      # @return [String, nil] SIS person source ID (consent-gated)
      attr_reader :lis_person_sourcedid

      # @return [String, nil] legacy LTI 1.1 user ID (consent-gated)
      attr_reader :lti11_legacy_user_id

      # @return [Array<Hash>, nil] per-resource-link message data (NRPS resource
      #   link endpoint only)
      attr_reader :message

      # @param raw [Hash] a single member object from the NRPS JSON response
      def initialize(raw)
        @user_id              = raw["user_id"]
        @roles                = Array(raw["roles"])
        @status               = raw.fetch("status", "Active")
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

      # @return [Boolean] true when the membership is currently active
      def active?
        @status == "Active"
      end

      # @return [Boolean] true when the membership has been deleted
      # (only appears in diff responses)
      def deleted?
        @status == "Deleted"
      end

      # Returns true when the member holds the given role.
      # Accepts both full URIs and the short form (e.g. "Learner").
      #
      # @param role [String] role URI or short name
      # @return [Boolean]
      def role?(role)
        @roles.any? { |r| r == role || r.end_with?("##{role}") }
      end

      alias has_role? role?

      # @return [String]
      def inspect
        "#<#{self.class.name} user_id=#{@user_id.inspect} " \
          "status=#{@status.inspect} roles=#{@roles.inspect}>"
      end
    end
  end
end
