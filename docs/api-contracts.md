# API Contracts - LTI 1.3 Launch Flow

This document details the endpoints used during the LTI 1.3 Advantage handshake.

## 1. OIDC Login Initiation

**Endpoint:** `POST/GET /oidc/init`
**Description:** Receives the initial OIDC login initiation request from the LMS (e.g., Canvas).

### Request Parameters
- `iss` (string, required): The Issuer identifier for the Platform.
- `login_hint` (string, required): Opaque string used by the Platform to identify the user session.
- `target_link_uri` (string, required): The actual resource URL the user wants to access.
- `lti_message_hint` (string, optional): Used by the Platform to identify the resource launch.

### Behavior
- Validates required parameters.
- Generates `state` and `nonce` in the configured replay-protection stores.
- Responds with an auto-submitting HTML form to the Platform's OIDC authorization endpoint.

---

## 2. LTI Launch (Redirect URI)

**Endpoint:** `POST /lti/launch`
**Description:** The final destination of the LTI handshake where the tool receives the signed ID Token.

### Request Parameters
- `id_token` (string, required): A signed JWT containing user identity and LTI claims.
- `state` (string, required): The random string sent during initiation to prevent CSRF.

### Behavior
- Validates the stored `state` value.
- Decodes and verifies the `id_token` (JWT) signature using the Platform's public keys.
- Validates standard claims (`iss`, `aud`, `exp`, `iat`, and `azp` when needed).
- Validates required LTI-specific claims and consumes `state` and `nonce` for replay protection.

---

## 3. Tool JWKS (Public Keys)

**Endpoint:** `GET /lti/jwks`
**Description:** Exposes the tool's public keys in JWKS format so the Platform can verify messages signed by the tool.

### Response
- `keys` (array): A list of JSON Web Keys (JWK).
