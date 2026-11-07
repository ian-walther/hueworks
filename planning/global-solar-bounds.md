# Global Solar Bounds Rollout

HueWorks implements global sunrise and sunset bounds, per-event timing inheritance, and the Home Assistant entities. See [Circadian Timing And Global Bounds](../docs/circadian-timing.md). This plan covers the remaining household rollout and Home Assistant scheduling work.

This document does not authorize deployment, live lighting tests, or edits to Home Assistant automations.

The household goal is an effective sunset no earlier than 18:00 in the configured timezone, so early winter sunsets do not start indoor evening behavior at 16:30 while later summer sunsets still follow the sun. This is a tunable starting point, not a product default.

## Initial Household Rollout

After deployment approval:

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

## Home Assistant Contract Verification

The MQTT contract is tested against stubbed networking only. Before relying on
it, verify against the live Home Assistant and broker:

- The command template renders with `to_json`, and an empty value clears a bound.
- An unset bound shows an empty text state, not `unknown`.
- Reconnecting rotates the session without changing entity IDs or unique IDs.
- `default_entity_id` produces the documented entity IDs.
- The last will reports `offline` on an unclean disconnect, and `online` returns
  after reconnecting, including when the broker takes over the old connection.
- A retained command is not applied after a reconnect.

## Home Assistant Scene Scheduling

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

Defer live HA automation edits until the entity contract is verified against
the live installation. The HA follow-up must define behavior for edits after the
target time, missed times during restarts, unavailable bounds, and maximum-bound
scheduling. An empty text state means the bound is unset; `unavailable` must not
be treated as unset. Avoid long delays that disappear on reload, competing
timers, and unconditional startup scene changes. Add an effective-sunset sensor
to HueWorks only if separately justified by the HA implementation.
