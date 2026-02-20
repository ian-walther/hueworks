# Circadian Prerequisites and Adaptive Logic

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
- Finalize manual power semantics while a scene is active:
  - manual `power: off` stays off until manual-on.
  - manual `power: on` applies current circadian target immediately.
- Wire circadian calculations to global solar config loaded from `AppSettings`.
- Add deep tests for circadian calculations and targeted scene/manual regressions.
- Add basic observability for circadian ticks and apply outcomes.

## Out of Scope
- Per-room/per-scene geolocation and timezone overrides.
- Smoothing/fade interpolation engine.
- Small-delta skip optimization.
- Legacy-data migration tooling.

## Integration Targets
- Circadian compute engine integrated with:
  - `lib/hueworks/control/circadian_poller.ex`
  - `lib/hueworks/scenes.ex`
- Active-scene semantics integrated with:
  - `lib/hueworks/active_scenes.ex`
  - `lib/hueworks/schemas/active_scene.ex`
- Circadian configuration path integrated with:
  - `lib/hueworks/circadian/config.ex`
  - `lib/hueworks/schemas/light_state.ex`
  - `lib/hueworks_web/live/scene_builder_component.ex`
- Global solar config input integrated with:
  - `lib/hueworks/app_settings.ex`
  - `lib/hueworks_web/live/config/config_live.ex`

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

### 3) Manual Power Semantics
- manual power-on while active circadian scene triggers immediate circadian apply for only that toggled entity.
- manual power-off remains off until manual-on.

## Config Model (Circadian `light_state.config`)
Initial requirement: mirror HA Adaptive Lighting key names for calculation-related settings.

Confirmed v1 circadian keys:
- `min_brightness`
- `max_brightness`
- `min_color_temp`
- `max_color_temp`
- `sunrise_time`
- `min_sunrise_time`
- `max_sunrise_time`
- `sunrise_offset`
- `sunset_time`
- `min_sunset_time`
- `max_sunset_time`
- `sunset_offset`
- `brightness_mode`
- `brightness_mode_time_dark`
- `brightness_mode_time_light`

Explicitly excluded in v1:
- all `sleep_*` options
- `prefer_rgb_color` and other RGB/color-mode options

Implementation notes:
- Keep config key parity with HA Adaptive Lighting settings listed above.
- Use normalized config values in circadian calculation.

## Global Solar Config
Global settings source:
- `latitude`
- `longitude`
- `timezone`

Implementation notes:
- Use this source as the runtime input for circadian calculation/apply.

## Files Likely to Change
- `lib/hueworks/scenes.ex`
- `lib/hueworks/control/circadian_poller.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks/circadian/config.ex`
- `lib/hueworks/app_settings.ex`
- `lib/hueworks/schemas/active_scene.ex` (if override semantics need extension)
- new circadian compute module(s), e.g.:
  - `lib/hueworks/circadian.ex`

## Testing Plan
- Unit tests:
  - circadian calculations across time boundaries/day phases
  - calculator behavior with app settings (`lat/lon/timezone`) inputs
- Scene integration tests:
  - active circadian scene reapply on poll
  - manual power-off remains off until manual-on
  - manual power-on applies current circadian targets immediately

## Execution Plan
1. Add circadian calculation engine and unit tests.
2. Add `:circadian` apply path in `Scenes.apply_scene/2`.
3. Wire calculator inputs from `AppSettings` global solar config.
4. Finalize active-scene manual power semantics for off-latch and manual-on immediate apply.
5. Add integration regressions and observability.

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
