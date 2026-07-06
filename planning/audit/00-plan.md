# Codebase Audit Plan

## Purpose

This folder holds an incremental, resumable audit of the whole HueWorks codebase. The audit is performed by a high-capability model that makes the decisions; the resulting findings docs are written so that cheaper models can implement them without re-deciding anything.

This file is the living plan and status ledger. Every audit session must end by updating the ledger below so the next session (possibly after a usage reset, with no shared context) can resume cold.

## How To Resume A Session

1. Read this file top to bottom.
2. Read `planned_architecture.md` (the architectural north star) and skim `planning/refactoring.md` (the pre-existing refactor targets, which this audit supersedes-by-absorption but must reconcile with).
3. Find the first chunk in the ledger whose status is not `done`.
4. If a chunk is `in-progress`, its findings doc says exactly which files were already covered; continue from there.
5. Audit the chunk, write/extend its findings doc, update the ledger, stop at a clean boundary.

## Ground Rules

- `planned_architecture.md` is the rulebook. Findings are judged against it; when code and rulebook disagree, the finding cites the violated rule.
- The audit records decisions, not options. Each finding says what to do, not "consider X or Y". If a decision genuinely needs the owner's input, mark it `DECISION-NEEDED` and phrase the question crisply.
- Findings must be implementable by a cheaper model: concrete file paths (with line numbers where useful), target shape, guardrails, and required characterization tests.
- Audit-only sessions do not change code. Implementation happens in separate sessions driven by the findings docs.
- The existing `planning/refactoring.md` items (scene power policy extraction, state-map normalization, scene builder state split) are inputs; the relevant chunk docs absorb, refine, or supersede them and say so explicitly.

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
| 5 | Integrations | `lib/hueworks/home_assistant/**`, `lib/hueworks/homekit*`, `lib/hueworks/picos/**` — judged against "integrations enter through normal control paths" | `05-integrations.md` | not-started |
| 6a | Web: scene builder | `lib/hueworks_web/live/scene_builder*` | `06a-web-scene-builder.md` | not-started |
| 6b | Web: everything else | remaining `lib/hueworks_web/**` (lights/rooms/config LiveViews, components, controllers, plugs, filter prefs) | `06b-web-other.md` | not-started |
| 7 | Cross-cutting & support | `lib/hueworks/{util,color,kelvin,rooms,groups,lights,instance,app_settings,credentials,debug_logging}*`, `lib/mix/tasks/**`, `config/**`, test support | `07-cross-cutting.md` | not-started |
| 8 | Distillation | Architectural synthesis of 1–7: systemic patterns, layering violations ranked, recommended sequencing of all refactors, reconciliation with `planning/refactoring.md` + `hueworks_todo.md` | `08-distillation.md` | not-started |

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

Note on AGENTS.md rule 1 (planning docs are forward-looking): the owner explicitly requested this ledger/session log so audit sessions can resume across usage resets. Keep entries to one line; when the whole audit is implemented and distilled, delete this folder's ledger rather than letting it become a progress narrative.

## Repo Hygiene (global, found during setup)

Logged here because they were visible before any chunk started; chunk 7 will finalize them:

- Repo root contains local databases and artifacts that look like they should be untracked/removed: `hueworks_dev.db`, `hueworks_test.db*`, `hueworks copy.db*`, `hueworks_dev_20260121T020205.db*`, `erl_crash.dump`. Verify git-tracked status before deleting; fix `.gitignore` accordingly.
- `secrets.env` and `secrets.json` sit in the repo root. `secrets.json` is a documented seed mechanism (see README), but confirm both are gitignored and never committed; consider moving the documented default out of the repo root.
- `exports/` contains captured bridge payloads with LAN IPs — decide whether these are fixtures (move under `test/fixtures/` or `priv/`) or scratch data (delete/ignore).

## Implementation Reconciliation Protocol

Implementer models (codex) record what they changed in `NN-<chunk>-implementation.md` next to the findings doc they worked from. When the auditor next runs, before starting any new chunk:

1. Read each `*-implementation.md`, then verify the claims against the actual diffs (`git diff` / `git log`) — never trust the note alone.
2. Run `mix test` (full suite) and confirm green.
3. Update the findings doc — docs stay strictly forward-facing: delete findings that are fully implemented and verified (no tombstones, no "removed as implemented" lists); rewrite partially-done findings to contain only the residual work; refute incorrect implementations by reverting the finding to open with a note on what went wrong. Keep finding IDs stable — never renumber; each doc's Status line says gaps mean completed work. Also sweep the other findings docs for now-dangling references to the deleted IDs.
4. Propagate completions to other planning docs (`hueworks_todo.md`, etc.) per AGENTS.md rule 2.
5. Delete the `*-implementation.md` file and log the reconciliation in the session log.

## Handoff Contract For Implementer Models

When feeding a chunk doc to an implementation model, give it: the chunk doc, `planned_architecture.md`, and this instruction: "Implement finding <ID> exactly as decided. Write the listed characterization tests first. Do not expand scope. Run `mix test` (and `mix credo`) before finishing."
