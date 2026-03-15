# Circadian Validation and Follow-Up

## Goal
Take the current circadian implementation from "functionally complete" to "trusted in daily use" without reopening the settled v1 data shape.

## Current Baseline
- Circadian scenes use HA-compatible calculation keys on `light_states.config`.
- Circadian adapts both brightness and kelvin.
- `active_scenes.brightness_override` suppresses brightness writes only; kelvin adaptation continues.
- Manual `power: off` stays off until manual `power: on`.
- Manual `power: on` immediately reapplies the current circadian target for the toggled entity.
- Global solar inputs come from `AppSettings` as `latitude` / `longitude` / `timezone`.
- Poll-based reapply and targeted debug logging already exist.

## Remaining Scope
- Replace the temporary room occupancy UI toggle with HA-driven presence input.
- Validate circadian behavior in real rooms with mixed bulb ranges and overlapping Hue groups.
- Decide whether the product should keep per-light-exact circadian outputs, or add a room-coherent circadian mode for synchronized fades.
- Add richer observability only if the current log-based debugging stops being sufficient.

## Locked Decisions
- Circadian config remains scene-level on `light_states.config` for `type: :circadian`.
- Global solar inputs stay global for now; no per-room/per-scene geolocation overrides in v1.
- No smoothing or interpolation engine is required for v1.
- No migration/backfill constraints need to be considered yet.
- Config key names should continue to track Home Assistant Adaptive Lighting names where applicable.

## Known Tradeoffs to Validate

### 1) Per-Light Accuracy vs Room Coherence
Current planner behavior groups by exact desired output after per-light clamping.

Implication:
- rooms with mixed effective kelvin ranges can split into multiple planner partitions
- multiple partitions can require multiple group commands
- multiple group commands can produce visibly staggered fades even when the planner is behaving correctly

Open decision:
- keep exact per-light circadian correctness as the default
- or add a room-coherent mode that intentionally trades some per-light precision for synchronized transitions

### 2) Group Layout Expectations
Circadian behavior can look substantially better when Hue groups line up with the partitions created by capability/range differences.

Implication:
- overlapping Hue groups may be sufficient to optimize away most visible stagger
- planner improvements may not be necessary if group layout is intentional

Follow-up:
- document any practical grouping guidance that emerges from live testing

### 3) Occupancy Input
Current occupancy behavior is intentionally temporary and driven by a room-page toggle for testing.

Follow-up:
- replace that toggle with HA-driven presence state
- keep the same `force_on` / `force_off` / `follow_occupancy` scene semantics

## Out of Scope
- Sleep-mode-specific circadian options
- RGB/adaptive color-mode output
- Per-room/per-scene timezone or geolocation overrides
- Small-delta skip heuristics
- Migration/backfill tooling

## Integration Targets
- `lib/hueworks/circadian.ex`
- `lib/hueworks/circadian/config.ex`
- `lib/hueworks/scenes.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks/app_settings.ex`
- `lib/hueworks_app/control/circadian_poller.ex`
- `lib/hueworks_web/live/rooms_live.ex`
- `lib/hueworks_web/live/scene_editor_live.ex`
- `lib/hueworks_web/live/scene_builder_component.ex`

## Testing Follow-Up
- Real-world validation of:
  - scene activation from manual -> circadian and circadian -> manual
  - manual off/on semantics while a circadian scene is active
  - circadian behavior in rooms with mixed temp ranges
  - planner/group behavior in rooms with intentionally overlapping Hue groups
- Add more automated coverage only when live testing reveals a repeatable regression that is not already represented in the existing math, scene, or LiveView tests.

## Observability Follow-Up
- Keep `ADVANCED_DEBUG_LOGGING=true` as the opt-in path for planner/control trace debugging.
- Add telemetry/counters later if:
  - log-based auditing becomes too noisy
  - long-running deployment visibility becomes more important than one-off debugging

## Open Questions
- Is the current log-only observability enough for production-ish use, or do circadian apply attempts/failures need first-class telemetry?
- Does the product actually need a room-coherent circadian mode, or is careful Hue grouping the better long-term answer?
