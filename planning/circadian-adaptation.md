# Circadian Prerequisites and Adaptive Logic (Planned)

## Goal
Implement adaptive circadian scene behavior with near-parity to Home Assistant Adaptive Lighting calculation settings, while preserving HueWorks control-pipeline consistency and scene semantics.

## Locked Decisions
- Circadian adapts both `brightness` and `kelvin`.
- `active_scenes.brightness_override` interrupts brightness adaptation only; temperature adaptation continues.
- Current room-level `brightness_override` is sufficient for v1 (future per-light refinement is allowed).
- Circadian config is scene-level only, stored on `light_states.config` for `type: :circadian`.
- Poll interval remains the existing `CircadianPoller` interval.
- On manual temperature/color changes, active scene is disabled.
- On manual brightness/power changes, scene remains active and is treated like brightness override behavior.
- Manual `power: off` remains off until manual on.
- Manual `power: on` should immediately apply current circadian values to only the toggled entity (no wait for next poll).
- Computed targets must clamp to target capability/range.
- No smoothing required initially.
- On apply errors, continue processing and log failures.
- Global solar inputs should be `lat/lon/timezone`, initially global (not per room).
- Config key names should match Home Assistant Adaptive Lighting names where applicable.
- No migration/backfill constraints for old circadian data.

## Scope
- Add a dedicated circadian calculation module reusable by poller and manual-on handling.
- Implement `LightState.type == :circadian` apply path in scene execution.
- Add circadian settings model/validation in `light_states.config`.
- Add circadian editing UI in scene builder (distinct from manual/off UI).
- Update planner behavior to support clamp-aware grouping partitions.
- Route manual UI controls through desired-state pipeline (not direct control mutation path).
- Add deep tests for circadian calculations and regression tests for scene/manual behavior.

## Out of Scope
- Per-room/per-scene geolocation and timezone overrides.
- Smoothing/fade interpolation engine.
- Small-delta skip optimization.
- Legacy-data migration tooling.

## Current-State Gaps (Audit)
- Poller exists and reapplies active scenes:
  - `lib/hueworks/control/circadian_poller.ex`
- Active scene tracking and brightness override exist:
  - `lib/hueworks/active_scenes.ex`
  - `lib/hueworks/schemas/active_scene.ex`
- `:circadian` state type exists in schema:
  - `lib/hueworks/schemas/light_state.ex`
- Missing:
  - Circadian compute engine.
  - Circadian branch in scene apply (`Scenes.desired_from_light_state/2` currently handles only `:off` and `:manual`).
  - Circadian UI in scene builder.
  - Clamp-aware group partition planning.
  - Desired-state-only pathway for manual UI controls.

## Design Overview

### 1) Circadian Calculation Engine
Create a dedicated module (example: `Hueworks.Circadian`) that:
- Accepts:
  - current datetime
  - global solar config (`lat/lon/timezone`)
  - circadian config map (HA-compatible keys)
  - optional entity capability/range context
- Produces:
  - normalized target `%{brightness: integer | nil, kelvin: integer | nil}`
- Guarantees:
  - deterministic output for a given timestamp/config
  - clamped outputs where entity range exists
  - clear validation failures for invalid config

Reusability targets:
- Poller tick (`CircadianPoller` -> `Scenes.apply_scene`)
- Manual power-on immediate adapt path

### 2) Scene Apply Behavior for `:circadian`
Extend `Scenes.apply_scene/2` to support circadian light states:
- Compute target brightness/kelvin from circadian module.
- Respect room-level brightness override:
  - suppress brightness writes when override is active.
  - keep temperature writes active.
- Keep lights with no temp support on brightness-only circadian behavior.
- Clamp values to target entity range before planning.

### 3) Planner Partitioning for Clamp-Aware Grouping
Current planner groups by exact desired map. To support mixed kelvin support/range:
- First normalize desired per light (including clamp/capability omission).
- Then group by normalized desired and bridge.
- Greedy group selection runs per partition, so:
  - lights supporting exact target can group together.
  - clamped/unsupported lights are partitioned separately.

This avoids issuing one shared group temp where members require different effective temps.

### 4) Manual Control Pipeline Unification
Current `/lights` path sends direct device commands and mutates state directly.
Target behavior:
- manual UI actions become desired-state mutations + planner/executor dispatch.
- physical state updates come from normal event/state reconciliation, not direct side-channel mutation.

Required semantics:
- brightness/manual power change does not clear active scene.
- manual temperature/color change clears active scene.
- manual power-on while active circadian scene triggers immediate circadian apply for only that toggled entity.
- manual power-off remains off until manual-on.

## Config Model (Circadian `light_state.config`)
Initial requirement: mirror HA Adaptive Lighting key names for calculation-related settings.

Implementation steps:
- Define allowed key list and types.
- Validate and normalize values at create/update time.
- Persist raw keys in `config` map; store normalized numeric forms used by calculator.

## Global Solar Config
Introduce a global settings source (DB singleton, with app config fallback during transition):
- `latitude`
- `longitude`
- `timezone`

Potential shape:
- new singleton table (example `app_settings`) with one row.
- helper context for load/update/cache.

## Files Likely to Change
- `lib/hueworks/scenes.ex`
- `lib/hueworks/control/circadian_poller.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_web/live/scene_builder_component.ex`
- `lib/hueworks_web/live/rooms_live.ex`
- `lib/hueworks_web/live/lights_live.ex`
- `lib/hueworks/schemas/light_state.ex`
- `lib/hueworks/schemas/active_scene.ex` (if override semantics need extension)
- `priv/repo/migrations/*` (global settings singleton)
- new circadian module(s), e.g.:
  - `lib/hueworks/circadian.ex`
  - `lib/hueworks/circadian/config.ex`

## Testing Plan
- Unit tests:
  - circadian calculations across time boundaries/day phases
  - HA-compatible config key parsing/validation
  - clamp behavior for supported, unsupported, and mixed ranges
- Scene integration tests:
  - active circadian scene reapply on poll
  - brightness override suppresses brightness only
  - temp manual change disables active scene
  - brightness/power manual change preserves active scene
  - manual power-off remains off until manual-on
  - manual power-on applies current circadian targets immediately
- Planner tests:
  - partitioned grouping for exact-target vs clamped-target subsets
  - no mixed-kelvin group action when outcomes differ

## Phased Execution Plan
1. Add circadian calculator + config schema validation + tests.
2. Add circadian apply path in scenes and poller integration.
3. Add clamp-aware planner partitioning.
4. Add scene builder circadian UI.
5. Refactor `/lights` manual control path into desired-state pipeline.
6. Add DB singleton global solar config.
7. Expand integration/regression coverage and observability.

## Observability
- Structured log events for:
  - poll tick start/end
  - active scene count
  - per-scene apply success/failure
  - circadian compute validation errors
- Counter hooks (or telemetry events) for:
  - apply attempts
  - apply failures
  - manual override transitions

## Open Questions (Needs Follow-up)
- Global settings lifecycle:
  - Is app-config fallback acceptable only for development, or required in production too?
- HA key parity:
  - Confirm exact list of calculation keys to include in v1 (all calculation-related keys, excluding HA automation/entity wiring keys).
