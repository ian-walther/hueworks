# Global Solar Bounds and Per-Light-State Overrides

## Goal

Introduce house-wide sunrise and sunset min/max bounds, editable in HueWorks
General Configuration and exposed to Home Assistant for adjustment and reuse.
Circadian light states may inherit each event's global timing or override it
locally. Inheritance disables all profile-specific timing shaping for that event.
Stored local values remain available when a local override is re-enabled.

The initial household use case is an effective sunset no earlier than 18:00 in
the configured local timezone. Early winter sunsets should not make indoor
lighting enter its evening behavior at 16:30. Later summer sunsets should still
follow the sun. This is a tunable starting point, not a hardcoded product default.

This document specifies future implementation and rollout. It does not authorize
deployment, live lighting tests, or edits to Home Assistant automations by itself.

## Agreed Semantics

### Global configuration

Add four optional values to HueWorks General Configuration:

- Sunrise minimum
- Sunrise maximum
- Sunset minimum
- Sunset maximum

Use local wall-clock times in the existing global timezone, not UTC or a fixed
UTC offset. Normalize through the project's time-parsing conventions. Blank means
unconstrained; midnight is a real value, not a sentinel for disabled.

Each min/max pair is a same-calendar-day window. Reject min greater than max.
Do not interpret an inverted pair as an overnight range. Equal bounds are valid
and pin the shared event to that time. All four global defaults are blank.

### Light-state editor

Add independent `Override sunrise timing` and `Override sunset timing` checkboxes
to each **circadian light state**. These are not scene fields:
scenes reuse light states, so a profile edit affects all consumers of that profile.

| Override | Bounds displayed | Bounds used in calculation |
| --- | --- | --- |
| Unchecked | Current global min/max, local timing inputs disabled | Astronomical event clamped by the global pair; default ramp timing |
| Checked | Editable local timing and min/max | Local timing and local pair only |

Rules:

- The local pair replaces the global pair completely. Never intersect them or
  fall back to a global bound when one local field is blank.
- Checked with both local fields blank means no bounds for that event.
- Checked with only one value supplies only that bound.
- Sunrise and sunset can independently inherit or override.
- Newly created circadian profiles default to both checkboxes unchecked.
- On a new profile, local bounds start blank. Enabling Override must not copy
  displayed global values into local storage implicitly.
- Retain local timing values while inheritance is selected: keep the existing
  fields stored, ignore them in calculations, and display the effective values.
  Re-enabling Override reveals the stored values. Use those existing fields,
  without a second remembered-values model or first-use tracking.
- Do not let disabled fields, missing form keys, or a generic form merge
  accidentally overwrite local bounds with displayed global values.
- Fixed times, shared offsets, and brightness/temperature offsets are disabled
  for the inherited event. Shared ramp-duration controls are disabled when both
  events inherit. When only one event overrides, explain that custom durations
  apply only around that event; the inherited event uses default durations.

There is no third Disabled policy. Override with blank bounds provides that
behavior without another enum value.

### Effective timing

Resolve timing independently for sunrise and sunset before calculating curves:

- Inherited event: astronomical time, no fixed time, zero shared/brightness/
  temperature offsets, global min/max bounds, and the existing default ramp
  durations (`brightness_mode_time_dark` 900 seconds and
  `brightness_mode_time_light` 3600 seconds).
- Overridden event: stored fixed time or astronomical time, stored shared
  offset, local min/max bounds, then stored brightness/temperature offsets.
  Its brightness ramp uses the stored duration values.

Do not add global offset or duration settings. Default timing remains active
even when the inherited global bounds are blank. Keep brightness curve type,
brightness/Kelvin ranges, and temperature ceilings per-profile; they are not
event-timing overrides. Preserve existing curve formulas and the noon/midnight
anchor algorithm, using effective timing rather than ignored stored values.

Consequences to preserve and test:

- No stored fixed time or offset can shift an inherited event. Runtime, preview
  samples, and all event markers must agree on this.
- In local override mode, retain the existing order: a shared offset precedes
  local clamping and curve-specific offsets follow it. A local curve offset can
  therefore move that curve outside its local shared bounds.
- An overridden fixed event time is still subject to local bounds.
- Bounds change the event anchors; they do not hold brightness or Kelvin constant
  until a deadline. Preserve effective ramp widths, temperature ceilings, and
  brightness/temperature formulas.
- Blank inherited bounds must behave like blank local bounds, even if ignored
  local values remain stored. An inheritance flag alone must not make the engine
  treat solar timing as constrained and shift noon/midnight anchors.

Examples for sunset, before curve-specific offsets:

| Astronomical/fixed base | Shared offset | Effective bounds | Shared result |
| --- | --- | --- | --- |
| 16:45 | 0 | global min 18:00, inheriting | 18:00 |
| 20:30 | 0 | global min 18:00, inheriting | 20:30 |
| 20:30 | 0 | global max 20:00, inheriting | 20:00 |
| 16:45 | 0 | local pair blank, overriding | 16:45 |
| 16:45 | 0 | local min 17:00, overriding global 18:00 | 17:00 |
| 18:15 | -30 minutes stored, ignored | global min 18:00, inheriting | 18:15 |

## Implementation Boundaries

### Data model and compatibility

Suggested flag names are `override_sunrise_timing` and
`override_sunset_timing`; their names must reflect the full timing override.

The existing light-state configuration is an embedded configuration stored in
the `light_states.config` database column. Prefer putting the flags alongside
the existing bounds there, rather than adding unrelated scene fields. Add the
global values to the existing global settings model and persistence path.

Migration requirements:

- Explicitly populate both override flags as **true** on every existing circadian
  profile, preserving its existing local values and pre-upgrade behavior.
- Do not reset, normalize away, or otherwise rewrite unrelated profile fields.
- Do not change manual light states, scene assignments, active scenes, presence
  rules, power overrides, or physical light state.
- Add global bounds as blank. Do not bake Ian's 18:00 preference or profile IDs
  into a schema migration or general default.
- Ensure both false and true survive all embedded-schema conversions, config
  dump/load paths, update merges, and exports. False must not disappear through
  truthiness-based fallback logic.
- Existing/legacy configuration payloads with missing flags must retain legacy
  local behavior. New-profile creation must explicitly initialize inheritance;
  do not conflate old missing fields with a newly created profile.
- Duplicating a profile preserves its flags and local bounds.
- If configuration import/export is supported, extend its compatibility handling
  and tests as well. An old imported profile must not unexpectedly inherit.

### Shared calculation and preview

Resolve effective timing in one shared, pure domain path used by runtime and
preview. Pass global values into that path through normal configuration inputs;
do not make `Hueworks.Circadian` query the database, HA, or MQTT.

Audit callers and normalizers, not just the main calculator. In particular, the
preview's solar-config normalization currently reconstructs a limited map; new
global fields must not be silently dropped before the shared calculation runs.

The chart's sampled values and shared/brightness/temperature event markers must
reflect the exact same resolution rules as runtime. Use existing preview UI
conventions to make inherited bounds and effective event times inspectable.
Avoid a parallel preview-only implementation.

Global edits must invalidate any relevant settings/planner/preview caches.
Active circadian scenes should pick up accepted changes through the existing
adaptation cycle, without switching scenes, clearing manual power overrides, or
creating a separate hardware-dispatch loop. The normal poll interval is an
acceptable convergence delay; do not introduce request flooding.

### Validation

- Validate global and local pairs using the same time formats and range rules.
- Reject malformed values and inverted active bounds with actionable field errors.
- Validate effective event ordering after resolving inheritance. Reject edits
  that introduce an invalid ordering for an affected profile on the current
  configured local date, and identify the profile in the error. Do not silently
  disable overrides, erase stored settings, or change another user's profile.
- Seasonal astronomical unavailability is a calculation failure, not proof that
  otherwise valid settings are malformed. Propagate neighboring-day failures
  as errors instead of raising. Retain existing valid desired targets when a
  circadian calculation fails, while still honoring explicit off/presence-off
  intent. Do not emit an incomplete on command or fabricate target levels.
- Resolve solar events and neighboring days by the configured local calendar
  date, including UTC-boundary and date-line timezones. Preserve the existing
  documented ambiguous/nonexistent local wall-time policy and test DST cases.
- Invalid HA commands must leave the last accepted persisted value intact.
- Validate and patch the latest persisted settings atomically. Cached snapshots
  must not overwrite concurrent UI/HA edits or validate against a stale pair.

## Home Assistant Contract

### Ownership and exposure

HueWorks owns and persists the global settings. Home Assistant provides editable
controls backed by those settings, not a second independent helper that must be
kept synchronized through SSH, database writes, or a separate automation.

Extend the existing MQTT discovery/command/state architecture. Expose stable,
clearly named entities for all four global bounds when HA export is enabled.

The contract must support:

- Reading, setting, and explicitly clearing each optional bound.
- State publication reflecting accepted persisted values, not optimistic commands.
- Updates made in either HueWorks UI or HA appearing in the other surface.
- Existing availability conventions: unavailable is not the same as unset.
- Correct discovery and state restoration after HA, broker, or HueWorks restart.
- Repeated identical commands being harmless, without unnecessary scene dispatch.
- No replay of stale retained commands overwriting newer persisted settings.
- Pair validation through the same application boundary used by the HueWorks UI.

Use an HA entity type that can represent optional times honestly. Prefer a native
time editor if supported clear/unset semantics fit. Otherwise a validated text
entity with an explicit blank/clear contract is acceptable. Do not use 00:00,
unknown, or unavailable as a fake unconstrained value. Verify supported MQTT
discovery schemas and report the final entity IDs, services, and unset behavior
to the HA implementer. This representation is an implementation choice, not a
requirement to add redundant boolean helpers for every bound.

The audited native MQTT time entity lacks an explicit clear operation and uses
unknown for an unset value. Prefer four validated MQTT text entities unless a
verified native alternative meets the full contract. Publish a retained,
nonempty state envelope so a blank value does not delete the retained state.

The current Tortoise handler drops the retain flag and the exporter has no
offline last will. Implement and test an explicit stale-command defense and
broker-backed availability. Setting discovery `retain: false` alone does not
protect against an already-retained command. Avoid timing-based replay filters.

### Downstream automation handoff

The HA scene schedule is separate from individual profiles' circadian offsets.
It should use astronomical sunset clamped by the global sunset bounds only.
It must not use one arbitrary light state's fixed times or offsets.

For the initial rollout, with only a minimum configured, the desired transition
time is the later of actual sunset and the configured minimum. If a maximum is
later configured, the HA scheduling implementation must account for it too;
the earlier two-trigger/minimum-only recipe is not a complete general solution.

The existing automation to adapt is:

- `automation.main_floor_hueworks_evening_auto_at_sunset`
- Unique ID: `1780620688779`
- Guard: `select.hueworks_main_floor_scene` is `All Auto`.
- Actions: Main Floor to `Evening Auto`, then Foyer to `Evening`.

Preserve that guard and those actions. Do not automatically reverse a scene
change or override Bright, Manual, Off, or another deliberate scene selection
when a bound changes. Do not alter the real `sun.sun` entity or HA location.

Keep these unrelated automations on actual astronomical events:

- Front/outdoor lights at sunset
- Office shades at sunrise/sunset

Defer live HA automation edits until HueWorks exposes a verified contract. The
HA follow-up must define behavior for edits after the target time, missed times
during restarts, unavailable bounds, and maximum-bound scheduling. Avoid long
delays that disappear on reload, competing timers, and unconditional startup
scene changes. This spec does not require a new effective-sunset sensor in the
HueWorks release; add one only if separately justified by the HA implementation.

## Suggested Code Touchpoints

Inspect current code before editing; another thread may have ongoing changes.

- `lib/hueworks/schemas/app_setting.ex`
- `lib/hueworks/app_settings.ex`
- `lib/hueworks/app_settings/solar_config.ex`
- `lib/hueworks/circadian/config.ex`
- `lib/hueworks/schemas/light_state/config.ex`
- `lib/hueworks/schemas/light_state.ex`
- `lib/hueworks/circadian.ex`
- `lib/hueworks/circadian_preview.ex`
- `lib/hueworks/scenes/light_states.ex`
- General Configuration LiveView and circadian light-state editor/form/preview
- Existing HA export discovery, command routing, publication, and lifecycle code
- Configuration import/export, relevant runtime caches, and calculation callers

Follow the existing pure-domain versus supervised-runtime split. Prefer a small
resolver/helper if needed, not a general settings-inheritance framework.

## Acceptance Tests

1. Migration preserves all existing circadian outputs and local config, with both
   flags explicitly true and all new global fields blank; manual states unchanged.
2. New profiles inherit, legacy missing-flag payloads retain local behavior, and
   duplication/import/export preserve the intended semantics, including false.
3. Sunrise-only, sunset-only, both, and neither override combinations work.
4. Blank, one-sided, equal, valid two-sided, malformed, and inverted bounds behave
   correctly. Blank local fields never inherit individual global fields.
5. Ignored stored local timing cannot leak into event calculation or constrained
   noon/midnight detection.
6. Inheritance ignores fixed times, all shared/curve-specific offsets, and custom
   ramp durations without erasing them. Local override restores them. Cover
   each mixed sunrise/sunset combination and both blank and populated globals.
7. Winter, summer, both DST transitions, local dates near UTC midnight, and event
   ordering use the configured timezone consistently. Include Kiritimati's local
   date and Tromso's neighboring-day polar-event error. No failed calculation
   may crash adaptation or emit an incomplete on command.
8. Preview samples and all event markers match direct runtime calculation for
   the same date, profile, and global values, including unsaved editor changes.
9. Editor inheritance displays globals read-only without persisting them as
   local values; test toggle/save/reload/duplicate behavior and the selected local
   value retention behavior, including disabled timing inputs and durations.
10. Global changes reach active inherited profiles through normal adaptation;
    overridden and manual profiles retain their configured behavior. Presence
    gates, manual power overrides, and active-scene ownership remain intact.
11. MQTT commands validate, persist, and publish accepted state; clearing,
    rejected commands, duplicates, availability, and restart/reconnect behavior
    do not produce stale writes or split-brain values.
12. Run focused tests and the full `mix test` suite. Update durable documentation
    and remove implemented work from this forward-looking plan as it lands.

Use fixtures grounded in the actual Main Floor shared-profile arrangement, not
only isolated synthetic curves. Pure calculations must not dispatch hardware.

## Initial Household Rollout (Separate From Migration)

After implementation, testing, and deployment approval:

1. Back up the relevant configuration and capture baseline effective curves.
2. Set global sunset minimum to 18:00; leave the other three bounds blank.
3. Explicitly enable inheritance for sunrise and sunset on the six intended
   profiles, verifying names and IDs against the live installation:
   - Default Circadian
   - Default Circadian Dim
   - Default Circadian Very Dim
   - Warm Circadian
   - Default Circadian Extra Warm
   - 2700K Circadian
4. Preserve every other profile value and all scene assignments. An unused
   profile should still be configured consistently; do not delete it.
5. Verify HA readback, edit/clear/restore behavior, runtime/preview agreement,
   and normal adaptation without forcing a different scene for testing.
6. Hand off the final HA entity contract and update the scene-scheduling
   automation in a separately controlled step.

The shared default profile affects Main Floor, Garage, Hallway, Guest Room,
Master Bedroom, and Studio. Foyer has separate circadian profiles. House-wide
scope is intentional. Off scenes may reference a circadian profile for their
other state properties; inheritance must not turn their lights on.

Keep the previous global/local values and flags available for configuration
rollback. Do not assume rolling back the application image also reverses its
database migration.

## Non-Goals

- Editable global offsets or ramp durations
- A third Disabled policy
- Per-scene copies of shared profile settings
- Automatic switching to Bright or changes to scene membership/brightness ranges
- A new curve formula or holding all lights at maximum until the minimum time
- Mandatory HA availability for local circadian adaptation
- Generic inheritance infrastructure, arbitrary HA entity bindings, or SSH/DB sync
- Unrelated lighting cleanup, changes to outdoor schedules, or live deployment
