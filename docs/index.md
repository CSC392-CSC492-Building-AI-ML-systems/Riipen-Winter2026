# Project Documentation - LTI Advantage (Ruby)

Welcome to the documentation for the `lti-advantage` library and the Sinatra demo application. This documentation is optimized for AI agents and developers working on the project.

---

## Project Overview

- **Type:** Ruby Library (Primary) with Sinatra Backend (Demo)
- **Primary Language:** Ruby 3.4.0
- **Architecture:** LTI 1.3 core launch implementation with a `Client`-based API

### Quick Reference

#### LTI Advantage Library (core)
- **Tech Stack:** Ruby, JWT, Net::HTTP
- **Root:** `lib/`
- **Purpose:** Core login initiation parsing, authentication request generation, launch validation, and replay protection.

#### Sinatra Demo App (demo)
- **Tech Stack:** Sinatra, Puma, Rack
- **Root:** `demo/`
- **Purpose:** Example tool app using `Lti::Advantage::Client` for core launch flow and `Lti::Advantage::KeyPair` for `/lti/jwks`.

---

## Core Handshake Documentation

- **[Core Launch Flow](./core-launch-flow.md)** - Detailed analysis of the `Client`-based LTI 1.3 handshake.
- **[API Contracts](./api-contracts.md)** - Endpoints and request/response schemas for the launch flow.
- **[Data Models](./data-models.md)** - Core registration, launch, JWT, and JWKS data structures.

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
4. **Local LTI Testing:** Configure `CLIENT_ID`, `LMS_ISSUER`, `LMS_AUTH_URL`, `LMS_JWKS_URL`, `LTI_DEPLOYMENT_ID`, and `TOOL_HOST` in your environment.

---

Last Updated: 2026-03-08
Status: Current
