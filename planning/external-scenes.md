# External Scene Mapping (Planned)

## Goal
Allow external scene activations (starting with Home Assistant) to activate mapped HueWorks scenes, so HueWorks can be used in production via existing HA automations/buttons without waiting on full native trigger ingestion.

## Locked Decisions
- Use a generic external scene model (`external_scenes`) with `source` (`:ha` first).
- V1 direction is one-way:
  - external scene activation triggers HueWorks scene activation.
  - HueWorks scene activation does not trigger external scenes.
- V1 trigger source is Home Assistant scene service calls (`scene.turn_on`).
- `scene.apply` is out of scope for V1.
- Mapping is explicit and user-managed; no automatic matching in V1.
- Home Assistant scene import/resync should be a separate operator action from the main entity import.
- The config entry point for this work should live on the Home Assistant bridge card in `/config` as a dedicated scene import/sync action, not be buried inside the normal light/group import path.
- We accept operator discipline as a constraint:
  - users should avoid HA scenes that also directly mutate HueWorks-managed lights in conflicting ways.

## Product Framing
This work should be treated as part of a broader "external inputs behave like HueWorks UI actions" workflow.

The important product idea is:

- a Home Assistant scene activation should be treated like a user intentionally activating a HueWorks scene from the app
- the integration should enter the existing HueWorks scene pipeline rather than creating a parallel control model

This framing should stay aligned with Pico support, since both are external inputs that should end up doing the same kinds of things users can already do directly in HueWorks.

## Scope
- Add persistence for external scenes and mappings to HueWorks scenes.
- Add HA scene import/resync path for `scene.*` entities.
- Add UI for viewing/syncing external scenes and assigning mappings.
- Add runtime event handling for HA scene activations.
- Activate mapped HueWorks scenes through existing scene pipeline (`Scenes.activate_scene/1`).
- Add tests for sync, mapping, and activation flow.

## Out of Scope (V1)
- Bidirectional sync/activation between systems.
- Non-HA sources (future use of same generic model).
- Automatic conflict detection between HA scene effects and HueWorks-managed entities.
- Mapping from arbitrary light service calls (`light.turn_on`) to HueWorks scenes.

## Proposed Data Model

### `external_scenes`
- `id`
- `source` (`:ha`, future extensible)
- `source_id` (e.g. HA `scene.some_scene`)
- `name`
- `display_name` (optional)
- `metadata` (raw source details / capability hints)
- timestamps
- unique index on `[:source, :source_id]`

### `external_scene_mappings`
- `id`
- `external_scene_id` FK
- `scene_id` FK (`scenes.id`)
- `enabled` boolean (default `true`)
- `mode` (optional future field for behavior variants)
- timestamps
- unique index on `[:external_scene_id]` for simple 1:1 in V1

## Runtime Flow (HA V1)
1. HA websocket subscription receives `call_service` event.
2. Filter to:
   - `domain == "scene"`
   - `service == "turn_on"`
3. Extract target entity IDs (single or list).
4. Resolve `external_scenes` by `source: :ha` + `source_id`.
5. Resolve enabled mapping.
6. Call `Scenes.activate_scene(mapped_scene_id)`.
7. Record logs/telemetry for traceability.

## Import/Resync Flow
1. User explicitly triggers scene import/resync from the Home Assistant bridge card on `/config`.
2. Fetch scene entities (`scene.*`) from HA entity registry/state.
3. Upsert into `external_scenes`.
4. Keep mappings stable across resyncs by keying on `source + source_id`.
5. Optionally mark missing scenes as disabled/stale rather than hard-delete.

This flow is intentionally separate from the main entity import for lights/groups because:

- it diverges from the shared entity import logic
- it will likely be run more frequently as HA trigger scenes are created and adjusted
- operators may want to refresh scene mappings without rerunning the broader bridge import pipeline

It should still share normalization/context code where appropriate, but operationally it should be presented as its own sync process.

## UI Surface (V1)
- Add a dedicated action on the Home Assistant bridge card in `/config` for scene import/sync.
- Add an External Scenes section under `/config` that:
  - lists external scenes by source
  - shows mapping status
  - assigns/changes mapped HueWorks scenes
  - disables/enables mappings
  - triggers resync

Recommended operator flow:

1. Run the normal HA entity import for lights/groups when bridge entities change.
2. Run the dedicated HA scene import when HA trigger scenes are added or edited.
3. Configure or adjust mappings in the External Scenes section.
4. Use HA scenes as external triggers for the same HueWorks scene activations users could perform from the UI.

## Safety / Conflict Model
- We will not block mapping if a user chooses overlapping HA/HueWorks behavior.
- Document operator expectation:
  - keep HA scenes used as triggers focused on intent, not direct control of HueWorks-managed entities.
- Add visible warning text in mapping UI for this constraint.

## Testing Plan
- Unit:
  - scene entity normalization/import for HA `scene.*`
  - mapping resolution rules
  - idempotent resync behavior
  - separation between entity import and scene import flows
- Integration:
  - HA `call_service` event -> mapped HueWorks scene activation
  - unmapped scene -> no-op
  - disabled mapping -> no-op
  - duplicate event/context handling (if dedupe added in V1)
- UI:
  - Home Assistant bridge card scene-import entry point
  - mapping create/update/remove
  - resync flow and status

## Phased Execution Plan
1. Schema + context APIs (`external_scenes`, `external_scene_mappings`).
2. HA import/resync support for scene entities.
3. Mapping UI and management actions.
4. HA event handler for `scene.turn_on` -> `Scenes.activate_scene/1`.
5. Regression/observability pass and docs.

## Open Questions
- Should stale external scenes be soft-disabled or deleted on resync?
- Is one-to-one mapping sufficient for V1, or do we need one external -> many HueWorks scenes?
- Do we want event dedupe in V1 using HA context IDs?
