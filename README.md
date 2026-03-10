# Lti::Advantage

`lti-advantage` provides a focused implementation of the LTI 1.3 core launch flow for Ruby applications.

Implemented core behaviors:

- Validate LTI OIDC login initiation requests
- Build OIDC authentication requests (`response_type=id_token`, `response_mode=form_post`, `scope=openid`, `prompt=none`)
- Validate signed `id_token` launch messages against platform JWKS
- Enforce required LTI 1.3 resource link claims
- Protect against replay attacks with one-time `state` and `nonce` values

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

## Demo app and tool JWKS

The Sinatra demo in `demo/app.rb` uses the new `Client` flow for login and launch validation while keeping `Lti::Advantage::KeyPair` to publish the tool's public key at `/lti/jwks`.

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
