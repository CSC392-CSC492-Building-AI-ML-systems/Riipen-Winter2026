# Test Framework Setup

This project uses a hybrid testing strategy combining **RSpec** for backend unit/integration testing and **Playwright** for system-level/E2E smoke testing.

## Frameworks Overview

1.  **RSpec (Ruby)**
    *   **Scope:** **Unit tests** for core logic, Integration (API) tests for Sinatra endpoints.
    *   **Location:** `spec/`
    *   **Key Helpers:** `spec/spec_helper.rb`, `spec/support/factories.rb`.

2.  **Playwright (TypeScript/Node.js)**
    *   **Scope:** **Smoke tests** for the LTI 1.3 OIDC handshake flow.
    *   **Location:** `tests/e2e/`
    *   **Configuration:** `playwright.config.ts`.

3.  **Pact (Contract Testing)**
    *   **Scope:** Consumer and Provider **contract tests**.
    *   **Location:** `pact/`

---

## Setup Instructions

### Prerequisites
- Ruby (see `.ruby-version`)
- Node.js (see `.nvmrc`)

### Installation
1.  **Ruby Dependencies:**
    ```bash
    bundle install
    ```
2.  **Node.js Dependencies:**
    ```bash
    npm install
    npx playwright install --with-deps
    ```

---

## Running Tests

### Using Makefile (Convenience)
Run all tests (Ruby + JS):
```bash
make test
```

Run only Playwright E2E tests:
```bash
make test-e2e
```

### Individual Runners
**RSpec:**
```bash
bundle exec rspec
```

**Playwright:**
```bash
npx playwright test          # Run all tests
npx playwright test --ui     # Run in UI mode
npx playwright test --debug  # Debug mode
```

---

## Architecture & Best Practices

### Test Data (Factories)
- **Ruby:** Use `TestFactories` module in `spec/support/factories.rb`.
- **TypeScript:** Use `@faker-js/faker` for generating unique test data in `tests/support`.

### Selectors
- Prefer `data-testid` attributes for stable UI testing.
- Use Playwright's `locator` and `expect` with automatic retries.

### Isolation & Cleanup
- Tests must be independent and clean up after themselves.
- Use `afterEach` hooks or RSpec `around` hooks for database/state cleanup.

---

## CI Integration
Tests are configured to generate JUnit reports (`results.xml`) and HTML reports for CI consumption.

---

## Knowledge Base References
- `risk-governance.md`
- `test-levels-framework.md`
- `test-quality.md`

---

## 📖 The "Plain English" Guide to Our Tests

If you're new here, this section explains exactly what each test file is doing without the technical jargon.

### 1. The "Digital ID Badge" Reader
**File:** `spec/lti/advantage/message_spec.rb`
*   **What it does:** When an LMS (like Canvas) talks to our tool, it sends a "Digital ID Badge" (called a JWT). This test makes sure our tool can read that badge correctly, knows who the student is, and can spot a fake or expired badge.

### 2. The "Handshake" Rulebook
**File:** `spec/lti/advantage/oidc_spec.rb`
*   **What it does:** Before the LMS and our tool start talking, they do a "secret handshake" (OIDC). This test checks the rules of that handshake—making sure we don't start talking unless we have all the required information (like where the student is coming from).

### 3. The "Live Phone Line" Check
**File:** `spec/integration/oidc_initiation_spec.rb`
*   **What it does:** This is an integration test. It's like actually calling the office to see if the phone line is working. It sends a real request to our tool's "Handshake Start" address and checks if the tool responds with the right secret codes.

### 4. The "Robot Browser" Test
**File:** `tests/e2e/sample.spec.ts`
*   **What it does:** This uses a robot to open a real web browser (like Chrome). It goes to our tool's website and checks if the "Lights are on"—making sure the website is actually running and showing the correct messages when someone visits.

### 5. The "Business Contract" Test
**File:** `pact/http/consumer/lti_consumer.spec.ts`
*   **What it does:** This is a "Contract Test." Think of it as a signed agreement between us and the LMS. It records exactly how we expect to talk to each other. If we ever change our code in a way that breaks this agreement, this test will "sound the alarm" before we even ship the code.
