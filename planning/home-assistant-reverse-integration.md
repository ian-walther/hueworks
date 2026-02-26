# Home Assistant Reverse Integration (HueWorks -> HA) (Planned)

## Goal
Expose HueWorks-controlled lights into Home Assistant so HA can control HueWorks entities directly, mirroring the current one-way Home Assistant support in the opposite direction with a seamless, parity-or-better user experience.

## Priority
Low priority. This is a later-phase integration track.

## Locked Decisions
- Home Assistant support remains optional for HueWorks core value.
- When enabled, HA integration should feel first-class for HA-centric households.
- HA-originated control must use HueWorks desired-state -> planner -> executor (no bypass path).
- State coherence between HA and HueWorks is a hard requirement (no prolonged drift as normal behavior).

## Scope
- Add a Home Assistant-facing integration surface for HueWorks light entities.
- Expose HueWorks lights with stable IDs and metadata that HA can consume.
- Route HA control requests through the existing HueWorks control pipeline:
  - desired state update
  - planner
  - executor
- Publish HueWorks physical-state updates back to HA entity state.
- Support synchronization lifecycle for add/remove/rename/availability changes.

## Out of Scope (V1)
- Full parity for all accessory classes beyond lights.
- Complex automation authoring UX inside HueWorks.
- Bidirectional scene synchronization semantics beyond basic control.
- Multi-instance federation across multiple HueWorks deployments.

## Design Notes
- Do not bypass HueWorks planner/executor; HA-originated writes should use the same path as UI/manual actions.
- Preserve HueWorks as the control source of truth for desired/physical state.
- Start with light power/brightness/temperature controls first; advanced features can follow.
- Use source-scoped identity mapping to avoid collisions and preserve stable entity IDs.
- Optimize for "feels native in HA" outcomes: reliable state reflection, predictable timing, and low-surprise behavior.

## Likely Implementation Areas
- New HA integration runtime surface (API/websocket/discovery path as selected).
- Entity mapping/context layer (HueWorks light IDs <-> HA entity IDs).
- Control entrypoint wiring into:
  - `Hueworks.Control.DesiredState`
  - `Hueworks.Control.Planner`
  - `Hueworks.Control.Executor`
- State publication hooks from subscription/control-state fan-out to HA.
- Config/runtime settings for HA integration endpoint/auth/namespace.

## Testing Plan
- Unit:
  - HA command payload -> HueWorks desired-state mapping.
  - entity metadata/identity mapping and lifecycle behavior.
- Integration:
  - HA control request -> desired state -> planned actions.
  - physical-state change in HueWorks -> reflected HA state.
  - entity lifecycle changes (rename/disable/remove) reflected to HA.
- Regression:
  - mixed bridge/device rooms maintain planner grouping and kelvin clamping behavior.

## Acceptance Criteria
- Core HA control paths (on/off, brightness, temperature) are functionally reliable and predictable.
- HA state reflects HueWorks physical state quickly enough for normal interactive use.
- HA users can operate daily lighting workflows without understanding HueWorks internals.
- Integration quality is at least parity with HA-native behavior for common day-to-day controls, while preserving HueWorks optimization benefits.

## Open Questions
- Should the integration be implemented as HA MQTT discovery/entities, HA websocket integration, or a custom HA integration component first?
- How should authentication and trust boundaries be enforced between HA and HueWorks?
- Should groups/scenes be exposed in V1, or lights-only first?
