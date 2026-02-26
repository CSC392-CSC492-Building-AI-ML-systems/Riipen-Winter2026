---
stepsCompleted: ['step-01-detect-mode', 'step-02-load-context', 'step-03-risk-and-testability', 'step-04-coverage-plan', 'step-05-generate-output']
lastStep: 'step-05-generate-output'
lastSaved: '2026-02-26'
---

# Step 5: Generate Outputs & Validate

## Generated Documents
1. **Architecture Doc:** `_bmad-output/test-artifacts/test-design-architecture.md`
2. **QA Doc:** `_bmad-output/test-artifacts/test-design-qa.md`
3. **BMAD Handoff Doc:** `_bmad-output/test-artifacts/test-design/lti-advantage-handoff.md`

## Validation Results
- [x] **Mode:** System-Level
- [x] **Risks Scored & Categorized:** 5 risks identified, highest score = 9 (LMS Integration).
- [x] **Coverage Matrix:** 13 atomic scenarios prioritized P0-P3.
- [x] **Resource Estimates:** Ranges provided (~50–85 hours total).
- [x] **Quality Gates:** Defined (P0=100% pass, P1≥95%).
- [x] **Handoff Document:** Generated and populated with risk-to-story mapping.

## Completion Summary
The `testarch-test-design` workflow for the LTI 1.3 Advantage Core Launch is **complete**. The strategy prioritizes the critical handshake and security-sensitive JWT validation. The output is ready for consumption by BMAD for epic and story decomposition.
