# Lti::Advantage

`lti-advantage` provides a focused implementation of the LTI 1.3 core launch flow for Ruby applications, with initial support for LTI Advantage NRPS roster access.

Implemented core behaviors:

- Validate LTI OIDC login initiation requests
- Build OIDC authentication requests (`response_type=id_token`, `response_mode=form_post`, `scope=openid`, `prompt=none`)
- Validate signed `id_token` launch messages against platform JWKS
- Enforce required LTI 1.3 resource link claims
- Protect against replay attacks with one-time `state` and `nonce` values
- Read the NRPS claim from a validated launch
- Request OAuth access tokens for LTI services with JWT client assertions
- Fetch course memberships through the NRPS v2 memberships endpoint

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

`AccessToken` uses the platform token endpoint configured on the selected `Registration`, and `NamesRoleService#memberships` normalizes short role filters like `"Learner"` to their IMS membership role URIs while validating `limit` and `resource_link_id`. `NamesRoleService#memberships_from_url` rejects cross-origin follow-up URLs by default so LMS bearer tokens stay scoped to the original NRPS origin; pass `enforce_same_origin: false` only if your platform legitimately paginates across multiple origins.

## Demo app and tool JWKS

The Sinatra demo in `demo/app.rb` uses the `Client` flow for login and launch validation, stores the NRPS memberships URL only after a successful launch, exchanges a JWT client assertion for an NRPS access token, and proxies `next_page_url` / `differences_url` back through opaque server-side cursors so the LMS bearer token never needs to touch the browser and the browser never chooses the follow-up URL that receives it.

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
