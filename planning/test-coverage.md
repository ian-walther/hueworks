# Coverage Expansion

## Goal
Increase confidence in runtime behavior that is currently weakly tested, especially subscriptions and bridge edge cases.

## Architectural Constraint
Coverage expansion should reinforce the boundaries in `/Users/ianwalther/code/hueworks/planning/architecture-reset.md`.

That means:
- prefer tests that exercise desired-state writes and downstream planner/executor behavior together
- add tests when a failure reveals a real control-boundary regression
- if a test breaks during an expected refactor, reconsider whether it belongs at a different level instead of preserving an outdated seam

## Scope
- Subscription and event-stream tests as new bridge runtimes or failure modes are added.
- Control integration tests for failure paths: per-bridge dispatch errors, partial scene apply outcomes, retry/backoff behavior under mixed workloads.
- Scene and circadian interaction tests: active-scene lifecycle, manual-control interactions, and lower-level control-boundary edge cases.

## Out of Scope
- Full hardware integration tests.
- Load/perf benchmarking suite.

## Acceptance Criteria
- Control executor and planner tests include partial-failure assertions.
- Scene, circadian, and manual behavior has regression coverage at the boundaries where desired-state writes meet downstream control behavior.
- Coverage threshold policy is documented (local-only vs CI-enforced).

## Open Questions
- Enforce coverage minimum in CI now, or after broader failure-path coverage lands?
- Add StreamData now for parser fuzzing, or defer to a later quality pass?
