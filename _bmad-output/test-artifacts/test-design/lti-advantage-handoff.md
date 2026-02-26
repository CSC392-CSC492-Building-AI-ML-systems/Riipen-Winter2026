---
title: 'TEA Test Design → BMAD Handoff Document'
version: '1.0'
workflowType: 'testarch-test-design-handoff'
inputDocuments:
  - '_bmad-output/test-artifacts/test-design-architecture.md'
  - '_bmad-output/test-artifacts/test-design-qa.md'
sourceWorkflow: 'testarch-test-design'
generatedBy: 'TEA Master Test Architect'
generatedAt: '2026-02-26'
projectName: 'lti-advantage'
---

# TEA → BMAD Integration Handoff

## Purpose

This document bridges TEA's test design outputs with BMAD's epic/story decomposition workflow. It provides structured integration guidance so that quality requirements, risk assessments, and test strategies flow into implementation planning.

## TEA Artifacts Inventory

| Artifact | Path | BMAD Integration Point |
| --- | --- | --- |
| Test Design Document | `_bmad-output/test-artifacts/test-design-qa.md` | Epic quality requirements, story acceptance criteria |
| Risk Assessment | `_bmad-output/test-artifacts/test-design-architecture.md` | Epic risk classification, story priority |
| Coverage Strategy | (embedded in test-design-qa.md) | Story test requirements |

## Epic-Level Integration Guidance

### Risk References
- **R-001: LMS Integration Failure (Score: 9)** - Must appear as a critical quality gate for the "Core Launch Handshake" Epic.
- **R-002: Invalid/Expired ID Token Handling (Score: 6)** - Security risk that must be addressed in the "JWT Authentication" Epic.

### Quality Gates
- **Handshake Pass Gate:** Successful completion of the end-to-end OIDC handshake with a mock LMS.
- **Security Pass Gate:** 100% pass rate on all JWT validation edge-case tests (RS256 signature, expiry, audience).

## Story-Level Integration Guidance

### P0/P1 Test Scenarios → Story Acceptance Criteria
- **Login Initiation Story:** AC: "Tool validates required `iss`, `login_hint`, and `target_link_uri` parameters."
- **LTI Launch Story:** AC: "Tool verifies `state` and `nonce` against session; Tool verifies JWT signature using LMS public keys."

### Data-TestId Requirements
- N/A (Backend library focus) - Ensure clear logging of handshake errors for testability.

## Risk-to-Story Mapping

| Risk ID | Category | P×I | Recommended Story/Epic | Test Level |
| --- | --- | --- | --- | --- |
| R-001 | OPS | 9 | Core Handshake Smoke Test | Smoke/E2E |
| R-002 | SEC | 6 | JWT Verification Logic | Unit |
| R-003 | SEC | 4 | OIDC CSRF Protection | Integration |
| R-004 | OPS | 4 | KeyStore Key Fetching | Integration |
| R-005 | BUS | 4 | LTI Claim Processing | Unit/API |

## Recommended BMAD → TEA Workflow Sequence

1. **TEA Test Design** (`TD`) → produces this handoff document.
2. **BMAD Create Epics & Stories** → consumes this handoff, embeds quality requirements.
3. **TEA ATDD** (`AT`) → generates acceptance tests per story.
4. **BMAD Implementation** → developers implement with test-first guidance.
5. **TEA Automate** (`TA`) → generates full test suite.
6. **TEA Trace** (`TR`) → validates coverage completeness.

## Phase Transition Quality Gates

- **Test Design → Epic/Story Creation:** All P0 risks (R-001, R-002) have mitigation strategies.
- **Epic/Story Creation → ATDD:** Stories have acceptance criteria (AC) from the test design.
- **ATDD → Implementation:** Failing acceptance tests exist for all P0/P1 scenarios.
