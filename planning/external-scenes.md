# External Scene Mapping

## Goal
Allow external scene activations, starting with Home Assistant, to activate mapped HueWorks scenes so HueWorks can participate cleanly in automation-heavy workflows without inventing a parallel control model.

## Architectural Constraint
This work should stay aligned with `/Users/ianwalther/code/hueworks/planning/architecture-reset.md`:

- external triggers decide upstream intent only
- the integration should enter the existing HueWorks scene pipeline
- external inputs should not bypass desired-state commits or create a second downstream dispatch path

## Locked Decisions
- Use a generic external scene model (`external_scenes`) with `source` (`:ha` first).
- V1 direction is one-way:
  - external scene activation triggers HueWorks scene activation
  - HueWorks scene activation does not trigger external scenes
- V1 trigger source is Home Assistant scene service calls (`scene.turn_on`).
- `scene.apply` is out of scope for V1.
- Mapping is explicit and user-managed; no automatic matching in V1.
- Home Assistant scene import/resync should be a separate operator action from the main entity import.
- The config entry point for this work should live on the Home Assistant bridge card in `/config` as a dedicated scene import/sync action.
- Users should avoid HA scenes that also directly mutate HueWorks-managed lights in conflicting ways.
- HA scene sync should fetch current HA `scene.*` entities directly from Home Assistant at sync time rather than relying on an earlier bridge import snapshot.

## Product Framing
This work should be treated as part of the broader "external inputs behave like HueWorks UI actions" workflow.

The important product idea is:

- a Home Assistant scene activation should be treated like a user intentionally activating a HueWorks scene from the app
- the integration should enter the existing HueWorks scene pipeline rather than creating a parallel control model

This framing should remain aligned with Pico support, since both are external inputs that should end up doing the same kinds of things users can already do directly in HueWorks.

## Data Model

### `external_scenes`
- `id`
- `bridge_id`
- `source` (`:ha`, future extensible)
- `source_id` (for example HA `scene.some_scene`)
- `name`
- `display_name` (optional)
- `enabled`
- `metadata` (raw source details / capability hints)
- timestamps
- unique index on `[:bridge_id, :source, :source_id]`

### `external_scene_mappings`
- `id`
- `external_scene_id` FK
- `scene_id` FK (`scenes.id`)
- `enabled` boolean (default `true`)
- `metadata`
- timestamps
- unique index on `[:external_scene_id]` for simple 1:1 in V1

## Runtime Flow
1. Receive Home Assistant service-call event.
2. Filter to:
   - `domain == "scene"`
   - `service == "turn_on"`
3. Extract one or more target scene entity ids.
4. Resolve `external_scenes` by `source: :ha` + `source_id`.
5. Resolve enabled mapping.
6. Activate the mapped HueWorks scene through the normal scene pathway.
7. Record enough logs/telemetry for traceability.

## Import / Resync Flow
1. User explicitly triggers scene import/resync from the Home Assistant bridge card on `/config`.
2. Fetch current `scene.*` entities directly from Home Assistant.
3. Upsert them into `external_scenes`.
4. Keep mappings stable across resyncs by keying on `source + source_id`.
5. Mark missing scenes as disabled/stale rather than hard-delete.

This flow should remain separate from the main entity import for lights/groups because:

- it diverges from the shared entity import logic
- it will likely be run more frequently as HA trigger scenes are created and adjusted
- operators may want to refresh scene mappings without rerunning the broader bridge import pipeline

## UI Direction
- The Home Assistant bridge card on `/config` should continue to expose a dedicated `Scene Import` entry point.
- The mapping page should:
  - list synced external scenes
  - show mapping status
  - assign/change mapped HueWorks scenes
  - enable/disable mappings
  - trigger resync
- Empty states should clearly distinguish:
  - no external scenes synced
  - no local HueWorks scenes available to map

## Safety / Conflict Model
- Do not block mappings when users choose overlapping HA/HueWorks behavior.
- Keep the operator expectation explicit:
  - HA scenes used as triggers should primarily express intent, not also directly fight HueWorks-managed entities.
- Surface that expectation clearly in the mapping UI.

## Remaining Follow-Up
- Improve the external-scene config page hierarchy and polish.
- Add clearer empty-state messaging when there are no local HueWorks scenes available to map.
- Add better runtime logging/traceability around external scene activation.
- Consider event dedupe using HA context ids if duplicate service events show up in practice.
- Decide whether one external scene should ever map to multiple HueWorks scenes in a future version.
- Decide whether stale scenes should remain disabled indefinitely or gain explicit cleanup/archive UI.

## Open Questions
- Is one-to-one mapping sufficient beyond V1, or do we eventually need one external -> many HueWorks scenes?
- Do we want event dedupe using HA context ids?
