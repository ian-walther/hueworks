# Chunk 8: Cross-Cutting — Docs, Tests, Style, Gap Analysis

Status: complete. Scope: README/`docs/compatibility.md`/`docs/troubleshooting.md` (at HEAD `ff525f8` via `git show`; all three dirty with later work), committed test-suite shape for the new subsystems, residual style sweep, and the release-blocker gap analysis against `planning/pre-release_refinement.md`. This closes the audit of the original commit range `09fa9e3..ff525f8`.

## Findings

### RC-1 — closed 2026-07-26, and it earned its keep

Fully implemented: every suite named by the finding (space mappings, suggestions, inventory, area design, reimport plan, reimport apply) now defaults its normalized fixtures to `blob_shaped/1` (JSON round-trip) with explicit atom-key smoke cases retained via `:blob`/`:atom` shape parameters. **The very first blob-shaped run exposed a real production defect** (red evidence: 2 of 35 failures): `ReimportPlan.build/3` did `Map.put(:lights, filtered)` on a possibly string-keyed snapshot, creating a mixed-key map whose stringification could resurrect the *unfiltered* entity list — silently restoring HueWorks-exported wrappers that `Duplicates.reject_hueworks_exported/1` had removed. Fixed by canonicalizing both normalized inputs through `NormalizeJson.to_map/1` at the function boundary and writing string keys only (verified line-by-line; public output shape unchanged; suite green at 1077). This was the same bug class as ES-1, in a module the original audit had read — the finding's premise (atom-keyed fixtures mask this class) is now empirically proven twice. The boundary-rule record in `04-` covers the durable lesson.

## Release-Blocker Gap Analysis (committed range vs `pre-release_refinement.md`)

Status of each blocker/refinement as of `ff525f8`. "Open" = not a defect in this range; listed so the release checklist stays honest. Items marked ⏳ have uncommitted work in the working tree that the phase-2 audit covers.

| Requirement | Status at `ff525f8` |
| --- | --- |
| HA browser authorization replaces long-lived token | **Landed** (`daf87f5`, audited in chunk 9; HA-1/HA-2 implemented 2026-07-26). README/compatibility now describe OAuth as the normal path with token fallback — verified current. |
| Guided Caseta pairing | Open — serial-driven *discovery* landed (`d3afcee`), but LEAP certificate acquisition (the actual blocker) is still unimplemented; compatibility doc states the limitation plainly. |
| Guided Z2M assistance (`_mqtt._tcp` discovery, base-topic candidates, multi-instance) | Open — HA-export-reuse + retained-snapshot validation landed; discovery honestly documented as "not guaranteed". |
| Discovery in production Docker topology | Open — rehearsal item; chunk 3 noted the `.local` fallback host risk to verify there. |
| Import ordering & duplicate transparency | **Landed** — inventory-first journey, `ha_import_order_risk` warning, wrapper-linking disclosure in completion summary. |
| ExternalSpaceMappings guide new placement only | **Landed** — the ES-1 identity defect is fixed and verified (2026-07-26); only the RC-1 fixture-breadth residual remains. |
| Scene onboarding explanations | **Landed** — scene-builder guidance callout + power-policy disclosure. |
| Circadian Basic/Advanced modes | Open — untouched in this range; still an Open Product Decision. |
| Common bridge status vocabulary on cards/panels | Partial — health readiness, three-state HomeKit runtime status, imported?/latest-import on bridge cards. The full configured/worker/last-event/retrying vocabulary is not built. |
| Diagnostics surface + copyable support summary | Open — `/health` and the verification banner exist; no operator diagnostics page or support summary. |
| Docs: install/upgrade/rollback/troubleshooting/compatibility | **Largely landed** — first-run journey, optional-seeds demotion, backup/restore procedure (verified accurate against `Release`/`DatabaseMaintenance` including the `pre_restore_` prefix and retention behavior), new compatibility + troubleshooting docs with honest HomeKit/TLS/token limitations, trusted-LAN boundary stated. |
| Screenshots, favicon/app icons, release metadata | Open — none present at `ff525f8`. |
| State coverage matrix (setup/import/reimport/control) | Largely landed per chunks 5/7; interactive accessibility + responsive matrix must be exercised in the rehearsal (cannot be audited statically). |
| Dependency deprecation noise separation | Not assessed — needs a clean-build log during the rehearsal; park there. |

## Test & Style Assessment (committed range)

- **Coverage shape is good**: every new subsystem has a dedicated committed test file (onboarding, area design, external spaces, space mappings/suggestions, inventory, both bridge-onboarding discoveries, connection tests, release/migrations, health + redirect controllers, setup/areas/bridge LiveViews, schema constraint parity). Z2M snapshot is covered via its connection test; `PublishedIdentity` via schema tests. The migration-helper and constraint-parity tests are the standout practice.
- **Prior-audit recurring classes were respected**: no `String.to_atom` on external input anywhere in the new modules; no synchronous network calls in LiveView handlers (everything is `start_async`, mostly with request-id guards — OB-2 notes the one weaker surface); `Z2MConfig`/`CasetaLeap` vocabulary reused rather than re-implemented; boundary modules (`RuntimeIO`, `ExternalSpaces`, `Inventory`) have clear single responsibilities and moduledocs that state their contracts.
- **Residual style debt is small and already ticketed**: mDNS parser duplication (BO-4), dual identity APIs (MG-2), `default_kind` drift (folded into ES-1), unused `schema_version` (AR-2). Nothing else systemic surfaced in the sweep.

## Aggregated Rehearsal Checklist (parked here from all chunks)

Run during the clean-setup rehearsal, not before:

1. Discovery from the primary Docker topology (Hue + HA mDNS; does the `.local` fallback host ever surface, and does manual fallback preserve entered work).
2. Interactive accessibility/responsive matrix: keyboard order, focus-visible, reimport-modal focus trap/restore, touch targets, narrow-width overflow for long identifiers (chunk 7 skipped these statically; `app.css` was also skipped as dirty).
3. Retained-topic hygiene on the production broker after migration (AR-3 cleanup step in the rollout runbook).
4. Clean-build dependency deprecation noise (docs refinement item).
5. Verification-mode rehearsal (scene activation now no-ops with the Control banner — confirm end-to-end on a real isolated instance).

## Explicitly Fine / Leave-Alone

- **Documentation honesty**: every doc claim spot-checked against code was accurate (manual-backup prefix, `pre_restore_` recovery snapshot, retention exemptions, seeds-never-run-by-setup, Z2M retained-snapshot validation, HA-export MQTT reuse). HomeKit is described with its real limitations ("should not be treated as release-quality" for color) — exactly the no-overstating rule.
- **Seeds demotion** (`secrets.json` optional, explicit-failure task, compose overlay recording one-shot bootstrap): implements "useful without private setup knowledge" faithfully.
- **`docs/troubleshooting.md` structure** (start with `/health`, discovery, Z2M validation, reimport safety, HomeKit, what to include in a bug report): matches the diagnosable-failures principle at doc level even though the in-app diagnostics surface remains open.
