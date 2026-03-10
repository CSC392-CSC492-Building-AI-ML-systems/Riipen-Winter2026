# Overview

This repository now implements the LTI 1.3 core launch flow around a small public API:

- `Lti::Advantage::Registration` stores platform trust configuration.
- `Lti::Advantage::Client` handles login initiation and launch validation.
- `Lti::Advantage::Launch` exposes trusted launch data after validation.
- `Lti::Advantage::KeyPair` remains available for the demo tool's JWKS endpoint.

The browser flow is:

1. Platform -> Tool login initiation (`/oidc/init`)
2. Tool -> Platform OIDC authentication request
3. Platform -> Tool launch POST (`/lti/launch`) with `id_token` and `state`
4. Tool validates the launch and starts its own application session

Core security behaviors now covered by the library:

- signature verification using platform JWKS
- issuer, audience, `iat`, `exp`, and `azp` validation
- required LTI resource-link claims
- deployment and target-link consistency checks
- replay protection through one-time `state` and `nonce`

The demo app in `demo/app.rb` shows how to wire this into a Sinatra tool while still exposing `/lti/jwks` for tool-owned keys.

For a hands-on walkthrough, start with `README.md` and `docs/core-launch-flow.md`.

