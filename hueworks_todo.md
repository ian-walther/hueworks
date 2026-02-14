# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

## Now (Critical Path)

### 1) Core control coordination and no-popcorning behavior
Reference: `planning/control-batching.md`
- [ ] Ensure coordinated execution semantics for mixed actions in a room scene apply.
- [ ] Validate cross-bridge timing behavior and define acceptable skew.
- [ ] Add explicit failure surface for partial bridge failures during scene apply.
- [ ] Decide and document executor mode defaults (`:append` vs `:replace`) per call path.
- [ ] Add end-to-end tests proving expected behavior with 10+ light scene patterns.
- [ ] Align and update `planning/control-batching.md` to reflect actual remaining work.

### 2) Close known runtime gaps
- [ ] Implement Caseta group dispatch path in `Hueworks.Control.Group`.
- [ ] Replace Caseta Pico stub event logging with real event handling + mapping entrypoint.
- [ ] Resolve HA group fan-out edge cases currently noted in subscription code.
- [ ] Add regression tests for all three items above.

### 3) Subscription test coverage
Reference: `planning/test-coverage.md`
- [ ] Add parser + mapper tests for Hue SSE event handling.
- [ ] Add Home Assistant websocket event-flow tests (auth, subscribe, state_changed).
- [ ] Add Caseta LEAP connection/event parsing tests.
- [ ] Add failure/reconnect tests for all subscription supervisors.
- [ ] Update `planning/test-coverage.md` with concrete remaining test targets.

## Next

### 4) Circadian and active-scene behavior hardening
- [ ] Define expected circadian re-apply semantics for active scenes.
- [ ] Add tests for `brightness_override` behavior under manual changes.
- [ ] Add safeguards against redundant scene re-application churn.
- [ ] Introduce basic observability (logs/metrics) for circadian ticks and apply outcomes.

### 5) Bridge credential lifecycle
- [ ] Support editing bridge host/credentials safely without destructive re-setup.
- [ ] Re-test credentials from UI after edit and gate save on validation.
- [ ] Add migration-safe credential update flow for Caseta cert/key paths.

### 6) Reimport and idempotency polish
Reference: `planning/import-resync.md`
- [ ] Finalize and document deletion semantics (disabled vs removed) during reimport.
- [ ] Persist/import history queries for operator-facing visibility.
- [ ] Add stronger tests around preserving user edits during reimport.
- [ ] Update `planning/import-resync.md` to match the current implementation and remaining gaps.

### 6.5) DB integrity and query health follow-up
Reference: `planning/db-integrity.md`
- [ ] Verify import-history/status query paths and add any missing targeted indices.
- [ ] Audit FK behavior vs manual cleanup code for consistency.
- [ ] Add migration review checklist and link it from README/planning.

## Later

### 7) Room assignment intelligence
- [ ] Extract room derivation into a dedicated module.
- [ ] Add confidence scoring and suggested assignment review.
- [ ] Improve unassigned/cross-bridge room handling UX.

### 8) Scene UX improvements
- [ ] Scene preview/dry-run mode before apply.
- [ ] Scene activation history and error summaries in UI.
- [ ] Bulk scene operations per room.

### 9) Security and operations
- [ ] Add security hardening planning doc once scope is finalized.
- [ ] Encrypt bridge credentials at rest.
- [ ] Harden file permissions and backup handling for secrets/material.
- [ ] Add deployment/runbook docs for restore and recovery procedures.

### 10) Product expansion
- [ ] Additional bridge integrations (first target: Zigbee2MQTT).
- [ ] Public API surface (WebSocket/REST) for external control.
- [ ] Multi-user/auth model for non-single-operator deployments.

## Quality Gates
- [ ] Keep TODO and planning docs synchronized when priorities change.
- [ ] Keep tests green on every merge (`mix test`).
- [ ] Keep static checks clean (`mix credo`).
- [ ] Require migration verification for schema changes.
- [ ] Keep docs in sync with implementation each sprint.
