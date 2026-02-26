# Project Documentation - LTI Advantage (Ruby)

Welcome to the documentation for the `lti-advantage` library and the Sinatra demo application. This documentation is optimized for AI agents and developers working on the project.

---

## Project Overview

- **Type:** Ruby Library (Primary) with Sinatra Backend (Demo)
- **Primary Language:** Ruby 3.4.0
- **Architecture:** LTI 1.3 Advantage Handshake (OIDC-based)

### Quick Reference

#### LTI Advantage Library (core)
- **Tech Stack:** Ruby, JWT, Faraday
- **Root:** `lib/`
- **Purpose:** Core logic for LTI 1.3 Advantage messages and OIDC initiation.

#### Sinatra Demo App (demo)
- **Tech Stack:** Sinatra, Puma, Rack
- **Root:** `demo/`
- **Purpose:** Functional prototype for local LTI 1.3 testing with an LMS (e.g., Canvas).

---

## Core Handshake Documentation

- **[Core Launch Flow](./core-launch-flow.md)** - Detailed analysis of the LTI 1.3 handshake (OIDC initiation & launch).
- **[API Contracts](./api-contracts.md)** - Endpoints and request/response schemas for the launch flow.
- **[Data Models](./data-models.md)** - Structure of LTI Messages (JWT) and JWKS.

---

## Existing Documentation

- **[README.md](../README.md)** - Project installation and basic usage.
- **[Overview](./overview.md)** - High-level project overview.
- **[Test Setup](./test_setup.md)** - Instructions for setting up and running RSpec tests.

---

## Getting Started (Local Development)

1. **Install Dependencies:** `bundle install`
2. **Run Tests:** `bundle exec rspec`
3. **Run Demo App:** `ruby demo/app.rb`
4. **Local LTI Testing:** Update `TOOL_HOST` and `LMS_BROWSER_URL` in `demo/app.rb` with your local IP and LMS URL.

---

Last Updated: 2026-02-26
Status: Complete
Docs Generated: 4 (api-contracts, data-models, core-launch-flow, index)
