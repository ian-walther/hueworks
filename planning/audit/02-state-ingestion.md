# Audit Chunk 2: State Ingestion

Scope: `lib/hueworks/subscription/**` (parsers, mappers, readiness, the misfiled Z2M connection) and `lib/hueworks_app/subscription/**` (per-bridge connection processes, `GenericEventStream`).
Status: audit complete (all 12 files read). Finding IDs are stable; gaps in numbering mean the finding was implemented and removed.

Overall assessment: the supervision design is good — `GenericEventStream` monitors each per-bridge connection, restarts with delay, and defers startup until the bridges table exists, so individual stream crashes are self-healing. The Hue path is the reference implementation: deferred connect, staleness-triggered index refresh, and careful desired-state-aware group fan-out. The remaining findings are the Caseta LEAP consolidation and the Caseta/HA streams lacking the Hue path's refresh and non-blocking-init virtues.

---

### SI-3: Caseta subscription re-implements the LEAP client and bridge-credential logic
- Severity: medium
- Type: refactor
- Where: [lib/hueworks_app/subscription/caseta_event_stream/connection.ex:187-295](../../lib/hueworks_app/subscription/caseta_event_stream/connection.ex) vs [lib/hueworks/control/caseta_client.ex](../../lib/hueworks/control/caseta_client.ex) and [lib/hueworks/control/caseta_bridge.ex](../../lib/hueworks/control/caseta_bridge.ex)
- What: `read_until_match/3`, `decode_message/1`, the ssl_opts construction, and `invalid_credential?/1` are duplicated from the control-side client/bridge modules, with small drift (control's `read_until_match` checks StatusCode and returns `:ok`/error; the subscription's returns the decoded message).
- Decision: extract `Hueworks.Control.CasetaLeap` owning: `ssl_opts_for(bridge)` (from CasetaBridge, keeping the existing verify_none intent comments), `send_request(socket, payload)` (keeping the send/setopts error checking now in CasetaClient), `read_until_match(socket, url, timeout, mode)` where mode `:status` gives the client's semantics and `:message` the subscription's, and `decode_message/1`. `CasetaClient`, `CasetaBridge`, this connection, and `Import.Fetch.Caseta` (see IM-5) consume it. Follow-up opportunity once extracted (perf-triggered only, don't do speculatively): Caseta opens a fresh TLS handshake per command — if Caseta responsiveness ever becomes a product complaint, a persistent LEAP connection process belongs behind this module.
- Guardrails: `subscription_caseta_event_stream_connection_test.exs`, `control_caseta_client_test.exs`, and caseta control/payload tests green. Keep `handle_frame/2` as the public test surface and the `request/4` injection seam. The `state_put` injection seam at connection.ex:297-300 stays as-is (it's the test seam the suite relies on).
- Effort: M

### SI-4: Caseta and HA streams never refresh their entity indexes
- Severity: medium
- Type: bug-risk
- Where: [caseta_event_stream/connection.ex:31-32](../../lib/hueworks_app/subscription/caseta_event_stream/connection.ex) (`load_lights`, `load_pico_button_ids` at init only), [home_assistant_event_stream/connection.ex:27-28](../../lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex) (`load_lights`, `load_groups` at start only)
- What: Hue refreshes its indexes when an unknown entity appears (≤ once per 2s, connection.ex:119-142); Z2M does the same (`maybe_refresh_and_retry`). Caseta and HA load once at connection start, so lights imported/enabled/relinked after startup are invisible to those streams until the process happens to restart. Worse for Caseta: pico button subscriptions are LEAP `SubscribeRequest`s sent once at init, so a newly enabled pico gets no events at all.
- Why: physical state silently going stale for new entities breaks "observed physical state" as a usable comparison plane, and the failure is invisible.
- Decision: add the same unknown-entity-triggered refresh (rate-limited to 2s like Hue/Z2M) to both: Caseta on unknown zone_id in `handle_zone_status`, HA on unknown entity_id in `handle_event`. For Caseta pico subscriptions: on refresh, diff `load_pico_button_ids` against the subscribed set and send `SubscribeRequest` for new button ids (LEAP allows subscribing mid-connection — it's the same call made at init). If an unknown *button* event arrives, treat it as the refresh trigger.
- Guardrails: extend both connection test suites: event for an unknown entity → index refreshed → immediately-following event applies. Rate-limit must be tested (two unknown events within 2s → one reload).
- Effort: M

### SI-5: Caseta and HA connections do blocking network I/O during process init
- Severity: medium
- Type: refactor
- Where: [caseta_event_stream/connection.ex:23-48](../../lib/hueworks_app/subscription/caseta_event_stream/connection.ex) (SSL connect + up-to-5s initial zone read inside `init/1`), [home_assistant_event_stream/connection.ex:19-44](../../lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex) (`WebSockex.start_link` performs the WS handshake synchronously, plus DB loads in `start_link`)
- What: `GenericEventStream.init` starts all connections synchronously during application boot; an unreachable Caseta bridge stalls startup ~5s (per bridge), and every retry cycle re-blocks the manager for the same window inside `handle_info`. Hue avoids this (`send(self(), :connect)` from init).
- Decision: adopt the Hue pattern. Caseta: `init` stores the bridge and returns `{:ok, state, {:continue, :connect}}`; connect/initial-read/subscribe move to `handle_continue`; on failure `{:stop, reason}` there (monitor + delayed restart in GenericEventStream already handles it). HA: pass `async: true` to `WebSockex.start_link` and move `load_lights/load_groups` into the process (`handle_connect` or init callback) so `start_link` returns immediately.
- Guardrails: verify GenericEventStream's `{:error, reason}` branch still gets exercised for the missing-token/missing-credentials preflight cases (keep those checks in `start_link` so they fail fast without a process); connection test suites green.
- Effort: M

### SI-7: HA websocket subscription bookkeeping is misleading
- Severity: low
- Type: refactor
- Where: [home_assistant_event_stream/connection.ex:34-36,79-94](../../lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex)
- What: `subscribed` is written and never read; the `state_changed_subscribed`/`call_service_subscribed` flag-chain encodes "subscribe to state_changed, then on its ack subscribe to call_service" in a way that took three reads to verify. Works, but the next event type added here will break it.
- Decision: fold into SI-4 work on this file: replace the three booleans with a `pending_subscriptions: ["state_changed", "call_service"]` list — on `auth_ok` and on each success result, pop and subscribe the next; drop `subscribed`.
- Guardrails: existing connection tests assert the subscribe frames; keep frame order identical.
- Effort: S

---

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- Coverage here is genuinely good: every stream has a connection-level suite, and Hue additionally has parser and mapper suites. Explicitly leave the parser suite alone.
- Gap: no test covers the SI-4 staleness scenarios (entity added after connection start) for any stream — add for Caseta/HA when implementing, and consider one for Hue's existing `maybe_refresh_indexes` while in there (it's load-bearing and only indirectly tested).
- Gap: `GenericEventStream` restart-on-DOWN and readiness-retry behavior has no direct test; it's the self-healing backbone for all four streams. One small test with a crashing fake connection module would cover it.

## Parked (noted early, belongs to later chunks)

- Chunk 3: `ExternalScenes.activate_home_assistant_scenes/2` is invoked from the HA `call_service` handler — verify external scene activation enters through normal scene-apply paths (it appears to; confirm in scenes chunk).
- Chunk 5: Pico button-press handling (`Picos.handle_button_press/2`) is called synchronously from the Caseta socket loop — if a press triggers slow scene application, the socket stops reading frames meanwhile. Assess in the Picos chunk whether that work should be cast off the connection process.
- Chunk 7: `Readiness.bridges_table_ready?/0` exists to tolerate boot-before-migration ordering; revisit whether release-time migrations make it dead in practice (keep for dev `ecto.reset` workflows unless proven otherwise).

## Suggested Implementation Order (for cheap-model sessions)

1. SI-4 (staleness refresh, Caseta + HA)
2. SI-5 + SI-7 (same files as SI-4 — can be one HA pass and one Caseta pass)
3. SI-3 (Caseta LEAP consolidation; picks up IM-5's import-fetch migration)
