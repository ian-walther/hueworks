# Pre-Release Refinement

## Goal

Prepare HueWorks for a source-available public release by making a clean installation understandable, safe to operate, honest about integration state, and useful without private setup knowledge.

The release gate is a real clean-setup rehearsal. The owner must be able to start a fresh local development instance with an empty database and credential directory, no bridge seeds, and no copied production credentials; connect the real household integrations through the UI; import entities; create a useful scene; and control it without an undocumented workaround, database edit, source inspection, or log archaeology.

The core planner, executor, scene semantics, import ownership model, and reimport safety contract are not redesign targets unless the rehearsal exposes a domain defect.

## Desired Outcome

- Every advertised bridge has a source-appropriate setup journey with validation before persistence.
- The recommended first-run journey uses Home Assistant as an inventory and migration assistant while HueWorks remains the durable lighting owner.
- The UI connects to Home Assistant for inventory before native setup, but imports native bridge entities before Home Assistant-only entities.
- A successful initial setup leads through HueWorks Area review, source-space mapping, and first-scene creation.
- Runtime status distinguishes saved configuration from live availability without claiming precision a transport cannot provide.
- Optional integrations remain outside the minimum successful setup path.
- Installation, upgrades, rollback, troubleshooting, compatibility, and limitations are documented for an owner who did not build the app.
- Desktop and mobile workflows have intentional empty, loading, error, success, and destructive states.
- The trusted-LAN security boundary is prominent and never confused with public-Internet readiness.

## Remaining Release Blockers

### Home Assistant Browser Authorization

Local `_home-assistant._tcp.local` discovery and stable instance selection are available, but the normal path still requires a manually supplied long-lived token. Browser authorization must replace token handling in the primary journey.

Required direction:

- Redirect through Home Assistant's authorization-code flow using client and callback URLs derived from HueWorks' configured canonical browser URL.
- Detect a missing or unusable LAN callback URL before redirecting.
- Validate callback state, reject replay, handle denial/cancellation, and avoid partial bridge rows.
- Persist refresh-token credentials and short-lived access-token metadata without displaying them.
- Add one shared token provider used by import, control, connection validation, and event streams. No caller should continue reading a permanent token directly from `Bridge.Credentials`.
- Refresh before expiry, retry once after authentication failure, and surface reauthorization when refresh is revoked or permanently rejected.
- Extend Home Assistant host handling to preserve explicit `http`/`https` and produce matching REST and WebSocket URLs instead of assuming plain HTTP.
- Keep manual URL and long-lived-token entry as an advanced recovery path with an explicit non-refreshable warning.
- Validate the authorized connection with the APIs required by import before persisting.
- Test multiple instances, duplicate identity, callback mismatch, invalid/replayed state, denial, exchange failure, refresh, concurrent refresh, revoked refresh token, reauthorization, and credential redaction.

### Guided Caseta Pairing

Caseta import and control can validate uploaded LEAP credentials, but certificate acquisition still requires external technical work.

Required direction:

- Wrap the reverse-engineered `pylutron-caseta` pairing module behind a pinned, machine-readable helper protocol rather than scraping an interactive CLI.
- Report discovery, readiness for physical button press, success, bounded errors, timeout, and cancellation as distinct states.
- Stage generated CA certificate, client certificate, and private key with restrictive permissions.
- Perform the existing safe LEAP validation before atomically moving credentials and persisting the bridge.
- Delete partial credentials after failure, cancellation, timeout, or LiveView termination, and never log PEM contents.
- Keep manual certificate upload as an advanced recovery path.
- Record dependency license/provenance and tested bridge models.
- Test multiple discoveries, button timeout, malformed helper output, helper crash, validation failure, cleanup, cancellation, duplicate identity, and credential redaction.

### Guided Zigbee2MQTT Assistance

Manual MQTT configuration and reuse of Home Assistant-export settings are supported. Discovery and multiple-instance assistance remain.

Required direction:

- Discover brokers only through advertised `_mqtt._tcp` services; never scan arbitrary hosts or ports.
- Treat discovery as optional because it cannot identify a base topic or broker credentials reliably.
- Try the standard `zigbee2mqtt` base topic first after an explicit broker choice.
- Where practical, use narrowly scoped retained bridge metadata to offer additional base-topic candidates without subscribing indefinitely to `#`.
- If one instance validates, prefill it. If several validate, present coordinator identity and bridge metadata for selection.
- Never reveal a stored MQTT password while reusing it.
- State clearly in setup that MQTT-over-TLS is not currently supported.
- Test multiple brokers/instances, custom base topics, restricted subscriptions, timeouts, missing/malformed retained topics, and secret redaction.

### Discovery In Production Topology

Native-development mDNS success is not sufficient. Verify Hue and Home Assistant discovery from the primary Docker topology and document when container networking blocks multicast. Manual fallback must remain usable without discarding setup work.

## Workflow Refinements

### Import Ordering And Duplicate Transparency

Canonical duplicate recognition is directional: a Home Assistant wrapper can be recognized after its native source exists, while importing the native source after its HA wrapper can leave visible twins.

- Distinguish HA inventory from HA entity import throughout the UI: inventory happens first, entity materialization happens last.
- Explain that HA mirrors may remain as hidden topology bookkeeping when linked after native import.
- Keep automatic linking disclosed rather than invisible.
- Use ExternalSpaceMappings to preselect destinations for new entities without changing the reimport rule that existing entity placement is authored HueWorks intent.

### Scene Onboarding

- Keep live preview available without making activation destructive or surprising.

### Circadian Basic And Advanced Modes

- Add concise plain-language explanations for brightness timing, temperature timing, solar-relative versus fixed windows, offsets, and fallback behavior.
- Consider a Basic mode with a useful preset and an Advanced mode preserving the full editor.
- Never silently discard advanced values when switching presentation modes.
- Validate presets against real sunrise, daytime, sunset, and overnight behavior before treating them as release defaults.

## Runtime Trust And Diagnostics

### Bridge And Integration Status

The app needs one truthful operator-facing status model without creating a second control or persistence architecture.

- Define the common minimum status vocabulary across bridge transports: configured, runtime worker present, last successful event or request where known, retrying, and actionable error.
- Do not label a transport `connected` merely because a manager or child process is alive.
- Expose status on bridge cards and integration panels with timestamps and recovery actions.
- Distinguish Home Assistant MQTT-export configuration from live broker availability.
- Distinguish HomeKit runtime configuration, HAP availability, and saved pairing.
- Keep detailed payloads, credentials, and sensitive topology out of status projections.

### Human Support Information

- Add a diagnostics surface that shows version, database/core readiness, bridge/integration summaries, recent sanitized errors, last successful import/reimport, and useful next actions.
- Provide a copyable sanitized support summary.
- Link to relevant config and troubleshooting actions rather than requiring log or database access.
- Keep the authenticated AI API as deeper optional diagnostics, not the only way to understand ordinary failures.

## Public Presentation And Documentation

- Add screenshots for first run, import/reimport, scene creation, Control, and integration configuration.
- Add intentional favicon/application icons and release metadata.
- Document source-build upgrades, prod-branch deployment, rollback, backup selection, restore, and post-upgrade verification as one coherent operator procedure.
- Decide whether the first release publishes tagged container images or remains source-build-only.
- Add a changelog/release-note policy when public versioning begins.
- Keep compatibility and known-limitations documentation synchronized with tested versions and hardware.
- Reduce or clearly separate dependency deprecation noise so project-owned warnings remain visible during a clean build.

## UI And Accessibility Refinements

- Verify keyboard order, focus-visible treatment, modal focus trapping/restoration, disabled states, and touch targets.
- Verify setup, import, scene building, Integrations, Control, and Lights at narrow mobile, tablet, and desktop widths.
- Keep long identifiers, tokens, source IDs, errors, and environment snippets wrapped or horizontally scrollable without page overflow.
- Correct any remaining Pico copy that implies one control group or all groups rather than an arbitrary selected list.
- Keep destructive operations separated and confirmed, including bridge/entity deletion, HomeKit pairing reset, token rotation, and database restore.

## State Coverage Matrix

Every primary workflow must intentionally handle:

- Bridge discovery loading, none found, multiple found, duplicate identity, authorization/pairing pending, timeout, cancellation, validation failure, and success.
- Initial import loading, authentication/protocol failure, empty result, review, apply failure, and success.
- Reimport no changes, bridge-owned-only refresh, new/missing entities, duplicates, warnings, destructive resolutions, stale review, and success.
- No Areas, empty Areas, unassigned entities, Areas without scenes, and Areas without controllable lights.
- HA inventory with no Floors/Areas, one broad Area, nested Floor/Area candidates, unassigned entities, multiple HA instances, and unavailable registry commands.
- External-space mapping with many-to-one mappings, source renames, partial identifier coverage, conflicting evidence, intentionally unmapped source spaces, and stale mappings.
- Scene builder with no available lights, unassigned lights, duplicate assignments, embedded custom state, saved state, preview, and activation failure.
- Runtime bridge disconnection, recovery, stale physical state, and unknown physical state.
- Integration disabled, configured but unavailable, running, and error states.
- Backup failure, migration failure, corrupt restore input, successful restore, and rollback.

Public errors should identify what failed, what was preserved, and the next safe action. Raw `inspect/1` output must not be the primary user-facing vocabulary.

## Release-Gate Verification

After the remaining source-specific setup blockers are implemented, repeat the complete first-run journey from an empty database and credential directory without bridge seeds or copied production credentials. The owner should be able to use HA-assisted or direct setup, pair every advertised source through supported UI paths, import native sources before selected HA-only entities, create and activate a useful scene, restart cleanly, and understand any failure without source inspection or database edits.

The pending Area/onboarding production rollout has its exact preflight, backup, validation, smoke-test, and rollback procedure in [`area-onboarding-rollout.md`](area-onboarding-rollout.md). Do not deploy that migration until the runbook's target and fresh backup are explicitly approved.

### Hardware Smoke

- Exercise representative Hue, Caseta, Home Assistant, and Zigbee2MQTT control/event paths.
- Activate manual, circadian, presence-driven, force-on, and force-off scenes.
- Verify Pico on/off/toggle/scene bindings and multiple-target control groups.
- Verify Home Assistant MQTT discovery, scene selection, light/group opt-in, and Presence Input writes.
- Verify HomeKit on/off and document brightness/color results without overstating support.
- Force bridge outages and verify status, retry, recovery, and unknown physical state.

## Release Readiness Criteria

HueWorks is a public release candidate when:

- The clean Docker path and fresh local hardware rehearsal both pass.
- Every advertised bridge has either a complete source-native setup path or an explicitly scoped, documented release decision.
- HA-assisted setup can inventory first, map Areas, import native sources, and import HA-only entities last without undocumented intervention.
- Native-before-Home-Assistant materialization and reverse-order risk are visible before import.
- Direct setup without Home Assistant remains complete and tested.
- ExternalSpaceMappings guide future new-entity placement without changing existing Area assignments.
- Runtime/configuration state is truthful and ordinary failures are diagnosable in the UI.
- Database upgrades and restore have passed production-shaped recovery testing.
- Supported/tested configurations and known limitations are explicit.
- The primary desktop and mobile workflows pass the state and accessibility matrix.
- The trusted-LAN security boundary is prominent in installation docs and the application.

## Non-Goals

- Do not add public-Internet authentication incidentally. Remote exposure requires a separate system-wide security design.
- Do not redesign core planning, execution, scene, or reimport semantics without evidence of a domain defect.
- Do not make HomeKit brightness/color reliability a blocker if on/off is presented as the stable capability.
- Do not force every user through a rigid wizard when state-derived contextual guidance works.
- Do not require Home Assistant, HomeKit, Picos, circadian behavior, Presence Inputs, or the AI API for basic installation.
- Do not make Home Assistant the durable owner of HueWorks Areas, entity placement, topology, scene intent, or control behavior.
- Do not continuously synchronize HA spatial changes into existing HueWorks Area assignments.
- Do not introduce recursive HueWorks Areas as part of the terminology rename or first-run setup work.
- Do not turn diagnostics into a second persistence or control architecture.
- Do not replace semantic tests with broad pixel-perfect screenshot testing.

## Open Product Decisions

- Whether tagged container images ship with the first release or Docker Compose remains source-build-only.
- Whether the Caseta helper is bundled into the primary image or shipped as a companion after measuring image size, maintenance, licensing, and security tradeoffs.
- Which transport-specific runtime facts can support a common status vocabulary without misleading precision.
- Whether the first release includes a Basic circadian preset or documents the full editor as an expert feature.
- Whether public versioning starts at `0.1.0` or a new initial release version, and when changelog/compatibility guarantees begin.
