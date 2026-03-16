# Coverage Expansion

## Goal
Increase confidence in runtime behavior that is currently weakly tested, especially subscriptions and bridge edge cases.

## Scope
- Subscription/event-stream tests:
  Caseta LEAP parsing/reconnect behavior and subscription supervisor failure paths.
- Control integration tests for failure paths:
  per-bridge dispatch errors, partial scene apply outcomes, retry/backoff behavior under mixed workloads.
- Scene/circadian interaction tests:
  active-scene reapply and brightness-override edge cases.

## Out of Scope
- Full hardware integration tests.
- Load/perf benchmarking suite.

## Files to Touch (Likely)
- `test/hueworks/control_*`
- `test/hueworks/scenes_*`
- `test/hueworks/subscription/*` (new)
- `test/hueworks_web/live/scene_activation_round_trip_test.exs`
- `lib/hueworks/subscription/*` (only for testability seams)

## Acceptance Criteria
- Subscription modules have dedicated unit/integration tests for parse/map/reconnect paths across all currently supported bridges.
- Control executor/planner tests include partial-failure assertions.
- Scene/circadian behavior has regression coverage for override semantics.
- Coverage threshold policy is documented (local-only vs CI-enforced).

## Open Questions
- Enforce coverage minimum in CI now, or after the remaining Caseta/reconnect tests land?
- Add StreamData now for parser fuzzing, or defer to a later quality pass?
