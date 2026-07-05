# Import Diff Discovery and Resolution

## Goal
Make repeated manual bridge imports safe, predictable, and boring.

The operator should be able to reimport a bridge at any time to discover upstream changes, refresh bridge-owned facts, and resolve meaningful differences without risking HueWorks-authored intent. "No-op reimport" means no unselected change to user-facing behavior or authored configuration; it does not mean no database writes.

Initial import and manual reimport have different contracts:
- Initial import materializes selected upstream bridge state into new HueWorks configuration.
- Manual reimport compares the latest bridge observation to current HueWorks configuration.
- Manual reimport auto-refreshes bridge-owned facts for confidently matched entities.
- Manual reimport presents only the differences that require operator intent or safety review.
- Manual reimport applies only safe bridge-owned refreshes, safe duplicate bookkeeping, and explicit operator resolutions.

## Priority
This is the next major work item before the control-architecture refactor.

The control refactor targets scene/runtime seams, while reimport safety lives in import planning, diffing, materialization, identity matching, linking boundaries, and persistence. There is no clear ordering dependency where the control refactor makes reimport work easier.

This should ship as one coherent feature. The plan is intentionally detailed so the implementation can land with the intended product contract intact.

## Product Contract
Manual reimport is a bridge refresh and diff-resolution workflow, not a checkbox import workflow.

The workflow should be:
1. Fetch and normalize the latest bridge state into a new bridge import observation.
2. Match upstream entities to current HueWorks entities using stable identity keys.
3. Surface ambiguous identity instead of guessing.
4. Plan bridge-owned fact refreshes for confidently matched entities.
5. Produce review items for new entities, duplicates, missing entities, ambiguous identities, and membership warnings.
6. Default every review item to the safest behavior defined by this plan.
7. Apply bridge-owned refreshes, safe duplicate bookkeeping, and selected operator resolutions.
8. Show the same unresolved review item again on a later manual reimport if the underlying difference still exists.

Manual reimport may persist bridge import observations, review blobs, selected resolutions, timestamps, and audit/debug metadata. It may refresh bridge-owned cache fields on live rows. It may create hidden duplicate rows when the duplicate default resolution is applied. Without an explicit operator resolution, it must not move entities between rooms, toggle enablement for existing visible rows, change export modes, alter actual kelvin overrides, change canonical links on existing rows, delete user-visible entities, remove scene/Pico references, or otherwise mutate HueWorks-authored behavior.

Future automatic reimport can build on this feature by adding a persistent inbox. That future inbox should treat stored diffs as derived cache, not queued commands or source-of-truth state. This manual reimport feature is self-contained; preserving a review item in one reimport means "do nothing now," not "hide this forever."

## Source Of Truth
Bridge imports are observations. HueWorks entity tables contain current app configuration plus cached bridge facts. Diffs are comparisons between the latest observation and current configuration. Resolutions are explicit mutations to HueWorks-authored intent or safe bookkeeping defined by this plan.

The model is:
- Latest normalized import plus current HueWorks configuration equals planned bridge fact refreshes and review items.
- Current HueWorks configuration plus planned bridge fact refreshes and selected resolutions equals updated HueWorks configuration.
- Stored import observations, review blobs, and resolution history are useful for audit/debugging, but not as a durable recipe for current entities.
- `lights.normalized_json` and `groups.normalized_json` are cached bridge observations on live rows, not the source of truth for user-managed fields.

## Field Ownership
Manual reimport must distinguish HueWorks-authored intent from bridge-owned facts.

HueWorks-authored intent is protected by default:
- `display_name`
- `room_id`
- `enabled`
- `ha_export_mode`
- `homekit_export_mode`
- `actual_min_kelvin`
- `actual_max_kelvin`
- `extended_min_kelvin`
- `extended_kelvin_range`
- canonical link fields on existing rows
- `parent_group_id`
- scene/component references
- Pico device configuration and button bindings
- destructive lifecycle choices such as disable and delete

Bridge-owned facts refresh automatically for confidently matched entities:
- `name`
- `supports_color`
- `supports_temp`
- `reported_min_kelvin`
- `reported_max_kelvin`
- bridge identifiers in `metadata`
- capabilities and raw bridge metadata
- `normalized_json`
- imported bridge group membership/topology when every referenced member resolves unambiguously

Technical identity and control fields refresh automatically only after confident identity matching:
- `source_id`
- `external_id`
- stable identity metadata used for future matching

`bridge_id` and `source` define the import scope for an entity and should not move during reimport. If the same physical hardware appears under a different bridge or source, classify it through new, missing, duplicate, or ambiguous-identity review items instead of moving the existing row without an explicit resolution.

Light and group `metadata` is bridge-owned and may be replaced wholesale on refresh. No feature should store HueWorks-authored user intent in light/group metadata.

## Labels
`name` is the bridge-owned name cache. `display_name` is the HueWorks-owned user label.

Requirements:
- Initial import sets `display_name` to the imported `name` when creating a row.
- Hidden duplicate import sets `display_name` to the imported `name` when creating a row.
- A migration backfills `display_name` from `name` for existing rows where `display_name` is null.
- Light and group changesets or database constraints should enforce populated `display_name` after the backfill, preferably with a NOT NULL constraint once all creation paths set it.
- Light and group user-facing names read `display_name` directly once it is always populated.
- Bridge renames refresh `name` silently and never change `display_name`.
- This feature intentionally does not add an "adopt bridge name" review action. If a user wants a bridge-side rename to become the HueWorks label, they should rename the entity in HueWorks.
- Remove `display_name || name` fallback logic for light/group app display names, Home Assistant export names, and HomeKit accessory names after the backfill exists.
- Keep existing fallback behavior for rooms, scenes, external scenes, and Pico devices unless this feature explicitly backfills and enforces `display_name` for those domains too.

This keeps bridge-name refreshes from renaming HueWorks UI labels, HA entities, or HomeKit accessories.

## Stable Identity Keys
Identity matching must run before new/missing classification.

This section describes same-source identity matching for existing HueWorks entities from the bridge being reimported. Cross-source duplicate detection is separate and follows the directional rules in the duplicate section.

Use the strongest stable key available for each bridge type:
- Hue lights: prefer Hue `uniqueid`, then MAC, then source ID only as a fallback.
- Hue groups: use source ID unless a stronger stable group key is available.
- Home Assistant lights and groups: prefer entity registry `unique_id`; fall back to stable device identifiers; use `entity_id` only when no stronger key exists.
- Caseta lights and groups: prefer Lutron device ID, then serial, then source ID.
- Zigbee2MQTT lights: prefer IEEE address, then source ID.
- Zigbee2MQTT groups: prefer numeric Z2M group ID when available, then source ID or friendly name.

Home Assistant group import must preserve entity registry `unique_id` in normalized group metadata when HA provides one. When a HA group has no `unique_id`, the fallback identity is `entity_id`; rename protection for that group is not available until HA provides a stable identity. No registry backfill migration is required. Rename protection activates per HA entity after the first successful post-upgrade reimport apply refreshes its normalized snapshot, so each HA bridge should be reimported once before HA entity renames are made.

If exactly one existing HueWorks entity and one upstream entity share a stable identity key, reimport may refresh technical identity and bridge facts automatically. If no stable key matches, classify as new/missing. If multiple matches are possible, or if an identity refresh would move an entity to a `source_id` already owned by another row on the same bridge, classify as `ambiguous_identity` and do not mutate that entity.

## Review Model
The diff builder should produce composable review items, not a single status enum.

Review item types:
- `new_entity`: upstream entity has no matching HueWorks entity.
- `duplicate`: upstream Home Assistant wrapper entity is new to this bridge import but uniquely matches an existing native HueWorks entity strongly enough to be treated as the same physical control target.
- `missing_entity`: existing HueWorks entity from this bridge has no matching upstream entity.
- `ambiguous_identity`: stable matching found multiple plausible matches, conflicting identifiers, or a source ID collision.
- `membership_warning`: imported bridge group membership cannot be safely refreshed because one or more members are missing, unimported, or ambiguous.

Auto-refresh records should be visible as collapsed details or audit information, but they are not review items unless they require operator judgment.

Disable and delete confirmations are resolution states, not review item types. The diff builder should produce a `missing_entity` item; the UI/applier should add dependency disclosure and confirmation when the operator selects a destructive resolution.

Manual reimport should not produce `returned_entity`, `room_drift`, `label_drift`, or `link_suggested` review items.

## Duplicate And Dedup Behavior
Canonical linking's reimport role is deduplication.

A duplicate is directional. It exists when a new Home Assistant wrapper entity mirrors an already-imported native HueWorks entity from Hue, Caseta, or Zigbee2MQTT. The reverse is not a duplicate: if a native bridge is imported after a Home Assistant bridge, native entities import as real entities by default and any pre-existing HA mirror remains a visible twin until handled by manual link editing or a future dedup tool.

Manual link editing already exists as an escape hatch for visible twins, but link editing alone does not disable the wrapper row, remove it from rooms, or enforce the hidden-duplicate invariant.

A duplicate resolution creates a disabled, canonical-linked row so the mirrored upstream entity is acknowledged and will not be classified as new on every future reimport. This linked-disabled row is the memory of the duplicate; no durable suppression inbox is needed.

Duplicate matching requirements:
- Only Home Assistant wrapper entities can be classified as duplicates in this feature.
- Only native Hue, Caseta, or Zigbee2MQTT entities can be duplicate targets.
- Light duplicates require a unique cross-source physical-identifier match, using identifiers such as MAC, serial, or IEEE from normalized metadata.
- Non-unique cross-source matches classify as `new_entity`, not `duplicate` and not `ambiguous_identity`.
- Group duplicates require a unique native group whose non-empty member set equals the HA group's canonicalized member set after member-light matching/linking is known.
- HA group duplicates should not be inferred when member canonicalization is incomplete, missing, or non-unique.
- During manual reimport review, HA group duplicate classification is derived from the current member-light resolutions. If a member-light resolution changes, the UI should recompute affected group duplicate items reactively.
- During apply, group duplicate resolutions must be recomputed after member-light resolutions. If a selected group duplicate resolution is no longer valid, abort and return to review instead of silently dropping the group, importing it as a real group, or linking it to the wrong target.

Rules:
- Reimport never mutates canonical links on existing rows.
- Reimport never removes or replaces an existing canonical link.
- The only link-bearing operation in reimport is the explicit duplicate resolution that creates a new row born linked.
- Hidden duplicate rows must be `enabled: false`, canonical-linked, export-disabled, and `room_id: nil`.
- Hidden duplicate rows are excluded from rooms, control planning, exports, and normal UI target lists.
- Hidden duplicate rows may still participate in imported bridge group topology as bridge-owned bookkeeping, including HA group membership and HA group duplicate detection.
- A duplicate may be imported as a real entity only through an explicit alternative resolution.
- A missing hidden duplicate row should be auto-deleted instead of surfaced as a recurring `missing_entity` decision.
- Deleting a native entity should also delete hidden duplicate rows whose canonical links target that entity.

The disabled/canonical/roomless invariant avoids needing a separate `hidden` column. If a future UI needs to hide duplicate rows even from administrative "show disabled/show linked" views, that should be treated as a separate visibility feature rather than part of reimport safety.

Scanning existing entities for dedup opportunities, unlinking, relinking, or replacing canonical links belongs in a standalone dedup tool, not in manual reimport.

Initial import of a Home Assistant bridge must run the same duplicate matcher for rows it is creating and default matching wrapper entities to hidden duplicate imports. This replaces the current global `Link.apply()` behavior for the standard onboarding flow where native bridges already exist before the HA bridge is imported. Initial import must not run a global link pass or mutate canonical links on unrelated existing rows.

Initial HA import may apply duplicate defaults silently without adding duplicate-choice controls to the initial checkbox UI. The escape hatch for users who want the HA wrapper visible is after import: manually enable and place the wrapper row, and remove or adjust the canonical link where the UI supports it. A richer initial-import duplicate choice can be added later, but it is not required for this feature.

## Default Resolution Rules
These defaults should make "Apply" safe even when the user changes nothing.

| Situation | Default behavior | Explicit resolutions |
| --- | --- | --- |
| Existing matched entity with only bridge-owned fact changes | Auto-refresh bridge facts | None, details only |
| Confident technical identity drift | Auto-refresh identity/control fields | None, details only |
| New upstream light or group | Do not import | Import, with room destination |
| Duplicate upstream entity | Import hidden duplicate | Import as real entity |
| Missing upstream light or group | Keep existing entity | Disable, delete |
| Missing hidden duplicate row | Auto-delete bookkeeping row | None, details only |
| Missing entity referenced by scenes or Pico config | Keep existing entity | Disable or delete with dependency warning |
| Ambiguous identity match | Keep separate | None in this feature |
| Bridge group membership changes and all members resolve | Auto-refresh imported bridge group membership | None, details only |
| Bridge group membership references missing, unimported, or ambiguous members | Keep current membership and warn | Import missing members, choose matches, or skip those members |
| Destructive action selected | Require dependency disclosure and confirmation | Confirm or cancel |

Delete must warn when the entity participates in scenes, Pico bindings, groups, Home Assistant export, HomeKit export, or canonical links. When the deleted entity is a canonical target, dependent hidden duplicate rows should be deleted in the same transaction. Disable should be the safer destructive option.

HueWorks-managed entities that appear through a Home Assistant bridge import should be filtered before matching so HueWorks exports do not re-enter HueWorks as new upstream entities. Recognition should use the HA entity registry `unique_id` convention for exported HueWorks entities, especially `hueworks_light_*`, `hueworks_group_*`, `hueworks_scene_*`, `hueworks_room_*`, and `hueworks_presence_input_*`.

## Room Mapping
Upstream rooms are used only for placing new entities during manual reimport.

During a reimport review:
- For a new real entity, show a room destination control.
- Preselect an existing HueWorks room only when the upstream room name clearly matches a current HueWorks room by normalized name.
- If no clear match exists, default the new real entity to unassigned and offer `Create room` or `Choose room`.
- Upstream rooms with no imported entities should not create rooms or require decisions.
- Existing entities never receive room suggestions from manual reimport.
- Hidden duplicate rows are always roomless.

Hue-specific rule: Hue rooms arrive as both normalized rooms and groups of type `Room`. If a light moves rooms in the Hue app, the imported room-group membership refreshes as a bridge-owned fact while the light's HueWorks `room_id` stays put as authored intent. That divergence is correct. Reimport must not infer or update HueWorks `room_id` from Hue group membership.

## Imported Group Membership
Imported bridge group membership is bridge-owned and auto-refreshes when every referenced member resolves unambiguously.

Invariant:
- Imported group membership is not user-editable in HueWorks.
- Users who want custom topology should create HueWorks-side structures or edit topology on the bridge.
- Membership refreshes are scoped to the matched imported group.
- A bridge-reported empty member list is a complete, resolved membership and should clear the matched group's current membership.
- If any referenced member is missing, unimported, or ambiguous, keep current membership and surface a `membership_warning`.

Keeping imported group membership fresh matters for control planning and group optimization; stale memberships can cause HueWorks to choose inefficient or incorrect hardware calls.

## Review UI
The page should guide the operator toward decisions instead of showing every entity as visual noise.

UI requirements:
- Show summary counts for unchanged, auto-refreshed, new, duplicate, missing, ambiguous identity, and membership warning items.
- Collapse unchanged and auto-refreshed entities by default.
- Make auto-refreshed bridge facts inspectable for debugging without presenting them as decisions.
- For review items, show current HueWorks value and bridge value clearly enough that the operator can understand the consequence.
- Use controls that default to the safe behavior from this plan.
- Use `Do Not Import` and `Import` for new entities.
- Use `Import Hidden Duplicate` and `Import as Real Entity` for duplicates.
- Use `Keep`, `Disable`, and `Delete` for missing entities.
- Include bulk actions for `Import all new` and `Disable all missing`.
- Require explicit confirmation for delete and other high-risk destructive actions.

Avoid using "ignore" because it blurs "do nothing in this review" with durable acknowledgment. This feature does not include durable acknowledgment; if the review item remains true on the next manual reimport, it should appear again.

## Apply Semantics
Resolution apply should be transactional for database mutations.

Requirements:
- Apply in fixed phases: imports, identity refreshes, cache and membership refreshes, intent mutations, destructive actions.
- Recompute dependent refresh operations after selected resolutions are sequenced rather than replaying review-time operations verbatim.
- Validate selected intent mutations against expected current DB values before mutating.
- If any selected intent mutation is stale, abort the database transaction, refresh the diff, and return the user to review.
- Bridge-owned cache refreshes are last-write-wins; a mismatch on a cache field should not abort selected intent resolutions.
- Apply planned bridge-owned refreshes, hidden duplicate imports, hidden duplicate cleanup, and selected DB mutations in one transaction so partial database application does not occur.
- When deleting a canonical target, delete dependent hidden duplicate rows before the foreign key can nilify the canonical link.
- Do not call external side effects inside the database transaction.
- External side effects such as Home Assistant and HomeKit export updates must run after the database transaction commits.
- Deleted or disabled exported entities should be unpublished after commit, and export runtimes should be reloaded from committed DB state.
- If a post-commit side effect fails, surface the failure and make it retryable by rerunning the sync.

## Bridge Import Retention
`bridge_imports` is a short debugging and audit trail, not a durable event log.

Retention rule:
- Keep the five newest `bridge_imports` rows per bridge.
- Treat the active/current reimport review as part of that five-row window.
- Prune older observations after every successful import creation and after apply status changes.
- Do not rely on pruned observations for correctness; current entity tables and selected resolutions are the source of truth.

## Remaining Work
The next pass should focus on making the operator review experience easier to scan. Keep the backend invariants above intact while reducing visual noise and making high-risk decisions harder to apply accidentally.

Remaining product work:
- Collapse unchanged and auto-refreshed entities by default while making bridge-owned refresh details inspectable.
- Replace remaining generic checkboxes for new/existing rows with explicit controls where that improves clarity. Duplicate rows already expose `Import Hidden Duplicate`, `Import as Real Entity`, and `Do Not Import`; missing rows already expose `Keep`, `Disable`, and `Delete`.
- Recompute affected HA group duplicate items in the UI when member-light resolutions change instead of waiting for apply-time validation.
- Add dependency disclosure and confirmation UI for destructive disable/delete resolutions.
- Surface membership warnings when imported bridge group membership cannot be refreshed because a member is missing, unimported, or ambiguous.
- Add richer ambiguous-identity resolutions such as choosing an explicit match or importing as a new entity. The current feature ships only `Keep separate`.
- Consider a future full export reconciliation primitive that can compare retained MQTT/HomeKit publication state with committed DB state. The current apply path runs destructive export cleanup after commit and reloads export runtimes.
- Add an explicit "reset and reimport from scratch" flow if a destructive bridge reset is needed; the normal setup route should not silently materialize over already-imported bridge data.

Guardrails for future changes:
- Do not reintroduce global `Hueworks.Import.Link.apply/0` into initial import or manual reimport.
- Do not call `Hueworks.Bridges.delete_unchecked_entities/3` from manual reimport.
- Do not infer existing HueWorks `room_id` from upstream room/group membership.
- Do not mutate canonical links on existing rows during reimport.
- Do not store HueWorks-authored intent in light/group `metadata`.
- Preserve the five-import retention rule for `bridge_imports`; retained rows are debugging/audit context, not source-of-truth event history.

## Rollout Verification Plan
Use this procedure before deploying the reimport implementation to production. The goal is to prove two things before touching the live app:
- The database migration is non-destructive and only normalizes the intended schema/data.
- A default manual reimport preserves HueWorks-authored configuration unless the operator explicitly chooses a destructive resolution.

### Known Risk Areas
These are the places where a safe-looking reimport can still create surprising side effects.

- Display-name migration: the migration should backfill blank light/group `display_name` values from `name` and leave table shape, row counts, and relationships unchanged. Changesets should enforce populated `display_name` for new light/group rows; do not use a fragile SQLite table rewrite just to add a DB-level `NOT NULL` constraint.
- Pico config deletion: the old reimport path could call `Hueworks.Bridges.delete_unchecked_entities/3`; for Caseta bridges, that helper clears `pico_devices` and `pico_buttons`. Manual reimport must not call that helper, and Caseta reimport must preserve Pico devices, buttons, room assignment, display names, button bindings, and control-group metadata.
- Missing upstream entities: entities missing from a new bridge snapshot must default to "keep", not "delete" or "disable". Scene component rows, Pico bindings, exports, and canonical links should survive unless the operator explicitly selects a destructive option.
- Room drift: bridge-reported room changes must not move existing HueWorks `room_id` values. Hue room-group membership may refresh while HueWorks room assignment stays authored locally.
- Group membership drift: imported bridge group membership is bridge-owned and should refresh when every referenced member resolves. It should not refresh partially or guess when members are missing, ambiguous, or intentionally not imported.
- Duplicate direction: Home Assistant wrapper entities may become hidden duplicates of native Hue/Caseta/Z2M entities. Native entities must not become hidden duplicates of Home Assistant rows.
- Canonical link stability: reimport must not scan existing rows for new dedup opportunities, unlink rows, or relink existing canonical relationships. Only newly imported hidden duplicates should be born with canonical links.
- HueWorks self-import loop: Home Assistant entities exported by HueWorks must be filtered before planning so `hueworks_light_*`, `hueworks_group_*`, `hueworks_scene_*`, `hueworks_room_*`, and `hueworks_presence_input_*` unique IDs do not re-enter HueWorks as upstream entities.
- Identity drift and collision: a confident stable-identity match may refresh `source_id`; a collision with an occupied `source_id` must not mutate the wrong row.
- Hidden duplicate cleanup: missing hidden duplicates should be removed as bookkeeping. Deleting a canonical target should also delete its dependent hidden duplicates in the same transaction.
- Destructive resolution staleness: disable/delete choices should validate the reviewed current entity identity before mutating. If the row changed since review, apply should abort and the operator should refresh the review.
- Bridge import retention: reimport should keep only the five newest `bridge_imports` rows per bridge.
- External side effects: Home Assistant and HomeKit export cleanup must run only after the database transaction commits. Migration rehearsal should not depend on external side effects.

### Snapshot Production Data
Take a SQLite online backup from the production host before any deploy. Do not use a backup command that renames or replaces the live database.

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_DIR="/tmp/hueworks-reimport-rollout-${RUN_ID}"
LOCAL_DIR="/tmp/hueworks-reimport-rollout-${RUN_ID}"

ssh ha "mkdir -p ${REMOTE_DIR} && cd ~/docker/hueworks && sqlite3 data/hueworks.db '.backup ${REMOTE_DIR}/prod-pre.db'"
mkdir -p "${LOCAL_DIR}"
scp "ha:${REMOTE_DIR}/prod-pre.db" "${LOCAL_DIR}/prod-pre.db"
rm -f "${LOCAL_DIR}/prod-migrated.db-wal" "${LOCAL_DIR}/prod-migrated.db-shm"
cp "${LOCAL_DIR}/prod-pre.db" "${LOCAL_DIR}/prod-migrated.db"
```

If the production host does not have `sqlite3` installed, take the backup through the running HueWorks container instead:

```bash
ssh ha "mkdir -p ${REMOTE_DIR} && cd ~/docker/hueworks && docker compose exec -T hueworks sqlite3 /data/hueworks.db '.backup /tmp/prod-pre.db' && docker cp \$(docker compose ps -q hueworks):/tmp/prod-pre.db ${REMOTE_DIR}/prod-pre.db"
```

When resetting a reused local rehearsal copy, always delete the copied database's `-wal` and `-shm` sidecar files before copying `prod-pre.db` over it. Otherwise SQLite can replay stale pages from an earlier failed rehearsal into the fresh-looking database file.

Capture a small pre-migration fingerprint that separates protected user intent from bridge-owned facts.

```bash
sqlite3 -header -column "${LOCAL_DIR}/prod-pre.db" > "${LOCAL_DIR}/pre-summary.txt" <<'SQL'
SELECT 'rooms' AS table_name, COUNT(*) AS rows FROM rooms
UNION ALL SELECT 'lights', COUNT(*) FROM lights
UNION ALL SELECT 'groups', COUNT(*) FROM groups
UNION ALL SELECT 'group_lights', COUNT(*) FROM group_lights
UNION ALL SELECT 'scene_component_lights', COUNT(*) FROM scene_component_lights
UNION ALL SELECT 'pico_devices', COUNT(*) FROM pico_devices
UNION ALL SELECT 'pico_buttons', COUNT(*) FROM pico_buttons
UNION ALL SELECT 'bridge_imports', COUNT(*) FROM bridge_imports;

SELECT 'blank_light_display_names' AS check_name, COUNT(*) AS rows
FROM lights
WHERE display_name IS NULL OR trim(display_name) = '';

SELECT 'blank_group_display_names' AS check_name, COUNT(*) AS rows
FROM groups
WHERE display_name IS NULL OR trim(display_name) = '';

SELECT id, bridge_id, source, source_id, name, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, canonical_light_id
FROM lights
ORDER BY id;

SELECT id, bridge_id, source, source_id, name, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, canonical_group_id
FROM groups
ORDER BY id;

SELECT id, bridge_id, room_id, source_id, name, display_name, hardware_profile,
       enabled, metadata
FROM pico_devices
ORDER BY id;

SELECT id, pico_device_id, source_id, button_number, slot_index, action_type,
       action_config, enabled, metadata
FROM pico_buttons
ORDER BY id;
SQL
```

### Rehearse The Migration Locally
Run the release migration against the copied database, not the production database.

```bash
MIX_ENV=prod \
DATABASE_PATH="${LOCAL_DIR}/prod-migrated.db" \
SECRET_KEY_BASE="rollout-rehearsal-secret" \
mix run --no-start -e 'Hueworks.Release.migrate()'
```

After the migration, capture the same fingerprint and compare it to the pre-migration output.

```bash
sqlite3 -header -column "${LOCAL_DIR}/prod-migrated.db" > "${LOCAL_DIR}/post-migration-summary.txt" <<'SQL'
SELECT 'rooms' AS table_name, COUNT(*) AS rows FROM rooms
UNION ALL SELECT 'lights', COUNT(*) FROM lights
UNION ALL SELECT 'groups', COUNT(*) FROM groups
UNION ALL SELECT 'group_lights', COUNT(*) FROM group_lights
UNION ALL SELECT 'scene_component_lights', COUNT(*) FROM scene_component_lights
UNION ALL SELECT 'pico_devices', COUNT(*) FROM pico_devices
UNION ALL SELECT 'pico_buttons', COUNT(*) FROM pico_buttons
UNION ALL SELECT 'bridge_imports', COUNT(*) FROM bridge_imports;

SELECT 'blank_light_display_names' AS check_name, COUNT(*) AS rows
FROM lights
WHERE display_name IS NULL OR trim(display_name) = '';

SELECT 'blank_group_display_names' AS check_name, COUNT(*) AS rows
FROM groups
WHERE display_name IS NULL OR trim(display_name) = '';

SELECT id, bridge_id, source, source_id, name, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, canonical_light_id
FROM lights
ORDER BY id;

SELECT id, bridge_id, source, source_id, name, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, canonical_group_id
FROM groups
ORDER BY id;

SELECT id, bridge_id, room_id, source_id, name, display_name, hardware_profile,
       enabled, metadata
FROM pico_devices
ORDER BY id;

SELECT id, pico_device_id, source_id, button_number, slot_index, action_type,
       action_config, enabled, metadata
FROM pico_buttons
ORDER BY id;
SQL

diff -u "${LOCAL_DIR}/pre-summary.txt" "${LOCAL_DIR}/post-migration-summary.txt"
```

Expected migration-only differences:
- Blank light/group display-name counts become zero.
- Rows that had blank display names now have `display_name` equal to their existing `name`.
- `schema_migrations` may change.
- Light, group, room, scene, Pico, group-membership, canonical-link, enabled/export-mode, and room-assignment counts should not change.

Stop the rollout if any migration-only diff touches scene membership, Pico rows, group membership, exports, canonical links, or room assignment.

### Rehearse Manual Reimport Locally
Use the migrated database copy for a full bridge reimport rehearsal before production. Prefer a local app process or script pointed at the copied database. Do not run the rehearsal against the live production database.

If the production DB stores container-local credential paths, rewrite those paths only in the copied rehearsal DB before importing. For example, Caseta certificates stored as `/credentials/...` in Docker need to be copied to the local rehearsal directory and the copied bridge row should point at those local files. Do not change production credentials for a local rehearsal.

Reimport order:
1. Native lighting/control bridges first: Hue, Caseta, and Z2M.
2. Home Assistant bridge last, so native entities are available as duplicate targets.

Before applying each bridge reimport, capture bridge-scoped protected state.

```bash
BRIDGE_ID="<bridge id under test>"

sqlite3 -header -column "${LOCAL_DIR}/prod-migrated.db" > "${LOCAL_DIR}/bridge-${BRIDGE_ID}-before.txt" <<SQL
SELECT id, bridge_id, source, source_id, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, actual_min_kelvin, actual_max_kelvin,
       extended_min_kelvin, extended_kelvin_range, canonical_light_id
FROM lights
WHERE bridge_id = ${BRIDGE_ID}
ORDER BY id;

SELECT id, bridge_id, source, source_id, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, actual_min_kelvin, actual_max_kelvin,
       extended_min_kelvin, extended_kelvin_range, canonical_group_id
FROM groups
WHERE bridge_id = ${BRIDGE_ID}
ORDER BY id;

SELECT pd.id, pd.bridge_id, pd.room_id, pd.source_id, pd.display_name,
       pd.hardware_profile, pd.enabled, pd.metadata
FROM pico_devices pd
WHERE pd.bridge_id = ${BRIDGE_ID}
ORDER BY pd.id;

SELECT pb.id, pb.pico_device_id, pb.source_id, pb.button_number, pb.slot_index,
       pb.action_type, pb.action_config, pb.enabled, pb.metadata
FROM pico_buttons pb
JOIN pico_devices pd ON pd.id = pb.pico_device_id
WHERE pd.bridge_id = ${BRIDGE_ID}
ORDER BY pb.id;

SELECT scl.id, scl.scene_component_id, scl.light_id, scl.default_power,
       scl.presence_input_id
FROM scene_component_lights scl
JOIN lights l ON l.id = scl.light_id
WHERE l.bridge_id = ${BRIDGE_ID}
ORDER BY scl.id;
SQL
```

Apply the bridge reimport with default selections first. For the initial rollout, default apply should be boring: no operator choices, no destructive resolutions, and no reset-from-scratch flow.

After applying the default reimport, capture the same bridge-scoped state and diff it.

```bash
sqlite3 -header -column "${LOCAL_DIR}/prod-migrated.db" > "${LOCAL_DIR}/bridge-${BRIDGE_ID}-after.txt" <<SQL
SELECT id, bridge_id, source, source_id, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, actual_min_kelvin, actual_max_kelvin,
       extended_min_kelvin, extended_kelvin_range, canonical_light_id
FROM lights
WHERE bridge_id = ${BRIDGE_ID}
ORDER BY id;

SELECT id, bridge_id, source, source_id, display_name, room_id, enabled,
       ha_export_mode, homekit_export_mode, actual_min_kelvin, actual_max_kelvin,
       extended_min_kelvin, extended_kelvin_range, canonical_group_id
FROM groups
WHERE bridge_id = ${BRIDGE_ID}
ORDER BY id;

SELECT pd.id, pd.bridge_id, pd.room_id, pd.source_id, pd.display_name,
       pd.hardware_profile, pd.enabled, pd.metadata
FROM pico_devices pd
WHERE pd.bridge_id = ${BRIDGE_ID}
ORDER BY pd.id;

SELECT pb.id, pb.pico_device_id, pb.source_id, pb.button_number, pb.slot_index,
       pb.action_type, pb.action_config, pb.enabled, pb.metadata
FROM pico_buttons pb
JOIN pico_devices pd ON pd.id = pb.pico_device_id
WHERE pd.bridge_id = ${BRIDGE_ID}
ORDER BY pb.id;

SELECT scl.id, scl.scene_component_id, scl.light_id, scl.default_power,
       scl.presence_input_id
FROM scene_component_lights scl
JOIN lights l ON l.id = scl.light_id
WHERE l.bridge_id = ${BRIDGE_ID}
ORDER BY scl.id;
SQL

diff -u "${LOCAL_DIR}/bridge-${BRIDGE_ID}-before.txt" "${LOCAL_DIR}/bridge-${BRIDGE_ID}-after.txt"
```

Expected default-reimport differences:
- Existing visible light/group `display_name`, `room_id`, `enabled`, export modes, actual/extended kelvin settings, scene references, Pico rows, and existing canonical links do not change.
- Bridge-owned cache fields may refresh: `name`, `source_id` when identity drift is confident, `reported_min_kelvin`, `reported_max_kelvin`, capabilities, `external_id`, `metadata`, and `normalized_json`.
- Imported bridge `group_lights` may refresh when all members resolve unambiguously.
- New upstream entities remain unimported unless explicitly selected.
- Missing visible entities remain enabled and present unless explicitly disabled or deleted.
- Explicit destructive choices for missing entities validate the reviewed external identity before mutating. If the row changed after review, apply aborts instead of disabling or deleting a stale target.
- Missing hidden duplicate rows may disappear.
- `bridge_imports` retention may prune older rows down to the newest five for the bridge.

For the Caseta bridge, additionally verify:
- `pico_devices` row count and IDs are unchanged.
- `pico_buttons` row count and IDs are unchanged.
- Pico `metadata`, button `action_config`, and room assignments are unchanged.
- Pico button presses still resolve to the same configured control groups after reimport.

For the Home Assistant bridge, additionally verify:
- HueWorks-exported HA entities are absent from the reimport review and are not inserted.
- Unique HA wrappers for existing native lights/groups import only as hidden duplicates when selected by default: `enabled = false`, `room_id IS NULL`, export modes `none`, and a canonical link to the native entity.
- Non-unique or ambiguous HA wrappers are not hidden automatically.
- Native entities remain the canonical targets; no native row points at an HA wrapper as canonical.

Run the same default reimport a second time against the local copy. The second pass should be intent-idempotent: aside from a new/pruned `bridge_imports` row and bridge-owned cache refreshes, protected state should remain unchanged.

### Production Deployment Gates
Only deploy to production after the local migration and local reimport rehearsal pass.

Production sequence:
1. Take a fresh SQLite online backup from production.
2. Deploy the migration and application code.
3. Verify the app boots and the schema migration completed.
4. Re-run the migration fingerprint against production.
5. Reimport one native bridge first, preferably a low-risk bridge.
6. Verify protected-state diffs before reimporting the next bridge.
7. Reimport the Caseta bridge before Home Assistant so the Pico-preservation checks happen before the HA duplicate pass.
8. Reimport Home Assistant last.
9. After all bridge reimports, verify a representative room, scene activation, Pico button action, Home Assistant export, and HomeKit export.

Stop and restore from backup if any of these happen:
- Pico device/button rows disappear or Pico button config changes without an explicit Pico sync.
- Existing scene component rows disappear or point at different light IDs.
- Existing visible lights/groups move rooms, become disabled, or change export modes without an explicit selected resolution.
- A destructive missing-entity resolution applies after the reviewed entity changed identity.
- Existing canonical links are removed, reversed, or pointed at different targets.
- HueWorks-exported HA entities are imported back into HueWorks.
- A native bridge entity becomes a hidden duplicate of a Home Assistant wrapper.

Rollback expectation:
- If the migration has run but no destructive resolutions have been applied, restoring the pre-deploy SQLite backup should return the app to the previous production state.
- If destructive resolutions were explicitly applied during production reimport, treat rollback as a data restore decision, not an application-code rollback.
- Do not roll back by running old reimport code against the migrated database; restore the database backup first if data shape is suspect.
