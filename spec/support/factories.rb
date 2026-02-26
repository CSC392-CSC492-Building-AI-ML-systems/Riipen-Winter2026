# frozen_string_literal: true

module TestFactories
  def self.create_lti_params(overrides = {})
    {
      iss: "https://canvas.instructure.com",
      login_hint: "login-hint-#{rand(1000)}",
      target_link_uri: "http://127.0.0.1:4567/lti/launch",
      lti_message_hint: "message-hint-#{rand(1000)}"
    }.merge(overrides)
  end

  def self.create_jwt_payload(overrides = {})
    {
      iss: "https://canvas.instructure.com",
      aud: "client-id-123",
      sub: "user-#{rand(1000)}",
      exp: Time.now.to_i + 3600,
      iat: Time.now.to_i,
      "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiResourceLinkRequest"
    }.merge(overrides)
  end
end
