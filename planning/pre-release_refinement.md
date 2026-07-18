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

## First-Run Setup And Spatial Model

### `Room` To `Area` Cutover

`Room` was too narrow for HueWorks' top-level lighting coordination boundary. A HueWorks coordination boundary may represent one physical room, several rooms in an open floor plan, or an entire floor. The product and domain term is now `Area`.

The rename is a discrete prerequisite to the setup work and must land atomically before external-space mapping or the guided setup flow. It is a terminology and schema migration, not a control-semantics redesign.

Required scope:

- Rename the HueWorks domain concept, schemas, associations, foreign keys, contexts, UI copy, routes, API/MCP vocabulary, tests, and documentation coherently rather than maintaining parallel Room and Area concepts.
- Migrate every existing Room and relationship one-to-one without changing entity placement, scene ownership, active scenes, Presence Inputs, Pico configuration, or control behavior.
- Replace browser routes, API fields and operations, MCP tools and arguments, MQTT command/state/attribute topics, exported attribute names, domain events, and runtime vocabulary with Area terminology. Do not retain old browser redirects, parameter aliases, route aliases, dual subscriptions, or deprecated Room-shaped runtime APIs.
- Keep HueWorks Areas flat. This rename does not introduce recursive Areas, nested scene composition, or a second grouping model.
- Use source-qualified labels during setup, such as `HA floor`, `HA area`, `Hue room`, `Caseta area`, and `HueWorks area`, so similarly named concepts remain understandable.
- Treat successful migration of the existing production database as a hard acceptance requirement, not a best-effort cleanup task.
- Take a verified production database snapshot immediately before the migration/deploy. Do not run the migration without a restorable snapshot and recorded snapshot path.
- Rehearse the exact migration against a fresh copy of the production database before the real deployment and inspect the migrated copy deeply.
- Backfill every newly required column and persisted external identity for all existing rows inside the migration transaction before applying `NOT NULL` or uniqueness constraints. Do not rely on application startup, first export, or lazy reads to repair migrated rows.
- Verify production-shaped data before rollout, including Areas, lights, groups, scenes, active scenes, Presence Inputs, Pico bindings, exports, and API identifiers.
- Treat rollback across the atomic rename as database restore plus prior application revision unless the completed implementation proves backward compatibility. Do not assume the pre-migration application can run safely against the migrated schema.

### Persisted External Identity

Externally published durable identity must be stored rather than regenerated from current naming conventions on every export. Product terminology and transport vocabulary may evolve without recreating an existing external entity.

Rules:

- Generate each durable external identity once, persist the final published value, and reuse that exact value for the life of the owning record.
- Backfill existing records with the exact identifiers they published before the Room-to-Area rename. Existing values containing `room` remain inert persisted data, not a legacy runtime model.
- Generate identities for new Areas using the new Area convention. Runtime code must read the stored value rather than branch on record age or infer which naming convention applies.
- Keep stored identities opaque, immutable, unique within their external namespace, and unavailable for ordinary user editing.
- A rename, display-name change, source-space remap, or Room-to-Area migration must never change a stored external identity.
- Deleting an owning record may retire its identity, but an identity must not be silently regenerated for an existing record when missing or invalid. Treat that as a repairable integrity error.
- Store only values that external systems use as durable identity. Ordinary display labels, command paths, payload attribute names, and internal/API vocabulary should use current Area terminology and remain independently changeable.
- Do not preserve old browser paths, API/MCP names, MQTT command paths, or payload fields merely because a durable external identifier contains the old word.

Home Assistant export requirements:

- Persist the Area-level HA discovery identity used by the scene selector and the HA device identifier shared by Area scenes, lights, groups, and Presence Inputs.
- Backfill current Areas with their exact existing `hueworks_room_*` identity values so HA updates the same registry entities and devices during the rename.
- Generate `hueworks_area_*` identity values for Areas created after the rename.
- Publish renamed Area command/state/attribute topics and Area-shaped attributes under the preserved discovery identity so existing HA entities update in place.
- If the retained MQTT discovery topic itself depends on the discovery identity, derive that topic only from the stored final discovery value rather than reconstructing an old or new convention.
- Verify retained discovery updates against a production-shaped HA registry and ensure the rename neither creates duplicate entities nor strands retained Room-era discovery records.

HomeKit accessory serials currently identify lights, groups, and scenes rather than the former Rooms. Verify that no Room-derived HAP identity exists before migration; if one is found, preserve it through the same persisted-identity rule rather than adding a compatibility route or alternate Room model.

### Product Role Of Home Assistant

The recommended user story is migration of lighting ownership from Home Assistant into HueWorks. Home Assistant is used to describe the user's existing integrations and spatial organization, not to become HueWorks' durable source of lighting intent or topology.

Rules:

- Offer `Use Home Assistant to guide setup` as the recommended first-run choice and `Set up HueWorks directly` as a fully supported alternative.
- Connect and authorize Home Assistant early enough to build an inventory, but do not materialize HA light entities before native bridge setup.
- Read HA config entries, entity and device registries, Areas, Floors, states needed for capability discovery, and stable physical identifiers where available.
- Resolve HA placement using an entity's explicit Area first and its device Area only as a fallback, matching HA's override semantics.
- Use the inventory to identify likely native sources, HA-only entities, source relationships, and spatial placement candidates.
- Pair supported Hue, Caseta, and Zigbee2MQTT sources directly with HueWorks and import their native entities first.
- Import selected ZHA, template, virtual, and otherwise HA-only entities only after native imports and duplicate matching are available.
- Keep HueWorks as the owner of Areas, entity placement, scenes, desired state, planning, optimization, and control behavior.
- If no HA-only entities remain, continued HA connectivity is optional. Disconnecting HA must not delete HueWorks Areas, source-space mappings, native entities, or authored configuration.
- If HA-only entities are imported, make their ongoing HA runtime dependency explicit without implying that HA owns the rest of the configuration.

### Guided, Resumable Setup

First run should auto-open a dedicated setup workspace when configuration is empty. The workspace should provide one obvious happy path without becoming a rigid modal wizard or a second persistence architecture.

Required behavior:

- Derive progress from committed HueWorks configuration wherever possible.
- Persist only the minimal onboarding state needed to remember an explicit completion or dismissal and the selected setup path; do not store a parallel copy of bridge/import configuration.
- Allow the user to leave for normal Config pages at any point without losing completed work.
- Show a resumable setup callout until the user explicitly finishes or dismisses setup.
- Reuse source-specific pairing, validation, preview, and import domain operations rather than duplicating them inside the setup UI.
- Permit advanced users to skip or reorder steps, while keeping the recommended sequence and its consequences visible.
- Preserve manual URLs, credentials, and direct setup as advanced recovery paths when discovery or authorization is unavailable.

Recommended HA-assisted sequence:

1. Configure HueWorks location and canonical browser URL requirements.
2. Discover and authorize one Home Assistant instance.
3. Inventory HA integrations, Floors, Areas, lighting entities, physical identifiers, and likely native sources without importing HA entities.
4. Review proposed HueWorks Areas and map HA Floors and Areas into them.
5. Pair, validate, map, and import each supported native bridge.
6. Review unmatched and HA-only entities, then import only the selected remainder through HA.
7. Review final Area placement and duplicate/link outcomes.
8. Create, preview, save, and activate a first useful scene.
9. Configure optional HueWorks exports back to Home Assistant.
10. Finish setup and continue to Control.

Recommended direct sequence:

1. Configure HueWorks location.
2. Create HueWorks Areas manually or derive candidates from the first native bridge preview.
3. Pair, validate, map, and import native bridges.
4. Review final Area placement.
5. Create, preview, save, and activate a first useful scene.
6. Finish setup and continue to Control.

### HueWorks Area Design From Home Assistant

Home Assistant's formal spatial hierarchy is Floor -> Area -> device/entity. HueWorks Areas are lighting coordination boundaries and need not match either HA level one-to-one.

The HA inventory step should propose, but never silently create, HueWorks Areas:

- For each HA Floor, allow `Use this floor as one HueWorks Area`, `Use its HA Areas separately`, or `Skip`.
- Present HA Areas without a Floor as individual candidates.
- Allow candidates to be merged into one HueWorks Area, renamed, mapped to an already-created Area, or skipped.
- Show how many relevant lights, groups, native integrations, and unresolved entities support each proposal.
- Apply the reviewed Area design before native bridge imports so later placement has stable HueWorks destinations.
- Do not require the user to reproduce HA's layout. A broad HA Area may map directly to a HueWorks Area, and several HA Areas may map to one HueWorks Area.

### External Spaces And Mappings

Spatial placement must be generalized across integrations rather than implemented as an HA-only feature.

Definitions:

- A HueWorks `Area` is an authored lighting coordination boundary.
- An `ExternalSpace` is a source-reported spatial concept such as an HA Floor, HA Area, Hue area, Caseta area, or another bridge's equivalent.
- An `ExternalSpaceMapping` is user-owned HueWorks intent that maps one ExternalSpace to one HueWorks Area for placement guidance.

Mapping rules:

- Many ExternalSpaces may map to one HueWorks Area.
- One ExternalSpace maps to at most one HueWorks Area. If its entities intentionally span several HueWorks Areas, leave the ExternalSpace unmapped and use per-entity placement choices.
- Persist mappings by source/bridge identity, external-space kind, and stable external ID, with the current external name retained only for display and rename diagnostics.
- A source rename must not break a mapping whose stable external ID is unchanged.
- A changed HA Area-to-Floor relationship may change future inherited Floor suggestions, but must not rewrite a direct HA Area mapping or any existing HueWorks entity placement. Disclose the changed hierarchy when it affects a review.
- Deleting or disconnecting a source must not move or delete existing HueWorks entities. Stale mappings should remain inspectable until explicitly removed or until their owning bridge is intentionally deleted.
- Mappings provide defaults only for new entities. They never move existing lights or groups during reimport.
- Editing a mapping affects future placement suggestions; moving existing entities remains a separate explicit HueWorks action.
- Existing bridge group membership remains bridge-owned topology and may diverge from HueWorks Area placement.

Placement precedence for a newly imported real entity:

1. An explicit destination selected in the current import review.
2. A non-conflicting exact mapping for the entity's own source space.
3. A non-conflicting placement inferred through a confidently matched HA counterpart and its mapped HA Area.
4. A mapped HA Floor inherited through the counterpart's HA Area when no Area-level mapping exists.
5. A unique normalized-name match to an existing HueWorks Area.
6. Unassigned, with an explicit choice required before import if the workflow requires Area membership.

When applicable sources imply different HueWorks Areas, show the evidence and require an explicit destination. Never resolve a mapping conflict by source priority, majority vote, or silently moving existing entities.

Unassigned real entities remain supported. Setup may finish with them when the user explicitly accepts the result, but the final review must disclose which entities will not participate in Area-scoped scenes and control until assigned.

### Native Bridge Mapping From HA Inventory

After the HA Area mapping is reviewed, each native bridge preview should try to correlate native entities with their HA wrappers using the same stable physical identifiers used for duplicate recognition.

- If all confidently matched members of a native source space resolve to the same HueWorks Area, propose that native space mapping and disclose match coverage.
- If only a subset matches but every matched member agrees, show the destination as a suggestion requiring confirmation rather than an automatic mapping.
- If matched members span HueWorks Areas, if identity is ambiguous, or if no reliable match exists, leave the native space unmapped and ask for a destination or per-entity choices.
- Fall back to normalized-name matching only after identifier-based evidence.
- Save confirmed native mappings with the native import so future entities discovered in that source space receive the same placement default.
- Do not require Home Assistant to remain connected for saved native mappings to continue working.

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

## Automated Verification Strategy

### Implementation And Rollout Contract

Implement the Area rename, persisted identity, external-space mapping, and guided setup as one long-running development task. Complete implementation, documentation, tests, production-shaped migration rehearsal, rollback rehearsal, and the deploy runbook without requiring an intermediate production deployment.

The final production deployment is a separate user-approved action. Reaching a green local result does not authorize touching the production checkout, database, container, or runtime. Stop after reporting the verified commit sequence, evidence, risks, backup/restore paths, and exact proposed deployment commands, then wait for explicit approval.

Commit structure must preserve the smallest practical rollback boundaries:

1. Additive persisted-identity prerequisites: add storage, backfill existing Room-era published values, constraints, and focused migration tests while keeping the pre-cutover Room application behavior working where practical.
2. Atomic Room-to-Area cutover: rename the schema and all application/runtime vocabulary together, remove old paths and compatibility code, and update export protocols to read persisted identity.
3. Additive external-space mapping schema and domain primitives.
4. HA inventory and cross-source mapping logic, with no guided UI dependency.
5. Guided first-run setup and source-specific UI orchestration.
6. Final documentation, acceptance coverage, and rollout tooling that cannot be placed more naturally with an earlier commit.

Commits may be split more finely when that improves review or rollback, but do not squash the additive data prerequisite, atomic rename, mapping foundation, and guided feature into one commit. Every commit after the atomic rename should be independently revertible while leaving the renamed schema and migrated data valid.

The atomic rename is the unavoidable compatibility boundary. Rolling back to a commit before that boundary requires restoring the pre-migration database snapshot. Rolling back only mapping or guided-setup commits should not require a database restore unless their own additive schema is explicitly removed.

Production-shaped rehearsal requirements:

- Obtain a new application-consistent production database snapshot for local testing without modifying production data or configuration.
- Preserve the snapshot byte-for-byte as the immutable rehearsal source and make disposable copies for every migration, startup, and rollback exercise.
- Record SQLite integrity, schema version, row counts, foreign-key checks, and relevant identity values before mutation.
- Run the exact commit-ordered migration sequence against a disposable copy using the real production entrypoint or equivalent migration command.
- Compare every required count, relationship, identity backfill, and retained import/configuration artifact after each migration boundary, not only at the final tip.
- Start the final application against a separate migrated copy and exercise the planned smoke path.
- Prevent the rehearsal application from connecting to or commanding real Hue, Caseta, Zigbee2MQTT, Home Assistant, HomeKit, MQTT, or other household services. Use an explicit runtime-I/O-disabled verification mode or equivalent enforced network isolation; do not rely on operator caution or assumptions that startup is read-only.
- Prove the isolation mechanism itself before starting the app against copied production data.
- Run the full automated suite and focused migration, identity, import, mapping, onboarding, API/MCP, MQTT export, and route-removal tests.
- Rehearse restoring the immutable pre-migration snapshot and starting the prior production revision.
- Rehearse reverting post-rename feature commits while retaining the renamed database, proving the intended feature rollback boundary.
- Leave the real production database, checkout, branch, containers, integrations, and lights untouched throughout rehearsal.

Before requesting deployment approval, produce one exact runbook covering:

1. Expected production revision and ordered commits.
2. Preflight health, branch, revision, disk-space, and SQLite checks.
3. Application-consistent snapshot command, destination, integrity verification, and retention.
4. Build and migration commands in their exact order.
5. Per-stage database assertions and expected counts/identities.
6. Application startup and health checks.
7. Area, scene, Pico, bridge, API/MCP, HA MQTT, HomeKit, and representative real-light smoke tests.
8. Stop conditions that trigger immediate rollback.
9. Feature-only rollback steps after the rename boundary.
10. Full pre-rename rollback steps using the snapshot and prior revision.

No production deployment command may run until the user explicitly approves that runbook and authorizes deployment.

### Clean-Install Acceptance

Automate as much of this path as practical from an empty database:

1. Migrations complete and `/health` reports ready.
2. `/` routes to first-run setup.
3. First run offers recommended HA-assisted setup and fully supported direct setup.
4. HA inventory proposes Areas without materializing HA light entities.
5. A fixture native bridge passes protocol-level validation and receives mapping suggestions from matched HA inventory.
6. Native entities materialize before selected HA-only entities, with duplicates linked in the supported direction.
7. Initial imports apply reviewed ExternalSpaceMappings and entity destinations without moving pre-existing entities.
8. An embedded custom scene persists untouched displayed defaults.
9. The scene activates and appears on Control.
10. Restarting resumes or completes onboarding from committed state without replaying completed imports.

Use domain and LiveView tests for semantics plus a small rendered-browser smoke path for browser-specific input behavior and critical navigation.

### Fresh Local Hardware Rehearsal

Preparation:

- Preserve the existing development database and credentials only as a restorable backup.
- Use an empty database, empty credential directory, no seed file, and no copied production credentials.
- Follow documented contributor startup commands exactly.
- Keep this separate from the primary Docker clean-install test.

Journey:

1. Follow first-run routing and configure location.
2. Choose the recommended HA-assisted path, discover Home Assistant, authorize in the browser, and return to a validated inventory connection without creating a long-lived token.
3. Read HA integrations, Floors, Areas, and lights without creating HA-backed light rows.
4. Create the intended HueWorks Areas, including mapping several HA spaces into one coordination Area.
5. Discover and pair both Hue bridges without handling API keys, then verify identifier-assisted native area mapping suggestions.
6. Discover and pair Caseta without a terminal helper or manual certificate movement, then map its source areas.
7. Configure Zigbee2MQTT with reuse/discovery assistance, validate its retained snapshot, and map any source spaces it exposes.
8. Import native bridges before Home Assistant entities with ordering consequences and inferred mappings visible.
9. Import one HA-only entity while excluding or linking native wrappers appropriately.
10. Add a newly discovered native entity and verify its saved ExternalSpaceMapping supplies the correct default without moving existing entities.
11. Create, activate, and control a useful embedded-state scene.
12. Restart HueWorks and verify credentials, Areas, mappings, imports, runtime connections, scenes, and first-run completion recover.
13. Disconnect HA when no HA-only runtime dependency remains and verify native control, Areas, mappings, and authored configuration remain intact.

Any step completed only because the owner remembers the old installation counts as a failed acceptance step.

### Upgrade And Recovery

- Restore a production-shaped database into isolation and record entity, Room/Area, scene, Light State, Pico, Presence Input, bridge-import, canonical-link, and integration counts.
- Start through the real Docker entrypoint and verify a pre-migration snapshot and SQLite integrity.
- Run the exact production migration on the isolated snapshot before deploying it to production; a synthetic fixture migration is insufficient for this rename.
- Verify the atomic Room-to-Area migration preserves one-to-one IDs and relationships before enabling any guided-setup behavior.
- Assert that every required persisted external identity is non-null and unique and that every legacy row received its exact pre-migration published value.
- Compare post-migration counts, foreign keys, active scenes, Pico bindings, recursive groups, hidden duplicates, ExternalSpaceMappings, exports, API identifiers, and credentials.
- Start the new application against the migrated copy and exercise health, Config, Areas, Control, scene activation, Pico configuration, representative bridge control, HA export, HomeKit topology, API, and MCP reads before the real deployment.
- Immediately before production deployment, create a new application-consistent database snapshot and verify SQLite integrity rather than reusing the earlier rehearsal copy.
- After production startup, repeat count/integrity checks and representative control/export smoke tests before declaring the migration successful.
- Exercise representative import/reimport paths.
- Rehearse restoring the pre-migration database snapshot with the prior application revision and verify recovery before the production change.

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
