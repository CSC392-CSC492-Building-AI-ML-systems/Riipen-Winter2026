# frozen_string_literal: true

module TestFactories
  def self.create_lti_params(overrides = {})
    {
      iss: ENV["LMS_ISSUER"] || "http://127.0.0.1:3000",
      login_hint: "login-hint-#{rand(1000)}",
      target_link_uri: "http://127.0.0.1:4567/lti/launch",
      lti_message_hint: "message-hint-#{rand(1000)}",
      lti_deployment_id: ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"
    }.merge(overrides)
  end
end
