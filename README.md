# HueWorks

Professional-grade lighting control for commodity smart bulbs.

HueWorks brings Lutron HomeWorks-style functionality to commodity smart lighting systems, eliminating "popcorning" effects through intelligent command optimization and group coordination.

## Project Status

**Phase 0: Foundations + Control UI**

HueWorks is in active early development with a working import pipeline, LiveView setup wizard, and basic control UI. The core value prop (group batching to eliminate popcorning) is not implemented yet, but the schema, import flow, and control scaffolding are in place.

## Core Vision

- **Problem**: Home Assistant's lighting control causes lights to turn on/off one at a time
- **Solution**: Intelligent command batching, group detection, and hardware optimization
- **Target**: Power users with 50+ bulbs who want professional lighting behavior without the professional price tag

## Features (Current)

- Multi-bridge import pipeline (Hue, Home Assistant, Caseta)
- LiveView bridge setup wizard (add bridge, test credentials, import, review, apply)
- Control UI for lights and groups (Hue + Home Assistant fully wired; Caseta lights only)
- Event stream subscriptions (Hue SSE, Home Assistant WebSocket, Caseta LEAP) feeding in-memory state
- Rooms + scenes CRUD UI (scene activation not implemented yet)
- Kelvin mapping helpers and per-entity override controls

## Features (Planned)

- Multi-vendor bridge support (Philips Hue, Zigbee2MQTT, Lutron Caseta)
- Command aggregation and optimization
- Circadian rhythm lighting
- Scene management
- Home Assistant integration
- Physical switch support (Pico remotes)

## Development Philosophy

- Test-Driven Development from day one
- Type specifications on all public functions
- Test coverage is growing (import + kelvin paths have tests; control + contexts still need coverage)
- Learn by building vertical slices first, then abstract

## Getting Started

```bash
# Install dependencies
mix deps.get

# Create database, run migrations, and seed bridges
mix ecto.reset

# Optional: re-run seeds without resetting
mix run priv/repo/seeds.exs

# Set up and build assets
mix assets.setup
mix assets.build

# Start the application
iex -S mix phx.server
```

Visit `http://localhost:4000` and use the UI:

- `/config` to add a bridge and run the import wizard
- `/lights` to control lights/groups and tune kelvin ranges
- `/rooms` to manage room names and scenes

The `/explore` route is a placeholder.

## Architecture Tour

If you want to orient quickly, these are the main flows and modules:

- **Bridge setup + import wizard (UI)**: `/config` and `/config/bridge/:id/setup`  
  `lib/hueworks_web/live/config/bridge_live.ex`  
  `lib/hueworks_web/live/config/bridge_setup_live.ex`
- **Import pipeline (core)**: fetch → normalize → plan → materialize → link  
  `lib/hueworks/import/pipeline.ex`  
  `lib/hueworks/import/normalize/*.ex`  
  `lib/hueworks/import/materialize.ex`  
  `lib/hueworks/import/link.ex`
- **Control dispatch** (per-bridge implementations)  
  `lib/hueworks/control/light.ex`  
  `lib/hueworks/control/group.ex`
- **Event subscriptions → in-memory state**  
  `lib/hueworks/subscription/*`  
  `lib/hueworks/control/state.ex`
- **UI control screens**  
  `lib/hueworks_web/live/lights_live.ex`  
  `lib/hueworks_web/live/rooms_live.ex`
- **Domain + schema**  
  `lib/hueworks/schemas/*`  
  `lib/hueworks/lights.ex`, `lib/hueworks/groups.ex`, `lib/hueworks/rooms.ex`

## Import Pipeline Overview

There are two ways to run imports: the UI wizard or the CLI mix tasks. Under the hood they share the same pipeline.

**Pipeline steps**
1) **Fetch raw data** from each bridge into a JSON blob.
2) **Normalize** into a common shape (rooms, groups, lights, memberships).
3) **Plan** a default review plan (what to create/skip/merge).
4) **Materialize** into the database.
5) **Link** canonical entities across imports (primarily HA ↔ Hue/Caseta).

**CLI path (optional)**
```bash
mix export_bridge_imports
mix normalize_bridge_imports
mix materialize_bridge_imports
mix link_bridge_imports
```

**Output files**
- Raw files: `exports/*_raw_*.json`
- Normalized files: `exports/*_normalized_*.json`

## Bridge Credentials + Seeding Workflow

Bridge records live in the database. You can either seed via `secrets.env` or use the UI wizard.

1) Create `secrets.env` at the repo root:

```bash
export HUE_API_KEY="..."
export LUTRON_CERT_PATH="/path/to/bridge.crt"
export LUTRON_KEY_PATH="/path/to/bridge.key"
export LUTRON_CACERT_PATH="/path/to/bridge-ca.crt"
export HA_TOKEN="..."
```

2) Reset the DB (migrations + seeds):

```bash
mix ecto.reset
```

3) Optional: re-run seeds without resetting:

```bash
mix seed_bridges
```

4) Optional: run the CLI import pipeline:

```bash
mix export_bridge_imports
mix normalize_bridge_imports
mix materialize_bridge_imports
mix link_bridge_imports
```

Notes:
- The UI setup wizard can do import + review + apply without any CLI steps.
- Caseta credentials can also be uploaded via the UI and are stored under `priv/credentials/caseta/`.

## Mix Tasks

- `mix backup_db` — Back up the SQLite database with a timestamp suffix.
- `mix restore_db` — Restore the most recent SQLite database backup.
- `mix seed_bridges` — Seed bridges from `secrets.env` with `import_complete=false`.
- `mix export_bridge_imports` — Fetch raw bridge configuration and write JSON to `exports/`.
- `mix normalize_bridge_imports` — Normalize raw bridge JSON into `exports/*_normalized_*.json`.
- `mix materialize_bridge_imports` — Materialize normalized bridge JSON into the database.
- `mix link_bridge_imports` — Link canonical entities across imports.

## License

Copyright © 2025
