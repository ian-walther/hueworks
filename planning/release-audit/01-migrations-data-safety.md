# Chunk 1: Migrations & Data Safety

Status: complete. Scope: migrations `20260717120000`–`20260717160000`, `lib/hueworks/release.ex`, `lib/hueworks/database_maintenance.ex`, `lib/hueworks/published_identity.ex`, `lib/hueworks/schemas/area.ex` (identity generation only), consistency with `planning/area-onboarding-rollout.md`. All files read line-by-line at HEAD (`ff525f8`); none were dirty.

## Findings

### MG-1: Backup prune failure aborts the release migration path

- Severity: low. Type: technical (availability).
- Location: `lib/hueworks/release.ex`, `maybe_backup_pending_migrations/4` — `:ok = maintenance.prune_backups(dir, @pre_migration_prefix, retention)`.
- Problem: after a *successful* pre-migration backup, a prune failure (e.g. permission error on one old backup file) raises `MatchError` inside `with_repo`, so migrations never run and the deploy aborts. Prune failure leaves *extra* backups on disk — a safe condition that does not justify blocking an upgrade. Contrast: backup failure correctly raises with an explicit message.
- Decision: on `{:error, reason}` from `prune_backups`, log a warning naming the path/reason and continue with migrations. Do not change the behavior for backup failure itself.
- Guardrail: extend the existing release migrate tests (the DI seams `migrator:`/`maintenance:` exist for exactly this) with a case where `prune_backups` returns an error and migrations still run.
- Effort: S.

### MG-2: Two parallel published-identity generation APIs, one of them dead-in-practice

- Severity: low. Type: style (single-source-of-truth drift).
- Location: `lib/hueworks/published_identity.ex` (`space_identifiers/1` vs `area_device_identifier/0` + `area_scene_select_identifier/0`) and `lib/hueworks/schemas/area.ex` (field-level `autogenerate:` MFAs *and* changeset-level `put_new_published_identities/1`).
- Problem: the changeset always populates both identifiers on insert, so the `autogenerate` MFAs never fire on the changeset path; they exist only for hypothetical bare-struct inserts, which the DB trigger already rejects safely. The two APIs also differ semantically: `space_identifiers/1` shares one UUID token across both identifiers, the individual functions generate unrelated tokens. Two generation points with different token semantics is drift waiting to be extended.
- Decision: keep `space_identifiers/1` (shared token; easier operator correlation in HA) as the only generator, called from the changeset. Delete `area_device_identifier/0`, `area_scene_select_identifier/0`, and the `autogenerate:` options; keep `fetch!/2`. Before deleting, grep for any `Repo.insert` of a bare `%Area{}` (none expected; import goes through the changeset) — if one exists, route it through the changeset instead.
- Guardrail: `test/hueworks/schemas_test.exs` identity tests and `test/hueworks/schema_constraint_parity_test.exs` (trigger + uniqueness) already cover the surviving path.
- Effort: S.

## Parked For Later Chunks

- `bridge_imports` stored review blobs (and any other persisted import/normalized JSON) may embed room-era keys written before `e88ae84`; the rename migration only rewrites `pico_buttons.action_config` and `pico_devices.metadata`. Verify in chunk 2/4 how stale persisted review blobs are read post-rename (the refinement doc's "stale review" state) — either the read path tolerates old keys or stale reviews are invalidated.

## Explicitly Fine / Leave-Alone

- **Irreversible `down` in `20260717140000`** raising with a message pointing at snapshot restore: matches the rollout runbook's stated safety boundary. Correct choice over a fake reversal.
- **Room-prefixed identifiers surviving the rename** (`hueworks_room_<id>` backfilled in `130000`, kept through `140000`, while new areas get `hueworks_area_<uuid>`): intentional HA identity preservation so existing HA devices/selectors are updated rather than duplicated. The mixed prefixes are cosmetic; do not "clean them up" — that would fork HA identities.
- **`rename_action_config_key` using `Map.put_new`**: pre-migration data cannot contain the destination key, and conservative no-overwrite is the right instinct in a data rewrite. Helpers are public and covered by `test/hueworks/migrations/*` — testable-migration pattern, keep.
- **NULL-decode risk in the pico JSON rewrites**: refuted — `action_config` and `metadata` are `null: false, default: %{}` since `20260331190000`.
- **`occupancy_sources.room_id`**: refuted as a rename miss — that table was dropped in `20260622120000`; the six-table `@area_tables` list plus the two JSON rewrites cover every live `room` reference. Runbook count/identity assertions (49 migrations, 110 `area_id` buttons, 36 metadata devices) are consistent with the migration code.
- **Identity triggers**: creation-order is sound (created after rename + backfilled data), and `schema_constraint_parity_test.exs` asserts the trigger fires — that test is also the tripwire if a future migration rebuilds `areas` and silently drops the triggers. No action now.
- **`backfill_identities` interpolating its table-name argument into SQL**: only ever called with literal `"rooms"`/test table names inside migration/test code; not an injection surface. Leave.
- **Backup machinery**: `vacuum_into` (safe live-SQLite snapshot), refuse-if-backup-exists, restore double `integrity_check` + temp-copy + recovery snapshot + `RESTORE` confirmation + running-app check independent of `force:` — all sound and match the runbook's stop conditions. Second-resolution timestamp collision on backup names is theoretical (two migrate runs in one second) and fails loudly; leave.
- **Manual backups (`hueworks_manual_*`) exempt from retention pruning**: operator-created artifacts should not be auto-deleted. Intentional asymmetry, keep.
