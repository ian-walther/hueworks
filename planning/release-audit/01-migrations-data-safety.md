# Chunk 1: Migrations & Data Safety

Status: complete; implementation reconciled 2026-07-26 (suite green at 1077 tests). Scope: migrations `20260717120000`–`20260717160000`, `lib/hueworks/release.ex`, `database_maintenance.ex`, `published_identity.ex`, `schemas/area.ex` identity generation, consistency with `planning/area-onboarding-rollout.md`. No open findings.

## Refutations (permanent record)

- **MG-2 (dual published-identity APIs) — the implementer was right, the audit was wrong.** The audit called the field-level `autogenerate` MFAs dead-in-practice and decided to delete them. Codex verified 256 bare `%Repo.insert!(%Area{...})` call sites across the test suite that rely on autogeneration (without it, every one hits the DB identity trigger). The audit's own guardrail step ("grep for bare-struct inserts — none expected") was executed with the wrong expectation: production inserts do all use the changeset, but the test surface is a legitimate consumer. Removing autogeneration buys no runtime behavior and costs a 256-site fixture rewrite. The dual generation path is now recorded as intentional: changeset (shared token) for production, autogenerate (independent tokens) as the test-fixture path, DB trigger as the invariant. Do not re-open without also deciding to rewrite the fixtures.

## Parked For Later Chunks

- (resolved) The stale-review-blob question was answered in chunk 2: reviews are rebuilt fresh on mount and re-validated on apply.

## Explicitly Fine / Leave-Alone

- **Backup prune failures now warn-and-continue** while backup creation failures still abort migrations — the two failure modes are correctly distinguished in `Hueworks.Release` (formerly MG-1, implemented with a red-first regression test).
- **Irreversible `down` in `20260717140000`** raising with a message pointing at snapshot restore: matches the rollout runbook's stated safety boundary. Correct choice over a fake reversal.
- **Room-prefixed identifiers surviving the rename** (`hueworks_room_<id>` backfilled in `130000`, kept through `140000`, while new areas get `hueworks_area_<uuid>`): intentional HA identity preservation so existing HA devices/selectors are updated rather than duplicated. The mixed prefixes are cosmetic; do not "clean them up" — that would fork HA identities.
- **`rename_action_config_key` using `Map.put_new`**: pre-migration data cannot contain the destination key, and conservative no-overwrite is the right instinct in a data rewrite. Helpers are public and covered by `test/hueworks/migrations/*` — testable-migration pattern, keep.
- **NULL-decode risk in the pico JSON rewrites**: refuted — `action_config` and `metadata` are `null: false, default: %{}` since `20260331190000`.
- **`occupancy_sources.room_id`**: refuted as a rename miss — that table was dropped in `20260622120000`; the six-table `@area_tables` list plus the two JSON rewrites cover every live `room` reference. Runbook count/identity assertions (49 migrations, 110 `area_id` buttons, 36 metadata devices) are consistent with the migration code.
- **Identity triggers**: creation-order is sound (created after rename + backfilled data), and `schema_constraint_parity_test.exs` asserts the trigger fires — that test is also the tripwire if a future migration rebuilds `areas` and silently drops the triggers. No action now.
- **`backfill_identities` interpolating its table-name argument into SQL**: only ever called with literal `"rooms"`/test table names inside migration/test code; not an injection surface. Leave.
- **Backup machinery**: `vacuum_into` (safe live-SQLite snapshot), refuse-if-backup-exists, restore double `integrity_check` + temp-copy + recovery snapshot + `RESTORE` confirmation + running-app check independent of `force:` — all sound and match the runbook's stop conditions. Second-resolution timestamp collision on backup names is theoretical (two migrate runs in one second) and fails loudly; leave.
- **Manual backups (`hueworks_manual_*`) exempt from retention pruning**: operator-created artifacts should not be auto-deleted. Intentional asymmetry, keep.
