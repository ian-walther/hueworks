# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

## Now (Critical Path)

### 1) HomeKit bridge integration
Reference: `planning/homekit-bridge.md`
- [ ] Add a HomeKit bridge endpoint using the `hap` dependency as-is.
- [ ] Expose HueWorks-controlled lights as HomeKit accessories for second-device testing.
- [ ] Expose HueWorks scenes as virtual HomeKit switches with per-room active-scene exclusivity.
- [ ] Map HomeKit writes to HueWorks desired-state -> planner/executor flow.
- [ ] Mirror physical-state and active-scene updates back to HomeKit.
- [ ] Add stable bridge identity/pairing persistence and HAP-child restart handling for topology changes.
- [ ] Add integration and manual verification coverage for pairing, light control, and scene-switch behavior.

### 2) Reimport and idempotency polish
Reference: `planning/import-resync.md`
- [ ] Guarantee that a reimport with unchanged upstream data and unchanged operator selections is a true no-op.
- [ ] Finalize and document deletion semantics (disabled vs removed) during reimport.
- [ ] Persist/import history queries for operator-facing visibility.
- [ ] Add stronger tests around preserving user edits during reimport.

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

### 7) DB integrity and query health follow-up
Reference: `planning/db-integrity.md`
- [ ] Audit FK behavior vs manual cleanup code for consistency.

## Later

### 8) Room assignment intelligence
- [ ] Extract room derivation into a dedicated module.
- [ ] Add confidence scoring and suggested assignment review.
- [ ] Improve unassigned/cross-bridge room handling UX.

### 9) Scene UX improvements
- [ ] Scene preview/dry-run mode before apply.
- [ ] Scene activation history and error summaries in UI.
- [ ] Bulk scene operations per room.
- [ ] Add configurable on/off transition-time support and expose it as scene-level configuration.

### 10) Security and operations
- [ ] Add security hardening planning doc once scope is finalized.
- [ ] Encrypt bridge credentials at rest.
- [ ] Harden file permissions and backup handling for secrets/material.

### 11) Product expansion
- [ ] Additional bridge integrations beyond Zigbee2MQTT.
- [ ] Public API surface (WebSocket/REST) for external control.
- [ ] Multi-user/auth model for non-single-operator deployments.

### 12) Home Assistant reverse integration (HueWorks -> HA)
Reference: `planning/home-assistant-reverse-integration.md`
- [ ] Tighten exported-entity parity for daily-control paths across lights, scenes, and room selectors.
- [ ] Finalize capability-policy decisions so exported entities stay predictable in HA dashboards and automations.
- [ ] Improve republish/recovery behavior and operator visibility around MQTT export state.
- [ ] Define and enforce HA parity quality bar (state coherence, interaction latency, reliability) for daily control paths.

### 13) Assisted-user functionality polish
Reference: `planning/assisted-user-functionality.md`
- [ ] Add high-impact guardrails for scene/control conflict predictability.
- [ ] Improve active-scene clarity (state + deactivation reasons) in room UX.
- [ ] Add plain-language runtime status to increase day-to-day user confidence.
- [ ] Prioritize outcome-focused scene usability improvements over setup automation.
