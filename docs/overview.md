The flow should now be:
  canvas.docker (Browser) -> 192.168.2.57:4567 (Tool) -> canvas.docker (Browser) ->
  192.168.2.57:4567 (Tool).

## overview

LTI 1.3 (LTI Advantage) transitions from the older OAuth 1.0a based signing to a modern
  security model based on OAuth 2.0, OpenID Connect (OIDC), and JSON Web Tokens (JWT).

  Key Components to Implement
  

   1. OIDC Authentication Flow:
       * Login Initiation: The Platform (LMS) sends a request to the Tool's initiation
         endpoint.
       * Authentication Request: The Tool redirects the user back to the Platform's OIDC
         authorization endpoint.
       * Authentication Response: The Platform redirects the user to the Tool's launch URL with
         an id_token (JWT).


   2. Message Handling (JWT):
       * Verification: Validating the id_token signature using the Platform's public keys (via
         JWKS).
       * Claims Extraction: Parsing LTI-specific claims (e.g.,
         https://purl.imsglobal.org/spec/lti/claim/roles).


   3. LTI Advantage Services:
       * Assignment and Grading Service (AGS): Synchronizing grades and feedback.
       * Names and Role Provisioning Service (NRPS): Accessing course rosters and user roles.
       * Deep Linking: Enabling content selection within the LMS.

   4. Security & Key Management:
       * Providing a JWKS endpoint for the Platform to fetch the Tool's public keys.

###  TODO List
    - [ ] Infrastructure Setup
       - [ ] Add dependencies to lti-advantage.gemspec (e.g., jwt, json-jwt, faraday).
       - [ ] Define the base module structure for OIDC and Services.
    - [ ] OIDC Core Implementation
      - [ ] Implement LoginInitiation handler.
       - [ ] Implement AuthenticationResponse (Launch) handler.
       - [ ] Add JWT validation logic (Signature, Issuer, Audience, Expiry, Nonce).
    - [ ] JWKS Management
       - [ ] Implement utility to generate and serve JWKS for the Tool.
    - [ ] LTI Advantage Services
       - [ ] Implement AssignmentAndGradingService client.
       - [ ] Implement NamesAndRoleProvisioningService client.
       - [ ] Implement DeepLinking response builder.
    - [ ] Validation & Testing
       - [ ] Add RSpec tests for OIDC flows.
       - [ ] Add RSpec tests for JWT claim parsing.
       - [ ] Create a dummy Platform mock for integration testing.


LTI 1.3 is like a secure "handshake" between a Learning Management System
  (LMS, like Canvas or Blackboard) and your tool. 


  Instead of using passwords, they exchange JSON Web Tokens (JWTs)—which are like digital "ID
  badges." These badges are signed with a private key to prove they haven't been tampered with.

  Why we need these dependencies:

    * `jwt`: This gem allows us to create and read those "digital ID badges." We use it
    to verify that the LMS is actually who it says it is and to see which student is clicking
    on your tool.
    * `faraday`: This is used to make "phone calls" (HTTP requests) to the LMS. We need
    it when we want to send a grade back to the LMS or ask for a list of everyone in the
    class.


