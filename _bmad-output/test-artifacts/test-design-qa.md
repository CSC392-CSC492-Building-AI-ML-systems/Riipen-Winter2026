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

# Test Design for QA: LTI 1.3 Advantage Core Launch

**Purpose:** Test execution recipe for QA team. Defines what to test, how to test it, and what QA needs from other teams.

**Date:** 2026-02-26
**Author:** TEA Master Test Architect
**Status:** Draft
**Project:** lti-advantage

**Related:** See Architecture doc (test-design-architecture.md) for testability concerns and architectural blockers.

---

## Executive Summary

**Scope:** Testing the LTI 1.3 Advantage Core Handshake (OIDC Initiation, LTI Launch, JWKS exposure).

**Risk Summary:**
- Total Risks: 5 (2 high-priority score ≥6)
- Critical Categories: OPS (LMS integration), SEC (JWT validation).

**Coverage Summary:**
- P0 tests: ~5 (critical handshake, security)
- P1 tests: ~4 (API endpoints, key fetching)
- P2 tests: ~3 (Advantage services)
- P3 tests: ~1 (Performance)
- **Total**: ~13 tests (~2-3 weeks with 1 QA)

---

## Not in Scope

| Item | Reasoning | Mitigation |
| --- | --- | --- |
| **LMS UI Validation** | QA cannot test LMS-side UI (e.g., Canvas). | End-to-end handshake with a mock LMS API. |
| **RSA Algorithm Strength** | Assumed handled by standard `openssl` library. | Unit tests for valid/invalid key pairs. |

---

## Dependencies & Test Blockers

**CRITICAL:** QA cannot proceed without these items from other teams.

### Backend/Architecture Dependencies (Pre-Implementation)

1. **LMS JWKS Mocking** - Dev - Pre-Launch
   - Need a way to inject mock LMS public keys into `KeyStore`.
   - Blocks JWT signature verification in integration tests.

2. **Session Persistence Support** - Dev - Pre-Launch
   - Ensure `Rack-Test` or similar tool can handle state/nonce in sessions for handshake tests.

### QA Infrastructure Setup (Pre-Implementation)

1. **Mock LMS App** - QA
   - Sinatra app simulating OIDC initiation and launch jump.
2. **JWT Factory** - QA
   - RSA-signed JWT generator for edge-case testing.

---

## Risk Assessment

### High-Priority Risks (Score ≥6)

| Risk ID | Category | Description | Score | QA Test Coverage |
| --- | --- | --- | --- | --- |
| **R-001** | OPS | LMS Integration Failure | **9** | End-to-end smoke tests using a mock LMS. |
| **R-002** | SEC | Invalid/Expired ID Token | **6** | Exhaustive unit tests for all validation edge cases. |

---

## Entry Criteria

- [ ] Requirements and assumptions agreed upon by QA, Dev, PM.
- [ ] Mock LMS Sinatra app ready for handshake simulation.
- [ ] Test JWT factories ready for edge-case testing.
- [ ] Sinatra demo app deployable to local/test environment.

## Exit Criteria

- [ ] All P0 tests passing (Handshake & Security).
- [ ] All P1 tests passing (API & Integration).
- [ ] No open high-priority / high-severity bugs.
- [ ] Code coverage ≥ 80% on core library logic.

---

## Test Coverage Plan

**Note:** P0/P1/P2/P3 = priority, NOT execution timing.

### P0 (Critical)

| Test ID | Requirement | Test Level | Risk Link | Notes |
| --- | --- | --- | --- | --- |
| **P0-001** | E2E Handshake | Smoke/E2E | R-001 | Complete handshake with mock LMS. |
| **P0-002** | JWT Signature | Unit | R-002 | Verify RS256 signature; reject invalid tokens. |
| **P0-003** | Claim Validation | Unit | R-002 | Validate `iss`, `aud`, `exp`, `iat`, `sub`. |
| **P0-004** | OIDC Params | Unit | R-001 | Ensure required OIDC initiation params exist. |
| **P0-005** | State Mismatch | Integration | R-003 | Fail launch if `state` does not match session. |

---

### P1 (High)

| Test ID | Requirement | Test Level | Risk Link | Notes |
| --- | --- | --- | --- | --- |
| **P1-001** | JWKS Endpoint | API | - | Verify `/lti/jwks` returns valid public keys. |
| **P1-002** | User ID Extraction | Unit | - | Extract `sub` from id_token. |
| **P1-003** | Key Fetching | Integration | R-004 | Fetch and cache keys from LMS JWKS. |

---

## Execution Strategy

**Organized by TOOL TYPE:**

### Every PR: RSpec Unit & Integration (~5 min)
- All Unit tests (P0, P1).
- All Integration tests for core logic.
- Why run in PRs: Fast feedback on library correctness.

### Nightly / Pre-Release: Sinatra Smoke Tests (~15 min)
- Full Handshake E2E suite with Mock LMS using `Rack-Test`.
- Service-level integration tests (AGS/NRPS).
- Why run in Nightly: Higher setup overhead for full handshake.

---

## QA Effort Estimate

| Priority | Count | Effort Range | Notes |
| --- | --- | --- | --- |
| P0 | ~5 | ~20–30 hours | Complex setup (Mock LMS, Handshake). |
| P1 | ~4 | ~15–25 hours | API and key store integration. |
| P2/P3 | ~4 | ~15–30 hours | Advantage services and performance. |
| **Total** | **~13** | **~50–85 hours** | **1 QA engineer, full-time.** |

---

## Appendix A: Code Examples & Tagging (RSpec)

```ruby
# P0 Handshake Smoke Test
RSpec.describe "LTI 1.3 Handshake", type: :request do
  it "successfully completes OIDC flow" do
    # 1. Login Initiation
    post "/oidc/init", { iss: "...", login_hint: "...", target_link_uri: "..." }
    expect(last_response).to be_ok # Form redirect

    # 2. LTI Launch (Mocked return from LMS)
    post "/lti/launch", { id_token: "VALID_JWT", state: "MATCHING_STATE" }
    expect(last_response).to be_redirect
  end
end
```

**End of QA Document**
