# Codebase Audit Plan

## Purpose

This folder holds an incremental, resumable audit of the whole HueWorks codebase. The audit is performed by a high-capability model that makes the decisions; the resulting findings docs are written so that cheaper models can implement them without re-deciding anything.

This file is the living plan and status ledger. Every audit session must end by updating the ledger below so the next session (possibly after a usage reset, with no shared context) can resume cold.

## How To Resume A Session

0. If you are the Auditor (any model in that role), read `auditor-instructions.md` first — role, per-session loop, judgment calibration, and the remaining-work map live there. Implementers read `codex-instructions.md`.
1. Read this file top to bottom.
2. Read `planned_architecture.md` (the architectural north star). (The pre-audit `planning/refactoring.md` has been fully absorbed and deleted.)
3. Find the first chunk in the ledger whose status is not `done`.
4. If a chunk is `in-progress`, its findings doc says exactly which files were already covered; continue from there.
5. Audit the chunk, write/extend its findings doc, update the ledger, stop at a clean boundary.

## Ground Rules

- `planned_architecture.md` is the rulebook. Findings are judged against it; when code and rulebook disagree, the finding cites the violated rule.
- The audit records decisions, not options. Each finding says what to do, not "consider X or Y". If a decision genuinely needs the owner's input, mark it `DECISION-NEEDED` and phrase the question crisply.
- Findings must be implementable by a cheaper model: concrete file paths (with line numbers where useful), target shape, guardrails, and required characterization tests.
- Audit-only sessions do not change code. Implementation happens in separate sessions driven by the findings docs.
- The pre-audit `planning/refactoring.md` items were absorbed by chunks 1/3/6a and the doc is deleted; new refactor targets belong in these chunk docs.

## Finding Format

Each finding in a chunk doc uses this shape:

```
### <CHUNK-ID>-<n>: <short title>
- Severity: critical | high | medium | low
- Type: refactor | bug-risk | hygiene | test-gap | doc-drift
- Where: file paths (+ line refs)
- What: the problem, concretely
- Why: which architecture rule or maintainability cost it hits
- Decision: what to do (the implementer executes this, not re-derives it)
- Guardrails: what must not change; required characterization tests
- Effort: S | M | L
```

Cross-cutting observations that belong to a later chunk get logged in that chunk's doc under a `## Parked (noted early)` section, or in `08-distillation.md` if architectural.

## Scope Per Chunk

Every chunk covers, for its files: refactoring targets, bug risks noticed in passing, repo hygiene, test-coverage gaps (cross-referencing `planning/test-coverage-audit.md`, not duplicating it), and doc drift against `README.md` / `planned_architecture.md` / planning docs.

## Chunk Ledger

Order follows the control pipeline (architecture centrality), not the directory listing.

| # | Chunk | Scope | Output doc | Status |
|---|-------|-------|------------|--------|
| 1 | Control plane | `lib/hueworks/control/**`, `lib/hueworks_app/control/**`, `lib/hueworks_app/cache*`, `lib/hueworks/active_scenes.ex` | `01-control-plane.md` | done |
| 2 | State ingestion | `lib/hueworks/subscription/**`, `lib/hueworks_app/subscription/**` (event streams, parsers, physical-state writes) | `02-state-ingestion.md` | done |
| 3 | Scenes & semantics | `lib/hueworks/scenes/**`, `lib/hueworks/scenes.ex`, `lib/hueworks/circadian*`, `lib/hueworks/presence_inputs.ex`, `lib/hueworks/external_scenes.ex` | `03-scenes-semantics.md` | done |
| 4 | Import & persistence | `lib/hueworks/import/**`, `lib/hueworks/bridge_seeds.ex`, `lib/hueworks/bridges.ex`, materialize/link paths, `lib/hueworks/schemas/**` (import-owned) | `04-import.md` | done |
| 5 | Integrations | `lib/hueworks/home_assistant/**`, `lib/hueworks/homekit*`, `lib/hueworks/picos/**` — judged against "integrations enter through normal control paths" | `05-integrations.md` | done |
| 6a | Web: scene builder | `lib/hueworks_web/live/scene_builder*`, `scene_editor_live.ex` | `06a-web-scene-builder.md` | done |
| 6b | Web: everything else | remaining `lib/hueworks_web/**` (lights/rooms/config LiveViews, components, controllers, plugs, filter prefs) | `06b-web-other.md` | done |
| 7 | Cross-cutting & support | `lib/hueworks/{util,color,kelvin,rooms,groups,lights,instance,app_settings,credentials,debug_logging}*`, `lib/mix/tasks/**`, `config/**`, test support | `07-cross-cutting.md` | done |
| 8 | Distillation | Architectural synthesis of 1–7: systemic patterns, remaining risks, reconciliation with `hueworks_todo.md` and `planned_architecture.md` | `08-distillation.md` | done |

Status values: `not-started` → `in-progress` → `done`. A chunk is `done` only when its findings doc is complete for its whole scope and this ledger row is updated.

## Session Log

| Date | Session did | Next step |
|------|-------------|-----------|
| 2026-07-05 | Created audit plan; completed chunk 1 (control plane): 12 findings incl. one high bug-risk (CP-1 manual-control queue clobbering), absorbed refactoring.md item 2 into CP-2/CP-3. | Chunk 2: state ingestion. |
| 2026-07-05 | Completed chunk 2 (state ingestion): 8 findings; confirmed the hueworks_todo HA group fan-out gap with mechanism (SI-1); SI-2 completes CP-5; several findings pair with CP-8/CP-9/CP-12. | Chunk 3: scenes & semantics. |
| 2026-07-05 | Reconciled codex's first implementation pass: verified CP-1 core, CP-6, SI-1 against diffs (all correct; suite green at 698 tests). Removed CP-6/SI-1 from findings docs; CP-1 reduced to a residual (`scenes/apply.ex:52` stale `:replace` default). Added reconciliation protocol above. | Implement remaining chunk 1/2 findings, or audit chunk 3. |
| 2026-07-05 | Completed chunk 3 (scenes & semantics): 5 findings. SC-1 absorbs refactoring.md item 1 (power-policy vocabulary parsed in 3 places); SC-2 covers inline integration-sync calls (stage 2 blocked on chunk 5); SC-4 closes the chunk-1 parked enqueue-mode question; resolved chunk-2 parked external-scenes question (clean). Layer is healthier than expected; Circadian.Config named the boundary-module reference pattern. | Chunk 4: import & persistence. |
| 2026-07-05 | Completed chunk 4 (import): 8 findings. IM-1 CONFIRMED data bug (NormalizeJson stringifies booleans/nil in every normalized_json row); IM-8 ReimportApply (860 lines, deletes entities) has ZERO tests — blocks all other chunk-4 work; IM-2 Materialize/ReimportApply duplication incl. a display_name behavior divergence; import-resync.md badly drifted (IM-6). | Chunk 5: integrations (HA export, HomeKit, Picos). |
| 2026-07-05 | Reconciled codex pass 2: verified SC-2 stage 1, SC-3, SC-4 + CP-1 residual, IM-1 against diffs — all correct, suite green at 701 tests, nothing refuted. Deleted completed findings outright per new forward-facing rule (also retroactively removed the pass-1 tombstone lines from 01/02); protocol step 3 updated. | Implement IM-8/SC-1/CP-2 next, or audit chunk 5. |
| 2026-07-06 | Reconciled codex pass 3 (largest yet): verified CP-2/4/5/7/8/9/10/12, SI-2/6/8, SC-1, IM-3/7 complete + IM-8 partial — suite green at 721 tests, nothing refuted. Notable: shared GroupState projection gained a deliberate kelvin-over-xy white-state invariant (test-encoded); refactoring.md items 1+2 landed (item 2 has an HA-export residual for chunk 5); IM-8 rewritten as residual matrix. Chunk 1 is down to CP-3 + CP-11(no-op); chunk 3 fully blocked/deferred. | Implement IM-8 residual/SI-4/CP-3, or audit chunk 5 (which unblocks SC-2 + the HA-export residual). |
| 2026-07-06 | Reconciled codex pass 4: verified SI-4/SI-5/SI-7 — suite green at 730 tests, nothing refuted. Bonus from SI-5: HA indexes now reload on every websocket reconnect (handle_connect). Chunk 2 is down to SI-3 only; all four streams now share the reference stream behaviors. | Implement IM-8 residual/CP-3/SI-3, or audit chunk 5. |
| 2026-07-06 | Completed chunk 5 (integrations), audited in 4 flushed sub-passes: 6 findings, all small. Headline: no control-path bypasses anywhere; SC-2 is GO (design in 05 doc, 03 updated); IN-1 finishes refactoring.md item 2; both chunk-1 HA parked items and the chunk-2 Pico parked item resolved (IN-5, IN-6). | Implement SC-2/IN-1/IM-8 residual/CP-3/SI-3, or audit chunk 6a (scene builder). |
| 2026-07-06 | Reconciled codex pass 5: verified SC-2 (DomainEvents inversion — publisher + subscriber sides exact, both sync guardrails held), IN-1..IN-6, AND an undocumented SI-3/CasetaLeap (verified independently; includes IM-5's Caseta half). Suite green at 748 tests. Chunks 2/3/5 now have zero actionable findings; IM-5 rewritten to its Z2M-fetch residual; refactoring.md down to item 3 only. Process note: implementation notes were stale vs the tree (SI-3 unlisted, test count off) — flagged to owner. | Remaining backlog: CP-3, IM-2/4/5-residual/6/8-residual. Or audit chunk 6a. |
| 2026-07-06 | Reconciled codex pass 6: verified CP-3 (atom-key funnel via `normalize_keys/1` in merge_state + State.ensure; downstream dual-key handling deleted incl. the 05 rider; only StateParser stays loose — correct), IM-8 residual (full 12-case matrix), IM-2/4/5/6, and the SI-3 sentinel bug fix (real latent multi-line-packet bug, red/green). Suite green at 753. **Codex correctly REFUTED IM-2's display_name divergence sub-claim** — the schema's put_default_display_name forces it on both paths; correction recorded in 04. **The chunks 1–5 backlog is now empty** (CP-11 accepted-risk, SC-5 perf-deferred). | Audit chunk 6a (scene builder) next; then 6b, 7, 8 (distillation). |
| 2026-07-06 | Completed chunk 6a (scene builder): 3 findings. Verdict on refactoring.md item 3: mostly already fixed organically (thin Flow, PowerPolicy, Builder, Topology); SB-1 is the right-sized remainder (Component struct + State facade split), after which refactoring.md gets deleted entirely. SB-4: editor double-activates scenes (only web caller of set_active). | Audit chunk 6b (remaining web), then 7, 8. |
| 2026-07-06 | Completed 6b-1 (manual control surfaces): 4 findings. WB-1 Reload button blocks LiveView on full synchronous bridge re-bootstrap; WB-2 the UI is the SOLE caller of State.ensure and fabricates physical-state observations for slider defaults (delete ensure, make defaults display-local); WB-3/4 duplication + dead-tolerance smalls. Lights surface confirmed on the shared ManualControl semantic path. | 6b-2 (config/bridge-setup UI vs import-resync contract), 6b-3 (picos/rooms), 6b-4 (light-state editor + sweep). |
| 2026-07-06 | Reconciled codex pass 7: verified SB-1 (Component struct + Membership/Policy/CustomState split behind the State facade, 769→194-line facade), SB-2/SB-4 (with single-broadcast red/green), WB-1..WB-4 — all exact; refactoring.md deleted with its dangling pointers fixed (00-plan, planned_architecture.md). Chunks 6a and 6b-1 now have zero open findings. Suite: 756 tests, but surfaced an intermittent PRE-EXISTING SQLite "Database busy" flake (logged in hygiene section for chunk 7; not caused by this pass — verified green twice, flaky once/twice across runs). | Audit 6b-2 (config/bridge-setup vs import-resync contract), then 6b-3/6b-4, 7, 8. |
| 2026-07-06 | Audited 6b-2 bridge_setup + config_live in two atomic flushed drops: 7 findings. Headline: WB-9 CONFIRMED high bug — saving HA export settings with the blank password field (whose placeholder promises "leave blank to keep") WIPES the stored MQTT password via HaExportConfig's blank-as-nil semantics. Also WB-5 (destructive reimport resolutions lack confirmation — the one genuinely-missing hueworks_todo reimport UI item; items 1+3 look mostly satisfied, owner should re-check), WB-10 one-click bridge deletion, WB-6/7/8/11 extractions. | Resume at 6b-2 part 3 (bridge_live.ex), then 6b-3, 6b-4, 7, 8. |
| 2026-07-06 | Reconciled codex pass 8 incrementally: WB-5..WB-11 all verified exact (suite 763 green, +7 tests, no flake this run). WB-9's two-layer password fix, WB-5's dependency-disclosure confirm panel (incl. clearing stale confirmations on plan edits), Import.apply_review/ReviewPlan/Bridges.imported?/editor_label extractions all consumed at every call site. hueworks_todo's three reimport UI bullets now all look satisfied — owner should hands-on verify and trim. Zero open findings anywhere; only audit work remains. | Audit 6b-2 part 3 (bridge_live.ex), then 6b-3, 6b-4, 7, 8. |
| 2026-07-06 | Audited bridge_live (6b-2 done) + rooms/external-scene (6b-3 part 1) in two atomic drops: 5 findings. WB-12 wizard connection tests block the LiveView (same class as fixed WB-1); WB-15 one-click room/scene/presence deletion with zero data-confirm (same class as fixed WB-10); WB-13/14/16 smalls (Z2M vocab copy + staging leftovers, atom leak from form params, String.to_integer crashes, triple-copied scene-toggle flow, dead assigns). | Audit 6b-3 part 2 (pico_config_live, ~1,700 lines w/ heex), then 6b-4, 7, 8. |
| 2026-07-06 | Reconciled codex pass 9: WB-12..WB-16 all verified exact — suite 767 green twice, no flake. WB-12 landed with request-id guarding against stale async completions (beyond spec); WB-13 added TTL-based staging prune in Credentials; Scenes.toggle_activation consumed by all three LiveViews. Zero open findings again. | Audit 6b-3 part 2 (pico_config_live), then 6b-4, 7, 8. |
| 2026-07-06 | Prepared auditor handoff (Fable → any capable model, e.g. GPT Sol): wrote `auditor-instructions.md` (role, per-session loop, judgment calibration, remaining-work map — everything that previously lived only in Fable's session memory); created `07-cross-cutting.md` with the scattered hygiene/warnings/flake/parked backlog consolidated as CC-1..CC-6; pointed 00-plan resume instructions and the former parked sections at the new docs. | New auditor: read auditor-instructions.md, then resume at 6b-3 part 2 (pico_config_live). CC-1..CC-6 are implementable by codex immediately. |
| 2026-07-10 | Completed 6b-3 part 2 (`pico_config_live` + HEEx) after confirming a clean tree and no implementation receipts: 4 findings. Pico config CRUD correctly stays behind `Picos`/`Picos.Config`; WB-17 moves blocking three-endpoint Caseta sync async, WB-18 fixes stale all-unchecked form state, WB-19 splits the 28-assign monolith into focused web coordinators, and WB-20 adds cascade-aware confirms to config clear/clone/group delete/binding clear. Audit-only docs pass; no test run per AGENTS.md. | Implement WB-17..WB-20 or audit 6b-4 (light-state editor + remaining web sweep), then 7 and 8. |
| 2026-07-10 | Reconciled the Pico implementation pass against code and tests: WB-17 async sync (including request-id/stale-result guard), WB-19 Loader/ControlGroupEditor/BindingEditor split, and WB-20 cascade-aware confirms are correct and removed. WB-18 is partial: all-unchecked now works, but the extraction regresses `groups -> scene -> groups` by discarding the preserved group IDs on return; rewritten to that residual only. Focused suite 31 green, full suite 777 green, format check green; receipt deleted. | Implement WB-18 residual or audit 6b-4, then 7 and 8. |
| 2026-07-10 | Reconciled the WB-18 residual: verified the new red/green unit and LiveView coverage, and confirmed `BindingEditor` now distinguishes a rendered all-unchecked group form from a scene form that cannot submit group IDs. Both `groups -> scene -> groups` retention and explicit final-group clearing hold. Focused suite 30 green, full suite 779 green; receipt deleted. 6b-3 has zero open findings. | Audit 6b-4, then 7 and 8. |
| 2026-07-10 | Completed 6b-4 and chunk 6b: line-by-line light-state editor/FormState/Preview audit plus components/controllers/plugs/filter prefs and full HEEx/route/action sweep. Three findings: WB-21 makes the existing dead/inaccurate dirty state protect real unsaved edits, WB-22 removes the broken `/explore` route and unused generated web scaffolding, WB-23 confirms one-click light-state deletion. Control and persistence boundaries remain sound. Audit-only docs pass; no new test run after the already-green 779 reconciliation suite. | Implement WB-21..WB-23 or begin chunk 7 cross-cutting/support audit, then chunk 8 distillation. |
| 2026-07-10 | Completed chunk 7: audited the support contexts/math/input boundaries, every Mix task, dependencies/config, and test support. Six new findings (CC-7..CC-12): canonical-light validation bypass and destructive DB maintenance tasks are the high risks; group room cascade/export consistency, partial HA-toggle derivation, bounded import source parsing, and the exact upstream tzdata 1.1.3/OTP 29 crash round out the pass. Reverified the pre-collected backlog and current ignored-root-artifact state; CC-6 was resolved as a justified leave-alone. Architecture remains sound; the issues are narrow invariants, maintenance safety, and infra hygiene. | Implement WB-21..WB-23 and the open CC findings, or complete chunk 8 distillation. |
| 2026-07-10 | Completed chunk 8 and the whole-code audit. Distillation confirms the desired/physical/planner/executor pipeline, boundary normalization, integration entry paths, and runtime/domain split are sound; no rewrite is warranted. Codified context-owned invariants, post-commit domain-event fan-out, and file placement in the architecture rulebook. Reconciled planning drift: destructive reimport confirmation and the generic coverage-audit task are complete; their docs now contain only concrete residual work. | Implement WB-21..WB-23 and CC-1..CC-5/CC-7..CC-12. Future Auditor sessions reconcile receipts before any new audit work. |
| 2026-07-11 | Reconciled the final WB/CC implementation passes across committed and working-tree changes. Verified WB-21..23 and CC-1/4/7/8/9/10/11/12 complete; focused suite 194 green, full suite 799 green, forced test compile warning-free. CC-2 is reduced to its missing direct HAP delegation tests. CC-5 is partial/refuted as complete: its new linked-child test passes by restarting the entire supervised manager; an independent probe confirmed the original manager dies on child `:shutdown`, so the finding now specifies real per-connection isolation and same-manager evidence. CC-3 remains human-approved local cleanup only. Receipts deleted. | Implement CC-2 and CC-5. Ask Ian immediately before performing CC-3 cleanup. |
| 2026-07-11 | Reconciled the CC-2/CC-5 follow-up. CC-2's two direct HAP delegation cases are exact. CC-5's runtime fix is correct: the manager traps known connection exits, preserves supervisor semantics for unknown links, and a no-supervisor probe verified the original manager survives with one distinct tracked replacement. Its test still has a pending automatic retry when it manually sends `:retry_bootstrap`, so the next attempt can be a duplicate bootstrap; CC-5 is reduced to removing that false-positive path. Focused suite 34 green, full suite 801 green, forced test compile warning-free. Receipt deleted. CC-3 was not attempted because no destructive-cleanup approval was given. | Implement the CC-5 deterministic-test residual. Ask Ian immediately before CC-3 cleanup. |
| 2026-07-11 | Reconciled the CC-3/CC-5 residual pass. CC-5 is exact: only the scheduled readiness retry creates the initial child, and the test proves one tracked child before/after crash under the same manager; focused 17 and full 801 green after schema setup. CC-3's approved cleanup stayed within scope (root crash/DB/export artifacts removed; secrets and `data/homekit` retained), but exposed that plain `mix test` from the clean checkout creates an unmigrated DB and fails 17/17 with `no such table: bridges`; the receipt's suite preceded deletion. CC-3 is reduced to adding the standard create/migrate test alias. Auditor verification DB was removed afterward. Receipt deleted. | Implement the CC-3 clean-test-database bootstrap; then the audit backlog is empty. |
| 2026-07-11 | Reconciled the final CC-3 residual from a genuinely absent test database. The standard test alias creates/migrates before the real task and preserves focused arguments; the migration unit test safely avoids redefining an already-loaded migration module. Clean-state focused suite 17 green and clean-state full suite 801 green. Generated test DB/sidecars removed afterward; format, forced test compile, and diff checks green. Receipt deleted. | Audit and audit-directed implementation backlog are empty. |

Note on AGENTS.md rule 1 (planning docs are forward-looking): the owner explicitly requested this ledger/session log so audit sessions can resume across usage resets. Keep entries to one line; when the whole audit is implemented and distilled, delete this folder's ledger rather than letting it become a progress narrative.

## Repo Hygiene

No cross-cutting findings remain. The former CC-6 readiness question was audited and resolved as a leave-alone.

## Implementation Reconciliation Protocol

Implementer models (codex) record what they changed in `NN-<chunk>-implementation.md` next to the findings doc they worked from. When the auditor next runs, before starting any new chunk:

1. Read each `*-implementation.md`, then verify the claims against the actual diffs (`git diff` / `git log`) — never trust the note alone.
2. Run `mix test` (full suite) and confirm green.
3. Update the findings doc — docs stay strictly forward-facing: delete findings that are fully implemented and verified (no tombstones, no "removed as implemented" lists); rewrite partially-done findings to contain only the residual work; refute incorrect implementations by reverting the finding to open with a note on what went wrong. Keep finding IDs stable — never renumber; each doc's Status line says gaps mean completed work. Also sweep the other findings docs for now-dangling references to the deleted IDs.
4. Propagate completions to other planning docs (`hueworks_todo.md`, etc.) per AGENTS.md rule 2.
5. Delete the `*-implementation.md` file and log the reconciliation in the session log.

## Handoff Contract For Implementer Models

When feeding a chunk doc to an implementation model, give it: the chunk doc, `planned_architecture.md`, and this instruction: "Implement finding <ID> exactly as decided. Write the listed characterization tests first. Do not expand scope. Run `mix test` (and `mix credo`) before finishing."
