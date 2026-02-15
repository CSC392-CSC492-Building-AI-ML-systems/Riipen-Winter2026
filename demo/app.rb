# frozen_string_literal: true

require "sinatra"
require "securerandom"
require_relative "../lib/lti/advantage"

# Enable session storage for storing state and nonce
enable :sessions
set :session_secret, "a_very_long_and_very_secure_secret_key_that_is_at_least_64_bytes_long_1234567890_abcdefg"

# Mock: Your tool's Client ID registered in the LMS
CLIENT_ID = "10000000000001"
LMS_ISSUER = "http://localhost:3000" # Assuming local Canvas runs on port 3000

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new

# 0. JWKS Endpoint (Exposes your public keys)
# Configure in Canvas as: http://localhost:4567/lti/jwks
get "/lti/jwks" do
  content_type :json
  { keys: [TOOL_KEY_PAIR.public_jwk] }.to_json
end

# 1. Login Initiation (OIDC Initiation)
# Configure in Canvas as: http://localhost:4567/oidc/init
get "/oidc/init" do
  initiation = Lti::Advantage::Oidc::LoginInitiation.new(params)
  
  begin
    initiation.validate!
    
    # Generate random strings to prevent attacks and store in session
    state = SecureRandom.hex(16)
    nonce = SecureRandom.hex(16)
    session[:lti_state] = state
    session[:lti_nonce] = nonce
    
    # Prepare redirect parameters for the LMS
    redirect_params = initiation.redirect_params(
      client_id: CLIENT_ID,
      redirect_uri: "http://localhost:4567/lti/launch",
      state: state,
      nonce: nonce
    )
    
    # Canvas OIDC auth endpoint (Assuming /api/lti/authorize_redirect)
    auth_url = "#{params[:iss]}/api/lti/authorize_redirect"
    
    # Render auto-submitting form to redirect back to Canvas
    erb :redirect, locals: { url: auth_url, params: redirect_params }
  rescue Lti::Advantage::Error => e
    halt 400, "Validation Error: #{e.message}"
  end
end

# 2. Main Launch Endpoint (LTI Launch)
post "/lti/launch" do
  if params[:state] != session[:lti_state]
    halt 403, "Invalid State"
  end
  
  message = Lti::Advantage::Message.new(params[:id_token])
  
  # Save info for grading later
  session[:user_id] = message.user_id
  session[:line_item_url] = message.ags_line_item_url
  
  erb :welcome, locals: { user_id: message.user_id }
end

# 3. Grade Submission Endpoint
post "/lti/submit_grade" do
  ags = Lti::Advantage::Services::Ags.new(
    access_token_url: "#{LMS_ISSUER}/login/oauth2/token",
    client_id: CLIENT_ID,
    key_pair: TOOL_KEY_PAIR
  )

  response = ags.post_score(
    line_item_url: session[:line_item_url],
    score: 10.0,
    total: 10.0,
    user_id: session[:user_id]
  )

  if response.success?
    "Grade submitted successfully!"
  else
    "Failed to submit grade: #{response.body}"
  end
end

__END__

@@welcome
<!DOCTYPE html>
<html>
<body>
  <h1>Welcome, <%= user_id %>!</h1>
  <p>Launch successful. Ready to test grading?</p>
  <form action="/lti/submit_grade" method="POST">
    <button type="submit">Send 10/10 Grade to Canvas</button>
  </form>
</body>
</html>

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
