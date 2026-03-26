# frozen_string_literal: true

module Lti
  module Advantage
    # LTI claim URI constants used in launch payloads.
    module Claims
      # URI for message type claim (for example, +LtiResourceLinkRequest+).
      MESSAGE_TYPE = "https://purl.imsglobal.org/spec/lti/claim/message_type"

      # URI for LTI version claim (for example, +1.3.0+).
      VERSION = "https://purl.imsglobal.org/spec/lti/claim/version"

      # URI for deployment identifier claim.
      DEPLOYMENT_ID = "https://purl.imsglobal.org/spec/lti/claim/deployment_id"

      # URI for launch target URL claim.
      TARGET_LINK_URI = "https://purl.imsglobal.org/spec/lti/claim/target_link_uri"

      # URI for resource link object claim.
      RESOURCE_LINK = "https://purl.imsglobal.org/spec/lti/claim/resource_link"

      # URI for roles array claim.
      ROLES = "https://purl.imsglobal.org/spec/lti/claim/roles"

      # URI for optional context object claim.
      CONTEXT = "https://purl.imsglobal.org/spec/lti/claim/context"

      # URI for optional tool platform object claim.
      TOOL_PLATFORM = "https://purl.imsglobal.org/spec/lti/claim/tool_platform"

      # URI for custom parameter map claim.
      CUSTOM = "https://purl.imsglobal.org/spec/lti/claim/custom"

      # URI for the Assignment and Grade Services endpoint claim.
      AGS_ENDPOINT = "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"
    end
  end
end
