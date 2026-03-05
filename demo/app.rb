# frozen_string_literal: true

require "sinatra"
require "securerandom"
require "dotenv/load"
require_relative "../lib/lti/advantage"

# Bind to 0.0.0.0 to listen on all network interfaces
set :bind, "0.0.0.0"

# Disable strict protection and frame options for local LTI testing
set :protection, except: [:http_origin, :remote_token, :session_hijacking, :frame_options, :host_authorization]

# Allow cookies to be sent in an iframe (SameSite=None; Secure=True is usually required by modern browsers)
# Note: For local testing without HTTPS, we might still face some cookie blocking.
use Rack::Session::Cookie, 
  key: "rack.session",
  path: "/",
  secret: "a_very_long_and_very_secure_secret_key_that_is_at_least_64_bytes_long_1234567890_abcdefg",
  same_site: :none,
  secure: false 

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
LMS_JWKS_URL    = ENV["LMS_JWKS_URL"]    || "#{LMS_ISSUER}/api/lti/security/jwks"
DEPLOYMENT_ID   = ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new
NONCE_STORE = Lti::Advantage::NonceStore.new

# 0. JWKS Endpoint (Exposes your public keys)
get "/lti/jwks" do
  content_type :json
  { keys: [TOOL_KEY_PAIR.public_jwk] }.to_json
end

# 1. Login Initiation (OIDC Initiation)
[:get, :post].each do |method|
  send(method, "/oidc/init") do
    initiation = Lti::Advantage::Oidc::LoginInitiation.new(params)
    
    begin
      initiation.validate!
      
      state = SecureRandom.hex(16)
      nonce = SecureRandom.hex(16)
      session[:lti_state] = state
      session[:lti_nonce] = nonce
      
      redirect_params = initiation.redirect_params(
        client_id: CLIENT_ID,
        redirect_uri: "http://#{TOOL_HOST}/lti/launch",
        state: state,
        nonce: nonce
      )
      
      # Use the BROWSER URL for this jump
      auth_url = "#{LMS_BROWSER_URL}/api/lti/authorize_redirect"
      puts "Redirecting browser back to Canvas at: #{auth_url}"
      
      erb :redirect, locals: { url: auth_url, params: redirect_params }
    rescue Lti::Advantage::Error => e
      halt 400, "Validation Error: #{e.message}"
    end
  end
end

# 2. Main Launch Endpoint (LTI Launch)
post "/lti/launch" do
  puts "Checking for ID Token..."
  if params[:id_token].nil?
    if params[:error]
      halt 400, "LMS Error: #{params[:error]} - #{params[:error_description]}"
    else
      halt 400, "Missing id_token. Received params: #{params.keys.join(', ')}"
    end
  end

  puts "Checking State..."
  puts "Session State: #{session[:lti_state]}"
  puts "Params State:  #{params[:state]}"

  # A. Security check: verify the state matches the session
  if params[:state] != session[:lti_state]
    halt 403, "Invalid state"
  end
  
  # B. Parse and verify the JWT (ID Token)
  message = Lti::Advantage::Message.new(params[:id_token])
  key_store = Lti::Advantage::KeyStore.new(LMS_JWKS_URL)
  
  begin
    message.verify!(key_store: key_store, client_id: CLIENT_ID, issuer: LMS_ISSUER)
    message.validate_nonce!(expected_nonce: session[:lti_nonce])
    NONCE_STORE.consume!(message.nonce, expires_at: message.jwt_body["exp"])
    message.validate_resource_link_launch!(
      expected_deployment_id: DEPLOYMENT_ID,
      expected_target_link_uri: "http://#{TOOL_HOST}/lti/launch"
    )

    session.delete(:lti_state)
    session.delete(:lti_nonce)
    
    # If verification passes, display welcome message
    "Welcome, student! Your ID is: #{message.user_id}. Launch successful!"
  rescue Lti::Advantage::Error => e
    halt 401, "Verification Failed: #{e.message}"
  end
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
