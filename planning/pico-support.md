# Pico Support (Planned)

## Goal
Allow Caseta Pico remotes to act as first-class external inputs for HueWorks so they can trigger the same kinds of actions users can already perform directly in the HueWorks UI.

This should close one of the last major gaps preventing HueWorks from being the full-time main-floor lighting workflow.

## Product Framing
Pico support should be designed as part of the same broad workflow as Home Assistant scene activation:

- these are external inputs
- they should enter the same core scene/control pipeline as direct UI interaction
- they should not invent a parallel control model unless there is a strong reason to do so

The guiding principle should be:

> A Pico button press should feel like a physical shortcut for actions users could already trigger from HueWorks.

That means the implementation should prefer reusing the existing HueWorks action paths rather than creating one-off dispatch behavior for remotes.

## Locked Decisions
- Pico configuration should have a dedicated entry point from the Caseta bridge card on `/config`.
- Pico support should be treated as bridge-specific configuration, not as part of the general light/group import UI.
- Runtime Pico actions should map onto existing HueWorks actions wherever possible.
- This work should be considered alongside Home Assistant scene inputs, because both represent external triggers for the same internal behaviors.

## Scope
- Replace the current Caseta Pico stub logging path with real event ingestion.
- Add persistence for Pico devices and their button mappings.
- Add UI for reviewing available Picos and configuring button behavior.
- Map Pico button presses into existing HueWorks runtime actions.
- Add tests for Pico event ingestion, mapping resolution, and runtime action dispatch.

## Out Of Scope (Initial Version)
- Arbitrary scripting/macros beyond what the HueWorks UI already supports.
- Cross-system Pico sync with Home Assistant or other controllers.
- Rich multi-step automations triggered by one Pico event.
- Per-button custom rate curves or advanced dimming choreography unless needed for parity.

## Config UI Surface
Add a dedicated Pico configuration action to the Caseta bridge card on `/config`.

This should likely open a dedicated Pico configuration view or modal where operators can:

- see discovered Pico devices
- identify them by name or source id
- review current button mappings
- assign or change mappings
- disable or clear mappings
- validate that incoming button events are being seen

The important product decision here is that Pico configuration should be easy to reach from the same place users already manage bridge-level setup.

It should not feel like a hidden expert-only path.

## Runtime Behavior Model
The safest model is to treat Pico button actions as requests for HueWorks-native actions.

Examples:

- activate a HueWorks scene
- toggle room occupancy
- turn a group on or off
- raise or lower brightness through the same manual-control path used by the UI

The more Pico behavior can reuse existing HueWorks action boundaries, the fewer special cases we will create.

That suggests a structure like:

- Pico event arrives
- event resolves to a configured HueWorks action
- that action calls the same context/runtime entry point used by UI interactions

Examples of target entry points could include:

- `Scenes.activate_scene/1`
- room-level occupancy/action handlers
- light/group manual control paths

The key architectural preference is:

- translate Pico input into a HueWorks action
- do not translate Pico input directly into low-level bridge commands unless absolutely necessary

## Mapping Model
A first version can stay intentionally simple.

Possible shape:

### `pico_devices`
- `id`
- `bridge_id`
- `source_id`
- `name`
- `display_name`
- `metadata`
- timestamps

### `pico_button_mappings`
- `id`
- `pico_device_id`
- `button` or `button_number`
- `press_type` or gesture (`press`, `hold`, `release` if needed)
- `action_type`
- `action_config`
- `enabled`
- timestamps

The exact schema can stay flexible, but the important part is that mappings should resolve to HueWorks-native actions, not arbitrary transport behavior.

## Action Types To Consider
Initial action types that seem most aligned with current HueWorks behavior:

- activate scene
- turn room/group/light on
- turn room/group/light off
- toggle occupancy
- brighten / dim active room scene
- maybe cycle scenes in a room later

I would strongly prefer starting with a narrow, high-confidence set that maps cleanly onto existing runtime paths.

A simpler first version is probably better than over-designing a huge action surface.

## Discovery And Refresh
Pico support likely needs a device discovery or refresh path, but this should still be kept conceptually separate from normal light/group import.

A reasonable operator flow would be:

1. Configure Caseta bridge.
2. Open Pico config from the Caseta bridge card.
3. Refresh or discover Pico devices.
4. Assign mappings to buttons.
5. Test a button press and confirm that HueWorks performs the expected action.

This keeps bridge setup, Pico discovery, and runtime mapping close together in the UI.

## Relationship To Home Assistant Scene Inputs
These two efforts should be designed with a shared mental model:

- Home Assistant scenes are external software triggers.
- Picos are external hardware triggers.
- both should ultimately invoke the same internal HueWorks actions users can trigger from the app.

This matters because it gives us a more coherent architecture:

- external input adapters
- mapping/configuration layer
- shared HueWorks action entry points

rather than:

- one special flow for HA scenes
- another unrelated special flow for Picos
- direct bridge dispatch scattered in multiple places

## Testing Plan
- Unit:
  - Pico event normalization/parsing
  - mapping resolution rules
  - invalid/unmapped button behavior
- Integration:
  - Pico event -> mapped HueWorks action
  - disabled mapping -> no-op
  - repeated button events behave predictably
- UI:
  - Caseta bridge card Pico config entry point
  - mapping create/update/remove
  - discovered device list and status

## Phased Execution Plan
1. Define Pico data model and mapping shape.
2. Add Caseta bridge-card config entry point in `/config`.
3. Add Pico discovery/listing/config UI.
4. Replace stub Pico event logging with real mapping resolution.
5. Route mapped actions into existing HueWorks runtime entry points.
6. Add integration and UI regression coverage.

## Open Questions
- What is the smallest initial action surface that still makes Pico support feel useful day one?
- Do we need hold/release gesture differentiation in V1, or is single-press mapping enough?
- Should room-level dimming actions target the active scene, the room, or explicit groups/lights?
- How much runtime feedback about Pico presses should be exposed in the UI/logs?

## Bottom Line
Pico support should not be treated as a one-off remote-control exception.

It should be treated as another external-input path into HueWorks-native actions.

That keeps the user experience coherent:

- clicking in the HueWorks UI
- triggering a mapped Home Assistant scene
- pressing a Pico button

should all feel like different front doors into the same control system.
