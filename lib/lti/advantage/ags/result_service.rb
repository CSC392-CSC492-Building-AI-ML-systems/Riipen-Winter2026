# frozen_string_literal: true

module Lti
  module Advantage
    module AGS
      # Client for the LTI AGS Result service (read-only: fetch results from the platform gradebook).
      # @see https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service
      class ResultService
        RESULT_CONTAINER_CONTENT_TYPE = "application/vnd.ims.lis.v2.resultcontainer+json"

        def initialize(service_client:)
          @service_client = service_client
        end

      end
    end
  end
end
