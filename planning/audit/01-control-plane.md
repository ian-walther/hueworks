# Audit Chunk 1: Control Plane

Scope: `lib/hueworks/control/**`, `lib/hueworks_app/control/**`, `lib/hueworks_app/cache*`, `lib/hueworks/active_scenes.ex`, plus `lib/hueworks/application.ex` supervision wiring.
Status: audit complete (all files in scope read). Finding IDs are stable; gaps in numbering mean the finding was implemented and removed.

Overall assessment: the pipeline mandated by `planned_architecture.md` (intent → DesiredState → planner → executor → dispatch) is genuinely present and mostly respected. The planner/executor split is clean, tracing is consistent, and device quirks live in payload/Kelvin modules as intended. The main remaining problem is a mixed atom/string-key tolerance that has metastasized through the whole plane (CP-3).

---

### CP-3: Mixed atom/string key tolerance has spread through the entire control plane
- Severity: high
- Type: refactor
- Where: dual lookups `Map.get(m, :k) || Map.get(m, "k")` and dual clauses in [planner.ex](../../lib/hueworks/control/planner.ex) (`{:light, id}` and `{"light", id}` diff keys), [planner/context.ex](../../lib/hueworks/control/planner/context.ex), the payload modules' `power` dual reads, [apply.ex](../../lib/hueworks/control/apply.ex) (`map_value`), [group_state.ex](../../lib/hueworks/control/group_state.ex) (`fetch_value`), and the alias tables in [light_state_semantics.ex](../../lib/hueworks/control/light_state_semantics.ex).
- What: internal desired/physical state maps and diff keys tolerate both key shapes at every layer, so every consumer re-implements boundary normalization.
- Why: direct violation of "Normalize At Boundaries — do not spread mixed atom/string key handling through downstream domain code."
- Decision: make atom-keyed state maps with `{:light | :group, integer_id}` diff keys the **internal invariant** of the control plane, enforced at the two write funnels: `DesiredState.apply/put` and `State.put/ensure`. Add `LightStateSemantics.normalize_keys/1` (string keys → known atoms via the existing `key_aliases` vocabulary, `temperature` → `kelvin`, string power → atom) and call it inside the existing `LightStateSemantics.merge_state/2` seam. Then, in a follow-up pass per module, delete downstream dual-key handling: planner string-tuple clauses, `Transition`/`GroupState` dual reads, `Apply.map_value` (trace maps: pick atom keys, fix callers). StateParser keeps accepting loose external payloads — it already emits atom keys; that is the correct boundary. `Circadian.Config` is the reference pattern for boundary modules (see chunk 3 doc).
- Guardrails: do one downstream module per commit with the full suite green. Where a test feeds string-keyed state directly into a downstream module (bypassing the funnel), relocate the assertion to the funnel per the Testing Rule in refactoring.md rather than preserving the internal tolerance.
- Effort: L (mechanical but wide)

### CP-11: DesiredState.commit is a read-modify-write loop of GenServer calls
- Severity: low
- Type: refactor (accepted risk — document, don't fix yet)
- Where: [lib/hueworks_app/control/desired_state.ex:83-127](../../lib/hueworks_app/control/desired_state.ex)
- What: `commit/1` iterates entities doing one `GenServer.call` per entity, computing diffs outside the server; concurrent transactions can interleave per-entity. Similarly, `Executor.dispatch_action` does a `Repo.get` per action ([executor.ex:344,356](../../lib/hueworks_app/control/executor.ex)).
- Why noted: at single-home scale neither is a real problem, and last-writer-wins per entity matches the product's manual-vs-scene semantics today. Recording so a future contributor doesn't discover it mid-incident.
- Decision: no change now. If a real interleaving bug is ever traced here, move commit into a single `handle_call` that applies the whole transaction atomically — do not add locks upstream.
- Effort: — 

---

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- The control plane is well covered overall: state, desired state, planner, apply, payloads, bootstraps, convergence, and executor retry/backoff all have focused suites. Explicitly leave alone. (The cross-bridge queue-replacement scenario is covered in `lights_manual_control_test.exs`; retry/backoff in `control_executor_test.exs`.)

## Parked (noted early, belongs to later chunks)

- Chunk 3: `ActiveScenes.set_active/clear_for_room` call `HomeAssistantExport.refresh_room_select` inline — domain module reaching into an integration; absorbed into SC-2's domain-event design (chunk 3 doc).
- Chunk 5: point `HomeAssistant.Export.Commands` optimistic state at the shared `LightStateSemantics.merge_state/2` helper.
- Chunk 5: `Bootstrap.HomeAssistant.run` assumes a single HA bridge (`Repo.one`) while the rest of the app supports N bridges per type.
- Chunk 4: import still writes `metadata["bridge_host"]` on Hue lights/groups (materialize.ex, reimport_apply.ex, normalize/hue.ex) but nothing reads it anymore — decide whether to keep it as an inspectable bridge-owned fact or stop writing it.

## Suggested Implementation Order (for cheap-model sessions)

1. CP-3 (the remaining item; wide but mechanical, one module per commit)
2. CP-11 stays a documented no-op until evidence triggers it
