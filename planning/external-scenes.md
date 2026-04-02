# External Scene Mapping

## Goal
Allow external scene activations, starting with Home Assistant, to activate mapped HueWorks scenes so HueWorks can participate cleanly in an automation-heavy workflow without inventing a parallel control model.

## Current Status
The first Home Assistant scene slice is now implemented end-to-end:

- external scene persistence exists
- external scene mappings exist
- HA scene sync is separate from the main entity import flow
- the Home Assistant bridge card on `/config` has a dedicated `Scene Import` entry point
- there is a dedicated external scene mapping page
- Home Assistant `scene.turn_on` events now activate mapped HueWorks scenes through the normal scene pipeline

At this point, the core architecture is in place and working. The remaining work is mostly polish, observability, and future expansion rather than basic functionality.

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
- HA scene sync should fetch current HA `scene.*` entities directly from Home Assistant at sync time rather than relying on the earlier bridge import snapshot.

## Product Framing
This work should be treated as part of a broader "external inputs behave like HueWorks UI actions" workflow.

The important product idea is:

- a Home Assistant scene activation should be treated like a user intentionally activating a HueWorks scene from the app
- the integration should enter the existing HueWorks scene pipeline rather than creating a parallel control model

This framing should stay aligned with Pico support, since both are external inputs that should end up doing the same kinds of things users can already do directly in HueWorks.

## Implemented In V1
- Added persistence for external scenes and external scene mappings.
- Added a dedicated HA scene import/resync path for `scene.*` entities.
- Added UI for viewing/syncing external scenes and assigning mappings.
- Added runtime event handling for HA `scene.turn_on` activations.
- Activated mapped HueWorks scenes through the existing scene pipeline (`Scenes.activate_scene/2`).
- Added tests for sync, mapping, config UI, and runtime activation flow.

## Out of Scope (V1)
- Bidirectional sync/activation between systems.
- Non-HA sources (future use of same generic model).
- Automatic conflict detection between HA scene effects and HueWorks-managed entities.
- Mapping from arbitrary light service calls (`light.turn_on`) to HueWorks scenes.

## Data Model

### `external_scenes`
- `id`
- `bridge_id`
- `source` (`:ha`, future extensible)
- `source_id` (e.g. HA `scene.some_scene`)
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

Current runtime implementation detail:

- the HA websocket now subscribes to both:
  - `state_changed`
  - `call_service`

The former continues to support HA-driven physical state updates for imported HA lights/groups. The latter now powers external scene activation.

## Import/Resync Flow
1. User explicitly triggers scene import/resync from the Home Assistant bridge card on `/config`.
2. Fetch current scene entities (`scene.*`) directly from HA state.
3. Upsert into `external_scenes`.
4. Keep mappings stable across resyncs by keying on `source + source_id`.
5. Mark missing scenes as disabled/stale rather than hard-delete.

This flow is intentionally separate from the main entity import for lights/groups because:

- it diverges from the shared entity import logic
- it will likely be run more frequently as HA trigger scenes are created and adjusted
- operators may want to refresh scene mappings without rerunning the broader bridge import pipeline

It should still share normalization/context code where appropriate, but operationally it should be presented as its own sync process.

## UI Surface (V1)
- The Home Assistant bridge card in `/config` now has a dedicated `Scene Import` button.
- The external scene config page currently:
  - lists synced external scenes
  - shows mapping status
  - assigns/changes mapped HueWorks scenes
  - enables/disables mappings
  - triggers resync

One small but important workflow note:

- the mapping dropdown lists HueWorks scenes, not Home Assistant scenes
- if it appears empty, that means there are no local HueWorks scene rows available to map in the current environment
- this is separate from whether HA scene sync succeeded

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

## Test Coverage Added
- Context/API coverage for:
  - HA scene sync
  - mapping persistence
  - stale-scene disable behavior on resync
- LiveView coverage for:
  - `Scene Import` entry point
  - external scene config page
  - mapping save flow
- Runtime coverage for:
  - HA websocket auth/subscription sequence
  - `call_service` scene activation -> mapped HueWorks scene activation

## Remaining Follow-Up
- Improve the external-scene config page UI polish and hierarchy.
- Add clearer empty-state messaging when there are no local HueWorks scenes available to map.
- Add better runtime logging/traceability around external scene activation.
- Consider event dedupe using HA context ids if duplicate service events show up in practice.
- Decide whether one external scene should ever map to multiple HueWorks scenes in a future version.
- Consider whether stale scenes should remain disabled indefinitely or gain explicit cleanup/archive UI.

## Open Questions
- Is one-to-one mapping sufficient beyond V1, or do we eventually need one external -> many HueWorks scenes?
- Do we want event dedupe in V1 using HA context IDs?
