# Area Design Production Rollout

## Scope And Safety Boundary

This runbook covers the focused Area-design workflow and migration `20260719120000_create_external_space_ignores`. The migration is additive: existing `external_space_mappings` remain canonical, and the new table stores explicit ignored source spaces. It must not change Areas, entity placement, scenes, Pico configuration, bridge credentials, or existing mappings.

Do not deploy until the user approves the final target revision. Use a fresh production backup for the real deployment even after a production-shaped rehearsal succeeds.

## Local Production-Shaped Rehearsal

Before deployment, copy a fresh production database backup into an isolated local path. Never overwrite the normal local database without first preserving it.

Record these pre-migration values from the copied database:

- SQLite integrity and foreign-key checks.
- Latest schema migration and total migration count.
- Counts for Areas, lights, groups, group memberships, scenes, scene components, active scenes, Pico devices/buttons, Presence Inputs, bridge imports, external spaces, and external-space mappings.
- Every `(external_space_id, area_id)` mapping row.
- Counts of unresolved HA Floors whose children are all mapped; these are the only rows the migration may infer as explicit Floor ignores.

Run the release migration against only the copied database. Verify afterward:

- `PRAGMA integrity_check` is `ok` and `PRAGMA foreign_key_check` is empty.
- The latest migration is `20260719120000`.
- All pre-migration domain counts are unchanged.
- The exact set of `external_space_mappings` is unchanged.
- `external_space_ignores` contains exactly the inferred Floor decisions and no mapped child space.
- No external space has both a mapping and an ignore record.

Start the application against the migrated copy in isolated verification mode. Exercise the Area-design page, save one temporary ignored decision, replace it with a mapping, and verify that only one variant exists after each write. Confirm that mapped HA spaces preselect newly reviewed native lights and groups, while ignored spaces do not. Confirm that existing light and group `area_id` values never change.

## Production Preflight

Immediately before deployment:

1. Fetch `remote/prod`, record the exact source and target SHAs, and review every commit in the range.
2. Confirm the production checkout is clean, the HueWorks container is healthy, and disk space is sufficient for an image build plus two database snapshots.
3. Confirm SQLite integrity, foreign keys, and the latest migration before changing the checkout.
4. Record authoritative pre-deploy domain counts and the complete external-space mapping set.
5. Run the ignored local deployment script and verify it reports a fresh, integrity-checked `hueworks_pre_deploy_*` backup before confirmation.

The container entrypoint creates a second automatic pre-migration backup. Stop if either backup is missing, corrupt, or has an unknown path.

## Post-Migration Checks

Before controlling a real light, verify:

1. SQLite integrity is `ok`, foreign-key checks are empty, and migration `20260719120000` is present.
2. Every recorded core-table count is unchanged.
3. Every pre-deploy external-space mapping still exists with the same destination Area.
4. The ignore count equals the number of inferred resolved Floors plus any decisions intentionally created after deployment.
5. No external space has both a mapping and an ignore record.
6. No light, group, scene, active scene, Pico device, Pico button, Presence Input, bridge, or bridge import was deleted or reassigned.
7. `/health` reports normal runtime I/O and the container remains stable.

## UI And Runtime Smoke

1. Open `/setup` and confirm Area design is summarized rather than expanded inline.
2. Open `/setup/areas` and confirm unresolved decisions appear in the work queue and prior mapped decisions appear under completed decisions.
3. Save and then revise one low-risk source-space decision; verify each save leaves the work queue and survives a remount.
4. Review a native bridge import and confirm confident HA evidence preselects the expected destination for both lights and groups.
5. Cancel without applying, then confirm existing production entity placement is unchanged.
6. Verify representative Hue, Caseta, Zigbee2MQTT, and Home Assistant state updates before issuing commands.
7. Verify one low-risk scene action, the Office Pico controls, HA MQTT controls, HomeKit on/off, and AI API entity lookup.

## Stop Conditions

Stop and restore or roll back if:

- A backup, integrity check, foreign-key check, migration assertion, domain count, or mapping-preservation check fails.
- Any external space has both decision variants.
- Existing entity placement changes during Area design or import review.
- The container restarts repeatedly, `/health` is not ready, or runtime I/O is disabled.
- Existing Areas, scenes, Presence Inputs, Pico configuration, bridge credentials, canonical links, HA identities, or HomeKit topology are missing or reassigned.
- Any uncontrolled or surprising real-light action occurs.

## Rollback

The migration is additive, so the currently deployed pre-feature application can run against the migrated database and ignore `external_space_ignores`. For a feature-only problem, move `prod` back to the recorded source SHA and run the deployment script without restoring the database. New ignore decisions remain unused but harmless.

For migration corruption or any unexpected data change, stop HueWorks, preserve the failed database, restore the exact fresh pre-deploy backup with the release restore command, move `prod` to the recorded source SHA, and redeploy. Never replace the database while the HueWorks container is running.
