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

# Create DB, migrate, and seed bridges from secrets.env
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

Create `secrets.env` in repo root:

```bash
export HUE_API_KEY="..."
export HUE_API_KEY_DOWNSTAIRS="..."
export LUTRON_CERT_PATH="/path/to/bridge.crt"
export LUTRON_KEY_PATH="/path/to/bridge.key"
export LUTRON_CACERT_PATH="/path/to/bridge-ca.crt"
export HA_TOKEN="..."
```

Then run:

```bash
mix ecto.reset
```

or reseed only:

```bash
mix seed_bridges
```

Caseta credentials can also be uploaded through the UI and are stored under `priv/credentials/caseta/`.

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
# seed bridge rows from secrets.env
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
