# Chunk 8: Cross-Cutting — Docs, Tests, Style, Gap Analysis

Status: complete. Scope: README/`docs/compatibility.md`/`docs/troubleshooting.md` (at HEAD `ff525f8` via `git show`; all three dirty with later work), committed test-suite shape for the new subsystems, residual style sweep, and the release-blocker gap analysis against `planning/pre-release_refinement.md`. This closes the audit of the original commit range `09fa9e3..ff525f8`.

## Findings

### RC-1: Import-plane tests systematically use atom-keyed fixtures, masking blob-shape bugs

- Severity: medium. Type: test strategy.
- Location: fixtures/builders across `test/hueworks/import_*`, `space_*`, setup/reimport LiveView tests.
- Problem: production import data crosses a JSON boundary twice (`bridge_imports.normalized_blob`, `NormalizeJson.to_map`) and arrives **string-keyed**; tests feed atom-keyed maps. This is exactly how ES-1 (the one high-severity bug in the whole range — floor-mapping apply crash) shipped with green tests. The dual-key `Normalize.fetch` convention makes both shapes *usually* work, which is precisely why only a systematic check catches the asymmetric cases (`Map.put_new` with atom keys, atom-first fetch precedence).
- Decision: add one fixture helper (`blob_shaped/1` ≈ `Jason.decode!(Jason.encode!(value))`) and run the import-plane suites that consume persisted blobs (space mappings, suggestions, review/reimport plan+apply, inventory, area design) against both shapes — either via a shared test macro or by converting the canonical fixtures to string keys and keeping a few atom-shape smoke cases. Implement together with ES-1's guardrail tests.
- Effort: M (mostly mechanical).

## Release-Blocker Gap Analysis (committed range vs `pre-release_refinement.md`)

Status of each blocker/refinement as of `ff525f8`. "Open" = not a defect in this range; listed so the release checklist stays honest. Items marked ⏳ have uncommitted work in the working tree that the phase-2 audit covers.

| Requirement | Status at `ff525f8` |
| --- | --- |
| HA browser authorization replaces long-lived token | Open ⏳ — docs honestly state the token limitation (README + compatibility). |
| Guided Caseta pairing | Open ⏳ — compatibility doc states the certificate-upload limitation plainly. |
| Guided Z2M assistance (`_mqtt._tcp` discovery, base-topic candidates, multi-instance) | Open — HA-export-reuse + retained-snapshot validation landed; discovery honestly documented as "not guaranteed". |
| Discovery in production Docker topology | Open — rehearsal item; chunk 3 noted the `.local` fallback host risk to verify there. |
| Import ordering & duplicate transparency | **Landed** — inventory-first journey, `ha_import_order_risk` warning, wrapper-linking disclosure in completion summary. |
| ExternalSpaceMappings guide new placement only | Landed with one high-severity defect (ES-1) and its test-strategy root cause (RC-1). |
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
5. Verification-mode rehearsal after IV-1 lands (scene activation must no-op cleanly, not crash).

## Explicitly Fine / Leave-Alone

- **Documentation honesty**: every doc claim spot-checked against code was accurate (manual-backup prefix, `pre_restore_` recovery snapshot, retention exemptions, seeds-never-run-by-setup, Z2M retained-snapshot validation, HA-export MQTT reuse). HomeKit is described with its real limitations ("should not be treated as release-quality" for color) — exactly the no-overstating rule.
- **Seeds demotion** (`secrets.json` optional, explicit-failure task, compose overlay recording one-shot bootstrap): implements "useful without private setup knowledge" faithfully.
- **`docs/troubleshooting.md` structure** (start with `/health`, discovery, Z2M validation, reimport safety, HomeKit, what to include in a bug report): matches the diagnosable-failures principle at doc level even though the in-app diagnostics surface remains open.
