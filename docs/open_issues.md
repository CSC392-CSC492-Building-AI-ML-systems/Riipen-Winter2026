## Core Launch
- http:// URLs are accepted which could present security vulnerabilities.

## NRPS
- Developer interface is somewhat low level. For example, launch.registration.token_endpoint must be manually wired into Lti::Advantage::Services::AccessToken.new
- lib/lti/advantage/services/access_token.rb does not cache tokens or track expiry.
- Poor differences interface. Developers must manually call memberships_from_url(result.differences_url) using the generic method in lib/lti/advantage/services/names_role_service.rb
