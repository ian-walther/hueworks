# Chunk 10 (Phase 2): Caseta Discovery, Location Lookup, Remaining Deltas

Status: complete; implementation reconciled 2026-07-26. Scope: Caseta discovery groundwork, postal-code lookup + general-config wiring, HA inventory prefill, control retry adoption, setup/config copy. Guided Caseta LEAP *pairing* remains an open release blocker (tracked in chunk 8's gap table), not a finding here. No open findings.

## Explicitly Fine / Leave-Alone

- **One mDNS parser, one transport** (formerly CL-1 + BO-4, implemented): `Hueworks.BridgeOnboarding.Mdns` owns record walking (ptr/srv/txt/address assembly) and routes queries through `MdnsTransport` (multi-response UDP collection) for all three integrations; adapters shrank to 38/68 lines keeping only service constants, timeouts, device construction, and Caseta's targeted `lutron-<serial>.local` resolution. Shared parser tests + per-adapter construction tests. Zero duplicate record walkers remain.
- **Direct module contracts** (formerly CL-2, implemented): both Caseta discovery call sites call `module.resolve/1`/`discover/1` directly — no `Code.ensure_loaded?` reflection masking incomplete doubles.
- **Postal lookup disclosure** (formerly CL-3, implemented): the general-settings form states "Looks up coordinates via zippopotam.us; only the country and postal code are sent," `docs/compatibility.md` records the same external call with the manual/browser alternatives, and LiveView coverage asserts the disclosure renders.
- **Setup copy vocabulary** (formerly CL-4, implemented): the HA inventory description uses real HA vocabulary (Floors, Areas, Lights/Groups), terminal punctuation restored, with a regression test rejecting the "Rooms" phrasing.
- **Caseta targeted resolve** (strict `^[0-9a-f]{8}$` serial validation, browse fallback): good design for "find the bridge HA told us about"; the serial regex matches the inventory extractor's, keeping the prefill hand-off consistent — and that identity now persists at save (chunk 3, formerly BO-3).
- **HA inventory prefill**: native-source cards carry `external_id` (Hue bridgeid from device-registry identifiers, Caseta serial from entry title) and `host` (Z2M broker) for prefilled, pre-verified native setup. Read-only, defensive `Normalize.fetch` parsing throughout.
- **Control light/group adoption of `HomeAssistantBridge.request/2`**: the 401-retry-once helper wraps HA control calls; closes the "no caller reads the permanent token" loop.
- **`PostalCodeLookup` implementation**: strict validation before any request, URI-encoded path, bounded timeouts, status-classified errors, coordinate range validation, `start_async` in the LiveView.
