# Test Coverage Audit

## Goal
Reassess whether HueWorks still has strong test coverage after recent feature work and production-driven fixes.

The test suite was previously brought to a good state, but it has not had a deliberate coverage review in a while. The audit should determine whether coverage is still strong before assuming a large test-expansion project is needed.

## Desired Outcome
The result of the audit should be a short, current list of meaningful gaps.

Useful findings include:
- important behavior that is not covered by tests
- regression-prone production fixes that lack focused regression tests
- feature paths that are only covered indirectly
- integration boundaries where mocks or fixtures no longer match real usage
- brittle tests that make refactoring harder without protecting real behavior

## Non-Goals
- Do not recreate a broad test backlog before auditing.
- Do not chase coverage percentage for its own sake.
- Do not add low-value tests just because a module is uncovered.
- Do not preserve outdated internal-boundary tests if behavior is better asserted elsewhere.

## Audit Areas
- Scene application and active-scene recomputation.
- Desired state, physical state, planner, and executor boundaries.
- Home Assistant and HomeKit export/control paths.
- Bridge import, reimport, and materialization behavior.
- Presence-input and power-policy behavior.
- Scene builder and control-page LiveView flows that protect high-value user workflows.

## Acceptance Criteria
- Current high-risk gaps are identified and prioritized.
- Any recommended new tests are tied to user-visible behavior, production regressions, or important architectural boundaries.
- Areas that are still well covered are explicitly left alone.
