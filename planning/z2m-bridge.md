# Zigbee2MQTT Bridge Phase 2 (Planned)

## Goal
Expand the existing Zigbee2MQTT integration with stronger identity handling, better resilience, and broader device support while keeping the control pipeline behavior predictable.

## Scope
- Harden device identity handling when Z2M friendly names change.
- Improve reconnect/offline behavior and startup state consistency.
- Expand support beyond core light controls where it adds clear value.
- Add broader multi-device/multi-group regression coverage based on real-world topologies.

## Phase 2 Work Items

### 1) Identity Stability
- Add explicit IEEE-backed identity reconciliation when a device `friendly_name` changes.
- Ensure reimport/resync preserves user-edited metadata (display names, room assignments, overrides).
- Add conflict handling for duplicate or renamed entities discovered in the same import cycle.

### 2) Group and Topology Validation
- Add multi-light Z2M group integration tests with mixed capability/range devices.
- Validate planner grouping behavior under real-world mixed-range kelvin targets.
- Add regression coverage for group fan-out updates coming from MQTT state messages.

### 3) MQTT Reliability and Safety
- Add explicit offline/online handling from Z2M availability/LWT topics.
- Define reconnect + backoff behavior and add tests for repeated broker disconnects.
- Guard startup/bootstrap behavior against stale retained messages.

### 4) Credentials and Transport Hardening
- Add first-class TLS MQTT credential support where needed for production deployments.
- Validate credential update behavior for running subscriptions without destructive resets.
- Document secure credential recommendations for broker auth in production.

### 5) Capability Expansion (Post-Core)
- Evaluate optional support for RGB/effects payloads behind explicit feature gates.
- Define remote/button event handling approach and mapping entrypoint.
- Keep advanced Z2M-specific features opt-in until core reliability targets are met.

## Testing Plan
- Unit:
  - identity reconciliation helpers
  - topic/availability parsing
  - capability expansion payload parsing
- Integration:
  - import/resync with rename scenarios
  - reconnect/offline lifecycle behavior
  - group state fan-out and planner/executor interactions for mixed topologies
- Regression:
  - real fixture-based tests for strip drivers and mixed brightness/temp support devices

## Open Questions
- Should friendly-name rename detection auto-merge, or require explicit operator confirmation in ambiguous cases?
- Do we require TLS support before first production deployment, or treat it as an immediate follow-up?
- Which Z2M advanced capabilities are worth phase-2 support vs. deferring to Home Assistant integrations?
