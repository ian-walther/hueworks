# Circadian Validation and Follow-Up

## Goal
Take the current circadian implementation from "works in real rooms" to "understood, trusted, and easy to evolve" without reopening the settled v1 data shape.

## Current Baseline
- Circadian scenes are represented by `light_states.type = :circadian` with scene-level config stored on `light_states.config`.
- Circadian adapts both brightness and kelvin.
- Active scenes are tracked per room in `active_scenes`.
- Active scenes have a short pending/grace window after apply or reapply to avoid clearing on immediate device feedback.
- `active_scenes.brightness_override` suppresses circadian brightness writes while continuing kelvin adaptation.
- While brightness override is active, manual power latches are preserved during circadian reapply:
  - manual `power: off` stays off
  - manual `power: on` stays on, including for lights whose scene component default is off
- Manual power-only changes do not deactivate the active scene.
- Manual power-on from the lights page can reapply the active scene for the targeted light in a single combined action instead of sending a blind `power: on` first and fixing state afterward.
- Scene-clear comparison now uses effective per-light desired state after clamping, not only the raw scene target.
- Scene-clear and reconcile logic tolerate small brightness drift.
- Reload/bootstrap refreshes are treated as resync activity and should not clear active scenes.
- Global solar inputs come from `AppSettings` as `latitude`, `longitude`, and `timezone`.
- Poll-based reapply exists and runs through `CircadianPoller`.
- Active scene edits and active light-state edits reapply immediately.
- Debug logging for planner, apply, poller, and scene-clear behavior already exists and has been useful in production-ish debugging.

## Remaining Scope
- Replace the current room occupancy UI toggle with HA-driven presence input.
- Validate circadian behavior in real rooms with mixed bulb ranges, overlapping Hue groups, and Z2M-backed devices.
- Decide whether the product should stay per-light exact by default or add a room-coherent circadian mode for more synchronized fades.
- Decide how much of the current debug logging should remain long-term versus being replaced with narrower telemetry or counters.

## Locked Decisions
- Circadian config remains scene-level on `light_states.config` for `type: :circadian`.
- Global solar inputs stay global for now; no per-room or per-scene geolocation overrides in v1.
- No smoothing or interpolation engine is required for v1.
- Config key names should continue to track Home Assistant Adaptive Lighting names where practical.
- Scene component power policy continues to use the existing internal enum values:
  - `:force_on`
  - `:force_off`
  - `:follow_occupancy`
- User-facing labels for those policies are:
  - `Default On`
  - `Default Off`
  - `Follow Occupancy`

## Known Tradeoffs to Validate

### 1) Per-Light Accuracy vs Room Coherence
Planner behavior still partitions by effective desired output after per-light clamping.

Implication:
- rooms with mixed effective kelvin ranges can split into multiple planner partitions
- multiple partitions can require multiple group commands
- multiple group commands can produce visibly staggered fades even when the planner is behaving correctly

Open decision:
- keep exact per-light circadian correctness as the default
- or add a room-coherent mode that intentionally trades some per-light precision for synchronized transitions

### 2) Group Layout Expectations
Circadian behavior can look substantially better when Hue groups line up with the partitions created by capability and range differences.

Implication:
- overlapping Hue groups may be sufficient to optimize away most visible stagger
- planner changes may not be necessary if group layout is intentional

Follow-up:
- document any practical grouping guidance that emerges from live testing

### 3) Occupancy Input
Occupancy behavior is still room-level and currently comes from the room-page UI toggle.

Follow-up:
- replace that toggle with HA-driven presence state
- keep the same scene component power-policy semantics once occupancy is sourced externally

### 4) Active Scene Persistence vs User Intent
The current behavior now makes a stronger distinction between:
- real external state divergence
- manual power toggles
- resync/bootstrap noise

This is better than the original v1 behavior, but it is still a product surface that needs validation in daily use.

Follow-up:
- confirm that the current auto-clear thresholds feel right in practice
- confirm that preserving manual power latches during circadian reapply matches user expectations over longer periods

## Out of Scope
- Sleep-mode-specific circadian options
- RGB or adaptive color-mode output
- Per-room or per-scene timezone/geolocation overrides
- A smoothing or interpolation engine
- Migration or backfill tooling

## Integration Targets
- `lib/hueworks/circadian.ex`
- `lib/hueworks/circadian/config.ex`
- `lib/hueworks/scenes.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks/rooms.ex`
- `lib/hueworks/app_settings.ex`
- `lib/hueworks_app/control/circadian_poller.ex`
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks_app/control/desired_state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_web/live/rooms_live.ex`
- `lib/hueworks_web/live/lights_live.ex`
- `lib/hueworks_web/live/scene_editor_live.ex`
- `lib/hueworks_web/live/scene_builder_component.ex`

## Testing Follow-Up
- Continue real-world validation of:
  - scene activation from manual -> circadian and circadian -> manual
  - manual off/on semantics while a circadian scene is active
  - default-off component behavior when manually toggled on
  - active-scene survival during refresh/bootstrap activity
  - circadian behavior in rooms with mixed temp ranges
  - planner/group behavior in rooms with intentionally overlapping Hue groups
- Add more automated coverage when live testing reveals a repeatable regression that is not already represented in the existing math, planner, scene, or LiveView tests.

## Observability Follow-Up
- Keep `ADVANCED_DEBUG_LOGGING=true` as the opt-in path for planner/control trace debugging.
- Current logging is already sufficient for one-off debugging of:
  - planner partitioning
  - active-scene reapply
  - circadian poller apply attempts
  - scene-clear candidates and clears
- Add telemetry or counters later if:
  - log-based auditing becomes too noisy
  - long-running deployment visibility becomes more important than per-incident diagnosis

## Open Questions
- Is the current log-based observability enough for ongoing production-ish use, or do circadian apply attempts and scene clears need first-class telemetry?
- Does the product actually need a room-coherent circadian mode, or is careful Hue grouping the better long-term answer?
- Once HA-driven occupancy exists, do `Default Off` and `Follow Occupancy` still feel like the right mental model for scene component power policy?
