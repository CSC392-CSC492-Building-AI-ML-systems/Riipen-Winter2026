# frozen_string_literal: true

require "sinatra"
require "dotenv/load"
require_relative "../lib/lti/advantage"

# Bind to 0.0.0.0 to listen on all network interfaces
set :bind, "0.0.0.0"

# Disable strict protection and frame options for local LTI testing
set :protection, except: %i[http_origin remote_token session_hijacking frame_options host_authorization]

# Log every request to the terminal
before do
  puts "Incoming Request: #{request.request_method} #{request.path_info}"
  puts "Params: #{params.inspect}" if params.any?
end

# LTI Configuration (Loaded from .env)
CLIENT_ID       = ENV["CLIENT_ID"]       || "10000000000001"
LMS_BROWSER_URL = ENV["LMS_BROWSER_URL"] || "http://canvas.docker"
TOOL_HOST       = ENV["TOOL_HOST"]       || "127.0.0.1:4567"
LMS_ISSUER      = ENV["LMS_ISSUER"]      || "http://127.0.0.1:3000"
LMS_AUTH_URL    = ENV["LMS_AUTH_URL"]    || "#{LMS_BROWSER_URL}/api/lti/authorize_redirect"
LMS_JWKS_URL    = ENV["LMS_JWKS_URL"]    || "#{LMS_ISSUER}/api/lti/security/jwks"
DEPLOYMENT_ID   = ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"
TOOL_LAUNCH_URL = "http://#{TOOL_HOST}/lti/launch".freeze

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new
LTI_REGISTRATION = Lti::Advantage::Registration.new(
  issuer: LMS_ISSUER,
  client_id: CLIENT_ID,
  authorization_endpoint: LMS_AUTH_URL,
  jwks_url: LMS_JWKS_URL,
  deployment_ids: [DEPLOYMENT_ID]
)
LTI_CLIENT = Lti::Advantage::Client.new(registrations: [LTI_REGISTRATION])

# 0. JWKS Endpoint (Exposes your public keys)
get "/lti/jwks" do
  content_type :json
  { keys: [TOOL_KEY_PAIR.public_jwk] }.to_json
end

# 1. Login Initiation (OIDC Initiation)
%i[get post].each do |method|
  send(method, "/oidc/init") do
    auth_request = LTI_CLIENT.authentication_request(
      login_params: params,
      redirect_uri: TOOL_LAUNCH_URL
    )

    puts "Redirecting browser back to Canvas at: #{auth_request.authorization_endpoint}"

    erb :redirect, locals: { url: auth_request.authorization_endpoint, params: auth_request.parameters }
  rescue Lti::Advantage::ValidationError => e
    halt 400, "Validation Error: #{e.message}"
  end
end

# 2. Main Launch Endpoint (LTI Launch)
post "/lti/launch" do
  launch = LTI_CLIENT.validate_launch!(
    id_token: params.fetch("id_token"),
    state: params.fetch("state")
  )

  "Welcome, student! Your ID is: #{launch.subject || "anonymous"}. Launch successful!"
rescue KeyError
  halt 400, "Missing id_token or state"
rescue Lti::Advantage::ReplayError => e
  halt 401, "Replay protection failed: #{e.message}"
rescue Lti::Advantage::JwtVerificationError => e
  halt 401, "JWT verification failed: #{e.message}"
rescue Lti::Advantage::ValidationError => e
  halt 400, "Launch validation failed: #{e.message}"
end

__END__

@@redirect
<!DOCTYPE html>
<html>
<head>
  <title>Redirecting...</title>
</head>
<body onload="document.forms[0].submit()">
  <form action="<%= url %>" method="POST">
    <% params.each do |k, v| %>
      <input type="hidden" name="<%= k %>" value="<%= v %>">
    <% end %>
    <noscript><input type="submit" value="Click here to continue"></noscript>
  </form>
</body>
</html>
