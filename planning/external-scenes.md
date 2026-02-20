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
- We accept operator discipline as a constraint:
  - users should avoid HA scenes that also directly mutate HueWorks-managed lights in conflicting ways.

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
1. During HA import/sync, fetch scene entities (`scene.*`) from entity registry/state.
2. Upsert into `external_scenes`.
3. Keep mappings stable across resyncs by keying on `source + source_id`.
4. Optionally mark missing scenes as disabled/stale rather than hard-delete.

## UI Surface (V1)
- Add External Scenes section (likely under `/config`):
  - list external scenes by source
  - show mapping status
  - assign/change mapped HueWorks scene
  - disable/enable mapping
  - trigger resync

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
- Integration:
  - HA `call_service` event -> mapped HueWorks scene activation
  - unmapped scene -> no-op
  - disabled mapping -> no-op
  - duplicate event/context handling (if dedupe added in V1)
- UI:
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
