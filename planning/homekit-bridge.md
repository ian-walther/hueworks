# HomeKit Bridge Integration (Planned)

## Goal
Allow HueWorks-controlled lights to be controlled from Apple Home/HomeKit by exposing HueWorks as a HomeKit bridge.

## Priority
Low priority. This is a later-phase integration track.

## Scope
- Add a HomeKit bridge runtime component in HueWorks.
- Expose HueWorks lights as HomeKit accessories/services/characteristics.
- Route HomeKit writes through the existing HueWorks control pipeline:
  - desired state update
  - planner
  - executor
- Reflect physical-state updates back into HomeKit so Apple Home stays in sync.
- Persist pairing/accessory metadata safely across restarts.

## Out of Scope (V1)
- Full scene parity as first-class HomeKit scenes.
- Advanced HomeKit automations/scripting support.
- Camera/sensor/non-light accessory classes.
- Cross-home multi-tenant support.

## Design Notes
- Prefer one-way command flow from HomeKit -> HueWorks control pipeline (no bypass paths).
- Keep source-of-truth semantics in HueWorks desired/physical state stores.
- Preserve current bridge throttling and grouping behavior by reusing planner/executor.
- Start with light power/brightness/temperature; color can follow.

## Likely Implementation Areas
- New HomeKit bridge/app runtime module(s) (for example under `lib/hueworks_app/`).
- Entity mapping/context layer (HueWorks light IDs <-> HomeKit accessory IDs).
- Control entrypoint wiring into existing:
  - `Hueworks.Control.DesiredState`
  - `Hueworks.Control.Planner`
  - `Hueworks.Control.Executor`
- Subscription/state fan-out path to publish updates back to HomeKit.
- Config/runtime env surface for HomeKit bridge identity and pairing storage.

## Testing Plan
- Unit:
  - HomeKit characteristic <-> HueWorks command mapping.
  - Accessory metadata mapping and persistence behavior.
- Integration:
  - HomeKit write -> desired state -> planned actions.
  - Physical-state updates reflected back to HomeKit characteristic state.
  - Restart behavior with preserved pairing/accessory identity.
- Regression:
  - Mixed bridge/device rooms still honor planner grouping and clamping semantics.

## Open Questions
- Which HomeKit library/runtime approach is the best fit for Elixir in this project?
- Should V1 expose lights only, or include groups as virtual accessories?
- How should HomeKit pairing material be secured/rotated in production deployments?
