# Claude Architecture Audit — Outstanding Items

## Purpose
Independent code-level audit of the HueWorks codebase, focused on concrete patterns, duplication, error handling, naming, and structural issues — complementary to the architectural direction in `refactoring.md`. Items addressed by subsequent refactoring passes have been removed; what remains is only what still needs attention.

Last revised 2026-04-16 after a large struct/schema-direction refactoring pass.

---

## Priority Next Steps

1. **Normalize keys at the `state_parser.ex` boundary** (1a + 13b) — the single highest-leverage remaining issue. Make `state_parser.ex` return atom-keyed maps (or a struct) so the dual-key problem doesn't propagate into ETS. The `DesiredAttrs` struct in `scenes/intent.ex` is a good model.
2. **Generate trace IDs by default in `apply_scene`** (14d) — activates the already-built trace infrastructure with zero new plumbing.
3. **Break the Rooms → HomeAssistantExport coupling** (6a) — the cycle moved from `scenes.ex` to `rooms.ex` but still exists. PubSub-based eventing is the right decoupling.
4. **Add `@spec` coverage to the critical 5 control modules** (13a) — `state.ex`, `desired_state.ex`, `light_state_semantics.ex`, `state_parser.ex`, `scenes.ex`. Dialyxir is already present, so specs will be verified immediately.
5. **Fix the N+1 in `picos/targets.ex`** (8b) — isolated performance win.
6. **Log bare rescue stack traces** (2a) — small change, meaningful debuggability improvement.
7. **Parameterize `materialize.ex` upserts** (1g) — ~44 lines eliminated, mechanical.

---

## 1. Systemic Duplication Patterns

### 1a. String/Atom Dual-Key Handling (highest-leverage remaining)

Data from MQTT and external sources arrives with string keys; the domain model uses atoms. The conversion is still handled ad-hoc in 6+ places:

- `scenes/intent.ex:116-117`: `Map.get(component, :light_defaults) || Map.get(component, "light_defaults")`; `light_default_lookup/2:214-219` uses `cond` with `Map.has_key?` for both forms
- `home_assistant/export/commands.ex:99-127`: `drop_kelvin/1`, `drop_xy/1` delete both atom/string variants; `incoming_has_xy?/1` and `incoming_has_kelvin?/1` check both
- `control/light_state_semantics.ex:66-78`: `key_aliases/1` returns lists like `[:kelvin, "kelvin", :temperature, "temperature"]`
- `control/state_parser.ex:13,18`: inline `state["attributes"] || state[:attributes]`, `attrs["brightness"] || attrs[:brightness]`
- `hueworks_app/control/executor/commands.ex:10`, `desired_state.ex:144`, `planner.ex:321`, `apply.ex:177`, `home_assistant_payload.ex:17`, `z2m_payload.ex:15`, `hue_payload.ex:13`: all repeat `Map.get(desired, :power) || Map.get(desired, "power")`

**Recommendation:** Extract a shared `KeyNormalize` utility with `get_any(map, atom_key)` and `delete_any(map, keys)` / `has_any?(map, keys)`. Better: normalize at `state_parser.ex` so atom-keyed maps (or a struct) enter the ETS layer — this eliminates the problem at the root rather than papering over it.

### 1d. Fetch Module Duplication (partial)

`invalid_credential?/1` has been consolidated into `import/fetch/common.ex:26-28`. Remaining: `fetch/0` and `fetch_for_bridge/1` in each of `hue.ex`, `home_assistant.ex`, `caseta.ex`, `z2m.ex` are still 80-90% structurally identical — they differ only in the bridge type filter and credential extraction.

**Recommendation:** Extract shared `fetch_all(type, &fetch_fn/1)` and `fetch_one(bridge, &fetch_fn/1)` wrappers into `common.ex`.

### 1f. Blank Component Definition (2 files)

`@blank_component` is still defined identically in `scene_editor_live.ex` and `scene_builder_component/state.ex`.

**Recommendation:** Define once in a shared location (e.g., `Scenes.Builder` or `Scenes.Components`).

### 1g. Materialize upsert Duplication

`upsert_lights/4` (lines 92-135) and `upsert_groups/4` (lines 137-180) in `materialize.ex` are 44-line near-duplicates — same `attrs` map, same `Repo.get_by` + insert/update logic, differing only in schema and metadata helper calls.

**Recommendation:** Extract parameterized `upsert_entities/5`.

---

## 2. Error Handling Issues

### 2a. Bare Rescue Blocks

- `import/pipeline.ex:35-43`: `rescue error -> {:error, Exception.message(error)}` — swallows stack trace, loses exception type
- `hueworks_app/subscription/readiness.ex:17`: `rescue _error -> false` — silently converts any exception to false, making it impossible to distinguish "table not ready" from "database connection error"

**Recommendation:** Use `Logger.error` with `Exception.format(:error, error, __STACKTRACE__)` in rescue blocks. Return structured error tuples.

### 2b. Silent Error Swallowing

- `import/fetch/home_assistant.ex` lines 153, 160, 175, 190, 199, 275: all registry fetches silently return empty lists on error (`_ -> []`)
- `scenes/intent.ex` `Circadian.calculate/3` catch (~line 78): catches errors, logs warning, returns empty map — callers can't distinguish "circadian disabled" from "calculation failed"

**Recommendation:** Errors at system boundaries should be logged with context; errors in internal calls should be propagated as tuples.

### 2c. Inconsistent Error Return Styles

- `import/fetch/hue.ex:56-72` still returns `%{error: "..."}` maps (lines 63, 67, 70) instead of `{:error, reason}` tuples
- `import/fetch/caseta.ex:132` returns `%{error: inspect(reason), responses: acc}`
- `materialize.ex` `infer_group_rooms/1` performs DB updates as side effect with no return value

**Recommendation:** Standardize on `{:ok, result} | {:error, reason}` throughout.

---

## 3. Complexity Hotspots

### 3b. LightStateEditorLive (441 lines, down from 810 → 621)

Continued improvement, but chart calculation functions are still tightly coupled to the LiveView, and `@chart_width 640`, `@chart_height 188`, `@chart_padding` are magic numbers for chart rendering.

**Recommendation:** Extract chart rendering logic to a dedicated `CircadianChart` module.

### 3d. HA Normalize Reducer

`normalize/home_assistant.ex:19-149` is still a single 126-line reducer function with 4 levels of nesting and a `cond` block distinguishing groups, grouped lights, and standalone lights.

**Recommendation:** Break into separate functions per entity type.

---

## 4. Hard-Coded Values and Magic Numbers

### 4a. Tolerance Constants (still duplicated)

- `@brightness_tolerance 2` — in both `planner.ex:17` and `desired_state.ex:11`
- `@temperature_physical_mired_tolerance 1` and `@xy_tolerance 0.01` — in `planner.ex:18-19`
- `@temperature_reconcile_mired_tolerance 1` — in `desired_state.ex:12`

**Recommendation:** Centralize in a single module (e.g., `LightStateSemantics` or a new `Control.Tolerances`).

### 4b. Mired Conversion

`1_000_000 / mired` still appears 5 times in `state_parser.ex` (lines 199, 230, 288, 410, 450). `Kelvin` module exists but doesn't expose public `from_mired/1` / `to_mired/1` helpers.

**Recommendation:** Extract `Kelvin.from_mired/1` and `Kelvin.to_mired/1` and use them.

### 4d. Entity String Prefixes

`"light."` still appears 7 times as a filtering prefix in `import/fetch/home_assistant.ex` (lines 70, 84, 160, 175, 190, 199, 275).

**Recommendation:** Promote to a module constant.

---

## 5. Naming Inconsistencies

### 5a. Function Naming

- `fetch/0` vs `fetch_for_bridge/1` — both exist in Hue, HA, Caseta modules serving the same purpose (multi vs single)
- `normalize` vs `normalize_light` vs `normalize_group` — mixed granularity in Z2M normalize
- `load_bridge` (singular, Caseta) vs `load_bridges` (implied plural, Hue)
- `dispatch_action` vs `dispatch_toggle` in LightsLive
- `execute_button_action` vs `handle_button_press` in Picos — unclear distinction
- `normalize_` vs `parse_` used interchangeably across modules
- `planner.ex` `desired_key/1` returns a LIST for grouping, not a single key
- `state_parser.ex` `parse_*` functions do transformation, not just parsing

### 5b. Scenes Naming Confusion

- `apply_scene` vs `apply_active_scene` — subtle distinction
- `reapply_active_scene_lights` and `reapply_active_circadian_lights` are compatibility wrappers for `recompute_` variants — creates naming ambiguity

### 5c. Config Key Name Drift

`executor/convergence.ex:98` chains `Application.get_env` with fallback to a config key named `manual_control_reconcile_delays_ms` — the name doesn't match the current usage (convergence delay). Evidence of a rename that never happened.

---

## 6. Architectural Observations

### 6a. Circular Dependency: Rooms ↔ Export

The cycle migrated but was not broken. `scenes.ex` no longer calls `HomeAssistantExport.refresh_*`, but `rooms.ex:34,64-65` now calls `HomeAssistantExport.refresh_room()` and `HomeAssistantExport.remove_scene/1` directly. `HomeAssistantExport` still processes via `Router`, which still calls back into domain contexts.

**Recommendation:** Break the cycle with PubSub — domain contexts broadcast events, Export subscribes. This aligns with the architecture-reset principle that upstream code decides semantics while downstream reacts.

### 6b. Missing Bridge Adapter Abstraction

All fetch, normalize, and event stream modules still independently handle credential validation, bridge loading, connection errors, and response parsing. No `@callback` definitions exist anywhere in `lib/`.

**Recommendation:** Define a `@callback`-based behavior for fetch and normalize. The `GenericEventStream` consolidation has already done this for subscriptions — the same pattern can be applied here.

### 6c. Connection Management Risks

- No exponential backoff on event stream reconnection — all use fixed 1-2 second delays. If a bridge is down, the system hammers it indefinitely.
- Caseta LEAP raw socket: if `read_initial_zone_status` times out, socket may be left open
- Hue SSE: no explicit cleanup of `HTTPoison.AsyncResponse` on GenServer crash
- Z2M: tolerates `{:error, {:already_started, pid}}` silently — if handler crashes, connection persists orphaned

**Recommendation:** Implement bounded exponential backoff. Audit socket/connection cleanup in error paths. `GenericEventStream` consolidation makes this a single-site fix now.

### 6d. Snapshot vs. Streaming Race Condition

The import pipeline operates as batch snapshots (fetch all, normalize, materialize) while event streams process incremental deltas. No synchronization mechanism exists if an import runs during event stream processing.

**Recommendation:** Document this as a known constraint, or add a brief pause/drain during import.

### 6e. Planner Reuse in Convergence Recovery

`executor.ex` calls `Planner.plan_room` during convergence recovery. The Planner is designed for initial planning — it's unclear whether calling it during recovery can cascade into unexpected replanning behavior.

**Recommendation:** Investigate whether this can cause feedback loops, especially during mixed-bridge recovery scenarios.

### 6f. Transaction Pattern Underutilized

`DesiredState.Transaction` exists but is only used in `apply.ex`. No hooks for validation, rollback, or multi-entity consistency elsewhere.

---

## 8. Schema and Ecto Query Analysis

### 8b. N+1 Query Risks

**`picos/targets.ex:29-47` — `expand_room_targets/3`:**
- `room_light_ids` (line 108): `Repo.all` per room_id
- `room_group_light_ids` (lines 125-140): `Repo.all` for group validation, then `Repo.all` for light_ids
- Three queries per call, pattern unresolved.

**Recommendation:** Batch-load all group room_ids and member lights in a single query.

### 8c. Inefficient Preloading Pattern

Four instances of `Repo.all(...) |> Repo.preload(...)` instead of `preload: [...]` in the initial query:
- `home_assistant/export/entities.ex` lines 105, 115, 127, 139
- `rooms.ex` `list_rooms_with_children/0` — `Repo.all` then preloads `[:groups, :lights, :scenes]` (3 extra queries)

---

## 9. Mix Tasks

### 9a. Shared Boilerplate Duplication

- **Timestamp generation**: duplicated in `backup_db`, `export_bridge_imports`, `normalize_bridge_imports`
- **File operation helpers**: `rename_if_exists` duplicated between `backup_db` and `restore_db`
- **Type conversion**: `to_bridge_type` duplicated between `materialize_bridge_imports` and `normalize_bridge_imports`

**Recommendation:** Extract to a shared `Hueworks.TaskHelpers` module.

### 9b. `String.to_atom` on Untrusted Data

`materialize_bridge_imports.ex:64` and `normalize_bridge_imports.ex:64` both call `String.to_atom` on bridge type strings parsed from JSON files. This can cause atom table exhaustion if an attacker controls the input files.

**Recommendation:** Validate against a whitelist (`:hue`, `:caseta`, `:ha`, `:z2m`) using `String.to_existing_atom` or explicit matching.

### 9c. Unsafe File Operations

Multiple tasks use bang variants (`File.write!`, `File.read!`, `Jason.decode!`) without meaningful error context. When these raise, error messages lack file path and operation context.

### 9d. Startup Strategy

6 of 8 tasks use `app.start` (full supervision tree). Tasks that only need database access could use `app.config` (lightweight).

---

## 10. Application Startup and Infrastructure

### 10a. No Warmup/Health Check Before Endpoint

No health check before Endpoint starts accepting HTTP requests. If subscriptions are still connecting when a user loads the UI, they'll see incomplete state.

### 10b. Release.ex

- Migrations run via `Ecto.Migrator.run(:up, all: true)` — no rollback capability, no reporting of which migrations ran
- `start_repos/0` hardcodes the repo list — minor brittleness

### 10c. Router — No Authentication

All routes use the `:browser` pipeline with CSRF protection and secure headers, but there is **no authentication or authorization layer**. Every route is publicly accessible.

Likely intentional (local-network appliance), but worth documenting. If the app is ever exposed beyond a trusted network, an auth pipeline would be needed.

### 10e. Utility Module Sprawl

`util.ex` (234 lines, up from 216) mixes generic parsing, bridge-specific logic, room logic, light control normalization, error formatting, and filter logic. Becoming a dumping ground.

**Recommendation:** Split into focused submodules: `Util.Numeric`, `Util.Display`, `Util.Parsing`. Can be done incrementally.

---

## 11. Test Suite

Test surface has grown substantially in the recent refactor (71 → 89 test files). Source module count also grew (153 → 204). Structural observations below still apply; exact percentages should be re-measured.

### 11a. Error Path Coverage Is Thin

Most tests verify happy paths. Timeout scenarios, malformed subscription payloads, database constraint violations, concurrent state conflicts, and connection failures remain under-tested.

### 11b. No Property-Based Testing

All tests are example-based. Calculation-intensive modules (`Circadian`, `Color`, `Kelvin`) would benefit from `stream_data` property tests.

### 11c. No Mox Framework

External dependencies are mocked via `Application.put_env` substitution and inline stub modules. Works, but lacks call count/order verification that Mox provides.

### 11d. Large Test Files

- `circadian_integration_test.exs`: 1,427 lines
- `control_planner_test.exs`: 979 lines
- `home_assistant_export_test.exs`: 806 lines

Would benefit from splitting into focused test modules with `describe` blocks.

### 11e. No Factory Pattern

Each test file defines its own helper functions for creating test data. A shared factory module would reduce duplication and ensure consistent test data.

---

## 12. Config/Environment Management

### 12a. Config Value Scattering

Settings are read from multiple sources with inconsistent patterns:
- `Application.get_env` — ~30+ modules
- `AppSettings.get_global()` — database-backed settings with cache
- `System.get_env` — `release.ex` and some tasks
- Module attributes — compile-time constants

No single inventory of all configuration knobs. Adding a new setting requires knowing which mechanism to use.

### 12b. Conditional Feature Flags

Two features use conditional startup in `application.ex`:
- `:circadian_poll_enabled` (default: true)
- `:ha_export_runtime_enabled` (default: true)

Plus HA export has sub-toggles (`scenes_enabled?`, `lights_enabled?`) in AppSettings. The relationship between the startup flag and runtime sub-toggles is not obvious.

---

## 13. Type Safety & Specs

### 13a. @spec Coverage (partial progress — 3 → 83 specs; dialyxir added)

`dialyxir` is present at `mix.exs:60`. Specs have grown to ~83 across 10 modules (from 3). Still zero `@callback` definitions anywhere.

**Critical modules still without specs:** `state.ex`, `desired_state.ex`, most of the control pipeline, LiveViews, contexts.

**Recommendation:** Continue the momentum — next targets are the 5 control modules (`state.ex`, `desired_state.ex`, `light_state_semantics.ex`, `state_parser.ex`, `scenes.ex`). Since dialyxir is wired up, any specs added will be verified.

### 13b. Light State Is Still a Bare Map in the Control Pipeline

`DesiredAttrs` struct exists in `scenes/intent.ex` (fields: power, brightness, kelvin, x, y) — but `to_map/1` is called at the pipeline boundary (`DesiredState.apply`), so the ETS layer still stores bare maps. `state_parser.ex` still returns bare maps; `state.ex` still works with `state_map()` type alias on bare maps.

**Recommendation:** Make `state_parser.ex` return a struct (or at minimum atom-keyed maps) so that normalized data enters the ETS layer in a consistent shape. This eliminates 1a at its root.

### 13c. Mixed Return Types Without Specs

`scenes.ex` has several functions whose return shapes are only discoverable by reading the implementation:
- `apply_scene/2`: returns `{:ok, map(), map()}` in success, other shapes on failure
- `recompute_active_scene_lights/3`: returns `{:ok, %{}, %{}}` or `{:error, :invalid_args}` — the two empty-map returns aren't the same kind of data
- `list_editable_light_states_with_usage/0`: returns a list of ad-hoc maps `%{state: LightState, usage_count: int, usages: list}` — natural struct candidate

### 13d. Boundary Typing Is Uniformly Weak

At every system boundary, data flows as untyped maps:
- **MQTT/Z2M boundary**: bridge credentials normalized but no `@type`
- **HA WebSocket boundary**: JSON decode → bare maps, no schema enforcement
- **LiveView ↔ domain**: `lights_live.ex` merges `Loader.mount_assigns()` (untyped) into socket assigns
- **Ecto ↔ domain**: Ecto schemas are typed, but loaded into control state as bare maps (`state.ex`: `get(type, id) || %{}`)

---

## 14. Observability & Logging

### 14a. Logger Usage Is Sparse and Inconsistent

Most modules have no logging. Mix of deprecated `Logger.warn` and current `Logger.warning`. No Logger calls use metadata (`Logger.info("...", key: value)`) — everything is raw string interpolation. No correlation IDs or request-scoped logging.

**Recommendation:** Standardize on `Logger.warning`. Start adding structured metadata at least in connection managers and the executor.

### 14c. DebugLogging Module Is Underused

`Hueworks.DebugLogging` exists to gate verbose control-pipeline logs behind `:advanced_debug_logging` config. Only 2 modules use it (`control/planner.ex`, `scenes.ex`). It directly wraps `Logger.info`; no module calls `DebugLogging.enabled?()` to gate additional logs.

**Recommendation:** Either expand across the control pipeline (executor, state managers, subscriptions) or remove it in favor of standard Logger metadata.

### 14d. Trace Propagation Is Partially Implemented

Trace infrastructure is plumbed through the control pipeline via an optional `:trace` keyword:
- `Scenes.apply_scene/2` accepts trace, enriches with `trace_room_id`, `trace_scene_id`, `trace_target_occupied`
- `Planner.plan_snapshot/3` emits `planner_input`, `planner_partition`, `planner_group_pick`, `planner_light_decision`, `planner_output` — **only if `trace_id` is present**
- `Executor.dispatch_tick/1` logs `dispatch_start`, `dispatch_end`, `convergence_ok`, `convergence_retry` — **only if `action.trace_id` is set**

**Gaps:**
- No automatic trace ID generation — if a caller doesn't pass a trace, all downstream logging goes silent
- Subscription event → scene apply path is **not traced at all**
- LiveView → domain calls don't propagate trace context

**Recommendation:** Generate a trace ID by default in `Scenes.apply_scene/2` when one isn't provided. This activates all existing instrumentation for free.

### 14f. Error Logging Quality Is Low

- Rescue blocks capture `Exception.message/1` only; stack traces are lost
- Connection errors (Hue SSE, HA WebSocket, Caseta LEAP) log reasons but no retry count, no backoff state, no cumulative failure count

### 14g. Telemetry Is Nearly Absent

Only 2 telemetry metrics exist (`phoenix.endpoint.stop.duration`, `phoenix.router_dispatch.stop.duration`). `periodic_measurements` returns empty. **Zero custom `:telemetry.execute` calls** anywhere.

Blind spots:
- **Control pipeline**: no per-light latency, per-bridge throughput, planner timing
- **Subscription lag**: no measurement of event-received-to-state-applied latency
- **Import pipeline**: no phase timing (fetch, normalize, materialize)
- **Error rates**: no counters

**Recommendation:** `:telemetry.span` wrapping the dispatch loop and event handler would give latency histograms without rewriting logging.

---

## 15. Dependencies & mix.exs

### 15b. Missing Dev Tooling (partial)

`dialyxir` is present. Still missing:

| Tool | Status |
|------|--------|
| `dialyxir` | ✓ Present |
| `ex_doc` | Missing |
| `excoveralls` | Missing |

Skip `ex_doc` unless publishing docs. `excoveralls` is only valuable if you're going to act on coverage numbers.

### 15c. Tortoise Maintenance Concern

`tortoise ~> 0.10` is locked at `0.10.0` — slow release cadence, effectively at its last major release. Still works, but for a critical path (Z2M subscription + HA export), this is a sustainability risk.

**Options:** Monitor Tortoise repo; alternative is `emqtt` (from EMQX). Don't migrate preemptively — only worth acting on if you hit a bug.

### 15d. Phoenix LiveView Version

Phoenix 1.7.21, LiveView 0.20.17. LiveView 1.0 is released; `0.20.x` is still stable and compatible. Future project.

### 15e. HTTPoison → hackney Chain

HTTPoison pulls in hackney, which pulls in an older SSL stack. Not a security issue as long as system-level certificate management is in place. Alternative is `Req` (Finch → Mint → native `:ssl`), but migrating 8 files currently using HTTPoison is not a priority.
