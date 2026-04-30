# HomeKit Bridge Integration (Planned)

## Goal
Expose HueWorks lights and HueWorks scenes to Apple Home through a HomeKit bridge, while keeping HueWorks as the source of truth for scene behavior.

## Priority
Near-term. This is likely a prerequisite for having a second person test the app in a realistic day-to-day control flow.

## V1 Scope
- Add a HomeKit bridge runtime component in HueWorks using the `hap` Elixir dependency as-is.
- Expose eligible HueWorks-controlled lights as HomeKit `LightBulb` accessories.
- Expose HueWorks scenes as virtual HomeKit `Switch` accessories.
- Route HomeKit writes through the existing HueWorks control pipeline:
  - desired state update
  - planner
  - executor
- Reflect HueWorks physical-state and active-scene updates back into HomeKit so Apple Home stays in sync.
- Restart only the HomeKit bridge child when exported topology changes.
- Persist HomeKit pairing and bridge identity safely across HomeKit bridge restarts.

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

## Technical Direction
- Use `hap` as a normal dependency rather than forking it up front.
- Run `hap` behind a dedicated HueWorks manager/supervisor layer.
- Keep a stable HomeKit bridge `identifier`, deterministic accessory ordering, and persistent `data_path` so Home pairing survives HomeKit bridge child restarts.
- Treat HomeKit topology updates as rebuild + HomeKit bridge child restart events, not live graph edits.
- Use `hap` async value-notification support to keep light state and scene-switch state coherent without full restarts.

## Accessory Mapping
- Lights:
  - map controllable HueWorks lights to `LightBulb`
  - include on/off in V1
  - include brightness/temperature/color only if the mapping stays straightforward during implementation
- Scenes:
  - map each exported HueWorks scene to a virtual `Switch`
  - switch `on` activates the scene
  - scene-switch state reflects HueWorks active-scene state rather than acting as an independent boolean

## Implementation Areas
- HomeKit bridge runtime module(s) under `lib/hueworks_app/` or a dedicated `lib/hueworks/homekit/` namespace.
- Accessory graph builder:
  - stable accessory selection
  - stable ordering
  - stable accessory ID mapping
- HueWorks <-> HomeKit value-store layer for:
  - light writes
  - light reads
  - scene switch activation
  - async state notifications
- HomeKit bridge child manager responsible for:
  - startup
  - topology hash comparison
  - rebuild/restart when exported entities change
- Config surface for:
  - enable/disable HomeKit bridge
  - pairing metadata path
  - bridge display name / identity inputs if needed

## Testing Plan
- Unit:
  - light characteristic <-> HueWorks command mapping
  - scene switch activation mapping
  - per-room active-scene switch exclusivity
  - deterministic accessory ordering and stable ID mapping
- Integration:
  - HomeKit light write -> desired state -> planned actions
  - HomeKit scene switch write -> HueWorks scene activation
  - HueWorks physical-state updates reflected back to HomeKit
  - active-scene changes reflected by turning off sibling scene switches in the same room
  - HomeKit bridge child restart preserving pairing and bridge identity
- Manual:
  - pair from Apple Home
  - verify second-device control without HueWorks UI access
  - verify topology-change behavior after adding/removing exported entities

## Open Questions
- Should V1 expose groups in addition to lights, or keep the first pass lights-only plus scenes?
- Which HueWorks scenes should be exported by default, and does the user need explicit per-scene export control?
- Should brightness/temperature/color ship in the first pass, or should V1 deliberately target reliable on/off first?
- What exact runtime events should trigger a HomeKit bridge child rebuild/restart?
