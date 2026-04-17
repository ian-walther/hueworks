# HueWorks

HueWorks is a local-first smart home lighting controller for homes that span multiple lighting systems and bridge types.

It imports devices from Hue, Caseta, Home Assistant, and Zigbee2MQTT, links them into a canonical model, and gives you one place to manage lights, rooms, scenes, circadian light states, and Pico button bindings.

## What HueWorks Does

- Imports and reimports bridge data with a review/apply workflow
- Tracks canonical lights, groups, rooms, scenes, and active scenes in SQLite
- Maintains in-memory physical state and desired state for live control
- Applies scenes through a queued executor so changes can be planned and dispatched consistently per bridge
- Exports HueWorks scenes and optional entities back into Home Assistant over MQTT
- Lets you configure Caseta Picos with room-scoped control groups and scene bindings

## Supported Integrations

- Philips Hue
- Lutron Caseta
- Home Assistant
- Zigbee2MQTT

## Main UI Surfaces

- `/config`
  - global solar settings
  - Home Assistant MQTT export
  - light state configs
  - bridge list and bridge setup entrypoints
- `/config/bridge/:id/setup`
  - import/reimport review and apply
- `/config/bridge/:id/picos`
  - Pico list and per-device configuration
- `/config/bridge/:id/external-scenes`
  - Home Assistant scene mapping
- `/lights`
  - live control for lights and groups
  - display name edits
  - link management
  - manual overrides
- `/rooms`
  - room CRUD
  - occupancy toggles
  - scene activation
- `/rooms/:room_id/scenes/new`
- `/rooms/:room_id/scenes/:id/edit`
  - scene builder and scene editing
- `/config/light-states/new/manual`
- `/config/light-states/new/circadian`
- `/config/light-states/:id/edit`
  - manual and circadian light state editing

## Runtime Overview

HueWorks has four main runtime layers:

1. Import and persistence
   - bridge setup, import, normalization, materialization, linking
   - canonical entities stored in SQLite through Ecto
2. Control runtime
   - physical state and desired state in ETS
   - planner + executor turn desired room/light state into bridge-specific actions
3. Bridge integration layer
   - import clients, control adapters, and event stream subscriptions per integration
4. LiveView UI
   - configuration, control, scene editing, and Pico management

At runtime, `Hueworks.Application` supervises the Repo, PubSub, caches, control runtime, event streams, optional circadian poller, optional Home Assistant export runtime, and the Phoenix endpoint.

## Getting Started

### Local Development

```bash
mix setup
mix seed_bridges
iex -S mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

If you are starting from a clean database and want the bridge seed step included, you can also use:

```bash
mix ecto.reset
```

### Required Secrets

Bridge seeds are loaded from `secrets.json` in the repo root by default. You can override that path with `BRIDGE_SECRETS_PATH`.

Example:

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
mix seed_bridges
```

Caseta credential files uploaded through the UI are stored under `priv/credentials/caseta/` by default. You can override the root with `CREDENTIALS_ROOT`.

## Docker

For a fresh deployment:

```bash
cp .env.example .env
mkdir -p data credentials

# set SECRET_KEY_BASE and PHX_HOST in .env
# create or copy secrets.json into the repo root

docker compose up -d
```

What startup does:

- runs release migrations automatically
- seeds bridges from `secrets.json` on first boot if present
- starts the Phoenix server on port `4000`

Persistent data:

- SQLite database: `./data`
- uploaded credentials: `./credentials`

Useful commands:

```bash
docker compose logs -f
docker compose ps
```

## Common Mix Tasks

```bash
# dependencies, DB, and frontend tooling
mix setup

# create DB and run migrations
mix ecto.setup

# drop, recreate, migrate, and seed
mix ecto.reset

# seed bridge rows from secrets.json
mix seed_bridges

# bridge import pipeline
mix export_bridge_imports
mix normalize_bridge_imports
mix materialize_bridge_imports
mix link_bridge_imports

# database backup helpers
mix backup_db
mix restore_db

# quality
mix test
mix credo
mix dialyzer
```

## Development Notes

- `ADVANCED_DEBUG_LOGGING=true` enables verbose planner and control logs.
- `BRIDGE_SECRETS_PATH=/path/to/secrets.json` overrides the default seed file path.
- `CREDENTIALS_ROOT=/path/to/credentials` overrides where uploaded bridge credentials are stored.
- `ha_export_runtime_enabled` and `circadian_poll_enabled` can be toggled through application config if you need to disable those runtimes in a given environment.

## License

HueWorks is source-available under the PolyForm Noncommercial License 1.0.0.

- Noncommercial use is allowed under the terms in `LICENSE`
- Commercial use is not allowed without separate permission

This project is not open source in the OSI sense.
Unless otherwise noted, the license in `LICENSE` applies to all code in this repository and its git history authored by Ian Walther.

Copyright © 2026 Ian Walther
