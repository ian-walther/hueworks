# HueWorks

HueWorks is a local-first lighting control system for multi-bridge smart homes (Hue, Home Assistant, Caseta), with import/review workflows, unified state tracking, and scene-driven control execution.

## Current Status

HueWorks is in active development and already has working end-to-end flows for:
- bridge setup and credential testing
- import/reimport with review and apply
- canonical linking across sources
- live control UI for lights and groups
- rooms + scenes CRUD and scene activation
- event stream subscriptions feeding in-memory state

## What Works Today

- **Bridge setup wizard**: add bridge, validate credentials, import, review, apply  
  `lib/hueworks_web/live/config/bridge_live.ex`  
  `lib/hueworks_web/live/config/bridge_setup_live.ex`
- **Import pipeline**: fetch → normalize → plan → materialize → link  
  `lib/hueworks/import/pipeline.ex`  
  `lib/hueworks/import/normalize/*.ex`  
  `lib/hueworks/import/materialize.ex`  
  `lib/hueworks/import/link.ex`
- **Reimport behavior**: compares import vs DB state, supports selective deletion of unchecked entities  
  `lib/hueworks/import/reimport_plan.ex`  
  `lib/hueworks/bridges.ex`
- **Control runtime**: desired state + planner + queued executor  
  `lib/hueworks/control/desired_state.ex`  
  `lib/hueworks/control/planner.ex`  
  `lib/hueworks/control/executor.ex`
- **Scene activation**: updates desired state and enqueues control actions  
  `lib/hueworks/scenes.ex`
- **Subscription layer**: Hue SSE, HA WebSocket, Caseta LEAP subscriptions  
  `lib/hueworks/subscription/*`
- **UI screens**:  
  `/config`, `/lights`, `/rooms`

## Architecture

HueWorks currently has five primary layers:

1. **Bridge setup + import workflow (UI + pipeline)**
- Configure bridge credentials and validate connectivity in LiveView.
- Run import with review/apply (including reimport compare + selective deletion).
- Core modules:
  `lib/hueworks_web/live/config/bridge_live.ex`  
  `lib/hueworks_web/live/config/bridge_setup_live.ex`  
  `lib/hueworks/import/pipeline.ex`  
  `lib/hueworks/import/materialize.ex`  
  `lib/hueworks/import/reimport_plan.ex`  
  `lib/hueworks/import/link.ex`

2. **Domain + persistence layer**
- Canonical entities in SQLite via Ecto: bridges, imports, lights, groups, rooms, scenes, active scenes.
- Core modules:
  `lib/hueworks/schemas/*`  
  `lib/hueworks/repo.ex`  
  `lib/hueworks/lights.ex`  
  `lib/hueworks/groups.ex`  
  `lib/hueworks/rooms.ex`  
  `lib/hueworks/scenes.ex`  
  `lib/hueworks/active_scenes.ex`

3. **Control runtime**
- In-memory physical state and desired state in ETS.
- Scene apply updates desired state, planner builds actions, executor queues/dispatches by bridge.
- Core modules:
  `lib/hueworks/control/state.ex`  
  `lib/hueworks/control/desired_state.ex`  
  `lib/hueworks/control/planner.ex`  
  `lib/hueworks/control/executor.ex`  
  `lib/hueworks/control/light.ex`  
  `lib/hueworks/control/group.ex`

4. **Bridge adapters + subscriptions**
- Dispatch clients and payload transformers for Hue, HA, and Caseta.
- Background event stream processes keep in-memory state synchronized with bridge events.
- Core modules:
  `lib/hueworks/control/*_bridge.ex`  
  `lib/hueworks/control/*_client.ex`  
  `lib/hueworks/control/*_payload.ex`  
  `lib/hueworks/subscription/hue_event_stream.ex`  
  `lib/hueworks/subscription/home_assistant_event_stream.ex`  
  `lib/hueworks/subscription/caseta_event_stream.ex`

5. **Live UI layer**
- `/lights`: live controls, filtering, per-entity config, manual override entrypoints.
- `/rooms`: rooms CRUD, scene builder, scene activation.
- `/config`: bridge lifecycle and import lifecycle.
- Core modules:
  `lib/hueworks_web/live/lights_live.ex`  
  `lib/hueworks_web/live/rooms_live.ex`  
  `lib/hueworks_web/live/config/config_live.ex`

### Runtime startup

`Hueworks.Application` supervises Repo, PubSub, control state, desired state, executor, subscriptions, and endpoint:
`lib/hueworks/application.ex`

Optional runtime env vars:
- `ADVANCED_DEBUG_LOGGING=true` enables verbose planner/control trace logs for debugging scene application, circadian ticks, and executor dispatch behavior.
- `BRIDGE_SECRETS_PATH=/path/to/secrets.json` overrides the default bridge bootstrap file location.

### Current control flow (scene activation path)

1. Scene activated from `/rooms` UI.
2. `Hueworks.Scenes.apply_scene/2` computes desired per-light state.
3. `Hueworks.Control.Planner.plan_room/2` builds group/light action plan.
4. `Hueworks.Control.Executor.enqueue/2` queues dispatch.
5. Bridge-specific control modules send hardware/API commands.

## Known Gaps

- Caseta **group** dispatch is not implemented yet (`Control.Group` returns `{:error, :not_implemented}` for Caseta groups).
- Caseta Pico events are connected but still stub-logged (no action mapping runtime yet).
- HA group fan-out has known edge cases noted in code comments.
- Cross-bridge orchestration behavior still needs tightening around the core "no popcorning" promise.

## Getting Started

```bash
# Install dependencies
mix deps.get

# Create DB, migrate, and seed bridges from secrets.json
mix ecto.reset

# Build frontend assets
mix assets.setup
mix assets.build

# Start the app
iex -S mix phx.server
```

Open `http://localhost:4000`:
- `/config` for bridge setup/import/reimport
- `/lights` for live light/group control and kelvin override settings
- `/rooms` for rooms, scene builder, and scene activation

## Credentials and Seeding

Create `secrets.json` in repo root, or point `BRIDGE_SECRETS_PATH` at another file:

```json
{
  "bridges": [
    {
      "type": "hue",
      "name": "Upstairs Bridge",
      "host": "192.168.1.162",
      "credentials": {
        "api_key": "..."
      }
    },
    {
      "type": "hue",
      "name": "Downstairs Bridge",
      "host": "192.168.1.224",
      "credentials": {
        "api_key": "..."
      }
    },
    {
      "type": "caseta",
      "name": "Caseta Bridge",
      "host": "192.168.1.123",
      "credentials": {
        "cert_path": "/path/to/bridge.crt",
        "key_path": "/path/to/bridge.key",
        "cacert_path": "/path/to/bridge-ca.crt"
      }
    },
    {
      "type": "ha",
      "name": "Home Assistant",
      "host": "192.168.1.41",
      "credentials": {
        "token": "..."
      }
    },
    {
      "type": "z2m",
      "name": "Z2M Broker",
      "host": "192.168.1.50",
      "credentials": {
        "broker_port": 1883,
        "username": "mqtt-user",
        "password": "mqtt-pass",
        "base_topic": "zigbee2mqtt"
      }
    }
  ]
}
```

Then run:

```bash
mix ecto.reset
```

or reseed only:

```bash
mix seed_bridges
```

By default the seed task reads `secrets.json` from repo root. To use another path:

```bash
BRIDGE_SECRETS_PATH=/path/to/secrets.json mix seed_bridges
```

Caseta credentials can still be uploaded through the UI and are stored under `priv/credentials/caseta/`.
The credential storage root is configurable with `CREDENTIALS_ROOT`; in Docker it is set to `/credentials`.

## Docker Deployment

For a fresh clone on a Raspberry Pi or other Linux host, the intended baseline path is:

```bash
cp .env.example .env
mkdir -p data credentials
# edit .env and set SECRET_KEY_BASE + PHX_HOST

# create or copy secrets.json in repo root
# optionally place Caseta cert/key files under ./credentials

docker compose up -d
```

What happens on container startup:
- release migrations run automatically
- bridge rows are seeded from `secrets.json` on first boot if the file exists
- the Phoenix server starts on port `4000`

Files involved:
- `docker-compose.yml`
- `Dockerfile`
- `docker/start.sh`
- `.env`
- `secrets.json`

### Pi-friendly first boot checklist

1. Clone the repo.
2. Create `.env` from `.env.example`.
3. Set `SECRET_KEY_BASE` with:

```bash
mix phx.gen.secret
```

4. Set `PHX_HOST` to the hostname or IP you will use to reach the Pi.
5. Create `secrets.json` in repo root.
6. Create the local storage directories:

```bash
mkdir -p data credentials
```

7. If using Caseta, place cert/key material under `./credentials` and reference container paths like `/credentials/bridge.crt` in `secrets.json`.
8. Start the stack:

```bash
docker compose up -d
```

9. Tail logs if needed:

```bash
docker compose logs -f
```

### Docker runtime notes

- SQLite is persisted in the bind-mounted `./data` directory.
- `secrets.json` is bind-mounted read-only to `/run/hueworks/secrets.json`.
- `CREDENTIALS_ROOT` is set to `/credentials` in Docker, and `./credentials` is mounted there read/write so UI-uploaded Caseta certs persist.
- The Docker build context excludes local secrets and credentials via `.dockerignore`, so those files are not baked into the image.
- A seed marker is stored at `./data/.bridges_seeded` (mounted as `/data/.bridges_seeded` in the container), so automatic bridge bootstrap only happens once per persisted data directory.

### Docker backup / restore

Create a timestamped backup of the live SQLite database:

```bash
mkdir -p backups
cp data/hueworks.db "backups/hueworks-$(date +%Y%m%d-%H%M%S).db"
```

Recommended baseline:
- keep at least one known-good manual backup before upgrades
- keep a few recent backups if you expect to iterate on imports/schema often

Restore from a backup:

```bash
docker compose down
cp backups/hueworks-YYYYMMDD-HHMMSS.db data/hueworks.db
docker compose up -d
```

If you want to force bridge bootstrap again after restoring onto a fresh environment, remove the seed marker before restart:

```bash
rm -f data/.bridges_seeded
```

### Docker upgrade / rollback

Upgrade flow:

```bash
# optional but recommended first
mkdir -p backups
cp data/hueworks.db "backups/hueworks-pre-upgrade-$(date +%Y%m%d-%H%M%S).db"

git pull
docker compose down
docker compose up -d --build
docker compose logs -f
```

What to expect:
- release migrations run automatically on boot
- bridge bootstrap is skipped after first successful seed
- the app starts on port `4000`

Rollback flow:

```bash
docker compose down
git checkout <previous-known-good-revision>
cp backups/hueworks-pre-upgrade-YYYYMMDD-HHMMSS.db data/hueworks.db
docker compose up -d --build
docker compose logs -f
```

If a migration has already changed the DB shape, restore the pre-upgrade backup before rolling back the image.

### Docker smoke check

After first boot or an upgrade, this is the quickest sanity pass:

1. `docker compose ps` shows the `hueworks` container as running.
2. `docker compose logs --tail=200` shows:
   - migration success or `Migrations already up`
   - bridge seed success on first boot, or seed-marker skip on later boots
   - `Running HueworksWeb.Endpoint`
3. Open the app in a browser and confirm the home page and a LiveView page such as `/lights` both load.
4. Confirm your seeded bridges appear in the config UI.
5. If using Caseta cert files, confirm the configured paths resolve under `/credentials/...`.
6. If using a reverse proxy or hostname, confirm `PHX_HOST` matches the host you are actually visiting so LiveView sockets connect cleanly.

## Optional CLI Import Flow

The UI is the primary path, but CLI tasks are available:

```bash
mix export_bridge_imports
mix normalize_bridge_imports
mix materialize_bridge_imports
mix link_bridge_imports
```

Output:
- raw exports: `exports/*_raw_*.json`
- normalized exports: `exports/*_normalized_*.json`

## Mix Tasks and Commands

### Common aliases

```bash
# one-time local bootstrap
mix setup

# create DB + run migrations
mix ecto.setup

# drop DB + recreate + migrate + seed
mix ecto.reset

# frontend tool install
mix assets.setup

# build assets for dev
mix assets.build

# minified asset build for deploy
mix assets.deploy
```

### Bridge/import workflow

```bash
# seed bridge rows from secrets.json
mix seed_bridges

# export raw bridge payloads
mix export_bridge_imports

# normalize exported payloads
mix normalize_bridge_imports

# materialize normalized data into DB
mix materialize_bridge_imports

# link canonical entities across sources
mix link_bridge_imports
```

### Quality and operations

```bash
# run test suite
mix test

# static analysis
mix credo

# backup / restore sqlite DB files
mix backup_db
mix restore_db
```

## License

Copyright © 2025
