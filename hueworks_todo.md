# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

## Now (Critical Path)

### 1) Circadian prerequisites and adaptive circadian logic
Reference: `planning/circadian-adaptation.md`
- [ ] Implement circadian calculation module (using the existing HA-compatible config model).
- [ ] Add circadian `light_state` apply path for both brightness and kelvin.
- [ ] Enforce active-scene semantics:
  - manual power-off stays off until manual-on.
  - manual power-on applies current circadian target immediately.
- [ ] Wire circadian calculator reads to global solar config from `AppSettings`.
- [ ] Add deep circadian math tests and targeted scene integration regressions.
- [ ] Add basic observability for circadian ticks and apply outcomes.

### 2) External scene mapping (Home Assistant -> HueWorks)
Reference: `planning/external-scenes.md`
- [ ] Add generic external scene model (`external_scenes`) with source-scoped identity.
- [ ] Add scene mapping model linking external scenes to HueWorks scenes.
- [ ] Extend HA import/resync to include `scene.*` entities.
- [ ] Add UI to review/sync external scenes and manage mappings.
- [ ] Subscribe to HA scene activation events and trigger mapped HueWorks scenes.
- [ ] Add tests for sync, mapping resolution, and activation event flow.

### 3) Production deployment baseline (Docker)
Reference: `planning/prod-deploy.md`
- [ ] Finalize Docker runtime contract (env vars, volumes, ports).
- [ ] Add release migration workflow for deploys/upgrades.
- [ ] Add compose-based baseline deployment path.
- [ ] Add backup/restore and upgrade runbook docs.
- [ ] Add production smoke-check checklist.

### 4) Core control coordination and no-popcorning behavior
Reference: `planning/control-batching.md`
- [ ] Ensure coordinated execution semantics for mixed actions in a room scene apply.
- [ ] Validate cross-bridge timing behavior and define acceptable skew.
- [ ] Add explicit failure surface for partial bridge failures during scene apply.
- [ ] Decide and document executor mode defaults (`:append` vs `:replace`) per call path.
- [ ] Add end-to-end tests proving expected behavior with 10+ light scene patterns.

### 5) Close known runtime gaps
- [ ] Implement Caseta group dispatch path in `Hueworks.Control.Group`.
- [ ] Replace Caseta Pico stub event logging with real event handling + mapping entrypoint.
- [ ] Resolve HA group fan-out edge cases currently noted in subscription code.
- [ ] Add regression tests for all three items above.

### 6) Subscription test coverage
Reference: `planning/test-coverage.md`
- [ ] Add parser + mapper tests for Hue SSE event handling.
- [ ] Add Home Assistant websocket event-flow tests (auth, subscribe, state_changed).
- [ ] Add Caseta LEAP connection/event parsing tests.
- [ ] Add failure/reconnect tests for all subscription supervisors.

## Next

### 7) Bridge credential lifecycle
- [ ] Support editing bridge host/credentials safely without destructive re-setup.
- [ ] Re-test credentials from UI after edit and gate save on validation.
- [ ] Add migration-safe credential update flow for Caseta cert/key paths.

### 8) Reimport and idempotency polish
Reference: `planning/import-resync.md`
- [ ] Finalize and document deletion semantics (disabled vs removed) during reimport.
- [ ] Persist/import history queries for operator-facing visibility.
- [ ] Add stronger tests around preserving user edits during reimport.

### 8.5) DB integrity and query health follow-up
Reference: `planning/db-integrity.md`
- [ ] Verify import-history/status query paths and add any missing targeted indices.
- [ ] Audit FK behavior vs manual cleanup code for consistency.
- [ ] Add migration review checklist and link it from README/planning.

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
- [ ] Add deployment/runbook docs for restore and recovery procedures.

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
- [ ] Improve bridge seed secrets model to support arbitrary credential sets (for example `HUE_API_KEY_1`, `HUE_API_KEY_2`) instead of fixed env var names.
- [ ] Evaluate and potentially implement a `secrets.json`-driven initial bridge seed flow so bridge config and credentials can be sourced from one structured file.
- [ ] Add initial seeding support for Zigbee2MQTT bridges/entities.
- [ ] Add configurable on/off transition-time support and expose it as scene-level configuration.
- [ ] Move GenServer modules into a top-level `hueworks_app` folder alongside `hueworks` and `hueworks_web`.
