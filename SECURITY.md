# Security Policy

## Deployment Boundary

HueWorks is an unauthenticated trusted-LAN appliance. Every client that can reach its web endpoint can control lights, inspect configuration, upload bridge credentials, and perform confirmed destructive actions.

Never expose HueWorks directly to the public Internet, an untrusted VLAN, a public tunnel, or a port-forward. A private reverse proxy may terminate HTTPS for a trusted LAN, but HTTPS alone does not add authentication or authorization.

The optional AI API is token-authenticated and disabled by default. That token protects the API only; it does not protect the browser UI.

## Secrets

- Keep `.env`, `secrets.json`, bridge certificates, database files, HomeKit pairing data, and AI API tokens out of source control.
- Restrict access to `./data` and `./credentials` on the Docker host.
- Rotate an AI API token from Config after suspected disclosure.
- Reauthorize or re-pair an integration after its credential is exposed.

## Reporting

Do not post exploitable security details, credentials, database contents, or household topology in a public issue. Contact the maintainer privately with the affected version, deployment topology, reproduction steps, and sanitized logs.

Security support currently follows the latest revision of the project. There is no guaranteed patch window for older revisions before the first public release.
