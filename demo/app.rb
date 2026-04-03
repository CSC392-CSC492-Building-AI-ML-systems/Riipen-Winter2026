# frozen_string_literal: true

require "sinatra"
require "dotenv/load"
require "fileutils"
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

helpers do
  def escape_html(value)
    Rack::Utils.escape_html(value.to_s)
  end

  def summarized_roles(roles)
    Array(roles).map { |role| escape_html(role.to_s.split("#").last) }.join(", ")
  end

  def fetch_nrps_memberships(launch)
    token_service = Lti::Advantage::Services::AccessToken.new(
      key_pair: TOOL_KEY_PAIR,
      client_id: launch.registration.client_id,
      token_endpoint: launch.registration.token_endpoint,
      token_audience: launch.registration.token_audience,
      scope: Lti::Advantage::Services::NamesRoleService::SCOPE,
      deployment_id: launch.deployment_id
    )
    access_token = token_service.fetch

    Lti::Advantage::Services::NamesRoleService.new(
      memberships_url: launch.context_memberships_url,
      access_token: access_token,
      enforce_same_origin: true
    ).memberships
  end

  def fetch_ags_summary(launch)
    return { available: false } unless launch.ags_available?

    ags_client = LTI_CLIENT.ags_service_client(launch: launch, key_pair: TOOL_KEY_PAIR)
    endpoint = launch.ags_endpoint

    line_items = if endpoint.lineitem_url
                   [ags_client.line_item_service.fetch]
                 elsif endpoint.lineitems_url
                   ags_client.line_item_service.list(limit: 5)
                 else
                   []
                 end

    results = if endpoint.lineitem_url && endpoint.supports_scope?(Lti::Advantage::AGS::Endpoint::RESULT_READONLY_SCOPE)
                ags_client.result_service.list(limit: 5)
              else
                []
              end

    {
      available: true,
      scopes: endpoint.scopes,
      lineitems_url: endpoint.lineitems_url,
      lineitem_url: endpoint.lineitem_url,
      line_items: line_items,
      results: results
    }
  rescue Lti::Advantage::Error => e
    {
      available: true,
      scopes: launch.ags_endpoint&.scopes || [],
      lineitems_url: launch.ags_endpoint&.lineitems_url,
      lineitem_url: launch.ags_endpoint&.lineitem_url,
      line_items: [],
      results: [],
      error: e.message
    }
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
LMS_TOKEN_AUDIENCE = ENV["LMS_TOKEN_AUDIENCE"]
DEPLOYMENT_ID   = ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"
TOOL_KEY_KID    = ENV["TOOL_KEY_KID"] || "demo-tool-key"
TOOL_LAUNCH_URL = "http://#{TOOL_HOST}/lti/launch".freeze
DEFAULT_TOOL_PRIVATE_KEY_PATH = File.expand_path("../tmp/demo-tool-private-key.pem", __dir__).freeze

TOOL_PRIVATE_KEY_PEM = if ENV["TOOL_PRIVATE_KEY_PATH"]
                         File.read(ENV.fetch("TOOL_PRIVATE_KEY_PATH"))
                       elsif ENV["TOOL_PRIVATE_KEY_PEM"]
                         ENV["TOOL_PRIVATE_KEY_PEM"]&.gsub("\\n", "\n")
                       elsif File.exist?(DEFAULT_TOOL_PRIVATE_KEY_PATH)
                         File.read(DEFAULT_TOOL_PRIVATE_KEY_PATH)
                       else
                         generated_tool_key_pair = Lti::Advantage::KeyPair.new(nil, kid: TOOL_KEY_KID)
                         FileUtils.mkdir_p(File.dirname(DEFAULT_TOOL_PRIVATE_KEY_PATH))
                         File.write(DEFAULT_TOOL_PRIVATE_KEY_PATH, generated_tool_key_pair.to_pem)
                         File.chmod(0o600, DEFAULT_TOOL_PRIVATE_KEY_PATH)
                         generated_tool_key_pair.to_pem
                       end

# Initialize the tool's RSA key pair
TOOL_KEY_PAIR = Lti::Advantage::KeyPair.new(TOOL_PRIVATE_KEY_PEM, kid: TOOL_KEY_KID)
LTI_REGISTRATION = Lti::Advantage::Registration.new(
  issuer: LMS_ISSUER,
  client_id: CLIENT_ID,
  authorization_endpoint: LMS_AUTH_URL,
  jwks_url: LMS_JWKS_URL,
  token_endpoint: LMS_TOKEN_ENDPOINT,
  token_audience: LMS_TOKEN_AUDIENCE,
  deployment_ids: [DEPLOYMENT_ID]
)
LTI_CLIENT = Lti::Advantage::Client.new(registrations: [LTI_REGISTRATION])

# 0. JWKS Endpoint (Exposes your public keys)
get "/lti/jwks" do
  content_type :json
  { keys: [TOOL_KEY_PAIR.public_jwk] }.to_json
end

get "/lti/jwk" do
  content_type :json
  TOOL_KEY_PAIR.public_jwk.to_json
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

  memberships_result = nil
  nrps_error = nil
  ags_summary = fetch_ags_summary(launch)

  if launch.nrps_available?
    begin
      memberships_result = fetch_nrps_memberships(launch)
    rescue Lti::Advantage::Error => e
      nrps_error = e.message
    end
  end

  content_type :html
  erb :launch_result, locals: {
    launch: launch,
    memberships_result: memberships_result,
    nrps_error: nrps_error,
    ags_summary: ags_summary
  }
rescue KeyError
  halt 400, "Missing id_token or state"
rescue Lti::Advantage::ReplayError => e
  halt 401, "Replay protection failed: #{e.message}"
rescue Lti::Advantage::JwtVerificationError => e
  halt 401, "JWT verification failed: #{e.message}"
rescue Lti::Advantage::ValidationError => e
  halt 400, "Launch validation failed: #{e.message}"
end

get "/nrps/members" do
  halt 410,
       [
         "This demo now fetches the first NRPS roster page during /lti/launch.",
         "Launch the tool from Canvas to view the embedded roster."
       ].join(" ")
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

@@launch_result
<!DOCTYPE html>
<html>
<head>
  <title>LTI Launch Demo</title>
  <style>
    body {
      font-family: sans-serif;
      line-height: 1.5;
      margin: 2rem;
    }

    table {
      border-collapse: collapse;
      margin-top: 1rem;
      width: 100%;
    }

    th,
    td {
      border: 1px solid #d1d5db;
      padding: 0.5rem;
      text-align: left;
      vertical-align: top;
    }

    code {
      background: #f3f4f6;
      border-radius: 0.25rem;
      padding: 0.1rem 0.3rem;
    }

    .section {
      margin-top: 2rem;
    }

    .status {
      font-weight: 600;
    }
  </style>
</head>
<body>
  <h1>Launch successful</h1>
  <p>Welcome, student! Your ID is: <strong><%= escape_html(launch.subject || "anonymous") %></strong>.</p>
  <p>Deployment ID: <code><%= escape_html(launch.deployment_id) %></code></p>
  <p>Roles: <%= summarized_roles(launch.roles) %></p>

  <div class="section">
    <h2>AGS grade services</h2>
    <% if ags_summary[:available] %>
      <p class="status">Canvas granted AGS capability for this launch.</p>
      <p>Lineitems URL: <code><%= escape_html(ags_summary[:lineitems_url]) %></code></p>
      <p>Lineitem URL: <code><%= escape_html(ags_summary[:lineitem_url]) %></code></p>

      <h3>Granted scopes</h3>
      <ul>
        <% ags_summary[:scopes].each do |scope| %>
          <li><code><%= escape_html(scope) %></code></li>
        <% end %>
      </ul>

      <% if ags_summary[:error] %>
        <p>The launch advertised AGS, but the demo could not complete the read-only AGS probe.</p>
        <p><code><%= escape_html(ags_summary[:error]) %></code></p>
      <% else %>
        <h3>Line items</h3>
        <% if ags_summary[:line_items].empty? %>
          <p>No line items were returned for this launch context.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Label</th>
                <th>ID</th>
                <th>Score Maximum</th>
                <th>Resource Link ID</th>
              </tr>
            </thead>
            <tbody>
              <% ags_summary[:line_items].each do |line_item| %>
                <tr>
                  <td><%= escape_html(line_item.label) %></td>
                  <td><code><%= escape_html(line_item.id) %></code></td>
                  <td><%= escape_html(line_item.score_maximum) %></td>
                  <td><%= escape_html(line_item.resource_link_id) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>

        <% if ags_summary[:results].any? %>
          <h3>Results</h3>
          <table>
            <thead>
              <tr>
                <th>User ID</th>
                <th>Result Score</th>
                <th>Result Maximum</th>
                <th>Comment</th>
              </tr>
            </thead>
            <tbody>
              <% ags_summary[:results].each do |result| %>
                <tr>
                  <td><%= escape_html(result.user_id) %></td>
                  <td><%= escape_html(result.result_score) %></td>
                  <td><%= escape_html(result.result_maximum) %></td>
                  <td><%= escape_html(result.comment) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      <% end %>
    <% else %>
      <p>This launch did not include the AGS claim.</p>
    <% end %>
  </div>

  <div class="section">
  <% if memberships_result %>
    <h2>NRPS roster</h2>
    <p>Context: <strong><%= escape_html(memberships_result.context&.fetch("title", nil) || "n/a") %></strong></p>

    <% if memberships_result.members.empty? %>
      <p>No members were returned for this launch.</p>
    <% else %>
      <table>
        <thead>
          <tr>
            <th>User ID</th>
            <th>Name</th>
            <th>Email</th>
            <th>Roles</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <% memberships_result.members.each do |member| %>
            <tr>
              <td><%= escape_html(member.user_id) %></td>
              <td><%= escape_html(member.name || "(hidden)") %></td>
              <td><%= escape_html(member.email || "(hidden)") %></td>
              <td><%= summarized_roles(member.roles) %></td>
              <td><%= escape_html(member.status) %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>

    <% if memberships_result.next_page_url || memberships_result.differences_url %>
      <p>This embedded demo renders only the first NRPS page during launch.</p>
    <% end %>
  <% elsif nrps_error %>
    <h2>NRPS roster unavailable</h2>
    <p>The launch advertised NRPS, but the demo could not fetch the roster.</p>
    <p><code><%= escape_html(nrps_error) %></code></p>
  <% else %>
    <p>This launch did not include the NRPS claim.</p>
  <% end %>
  </div>
</body>
</html>
