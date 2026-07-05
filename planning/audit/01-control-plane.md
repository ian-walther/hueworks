# Audit Chunk 1: Control Plane

Scope: `lib/hueworks/control/**`, `lib/hueworks_app/control/**`, `lib/hueworks_app/cache*`, `lib/hueworks/active_scenes.ex`, plus `lib/hueworks/application.ex` supervision wiring.
Status: complete (all files in scope read).

Overall assessment: the pipeline mandated by `planned_architecture.md` (intent → DesiredState → planner → executor → dispatch) is genuinely present and mostly respected. The planner/executor split is clean, tracing is consistent, and device quirks live in payload/Kelvin modules as intended. The main problems are (a) duplicated state-semantics code that refactoring.md already suspected, (b) a mixed atom/string-key tolerance that has metastasized through the whole plane, (c) a meaningful amount of dead API surface kept alive only by tests, and (d) one real behavioral bug-risk in manual-control enqueueing.

---

### CP-1: One enqueue default lets manual control cancel unrelated queued work
- Severity: high
- Type: bug-risk
- Where: [lib/hueworks/lights/manual_control.ex:22](../../lib/hueworks/lights/manual_control.ex), [lib/hueworks/control/apply.ex:79](../../lib/hueworks/control/apply.ex), [lib/hueworks_app/control/executor.ex:150-175](../../lib/hueworks_app/control/executor.ex)
- What: `Executor.enqueue` mode `:replace` (the default in `Apply.plan_and_enqueue`) replaces the **entire queue for a bridge**, not just the affected targets. `Lights.ManualControl` calls `ControlApply.commit_and_enqueue(txn, room_id)` with no `enqueue_mode`, so a single manual light adjustment discards every queued action on that bridge — including in-flight scene application or convergence retries for *other rooms* on the same bridge. Scene apply already uses the safer modes (`:append` at scenes/apply.ex:26, `:replace_targets` at scenes/apply.ex:98).
- Why: Executor owns dispatch/convergence; upstream intent in one room must not silently cancel dispatch for another room ("Cross-bridge timing and no-popcorning behavior belongs here"). This is exactly the class of mixed-bridge reliability bug the architecture doc says to trace first.
- Decision: change `Lights.ManualControl` to pass `enqueue_mode: :replace_targets`. Then audit remaining `:replace` uses: make `:replace_targets` the default in `Apply.plan_and_enqueue` and reserve bare `:replace` for callers that explicitly want to wipe a bridge queue (none identified; if none remain after the change, delete the `:replace` branch in `enqueue_actions` — the catch-all `_` clause at executor.ex:154).
- Guardrails: per AGENTS.md, write the failing test first: enqueue actions for room A lights on bridge X, then commit a manual-control change for room B on bridge X, and assert room A's actions are still queued (`Executor.stats`). Keep `:append` semantics untouched (circadian reapply relies on it).
- Effort: S

### CP-2: State-map color/temperature harmonization duplicated across both state planes
- Severity: high
- Type: refactor
- Where: [lib/hueworks_app/control/desired_state.ex:141-209](../../lib/hueworks_app/control/desired_state.ex), [lib/hueworks_app/control/state.ex:197-241](../../lib/hueworks_app/control/state.ex), overlapping [lib/hueworks/control/light_state_semantics.ex:177-197](../../lib/hueworks/control/light_state_semantics.ex)
- What: `harmonize_color_and_temperature/2`, `drop_kelvin/1`, `drop_xy/1`, `incoming_has_xy?/1`, `incoming_has_kelvin?/1` are copied verbatim between `DesiredState` and `State` (physical). `LightStateSemantics` already exports its own `drop_kelvin`/`drop_xy`. `DesiredState` additionally owns `drop_light_levels` (power-off clears levels). The HA export command path keeps a third variant for optimistic state (`Hueworks.HomeAssistant.Export.Commands.optimistic_light_state` — see chunk 5). This is refactoring.md item 2 ("Centralize State-Map Normalization"), confirmed and absorbed here.
- Why: "one lower-level state semantics helper owns color/temperature harmonization" (refactoring.md); duplicate copies have already drifted (only DesiredState drops levels on power-off).
- Decision: move the write-side merge semantics into `Hueworks.Control.LightStateSemantics`: add `merge_state(current, incoming)` that (1) harmonizes xy-vs-kelvin based on incoming keys, (2) merges, and a separate `normalize_power_off(state)` that drops brightness/kelvin/temperature/x/y when power is off. `DesiredState.normalize_desired` = `merge_state` + `normalize_power_off`; `State.merge_and_store` = `merge_state` only (physical state intentionally keeps last-known levels when off — preserve that asymmetry, do not "fix" it). Delete the private copies in both GenServers. Chunk 5 will point HA optimistic state at the same helper.
- Guardrails: preserve current atom+string dual-key behavior for now (CP-3 removes it later, separately). Characterization tests: existing `control_state_test.exs`, `control_desired_state_test.exs` must pass unchanged; add cases asserting physical-state off-merge keeps levels and desired-state off-merge drops them.
- Effort: M

### CP-3: Mixed atom/string key tolerance has spread through the entire control plane
- Severity: high
- Type: refactor
- Where: everywhere below the boundary — dual lookups `Map.get(m, :k) || Map.get(m, "k")` and dual clauses in [desired_state.ex:144-209](../../lib/hueworks_app/control/desired_state.ex), [state.ex:197-241](../../lib/hueworks_app/control/state.ex), [planner.ex:34-37,51-65,320-325](../../lib/hueworks/control/planner.ex) (`{:light, id}` and `{"light", id}` diff keys), [planner/context.ex:49-53](../../lib/hueworks/control/planner/context.ex), [executor/commands.ex](../../lib/hueworks_app/control/executor/commands.ex), all four payload modules (`value_or_nil` ×3 + `power` dual reads), [apply.ex:184-186](../../lib/hueworks/control/apply.ex) (`map_value`), [group_state.ex:85-89](../../lib/hueworks/control/group_state.ex), and the alias tables in [light_state_semantics.ex:66-78](../../lib/hueworks/control/light_state_semantics.ex).
- What: internal desired/physical state maps and diff keys tolerate both key shapes at every layer, so every consumer re-implements boundary normalization.
- Why: direct violation of "Normalize At Boundaries — do not spread mixed atom/string key handling through downstream domain code."
- Decision: make atom-keyed state maps with `{:light | :group, integer_id}` diff keys the **internal invariant** of the control plane, enforced at the two write funnels: `DesiredState.apply/put` and `State.put/ensure` normalize incoming maps (string keys → known atoms via the existing `LightStateSemantics.key_aliases` vocabulary, `temperature` → `kelvin`, string power → atom). Implement as `LightStateSemantics.normalize_keys/1` used inside CP-2's `merge_state`. Then, in a follow-up pass per module, delete downstream dual-key handling: planner string-tuple clauses, `value_or_nil` key lists collapse to single atoms, `Commands`/`Transition`/`GroupState` dual reads, `Apply.map_value` (trace maps: pick atom keys, fix callers). StateParser keeps accepting loose external payloads — it already emits atom keys; that is the correct boundary.
- Guardrails: sequence AFTER CP-2 lands (normalization goes into the shared helper, not into two GenServers separately). Do one downstream module per commit with the full suite green. Where a test feeds string-keyed state directly into a downstream module (bypassing the funnel), relocate the assertion to the funnel per the Testing Rule in refactoring.md rather than preserving the internal tolerance.
- Effort: L (mechanical but wide)

### CP-4: Dead control API surface kept alive by tests or nothing at all
- Severity: medium
- Type: refactor
- Where and what (each verified to have zero production callers via grep):
  - `State.suppress_scene_clear_for_refresh/0` and `clear_scene_clear_suppression/0` — literal no-ops, [state.ex:63-67](../../lib/hueworks_app/control/state.ex).
  - `State.put/4`'s `caller` and `opts` are received and discarded (`_ = caller; _ = opts`, [state.ex:89-96](../../lib/hueworks_app/control/state.ex)); call sites pass `source: :bootstrap` etc. believing it matters.
  - `Executor.commands_for_action/1` wrapper ([executor.ex:47-51](../../lib/hueworks_app/control/executor.ex)) and the whole `Executor.Commands` module — dispatch uses `set_state` payload builders instead; only `control_executor_test.exs` calls it.
  - `Planner.plan_direct/2` ([planner.ex:27-70](../../lib/hueworks/control/planner.ex)) — only its own test calls it; it also does Repo queries inside the planner, against the "pure planner inputs" rule.
  - `Control.Light` and `Control.Group` convenience actions `on/off/set_brightness/set_color_temp/set_color` ([light.ex:19-33](../../lib/hueworks/control/light.ex), [group.ex:17-31](../../lib/hueworks/control/group.ex)) — only `set_state` is dispatched (by the executor). The corresponding payload-module clauses (`:on`, `:off`, `{:brightness, _}`, `{:color_temp, _}`, `{:color, _}`) become dead with them.
- Why: dead entry points below the desired-state boundary invite future code to dispatch hardware actions directly, the exact bypass planned_architecture.md forbids; the no-op suppress functions imply behavior that does not exist.
- Decision: delete all of the above. `State.put` becomes `put(type, id, attrs)` (drop caller/opts; update bootstrap/subscription call sites to stop passing `source:`). Delete `Executor.Commands`, its wrapper, and its tests. Delete `plan_direct` and its test. Prune Light/Group to `set_state/3`; delete the now-unreachable payload clauses and their direct tests, keeping every `{:set_state, ...}` payload test. If any deleted payload clause encodes device knowledge not covered by `set_state` tests (e.g. Hue hue/sat encoding), port that assertion into a `set_state` test first.
- Guardrails: full suite green after each deletion; do not delete `Executor.tick/stats` (used by tests as the sanctioned sync mechanism and by hardware_smoke).
- Effort: M (many small deletions)

### CP-5: Bootstrap.Z2M reimplements group-state derivation that GroupState already owns
- Severity: medium
- Type: refactor
- Where: [lib/hueworks/control/bootstrap/z2m.ex:254-321](../../lib/hueworks/control/bootstrap/z2m.ex) vs [lib/hueworks/control/group_state.ex](../../lib/hueworks/control/group_state.ex)
- What: `derive_group_state/1` + `maybe_put_group_brightness/kelvin` in the bootstrap duplicate `GroupState.derive_from_states/2` minus the xy handling and minus the `"ON"`/`false` power normalization.
- Why: groups are projections from member lights; there must be one projection function ("Do not let group records become a second independent light-state model").
- Decision: replace the bootstrap's private derivation with `GroupState.derive_from_states(states, length(lights))`. The deltas (xy averaging gained, `"ON"`/`false` power accepted) are strict improvements in observation parsing; accept them.
- Guardrails: add a characterization test for bootstrap group derivation (mixed on/off members, kelvin spread > 50) before the swap if none exists in `control_bootstrap_z2m_test.exs`.
- Effort: S

### CP-6: HueBridge resolves credentials by metadata["bridge_host"] instead of bridge_id
- Severity: medium
- Type: bug-risk
- Where: [lib/hueworks/control/hue_bridge.ex:26-30](../../lib/hueworks/control/hue_bridge.ex)
- What: every other bridge module (`CasetaBridge`, `HomeAssistantBridge`, `Z2MBridge`) resolves connection info from `entity.bridge_id`; Hue alone reads `metadata["bridge_host"]` (string key only) and then looks the bridge up by host. A Hue light whose metadata lacks `bridge_host`, or a bridge whose IP changed since import, fails control with `:missing_bridge_host`/`:bridge_not_found` even though `bridge_id` is right there and current.
- Why: identity should come from the canonical row, not a cached import-time fact; also violates normalize-at-boundaries (string-key metadata read in control code).
- Decision: rewrite `credentials_for/1` to match the others: look up `Repo.get(Bridge, entity.bridge_id)`, return `{:ok, bridge.host, api_key}`, cache under `{:hue, bridge_id}`. Delete `bridge_host/1`.
- Guardrails: confirm `Bootstrap.Hue` and the Hue event stream don't depend on the metadata host path (they load bridges directly — verified). Add a regression test: hue light with no `bridge_host` metadata but valid `bridge_id` dispatches successfully.
- Effort: S

### CP-7: Payload modules quadruplicate desired-value extraction helpers
- Severity: medium
- Type: refactor
- Where: `value_or_nil/2` + `normalized_xy/1` copied in [hue_payload.ex:95-110](../../lib/hueworks/control/hue_payload.ex), [home_assistant_payload.ex:102-117](../../lib/hueworks/control/home_assistant_payload.ex), [z2m_payload.ex:98-113](../../lib/hueworks/control/z2m_payload.ex); `value_or_nil` again in [executor/commands.ex:40-48](../../lib/hueworks_app/control/executor/commands.ex) (dies with CP-4).
- What: four hand-rolled copies of "first present key wins" plus three copies of xy rounding, while `LightStateSemantics` already exposes `value_or_alias/2`, `x_value/1`, `y_value/1`, `kelvin_value/1`.
- Why: refactoring.md item 2's vocabulary rule: multiple modules parsing the same key vocabulary means the boundary module is missing.
- Decision: add `LightStateSemantics.brightness_value/1` and `power_value/1` (normalizing to `:on`/`:off`/nil) alongside the existing accessors; payload modules consume `power_value/brightness_value/kelvin_value/x_value/y_value` and delete their private helpers. Note `x_value/y_value` clamp+round to 4 places — that matches the payloads' `Float.round(4)`; keep the clamp.
- Guardrails: existing `control_*_payload_test.exs` suites must pass unchanged; they are good characterization coverage. Largely superseded if CP-3 fully lands, but safe to do first — it shrinks CP-3's surface.
- Effort: S

### CP-8: CasetaClient ignores ssl send/setopts results
- Severity: low
- Type: bug-risk
- Where: [lib/hueworks/control/caseta_client.ex:10-12](../../lib/hueworks/control/caseta_client.ex)
- What: `:ssl.setopts/2` and `:ssl.send/2` return values are discarded; a send failure surfaces only as a 5-second `{:error, :timeout}` from the read loop, which delays the executor's retry/backoff by the full timeout and mislabels the error.
- Decision: pattern-match both calls in the `with`; return `{:error, {:ssl_send, reason}}` on failure. Separately note (no action now): a fresh TLS handshake per command is a latency tax on every Caseta action — if Caseta responsiveness becomes a product complaint, a persistent LEAP connection process belongs in the executor/bridge layer; park in `planning/transition-smoothness.md` territory rather than fixing speculatively.
- Guardrails: `verify: :verify_none` in CasetaBridge is acceptable for LEAP (bridge authenticates the client cert; server cert is self-signed) — leave it, but add a one-line comment stating that constraint so it isn't "fixed" into breakage.
- Effort: S

### CP-9: Z2M connection-config normalization duplicated three ways
- Severity: low
- Type: refactor
- Where: [z2m_bridge.ex:25-67](../../lib/hueworks/control/z2m_bridge.ex), [bootstrap/z2m.ex:323-366](../../lib/hueworks/control/bootstrap/z2m.ex), [z2m_client.ex:69-80](../../lib/hueworks/control/z2m_client.ex)
- What: `normalize_port/base_topic/optional` and `maybe_put_auth/maybe_put_password` are duplicated between the bridge module and the bootstrap; the auth helpers a third time in the client.
- Decision: extract `Hueworks.Control.Z2MConfig` owning `for_bridge(%Bridge{}) :: config_map` and `tortoise_auth_opts(config)`; bridge, bootstrap, and client consume it. Keep the per-caller Tortoise module indirection (test seams) where it is.
- Guardrails: existing z2m control/bootstrap tests green.
- Effort: S

### CP-10: CasetaBridge skips the credentials cache the other bridges use
- Severity: low
- Type: refactor
- Where: [lib/hueworks/control/caseta_bridge.ex:7-31](../../lib/hueworks/control/caseta_bridge.ex)
- What: Hue/HA/Z2M wrap credential loading in `Cache.get_or_load(:bridge_credentials, ...)` with a 10s TTL; Caseta hits the Repo on every dispatch.
- Decision: wrap `load` in the same cache pattern, key `{:caseta, bridge_id}`, same TTL config key.
- Effort: S

### CP-11: DesiredState.commit is a read-modify-write loop of GenServer calls
- Severity: low
- Type: refactor (accepted risk — document, don't fix yet)
- Where: [lib/hueworks_app/control/desired_state.ex:83-127](../../lib/hueworks_app/control/desired_state.ex)
- What: `commit/1` iterates entities doing one `GenServer.call` per entity, computing diffs outside the server; concurrent transactions can interleave per-entity. Similarly, `Executor.dispatch_action` does a `Repo.get` per action ([executor.ex:344,356](../../lib/hueworks_app/control/executor.ex)).
- Why noted: at single-home scale neither is a real problem, and last-writer-wins per entity matches the product's manual-vs-scene semantics today. Recording so a future contributor doesn't discover it mid-incident.
- Decision: no change now. If a real interleaving bug is ever traced here, move commit into a single `handle_call` that applies the whole transaction atomically — do not add locks upstream.
- Effort: — 

### CP-12: File location vs module namespace split is undocumented
- Severity: low
- Type: doc-drift
- Where: `lib/hueworks_app/control/*` defines `Hueworks.Control.State/DesiredState/Executor/CircadianPoller` while `lib/hueworks/control/*` defines the pure modules; only `HueworksApp.Cache` actually uses the `HueworksApp` namespace.
- What: the physical split (stateful runtime processes in `lib/hueworks_app`, pure domain in `lib/hueworks`) looks intentional and useful, but nothing states it, and the namespace only half-follows it — a future agent will "helpfully" collapse or misfile modules.
- Decision: document the convention in AGENTS.md (one paragraph: "`lib/hueworks_app` holds supervised runtime processes; `lib/hueworks` holds pure domain logic; module namespaces stay `Hueworks.*` except infra like `HueworksApp.Cache`"). Do not mass-rename modules or move files.
- Effort: S

---

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- The control plane is well covered overall: state, desired state, planner, apply, payloads, bootstraps, convergence all have focused suites. Explicitly leave alone.
- Missing: the CP-1 cross-bridge queue-replacement scenario (no test exercises two rooms' actions on one bridge queue).
- Missing: `Executor` retry/backoff timing behavior (`requeue_action`, `not_before` gating) has no direct test — worth one before anyone touches executor internals.
- `control_executor_test.exs` mostly tests the dead `commands_for_action` (see CP-4) — its value disappears with the deletion; replace with the retry/backoff test above so the file keeps earning its name.

## Parked (noted early, belongs to later chunks)

- Chunk 2: `Subscription.HueEventStream.Mapper` derives group state via `GroupState` (good) — verify HA/Z2M streams do the same rather than trusting bridge-reported group state.
- Chunk 3: `Scenes.Apply` uses `:append` for reapply and `:replace_targets` for activation — verify those choices against CP-1's new default.
- Chunk 3: `ActiveScenes.set_active/clear_for_room` call `HomeAssistantExport.refresh_room_select` inline — domain module reaching into an integration; assess direction (PubSub event the export layer subscribes to would match the architecture better).
- Chunk 5: point `HomeAssistant.Export.Commands` optimistic state at the CP-2 shared merge helper.
- Chunk 5: `Bootstrap.HomeAssistant.run` assumes a single HA bridge (`Repo.one`) while the rest of the app supports N bridges per type.

## Suggested Implementation Order (for cheap-model sessions)

1. CP-1 (bug-risk, small, test-first)
2. CP-6 (bug-risk, small)
3. CP-2 (unlocks CP-3; medium)
4. CP-4 + CP-7 (deletions/extractions, shrink CP-3's surface)
5. CP-5, CP-8, CP-9, CP-10, CP-12 (independent smalls, any order)
6. CP-3 last (wide, mechanical, one module per commit)
