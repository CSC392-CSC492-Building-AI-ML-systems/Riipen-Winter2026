# Data Models - LTI 1.3 Core Launch

This document describes the main runtime objects used by the core launch implementation.

## 1. Registration

`Lti::Advantage::Registration` models the trust relationship between the tool and a platform.

- `issuer` (string): The platform issuer identifier.
- `client_id` (string): The tool's client id issued by the platform.
- `authorization_endpoint` (string): Platform OIDC authorization URL.
- `jwks_url` (string): Platform JWKS URL.
- `deployment_ids` (array): Allowed deployment ids for this registration.
- `algorithms` (array): Accepted JWT signature algorithms.

---

## 2. Launch Token (`id_token`)

The `id_token` is a signed JWT (JSON Web Token) with two main parts: the header and the body (claims).

### Standard JWT Body Claims
- `iss` (string): The Issuer identifier (LMS URL).
- `aud` (string): The Audience (Tool's Client ID).
- `sub` (string): The Subject (User identifier).
- `exp` (integer): The Expiration time (Unix timestamp).
- `iat` (integer): The Issued At time (Unix timestamp).
- `nonce` (string): The random string sent during initiation.
- `azp` (string): Authorized party, required when `aud` has multiple values.

### LTI 1.3 Specific Claims
- `https://purl.imsglobal.org/spec/lti/claim/message_type` (string): Usually `LtiResourceLinkRequest` for launches.
- `https://purl.imsglobal.org/spec/lti/claim/version` (string): Fixed to `1.3.0`.
- `https://purl.imsglobal.org/spec/lti/claim/deployment_id` (string): The tool deployment identifier.
- `https://purl.imsglobal.org/spec/lti/claim/target_link_uri` (string): Launch URL expected by the tool.
- `https://purl.imsglobal.org/spec/lti/claim/resource_link` (object): Contains `id` and `title` of the link in the LMS.
- `https://purl.imsglobal.org/spec/lti/claim/roles` (array): List of URNs indicating the user's role (e.g., `http://purl.imsglobal.org/vocab/lis/v2/membership#Learner`).
- `https://purl.imsglobal.org/spec/lti/claim/context` (object): Information about the Course (id, label, title).

---

## 3. Validated Launch Object

`Lti::Advantage::Launch` wraps the verified JWT payload and provides convenience accessors:

- `message_type`
- `version`
- `deployment_id`
- `target_link_uri`
- `roles`
- `subject`
- `resource_link`
- `resource_link_id`

---

## 4. Key Structures

### JWK (JSON Web Key)
Used both for platform signing keys and for the tool's own published public keys.
- `kty` (string): Key Type (e.g., `RSA`).
- `n` (string): The modulus of the public key (Base64URL encoded).
- `e` (string): The exponent of the public key (Base64URL encoded).
- `kid` (string): Key ID (used to match keys in the `id_token` header).
- `alg` (string): Algorithm (usually `RS256`).
- `use` (string): Use (usually `sig`).
