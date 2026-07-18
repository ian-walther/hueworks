# Compatibility And Known Limitations

## Deployment

- Docker Compose is the primary owner-install path.
- Direct Mix setup is supported for development and contribution.
- HueWorks is intended only for a trusted local network and has no browser authentication.
- The application listens over HTTP. A private reverse proxy may provide browser-facing HTTPS when `PHX_HOST`, `PHX_SCHEME`, and `PHX_URL_PORT` describe that canonical URL.

## Bridges

### Philips Hue

- Local mDNS and the bounded official Hue discovery service are supported.
- Link-button pairing and API-key creation happen inside HueWorks.
- The current integration uses the Hue v1 HTTP API for import and control.

### Lutron Caseta

- Import, control, Pico discovery, Pico binding, and LEAP event updates are supported for bridges with valid LEAP certificates.
- Connection validation performs a read-only LEAP request.
- Guided certificate acquisition is not yet implemented; certificate upload remains a pre-release setup limitation.

### Home Assistant Import

- Official local mDNS instance discovery is supported.
- A long-lived access token is still required until browser OAuth and refresh-token management are implemented.
- Import supports light entities, supported groups, areas, ZHA group metadata, and external scene mapping.
- Import native Hue, Caseta, and Zigbee2MQTT bridges before Home Assistant. Reverse ordering can leave visible wrapper/native twins that require later cleanup.

### Zigbee2MQTT

- Plain MQTT on TCP is supported, with optional username/password and custom base topic.
- Setup validates retained `bridge/devices` and `bridge/groups` JSON before saving.
- MQTT-over-TLS is not currently supported.
- Broker discovery is not guaranteed; manual broker configuration remains authoritative.

## Integrations

### Home Assistant MQTT Export

- Scene controls, area scene selectors, opt-in lights/groups, and writable Presence Inputs are supported.
- MQTT settings describe export from HueWorks to Home Assistant; they are separate from importing Home Assistant as a bridge.

### HomeKit

- On/off behavior is the stable capability.
- Brightness is available but may be laggy or intermittently miss commands.
- Color and temperature should not be treated as release-quality behavior.
- Docker requires the HomeKit host-network overlay for reliable mDNS advertisement on Linux.

### AI API And MCP

- The API is opt-in and intended for local diagnostics and explicit normal control actions.
- It is not a remote-access security boundary and must not be exposed publicly.
