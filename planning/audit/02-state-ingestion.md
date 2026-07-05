# Audit Chunk 2: State Ingestion

Scope: `lib/hueworks/subscription/**` (parsers, mappers, readiness, the misfiled Z2M connection) and `lib/hueworks_app/subscription/**` (per-bridge connection processes, `GenericEventStream`).
Status: complete (all 12 files read).

Overall assessment: the supervision design is good — `GenericEventStream` monitors each per-bridge connection, restarts with delay, and defers startup until the bridges table exists, so individual stream crashes are self-healing. The Hue path is the reference implementation: deferred connect, staleness-triggered index refresh, and careful desired-state-aware group fan-out. The problems are that the other three streams each lack a different subset of those virtues, and that this chunk re-duplicates code chunk 1 already flagged (Z2M topology/index loading, group-state derivation, Caseta LEAP plumbing).

Read chunk 1 first: SI findings below extend CP-5 (GroupState duplication), CP-9 (Z2M config duplication), CP-8 (Caseta LEAP), and CP-12 (file-location convention).

---

### SI-1: HA group fan-out overwrites member-light state without the guards the Hue path has
- Severity: high
- Type: bug-risk
- Where: [lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex:107-117](../../lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex) vs the guarded Hue equivalent [lib/hueworks/subscription/hue_event_stream/mapper.ex:115-169](../../lib/hueworks/subscription/hue_event_stream/mapper.ex)
- What: when an HA group entity changes, the handler writes the group's parsed state verbatim onto every member light (`State.put(:light, light_id, state_update)`). The Hue mapper does the same fan-out but through `member_attrs_from_group/2`, which consults `DesiredState` and current physical state so a member with sticky manual-off or explicit desired-off doesn't get flipped to observed-on by a group report. HA has none of that: a group `on` report marks manually-off members as physically on, which can then suppress planner actions ("physical already matches") or corrupt group projections. This is the "HA group fan-out edge case" already listed in `hueworks_todo.md` and the `TODO` at connection.ex:111 — confirmed real, now with a concrete mechanism.
- Why: "Member lights are the source of truth for observation" and manual-power semantics in planned_architecture.md; observed group state must not silently overwrite per-light truth.
- Decision: extract the Hue mapper's guard logic (`member_attrs_from_group/2`, `explicit_power?/2`, `normalize_power/1`, mapper.ex:153-181) into `Hueworks.Control.GroupState` (it is group→member projection semantics, exactly that module's domain), and make the HA handler use it for fan-out. Then, like Hue, re-derive the group projection from members afterwards (`GroupState.derive_from_light_ids/1`) instead of leaving the bridge-reported group state as final. Keep the fan-out itself — HA template groups don't always emit member `state_changed` events, so member updates from group events are needed.
- Guardrails: `subscription_home_assistant_event_stream_connection_test.exs` already exercises fan-out with two member lights (around line 194) — extend it first with characterization cases: member with desired power `:off`, member physically `:off` with no desired state, member with desired `:on`. Mirror the expectations from `subscription_hue_event_stream_mapper_test.exs`. Do not change Hue behavior; this is a port, not a redesign.
- Effort: M

### SI-2: Z2M subscription handler is a wholesale copy of Bootstrap.Z2M internals
- Severity: high
- Type: refactor
- Where: [lib/hueworks/subscription/z2m_event_stream/connection.ex:237-373](../../lib/hueworks/subscription/z2m_event_stream/connection.ex) vs [lib/hueworks/control/bootstrap/z2m.ex:116-321](../../lib/hueworks/control/bootstrap/z2m.ex)
- What: three near-identical blocks are duplicated between the live Z2M handler and the bootstrap: `load_indexes/1` (same queries, the handler adds one inverted map), `entity_from_topic/2` (identical topic parsing), and `derive_group_state/1` + `maybe_put_group_brightness/kelvin` (the *third* copy of `GroupState` logic — CP-5 found the bootstrap copy). The connection module also repeats the config normalization CP-9 flagged.
- Why: two parsers of the same vocabulary means the boundary module is missing (planned_architecture.md); the copies have already drifted (handler's index has `group_source_ids_by_light_source_id`, bootstrap's doesn't).
- Decision: create `Hueworks.Control.Z2MTopology` owning `load_indexes(bridge_id)` (superset shape, including the inverted map — bootstrap just ignores it) and `entity_from_topic(topic_levels, base_levels)`. Both the handler and `Bootstrap.Z2M` consume it. Replace both private group derivations with `GroupState.derive_from_states/2` (this completes CP-5 — implement them together as one change). Fold the config normalization into CP-9's `Z2MConfig` module.
- Guardrails: `subscription_z2m_event_stream_test.exs`, `subscription_z2m_handler_test.exs`, and `control_bootstrap_z2m_test.exs` must pass unchanged; add topic-parsing edge cases (`bridge` topics, `.../set|get|availability`, nested `a/b/state`) to the shared module's own test if assertions currently live only in one consumer.
- Effort: M

### SI-3: Caseta subscription re-implements the LEAP client and bridge-credential logic
- Severity: medium
- Type: refactor
- Where: [lib/hueworks_app/subscription/caseta_event_stream/connection.ex:187-295](../../lib/hueworks_app/subscription/caseta_event_stream/connection.ex) vs [lib/hueworks/control/caseta_client.ex](../../lib/hueworks/control/caseta_client.ex) and [lib/hueworks/control/caseta_bridge.ex](../../lib/hueworks/control/caseta_bridge.ex)
- What: `read_until_match/3`, `decode_message/1`, the ssl_opts construction, and `invalid_credential?/1` are duplicated from the control-side client/bridge modules, with small drift (control's `read_until_match` checks StatusCode and returns `:ok`/error; the subscription's returns the decoded message).
- Decision: extract `Hueworks.Control.CasetaLeap` owning: `ssl_opts_for(bridge)` (from CasetaBridge, including the verify_none comment from CP-8), `send_request(socket, payload)`, `read_until_match(socket, url, timeout, mode)` where mode `:status` gives the client's semantics and `:message` the subscription's, and `decode_message/1`. `CasetaClient`, `CasetaBridge`, and this connection consume it. Do this together with CP-8's send-result checking.
- Guardrails: `subscription_caseta_event_stream_connection_test.exs` and caseta control/payload tests green. Keep `handle_frame/2` as the public test surface. The `state_put` injection seam at connection.ex:297-300 stays as-is (it's the test seam the suite relies on).
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

### SI-6: Z2M connection file lives on the pure-domain side of the runtime split
- Severity: low
- Type: hygiene
- Where: [lib/hueworks/subscription/z2m_event_stream/connection.ex](../../lib/hueworks/subscription/z2m_event_stream/connection.ex)
- What: every other connection process lives under `lib/hueworks_app/subscription/`; the pure mapper/parser/readiness modules live under `lib/hueworks/subscription/`. The Z2M connection (a Tortoise handler — runtime, stateful) is the one file on the wrong side.
- Decision: move the file to `lib/hueworks_app/subscription/z2m_event_stream/connection.ex` (module name unchanged, zero behavior change). Do it in the same change as CP-12's AGENTS.md convention paragraph. Note: after SI-2 extracts the topology/derivation logic, what remains in this file is purely the connection handler, which is exactly what belongs in `hueworks_app`.
- Effort: S

### SI-7: HA websocket subscription bookkeeping is misleading
- Severity: low
- Type: refactor
- Where: [home_assistant_event_stream/connection.ex:34-36,79-94](../../lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex)
- What: `subscribed` is written and never read; the `state_changed_subscribed`/`call_service_subscribed` flag-chain encodes "subscribe to state_changed, then on its ack subscribe to call_service" in a way that took three reads to verify. Works, but the next event type added here will break it.
- Decision: fold into SI-1/SI-4 work on this file: replace the three booleans with a `pending_subscriptions: ["state_changed", "call_service"]` list — on `auth_ok` and on each success result, pop and subscribe the next; drop `subscribed`.
- Guardrails: existing connection tests assert the subscribe frames; keep frame order identical.
- Effort: S

### SI-8: Accepted-risk TLS shortcuts lack the "do not fix" comments
- Severity: low
- Type: hygiene
- Where: Hue SSE `hackney: [insecure: true]` at [hue_event_stream/connection.ex:56](../../lib/hueworks_app/subscription/hue_event_stream/connection.ex); Caseta `verify: :verify_none` at [caseta_event_stream/connection.ex:278](../../lib/hueworks_app/subscription/caseta_event_stream/connection.ex)
- What: both are correct for LAN bridges with self-signed certs (Hue bridge cert isn't CA-signed; LEAP authenticates via client cert), but nothing says so; a future security pass will "fix" them into broken connections.
- Decision: one-line comment at each site stating the constraint (same as CP-8's guardrail for CasetaBridge — do all three in one change).
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

1. SI-1 (bug-risk with existing test scaffolding; unblocks deleting the hueworks_todo runtime-gap item)
2. SI-2 + CP-5 together (one shared-topology change, three copies collapse)
3. SI-4 (staleness refresh, Caseta + HA)
4. SI-5 + SI-7 (same files as SI-4 — can be one HA pass and one Caseta pass)
5. SI-3 + CP-8 together (Caseta LEAP consolidation)
6. SI-6, SI-8 with CP-12/CP-8 (mechanical)
