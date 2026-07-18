# Area And Onboarding Production Rollout

## Scope And Safety Boundary

This runbook is the only supported production path for the Room-to-Area migration and guided-onboarding feature. The migration is intentionally irreversible in place. A rollback across the Area boundary requires restoring the fresh pre-deploy database snapshot before starting the old application.

Do not deploy until the user explicitly approves the final target revision and authorizes the production change. Do not reuse a rehearsal snapshot as the production safety backup.

## Required Revisions

The expected pre-deploy production revision is:

```text
09fa9e360c7bbfe0eb38cca17470d60f24153a82
```

The approved target must contain this ordered work:

```text
1113a4f pre-release setup refinements
7f60f53 persist published room identities
e88ae84 rename rooms to areas
3503af0 add external space mappings
5bb32e3 add home assistant setup guidance
24e3257 cover visible ha placement guidance
4b2ffd6 add resumable onboarding state
7e41dbd add guided first run setup
25cc6f3 add isolated verification mode
a4a5d49 report isolated verification health
4645ee9 preserve pico area metadata during migration
e9e7dfe fix area control copy
fd40400 polish area language
```

The final documentation commit may follow this list. The target must include `4645ee9` before migration `20260717140000` runs for the first time. Do not deploy an intermediate revision ending at `e88ae84`; that revision predates the production-shaped Pico metadata correction.

## Preflight

Fetch the approved `prod` branch and record its exact target:

```bash
git fetch remote
target_sha="$(git rev-parse remote/prod)"
printf 'Target: %s\n' "$target_sha"
git merge-base --is-ancestor 4645ee9 "$target_sha"
git log --oneline --reverse 09fa9e3.."$target_sha"
```

Stop if the ancestry check fails or the commit list differs from the approved list.

Confirm production checkout, health, free space, and a clean SQLite database:

```bash
ssh ha 'cd ~/docker/hueworks && \
  printf "revision: " && git rev-parse HEAD && \
  printf "worktree:\n" && git status --short && \
  docker compose ps hueworks && \
  curl --fail --silent --show-error http://127.0.0.1:4000/health && printf "\n" && \
  df -h . data && \
  python3 - <<"PY"
import sqlite3

with sqlite3.connect("data/hueworks.db") as db:
    print("integrity:", db.execute("PRAGMA integrity_check").fetchone()[0])
    print("foreign_keys:", len(db.execute("PRAGMA foreign_key_check").fetchall()))
    print("latest_migration:", db.execute("SELECT max(version) FROM schema_migrations").fetchone()[0])
PY'
```

Stop if production is not at `09fa9e360c7bbfe0eb38cca17470d60f24153a82`, the worktree is dirty, the service is unhealthy, disk space is marginal, integrity is not `ok`, foreign-key violations exist, or the latest migration is not `20260712100000`.

Immediately before deployment, record current counts. The last known baseline is shown only as a sanity reference; the fresh query is authoritative if legitimate production changes occurred after this plan was written.

| Table | Reference count |
| --- | ---: |
| `rooms` | 15 |
| `lights` | 192 |
| `groups` | 85 |
| `group_lights` | 453 |
| `scenes` | 34 |
| `scene_components` | 38 |
| `scene_component_lights` | 553 |
| `active_scenes` | 7 |
| `pico_devices` | 36 |
| `pico_buttons` | 175 |
| `presence_inputs` | 3 |
| `bridge_imports` | 18 |
| `external_scenes` | 7 |
| `external_scene_mappings` | 7 |
| `light_states` | 11 |
| `app_settings` | 1 |

```bash
ssh ha 'cd ~/docker/hueworks && python3 - <<"PY"
import sqlite3

tables = [
    "rooms", "lights", "groups", "group_lights", "scenes", "scene_components",
    "scene_component_lights", "active_scenes", "pico_devices", "pico_buttons",
    "presence_inputs", "bridge_imports", "external_scenes",
    "external_scene_mappings", "light_states", "app_settings"
]

with sqlite3.connect("data/hueworks.db") as db:
    for table in tables:
        query = "SELECT count(*) FROM " + table
        print(f"{table}={db.execute(query).fetchone()[0]}")
PY'
```

## Deploy

Run the ignored local deployment script from the repository root:

```bash
./deploy-prod.local.sh
```

Before confirmation, verify that the script reports a forward move from `09fa9e360c7b` to the approved target and prints the approved commit list. The script must report the path of a fresh `hueworks_pre_deploy_*` SQLite backup before it resets the checkout or starts the new image. Record that path in the deployment notes.

The container entrypoint creates a second automatic pre-migration snapshot before release migrations. Stop immediately if either backup or its integrity validation fails. Do not manually rerun a partially failed migration against the live database without first preserving the failed database and reviewing the logs.

## Post-Migration Data Checks

Run these checks before any real-light control test:

```bash
ssh ha 'cd ~/docker/hueworks && python3 - <<"PY"
import sqlite3

expected_counts = {
    "areas": 15,
    "lights": 192,
    "groups": 85,
    "group_lights": 453,
    "scenes": 34,
    "scene_components": 38,
    "scene_component_lights": 553,
    "active_scenes": 7,
    "pico_devices": 36,
    "pico_buttons": 175,
    "presence_inputs": 3,
    "bridge_imports": 18,
    "external_scenes": 7,
    "external_scene_mappings": 7,
    "light_states": 11,
    "app_settings": 1,
    "external_spaces": 0,
    "external_space_mappings": 0,
}

with sqlite3.connect("data/hueworks.db") as db:
    assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    assert db.execute("SELECT count(*), max(version) FROM schema_migrations").fetchone() == (49, 20260717160000)
    assert db.execute("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'rooms'").fetchone() == (0,)

    for table, expected in expected_counts.items():
        actual = db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        assert actual == expected, (table, actual, expected)

    assert db.execute("SELECT count(*) FROM areas WHERE ha_device_identifier IS NULL OR ha_device_identifier = '' OR ha_scene_select_identifier IS NULL OR ha_scene_select_identifier = ''").fetchone() == (0,)
    assert db.execute("SELECT count(*) - count(DISTINCT ha_device_identifier) FROM areas").fetchone() == (0,)
    assert db.execute("SELECT count(*) - count(DISTINCT ha_scene_select_identifier) FROM areas").fetchone() == (0,)
    assert db.execute("SELECT count(*) FROM pico_buttons WHERE json_type(action_config, '$.room_id') IS NOT NULL").fetchone() == (0,)
    assert db.execute("SELECT count(*) FROM pico_buttons WHERE json_type(action_config, '$.area_id') IS NOT NULL").fetchone() == (110,)
    assert db.execute("SELECT count(*) FROM pico_devices WHERE json_type(metadata, '$.room_override') IS NOT NULL OR json_type(metadata, '$.detected_room_id') IS NOT NULL").fetchone() == (0,)
    assert db.execute("SELECT count(*) FROM pico_devices WHERE json_type(metadata, '$.area_override') IS NOT NULL").fetchone() == (36,)
    assert db.execute("SELECT count(*) FROM pico_devices WHERE json_type(metadata, '$.detected_area_id') IS NOT NULL").fetchone() == (36,)

print("post-migration data checks passed")
PY'
```

If preflight counts changed legitimately, update only the corresponding expected values after comparing the fresh pre-deploy snapshot. Never weaken identity, schema, Pico-key, integrity, or foreign-key assertions.

## Runtime And UI Smoke

1. Confirm `curl http://127.0.0.1:4000/health` returns `status: ok`, an executor state of `ok`, and does not report `runtime_io: disabled`.
2. Confirm Config shows 5 bridges, 15 Areas, 34 scenes, and normal runtime mode.
3. Confirm Areas lists all existing production Areas with their scene counts, active scenes, Presence Inputs, groups, and lights.
4. Confirm Control shows the expected active scene for Main Floor, Garage, Foyer, Hallway, Master Bedroom, Guest Room, and Studio.
5. Open the Office Pico configuration and verify Main Floor is selected, the Lower and Overhead control groups are intact, and all five bindings are present.
6. Verify representative light and group state updates from Hue, Caseta, Zigbee2MQTT, and Home Assistant before issuing commands.
7. Activate or reapply one low-risk scene, then test the Office Pico's overhead, lower, and all-light controls.
8. Confirm HA MQTT Area selectors update existing Room-era registry entities rather than creating duplicates. Verify Presence Input writes and one exported light/group control.
9. Confirm HomeKit still reports existing accessories and reliable on/off control.
10. Confirm the AI API Area endpoints and MCP Area tools can read state and resolve an exact entity without using any removed Room operation.
11. Exercise one no-change reimport review without applying destructive resolutions.

Do not dismiss the setup callout merely to make the smoke test look complete; existing production configuration is valid even though onboarding completion state is initially empty.

## Stop Conditions

Immediately stop and choose a rollback path if any of these occur:

- Either pre-deploy backup is missing, corrupt, or has an unknown path.
- Migration count/version, table names, foreign keys, identities, Pico metadata, or row counts fail validation.
- The container restarts repeatedly, `/health` is not ready, or runtime I/O is unexpectedly disabled.
- Existing Areas, active scenes, scene components, Presence Inputs, Pico control groups, Pico bindings, bridge credentials, or canonical links are missing or reassigned.
- HA creates duplicate Area selectors/devices or loses existing entity identity.
- HomeKit topology disappears unexpectedly.
- Representative physical-state events or controls fail on more than one transport.
- Any uncontrolled or surprising real-light action occurs.

## Feature-Only Rollback

Use this when the Area schema and migrated data are correct but guided setup, external-space mapping, or later UI/runtime behavior is faulty. The verified compatibility floor is `e88ae84`; it can read the final additive schema after migrations `20260717150000` and `20260717160000` have run.

1. Move `prod` to `e88ae84` with force-with-lease.
2. Run `./deploy-prod.local.sh` and confirm it identifies a rollback.
3. Do not restore the pre-Area database.
4. Re-run health, Areas, Control, Pico, HA MQTT, HomeKit, and representative transport checks.

The database keeps additive external-space and onboarding tables/columns unused by this older code. This rollback is not appropriate for a defect in the Area migration itself.

## Full Pre-Area Rollback

Use this for migration/data corruption, missing configuration, broken Pico migration, identity duplication, or any defect that makes the Area schema unsafe.

1. Stop HueWorks before replacing the database.
2. While the current image is still available, restore the exact recorded `hueworks_pre_deploy_*` snapshot with the supported release restore command. This also creates a recovery snapshot of the failed migrated database.
3. Move `prod` back to `09fa9e360c7bbfe0eb38cca17470d60f24153a82` with force-with-lease.
4. Run `./deploy-prod.local.sh` so the prior image is rebuilt against the restored pre-Area schema.
5. Verify SQLite integrity, 44 migrations through `20260712100000`, the original core counts, `/rooms` behavior, Control, Pico bindings, bridge events, HA MQTT, HomeKit, and representative real lights.

Example offline restore command after stopping the service:

```bash
ssh ha 'cd ~/docker/hueworks && \
  docker compose stop hueworks && \
  docker compose run --rm --no-deps hueworks \
    /app/bin/hueworks eval '\''Hueworks.Release.restore("/data/backups/REPLACE_WITH_RECORDED_PRE_DEPLOY_BACKUP.db", "RESTORE")'\'''
```

Never start `09fa9e3` against the migrated Area schema, and never restore the pre-Area database while the new container is running.
