# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# NRPS Demo Route — add this block to demo/app.rb
#
# Pre-requisites already in app.rb:
#   CLIENT_ID, LMS_ISSUER, TOOL_KEY_PAIR
#
# The LMS must advertise its OAuth2 token endpoint.  For Canvas this is
# typically: #{LMS_BROWSER_URL}/login/oauth2/token
# ─────────────────────────────────────────────────────────────────────────────

# Token endpoint for Canvas (adjust if using a different LMS)
LMS_TOKEN_ENDPOINT = "#{LMS_BROWSER_URL}/login/oauth2/token"

# 3. NRPS — course roster endpoint
#    Hit this AFTER a successful LTI launch so the session holds the
#    memberships URL extracted from the id_token.
#
#    In the launch handler (post "/lti/launch"), store the URL:
#      session[:nrps_memberships_url] = message.context_memberships_url
#
get "/nrps/members" do
  memberships_url = session[:nrps_memberships_url]
  halt 400, "No memberships URL in session. Complete an LTI launch first." unless memberships_url

  # 1. Get an access token from the LMS
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

  # 2. Fetch the roster
  role_filter = params[:role]  # optional ?role=Learner
  nrps = Lti::Advantage::Services::NamesRoleService.new(
    memberships_url: memberships_url,
    access_token:    access_token
  )

  begin
    result = nrps.memberships(role: role_filter.presence)
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to fetch memberships: #{e.message}"
  end

  # 3. Render a simple HTML table
  content_type :html
  rows = result.members.map do |m|
    short_roles = m.roles.map { |r| r.split("#").last }.join(", ")
    "<tr><td>#{m.user_id}</td><td>#{m.name || "(hidden)"}</td>" \
      "<td>#{m.email || "(hidden)"}</td><td>#{short_roles}</td><td>#{m.status}</td></tr>"
  end

  next_link = result.next_page_url ? "<p><a href='#{result.next_page_url}'>Next page →</a></p>" : ""

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head><title>Course Roster</title></head>
    <body>
      <h1>Course Roster (#{result.members.size} members#{role_filter ? " – #{role_filter}" : ""})</h1>
      <p>Context: #{result.context&.fetch("title", "n/a")}</p>
      <table border="1" cellpadding="4">
        <thead>
          <tr><th>User ID</th><th>Name</th><th>Email</th><th>Roles</th><th>Status</th></tr>
        </thead>
        <tbody>
          #{rows.join("\n")}
        </tbody>
      </table>
      #{next_link}
      <p><a href="/nrps/members?role=Learner">Filter: Learners only</a> |
         <a href="/nrps/members?role=Instructor">Filter: Instructors only</a> |
         <a href="/nrps/members">Show all</a></p>
    </body>
    </html>
  HTML
end

# ─────────────────────────────────────────────────────────────────────────────
# In your existing post "/lti/launch" handler, add this line after parsing
# the message object to persist the memberships URL for the /nrps/members route:
#
#   session[:nrps_memberships_url] = message.context_memberships_url
# ─────────────────────────────────────────────────────────────────────────────