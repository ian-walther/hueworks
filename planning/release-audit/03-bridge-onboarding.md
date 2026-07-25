# Chunk 3: Bridge Onboarding & Discovery

Status: complete. Scope: `lib/hueworks/bridge_onboarding/**`, `bridges.ex` delta, connection-test changes (Hue, Caseta, Z2M committed; HA via `git show HEAD:`), `BridgeLive` add-bridge flow (discovery/pairing/test/save), `BridgeSetupLive` import review shell. Read line-by-line except the heex templates (deferred to chunk 7 with the rest of the UI sweep).

## Findings

### BO-1: Hue vendor cloud discovery runs unconditionally, not as a fallback

- Severity: medium. Type: technical/privacy + UX.
- Location: `lib/hueworks/bridge_onboarding/hue.ex` `discover/1` — `results = [safe_discover(local), safe_discover(fallback)]` always queries both `MdnsLite` and `https://discovery.meethue.com/`.
- Problem: every click of "Discover" contacts Signify's cloud (revealing the household's public IP and receiving bridges registered to it) even when mDNS already answered, and adds up to ~5s of blocking latency to every discovery. The module is literally bound as `fallback:` but is not used as one. The refinement doc's discovery philosophy (advertised local services first; cloud as assistance) and the trusted-LAN posture both point the same way.
- Decision: query `VendorDiscovery` only when mDNS returns zero devices. Keep the merged-sources design (`Device.merge`, `sources:` provenance) unchanged for the case where the fallback does run.
- Guardrail: bridge_live tests already inject discovery modules; add one asserting the vendor module is not invoked when local discovery yields devices.
- Effort: S.

### BO-2 — REFUTED (recorded per the honest-refutation rule; do not implement)

The original claim was that discovered Hue bridges are pairable even when already configured. Wrong: `decorate_hue_devices/1` (and `decorate_ha_devices/1`) match every discovery against existing bridges by `external_id` **or host**, the template renders a "configured" badge and hides the pair/select action, and `find_pairable_hue`/`find_selectable_ha` refuse `configured?` devices outright. The `unique_constraint` + "already configured" message is only the race backstop, as it should be. The audit erred by reading the `.ex` flow before the template. ID retired.

### BO-3: Manual Hue setup never captures bridge identity, leaving duplicate detection host-string-dependent

- Severity: low. Type: technical.
- Location: `BridgeLive.bridge_external_id/1` returns `nil` for everything except HA; `ConnectionTest.Hue.test/2` already fetches `/api/<key>/config` and parses the body but discards `bridgeid`.
- Problem: manually-added Hue bridges persist with `external_id: NULL`. The discovery decoration's host-match fallback (see BO-2 refutation) covers most duplicate scenarios, but only when host strings compare equal — the same bridge reachable as `192.168.1.10` in one row and a hostname in another evades both the decoration and the `[:type, :external_id]` unique index (NULLs are distinct in SQLite).
- Decision: have `ConnectionTest.Hue` return `{:ok, %{name: name, external_id: normalized_bridgeid}}` (it already has the body), thread it through `apply_test_result`, and persist it in `save_bridge`. The test-before-proceed gate guarantees the value is present at save time.
- Guardrail: connection-test unit test for bridgeid capture; bridge_live test asserting a manual save records `external_id`.
- Effort: S-M.

### BO-4: `Hue.Mdns` and `HomeAssistant.Mdns` are ~90-line near-duplicates

- Severity: low. Type: style (systemic duplication with drift risk).
- Location: `lib/hueworks/bridge_onboarding/hue/mdns.ex` vs `lib/hueworks/bridge_onboarding/home_assistant/mdns.ex` — `parse/1`, `ptr_instances/1`, `find_record/3`, `txt_properties/1`, `address_for_target/2`, `format_ip/1`, `same_domain?/2`, `normalize_domain/1`, `instance_name/1` are copied with only the service constant and device construction differing.
- Problem: the pre-release plan calls for a third discovery (`_mqtt._tcp` for Z2M assistance); a third copy locks in drift. This is exactly the "systemic duplication" class the previous audit ranked medium once it hits three copies.
- Decision: extract `Hueworks.BridgeOnboarding.Mdns` with `discover(service, build_device_fun)` (or `instances/2` returning `%{instance, srv, txt, host, port}` maps) and keep per-integration modules as thin adapters. Do this before the MQTT discovery work starts, not after.
- Guardrail: existing `parse/1` unit tests move to the shared module; adapters keep one construction test each.
- Effort: M.

### BO-5: Connection failures still speak developer vocabulary in the setup UI

- Severity: low-medium. Type: UX (violates "Raw `inspect/1` output must not be the primary user-facing vocabulary", `pre-release_refinement.md` State Coverage Matrix).
- Location: `ConnectionTest.Hue` / `.HomeAssistant` (`"... test failed: #{status} #{body}"` — can dump a full HTML error page into the flash; `inspect(reason)` for transport errors), `ConnectionTest.Caseta` (`inspect(reason)`), `BridgeLive` `{:test_bridge, ...} {:exit, reason}` ("Connection test crashed: #{inspect(reason)}"), `BridgeSetupLive` `apply_materialization` error path (`message = inspect(reason)` as both assign and flash).
- Problem: `:nxdomain`, `:econnrefused`, `:timeout`, 401 vs 404, and materialization rollback tuples are the *common* first-run failures — precisely the moments the refinement doc says must identify what failed and the next safe action.
- Decision: add one small shared translator (e.g. `Hueworks.ConnectionTest.Message.humanize/2`) mapping the common transport reasons and HTTP statuses per bridge type to plain language ("HueWorks could not reach <host>…", "The token was rejected…"); truncate any echoed response body to one line; keep `inspect` only as a suffix detail. For `apply_materialization`, translate the known rollback tuples (`:duplicate_classification_changed`, `:stale_resolution`, `:invalid_duplicate` already have messages in `BridgeReimportLive` — reuse that mapping) and fall back to a generic "Import could not be applied" + detail.
- Guardrail: unit tests on the translator; one bridge_live test asserting a refused connection produces the friendly string.
- Effort: M.

## Parked For Chunk 8 (gap analysis, not regressions)

- mDNS `host` falls back to the `.local` target name when no A record is in the response; `.local` names generally don't resolve inside the primary Docker topology. Already an explicit open blocker ("Discovery In Production Topology") — verify during the rehearsal rather than restructure now.
- No `_mqtt._tcp` discovery / guided Z2M assistance and no guided Caseta pairing yet — both are documented Remaining Release Blockers, not regressions in this range.

## Explicitly Fine / Leave-Alone

- **Async discipline in `BridgeLive`**: every network operation (discover ×2, pair, test) runs via `start_async` with per-request `System.unique_integer` staleness guards on both `{:ok, _}` and `{:exit, _}` arms, and `update_bridge` resets test state on any field change so a stale "Test passed" can't authorize saving different credentials. This resolves the WB-1 (sync-network-in-LiveView) class for this surface; the request-id pattern matches the prior audit's reference implementation.
- **Test-before-proceed enforcement** (`proceed_bridge` refuses unless `test_status == :ok`) and **RuntimeIO gating** of connection tests in isolated-verification mode: both correct and honest.
- **Hue pairing flow** (`Pairing.pair/3`): register → validate-with-new-key → identity verify against the discovered bridgeid, with distinct copy for the link-button state (type 101), sanitized/truncated bridge-supplied descriptions, and no partial bridge rows (insert happens only after validation). Meets "validation before persistence" cleanly.
- **Caseta and Z2M connection-test upgrades**: Caseta now performs a real LEAP `/device` read through the shared `CasetaLeap` module instead of a bare TLS handshake; Z2M validates actual retained `devices`/`groups` payloads through the `Z2MConfig`/snapshot vocabulary and reports counts. Both reuse the exact modules the previous audit designated as the canonical vocabulary — this is the desired pattern, and the stronger tests make "test passed" honest.
- **`Device.normalize/merge`** (id-or-host identity, source provenance, mDNS-first merge order) and **`safe_discover`** isolating discovery crashes: sound.
- **New `Bridges` helpers** (`any_bridges?`, `ha_import_order_risk`, `import_summary`): read-only projections; `ha_import_order_risk` is the mechanism behind the "reverse-order risk visible before import" release criterion. Dual-key `fetch_map` is correct import-plane convention (blobs round-trip JSON). The deletion machinery in the same file predates this range.
- **IPv4-only address resolution** in mDNS parsing: acceptable for the trusted-LAN scope; revisit only if a real IPv6-only household shows up.
