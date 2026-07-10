# Audit Chunk 1: Control Plane

Scope: `lib/hueworks/control/**`, `lib/hueworks_app/control/**`, `lib/hueworks_app/cache*`, `lib/hueworks/active_scenes.ex`, plus `lib/hueworks/application.ex` supervision wiring.
Status: audit complete; **no open findings** (IDs CP-1 through CP-12 were all implemented and removed per the forward-facing rule, except CP-11 below, which is a documented accepted risk, not a work item).

Overall assessment: the pipeline mandated by `planned_architecture.md` (intent → DesiredState → planner → executor → dispatch) is present and respected. State-map semantics are centralized in `LightStateSemantics` (including the `normalize_keys/1` atom-key write funnel — internal control-state maps and diff keys are atom-keyed by invariant; only `StateParser` accepts loose external payloads, which is the correct boundary).

## Accepted Risk (documented, no action)

### CP-11: DesiredState.commit is a read-modify-write loop of GenServer calls
- Where: [lib/hueworks_app/control/desired_state.ex](../../lib/hueworks_app/control/desired_state.ex) (`commit/1` iterates entities with one call each; concurrent transactions can interleave per-entity), and `Executor.dispatch_action` does a `Repo.get` per action.
- Why documented: at single-home scale neither is a real problem, and last-writer-wins per entity matches the product's manual-vs-scene semantics today. Recording so a future contributor doesn't discover it mid-incident.
- If a real interleaving bug is ever traced here: move commit into a single `handle_call` that applies the whole transaction atomically — do not add locks upstream.

## Parked

Formerly-parked items are consolidated as CC-2 and CC-4 in `07-cross-cutting.md`.
