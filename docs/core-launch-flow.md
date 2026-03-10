# Core Launch Flow - LTI 1.3 Advantage Handshake

This document provides a detailed breakdown of the LTI 1.3 Advantage handshake process, as implemented by the `Lti::Advantage::Client` API and the Sinatra demo app.

## Overview
LTI 1.3 Advantage uses the OpenID Connect (OIDC) "Third-Party Login Initiation" flow to launch a Tool from a Platform (LMS). This handshake ensures that the request is authenticated and authorized before the user is allowed access.

The runtime is organized around these classes:

- `Lti::Advantage::Registration` stores platform trust configuration.
- `Lti::Advantage::Client` is the main entrypoint for login initiation and launch validation.
- `Lti::Advantage::LaunchValidator` performs JWT, claim, and replay validation.
- `Lti::Advantage::Launch` exposes trusted launch claims.
- `Lti::Advantage::KeyPair` remains available for the demo tool's `/lti/jwks` endpoint.

---

## 1. OIDC Login Initiation (The Handshake Start)

The flow begins when the user clicks a link in the LMS. The LMS sends an initiation request (POST or GET) to the tool's initiation endpoint (`/oidc/init`).

- **Entry Point:** `demo/app.rb` -> `[:get, :post], "/oidc/init"`
- **Logic:** `Lti::Advantage::Client#authentication_request`

### Step-by-Step
1. **Request:** The LMS sends `iss`, `login_hint`, and `target_link_uri`.
2. **Validation:** `Client` parses the request with `OIDC::LoginInitiation` and resolves the configured `Registration`.
3. **Security:** `Client` generates one-time `state` and `nonce` values and stores them in replay-protection stores.
4. **Redirect:** The demo app responds with an auto-submitting POST form to the LMS authorization endpoint.
5. **Form Data:** Includes the tool's `client_id`, `redirect_uri`, `state`, `nonce`, and any LTI hints.

---

## 2. Resource Link Launch (The Handshake Completion)

After the OIDC "jump," the LMS redirects the user back to the tool's redirect URI (`/lti/launch`) with a signed `id_token`.

- **Entry Point:** `demo/app.rb` -> `post "/lti/launch"`
- **Logic:** `Lti::Advantage::Client#validate_launch!`

### Step-by-Step
1. **State Lookup:** The tool resolves the one-time `state` value from the configured store.
2. **JWT Verification:** `LaunchValidator` verifies the `id_token` signature using the LMS JWKS.
3. **OIDC Checks:** `iss`, `aud`, `iat`, `exp`, and `azp` rules are enforced.
4. **LTI Checks:** Required launch claims, deployment, target link, roles, and resource link structure are validated.
5. **Replay Protection:** `state` and `nonce` are consumed so the launch cannot be replayed.
6. **Trusted Launch Object:** The app receives a `Launch` value object and can read `subject`, `roles`, and `resource_link_id`.

---

## 3. Tool Public Keys (JWKS)

The demo app exposes its own public keys at `/lti/jwks` so the LMS can verify tool-signed messages in future LTI services.

- **Entry Point:** `demo/app.rb` -> `get "/lti/jwks"`
- **Logic:** `Lti::Advantage::KeyPair` generates and manages the tool's RSA keys.
