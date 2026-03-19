# frozen_string_literal: true

require_relative "advantage/version"
require_relative "advantage/errors"
require_relative "advantage/claims"
require_relative "advantage/registration"
require_relative "advantage/registration_store"
require_relative "advantage/store/memory_store"
require_relative "advantage/oidc/login_initiation"
require_relative "advantage/oidc/authentication_request"
require_relative "advantage/ags/endpoint"
require_relative "advantage/ags/result"
require_relative "advantage/ags/result_service"
require_relative "advantage/ags/score"
require_relative "advantage/ags/service_client"
require_relative "advantage/ags/score_service"
require_relative "advantage/jwks_repository"
require_relative "advantage/launch"
require_relative "advantage/launch_validator"
require_relative "advantage/client"
require_relative "advantage/key_pair"

# LTI namespace for interoperability-related gems.
module Lti
  # Tool-side implementation of the LTI 1.3 core launch flow.
  #
  # The most common entrypoint is {Client}, which can:
  #
  # 1. Validate login initiation parameters from a platform
  # 2. Generate a compliant OpenID authentication request URL
  # 3. Validate a signed +id_token+ launch payload
  #
  # See {Client#authentication_request} and {Client#validate_launch!} for the
  # main lifecycle methods.
  module Advantage
    # Namespace for OpenID Connect request/response objects used by LTI 1.3.
    module OIDC
    end

    # Backwards-compatible alias for the older camelization.
    Oidc = OIDC

    # Namespace for store implementations used for replay protection.
    module Store
    end
  end
end
