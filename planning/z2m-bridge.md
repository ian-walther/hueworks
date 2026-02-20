# Zigbee2MQTT Bridge Integration (Planned)

## Goal
Add Zigbee2MQTT (Z2M) as a first-class bridge source in HueWorks so Zigbee lights/drivers can be imported, controlled, and subscribed natively without routing through Home Assistant.

## Context
- Coordinator is now installed and running with Z2M + Mosquitto.
- Migration from ZHA to the new coordinator will happen incrementally.
- This work enables direct ownership of LED strip/driver control paths in HueWorks.

## Locked Decisions
- Z2M is added as a new bridge `source` (same model pattern as `:hue`, `:ha`, `:caseta`).
- MQTT transport is through Mosquitto (broker details stored with bridge credentials).
- V1 scope is lights and light-like entities only.
- V1 supports import, state subscription, and outbound control for core fields:
  - `power`
  - `brightness`
  - `kelvin` / color temperature
- Button/remote actions and advanced effects are out of scope for V1.

## Scope
- Bridge setup UI for Z2M credentials/connection test.
- Z2M fetch/import normalization and materialization into existing entities.
- Runtime subscription for Z2M state topics -> `Control.State`.
- Outbound command path from planner/executor -> Z2M set topics.
- Entity capability/range mapping for brightness/temp support.
- Tests for parser, mapper, control payloads, and end-to-end planner/executor flow.

## Out of Scope (V1)
- RGB/effects/scenes from Z2M-specific extensions.
- Zigbee button/remote automations.
- Auto-migration tooling from ZHA/HA entities to Z2M entities.
- Device-level OTA/update operations.

## Proposed Credentials / Bridge Config
- `broker_host`
- `broker_port` (default `1883`)
- `username` (optional)
- `password` (optional)
- `base_topic` (default `zigbee2mqtt`)
- TLS options (future; optional in V1 unless needed immediately)

## Data / Entity Mapping
- Import from Z2M retained/discovery/device payloads.
- Normalize to HueWorks light/group model:
  - unique source ID from Z2M friendly name or IEEE-backed stable ID
  - room assignment via configurable metadata or fallback rules
  - capabilities from exposes/features
  - temp range (kelvin) where available
- Keep metadata rich enough for future advanced features.

## Runtime Flow
1. Z2M subscription receives state updates from MQTT.
2. Parse normalized fields and call `State.put(:light, ...)`.
3. Desired-state/planner/executor remain unchanged conceptually.
4. Z2M control adapter publishes command payloads to set topic(s).

## Reliability / Safety Notes
- Handle offline/stale MQTT connections with reconnect strategy.
- Guard against retained-message startup surprises by normalizing boot sequence.
- Ensure no publish loops (ignore self-origin echoes where possible).

## Testing Plan
- Unit:
  - topic parsing
  - payload normalization
  - capability extraction
  - command payload encoding
- Integration:
  - import/materialize path with realistic fixture payloads
  - subscription event -> in-memory physical state updates
  - planner/executor -> MQTT publish assertions
- Regression:
  - mixed-room/group planning with Z2M lights
  - kelvin clamp behavior for strip drivers with varied ranges

## Phased Execution Plan
1. Schema/bridge setup additions for Z2M credentials.
2. Z2M connectivity test path in `/config`.
3. Import fetch + normalize + materialize support.
4. Subscription runtime + state mapper.
5. Control adapter + executor integration.
6. Tests and docs pass.

## Open Questions
- Should friendly-name renames in Z2M be treated as identity changes or metadata updates?
- Do we require TLS MQTT in first production rollout?
- What is the exact room-assignment strategy for devices with no HA area metadata?
