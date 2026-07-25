# Chunk 7: Web/UI Sweep

Status: complete; implementation reconciled 2026-07-26. Scope: config LiveViews, `ControlLive`/`AreasLive`/`IntegrationsConfigLive` deltas, bridge add/import/reimport templates, scene builder/editor deltas. `assets/css/app.css` and the interactive accessibility matrix remain rehearsal items (chunk 8 checklist). No open findings.

## Explicitly Fine / Leave-Alone

- **Bridge deletion cleans up the HA export** (formerly UI-1, implemented): `Bridges.delete_bridge/1` captures light/group ids before the delete and issues `HomeAssistantExport.remove_light/remove_group` only after a successful cascade; a failed delete returns the error unemitted. Both `BridgesConfigLive` delete events now degrade to error notices instead of crashing on failed matches, with a cast-receiver test proving each export removal is requested.
- **State-coverage matrix in the import surfaces**: `BridgeSetupLive`/`BridgeReimportLive` templates branch on loading (with `role="status"` + `aria-live="polite"`), error-without-data, review, applied-completion, and empty subsets. The reimport destructive flow uses a real modal (`aria-labelledby`, itemized `destructive_preview` per entity, explicit confirm/cancel) — the reference destructive-confirmation pattern in the codebase.
- **Completion panels drive the journey forward**: post-import summary with an "unassigned" callout and a create-first-scene CTA targeting `first_area_id` — directly serves the release-gate "import → first scene" hop.
- **`ControlLive`**: rename-faithful plus a proper guided empty state ("Nothing to control yet" → Add Bridge). The pre-existing `"ERROR area:"` notice copy uses `format_reason`, not raw inspect; not worth churn now that the shared `ConnectionTest.Message`/`ApplyError` vocabulary exists for future surfaces.
- **Simple destructive confirms** (`data-confirm` on delete bridge/entities/area/scene/presence-input): browser-native confirm with copy that names the cascade. Acceptable tier; reserve the modal pattern for multi-item destructive reviews like reimport.
- **`IntegrationsConfigLive`**: three-state HomeKit runtime status (`running`/`unavailable`/off) — implements "distinguish HomeKit runtime configuration, HAP availability, and saved pairing".
- **Scene builder**: plain-language guidance callout plus power-policy `<details>` explainer (Scene Onboarding requirement), and systematic `label for=`/`id` associations on custom fields.
- **`BridgeLive.html.heex`**: configured-badges suppress pair/select for known bridges (see BO-2 refutation, chunk 3); searching/status/error states distinct; manual paths framed as recovery with the recommended path stated; import-order-risk callout on native types only when unlinked HA entities exist.
- **Config surface**: setup callout with persisted dismiss; verification-mode banner from health (now also on Control, per IV-1).
