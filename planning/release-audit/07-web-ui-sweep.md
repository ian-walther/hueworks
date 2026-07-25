# Chunk 7: Web/UI Sweep

Status: complete at calibrated depth. Line-by-line: `BridgesConfigLive` (+heex via `git show`, dirty), `ControlLive` delta, `AreasLive` delta, `IntegrationsConfigLive` delta, `BridgeLive.html.heex` (committed), `BridgeSetupLive`/`BridgeReimportLive` templates (state-branch survey), scene builder/editor deltas, config callout. **Skipped**: `assets/css/app.css` (+513 — dirty with Sol's work and low audit yield; visual verification belongs to the rehearsal's responsive/accessibility pass), deep reads of `lights_live`/`pico_config` deltas (verified rename-plus-copy only via filtered diffs). The interactive accessibility matrix (focus order, modal trapping, touch targets, breakpoints) cannot be audited statically — it is parked as a rehearsal item in chunk 8.

## Findings

### UI-1: Deleting a bridge skips the HA-export cleanup that deleting its entities performs

- Severity: medium. Type: technical (stale external state).
- Location: `BridgesConfigLive.handle_event("delete_bridge", ...)` → `Bridges.delete_bridge/1` → bare `Repo.delete(bridge)`. Lights/groups/picos vanish via `on_delete: :delete_all` FKs, but the per-entity `HomeAssistantExport.remove_light/remove_group` calls that `delete_entities/1` makes never happen.
- Problem: a user who clicks "Delete bridge" without first clicking "Delete entities" (both buttons are offered side by side) leaves ghost lights/groups retained in the HA MQTT discovery tree — permanently, since the entity ids are gone. This violates the same cleanup symmetry the code carefully maintains everywhere else (`Areas.delete_area`, `delete_entities`).
- Decision: `Bridges.delete_bridge/1` collects the bridge's light/group ids first, deletes the bridge (cascades handle rows), then issues the export removals — i.e., fold `delete_entities`' export-cleanup tail into the delete path. Also replace the two `{:ok, _} =` matches in `BridgesConfigLive` with case + error notice so a failed delete degrades to a message instead of a LiveView crash.
- Guardrail: test asserting export removal is invoked for each entity on bridge deletion; test for the error-notice path.
- Effort: S-M.

## Explicitly Fine / Leave-Alone

- **State-coverage matrix in the import surfaces**: `BridgeSetupLive`/`BridgeReimportLive` templates branch on loading (with `role="status"` + `aria-live="polite"`), error-without-data, review, applied-completion, and empty subsets ("Nothing was removed…", "No new entities…"). The reimport destructive flow uses a real modal (`aria-labelledby`, itemized `destructive_preview` per entity, explicit confirm/cancel events) — this is the reference destructive-confirmation pattern in the codebase.
- **Completion panels drive the journey forward**: post-import summary (lights/groups/areas created/merged/linked wrappers/unassigned) with an "unassigned" callout and a create-first-scene CTA targeting `first_area_id` — directly serves the release-gate "import → first scene" hop.
- **`ControlLive` delta**: mechanical rename plus a proper guided empty state ("Nothing to control yet" → Add Bridge). The pre-existing `"ERROR area: #{Util.format_reason(...)}"` notice copy is clunky but uses `format_reason`, not raw inspect; not worth churn ahead of the BO-5 message-translation work.
- **Simple destructive confirms** (`data-confirm` on delete bridge/entities/area/scene/presence-input): browser-native confirm with copy that names the cascade ("…and its scenes?"). Acceptable tier for these actions; reserve the modal pattern for multi-item destructive reviews like reimport. No change.
- **`AreasLive`**: rename-faithful; deletion confirmations present.
- **`IntegrationsConfigLive`**: HomeKit badge upgraded from boolean paired? to three-state runtime status (`running`/`unavailable`/off) — implements the "distinguish HomeKit runtime configuration, HAP availability, and saved pairing" refinement.
- **Scene builder delta**: plain-language guidance callout (components, group-add-as-shortcut semantics, custom states) plus a power-policy explainer in a `<details>` disclosure — the Scene Onboarding requirement, done without cluttering the default view. Every custom field gained proper `label for=`/`id` associations (accessibility refinement, applied systematically).
- **`BridgeLive.html.heex`**: discovery lists show configured-badges and suppress pair/select for configured devices (see BO-2 refutation in chunk 3); searching/status/error states are distinct; manual paths are framed as recovery ("intended for recovery and segmented networks") with the recommended path stated; HA manual mode carries the long-lived-token framing the refinement doc requires for the pre-OAuth era. The import-order-risk callout renders on native bridge types only when unlinked HA entities exist — right condition, right place.
- **Config surface**: setup callout with dismiss persisted via `Onboarding.dismiss`, verification-mode banner from health (see IV-1 for extending it to Control).
