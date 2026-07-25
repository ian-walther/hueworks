# Release Audit Plan

Audit of all work since `09fa9e360c7bfe` (pre-effort baseline) through `HEAD` (`ff525f8` at plan time): the onboarding UX effort plus supporting refactors, per `planning/pre-release_refinement.md` and `planning/area-onboarding-rollout.md`. Three angles per chunk: **technical** (correctness, data safety, concurrency, security), **code style** (consistency with the post-refactor architecture, `planning/audit/08-distillation.md` conventions), and **UX** (state coverage matrix in `pre-release_refinement.md`, copy, honesty of status).

This is an audit only — no code changes. Findings go in per-chunk docs here, following the rules in `planning/audit/auditor-instructions.md`: stable IDs, decisions not options, forward-facing docs (completed work is deleted, not marked done), flush findings after every file or small file-group so a dead session loses nothing.

## Ground Rules For The Auditing Session

1. **Scope is committed work only**: `git log 09fa9e3..HEAD`. Sol has in-flight uncommitted HA browser-authorization work in the working tree (untracked `lib/hueworks/home_assistant/authorization.ex`, `connection_validator.ex`, `token_provider`, auth controller, plus modifications listed in `dirty-files` below). Do NOT audit that; it is not done.
2. **Dirty-file rule**: for any file modified in the working tree, read the committed version with `git show HEAD:<path>`. Dirty files at plan time (re-check with `git status` each session; if HEAD has moved past `ff525f8`, re-derive):
   README.md, assets/css/app.css, config/dev.exs, config/test.exs, docs/compatibility.md, docs/troubleshooting.md, lib/hueworks/application.ex, lib/hueworks/connection_test/home_assistant.ex, lib/hueworks/control/bootstrap/home_assistant.ex, lib/hueworks/control/group.ex, lib/hueworks/control/home_assistant_bridge.ex, lib/hueworks/control/home_assistant_client.ex, lib/hueworks/control/light.ex, lib/hueworks/home_assistant/host.ex, lib/hueworks/import/fetch/home_assistant.ex, lib/hueworks/import/fetch/home_assistant/client.ex, lib/hueworks/schemas/bridge/credentials.ex, lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex, lib/hueworks_web/live/config/bridge_live.html.heex, lib/hueworks_web/live/config/bridges_config_live.{ex,html.heex}, lib/hueworks_web/live/setup_live.html.heex, lib/hueworks_web/router.ex, and matching tests.
3. **Do not run the full test suite against the dirty tree** as an audit signal — failures may be Sol's in-progress work. Static reading and targeted `git show` diffs only. (This differs from the old auditor loop, which reconciled receipts; there are no receipts here.)
4. **Resume protocol**: read this file, find the first chunk in the tracker below that is not `done`, open its doc (if any), continue from its "Next" line. Update the tracker and the chunk doc's status line before ending every session.
5. **Severity calibration** (from auditor-instructions): high = data corruption, silent state divergence, broken release-gate journey, security regression; medium = blocking UI, missing safety affordance on destructive action, dishonest status, systemic drift; low = dead code, single-copy duplication, copy nits.
6. Cite the planning doc requirement a finding violates where one exists (`pre-release_refinement.md` sections, rollout runbook, state coverage matrix).

## Commit Range Under Audit

```text
1113a4f pre-release setup refinements        (74 files — grab-bag: discovery, bridges, health, docs, CSS)
7f60f53 persist published room identities
e88ae84 rename rooms to areas                (222 files — mechanical + migration 20260717140000)
3503af0 add external space mappings
5bb32e3 add home assistant setup guidance
24e3257 cover visible ha placement guidance  (test-only)
4b2ffd6 add resumable onboarding state
7e41dbd add guided first run setup
25cc6f3 add isolated verification mode
a4a5d49 report isolated verification health
4645ee9 preserve pico area metadata during migration
e9e7dfe fix area control copy
fd40400 polish area language
ff525f8 document area rollout
```

## Chunk Tracker

| # | Doc | Scope | Status |
| --- | --- | --- | --- |
| 1 | `01-migrations-data-safety.md` | All 5 migrations (`20260717120000`–`160000`), `lib/hueworks/release.ex`, `database_maintenance.ex`, `published_identity.ex`, backup/restore path, consistency with `area-onboarding-rollout.md` runbook assertions. Prefix **MG**. | done |
| 2 | `02-area-rename.md` | Rooms→Areas rename fidelity: `e88ae84` + `4645ee9` + copy commits. Leftover "room" references in code/UI/docs, API surface rename (`/api/areas`, removed room ops), redirect handling of old URLs, HA MQTT identity preservation (`export/sync/areas.ex`, discovery identities), pico `action_config`/metadata key migration. Prefix **AR**. | done |
| 3 | `03-bridge-onboarding.md` | `lib/hueworks/bridge_onboarding/**` (hue + HA mDNS, pairing, vendor discovery), `bridges.ex`, connection_test changes (caseta, z2m; HA via `git show`), `bridge_setup_live.{ex,heex}`, duplicate-identity handling, `external_id` migration usage. Prefix **BO**. | done (heex templates deferred to chunk 7) |
| 4 | `04-external-spaces-ha-inventory.md` | `external_spaces.ex`, schemas, `import/space_mappings.ex`, `import/space_suggestions.ex`, `home_assistant/inventory.ex`, `onboarding/area_design.ex`, import-plane integration (`review_plan.ex`, `materialize.ex`, `reimport_*` deltas), the "mappings guide placement without changing existing intent" rule. Prefix **ES**. | done — **contains ES-1, a high-severity apply-crash/data bug; read first** |
| 5 | `05-guided-setup.md` | `onboarding.ex`, onboarding state in `app_settings`, `setup_live.ex` (+ heex via `git show`), router/redirect integration, resumability, non-wizard rule ("do not force rigid wizard"), first-run journey against release-gate description. Prefix **OB**. | done |
| 6 | `06-isolated-verification.md` | `runtime_io.ex`, `application.ex` (via `git show`), `hueworks_app/health.ex`, `health_controller.ex`, `hardware_smoke.ex`, `z2m/snapshot.ex`, isolated-mode leak risk (can verification mode ever touch real lights / real brokers). Prefix **IV**. | done |
| 7 | `07-web-ui-sweep.md` | Remaining web layer deltas: `bridge_live.ex` (+537 lines), config lives, `control_live.ex`, `areas_live.*`, reimport live changes, scene builder/editor deltas, lights_live deltas, `app.css` (+513), state coverage matrix spot-checks, accessibility/responsive per refinement doc. Largest chunk — may split into 7a (bridge/config) and 7b (control/areas/scenes/lights/CSS). Prefix **UI**. | done (app.css + interactive a11y matrix deferred to rehearsal; noted in doc) |
| 8 | `08-cross-cutting.md` | Docs (README, compatibility, troubleshooting via `git show`), test-coverage assessment for the new subsystems, style-drift sweep (naming, boundary-module pattern adherence), gap analysis: what the release-blocker list still requires vs. what landed. Park out-of-scope observations from other chunks here. Prefix **RC**. | done — original-range audit COMPLETE |

Statuses: `pending` → `in-progress` (doc has a "Next:" line) → `done` (doc is findings-only, no tracker).

## Phase 2: Working-Tree Audit (Sol's in-flight work, uncommitted at `ff525f8`)

Commissioned after the original-range audit completed. Scope: `git diff HEAD` + untracked files (~1,631 changed + ~1,022 new lines). This code is **in-flight** — findings may describe work Sol is mid-way through; reconcile against the tree state at implementation time.

| # | Doc | Scope | Status |
| --- | --- | --- | --- |
| 9 | `09-ha-browser-auth.md` | HA browser authorization: `home_assistant/authorization.ex`, `connection_validator.ex`, `home_assistant_auth_controller.ex`, `hueworks_app/home_assistant/token_provider.ex`, `host.ex`/`credentials.ex` deltas, token-provider adoption across import/control/event-stream/connection-test, bridge_live + router integration. Audit against the blocker spec in `pre-release_refinement.md` §Home Assistant Browser Authorization. Prefix **HA**. | done |
| 10 | `10-caseta-location-misc.md` | Caseta discovery groundwork (`bridge_onboarding/caseta/`, `hueworks_app/bridge_onboarding/caseta*`), location postal-code lookup (`hueworks_app/location/`), general/setup/config UI deltas, docs/config deltas, remaining diff sweep. Prefix **CL**. | done |

## Phase 3: Reconciliation + New Commits (started 2026-07-24, HEAD `5af7d22`)

Phase-2 work landed as `daf87f5` (HA auth) + `d3afcee` (native discovery); new work: `7a0fd54` (persist area onboarding decisions), `c07d08f` (guided onboarding workflow), `f6ceb0f` (test stabilization), `5af7d22` (docs). Tree is clean.

| Step | Scope | Status |
| --- | --- | --- |
| R | Reconcile all open findings (MG/AR/BO/ES/OB/IV/UI/RC/HA/CL) against HEAD; delete fixed ones from docs (forward-facing rule); verify committed `daf87f5`/`d3afcee` match the audited working tree. | done — OB-1 fixed and deleted; OB-2/OB-3 relocated to `SetupAreasLive`; committed phase-2 code matches the audit; ALL other findings remain open, including ES-1 (high) |
| 11 | `11-onboarding-workflow.md` — audit `7a0fd54` + `c07d08f` + `f6ceb0f` with the same criteria. Prefix **OW**. | done — ALL PHASES COMPLETE at `5af7d22` |

## Phase 4: Implementation Reconciliation (2026-07-26)

Codex implemented the backlog (uncommitted working tree on `5af7d22`); receipts verified against actual diffs finding-by-finding and deleted. Full suite: **1077 tests, 0 failures**.

- **Implemented and verified faithful (deleted from docs)**: MG-1, AR-2, AR-3, BO-1, BO-3, BO-4, BO-5, ES-1, ES-2, OB-2, OB-3, IV-1, IV-2, IV-3, UI-1, HA-1, HA-2, CL-1, CL-2, CL-3, CL-4, OW-1, OW-2, OW-3. Several were better than spec (shared `ApplyError` adopted in both import LiveViews; identity capture threaded through `apply_test_result`; per-bridge design retry).
- **Correctly refuted by the implementer**: MG-2 (256 bare `%Area{}` test inserts rely on autogeneration; recorded in `01-` — the implementer was right).
- **AR-1 resolved**: Ian confirmed (2026-07-26) that dropping `/rooms` routes without redirects is the intended product behavior; recorded as leave-alone in `02-`.
- **RC-1 closed** (Sol, reconciled 2026-07-26): blob-shaped fixtures now default across all named import suites with atom smoke cases; the rollout exposed and fixed a real `ReimportPlan` mixed-key defect (see `08-`); suite green at 1077.

**AUDIT CLOSED — zero open findings.** Remaining work is product/release scope only: chunk 8's gap table and rehearsal checklist.
- Still-relevant non-finding work: chunk 8's gap table (open release blockers: Caseta LEAP pairing, Z2M discovery assistance, Docker discovery rehearsal, diagnostics surface, screenshots/favicon, circadian modes, status vocabulary) and the rehearsal checklist.

## Chunk Ordering Rationale

Data safety first (chunk 1) because the migration is irreversible in production and the runbook depends on its exact behavior; rename fidelity second because everything else sits on top of it; then the three new subsystems in dependency order (discovery → spaces/inventory → guided setup); runtime verification mode; then the wide-but-shallower UI sweep; cross-cutting last so it can aggregate parked observations.
