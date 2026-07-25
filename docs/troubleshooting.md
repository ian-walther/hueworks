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

## Home Assistant Authorization Fails

- Confirm `PHX_HOST`, `PHX_SCHEME`, and `PHX_URL_PORT` describe the trusted-LAN URL open in your browser. Home Assistant must be able to return the browser to that same HueWorks origin.
- Retry from Config > Bridges. An expired, cancelled, or already-used callback cannot be replayed.
- If Home Assistant revokes the refresh token, the bridge card shows Authorization required and offers a reconnect action without deleting imported entities.
- Use a manual long-lived token only when discovery or browser authorization cannot work across the network boundary; HueWorks cannot refresh that fallback credential.

## Postal Code Lookup Fails

- Postal-code lookup requires outbound internet access from the HueWorks server.
- Confirm the two-letter country code and ZIP or postal code are valid. Coverage and precision vary by country.
- Use browser geolocation or enter latitude and longitude manually when the lookup service is unavailable. Lookup only prefills the form; settings are not changed until saved.

## Reimport Safety

Reimport is a review of upstream differences, not a replacement initial import. Automatic bridge-owned refreshes are disclosed, while user-facing changes require explicit resolutions. If a review becomes stale, refresh it rather than retrying an old apply request.

## HomeKit Shows No Response

- Confirm Config reports the runtime as running rather than disabled or unavailable.
- Confirm `HOMEKIT_RUNTIME_ENABLED=true`, the static HomeKit port is reachable, and the Linux host-network overlay is active where required.
- If Apple Home and HueWorks pairing state diverge, remove the bridge from Apple Home, use Reset Pairing in HueWorks, and pair again.

## Before Reporting A Bug

Include the HueWorks version shown on Config, bridge type, sanitized error text, whether the operation was import/control/event update, and the smallest reproduction sequence. Never include tokens, certificates, database files, public household addresses, or unsanitized topology.
