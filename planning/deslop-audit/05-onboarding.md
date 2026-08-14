# Chunk 5 — Bridge Onboarding & Connection Tests

Status: AUDIT COMPLETE. **No findings.** Coverage: line-by-line for `hue/pairing.ex`, `bridge_onboarding/mdns.ex` (hueworks_app), `connection_test/{message,z2m,caseta}.ex`, `bridge_onboarding/hue.ex`, `hue/vendor_discovery.ex`; structural scan for the remaining small files (`caseta/*`, `home_assistant/*`, `hue/{device,mdns}.ex`, `mdns_transport.ex`, `connection_test/{hue,home_assistant}.ex`).

This chunk is what boundary code should look like: injectable transports for tests, user-facing error messages centralized in `ConnectionTest.Message`, defensive clauses that guard genuinely external data (DNS records, HTTP bodies, retained MQTT payloads).

## Explicitly Fine / Leave-Alone

- **`ConnectionTest.Message` clause fan-out** — deliberate per-error-shape UX copy; the catch-alls are reachable (arbitrary transport errors).
- **`Hue.Pairing` string-error returns** — errors double as user-facing copy by design; consistent within the onboarding plane.
- **`Mdns` record parsing** — defensive against real-world mDNS junk; correct.
- **`ConnectionTest.Z2M.fetch_opt` bare `to_existing_atom`** — already ruled intentional (see chunk 3 Leave-Alone, DM1 refutation).
- **`safe_discover` rescue in `BridgeOnboarding.Hue`** — wraps network discovery; boundary.
