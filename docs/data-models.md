# Data Models - LTI 1.3 Messages

This document describes the structure of LTI 1.3 Advantage messages (ID Tokens).

## 1. LTI 1.3 Message (ID Token)

The `id_token` is a signed JWT (JSON Web Token) with two main parts: the header and the body (claims).

### Standard JWT Body Claims
- `iss` (string): The Issuer identifier (LMS URL).
- `aud` (string): The Audience (Tool's Client ID).
- `sub` (string): The Subject (User identifier).
- `exp` (integer): The Expiration time (Unix timestamp).
- `iat` (integer): The Issued At time (Unix timestamp).
- `nonce` (string): The random string sent during initiation.

### LTI 1.3 Specific Claims
- `https://purl.imsglobal.org/spec/lti/claim/message_type` (string): Usually `LtiResourceLinkRequest` for launches.
- `https://purl.imsglobal.org/spec/lti/claim/version` (string): Fixed to `1.3.0`.
- `https://purl.imsglobal.org/spec/lti/claim/resource_link` (object): Contains `id` and `title` of the link in the LMS.
- `https://purl.imsglobal.org/spec/lti/claim/roles` (array): List of URNs indicating the user's role (e.g., `http://purl.imsglobal.org/vocab/lis/v2/membership#Learner`).
- `https://purl.imsglobal.org/spec/lti/claim/context` (object): Information about the Course (id, label, title).

---

## 2. Key Structures

### JWK (JSON Web Key)
Used to expose public RSA keys to the Platform for signature verification.
- `kty` (string): Key Type (e.g., `RSA`).
- `n` (string): The modulus of the public key (Base64URL encoded).
- `e` (string): The exponent of the public key (Base64URL encoded).
- `kid` (string): Key ID (used to match keys in the `id_token` header).
- `alg` (string): Algorithm (usually `RS256`).
- `use` (string): Use (usually `sig`).
