---
project_name: 'Riipen-Winter2026'
user_name: 'Mary'
date: '2026-02-26'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 24
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Language:** Ruby 3.4.0 (Target: 3.0+)
- **Web Framework:** Sinatra 4.2.1 (Micro-framework for APIs and routing)
- **Application Server:** Puma 7.2.0 (Multi-threaded web server)
- **HTTP Client:** Faraday 2.14.1 (Middleware-based HTTP requests)
- **Authentication:** JWT 2.10.2 (Critical for LTI 1.3 token handling)
- **Testing:** RSpec 3.13.2 (Unit and integration testing)
- **Linting:** RuboCop 1.84.2 (Enforced double-quote style)

---

## Critical Implementation Rules

### Language-Specific Rules (Ruby)

- **Double Quotes:** Use double quotes (`"string"`) for all string literals as enforced by RuboCop.
- **Frozen Strings:** Include `# frozen_string_literal: true` at the top of every `.rb` file.
- **Namespacing:** All library code must reside under the `Lti::Advantage` module.
- **Keywords:** Use keyword arguments (e.g., `def my_method(id:, name:)`) for methods with multiple parameters to improve clarity.
- **YARD Docs:** Document method parameters and returns using `# @param` and `# @return` tags.

### Framework-Specific Rules (Sinatra & LTI)

- **Route Handling:** Use `halt` (e.g., `halt 400`, `halt 401`) for early returns in route handlers during validation failures.
- **Session Security:** Store `lti_state` and `lti_nonce` in the session and verify them during the launch flow.
- **Iframe Compatibility:** For cookies to work in an LMS iframe, use `SameSite=None` and `Secure=True` in production (though relax `Secure` for local HTTP development).
- **Multi-Method Routes:** Handle both GET and POST for initiation endpoints using `[:get, :post].each`.

### Testing Rules (RSpec)

- **Directory Mirroring:** Maintain a 1-to-1 mapping between `lib/` and `spec/` (e.g., `lib/a.rb` -> `spec/a_spec.rb`).
- **Subject & Let:** Use `let` for setup and `subject { described_class.new(...) }` for the object under test.
- **Expect Syntax:** Use the `expect(...).to ...` syntax. Global monkey patching is disabled.
- **Crypto Mocks:** Generate real 2048-bit RSA keys with `OpenSSL::PKey::RSA` when testing token signing.

### Code Quality & Style Rules

- **Linting Compliance:** All code MUST pass `rubocop` checks.
- **Naming:** Use `snake_case` for files/folders and `PascalCase` for classes/modules.
- **Error Handling:** Raise `Lti::Advantage::Error` (or its subclasses) for domain-specific failures.

### Development Workflow Rules

- **Lockfile Integrity:** Always update `Gemfile.lock` when modifying dependencies.
- **Mirroring Requirement:** No feature PR is complete without its corresponding spec in the mirrored directory.
- **Demo Prototype:** Update `demo/app.rb` whenever core library logic changes to ensure the prototype remains functional.

### Critical Don't-Miss Rules (Anti-Patterns & Edge Cases)

- **Dynamic IPs (CRITICAL):** The `TOOL_HOST` and `LMS_ISSUER` in `demo/app.rb` use hardcoded private IPs. If the developer's private IP changes (e.g., on a different Wi-Fi), these constants **MUST** be updated to prevent LTI launch failures.
- **JWT Verification:** Always verify `iss` (issuer) and `aud` (client ID) during token validation to prevent cross-tenant attacks.
- **Private Data:** Never log full `id_token` payloads or sensitive PII (Personally Identifiable Information) from the JWT.
- **Key Strength:** Never use RSA keys weaker than 2048-bit for LTI signatures.

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code.
- Follow ALL rules exactly as documented.
- When in doubt, prefer the more restrictive option.
- Update this file if new patterns emerge.

**For Humans:**
- Keep this file lean and focused on agent needs.
- Update when the technology stack or private IP requirements change.
- Review quarterly to remove rules that become obvious over time.

_Last Updated: 2026-02-26_
