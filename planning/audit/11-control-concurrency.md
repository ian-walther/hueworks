# Audit Chunk 11: Control Concurrency

Scope: deterministic concurrent or interleaved execution of circadian ticks, manual control, and scene activation against shared entities, including desired-state convergence and executor dispatch behavior.
Status: complete. Deterministic phase staging proved a harmful plan/enqueue interleaving. Desired-state commits are now atomic, planner snapshots carry per-light revisions, and the executor replans stale light/group work before dispatch. No `CR-*` findings remain open.

## Sub-Area Tracker

| Area | Status |
|------|--------|
| Map commit, revision, enqueue, and dispatch synchronization points | complete |
| Build a deterministic phase-staged harness | complete |
| Exercise manual/circadian/scene interleavings | complete |
| Assert convergence and bounded dispatch | complete |
| Reconcile CP-11 and architecture posture | complete |

## Required Evidence

- Tests must control ordering with staged commit/plan/enqueue boundaries, barriers, messages, or explicit blocking fakes; repeated `Task.async` plus timing is insufficient.
- The final desired state must correspond to the last committed intent under the tested order.
- Stale planned work must not overwrite newer desired state, and equivalent work must not be dispatched twice solely because inputs raced.
- Any finding must name the exact interleaving and reproduce red before its fix.

## Current Invariant

`test/hueworks/control_concurrency_test.exs` stages circadian, manual, and scene intents at explicit commit/plan/enqueue boundaries. It proves that delayed older plans cannot dispatch over the latest desired state. Its grouped case proves stale group recovery sends the current changed light once and preserves the still-needed sibling once, rather than either double-dispatching or losing covered work.

`DesiredState.commit/1` applies the whole transaction in one GenServer call. `AreaSnapshot` obtains desired values and their revisions in one serialized snapshot. Planner actions retain the covered light IDs and snapshot revisions. At dispatch, a revision mismatch triggers a current-state replan through the normal planner instead of bridge dispatch. A stale-plan replan does not consume a transport retry, and a successfully dispatched current revision is not duplicated by later stale group recovery; its scheduled convergence check remains responsible for physical retry.

This evidence closes the former CP-11 accepted risk. Revision lineage remains dispatch metadata, not another desired-state plane.
