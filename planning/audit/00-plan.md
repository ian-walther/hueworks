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
| 3 | Scenes & semantics | `lib/hueworks/scenes/**`, `lib/hueworks/scenes.ex`, `lib/hueworks/circadian*`, `lib/hueworks/presence_inputs.ex`, `lib/hueworks/external_scenes.ex` | `03-scenes-semantics.md` | not-started |
| 4 | Import & persistence | `lib/hueworks/import/**`, `lib/hueworks/bridge_seeds.ex`, `lib/hueworks/bridges.ex`, materialize/link paths, `lib/hueworks/schemas/**` (import-owned) | `04-import.md` | not-started |
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

Note on AGENTS.md rule 1 (planning docs are forward-looking): the owner explicitly requested this ledger/session log so audit sessions can resume across usage resets. Keep entries to one line; when the whole audit is implemented and distilled, delete this folder's ledger rather than letting it become a progress narrative.

## Repo Hygiene (global, found during setup)

Logged here because they were visible before any chunk started; chunk 7 will finalize them:

- Repo root contains local databases and artifacts that look like they should be untracked/removed: `hueworks_dev.db`, `hueworks_test.db*`, `hueworks copy.db*`, `hueworks_dev_20260121T020205.db*`, `erl_crash.dump`. Verify git-tracked status before deleting; fix `.gitignore` accordingly.
- `secrets.env` and `secrets.json` sit in the repo root. `secrets.json` is a documented seed mechanism (see README), but confirm both are gitignored and never committed; consider moving the documented default out of the repo root.
- `exports/` contains captured bridge payloads with LAN IPs — decide whether these are fixtures (move under `test/fixtures/` or `priv/`) or scratch data (delete/ignore).

## Handoff Contract For Implementer Models

When feeding a chunk doc to an implementation model, give it: the chunk doc, `planned_architecture.md`, and this instruction: "Implement finding <ID> exactly as decided. Write the listed characterization tests first. Do not expand scope. Run `mix test` (and `mix credo`) before finishing."
