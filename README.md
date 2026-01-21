# HueWorks

Professional-grade lighting control for commodity smart bulbs.

HueWorks brings Lutron HomeWorks-style functionality to commodity smart lighting systems, eliminating "popcorning" effects through intelligent command optimization and group coordination.

## Project Status

**Phase 0: Vertical Slice Exploration**

This project is in early development. The current focus is on building throwaway vertical slices to understand API constraints before designing the final architecture.

## Core Vision

- **Problem**: Home Assistant's lighting control causes lights to turn on/off one at a time
- **Solution**: Intelligent command batching, group detection, and hardware optimization
- **Target**: Power users with 50+ bulbs who want professional lighting behavior without the professional price tag

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
- 80%+ test coverage enforced in CI
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

Visit `http://localhost:4000` to see the exploration UI.

## Database Seeding Workflow

Bridge records are seeded before any imports so credentials live in the database.

1) Create `secrets.env` at the repo root:

```bash
export HUE_API_KEY="..."
export LUTRON_CERT_PATH="/path/to/bridge.crt"
export LUTRON_KEY_PATH="/path/to/bridge.key"
export LUTRON_CACERT_PATH="/path/to/bridge-ca.crt"
export HA_TOKEN="..."
```

2) Reset the DB (migrations only):

```bash
mix ecto.reset
```

3) Seed bridges from `secrets.env`:

```bash
mix seed_bridges
```

4) Fetch raw bridge configuration to JSON:

```bash
mix export_bridge_imports
```

## Mix Tasks

- `mix backup_db` — Back up the SQLite database with a timestamp suffix.
- `mix restore_db` — Restore the most recent SQLite database backup.
- `mix seed_bridges` — Seed bridges from `secrets.env` with `import_complete=false`.
- `mix export_bridge_imports` — Fetch raw bridge configuration and write JSON to `exports/`.

## License

Copyright © 2025
