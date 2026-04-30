# Home Assistant Reverse Integration

## Goal
Keep HueWorks -> Home Assistant export coherent enough for daily control without letting Home Assistant become the source of truth.

## Priority
Medium-term polish work after HomeKit and core control reliability.

## Locked Decisions
- Use Home Assistant MQTT discovery first.
- Do not start with a custom Home Assistant integration.
- Keep Home Assistant-originated control flowing through HueWorks' normal public control paths.
- Use stable ID-based identities for Home Assistant entities.
- Use human-readable display names for Home Assistant entities.
- Do not dynamically change exposed light capabilities based on whether a scene is active.

## Light Capability Policy
Do not dynamically change Home Assistant light capabilities based on whether a scene is active.

Specifically:
- do not switch a light back and forth between:
  - on/off only
  - brightness/color-temperature/color capable

Instead:
- expose the light's actual capabilities all the time
- publish separate context entities later if Home Assistant needs to know:
  - whether a scene is currently active
  - whether manual brightness or temperature changes are currently allowed

## Remaining Work
- Tighten metadata and device grouping so exported scenes, room selectors, lights, and groups feel consistent in HA.
- Improve republish and recovery behavior when MQTT export settings or entity shapes change.
- Add stronger operator-facing visibility for export health, discovery state, and stale retained payload cleanup.
- Decide whether room-level context entities should expand before any deeper light-capability work.
- Revalidate daily-control parity in real use before treating HA export as a primary control surface.

## Open Questions
- Should room-level active scene be represented as a select entity, sensor, or both?
- Should groups remain switch/light-exportable separately from their member lights?
- How much context metadata is worth publishing before the entity model becomes noisy?
- Is retained discovery cleanup sufficient, or do we need a more explicit tombstone/retire flow?
