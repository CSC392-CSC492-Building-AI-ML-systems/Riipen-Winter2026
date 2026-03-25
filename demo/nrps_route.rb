# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# NRPS Demo Route — add this block to demo/app.rb
#
# Pre-requisites already in app.rb:
#   LTI_REGISTRATION, TOOL_KEY_PAIR
#
# The LMS must advertise its OAuth2 token endpoint.  For Canvas this is
# typically: #{LMS_BROWSER_URL}/login/oauth2/token
# ─────────────────────────────────────────────────────────────────────────────

# 3. NRPS — course roster endpoint
#    Hit this AFTER a successful LTI launch so the session holds the
#    memberships URL extracted from the id_token.
#
#    In the validated launch handler (post "/lti/launch"), store the URL:
#      session[:nrps_follow_ups] = {}
#      session[:nrps_memberships_url] = launch.context_memberships_url
#      session[:lti_deployment_id] = launch.deployment_id
#
#    To follow `next_page_url` or `differences_url`, store them server-side and
#    proxy them back through your tool route with an opaque `cursor` rather than
#    accepting a raw URL from the browser.
#
# rubocop:disable Metrics/BlockLength
get "/nrps/members" do
  memberships_url = session[:nrps_memberships_url]
  halt 400, "No memberships URL in session. Complete an LTI launch first." unless memberships_url

  stored_follow_ups = session[:nrps_follow_ups] ||= {}
  unless params[:page_url].to_s.strip.empty?
    halt 400,
         "page_url cannot be supplied directly; use the provided cursor path"
  end

  cursor = params[:cursor].to_s.strip
  cursor = nil if cursor.empty?

  # 1. Get an access token from the LMS
  token_service = Lti::Advantage::Services::AccessToken.new(
    key_pair: TOOL_KEY_PAIR,
    client_id: LTI_REGISTRATION.client_id,
    token_endpoint: LTI_REGISTRATION.token_endpoint,
    scope: Lti::Advantage::Services::NamesRoleService::SCOPE,
    deployment_id: session[:lti_deployment_id]
  )

  begin
    access_token = token_service.fetch
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to obtain access token: #{e.message}"
  end

  # 2. Fetch the roster
  page_url = cursor ? stored_follow_ups[cursor] : nil
  halt 400, "Invalid or expired NRPS cursor" if cursor && page_url.nil?

  role_filter = params[:role].to_s.strip
  role_filter = nil if role_filter.empty?

  halt 400, "cursor cannot be combined with role" if cursor && role_filter

  nrps = Lti::Advantage::Services::NamesRoleService.new(
    memberships_url: memberships_url,
    access_token: access_token,
    enforce_same_origin: true
  )

  begin
    result = if page_url
               nrps.memberships_from_url(page_url)
             else
               nrps.memberships(role: role_filter)
             end
    stored_follow_ups.delete(cursor) if cursor
  rescue Lti::Advantage::Error => e
    halt 500, "Failed to fetch memberships: #{e.message}"
  end

  # 3. Render a simple HTML table
  content_type :html
  escape = ->(value) { Rack::Utils.escape_html(value.to_s) }

  rows = result.members.map do |m|
    short_roles = m.roles.map { |r| escape.call(r.split("#").last) }.join(", ")
    "<tr><td>#{escape.call(m.user_id)}</td><td>#{escape.call(m.name || "(hidden)")}</td>" \
      "<td>#{escape.call(m.email || "(hidden)")}</td><td>#{short_roles}</td><td>#{escape.call(m.status)}</td></tr>"
  end

  next_link = if result.next_page_url
                next_cursor = SecureRandom.urlsafe_base64(24)
                stored_follow_ups[next_cursor] = result.next_page_url
                encoded_cursor = URI.encode_www_form(cursor: next_cursor)
                "<p><a href='/nrps/members?#{encoded_cursor}'>Next page -&gt;</a></p>"
              else
                ""
              end

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head><title>Course Roster</title></head>
    <body>
      <h1>Course Roster (#{result.members.size} members#{role_filter ? " - #{escape.call(role_filter)}" : ""})</h1>
      <p>Context: #{escape.call(result.context&.fetch("title", "n/a"))}</p>
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
# rubocop:enable Metrics/BlockLength

# ─────────────────────────────────────────────────────────────────────────────
# In your existing post "/lti/launch" handler, add these lines after
# successfully validating the launch to persist NRPS data for /nrps/members:
#
#   session[:nrps_follow_ups] = {}
#   session[:nrps_memberships_url] = launch.context_memberships_url
#   session[:lti_deployment_id] = launch.deployment_id
# ─────────────────────────────────────────────────────────────────────────────
