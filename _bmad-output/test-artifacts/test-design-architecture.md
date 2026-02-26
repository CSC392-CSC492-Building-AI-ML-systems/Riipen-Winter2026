---
stepsCompleted: ['step-01-detect-mode', 'step-02-load-context', 'step-03-risk-and-testability', 'step-04-coverage-plan', 'step-05-generate-output']
lastStep: 'step-05-generate-output'
lastSaved: '2026-02-26'
workflowType: 'testarch-test-design'
inputDocuments:
  - 'docs/overview.md'
  - 'docs/api-contracts.md'
  - 'docs/core-launch-flow.md'
  - 'docs/data-models.md'
---

# Test Design for Architecture: LTI 1.3 Advantage Core Launch

**Purpose:** Architectural concerns, testability gaps, and NFR requirements for review by Architecture/Dev teams. Serves as a contract between QA and Engineering on what must be addressed before test development begins.

**Date:** 2026-02-26
**Author:** TEA Master Test Architect
**Status:** Architecture Review Pending
**Project:** lti-advantage
**PRD Reference:** docs/overview.md
**ADR Reference:** docs/core-launch-flow.md

---

## Executive Summary

**Scope:** Implementation of the LTI 1.3 Advantage handshake, including OIDC Login Initiation, LTI Launch (JWT validation), and JWKS endpoint for public key exposure.

**Business Context (from PRD):**
- **Revenue/Impact:** Core foundational library for LTI 1.3 interoperability; failure blocks all LMS integrations.
- **Problem:** Transitioning from OAuth 1.0a to modern OIDC/JWT security model.
- **GA Launch:** Pre-launch implementation complete; testing required.

**Architecture (from ADR):**
- **Key Decision 1:** LTI 1.3 Advantage security model based on OIDC and JWT (RS256).
- **Key Decision 2:** Sinatra-based demo app for full-stack handshake validation.
- **Key Decision 3:** Ruby library for core message handling and OIDC logic.

**Risk Summary:**
- **Total risks**: 5
- **High-priority (≥6)**: 2 risks requiring immediate mitigation
- **Test effort**: ~50–85 hours (~2–3 weeks for 1 QA)

---

## Quick Guide

### 🚨 BLOCKERS - Team Must Decide (Can't Proceed Without)

**Pre-Implementation Critical Path** - These MUST be completed before QA can write integration tests:

1. **R-001: LMS JWKS Mocking** - Provide a mechanism to inject mock LMS public keys into `KeyStore` for JWT signature verification in tests (Dev/Architect).
2. **R-002: Session Persistence for OIDC** - Ensure the test environment can maintain `state` and `nonce` between `/oidc/init` and `/lti/launch` (Dev/QA).

### ⚠️ HIGH PRIORITY - Team Should Validate (We Provide Recommendation, You Approve)

1. **R-003: JWT Validation Edge Cases** - Approval needed on the list of JWT failure scenarios to test (exp, iat, aud, iss, alg:none) (Dev/Security).
2. **R-004: JWKS Endpoint Formatting** - Validate that the tool's JWKS output strictly follows the RFC 7517 specification for compatibility (Architect).

### 📋 INFO ONLY - Solutions Provided (Review, No Decisions Needed)

1. **Test strategy**: Multi-level (Unit for logic, Integration for endpoints, Smoke for handshake).
2. **Tooling**: RSpec (Unit/Integration), Rack-Test (Sinatra/API).
3. **Coverage**: 13 scenarios prioritized P0-P3.
4. **Quality gates**: P0 pass rate = 100%, P1 pass rate ≥ 95%.

---

## For Architects and Devs - Open Topics 👷

### Risk Assessment

**Total risks identified**: 5 (2 high-priority score ≥6, 3 medium)

#### High-Priority Risks (Score ≥6) - IMMEDIATE ATTENTION

| Risk ID | Category | Description | Probability | Impact | Score | Mitigation | Owner | Timeline |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **R-001** | **OPS** | **LMS Integration Failure (Handshake)** | 3 | 3 | **9** | **End-to-end smoke tests using a mock LMS; detailed failure logging.** | **QA** | **Pre-Launch** |
| **R-002** | **SEC** | **Invalid/Expired ID Token Handling** | 2 | 3 | **6** | **Unit and integration tests for all validation edge cases (exp, aud, iss).** | **Dev** | **Pre-Launch** |

#### Medium-Priority Risks (Score 3-5)

| Risk ID | Category | Description | Probability | Impact | Score | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-003 | SEC | CSRF / State Mismatch | 2 | 2 | 4 | Integration tests for OIDC flow with session persistence. | Dev/QA |
| R-004 | OPS | LMS JWKS Inaccessibility | 2 | 2 | 4 | Timeout/retry logic in `KeyStore`; monitoring. | Dev |
| R-005 | BUS | Incompatible LTI Claims | 2 | 2 | 4 | Contract testing or comprehensive LMS mocks. | Dev/QA |

---

### Testability Concerns and Architectural Gaps

**🚨 ACTIONABLE CONCERNS - Architecture Team Must Address**

#### 1. Blockers to Fast Feedback (WHAT WE NEED FROM ARCHITECTURE)

| Concern | Impact | What Architecture Must Provide | Owner | Timeline |
| --- | --- | --- | --- | --- |
| **No LMS JWKS Mock** | Cannot test JWT verification | Dependency injection point for `KeyStore` | Dev | Pre-implementation |
| **Session Isolation** | Flaky OIDC tests | Clear session handling for state/nonce in tests | Dev | Pre-implementation |

---

### Testability Assessment Summary

#### What Works Well
- ✅ Core logic (Message, LoginInitiation) is decoupled from HTTP, allowing pure unit tests.
- ✅ Clean separation of concerns in the library design.

---

### Risk Mitigation Plans (High-Priority Risks ≥6)

#### R-001: LMS Integration Failure (Handshake) (Score: 9) - CRITICAL

**Mitigation Strategy:**
1. Implement a `MockLms` Sinatra app that follows the OIDC flow.
2. Create end-to-end RSpec tests using `Rack-Test` to simulate the OIDC "jump" and LTI launch.
3. Validate session persistence of state and nonce.

**Owner:** QA
**Timeline:** Pre-Launch
**Status:** Planned
**Verification:** Successful completion of the full handshake in CI.

#### R-002: Invalid/Expired ID Token Handling (Score: 6) - HIGH

**Mitigation Strategy:**
1. Generate test JWTs with various invalid states (expired, future iat, wrong aud).
2. Verify `Lti::Advantage::Message#verify!` raises appropriate errors for each.
3. Ensure the tool returns appropriate error responses (e.g., 401 Unauthorized).

**Owner:** Dev
**Timeline:** Pre-Launch
**Status:** Planned
**Verification:** 100% pass rate on JWT edge-case unit tests.

---

### Assumptions and Dependencies

#### Assumptions
1. The `jwt` gem handles base signature verification correctly (RS256).
2. LMS providers strictly follow the LTI 1.3 and OIDC specifications.

#### Dependencies
1. Mock LMS environment required for smoke testing.

**End of Architecture Document**
