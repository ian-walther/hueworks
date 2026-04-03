# Control Coordination and No-Popcorning

## Goal
Ensure coordination behavior so scene/control execution is predictably synchronized across bridges and failures are explicit.

## Architectural Constraint
This work belongs below the desired-state commit boundary described in `/Users/ianwalther/code/hueworks/planning/architecture-reset.md`.

That means:
- upstream inputs should still only decide desired state
- planner/executor should own cross-bridge coordination, sequencing, partial-failure handling, and batching behavior
- this doc should not be used to justify special-case convergence logic in scene/manual/UI layers

## Scope
- Define and enforce cross-bridge dispatch timing expectations.
- Formalize partial-failure behavior (result shape + UI surfacing path).
- Ensure executor usage is consistent across call sites (`:append` vs `:replace` policy).
- Close Caseta group-control gap so group planning behavior is uniform.

## Out of Scope
- Major planner redesign.
- Circuit-breaker architecture and advanced resilience policy.

## Files to Touch (Likely)
- `lib/hueworks/control/executor.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks/control/group.ex`
- `lib/hueworks/scenes.ex`
- `lib/hueworks_web/live/lights_live.ex`
- `test/hueworks/control_executor_queue_test.exs`
- `test/hueworks_web/live/scene_activation_round_trip_test.exs`

## Acceptance Criteria
- Cross-bridge scene apply behavior has a documented timing contract and tests.
- Executor returns a structured result that distinguishes full success vs partial failure.
- Caseta group control no longer returns `{:error, :not_implemented}`.
- Regression tests cover mixed bridge/action scenarios.

## Open Questions
- Should executor return per-action results synchronously or emit async events only?
- Is best-effort apply acceptable when one bridge is unavailable, or should it fail-fast?
