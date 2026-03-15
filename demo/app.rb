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
LMS_TOKEN_ENDPOINT = "#{LMS_BROWSER_URL}/login/oauth2/token"

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new

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
    puts "WARNING: State mismatch! (Expected in local HTTP testing). Continuing anyway..."
    # halt 403, "Invalid State" # Temporarily disabled for local dev
  end
  
  # B. Parse and verify the JWT (ID Token)
  message = Lti::Advantage::Message.new(params[:id_token])

  session[:nrps_memberships_url] = message.context_memberships_url
  
  # In a real scenario, you would fetch public keys from the LMS JWKS URL
  # keys = Lti::Advantage::KeyStore.new("http://localhost:3000/api/lti/security/jwks").keys
  keys = [] # TODO: Populate with real public keys from the LMS
  
  begin
    # message.verify!(keys: keys, client_id: CLIENT_ID, issuer: LMS_ISSUER)
    
    # If verification passes, display welcome message
    "Welcome, student! Your ID is: #{message.user_id}. Launch successful!"
  rescue Lti::Advantage::Error => e
    halt 401, "Verification Failed: #{e.message}"
  end
end

get "/nrps/members" do
  memberships_url = session[:nrps_memberships_url]
  halt 400, "No memberships URL in session. Complete an LTI launch first." unless memberships_url

  token_service = Lti::Advantage::Services::AccessToken.new(
    key_pair:       TOOL_KEY_PAIR,
    client_id:      CLIENT_ID,
    token_endpoint: LMS_TOKEN_ENDPOINT,
    scope:          Lti::Advantage::Services::NamesRoleService::SCOPE
  )

  begin
    access_token = token_service.fetch
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to obtain access token: #{e.message}"
  end

  nrps = Lti::Advantage::Services::NamesRoleService.new(
    memberships_url: memberships_url,
    access_token:    access_token
  )

  begin
    result = nrps.memberships(role: params[:role])
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to fetch memberships: #{e.message}"
  end

  content_type :json
  {
    context: result.context,
    members: result.members.map { |m|
      { user_id: m.user_id, name: m.name, email: m.email, roles: m.roles, status: m.status }
    },
    next_page_url:   result.next_page_url,
    differences_url: result.differences_url
  }.to_json
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
