# Core Launch Flow - LTI 1.3 Advantage Handshake

This document provides a detailed breakdown of the LTI 1.3 Advantage handshake process, as implemented in the `lti-advantage` library and the `sinatra` demo app.

## Overview
LTI 1.3 Advantage uses the OpenID Connect (OIDC) "Third-Party Login Initiation" flow to launch a Tool from a Platform (LMS). This handshake ensures that the request is authenticated and authorized before the user is allowed access.

---

## 1. OIDC Login Initiation (The Handshake Start)

The flow begins when the user clicks a link in the LMS. The LMS sends an initiation request (POST or GET) to the tool's initiation endpoint (`/oidc/init`).

- **Entry Point:** `demo/app.rb` -> `[:get, :post], "/oidc/init"`
- **Logic:** `Lti::Advantage::Oidc::LoginInitiation` class.

### Step-by-Step
1. **Request:** The LMS sends `iss`, `login_hint`, and `target_link_uri`.
2. **Validation:** The tool checks for these required parameters (`initiation.validate!`).
3. **Security:** The tool generates a random `state` and `nonce` and stores them in the user's session.
4. **Redirect:** The tool responds with an auto-submitting POST form that "jumps" the user back to the LMS's OIDC authorization endpoint.
5. **Form Data:** Includes the tool's `client_id`, `redirect_uri` (`/lti/launch`), `state`, and `nonce`.

---

## 2. Resource Link Launch (The Handshake Completion)

After the OIDC "jump," the LMS redirects the user back to the tool's redirect URI (`/lti/launch`) with a signed `id_token`.

- **Entry Point:** `demo/app.rb` -> `post "/lti/launch"`
- **Logic:** `Lti::Advantage::Message` class.

### Step-by-Step
1. **Verification of State:** The tool checks that the `state` in the request matches the `state` in the session.
2. **JWT Decoding:** The `id_token` is parsed as a JWT.
3. **Public Key Retrieval:** The tool fetches the LMS's public keys (JWKS). In the demo, this is a placeholder (`keys = []`), but in production, `Lti::Advantage::KeyStore` is used.
4. **Signature Verification:** `message.verify!` uses the public keys and the `RS256` algorithm to verify the JWT signature.
5. **Claim Validation:** Standard claims like `iss` (issuer) and `aud` (audience/client_id) are checked against the tool's configuration.
6. **Launch Type Check:** `message.resource_launch?` confirms this is a standard `LtiResourceLinkRequest`.
7. **User Identification:** `message.user_id` extracts the user's unique ID (`sub`).

---

## 3. Tool Public Keys (JWKS)

The tool must expose its own public keys at `/lti/jwks` so the LMS can verify messages signed by the tool (e.g., for Names and Roles or Assignment and Grade Services).

- **Entry Point:** `demo/app.rb` -> `get "/lti/jwks"`
- **Logic:** `Lti::Advantage::KeyPair` generates and manages the tool's RSA keys.
