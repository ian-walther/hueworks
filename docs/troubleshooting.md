# Troubleshooting

## Start With Health

```bash
docker compose ps
curl http://localhost:4000/health
docker compose logs --tail=200 hueworks
```

`/health` reports only application version, database readiness, and core control-process readiness. A healthy response does not claim every optional bridge is connected.

## Startup Fails Before Migrations

HueWorks runs as UID 1000 in the container. If `./data` or `./credentials` is not writable:

```bash
sudo chown -R 1000:1000 data credentials
docker compose up -d
```

Migration startup stops before changing schema when the pre-migration backup cannot be created. Check free space and permissions under `./data/backups`.

## Discovery Finds Nothing

- Confirm HueWorks and the bridge are on the same multicast-capable LAN.
- Container networks and routed VLANs may block mDNS even when direct traffic works.
- Use the manual address fallback for segmented networks.
- HomeKit discovery from Docker on Linux requires `docker-compose.homekit.yml` and host networking.

## Zigbee2MQTT Validation Fails

- Confirm host, port, username/password, and base topic.
- Ensure retained `<base_topic>/bridge/devices` and `<base_topic>/bridge/groups` messages exist.
- Ensure the MQTT account can subscribe to those topics.
- TLS MQTT brokers are not currently supported.

## Reimport Safety

Reimport is a review of upstream differences, not a replacement initial import. Automatic bridge-owned refreshes are disclosed, while user-facing changes require explicit resolutions. If a review becomes stale, refresh it rather than retrying an old apply request.

## HomeKit Shows No Response

- Confirm Config reports the runtime as running rather than disabled or unavailable.
- Confirm `HOMEKIT_RUNTIME_ENABLED=true`, the static HomeKit port is reachable, and the Linux host-network overlay is active where required.
- If Apple Home and HueWorks pairing state diverge, remove the bridge from Apple Home, use Reset Pairing in HueWorks, and pair again.

## Before Reporting A Bug

Include the HueWorks version shown on Config, bridge type, sanitized error text, whether the operation was import/control/event update, and the smallest reproduction sequence. Never include tokens, certificates, database files, public household addresses, or unsanitized topology.
