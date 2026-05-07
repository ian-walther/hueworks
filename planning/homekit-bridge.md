# HomeKit Bridge Integration

## Goal
Expose HueWorks lights and HueWorks scenes to Apple Home through a HomeKit bridge, while keeping HueWorks as the source of truth for scene behavior.

## Priority
Near-term. This is likely a prerequisite for having a second person test the app in a realistic day-to-day control flow.

## Remaining V1 Work
- Validate pairing and daily control against Apple Home on real devices.
- Add a HueWorks UI surface for HomeKit bridge status and pairing details instead of relying on console output.
- Verify that the persistent HAP `data_path`, bridge identifier, setup ID, and pairing code preserve pairing across app restarts and HomeKit bridge child restarts.
- Decide whether the first UI should include a manual "restart HomeKit bridge" action for debugging, even though normal topology changes restart automatically.
- Confirm that enabling scene export with many scenes still feels usable in Apple Home.

## Out of Scope (V1)
- Native Apple Home scene authoring as a primary workflow.
- Full HomeKit scene parity as HAP-native objects.
- Pico/HomeKit button accessory work.
- Sensor, lock, thermostat, camera, or non-light accessory classes.
- Dynamic in-place accessory graph mutation without restarting the HomeKit bridge child.

## Product Direction
- Do not encourage users to recreate HueWorks scenes as native Apple Home scenes.
- Keep HueWorks scenes first-class by exposing them as virtual switches in HomeKit.
- Prefer room-local scene semantics:
  - one active scene switch per room
  - when one scene activates, other scene switches in that room turn off
  - if no HueWorks scene is active for a room, all scene switches for that room are off
- Scene export is controlled by one global HomeKit scene toggle.
- Light/group export is opt-in per entity from the Lights page edit modal.

## Technical Direction
- Use `hap` as a normal dependency rather than forking it up front.
- Run `hap` behind a dedicated HueWorks manager/supervisor layer.
- Keep a stable HomeKit bridge `identifier`, deterministic accessory ordering, and persistent `data_path` so Home pairing survives HomeKit bridge child restarts.
- Treat HomeKit topology updates as rebuild + HomeKit bridge child restart events, not live graph edits.
- Use `hap` async value-notification support to keep light state and scene-switch state coherent without full restarts.

## Accessory Mapping
- Lights:
  - map controllable HueWorks lights to `LightBulb`
- Groups:
  - map controllable HueWorks groups to `LightBulb`
- Light/group V1:
  - expose only on/off behavior
  - keep the per-entity export mode shape expandable for future brightness/temperature/color support
- Scenes:
  - map all HueWorks scenes to virtual `Switch` accessories when global scene export is enabled
  - switch `on` activates the scene
  - scene-switch state reflects HueWorks active-scene state rather than acting as an independent boolean

## Future Expansion
- Add brightness, temperature, and color HomeKit characteristics for lights/groups after on/off pairing and restart behavior is proven.
- Consider a reset-pairing workflow if testing shows stale HomeKit pairings are hard to recover from.
- Consider per-scene export controls only if global scene export proves noisy in real use.
