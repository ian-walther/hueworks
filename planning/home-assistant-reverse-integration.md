# Home Assistant Reverse Integration

## Goal
Expose HueWorks entities outward to Home Assistant in a way that feels native in Home Assistant while still preserving HueWorks as the control and state authority.

The first migration step is publishing HueWorks scenes into Home Assistant.

This document also tracks a second outward-integration path for HomeKit through MQTT, intended for beta testers who do not use Home Assistant.

## Priority
Low priority overall, but scenes are the cleanest first slice when this work resumes.

## Locked Decisions
- Use Home Assistant MQTT discovery first.
- Do not start with a custom Home Assistant integration.
- Keep Home Assistant-originated control flowing through HueWorks' normal public control paths.
- Start with scenes before lights.
- Keep the current inbound Home Assistant scene trigger path alive in parallel during migration.
- Use stable ID-based identities for Home Assistant entities.
- Use human-readable display names for Home Assistant entities.
- Do not dynamically change exposed light capabilities based on whether a scene is active.
- Keep in mind a second MQTT-based path for HomeKit using Homebridge and `homebridge-mqttthing`.
- For HomeKit, prefer a small packaged stack over a custom HAP implementation as a first step.

## Why MQTT Discovery First
- HueWorks already has MQTT plumbing through Zigbee2MQTT support.
- Home Assistant MQTT discovery is sufficient for scenes and lights.
- This avoids the complexity of maintaining a parallel Home Assistant custom integration.
- MQTT is a better fit for incremental rollout:
  - publish scenes first
  - then add state/context entities
  - then add lights

## Parallel Option: HomeKit via MQTT
For users who do not run Home Assistant, the most practical HomeKit path is not a custom Elixir HAP stack.

Instead, the likely first implementation path is:
- HueWorks
- MQTT broker
- Homebridge
- `homebridge-mqttthing`

Why this is attractive:
- it keeps HueWorks in MQTT land
- it avoids building or maintaining a custom HomeKit bridge in HueWorks
- it is much lighter than asking a beta tester to run Home Assistant just for HomeKit exposure
- it can be packaged as a small, mostly self-contained deployment

Recommended first HomeKit slice:
- scenes first
- then lights

Recommended HomeKit accessory mapping:
- HueWorks scenes -> HomeKit `Switch` accessories
- HueWorks lights -> HomeKit `Lightbulb` accessories

Recommended scene behavior:
- turning a scene switch `on` activates the corresponding HueWorks scene
- HueWorks can then publish the switch back to `off` so it behaves like a momentary trigger

Recommended packaging:
- provide a single Docker Compose bundle for:
  - MQTT broker
  - Homebridge
  - `homebridge-mqttthing`

This is a reasonable future path for a friend or beta tester who:
- wants HomeKit support
- does not use Home Assistant
- should not have to manage many moving parts manually

## V1 Scope
- Publish HueWorks scenes to Home Assistant as MQTT scene entities.
- Subscribe to scene command topics from Home Assistant.
- Activate the corresponding HueWorks scene through the normal scene activation path.
- Keep the current Home Assistant -> HueWorks external-scene mapping flow working in parallel.
- Prevent HueWorks from re-importing the scenes that HueWorks itself published into Home Assistant.

## V1 Out of Scope
- Exposing HueWorks lights.
- Dynamic capability switching for lights based on active-scene state.
- A Home Assistant custom integration.
- Bidirectional scene synchronization beyond "Home Assistant can trigger HueWorks scenes".
- Full metadata parity or polished Home Assistant device taxonomy.

## Scene Entity Model
Each HueWorks scene should be published as a Home Assistant MQTT scene entity.

Recommended naming:
- display name: `<Room Name> <Scene Name>`
- unique id: `hueworks_scene_<scene.id>`

Recommended Home Assistant device grouping:
- one Home Assistant device per HueWorks room
- device identifier: `hueworks_room_<room.id>`
- device name: `HueWorks <Room Name>`

This keeps:
- entity names easy to understand in dashboards and automations
- identifiers stable even if a room or scene gets renamed

## Scene MQTT Topics
Recommended topic shape:
- discovery topic:
  - `homeassistant/scene/hueworks_scene_<scene.id>/config`
- command topic:
  - `hueworks/ha_export/scenes/<scene.id>/set`
- attributes topic:
  - `hueworks/ha_export/scenes/<scene.id>/attributes`
- availability topic:
  - `hueworks/ha_export/status`

Retain should be enabled for:
- discovery payloads
- availability payloads
- attributes payloads if they are used as metadata snapshots

## Scene Discovery Payload
Recommended payload shape:

```json
{
  "platform": "scene",
  "name": "Main Floor All Auto",
  "unique_id": "hueworks_scene_123",
  "command_topic": "hueworks/ha_export/scenes/123/set",
  "payload_on": "ON",
  "availability_topic": "hueworks/ha_export/status",
  "payload_available": "online",
  "payload_not_available": "offline",
  "json_attributes_topic": "hueworks/ha_export/scenes/123/attributes",
  "device": {
    "identifiers": ["hueworks_room_1"],
    "name": "HueWorks Main Floor",
    "manufacturer": "HueWorks",
    "model": "Room Scenes"
  }
}
```

Recommended attributes payload:

```json
{
  "hueworks_managed": true,
  "hueworks_scene_id": 123,
  "hueworks_room_id": 1,
  "room_name": "Main Floor",
  "scene_name": "All Auto"
}
```

## Scene Command Handling
Subscribe to:
- `hueworks/ha_export/scenes/+/set`

Behavior:
- payload `ON` activates the matching HueWorks scene
- other payloads are ignored

Activation path:
- resolve the scene id from the topic
- call `Hueworks.Scenes.activate_scene(scene.id, ...)`
- do not add a Home Assistant-specific bypass path

This keeps Home Assistant scene activation semantically equivalent to activating the scene from the HueWorks UI.

## Migration Safety
The current inbound Home Assistant scene sync currently imports every `scene.*` entity from Home Assistant.

That means HueWorks-published MQTT scenes would otherwise be visible to the current inbound sync and could be re-imported into HueWorks.

The reverse-integration rollout should include a filter so inbound Home Assistant scene sync skips HueWorks-published scenes.

Recommended filter:
- mark reverse-published scenes with `hueworks_managed: true`
- exclude those during Home Assistant scene fetch/import

Fallback filter if needed:
- skip entities with a HueWorks-owned entity-id naming convention

The attribute-based marker is preferred.

## Availability
Publish a retained global availability topic:
- `hueworks/ha_export/status = online`

If clean shutdown support is added later, publish:
- `offline`

This is enough for the first scene slice.

## Light Exposure Plan
After scenes are working, lights can be exposed as Home Assistant MQTT lights.

That work should:
- use stable unique IDs based on HueWorks light IDs
- publish state from HueWorks physical state
- route commands through HueWorks manual-control entrypoints
- expose real light capabilities consistently

## Light Capability Policy
Do not dynamically change Home Assistant light capabilities based on whether a scene is active.

Specifically:
- do not switch a light back and forth between:
  - on/off only
  - brightness/color-temperature/color capable

Why:
- those capabilities describe the light itself, not the current scene policy
- a light entity whose controls change based on scene activity will be harder to reason about in Home Assistant dashboards and automations
- it blurs the architectural boundary between:
  - device capability
  - current HueWorks scene policy

Instead:
- expose the light's actual capabilities all the time
- publish separate context entities later if Home Assistant needs to know:
  - whether a scene is currently active
  - whether manual brightness or temperature changes are currently allowed

## Light V2 Ideas
Once scenes are published and stable, likely next additions are:
- MQTT lights for HueWorks-controlled lights
- room-level active-scene sensor
- room-level scene-active binary sensor
- optional policy/context sensors for manual-adjustment eligibility

That gives Home Assistant enough information to build policy-aware dashboards without mutating the light entity model itself.

## HomeKit MQTT Path
This is not the first implementation target, but it is a reasonable second path if HomeKit support is needed without Home Assistant.

Recommended bridge:
- Homebridge with `homebridge-mqttthing`

Recommended rollout:
1. MQTT scene export shaped for Homebridge scene switches
2. scene activation via MQTT command topics
3. light export for:
   - on/off
   - brightness
   - color temperature
4. optional color support later

Design guidance:
- keep HueWorks as the state and control authority
- keep MQTT topics stable and explicit
- prefer one Homebridge accessory per HueWorks scene or light
- do not make the HomeKit path depend on Home Assistant being present

Operational guidance:
- assume an MQTT broker is part of the deployment
- prefer a prepackaged Docker Compose setup over handwritten installation steps
- keep the Compose stack small enough for a beta tester to run comfortably

## Likely HueWorks Implementation Areas
- a new Home Assistant export runtime that publishes MQTT discovery/state payloads
- scene discovery payload generation
- scene command subscription and dispatch
- Home Assistant reverse-export identity conventions
- filtering in the current inbound Home Assistant scene import path so HueWorks-managed scenes are skipped

Likely code areas:
- `/Users/ianwalther/code/hueworks/lib/hueworks/external_scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/import/fetch/home_assistant.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex`
- MQTT runtime additions beside the existing Zigbee2MQTT MQTT plumbing

## Testing Plan
### Scenes
- unit:
  - scene discovery payload generation
  - scene topic parsing
  - scene command payload handling
  - HueWorks-managed scene import filtering
- integration:
  - publish scene discovery payloads
  - receive scene command topic
  - activate HueWorks scene through normal scene path
  - verify current inbound external-scene flow still works in parallel

### Lights
When lights are added later:
- unit:
  - command payload -> HueWorks control intent mapping
  - capability publication
  - unique-id/device grouping behavior
- integration:
  - Home Assistant command -> HueWorks control path
  - HueWorks physical-state change -> Home Assistant state publish
  - context entities reflect active-scene state correctly

## Acceptance Criteria
### Scenes
- HueWorks scenes appear in Home Assistant as stable MQTT scene entities.
- Activating a published Home Assistant scene reliably activates the corresponding HueWorks scene.
- Existing inbound Home Assistant scene mapping remains usable during migration.
- HueWorks does not re-import its own published scenes.

### Lights
For the later light slice:
- Home Assistant users can control HueWorks lights without bypassing HueWorks control semantics.
- Light entities remain stable in Home Assistant regardless of active scene state.
- Scene-policy context is exposed separately rather than encoded by mutating light capabilities.

## Open Questions
- Should reverse-export use the same MQTT broker config as Zigbee2MQTT by default, or its own explicit Home Assistant MQTT broker config?
- Should scene attributes include configuration URLs back into HueWorks once there is a stable route for that?
- Should room-level active-scene and scene-active context entities ship in the same release as lights, or one step earlier?
- If the HomeKit MQTT path is built later, should it share the same MQTT export broker config as Home Assistant reverse-export, or have its own explicit broker configuration?
- If the HomeKit MQTT path is built later, should HueWorks generate Homebridge-ready config fragments, or should the Docker bundle own that mapping entirely?
