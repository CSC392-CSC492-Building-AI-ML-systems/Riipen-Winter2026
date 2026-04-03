# frozen_string_literal: true

require "json"
require "sinatra/base"

module SpecSupport
  class TestToolApp < Sinatra::Base
    set :protection, except: %i[http_origin remote_token session_hijacking frame_options host_authorization]

    class << self
      def default_tool_host
        ENV["TOOL_HOST"] || "127.0.0.1:4567"
      end

      def default_tool_launch_url
        "http://#{default_tool_host}/lti/launch"
      end

      def default_key_pair
        @default_key_pair ||= Lti::Advantage::KeyPair.new(nil, kid: ENV["TOOL_KEY_KID"] || "test-tool-key")
      end

      def default_registration
        Lti::Advantage::Registration.new(
          issuer: ENV["LMS_ISSUER"] || "http://127.0.0.1:3000",
          client_id: ENV["CLIENT_ID"] || "10000000000001",
          authorization_endpoint: ENV["LMS_AUTH_URL"] || "http://canvas.docker/api/lti/authorize_redirect",
          jwks_url: ENV["LMS_JWKS_URL"] || "http://127.0.0.1:3000/api/lti/security/jwks",
          token_endpoint: ENV["LMS_TOKEN_ENDPOINT"] || "http://canvas.docker/login/oauth2/token",
          token_audience: ENV["LMS_TOKEN_AUDIENCE"],
          deployment_ids: [ENV["LTI_DEPLOYMENT_ID"] || "test-deployment-123"]
        )
      end

      def build_client(registration)
        Lti::Advantage::Client.new(registrations: [registration])
      end

      def configure_with(key_pair: default_key_pair, registration: default_registration, client: nil)
        set :tool_key_pair, key_pair
        set :registration, registration
        set :tool_launch_url, default_tool_launch_url
        set :client, client || build_client(registration)
      end

      def reset_configuration!
        configure_with
      end
    end

    helpers do
      def escape_html(value)
        Rack::Utils.escape_html(value.to_s)
      end

      def summarized_roles(roles)
        Array(roles).map { |role| escape_html(role.to_s.split("#").last) }.join(", ")
      end

      def redirect_form(url, params)
        hidden_inputs = params.map do |key, value|
          %(<input type="hidden" name="#{escape_html(key)}" value="#{escape_html(value)}">)
        end.join("\n")

        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Redirecting...</title>
          </head>
          <body onload="document.forms[0].submit()">
            <form action="#{escape_html(url)}" method="POST">
              #{hidden_inputs}
              <noscript><input type="submit" value="Click here to continue"></noscript>
            </form>
          </body>
          </html>
        HTML
      end

      def launch_result_body(launch:, memberships_result:, nrps_error:, ags_summary:)
        ags_section = build_ags_section(ags_summary)

        nrps_section = if memberships_result
                         build_memberships_section(memberships_result)
                       elsif nrps_error
                         <<~HTML
                           <h2>NRPS roster unavailable</h2>
                           <p>The launch advertised NRPS, but the application could not fetch the roster.</p>
                           <p><code>#{escape_html(nrps_error)}</code></p>
                         HTML
                       else
                         "<p>This launch did not include the NRPS claim.</p>"
                       end

        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>LTI Launch Result</title>
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
            </style>
          </head>
          <body>
            <h1>Launch successful</h1>
            <p>Welcome, student! Your ID is: <strong>#{escape_html(launch.subject || "anonymous")}</strong>.</p>
            <p>Deployment ID: <code>#{escape_html(launch.deployment_id)}</code></p>
            <p>Roles: #{summarized_roles(launch.roles)}</p>
            #{ags_section}
            #{nrps_section}
          </body>
          </html>
        HTML
      end

      def build_ags_section(ags_summary)
        return "<p>This launch did not include the AGS claim.</p>" unless ags_summary[:available]

        scopes = ags_summary[:scopes].map { |scope| "<li><code>#{escape_html(scope)}</code></li>" }.join
        line_item_rows = ags_summary[:line_items].map do |line_item|
          <<~HTML
            <tr>
              <td>#{escape_html(line_item.label)}</td>
              <td><code>#{escape_html(line_item.id)}</code></td>
              <td>#{escape_html(line_item.score_maximum)}</td>
              <td>#{escape_html(line_item.resource_link_id)}</td>
            </tr>
          HTML
        end.join
        result_rows = ags_summary[:results].map do |result|
          <<~HTML
            <tr>
              <td>#{escape_html(result.user_id)}</td>
              <td>#{escape_html(result.result_score)}</td>
              <td>#{escape_html(result.result_maximum)}</td>
              <td>#{escape_html(result.comment)}</td>
            </tr>
          HTML
        end.join

        operational_section = if ags_summary[:error]
                                <<~HTML
                                  <p>The launch advertised AGS, but the demo could not complete the read-only AGS probe.</p>
                                  <p><code>#{escape_html(ags_summary[:error])}</code></p>
                                HTML
                              else
                                <<~HTML
                                  <h3>Line items</h3>
                                  #{ags_summary[:line_items].empty? ? "<p>No line items were returned for this launch context.</p>" : <<~TABLE}
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
                                        #{line_item_rows}
                                      </tbody>
                                    </table>
                                  TABLE
                                  #{ags_summary[:results].any? ? <<~TABLE : ""}
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
                                        #{result_rows}
                                      </tbody>
                                    </table>
                                  TABLE
                                HTML
                              end

        <<~HTML
          <div class="section">
            <h2>AGS grade services</h2>
            <p>Canvas granted AGS capability for this launch.</p>
            <p>Lineitems URL: <code>#{escape_html(ags_summary[:lineitems_url])}</code></p>
            <p>Lineitem URL: <code>#{escape_html(ags_summary[:lineitem_url])}</code></p>
            <h3>Granted scopes</h3>
            <ul>
              #{scopes}
            </ul>
            #{operational_section}
          </div>
        HTML
      end

      def build_memberships_section(memberships_result)
        rows = memberships_result.members.map do |member|
          <<~HTML
            <tr>
              <td>#{escape_html(member.user_id)}</td>
              <td>#{escape_html(member.name || "(hidden)")}</td>
              <td>#{escape_html(member.email || "(hidden)")}</td>
              <td>#{summarized_roles(member.roles)}</td>
              <td>#{escape_html(member.status)}</td>
            </tr>
          HTML
        end.join

        pagination_note = if memberships_result.next_page_url || memberships_result.differences_url
                            "<p>This embedded response renders only the first NRPS page during launch.</p>"
                          else
                            ""
                          end

        <<~HTML
          <h2>NRPS roster</h2>
          <p>Context: <strong>#{escape_html(memberships_result.context&.fetch("title", nil) || "n/a")}</strong></p>
          #{memberships_result.members.empty? ? "<p>No members were returned for this launch.</p>" : <<~TABLE}
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
                #{rows}
              </tbody>
            </table>
          TABLE
          #{pagination_note}
        HTML
      end

      def fetch_nrps_memberships(launch)
        access_token = Lti::Advantage::Services::AccessToken.new(
          key_pair: settings.tool_key_pair,
          client_id: launch.registration.client_id,
          token_endpoint: launch.registration.token_endpoint,
          token_audience: launch.registration.token_audience,
          scope: Lti::Advantage::Services::NamesRoleService::SCOPE,
          deployment_id: launch.deployment_id
        ).fetch

        Lti::Advantage::Services::NamesRoleService.new(
          memberships_url: launch.context_memberships_url,
          access_token: access_token,
          enforce_same_origin: true
        ).memberships
      end

      def fetch_ags_summary(launch)
        return { available: false } unless launch.ags_available?

        ags_client = settings.client.ags_service_client(launch: launch, key_pair: settings.tool_key_pair)
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

    %i[get post].each do |method|
      send(method, "/oidc/init") do
        auth_request = settings.client.authentication_request(
          login_params: params,
          redirect_uri: settings.tool_launch_url
        )

        content_type :html
        redirect_form(auth_request.authorization_endpoint, auth_request.parameters)
      rescue Lti::Advantage::ValidationError => e
        halt 400, "Validation Error: #{e.message}"
      end
    end

    post "/lti/launch" do
      launch = settings.client.validate_launch!(
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
      launch_result_body(launch: launch, memberships_result: memberships_result, nrps_error: nrps_error, ags_summary: ags_summary)
    rescue KeyError
      halt 400, "Missing id_token or state"
    rescue Lti::Advantage::ReplayError => e
      halt 401, "Replay protection failed: #{e.message}"
    rescue Lti::Advantage::JwtVerificationError => e
      halt 401, "JWT verification failed: #{e.message}"
    rescue Lti::Advantage::ValidationError => e
      halt 400, "Launch validation failed: #{e.message}"
    end

    get "/lti/jwks" do
      content_type :json
      { keys: [settings.tool_key_pair.public_jwk] }.to_json
    end

    get "/lti/jwk" do
      content_type :json
      settings.tool_key_pair.public_jwk.to_json
    end

    get "/nrps/members" do
      halt 410,
           [
             "This application now fetches the first NRPS roster page during /lti/launch.",
             "Launch the tool to view the embedded roster."
           ].join(" ")
    end
  end
end

SpecSupport::TestToolApp.reset_configuration!
