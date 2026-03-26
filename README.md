# Lti::Advantage

`lti-advantage` provides a focused implementation of the LTI 1.3 core launch flow for Ruby applications, with support for LTI Advantage NRPS roster access and AGS grade services.

Implemented core behaviors:

- Validate LTI OIDC login initiation requests
- Build OIDC authentication requests (`response_type=id_token`, `response_mode=form_post`, `scope=openid`, `prompt=none`)
- Validate signed `id_token` launch messages against platform JWKS
- Enforce required LTI 1.3 resource link claims
- Protect against replay attacks with one-time `state` and `nonce` values
- Read the NRPS claim from a validated launch
- Request OAuth access tokens for LTI services with JWT client assertions
- Fetch course memberships through the NRPS v2 memberships endpoint
- Read the AGS endpoint claim from a validated launch
- Publish scores, fetch results, and manage line items through AGS

## Installation

Add this line to your application's Gemfile:

```ruby
gem "lti-advantage"
```

Then run:

```bash
bundle install
```

## Quick start

```ruby
require "lti/advantage"

registration = Lti::Advantage::Registration.new(
  issuer: "https://platform.example",
  client_id: "client-123",
  authorization_endpoint: "https://platform.example/oidc/auth",
  jwks_url: "https://platform.example/.well-known/jwks.json",
  token_endpoint: "https://platform.example/login/oauth2/token",
  # Optional when the LMS expects a different JWT aud value.
  token_audience: "https://platform.example/login/oauth2/token",
  deployment_ids: ["deployment-123"]
)

client = Lti::Advantage::Client.new(registrations: [registration])
```

### 1) Handle login initiation

```ruby
request = client.authentication_request(
  login_params: params,
  redirect_uri: "https://tool.example/lti/launch"
)

redirect_to request.url
```

`params` must include:

- `iss`
- `login_hint`
- `target_link_uri`

Optional values such as `lti_message_hint`, `lti_deployment_id`, and `client_id` are supported.

### 2) Handle launch

```ruby
launch = client.validate_launch!(
  id_token: params.fetch("id_token"),
  state: params.fetch("state")
)

puts launch.message_type
puts launch.resource_link_id
puts launch.roles
```

Validation includes:

- JWT signature verification using platform JWKS
- `iss`, `aud`, `iat`, and `exp` checks
- Required LTI claims including message type, version, deployment, target link, resource link, and roles
- One-time use replay protection for both `state` and `nonce`

Anonymous launches are supported (`sub` may be omitted).

### 3) Access NRPS memberships

```ruby
return unless launch.nrps_available?

token_endpoint = launch.registration.token_endpoint
raise "Configure registration.token_endpoint for NRPS" if token_endpoint.nil?

access_token = Lti::Advantage::Services::AccessToken.new(
  key_pair: TOOL_KEY_PAIR,
  client_id: launch.registration.client_id,
  token_endpoint: token_endpoint,
  token_audience: launch.registration.token_audience,
  scope: Lti::Advantage::Services::NamesRoleService::SCOPE,
  deployment_id: launch.deployment_id
).fetch

memberships = Lti::Advantage::Services::NamesRoleService.new(
  memberships_url: launch.context_memberships_url,
  access_token: access_token
)

result = memberships.memberships(role: "Learner", limit: 50)
result.members.each do |member|
  puts [member.user_id, member.name, member.roles].inspect
end
```

`launch.nrps_available?` only reflects what the launch advertises: it checks for a valid `context_memberships_url` plus at least one supported NRPS service version. It does not verify your `Registration` configuration, token issuance, granted scopes, or downstream HTTP success.

`AccessToken` uses the platform token endpoint configured on the selected `Registration`, and `NamesRoleService#memberships` normalizes short role filters like `"Learner"` to their IMS membership role URIs while validating `limit` and `resource_link_id`. `NamesRoleService#memberships_from_url` rejects cross-origin follow-up URLs by default so LMS bearer tokens stay scoped to the original NRPS origin; pass `enforce_same_origin: false` only if your platform legitimately paginates across multiple origins, or provide `allowed_origins:` to keep same-origin enforcement enabled while allowlisting known pagination hosts.

### 4) Access AGS services

```ruby
return unless launch.ags_available?

ags = client.ags_service_client(
  launch: launch,
  key_pair: TOOL_KEY_PAIR
)

score_service = ags.score_service
score_service.publish(
  score: {
    user_id: launch.subject,
    timestamp: Time.now.utc.iso8601(3),
    activity_progress: "Completed",
    grading_progress: "FullyGraded",
    score_given: 9,
    score_maximum: 10
  }
)

results = ags.result_service.list_all
line_items = ags.line_item_service.list_all(limit: 50)
```

AGS launches may include both NRPS and AGS claims in the same `id_token`. `Client#validate_launch!` preserves both, so a single validated `Launch` can drive roster and grade workflows.

`launch.ags_available?` only reflects whether the launch advertises at least one usable AGS endpoint plus granted scopes. It does not verify token issuance, later line item discovery, or downstream HTTP success.

`Client#ags_service_client` uses the `Registration` token settings, validates granted AGS scopes per request, caches access tokens by scope set, tracks score timestamps per service client instance so duplicate or out-of-order publishes are rejected before they are sent, and rejects cross-origin AGS follow-up URLs by default so platform bearer tokens stay scoped to launch-advertised AGS origins. Pass `enforce_same_origin: false` only if your LMS legitimately paginates across multiple origins, or provide `allowed_origins:` to allowlist known pagination hosts while keeping origin checks enabled.

## Demo app and tool JWKS

The Sinatra demo in `demo/app.rb` uses the `Client` flow for login and launch validation, exchanges a JWT client assertion for an NRPS access token during launch, and renders the first NRPS roster page directly in the embedded launch response so the Canvas demo does not depend on browser session cookies. If your LMS expects a distinct JWT audience for token exchange, set `LMS_TOKEN_AUDIENCE` so the demo passes that override through the registration. For local Canvas Docker setups, prefer a pasted `public_jwk` over an HTTP `public_jwk_url`; the demo exposes both `/lti/jwks` and a copy/paste-friendly `/lti/jwk` endpoint, and it persists a reusable dev private key under `tmp/demo-tool-private-key.pem` by default so the pasted JWK stays valid across restarts.

## API Documentation (RDoc)

Comprehensive API documentation is embedded directly in `lib/**/*.rb`, with an additional overview at `docs/rdoc/overview.rdoc`.

Generate HTML docs with:

```bash
bundle exec rake rdoc
```

Open `doc/index.html` after generation.

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
```

## License

MIT
