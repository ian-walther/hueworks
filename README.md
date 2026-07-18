# HueWorks

HueWorks is a local-first smart home lighting controller for homes that span multiple lighting systems and bridge types.

It imports devices from Hue, Caseta, Home Assistant, and Zigbee2MQTT, links them into a canonical model, and gives you one place to manage lights, areas, scenes, circadian light states, and Pico button bindings.

## What HueWorks Does

- Imports and reimports bridge data with a review/apply workflow
- Tracks canonical lights, groups, areas, scenes, and active scenes in SQLite
- Maintains in-memory physical state and desired state for live control
- Applies scenes through a queued executor so changes can be planned and dispatched consistently per bridge
- Exports HueWorks scenes and optional entities back into Home Assistant over MQTT
- Provides area-scoped Presence Inputs that Home Assistant can write over MQTT as simple occupied/unoccupied booleans
- Lets scene components follow Presence Inputs for per-light or nested-group power policy decisions
- Lets you configure Caseta Picos with area-scoped control groups and scene bindings

## Supported Integrations

- Philips Hue
- Lutron Caseta
- Home Assistant
- Zigbee2MQTT

## Main UI Surfaces

- `/config`
  - first-run checklist and system readiness
- `/config/general`
  - location, timezone, and transition defaults
- `/config/bridges`
  - bridge setup, initial import, and reimport entrypoints
- `/config/bridges/:id/import`
  - initial import review and apply
- `/config/bridges/:id/reimport`
  - upstream change review and explicit resolutions
- `/config/bridges/:id/picos`
  - Pico list and per-device configuration
- `/config/bridges/:id/external-scenes`
  - Home Assistant scene mapping
- `/config/integrations`
  - Home Assistant MQTT export, HomeKit, and local AI API
- `/lights`
  - live control for lights and groups
  - display name edits
  - link management
  - manual overrides
- `/areas`
  - area CRUD
  - presence input management
  - scene activation
- `/areas/:area_id/scenes/new`
- `/areas/:area_id/scenes/:id/edit`
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
   - planner + executor turn desired area/light state into bridge-specific actions
3. Bridge integration layer
   - import clients, control adapters, and event stream subscriptions per integration
4. LiveView UI
   - configuration, control, scene editing, and Pico management

At runtime, `Hueworks.Application` supervises the Repo, PubSub, caches, control runtime, event streams, optional circadian poller, optional Home Assistant export runtime, and the Phoenix endpoint.

## Getting Started

### First-Run Journey

After startup, open HueWorks at the configured `PHX_HOST` and port. An empty installation routes to Config and shows a state-derived checklist:

1. Set location and timezone under General.
2. Add native bridges before Home Assistant so mirrored HA entities can be recognized as wrappers instead of visible duplicates.
3. Review and apply each initial import. Bridge areas can be created, merged into an existing HueWorks area, or skipped.
4. Review imported areas and lights.
5. Create and activate a first scene, then use Control for everyday operation.

Hue bridges can be discovered and paired through their physical link button without handling an API key. Home Assistant can be discovered locally but still uses a manually supplied long-lived token until browser OAuth is implemented. Zigbee2MQTT can reuse the configured Home Assistant-export MQTT connection and validates its retained snapshot before saving. Caseta currently requires certificate files; guided physical-button certificate acquisition remains pre-release work.

### Local Development

```bash
mix setup
iex -S mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

To discard local development data and recreate an empty database:

```bash
mix ecto.reset
```

Bridges are configured through the application. A clean setup does not require a seed file.

### Optional Bridge Seeds

`secrets.json` is an optional advanced bootstrap and recovery mechanism. It is not part of the normal setup path. To seed bridge rows from a file, create `secrets.json` in the repo root or override its location with `BRIDGE_SECRETS_PATH`.

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

This task fails explicitly when the requested file is missing. It is never run by `mix setup` or `mix ecto.reset`.

Caseta credential files uploaded through the UI are stored under `priv/credentials/caseta/` by default. You can override the root with `CREDENTIALS_ROOT`.

## Security boundary

HueWorks is deliberately an unauthenticated trusted-LAN appliance. Any client that can reach the web endpoint can control devices, inspect configuration, upload credentials, and perform confirmed destructive operations.

Never expose HueWorks to the public Internet. Do not port-forward it, publish it through a public tunnel, or make it reachable from an untrusted network or VLAN. Plain HTTP is supported only inside the isolated trusted LAN. An optional private HTTPS reverse proxy may set `PHX_SCHEME=https` and `PHX_URL_PORT`, but those settings describe the browser-facing canonical URL; HueWorks itself still listens over HTTP.

CSRF protection and WebSocket origin checks remain enabled as defense in depth, but they are not authentication. A future remote-access use case requires a new security design before any exposure, including authentication, authorization, TLS, session policy, and secret handling.

See [SECURITY.md](SECURITY.md) before deploying and use private security reporting rather than a public issue for credential exposure or control-boundary vulnerabilities.

## AI API And MCP

HueWorks includes an opt-in, token-authenticated JSON API at `/api/v1` for
local diagnostics and explicit operational controls. It is disabled by default.

1. Open `/config` and enable **AI API**.
2. Reveal and copy the generated token only into your local MCP configuration.
3. Rotate the token from the same panel whenever that local configuration needs
   to be revoked.

The API exposes separate observed physical state and desired state. A `null`
physical state means HueWorks has no current observation; it does not mean the
light is off. Recent planner/executor lifecycle evidence is available through
the bounded in-memory trace endpoint. API controls use the same scene and
manual-control paths as the UI, so a successful write means intent was accepted
and queued, not that a bridge has already converged.

Every API request requires `Authorization: Bearer <token>`. The available v1
read endpoints are `GET /api/v1/status`, `/api/v1/areas`, `/api/v1/areas/:id`,
`/api/v1/entities?query=...`, `/api/v1/lights/:id`, `/api/v1/groups/:id`,
`/api/v1/traces`, and the matching
`/api/v1/debug/areas/:id`, `/api/v1/debug/lights/:id`, and
`/api/v1/debug/groups/:id` projections. The intentionally
narrow write endpoints are:

| Endpoint | Operation |
| --- | --- |
| `POST /api/v1/scenes/:id/activate` | Activate or reapply one scene. |
| `DELETE /api/v1/areas/:id/active-scene` | Explicitly deactivate a area scene. |
| `POST /api/v1/lights/:id/control` | Send exactly one `power`, `brightness`, `kelvin`, or `color` command. |
| `POST /api/v1/groups/:id/control` | Apply the same explicit command through existing group membership. |
| `POST /api/v1/runtime/physical-state/refresh` | Start an asynchronous observed-state refresh. |

Manual color input uses `{ "color": { "hue": 0..360, "saturation": 0..100 } }`.
Brightness, temperature, and color remain unavailable while a area scene is
active, just as they are in the browser UI. Configuration, reimport, Pico
configuration, credentials, and destructive operations are deliberately not
available through the API.

`GET /api/v1/entities` searches lights and groups by `name` and `display_name`.
Its results include exact-match and controllability metadata so MCP clients can
resolve a name safely: a control action is appropriate only when
`exact_controllable_match_count` is exactly `1` and the selected result is an
exact, controllable match. Partial matches and ambiguous names require user
confirmation.

The repository includes a local stdio MCP adapter in `mcp/`. It runs on the AI
client machine, not inside the HueWorks Docker container:

```bash
npm --prefix mcp ci
npm --prefix mcp run build
```

Register the compiled adapter in the user's global `~/.codex/config.toml`:

```toml
[mcp_servers.hueworks]
command = "node"
args = ["/absolute/path/to/hueworks/mcp/dist/index.js"]
cwd = "/absolute/path/to/hueworks/mcp"
startup_timeout_sec = 15
tool_timeout_sec = 60
default_tools_approval_mode = "writes"
enabled = true

[mcp_servers.hueworks.env]
HUEWORKS_API_URL = "https://hueworks.home"
HUEWORKS_API_TOKEN = "copy-from-HueWorks-Config"
```

Use the base URL shown on the Config page. Do not commit the token or place it
in the MCP package. Rebuild the adapter and restart Codex after changing its
source or configuration. The adapter's own contract tests run with
`npm --prefix mcp test`.

## Docker

For a fresh deployment:

```bash
cp .env.example .env
mkdir -p data credentials

# The container runs as UID 1000. On Linux, make these bind mounts writable by that UID.
sudo chown -R 1000:1000 data credentials

# set SECRET_KEY_BASE and PHX_HOST in .env
# direct Compose access uses PHX_SCHEME=http; set https only behind TLS termination
# set PHX_URL_PORT when the public proxy port is not the scheme default

docker compose up -d
```

What startup does:

- checks for pending migrations and creates a consistent SQLite snapshot before applying them
- retains the five newest automatic pre-migration snapshots in `./data/backups` by default
- runs release migrations automatically after the safety snapshot succeeds
- starts the Phoenix server on port `4000`
- reports container health through the non-sensitive `GET /health` readiness endpoint

To use the optional bridge-seed bootstrap, create `secrets.json` and start with the seed overlay:

```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.seeds.yml docker compose up -d
```

The overlay seeds bridges once, records the successful bootstrap in `./data`, and leaves normal UI-based setup unchanged when the overlay is not selected.

Persistent data:

- SQLite database: `./data`
- HomeKit pairing data: `./data/homekit` by default, override with `HOMEKIT_DATA_PATH`
- uploaded credentials: `./credentials`

HomeKit runtime:

- Docker defaults `HOMEKIT_RUNTIME_ENABLED=false` so schema/config changes can be deployed before starting the HAP server.
- Set `HOMEKIT_RUNTIME_ENABLED=true` when you are ready to expose the bridge and pair with Apple Home.
- `HOMEKIT_PORT` defaults to `51827` so Apple Home does not have to rediscover a new HAP TCP port after every HueWorks restart.
- `HOMEKIT_MDNS_HOST` defaults to `hueworks`, which advertises the bridge at `hueworks.local` over IPv4-only mDNS. Keep normal DNS such as `hueworks.home` pointed at the same host for browser access, but HomeKit discovery itself uses mDNS.
- The Apple Home setup code is shown on the Config page in the HomeKit Bridge section.
- On first pairing, HueWorks initially exposes the bridge without child accessories, then publishes exposed lights/groups/scenes shortly after pairing completes. This avoids Apple Home's initial add flow prompting for dumb prefilled child names.
- If Apple Home and HueWorks get out of sync during pairing or testing, use Config -> HomeKit Bridge -> Reset Pairing to clear saved HomeKit controller pairings before adding the bridge again.
- Light/group HomeKit export can expose entities as on/off switches or dimmable lights. On/off control is the reliable path today; brightness is available for testing but can be laggy or intermittently miss commands.
- For production HomeKit pairing from Docker on Linux, set `COMPOSE_FILE=docker-compose.yml:docker-compose.homekit.yml` so the HAP server's mDNS advertisement and static TCP port are reachable on the LAN through host networking.

Home Assistant MQTT export:

- Scenes, area scene selectors, lights, groups, and Presence Inputs are published through Home Assistant MQTT discovery when Home Assistant export is enabled.
- A scene can use the scene editor's **Activation Transition** setting: `Default` follows the global manual timing, while `Custom` applies an unscaled fade whenever that scene is explicitly activated. The setting does not affect later circadian adjustments or presence changes.
- For an automation that needs a one-shot scene fade, publish JSON directly to the discovered command topic instead of using Home Assistant's normal scene/select service. Direct-scene example: `{"transition_ms":30000}`. Area-select example: `{"option":"Evening Auto","transition_ms":30000}`. Plain `ON` scene commands and plain area-select options remain supported.
- Presence Inputs are configured per area on `/areas` and exported as writable MQTT switches. `ON` means `Occupied`; `OFF` means `Unoccupied`.
- Scene components can use `Follow Presence` as a power policy for individual lights or nested groups. The policy resolves to on/off from the selected Presence Input when a scene is applied.
- Home Assistant owns Presence Input values. Changing one stores and republishes state, then recomputes only the active-scene lights that follow that specific input.

Useful commands:

```bash
docker compose logs -f
docker compose ps
curl http://localhost:4000/health

# Create a manual SQLite snapshot in ./data/backups.
docker compose exec hueworks /app/bin/hueworks eval 'Hueworks.Release.backup()'
```

Database restore is intentionally offline and destructive. Stop the normal service, choose an explicit backup path from `./data/backups`, run the one-off release command with the exact `RESTORE` confirmation, then start HueWorks again:

```bash
docker compose stop hueworks
docker compose run --rm --no-deps hueworks \
  /app/bin/hueworks eval 'Hueworks.Release.restore("/data/backups/hueworks_manual_YYYYMMDDTHHMMSS.db", "RESTORE")'
docker compose up -d
```

Restore validates the selected backup, preserves it, and creates a `*_pre_restore_*` recovery snapshot of the current database before replacement. `DATABASE_BACKUP_RETENTION` changes the automatic pre-migration retention count; manual and pre-restore snapshots are never pruned automatically.

## Common Mix Tasks

```bash
# dependencies, DB, and frontend tooling
mix setup

# create DB and run migrations
mix ecto.setup

# drop, recreate, and migrate to an empty database
mix ecto.reset

# optional advanced bridge bootstrap from secrets.json
mix seed_bridges

# legacy/offline bridge import file tools
mix export_bridge_imports
mix normalize_bridge_imports
mix materialize_bridge_imports

Manual bridge reimport through the web UI is the supported application workflow. The file tasks are retained for offline inspection and recovery workflows only.

# database backup helpers
# Creates a consistent SQLite snapshot beside the configured DB.
mix backup_db

# Stop any running HueWorks service before restore. Restore validates the backup,
# keeps the source backup, and creates a *_pre_restore_* recovery snapshot first.
mix restore_db --force
mix restore_db --force --backup /path/to/hueworks_YYYYMMDDTHHMMSS.db

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
- See [CONTRIBUTING.md](CONTRIBUTING.md) for the test and documentation expectations used in this repository.
- See [Compatibility and Known Limitations](docs/compatibility.md) and [Troubleshooting](docs/troubleshooting.md) before filing an integration issue.

## License

HueWorks is source-available under the PolyForm Noncommercial License 1.0.0.

- Noncommercial use is allowed under the terms in `LICENSE`
- Commercial use is not allowed without separate permission

This project is not open source in the OSI sense.
Unless otherwise noted, the license in `LICENSE` applies to all code in this repository and its git history authored by Ian Walther.

Copyright © 2026 Ian Walther
