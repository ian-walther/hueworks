# Chunk 10 (Phase 2): Caseta Discovery, Location Lookup, Remaining Working-Tree Deltas

Status: complete against the working tree as of this session (uncommitted, in-flight). Scope: `bridge_onboarding/caseta/` + `hueworks_app/bridge_onboarding/caseta*`, `hueworks_app/location/postal_code_lookup.ex` + general-config wiring, HA inventory prefill delta, control light/group retry adoption, setup/config copy deltas, config/test deltas. Note: this is Caseta *discovery* groundwork only — the guided LEAP pairing helper from the blocker spec is not yet present; that blocker remains open.

## Findings

### CL-1: Third mDNS parser copy lands exactly as BO-4 predicted — extract now

- Severity: medium (escalated from BO-4's low). Type: style (systemic duplication, third copy).
- Location: `lib/hueworks_app/bridge_onboarding/caseta/mdns.ex` duplicates the record-walking core (`parse`, `ptr_instances`, `find_record`, `txt_properties`, address resolution, domain normalization) already duplicated between `Hue.Mdns` and `HomeAssistant.Mdns`.
- Problem: BO-4 (chunk 3) called for extraction *before* the third copy; the third copy now exists, and it already drifted (3s query timeout vs 1s, a resolver-injection variant the others lack). A future fix to any parsing edge case now needs three touches.
- Decision: implement BO-4's shared `BridgeOnboarding.Mdns` module now, with the Caseta adapter keeping its service constant, its `resolve/2` hostname path (`lutron-<id>.local`), and its timeout as adapter-level parameters. One extraction serves all three findings; retire BO-4 when done.
- Guardrail: move the shared `parse/1` unit tests to the shared module; one construction test per adapter (all three have committed/working-tree test files already).
- Effort: M.

### CL-2: Needless runtime reflection guarding a function that always exists

- Severity: low. Type: style.
- Location: `Hueworks.BridgeOnboarding.Caseta.discover_devices/2` — `Code.ensure_loaded?(module) and function_exported?(module, :resolve, 1)`.
- Problem: the default module defines `resolve/1`; injected test doubles can too. Runtime reflection here hides a contract that should just be the behaviour's shape, and it will silently skip `resolve` on a typo'd double rather than failing loudly.
- Decision: call `module.resolve(external_id)` directly when an external id is present; let a missing function crash the test that misconfigured it.
- Effort: S.

### CL-3: Postal-code lookup contacts a third-party service without saying so

- Severity: low. Type: privacy/UX.
- Location: `Hueworks.Location.PostalCodeLookup` (`api.zippopotam.us`), invoked from GeneralConfigLive's lookup button.
- Problem: the household's postal code is sent to an external cloud service. It is user-initiated and coordinates-only in response — proportionate — but the UI doesn't disclose the third party, and the compatibility doc's deployment section doesn't mention this single external call-out (the only one besides Hue vendor discovery).
- Decision: one line of helper copy under the lookup control ("Looks up coordinates via zippopotam.us; only the country and postal code are sent.") and a bullet in `docs/compatibility.md`. No code change.
- Effort: S.

### CL-4: Setup copy reintroduces "Rooms" into the HA inventory description

- Severity: low. Type: UX copy.
- Location: working-tree `setup_live.html.heex` — "Read your existing integrations, Floors, Areas, Rooms, and Lights/Groups."
- Problem: Home Assistant has Floors/Areas/Labels — not Rooms. The committed range spent two polish commits scrubbing Room/Area vocabulary confusion; this edit re-blurs it in the highest-visibility onboarding surface. (Same edit also dropped terminal periods on two sentences — style drift within one card.)
- Decision: drop "Rooms" from the list (or, if it meant Hue Rooms visible through HA, say "Hue Rooms" explicitly); restore sentence-final punctuation.
- Effort: S.

## Explicitly Fine / Leave-Alone

- **Caseta targeted resolve** (`lutron-<serial>.local` hostname resolution with strict `^[0-9a-f]{8}$` serial validation, falling back to `_lutron._tcp` browse): good design for "find the bridge HA told us about"; the serial regex matches the inventory extractor's, keeping the prefill hand-off consistent.
- **HA inventory prefill delta**: native-source cards now carry `external_id` (Hue bridgeid from device-registry identifiers, Caseta serial from entry title) and `host` (Z2M broker from title) so "Add <native bridge>" can prefill and pre-verify identity. Read-only projection, defensive parsing via `Normalize.fetch` throughout, tuple-and-list identifier shapes both handled.
- **Control light/group adoption of `HomeAssistantBridge.request/2`**: the 401-retry-once helper now wraps HA control calls; this closes the loop on chunk 9's "no caller reads the permanent token" verification.
- **`PostalCodeLookup` implementation**: strict country/postal validation before any request, URI-encoded path, bounded timeouts, status-classified errors, coordinate range validation, `start_async` + status assign in the LiveView. Mechanically this is the right shape (only the disclosure, CL-3, is missing).
- **Connection-test/`Host.http_url` adoption** and the general-config wiring: consistent with the chunk 9 host rewrite.
- **Setup copy tightening** otherwise (shorter subtitle, honest "may be more tedious" framing for direct setup): improvements; only the CL-4 line regresses.
