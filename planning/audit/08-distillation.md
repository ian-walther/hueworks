# Audit Chunk 8: Architectural Distillation

Scope: synthesis of chunks 1–7, accepted risks, remaining findings, and reconciliation with `planned_architecture.md`, `hueworks_todo.md`, `planning/import-resync.md`, and `planning/test-coverage-audit.md`.
Status: audit complete. This chunk adds no implementation findings; actionable work remains in the source chunk documents.

## Executive Verdict

HueWorks' architecture is sound. The core pipeline described by `planned_architecture.md` is not aspirational: inputs commit intent to desired state, the planner owns topology/capability optimization, the executor owns dispatch and convergence, and bridge streams write observation back to physical state. The audit found no integration or web control path that bypasses that model.

The work uncovered by the audit was mostly consolidation around already-correct boundaries, safety around destructive operations, and a limited set of real correctness bugs. It does not justify a broad rewrite or a second state/control abstraction.

## Architectural Conclusions

### The state ownership model held

- Desired state remains intent; physical state remains observation. The earlier UI path that fabricated observations for slider defaults was removed rather than normalized into the design.
- Manual control, scenes, Pico, Home Assistant, HomeKit, and web controls share the same semantic paths. Scene-active power retention and brightness/temperature locks are centralized rather than reinterpreted per caller.
- Groups remain planner optimization projections over member lights. Group display state and scene-builder membership reconstruct from light truth instead of creating another state plane.

### Boundary normalization is the successful refactor pattern

`Circadian.Config`, `BridgeSeeds`, `Import.Source`, `LightStateSemantics`, and the settings boundary modules demonstrate the right shape: accept loose external input once, validate/normalize it, then pass a bounded internal representation downstream. The audit repeatedly removed mixed-key and vocabulary handling from interior modules while deliberately preserving it in JSON/import parsers where it belongs.

The remaining CC-9 and CC-11 findings are local ordering/parser bypasses, not evidence that the boundary approach failed.

### Integration inversion is worth preserving

`Hueworks.DomainEvents` removed scene/presence persistence's need to know every optional integration consumer. The successful pattern is commit first, then broadcast; HA and HomeKit subscribers refresh independently. The few synchronous effects that remain have explicit ordering needs, notably presence refresh and import/bridge removal cleanup.

### File placement now reflects runtime ownership

Supervised state, executors, caches, pollers, and event-stream processes live under `lib/hueworks_app`; domain/application APIs and pure transformations live under `lib/hueworks`. The module namespace remains mostly `Hueworks.*`, which avoids an artificial public rename. This split and the domain-event/context-invariant lessons are now codified in `planned_architecture.md`.

### Thin coordinators beat generic framework layers

`LightsLive`, the split scene-builder state modules, Pico configuration coordinators, boundary config modules, and shared transport helpers all improved by extracting cohesive responsibilities behind the existing public surface. None needed a new generic service layer. Future refactors should keep following concrete duplication and invariant ownership rather than line-count thresholds alone.

## Remaining Audit-Directed Work

Implement in risk order, while retaining each finding's own test-first guardrails:

1. Protect data and topology: CC-10 (database backup/restore), CC-7 (canonical-light invariants), CC-8 (atomic group room cascade/export fan-out), and CC-9 (merged HA toggle derivation).
2. Restore deterministic runtime/test feedback: CC-12 (tzdata), CC-1 (SQLite busy timeout), and CC-2 (warnings-zero enforcement).
3. Finish web safety and state hygiene: WB-21 (real dirty-state protection), WB-23 (light-state delete confirmation), and WB-22 (broken/dead web scaffolding).
4. Complete bounded maintenance cleanup: CC-3 (ignored local artifacts), CC-4 (dead bridge-host metadata), CC-5 (two focused stream tests), and CC-11 (offline import task parsing/docs).

These are the complete open audit findings: WB-21..WB-23 and CC-1..CC-5 plus CC-7..CC-12. Gaps in the ID sequences are reconciled work or deliberate leave-alone decisions, not missing records.

## Accepted Risks And Product Work

- CP-11 remains an accepted single-home-scale risk: desired-state commits are per-entity GenServer calls. Change it only after evidence of a real interleaving failure.
- SC-5 remains performance-deferred: cache circadian solar windows only if profiling or a shorter poll interval makes the repeated calculation material.
- Transition smoothness and HomeKit brightness/color quality remain product-experience work, not refactoring debt.
- Caseta group dispatch remains a concrete runtime feature gap and should stay in `hueworks_todo.md` with its regression test.

## Planning Reconciliation

- The destructive reimport dependency/confirmation work is complete and was removed from forward-looking plans. The residual reimport work is narrower: explicit new-entity choices, current-versus-bridge presentation, inspectable auto-refresh details, missing summary/warning visibility, and dynamic HA-group duplicate recomputation.
- The deliberate test-coverage review is complete. `planning/test-coverage-audit.md` now contains only the small current gap list, and the generic audit task was removed from `hueworks_todo.md`.
- `planned_architecture.md` gained the three rules the implementation repeatedly validated: contexts own invariants, optional integration fan-out happens after commit, and supervised runtime placement stays separate from domain logic.

## Final Audit Posture

Do not reopen audited areas simply because some modules remain large or protocol code looks unusual. The chunk documents name the intentional quirks and reference patterns. New work should begin from production evidence, a failing regression, a product decision, or one of the open findings above.
