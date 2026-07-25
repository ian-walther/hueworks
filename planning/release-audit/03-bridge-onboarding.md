# Chunk 3: Bridge Onboarding & Discovery

Status: complete; implementation reconciled 2026-07-26. Scope: `lib/hueworks/bridge_onboarding/**`, `bridges.ex` delta, connection tests, `BridgeLive` add-bridge flow, `BridgeSetupLive` import review shell. No open findings.

## Refutations (permanent record)

- **BO-2 — retired, auditor error.** The original claim was that discovered Hue bridges are pairable even when already configured. Wrong: `decorate_hue_devices/1` (and `decorate_ha_devices/1`) match every discovery against existing bridges by `external_id` **or host**, the template renders a "configured" badge and hides the pair/select action, and `find_pairable_hue`/`find_selectable_ha` refuse `configured?` devices outright. The `unique_constraint` + "already configured" message is only the race backstop, as it should be. The audit erred by reading the `.ex` flow before the template.

## Parked For Chunk 8 (gap analysis, not regressions)

- mDNS `host` falls back to the `.local` target name when no A record is in the response; `.local` names generally don't resolve inside the primary Docker topology. Already an explicit open blocker ("Discovery In Production Topology") — verify during the rehearsal.
- Guided Caseta LEAP pairing and `_mqtt._tcp` Z2M discovery assistance remain documented Remaining Release Blockers, not regressions in this range.

## Explicitly Fine / Leave-Alone

- **Vendor cloud discovery is now a true fallback** (formerly BO-1, implemented): `discovery.meethue.com` is contacted only when local mDNS yields zero devices, with tests proving both the skip and the fallback path. The merged-sources design (`Device.merge`, `sources:` provenance) is unchanged for when the fallback does run.
- **Source identity now survives to persistence** (formerly BO-3, implemented): `ConnectionTest.Hue` extracts and normalizes `bridgeid` alongside the name; `apply_test_result` threads it into `source_external_id`; `save_bridge` persists it for hue/caseta (covering both the HA-inventory prefill hand-off and manual entry). End-to-end LiveView tests cover manual Hue and discovered Caseta saves.
- **One shared mDNS parser + transport** (formerly BO-4, implemented with CL-1): see chunk 10.
- **Human error vocabulary** (formerly BO-5, implemented): `Hueworks.ConnectionTest.Message` translates nxdomain/refused/timeout/HTTP-status classes per bridge type with bounded (160-char) detail suffixes; `Hueworks.Import.ApplyError` translates the known apply rollback tuples and bounds the fallback `inspect`; both import LiveViews route through them. The reference vocabulary for future error surfaces.
- **Async discipline in `BridgeLive`**: every network operation (discover, pair, test) runs via `start_async` with per-request staleness guards on both `{:ok, _}` and `{:exit, _}` arms, and `update_bridge` resets test state on any field change so a stale "Test passed" can't authorize saving different credentials. The request-id pattern matches the prior audit's reference implementation.
- **Test-before-proceed enforcement** (`proceed_bridge` refuses unless `test_status == :ok`) and **RuntimeIO gating** of discovery/pairing/connection tests: correct and honest.
- **Hue pairing flow** (`Pairing.pair/3`): register → validate-with-new-key → identity verify against the discovered bridgeid, with distinct copy for the link-button state (type 101), sanitized/truncated bridge-supplied descriptions, and no partial bridge rows. Meets "validation before persistence" cleanly.
- **Caseta and Z2M connection-test upgrades**: Caseta performs a real LEAP `/device` read through the shared `CasetaLeap` module; Z2M validates actual retained `devices`/`groups` payloads through the `Z2MConfig`/snapshot vocabulary and reports counts. Both reuse the canonical modules — the desired pattern.
- **`Device.normalize/merge`** (id-or-host identity, source provenance, mDNS-first merge order) and **`safe_discover`** isolating discovery crashes: sound.
- **New `Bridges` helpers** (`any_bridges?`, `ha_import_order_risk`, `import_summary`): read-only projections; `ha_import_order_risk` is the mechanism behind "reverse-order risk visible before import". Dual-key `fetch_map` is correct import-plane convention.
- **IPv4-only address resolution** in mDNS parsing: acceptable for the trusted-LAN scope; revisit only if a real IPv6-only household shows up.
