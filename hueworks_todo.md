# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

## Now (Critical Path)

### 1) Pico support
- [ ] Replace Caseta Pico stub event logging with real event handling + mapping entrypoint.
- [ ] Define Pico button mapping UX for HueWorks scene/control actions.
- [ ] Add end-to-end tests for Pico event ingestion, mapping resolution, and runtime activation.

### 2) Home Assistant scenes (Home Assistant -> HueWorks)
Reference: `planning/external-scenes.md`
- [ ] Add generic external scene model (`external_scenes`) with source-scoped identity.
- [ ] Add scene mapping model linking external scenes to HueWorks scenes.
- [ ] Extend HA import/resync to include `scene.*` entities.
- [ ] Add UI to review/sync external scenes and manage mappings.
- [ ] Subscribe to HA scene activation events and trigger mapped HueWorks scenes.
- [ ] Add tests for sync, mapping resolution, and activation event flow.

### 3) Circadian validation and polish
Reference: `planning/circadian-adaptation.md`
- [ ] Replace the current room occupancy UI toggle with HA-driven presence input for scene power policies.
- [ ] Do real-world validation of circadian behavior across mixed-range rooms and document any group-layout expectations that fall out of the planner.
- [ ] Decide whether room-coherent circadian output needs an explicit mode, or whether overlapping Hue groups are sufficient for the intended experience.
- [ ] Add telemetry/counters for circadian apply attempts/failures if log-based observability stops being sufficient.

### 4) Core control coordination and no-popcorning behavior
Reference: `planning/control-batching.md`
- [ ] Ensure coordinated execution semantics for mixed actions in a room scene apply.
- [ ] Validate cross-bridge timing behavior and define acceptable skew.
- [ ] Add explicit failure surface for partial bridge failures during scene apply.
- [ ] Decide and document executor mode defaults (`:append` vs `:replace`) per call path.
- [ ] Add end-to-end tests proving expected behavior with 10+ light scene patterns.

### 5) Close known runtime gaps
- [ ] Implement Caseta group dispatch path in `Hueworks.Control.Group`.
- [ ] Resolve HA group fan-out edge cases currently noted in subscription code.
- [ ] Add regression tests for both items above.

## Next

### 6) Bridge credential lifecycle
- [ ] Support editing bridge host/credentials safely without destructive re-setup.
- [ ] Re-test credentials from UI after edit and gate save on validation.
- [ ] Add migration-safe credential update flow for Caseta cert/key paths.

### 7) Reimport and idempotency polish
Reference: `planning/import-resync.md`
- [ ] Finalize and document deletion semantics (disabled vs removed) during reimport.
- [ ] Persist/import history queries for operator-facing visibility.
- [ ] Add stronger tests around preserving user edits during reimport.

### 8) DB integrity and query health follow-up
Reference: `planning/db-integrity.md`
- [ ] Audit FK behavior vs manual cleanup code for consistency.

## Later

### 9) Room assignment intelligence
- [ ] Extract room derivation into a dedicated module.
- [ ] Add confidence scoring and suggested assignment review.
- [ ] Improve unassigned/cross-bridge room handling UX.

### 10) Scene UX improvements
- [ ] Scene preview/dry-run mode before apply.
- [ ] Scene activation history and error summaries in UI.
- [ ] Bulk scene operations per room.

### 11) Security and operations
- [ ] Add security hardening planning doc once scope is finalized.
- [ ] Encrypt bridge credentials at rest.
- [ ] Harden file permissions and backup handling for secrets/material.

### 12) Product expansion
- [ ] Additional bridge integrations beyond Zigbee2MQTT.
- [ ] Public API surface (WebSocket/REST) for external control.
- [ ] Multi-user/auth model for non-single-operator deployments.

### 13) HomeKit bridge integration
Reference: `planning/homekit-bridge.md`
- [ ] Add a HomeKit bridge endpoint that exposes HueWorks-controlled lights.
- [ ] Map HomeKit characteristic writes to HueWorks desired-state -> planner/executor flow.
- [ ] Mirror physical-state updates back to HomeKit characteristics for state coherence.
- [ ] Add pairing/persistence, room/accessory metadata mapping, and regression tests.

### 14) Home Assistant reverse integration (HueWorks -> HA)
Reference: `planning/home-assistant-reverse-integration.md`
- [ ] Expose HueWorks-controlled lights into Home Assistant as entities.
- [ ] Map HA service calls/state writes to HueWorks desired-state -> planner/executor flow.
- [ ] Publish HueWorks physical state updates back into HA entity state.
- [ ] Add config/discovery lifecycle, metadata mapping, and regression tests.
- [ ] Define and enforce HA parity quality bar (state coherence, interaction latency, reliability) for daily control paths.

### 15) Assisted-user functionality polish
Reference: `planning/assisted-user-functionality.md`
- [ ] Add high-impact guardrails for scene/control conflict predictability.
- [ ] Improve active-scene clarity (state + deactivation reasons) in room UX.
- [ ] Add plain-language runtime status to increase day-to-day user confidence.
- [ ] Prioritize outcome-focused scene usability improvements over setup automation.

## Quality Gates
- [ ] Keep TODO and planning docs synchronized when priorities change.
- [ ] Keep tests green on every merge (`mix test`).
- [ ] Keep static checks clean (`mix credo`).
- [ ] Require migration verification for schema changes.
- [ ] Keep docs in sync with implementation each sprint.

## Additional Tasks
- [ ] Add configurable on/off transition-time support and expose it as scene-level configuration.
