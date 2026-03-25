# frozen_string_literal: true

require "sinatra"
require "dotenv/load"
require "securerandom"
require "uri"
require_relative "../lib/lti/advantage"

# Bind to 0.0.0.0 to listen on all network interfaces
set :bind, "0.0.0.0"

# Disable strict protection and frame options for local LTI testing
set :protection, except: %i[http_origin remote_token session_hijacking frame_options host_authorization]

# Allow cookies to be sent in an iframe (SameSite=None; Secure=True is usually required by modern browsers)
# Note: Local iframe testing over HTTP still requires `SESSION_COOKIE_SECURE=false`.
SESSION_SECRET = ENV["SESSION_SECRET"] || SecureRandom.hex(64)
SESSION_COOKIE_SECURE = ENV.fetch("SESSION_COOKIE_SECURE", "false") == "true"

use Rack::Session::Cookie,
    key: "rack.session",
    path: "/",
    secret: SESSION_SECRET,
    same_site: :none,
    secure: SESSION_COOKIE_SECURE

# Log every request to the terminal
before do
  puts "Incoming Request: #{request.request_method} #{request.path_info}"
  puts "Params: #{params.inspect}" if params.any?
end

helpers do
  def normalized_param(name)
    value = params[name]&.to_s&.strip
    value.nil? || value.empty? ? nil : value
  end

  def integer_param(name)
    value = normalized_param(name)
    value ? Integer(value, 10) : nil
  end
end

helpers do
  def memberships_response_body(result)
    {
      context: result.context,
      members: result.members.map do |member|
        {
          user_id: member.user_id,
          name: member.name,
          email: member.email,
          roles: member.roles,
          status: member.status
        }
      end,
      next_page_url: result.next_page_url,
      differences_url: result.differences_url,
      next_page_path: memberships_route_url(page_url: result.next_page_url),
      differences_path: memberships_route_url(page_url: result.differences_url)
    }
  end
end

helpers do
  def memberships_route_url(page_url: nil)
    return nil if page_url.nil?

    "/nrps/members?#{URI.encode_www_form(page_url: page_url)}"
  end
end

# LTI Configuration (Loaded from .env)
CLIENT_ID       = ENV["CLIENT_ID"]       || "10000000000001"
LMS_BROWSER_URL = ENV["LMS_BROWSER_URL"] || "http://canvas.docker"
TOOL_HOST       = ENV["TOOL_HOST"]       || "127.0.0.1:4567"
LMS_ISSUER      = ENV["LMS_ISSUER"]      || "http://127.0.0.1:3000"
LMS_AUTH_URL    = ENV["LMS_AUTH_URL"]    || "#{LMS_BROWSER_URL}/api/lti/authorize_redirect"
LMS_JWKS_URL    = ENV["LMS_JWKS_URL"]    || "#{LMS_ISSUER}/api/lti/security/jwks"
LMS_TOKEN_ENDPOINT = ENV["LMS_TOKEN_ENDPOINT"] || "#{LMS_BROWSER_URL}/login/oauth2/token"
DEPLOYMENT_ID   = ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"
TOOL_LAUNCH_URL = "http://#{TOOL_HOST}/lti/launch".freeze

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new
LTI_REGISTRATION = Lti::Advantage::Registration.new(
  issuer: LMS_ISSUER,
  client_id: CLIENT_ID,
  authorization_endpoint: LMS_AUTH_URL,
  jwks_url: LMS_JWKS_URL,
  token_endpoint: LMS_TOKEN_ENDPOINT,
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

  session[:nrps_memberships_url] = launch.context_memberships_url
  session[:lti_deployment_id] = launch.deployment_id

  launch_message = "Welcome, student! Your ID is: #{launch.subject || "anonymous"}. Launch successful!"
  if launch.nrps_available?
    "#{launch_message} NRPS memberships are available at /nrps/members."
  else
    "#{launch_message} This launch did not include the NRPS claim."
  end
rescue KeyError
  halt 400, "Missing id_token or state"
rescue Lti::Advantage::ReplayError => e
  halt 401, "Replay protection failed: #{e.message}"
rescue Lti::Advantage::JwtVerificationError => e
  halt 401, "JWT verification failed: #{e.message}"
rescue Lti::Advantage::ValidationError => e
  halt 400, "Launch validation failed: #{e.message}"
end

# rubocop:disable Metrics/BlockLength
get "/nrps/members" do
  memberships_url = session[:nrps_memberships_url]
  halt 400, "No memberships URL in session. Complete an LTI launch first." unless memberships_url

  limit = integer_param(:limit)
  page_url = normalized_param(:page_url)
  role = normalized_param(:role)
  resource_link_id = normalized_param(:resource_link_id)

  token_service = Lti::Advantage::Services::AccessToken.new(
    key_pair: TOOL_KEY_PAIR,
    client_id: CLIENT_ID,
    token_endpoint: LTI_REGISTRATION.token_endpoint,
    scope: Lti::Advantage::Services::NamesRoleService::SCOPE,
    deployment_id: session[:lti_deployment_id]
  )

  begin
    access_token = token_service.fetch
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to obtain access token: #{e.message}"
  end

  nrps = Lti::Advantage::Services::NamesRoleService.new(
    memberships_url: memberships_url,
    access_token: access_token
  )

  begin
    result = if page_url
               nrps.memberships_from_url(page_url)
             else
               nrps.memberships(role: role, limit: limit, resource_link_id: resource_link_id)
             end
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to fetch memberships: #{e.message}"
  end

  content_type :json
  memberships_response_body(result).to_json
rescue ArgumentError
  halt 400, "limit must be an integer"
end
# rubocop:enable Metrics/BlockLength

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
