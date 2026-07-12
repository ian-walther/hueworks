# Audit Chunk 8: Architectural Distillation

Scope: synthesis of chunks 1–7, accepted risks, remaining findings, and reconciliation with `planned_architecture.md`, `hueworks_todo.md`, and `planning/import-resync.md`.
Status: complete. Chunks 1–12 and all audit-directed implementation are reconciled; no audit findings remain open.

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

The CC-9 and CC-11 corrections were local ordering/parser bypasses, not evidence that the boundary approach failed.

### Integration inversion is worth preserving

`Hueworks.DomainEvents` removed scene/presence persistence's need to know every optional integration consumer. The successful pattern is commit first, then broadcast; HA and HomeKit subscribers refresh independently. The few synchronous effects that remain have explicit ordering needs, notably presence refresh and import/bridge removal cleanup.

### File placement now reflects runtime ownership

Supervised state, executors, caches, pollers, and event-stream processes live under `lib/hueworks_app`; domain/application APIs and pure transformations live under `lib/hueworks`. The module namespace remains mostly `Hueworks.*`, which avoids an artificial public rename. This split and the domain-event/context-invariant lessons are now codified in `planned_architecture.md`.

### Thin coordinators beat generic framework layers

`LightsLive`, the split scene-builder state modules, Pico configuration coordinators, boundary config modules, and shared transport helpers all improved by extracting cohesive responsibilities behind the existing public surface. None needed a new generic service layer. Future refactors should keep following concrete duplication and invariant ownership rather than line-count thresholds alone.

## Original Audit-Directed Work Complete

No findings from chunks 1–8 remain open. All WB and CC findings are implemented and reconciled; gaps in the ID sequences are intentional leave-alone or completed items. The approved ignored-artifact cleanup stayed within its deletion boundary, and the required test command now bootstraps a clean test database. Chunks 9–12 are a bounded extension, not a reopening of those audited areas without evidence.

## Drill-In Conclusions

- The web endpoint's protections are internally coherent for its declared product: a never-public trusted-LAN appliance with no application authentication and direct HTTP permitted only within that isolated boundary. CSRF and origin checks remain defense in depth, and public exposure is explicitly unsupported.
- Extended-Kelvin commands now have dynamic HA/Z2M encode-report-parse parity across both sides of the device-profile crossover, including reported-floor ambiguity.
- Deterministic commit/plan/enqueue interleavings proved and closed the former control concurrency risk. Desired-state revisions prevent older light and group plans from dispatching over newer intent without creating a second state plane.
- Migration constraints, browser hooks, and release plumbing received dynamic coverage. The sweep closed two missing unique-constraint mappings, duplicate paired-color events, inaccurate endpoint URL metadata, and one-time bootstrap loss when secrets arrive after first start.

## Accepted Risks And Product Work

- SC-5 remains performance-deferred: cache circadian solar windows only if profiling or a shorter poll interval makes the repeated calculation material.
- Transition smoothness and HomeKit brightness/color quality remain product-experience work, not refactoring debt.

## Planning Reconciliation

- The destructive reimport dependency/confirmation work is complete and was removed from forward-looking plans. The residual reimport work is narrower: explicit new-entity choices, current-versus-bridge presentation, inspectable auto-refresh details, missing summary/warning visibility, and dynamic HA-group duplicate recomputation.
- `planned_architecture.md` gained the three rules the implementation repeatedly validated: contexts own invariants, optional integration fan-out happens after commit, and supervised runtime placement stays separate from domain logic.

## Final Audit Posture

The audit is complete. Do not reopen audited areas simply because some modules remain large or protocol code looks unusual; the chunk documents name intentional quirks, accepted risks, and reference patterns. Reopen an area only when production evidence, a concrete feature, or a newly identified invariant supplies a specific reason.
