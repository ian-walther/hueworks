# Reimport Review UI

## Goal
Make repeated manual bridge imports safe, predictable, and easy to scan.

The backend contract is now a bridge-refresh and diff-resolution model. Future work should focus on making that model obvious in the UI so an operator can reimport a bridge, understand what changed upstream, and apply only the intended resolutions without risking HueWorks-authored configuration.

## Contract To Preserve
Initial import and manual reimport have different jobs:
- Initial import materializes selected upstream bridge state into new HueWorks configuration.
- Manual reimport compares the latest bridge observation to current HueWorks configuration.
- Manual reimport auto-refreshes bridge-owned facts for confidently matched entities.
- Manual reimport presents only differences that require operator intent or safety review.
- Manual reimport applies only safe bridge-owned refreshes, safe duplicate bookkeeping, and explicit operator resolutions.

"No-op reimport" means no unselected change to user-facing behavior or authored configuration. It does not mean no database writes; bridge-owned caches, retained import observations, review blobs, and audit metadata may change.

## Source Of Truth
Bridge imports are observations. HueWorks entity tables contain current app configuration plus cached bridge facts. Diffs are comparisons between the latest observation and current configuration. Resolutions are explicit mutations to HueWorks-authored intent or safe bookkeeping.

Preserve this model:
- Latest normalized import plus current HueWorks configuration equals planned bridge fact refreshes and review items.
- Current HueWorks configuration plus planned bridge fact refreshes and selected resolutions equals updated HueWorks configuration.
- Stored import observations, review blobs, and resolution history are audit/debug context, not a durable recipe for current entities.
- `lights.normalized_json` and `groups.normalized_json` are cached bridge observations on live rows, not the source of truth for user-managed fields.

## Field Ownership
HueWorks-authored intent must be protected by default:
- `display_name`
- `room_id`
- `enabled`
- `ha_export_mode`
- `homekit_export_mode`
- actual/extended Kelvin overrides
- canonical link fields on existing rows
- `parent_group_id`
- scene/component references
- Pico device configuration and button bindings
- destructive lifecycle choices such as disable and delete

Bridge-owned facts may refresh automatically for confidently matched entities:
- `name`
- `supports_color`
- `supports_temp`
- `reported_min_kelvin`
- `reported_max_kelvin`
- bridge identifiers in `metadata`
- capabilities and raw bridge metadata
- `normalized_json`
- imported bridge group membership/topology when every referenced member resolves unambiguously

Technical identity and control fields such as `source_id`, `external_id`, and stable identity metadata may refresh automatically only after confident identity matching.

`bridge_id` and `source` define the import scope for an entity and should not move during reimport. If the same physical hardware appears under a different bridge or source, classify it through new, missing, duplicate, or ambiguous-identity review items instead of moving the existing row without an explicit resolution.

Light and group `metadata` is bridge-owned. Do not store HueWorks-authored user intent there.

## Labels
`name` is the bridge-owned name cache. `display_name` is the HueWorks-owned user label.

Future reimport UI should keep bridge renames inspectable without automatically changing HueWorks UI labels, Home Assistant entity names, or HomeKit accessory names. This feature intentionally does not need an "adopt bridge name" review action; if a user wants a bridge-side rename to become the HueWorks label, they should rename the entity in HueWorks.

## Stable Identity Keys
Identity matching must run before new/missing classification.

Use the strongest stable key available for each bridge type:
- Hue lights: prefer Hue `uniqueid`, then MAC, then source ID only as a fallback.
- Hue groups: use source ID unless a stronger stable group key is available.
- Home Assistant lights and groups: prefer entity registry `unique_id`; fall back to stable device identifiers; use `entity_id` only when no stronger key exists.
- Caseta lights and groups: prefer Lutron device ID, then serial, then source ID.
- Zigbee2MQTT lights: prefer IEEE address, then source ID.
- Zigbee2MQTT groups: prefer numeric Z2M group ID when available, then source ID or friendly name.

If exactly one existing HueWorks entity and one upstream entity share a stable identity key, reimport may refresh technical identity and bridge facts automatically. If no stable key matches, classify as new/missing. If multiple matches are possible, or if an identity refresh would move an entity to a `source_id` already owned by another row on the same bridge, classify as `ambiguous_identity` and do not mutate that entity.

Home Assistant group import must preserve entity registry `unique_id` in normalized group metadata when HA provides one. When a HA group has no `unique_id`, the fallback identity is `entity_id`; rename protection for that group is not available until HA provides a stable identity.

## Review Item Types
The review builder should produce composable review items, not a single status enum:
- `new_entity`: upstream entity has no matching HueWorks entity.
- `duplicate`: upstream Home Assistant wrapper entity is new to this bridge import but uniquely matches an existing native HueWorks entity strongly enough to be treated as the same physical control target.
- `missing_entity`: existing HueWorks entity from this bridge has no matching upstream entity.
- `ambiguous_identity`: stable matching found multiple plausible matches, conflicting identifiers, or a source ID collision.
- `membership_warning`: imported bridge group membership cannot be safely refreshed because one or more members are missing, unimported, or ambiguous.

Auto-refresh records should be visible as collapsed details or audit information, but they are not review items unless they require operator judgment.

Manual reimport should not produce `returned_entity`, `room_drift`, `label_drift`, or `link_suggested` review items.

## Duplicate And Dedup Behavior
Canonical linking's reimport role is deduplication.

A duplicate is directional. It exists when a new Home Assistant wrapper entity mirrors an already-imported native HueWorks entity from Hue, Caseta, or Zigbee2MQTT. The reverse is not a duplicate: if a native bridge is imported after a Home Assistant bridge, native entities import as real entities by default and any pre-existing HA mirror remains a visible twin until handled by manual link editing or a future dedup tool.

Rules to preserve:
- Only Home Assistant wrapper entities can be classified as duplicates in this feature.
- Only native Hue, Caseta, or Zigbee2MQTT entities can be duplicate targets.
- Light duplicates require a unique cross-source physical-identifier match, using identifiers such as MAC, serial, or IEEE from normalized metadata.
- Non-unique cross-source matches classify as `new_entity`, not `duplicate` and not `ambiguous_identity`.
- Group duplicates require a unique native group whose non-empty member set equals the HA group's canonicalized member set after member-light matching/linking is known.
- HA group duplicates should not be inferred when member canonicalization is incomplete, missing, or non-unique.
- Reimport never mutates canonical links on existing rows.
- The only link-bearing operation in reimport is the explicit duplicate resolution that creates a new row born linked.
- Hidden duplicate rows must be `enabled: false`, canonical-linked, export-disabled, and `room_id: nil`.
- Hidden duplicate rows are excluded from rooms, control planning, exports, and normal UI target lists.
- Hidden duplicate rows may still participate in imported bridge group topology as bridge-owned bookkeeping.
- A missing hidden duplicate row should be auto-deleted instead of surfaced as a recurring `missing_entity` decision.
- Deleting a native entity should also delete hidden duplicate rows whose canonical links target that entity.

Scanning existing entities for dedup opportunities, unlinking, relinking, or replacing canonical links belongs in a standalone dedup tool, not in manual reimport.

## Default Resolution Rules
Defaults should make "Apply" safe even when the user changes nothing.

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

## Remaining UI Work
The next pass should make the operator review experience easier to scan while preserving the invariants above.

Required UI improvements:
- Show summary counts for unchanged, auto-refreshed, new, duplicate, missing, ambiguous identity, and membership warning items.
- Collapse unchanged and auto-refreshed entities by default.
- Make auto-refreshed bridge facts inspectable for debugging without presenting them as decisions.
- Replace remaining generic checkbox-shaped controls with explicit resolution controls where that improves clarity.
- For review items, show current HueWorks value and bridge value clearly enough that the operator can understand the consequence.
- Use `Do Not Import` and `Import` for new entities.
- Use `Import Hidden Duplicate` and `Import as Real Entity` for duplicates.
- Use `Keep`, `Disable`, and `Delete` for missing entities.
- Include bulk actions for `Import all new` and `Disable all missing`.
- Recompute affected HA group duplicate items in the UI when member-light resolutions change instead of waiting for apply-time validation.
- Add dependency disclosure and confirmation UI for destructive disable/delete resolutions.
- Surface membership warnings when imported bridge group membership cannot be refreshed because a member is missing, unimported, or ambiguous.
- Require explicit confirmation for delete and other high-risk destructive actions.

Avoid using "ignore" because it blurs "do nothing in this review" with durable acknowledgment. This feature does not include durable acknowledgment; if the review item remains true on the next manual reimport, it should appear again.

## Future Work
Automatic reimport can build on this feature by adding a persistent inbox. That future inbox should treat stored diffs as derived cache, not queued commands or source-of-truth state.

Potential future enhancements:
- Add richer ambiguous-identity resolutions such as choosing an explicit match or importing as a new entity. The current feature ships only `Keep separate`.
- Add a future full export reconciliation primitive that can compare retained MQTT/HomeKit publication state with committed DB state.
- Add an explicit "reset and reimport from scratch" flow if a destructive bridge reset is needed; the normal setup route should not silently materialize over already-imported bridge data.
- Add a standalone dedup tool for scanning existing entities, unlinking, relinking, replacing canonical links, or converting visible twins into hidden duplicates.

## Guardrails
Future changes must not:
- Reintroduce global `Hueworks.Import.Link.apply/0` into initial import or manual reimport.
- Call `Hueworks.Bridges.delete_unchecked_entities/3` from manual reimport.
- Infer existing HueWorks `room_id` from upstream room/group membership.
- Mutate canonical links on existing rows during reimport.
- Store HueWorks-authored intent in light/group `metadata`.
- Allow a default reimport to delete or disable visible entities.
- Allow a default reimport to remove scene component rows or Pico configuration.
- Import HueWorks-exported HA entities back into HueWorks.
- Make a native bridge entity a hidden duplicate of a Home Assistant wrapper.
- Remove the five-import retention rule for `bridge_imports`; retained rows are debugging/audit context, not source-of-truth event history.
