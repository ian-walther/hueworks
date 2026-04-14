# Claude Architecture Audit

## Purpose
Independent code audit of the HueWorks codebase, performed by Claude as a second-opinion review alongside the existing `refactoring.md` priorities. Findings here are complementary — they focus on code-level patterns, duplication, error handling, naming, and structural issues rather than repeating the architectural direction already documented.

## Audit Status

| Area | Status | Chunk |
|------|--------|-------|
| Control layer (executor, planner, state) | Done | 1 |
| Scenes + HA export | Done | 1 |
| LiveViews + domain (picos, circadian, kelvin) | Done | 1 |
| Import pipeline + subscriptions | Done | 1 |
| Schemas + Ecto queries | Done | 2 |
| Mix tasks + application startup | Done | 2 |
| Test suite structure + coverage gaps | Done | 2 |
| Config/env management patterns | Done | 2 |
| Cross-cutting: type safety + specs | Done | 3 |
| Cross-cutting: observability + logging | Done | 3 |
| Cross-cutting: dependency review | Done | 3 |

---

## Chunk 1 Findings

### 1. Systemic Duplication Patterns

These are the highest-value refactoring targets because they affect multiple modules and increase the cost of every future change.

#### 1a. String/Atom Dual-Key Handling (6+ modules)

Data from MQTT and external sources arrives with string keys; the domain model uses atoms. The conversion is handled ad-hoc in at least 6 places with slightly different patterns:

- `export/messages.ex`: 6 instances of checking both `:key` and `"key"`
- `scenes/intent.ex`: `config_lookup/2` tries string then atom (lines 158-178), `manual_mode/1` checks both (180-186), `light_default_lookup/2` checks int and string keys (188-201), `parse_default_power/1` has 8 clause patterns for true/"true"/1/"1"/:on/"on"
- `export/commands.ex`: `drop_kelvin/1` deletes 4 key variants, `drop_xy/1` deletes 4 key variants, `incoming_has_xy?/1` and `incoming_has_kelvin?/1` each check 4 variants
- `control/light_state_semantics.ex`: `key_aliases/1` returns mixed lists
- `control/state_parser.ex`: inline `Map.get(attrs, :kelvin) || Map.get(attrs, "kelvin")`
- `control/executor.ex`: `Map.get(desired, :power) || Map.get(desired, "power")`

**Recommendation:** Extract a shared `KeyNormalize` or similar utility with `get_any(map, atom_key)` that checks both forms, and `delete_any(map, keys)` / `has_any?(map, keys)` helpers. Then progressively adopt it. This would eliminate ~100 lines of duplicated guard logic.

#### 1b. Color/Temperature Harmonization (3 modules)

The logic ensuring xy coordinates and kelvin don't coexist is copy-pasted:

- `hueworks_app/control/state.ex` lines 114-158: `harmonize_color_and_temperature`, `drop_kelvin`, `drop_xy`, `incoming_has_xy?`, `incoming_has_kelvin?`
- `hueworks_app/control/desired_state.ex` lines 118-186: exact same functions
- `control/light_state_semantics.ex` lines 163-181: `drop_kelvin`, `drop_xy`

**Recommendation:** Single source of truth in `LightStateSemantics` (or a new `LightState.Normalize` module), imported by State and DesiredState.

#### 1c. Event Stream Manager Duplication (4 files, ~250 lines)

The four event stream managers are structurally identical:

- `hueworks_app/subscription/hue_event_stream.ex` (85 lines)
- `hueworks_app/subscription/home_assistant_event_stream.ex` (85 lines)
- `hueworks_app/subscription/caseta_event_stream.ex` (85 lines)
- `hueworks_app/subscription/z2m_event_stream.ex` (75 lines)

They share: `@restart_delay_ms`, `@retry_delay_ms`, identical `start_link/init/handle_info` implementations, and the same `maybe_start_connections` pattern with only the `:type` filter varying.

**Recommendation:** A single parametrized `GenericEventStream` module with bridge type as init arg would eliminate ~250 lines. Low risk since the structure is already identical.

#### 1d. Fetch Module Duplication (3 modules, ~120 lines)

`fetch/0` and `fetch_for_bridge/1` in each fetch module (Hue, HA, Caseta) are 80-90% identical — they differ only in the bridge type filter and credential extraction.

**Recommendation:** Extract shared `fetch_all(type, &fetch_fn/1)` and `fetch_one(bridge, &fetch_fn/1)` wrappers. Also: `invalid_credential?/1` is repeated verbatim in 4+ files — extract to `Credentials` module.

#### 1e. LightsLive dispatch_action Duplication (~100 lines)

`dispatch_action/4` has 8 clauses for light/group x brightness/color_temp/color/power. The light and group variants for each action type are ~90% identical.

**Recommendation:** Consolidate to a single function per action type that accepts entity type as parameter.

#### 1f. Blank Component Definition (3 files)

`@blank_component` is defined identically in `SceneBuilderComponent`, `SceneEditorLive`, and `PicoConfigLive`.

**Recommendation:** Define once in a shared location (e.g., `Scenes.Builder` already exists and is the natural home).

#### 1g. Materialize upsert Duplication

`upsert_lights/4` (lines 92-134) and `upsert_groups/4` (lines 137-179) in `materialize.ex` are structurally identical — 43 lines each with only schema and field names differing.

**Recommendation:** Extract parameterized `upsert_entities/5`.

---

### 2. Error Handling Issues

#### 2a. Bare Rescue Blocks

- `import/pipeline.ex` lines 35-37 and 41-43: `rescue error -> {:error, Exception.message(error)}` — swallows stack trace, loses exception type
- `subscription/readiness.ex` line 17: `rescue _error -> false` — silently converts any exception to false, making it impossible to distinguish "table not ready" from "database connection error"

**Recommendation:** Use `Logger.error` with `Exception.format(:error, error, __STACKTRACE__)` in rescue blocks. Return structured error tuples.

#### 2b. Silent Error Swallowing

- `export/router.ex` `handle_light_command/5` (lines 88-119): `else` clause uses wildcard `_`, silently discarding all errors with no logging
- `export/connection.ex` line 238: `_ = reason` ignores connection error
- `import/fetch/home_assistant.ex` lines 152-185: all registry fetches silently return empty lists on error
- `scenes/intent.ex` `Circadian.calculate/3` (line 78): catches errors, logs warning, returns empty map — callers can't distinguish "circadian disabled" from "calculation failed"
- `executor.ex` line 281: bare `_ ->` treats ALL unknown dispatch results as success

**Recommendation:** Establish a pattern: errors at system boundaries get logged with context; errors in internal calls get propagated as tuples. The executor line 281 catch-all is the highest risk — unknown dispatch results should not be treated as success.

#### 2c. Inconsistent Error Return Styles

- `import/fetch/hue.ex` `fetch_endpoint`: returns `%{error: "..."}` (map with error key)
- Z2M fetch: returns `{:error, reason}` tuples
- Caseta fetch: uses `IO.puts` on error instead of Logger
- Materialize: `infer_group_rooms/1` performs DB updates as side effect with no return value

**Recommendation:** Standardize on `{:ok, result} | {:error, reason}` throughout. Replace `IO.puts` with Logger calls.

---

### 3. Complexity Hotspots

These are the functions and modules where cognitive complexity is highest.

#### 3a. Planner Group/Light Planning (planner.ex lines 129-183)

The planning loop groups actions by desired state, then reconstructs candidate_ids by re-filtering ALL room_lights with the same criteria it already grouped by. Data is transformed multiple times unnecessarily. Recursive group planning (lines 229-238) passes 8 parameters.

**Recommendation:** Pass through original grouping data instead of reconstructing. Consider a struct for the 8-parameter recursive call.

#### 3b. LightStateEditorLive (810 lines — largest file)

This LiveView handles form updates, chart pixel calculations, circadian preview rendering, and timezone management. Specific issues:
- `key_to_atom/1` (lines 337-362): 26 match clauses converting strings to atoms — indicates a data structure normalization problem
- Chart calculation functions (lines 572-693): pixel math, axis labels, tick marks tightly coupled to LiveView
- Hardcoded timezone list (lines 777-796)
- `@chart_width 640`, `@chart_height 188`, `@chart_padding` — magic numbers for chart rendering

**Recommendation:** Extract chart rendering logic to a dedicated `CircadianChart` module. The `key_to_atom` problem should be solved upstream by normalizing keys at the boundary where data enters the system.

#### 3c. PicoConfigLive handle_info (lines 397-451)

4-5 levels of nested `cond` blocks handling Pico button press events. 40+ lines of logic in a single function.

**Recommendation:** Extract each branch to a named helper function.

#### 3d. HA Normalize Reducer (normalize/home_assistant.ex lines 19-149)

Single 149-line reducer function with 4 levels of nesting and a `cond` block distinguishing groups, grouped lights, and standalone lights.

**Recommendation:** Break into separate functions per entity type.

#### 3e. Picos.Config.clone_device_config (lines 14-91)

78-line transaction with nested device cloning. No error recovery if transaction fails mid-stream.

**Recommendation:** Break into smaller transactional steps with explicit error handling.

---

### 4. Hard-Coded Values and Magic Numbers

#### 4a. Tolerance Constants (defined in 2+ places)

- `@brightness_tolerance 2` — in both `planner.ex` (line 16) and `desired_state.ex` (line 11)
- `@temperature_physical_mired_tolerance 1` — in `planner.ex` (line 17)
- `@temperature_reconcile_mired_tolerance 1` — in `desired_state.ex` (line 12)
- `@xy_tolerance 0.01` — in `planner.ex` (line 18)

**Recommendation:** Centralize tolerance constants in a single module (e.g., `LightStateSemantics` or a new `Control.Tolerances`).

#### 4b. Mired Conversion

`1_000_000 / mired` appears 8+ times in `state_parser.ex` instead of using a helper function.

**Recommendation:** Extract to `Kelvin.from_mired/1` and `Kelvin.to_mired/1`.

#### 4c. Rate Limits and Timeouts

- `executor.ex` line 21: `@default_rates %{hue: 10, ha: 5, caseta: 5, z2m: 5}`
- `executor.ex` lines 22-23: `@default_max_retries 3`, `@default_backoff_ms 250`
- Event streams: `@restart_delay_ms 1_000`, `@retry_delay_ms 2_000` in 4 files
- Caseta fetch: `@bridge_port 8081`, various `5000` timeouts
- Z2M fetch: `@snapshot_timeout 8_000`
- HA fetch: `10_000` timeout in receive block

These are all reasonable as module attributes, but the event stream ones are duplicated and the Caseta port is not configurable.

#### 4d. Entity String Prefixes

`"light."` appears 5+ times in `import/fetch/home_assistant.ex` as a filtering prefix. Should be a module constant.

---

### 5. Naming Inconsistencies

#### 5a. Function Naming

- `fetch/0` vs `fetch_for_bridge/1` — both exist in Hue, HA, Caseta modules but serve the same purpose (multi vs single)
- `normalize` vs `normalize_light` vs `normalize_group` — mixed granularity in Z2M normalize
- `load_bridge` (singular, Caseta) vs `load_bridges` (implied plural, Hue)
- `dispatch_action` vs `dispatch_toggle` in LightsLive — inconsistent
- `execute_button_action` vs `handle_button_press` in Picos — unclear distinction
- `normalize_` vs `parse_` functions used interchangeably across modules
- `planner.ex` `desired_key/1` returns a LIST for grouping, not a single key
- `state_parser.ex` `parse_*` functions do transformation, not just parsing

#### 5b. Scenes Naming Confusion

- `apply_scene` vs `apply_active_scene` — subtle distinction
- `reapply_active_scene_lights` and `reapply_active_circadian_lights` are compatibility wrappers for `recompute_` variants — creates naming ambiguity

#### 5c. Config Key Naming

- `executor.ex` lines 578-588: convergence delay fallback to `manual_control_reconcile_delays_ms` — name mismatch suggests code evolution/technical debt

---

### 6. Architectural Observations

These go beyond what's in `refactoring.md` and represent structural patterns worth noting.

#### 6a. Circular Dependency: Scenes <-> Export

- `Scenes` (line 12) calls `HomeAssistantExport.refresh_*`
- `HomeAssistantExport` processes scenes via `Router`
- `Router` calls back into `Scenes`

**Recommendation:** Break the cycle with PubSub — Scenes broadcasts events, Export subscribes. This aligns with the architecture-reset principle that upstream code decides semantics while downstream reacts.

#### 6b. Missing Bridge Adapter Abstraction

All fetch, normalize, and event stream modules independently handle credential validation, bridge loading, connection errors, and response parsing. No shared behavior or protocol.

**Recommendation:** Define a `@callback`-based behavior for fetch and normalize. This would enforce consistency and make adding new bridge types (or modifying shared patterns) safer.

#### 6c. Connection Management Risks

- No exponential backoff on event stream reconnection — all use fixed 1-2 second delays. If a bridge is down, the system hammers it indefinitely.
- Caseta LEAP raw socket: if `read_initial_zone_status` times out, socket may be left open
- Hue SSE: no explicit cleanup of `HTTPoison.AsyncResponse` on GenServer crash
- Z2M: tolerates `{:error, {:already_started, pid}}` silently — if handler crashes, connection persists orphaned

**Recommendation:** Implement bounded exponential backoff for all event streams. Audit socket/connection cleanup in error paths.

#### 6d. Snapshot vs. Streaming Race Condition

The import pipeline operates as batch snapshots (fetch all, normalize, materialize) while event streams process incremental deltas. No synchronization mechanism exists if an import runs during event stream processing.

**Recommendation:** Document this as a known constraint, or add a brief pause/drain during import.

#### 6e. Planner Reuse in Convergence Recovery

`executor.ex` line 477 calls `Planner.plan_room` during convergence recovery. The Planner is designed for initial planning — it's unclear whether calling it during recovery can cascade into unexpected replanning behavior.

**Recommendation:** Investigate whether this can cause feedback loops, especially during mixed-bridge recovery scenarios.

#### 6f. Transaction Pattern Underutilized

`DesiredState.Transaction` exists but is only used in `apply.ex`. No hooks for validation, rollback, or multi-entity consistency elsewhere.

---

### 7. Positive Patterns Worth Preserving

- `Circadian` and `Color` modules are well-designed mathematical implementations with clean interfaces
- `LightsLive.DisplayState` and `Loader` effectively separate data loading from presentation
- `Picos.Actions` has clear separation of concerns
- Bridge dispatch in `Light` and `Group` modules uses clean pattern matching
- `Export.Runtime` is a model of single-responsibility design (59 lines, all functions <15 lines)
- `Export.Handler` is minimal and focused (42 lines)
- Good use of `with` for error handling in most domain modules
- `Builder.ex` (133 lines) is clean, functional-style code

---

---

## Chunk 2 Findings

### 8. Schema and Ecto Query Analysis

#### 8a. Schema Design — Generally Solid

16 schema modules were reviewed. Key observations:

- **Validation is thorough**: `AppSetting` has multi-changeset pattern with conditional validation (`validate_ha_export_requirements/1`). `LightState` routes to type-specific validators. `Group` and `Light` have custom kelvin-source and self-reference validations.
- **Associations are well-defined**: Join tables (`GroupLight`, `SceneComponentLight`) properly use composite unique constraints. Through-associations used where appropriate.
- **Single changeset per schema** (except `AppSetting` which needs two) — clean pattern.

#### 8b. N+1 Query Risks

**`picos/targets.ex` lines 22-38 — `expand_room_targets/3`:**
```
group_ids |> Enum.flat_map(fn group_id ->
  Repo.one(from(g in Group, where: g.id == ^group_id, select: g.room_id))
  Groups.member_light_ids(group_id)  # ANOTHER QUERY INSIDE LOOP
end)
```
One query per group_id + one query per group to get member lights = O(n) queries.

**Recommendation:** Batch-load all group room_ids and member lights in a single query.

**`picos/targets.ex` lines 96-103 — `scene_name_for_target/2`:**
Loads ALL scenes for a room via `Scenes.list_scenes_for_room/1`, then finds one by ID in memory. Should query the specific scene directly.

#### 8c. Inefficient Preloading Pattern (4 instances)

`home_assistant/export/entities.ex` lines 97-138 loads records then preloads in a separate query:
```
Repo.all(from(l in Light, where: ...))
|> Repo.preload(:room)  # SEPARATE QUERY
```
This pattern appears 4 times. Should use `preload: [:room]` in the initial query.

Similarly, `rooms.ex` `list_rooms_with_children/0` does `Repo.all(...)` then `|> Repo.preload([:groups, :lights, :scenes])` — 3 additional queries.

#### 8d. Transaction Usage — Sound

All 5 transaction sites are correctly structured:
- `scenes.ex` — atomic scene component replacement
- `external_scenes.ex` — sync transaction
- `bridges.ex` — cascade deletion
- `picos/config.ex` — device config cloning
- `import/pipeline.ex` — import creation

#### 8e. Index Coverage

Index coverage is generally good. All foreign keys have corresponding indexes in migrations. No missing critical indexes identified.

One note: `fragment("lower(?)", r.name)` in `materialize.ex` line 65 is SQLite-specific for case-insensitive search — acceptable given the project targets SQLite, but worth noting if the database ever changes.

---

### 9. Mix Tasks

8 mix tasks were reviewed. Key findings:

#### 9a. Shared Boilerplate Duplication

- **Timestamp generation**: duplicated in `backup_db`, `export_bridge_imports`, `normalize_bridge_imports`
- **File operation helpers**: `rename_if_exists` duplicated between `backup_db` and `restore_db`
- **Type conversion**: `to_bridge_type` duplicated between `materialize_bridge_imports` and `normalize_bridge_imports`

**Recommendation:** Extract to a shared `Hueworks.TaskHelpers` module.

#### 9b. `String.to_atom` on Untrusted Data

`materialize_bridge_imports.ex` line 64 and `normalize_bridge_imports.ex` line 64 both call `String.to_atom` on bridge type strings parsed from JSON files. This can cause atom table exhaustion if an attacker controls the input files.

**Recommendation:** Validate against a whitelist (`:hue`, `:caseta`, `:ha`, `:z2m`) using `String.to_existing_atom` or explicit matching.

#### 9c. Unsafe File Operations

Multiple tasks use bang variants (`File.write!`, `File.read!`, `Jason.decode!`) without meaningful error context. When these raise, the error message lacks the file path and operation context.

**Recommendation:** Wrap in `case File.read(path)` with descriptive error messages, or at minimum rescue with context.

#### 9d. Startup Strategy

6 of 8 tasks use `app.start` (full supervision tree). Only `backup_db` and `normalize_bridge_imports` correctly use `app.config` (lightweight, no daemons). Some tasks that only need database access may not need the full supervision tree.

---

### 10. Application Startup and Infrastructure

#### 10a. Supervision Tree Structure

```
Supervisor (:one_for_one)
  ├── Repo
  ├── PubSub
  ├── Cache.Store
  ├── Control.State
  ├── Control.DesiredState
  ├── Control.Executor
  ├── CircadianPoller (conditional)
  ├── HueEventStream
  ├── HomeAssistantEventStream
  ├── CasetaEventStream
  ├── Z2MEventStream
  ├── HomeAssistant.Export (conditional)
  └── Endpoint
```

**Child ordering is correct:** Repo first, Endpoint last, state modules before executor, executor before subscriptions.

**`:one_for_one` strategy is appropriate** — children are mostly independent. If Repo crashes, downstream services will fail on their next DB call and recover when Repo restarts.

**Conditional startup** for CircadianPoller and HA Export uses clean `Enum.reject(&is_nil/1)` pattern.

**Concern:** No warmup/health check before Endpoint starts accepting HTTP requests. If subscriptions are still connecting when a user loads the UI, they'll see incomplete state.

#### 10b. Release.ex

- Migrations run via `Ecto.Migrator.run(:up, all: true)` — no rollback capability, no reporting of which migrations ran
- Seed handling is well-implemented with proper error tuples and file existence check
- `start_repos/0` hardcodes the repo list — minor brittleness

#### 10c. Router — No Authentication

All routes use the `:browser` pipeline with CSRF protection and secure headers, but there is **no authentication or authorization layer**. Every route is publicly accessible.

This is likely intentional (local-network appliance), but worth documenting as a constraint. If the app is ever exposed beyond a trusted network, an auth pipeline would be needed.

#### 10d. Telemetry — Minimal

Only 2 metrics are collected:
1. `phoenix.endpoint.stop.duration` — total request time
2. `phoenix.router_dispatch.stop.duration` — router dispatch time

**Missing instrumentation for:**
- Database query timing (no `ecto_sql` events)
- Executor queue depth and dispatch latency
- Subscription event processing time and connection health
- LiveView mount/handle_event timing
- VM memory and process count
- Error rates

`periodic_measurements()` returns an empty list — no gauge-style metrics.

**Recommendation:** This is the biggest observability gap in the project. Adding Ecto telemetry events and executor/subscription metrics would significantly improve production debugging.

#### 10e. Utility Module Sprawl

`util.ex` (216 lines) mixes generic parsing, bridge-specific logic, room logic, light control normalization, error formatting, and filter logic. It's becoming a dumping ground.

**Recommendation:** Split into focused submodules: `Util.Numeric`, `Util.Display`, `Util.Parsing`. This can be done incrementally.

`app_settings.ex` (278 lines) has significant internal duplication — settings are projected in 2+ places (`with_defaults_from_current` and `normalize_attrs`), so adding a new setting requires updating multiple functions.

**Recommendation:** Consolidate setting projections into a single map definition.

#### 10f. bridge_seeds.ex — Well Implemented

Comprehensive validation, proper error tuples, transactional upserts with `on_conflict`. One of the better-implemented infrastructure modules.

---

### 11. Test Suite Analysis

**443 tests across 71 test files. 153 source modules total.**

#### 11a. Coverage: 46% Module Coverage

61 of 153 source modules have corresponding tests. The remaining 92 modules are untested.

**Critical untested modules:**
- All bridge client modules (`HueBridge`, `Z2MBridge`, `HomeAssistantBridge`, `CasetaBridge`)
- Context modules (`Bridges`, `Groups`, `Lights`, `Rooms`) — repository query logic untested
- `ExternalScenes` and `ExternalSceneMapping`
- LightsLive submodules (`DisplayState`, `Editor`, `Entities`, `Loader`)
- All mix tasks
- Cache module

**Well-tested areas:**
- Circadian calculations (900+ lines of tests with reference outputs)
- Control planning and state parsing
- Import pipeline (normalize, materialize, link)
- Scene activation round-trips
- Payload formatting (Hue, Z2M, HA)

#### 11b. Error Path Coverage: ~3%

Only ~14 of 443 tests verify error scenarios. This is the single biggest test quality gap.

**Covered:** Invalid JSON in seeds, circadian config validation, schema validation, missing light states.

**Not covered:** Timeout scenarios, malformed subscription payloads, database constraint violations, concurrent state conflicts, connection failures.

#### 11c. No Property-Based Testing

All tests are example-based. Calculation-intensive modules like `Circadian`, `Color`, and `Kelvin` would benefit significantly from `stream_data` property tests to explore input spaces.

#### 11d. No Mox Framework

External dependencies are mocked via Application.put_env substitution and inline stub modules. This works but lacks call count/order verification that Mox provides.

#### 11e. Integration-Heavy Balance

75% of tests are `async: false` (integration). This is appropriate for a hardware control system where state interactions matter, but it means the test suite runs sequentially and slowly.

#### 11f. Test Infrastructure — Solid

- Proper ETS table cleanup in setup blocks
- `on_exit` cleanup for env substitution
- DataCase sandbox with shared mode
- Fresh DB rows per test (no brittle ID assumptions)
- Test fixtures for realistic data-driven scenarios

#### 11g. Large Test Files

- `circadian_integration_test.exs`: 1,427 lines (19 tests)
- `control_planner_test.exs`: 979 lines (20 tests)
- `home_assistant_export_test.exs`: 806 lines (20 tests)

These could benefit from splitting into focused test modules with `describe` blocks.

#### 11h. No Factory Pattern

Each test file defines its own helper functions for creating test data. A shared factory module would reduce duplication and ensure consistent test data across the suite.

---

### 12. Config/Environment Management

#### 12a. Config Value Scattering

Settings are read from multiple sources with inconsistent patterns:
- `Application.get_env` — used directly in ~30+ modules
- `AppSettings.get_global()` — database-backed settings with cache
- `System.get_env` — used in release.ex and some tasks
- Module attributes (`@default_rates`, `@brightness_tolerance`) — compile-time constants

There's no single inventory of all configuration knobs. Adding a new setting requires knowing which mechanism to use.

#### 12b. Config Key Name Drift

`executor.ex` lines 578-588 chain `Application.get_env` with fallback to a config key named `manual_control_reconcile_delays_ms` — the name doesn't match the current usage (convergence delay). This suggests the config key name drifted as the feature evolved but was never renamed.

#### 12c. Conditional Feature Flags

Two features use conditional startup in application.ex:
- `:circadian_poll_enabled` (default: true)
- `:ha_export_runtime_enabled` (default: true)

Plus HA export has sub-toggles (`scenes_enabled?`, `lights_enabled?`, etc.) in AppSettings. The relationship between the startup flag and the runtime sub-toggles is not obvious.

---

---

## Chunk 3 Findings

Sub-area status:
- [x] 13. Type safety & specs
- [x] 14. Observability & logging
- [x] 15. Dependencies & mix.exs

---

### 13. Type Safety & Specs

#### 13a. @spec Coverage Is Effectively Zero

Only **3 `@spec` declarations exist across 153 modules** (~2% coverage):
- `circadian.ex` — 1 @spec (for `calculate/3`)
- `circadian_preview.ex` — 2 @specs

Every other module — including the critical state/control/planner/executor path — has zero type specifications.

- **No `@callback` definitions** anywhere (no behaviors)
- **Only 1 `@type` definition** (Circadian's `calc_result`)
- **dialyxir is not in mix.exs** — no static type checking is configured at all
- No `.dialyzer_ignore.exs` or PLT setup

**Recommendation:** Adding `@spec` everywhere at once is impractical. Start with the 5 modules that matter most for correctness: `state.ex`, `desired_state.ex`, `light_state_semantics.ex`, `state_parser.ex`, `scenes.ex`. Then add dialyxir so future specs are verified. This pairs well with the light state struct recommendation below.

#### 13b. Light State Is a Bare Map Everywhere

The most consequential data shape in the system — `%{power: :on, brightness: 0..100, kelvin: 2000..6500, x: float, y: float}` — is represented as a bare map throughout:

- `hueworks_app/control/desired_state.ex` lines 41-104: state stored as `%{}`, merged with `Map.merge(attrs)`, no type guarantee
- `hueworks_app/control/state.ex` lines 97-112: `merge_and_store/3` accepts and returns bare maps
- `control/light_state_semantics.ex` lines 9-20: `diff_state/2` uses `is_map(actual)` / `is_map(desired)` guards only

These maps are interchangeably keyed with atoms or strings (already documented in Chunk 1 finding 1a, but the type-safety angle is that this ambiguity is only possible because there's no struct).

Only **one non-Ecto struct exists in the entire codebase**: `Hueworks.Control.DesiredState.Transaction` — and even that one has no `@type t` definition.

**Recommendation:** Define a `LightState` struct (non-Ecto, in-memory only) with unified atom keys and a `@type t` definition. Use it as the return type of `state_parser.ex` functions and the storage shape in State/DesiredState. This would eliminate the atom/string duality at its root and give every downstream function a concrete type to pattern-match on.

#### 13c. Mixed Return Types Without Specs

`scenes.ex` has several functions whose return shapes are only discoverable by reading the implementation:
- `apply_scene/2` (line 302-352): returns `{:ok, map(), map()}` in success, other shapes on failure — the second map is undocumented
- `recompute_active_scene_lights/3` (line 376-379): returns `{:ok, %{}, %{}}` or `{:error, :invalid_args}` — the two empty-map returns aren't the same kind of data
- `list_editable_light_states_with_usage/0` (line 40-52): returns a list of ad-hoc maps `%{state: LightState, usage_count: int, usages: list}` — natural struct candidate

#### 13d. Boundary Typing Is Uniformly Weak

At every system boundary, data flows as untyped maps:
- **MQTT/Z2M boundary**: `z2m_event_stream/connection.ex` normalizes bridge credentials into a typed-looking map but returns no `@type`. Parser side (`state_parser.ex` `z2m_state/2`) accepts raw MQTT payload as bare map.
- **HA WebSocket boundary**: `home_assistant_event_stream/connection.ex` builds state as bare map, JSON decode produces bare maps, `StateParser.home_assistant_state` has no schema enforcement.
- **LiveView ↔ domain**: `lights_live.ex` (613 lines, zero @specs) merges `Loader.mount_assigns()` (untyped) into socket assigns.
- **Ecto ↔ domain**: Ecto schemas are typed, but when loaded into control state they're converted to bare maps (`state.ex` line 51: `get(type, id) || %{}`).

**Recommendation:** If the `LightState` struct (13b) is introduced, the natural next step is to make it the canonical shape at each of these boundaries.

---

### 14. Observability & Logging

#### 14a. Logger Usage Is Sparse and Inconsistent

Only **41 Logger calls across 14 files** in the entire codebase (153 modules total). Most modules have no logging at all.

Level breakdown:
- `Logger.debug`: 1 call
- `Logger.info`: 4 calls
- `Logger.warning` / `Logger.warn`: 10 calls (mixed — deprecated `warn` and current `warning` both in use)
- `Logger.error`: 1 call

No Logger calls use metadata (`Logger.info("...", key: value)`) — everything is raw string interpolation. No correlation IDs or request-scoped logging.

**Recommendation:** Standardize on `Logger.warning` (remove deprecated `warn`). Start adding structured metadata at least in connection managers and the executor.

#### 14b. IO.puts in Production Code (12 instances)

These should all be `Logger.info` or `Logger.warning`:
- `import/fetch/caseta.ex` lines 19, 22, 25, 92, 134
- `import/fetch/home_assistant.ex` lines 20, 23, 26, 29, 32
- `import/fetch/hue.ex` line 22
- `hardware_smoke.ex` line 512

In production (especially under Docker), these bypass the log formatter and log level filtering.

#### 14c. DebugLogging Module Is Underused

`Hueworks.DebugLogging` exists to gate verbose control-pipeline logs behind `:advanced_debug_logging` config. Only **2 modules import it**: `control/planner.ex` and `scenes.ex`. It directly wraps `Logger.info`, but no module actually calls `DebugLogging.enabled?()` to gate additional logs.

**Recommendation:** Either expand its use across the control pipeline (executor, state managers, subscriptions) or remove it in favor of standard Logger metadata.

#### 14d. Trace Propagation Is Partially Implemented

Traces exist and are plumbed through part of the control pipeline via an optional `:trace` keyword option:

- `Scenes.apply_scene/2` (line 302): accepts trace, enriches with `trace_room_id`, `trace_scene_id`, `trace_target_occupied`, passes to `ControlApply.commit_and_enqueue/3`
- `Control.Apply.attach_trace/3` (lines 100-122): attaches trace fields to each action
- `Planner.plan_snapshot/3` (lines 20-193): emits `planner_input`, `planner_partition`, `planner_group_pick`, `planner_light_decision`, `planner_output` events — **but only if `trace_id` is present**
- `Executor.dispatch_tick/1` (lines 228-296): logs `dispatch_start`, `dispatch_end`, `convergence_ok`, `convergence_retry` — again **only if `action.trace_id` is set**
- Latency is measured via `enqueued_at_ms` and `dispatch_started_ms`

**Gaps:**
- No automatic trace ID generation — if a caller doesn't pass a trace, all downstream logging goes silent
- Subscription event → scene apply path is **not traced at all** (no trace injected at event boundaries)
- LiveView → domain calls don't propagate trace context
- No correlation between an SSE event arriving and the eventual light state transition

**Recommendation:** Generate a trace ID by default in `Scenes.apply_scene/2` when one isn't provided. This would make the existing trace infrastructure valuable without any new plumbing.

#### 14e. Retry Exhaustion Is Silent

`Executor.requeue_action/4` (`executor.ex` lines 393-406) drops actions from the queue silently when `action.attempts + 1 > state.max_retries`. **No log, no metric, no error.** Only the trace-gated `maybe_log_convergence_retry` path emits anything, and only if a trace_id was present.

This is the single most dangerous observability gap: failed commands during a hardware outage will be invisible in logs.

**Recommendation:** Always emit `Logger.warning` (ungated) on retry exhaustion with action details. This should happen before any metrics work.

#### 14f. Error Logging Quality Is Low

- Only 2 `rescue` blocks in the entire codebase (both in `import/pipeline.ex` lines 35-42) — they capture `Exception.message/1` only; stack traces are lost
- The single `Logger.error` call (`import/fetch/home_assistant/client.ex` line 54) has no structured context beyond an inspect of the payload
- Connection errors (Hue SSE, HA WebSocket, Caseta LEAP) log reasons but no retry count, no backoff state, no cumulative failure count

#### 14g. Telemetry Is Nearly Absent

Confirming Chunk 2: only 2 telemetry metrics exist (`phoenix.endpoint.stop.duration`, `phoenix.router_dispatch.stop.duration`), `periodic_measurements` returns empty, and there are **zero custom `:telemetry.execute` calls** anywhere in the codebase.

Blind spots:
- **Control pipeline**: no per-light latency, per-bridge throughput, or planner timing
- **Subscription lag**: no measurement of event-received-to-state-applied latency
- **Import pipeline**: no phase timing (fetch, normalize, materialize)
- **Error rates**: failed actions dropped silently, no counters

**Recommendation:** The executor and subscription connections are the highest-value places to add custom telemetry events. `:telemetry.span` wrapping the dispatch loop and event handler would give latency histograms without rewriting logging.

---

### 15. Dependencies & mix.exs

#### 15a. Dependency Hygiene Is Good

- **20 direct dependencies** — lean for a Phoenix LiveView app with 4 bridge adapters
- **No duplicate HTTP clients**: HTTPoison only (plus native `:ssl` for Caseta LEAP)
- **No duplicate JSON libraries**: Jason everywhere
- **Single MQTT client**: Tortoise
- **Single WebSocket client**: WebSockex
- **mix.lock is committed** and locks 58 total entries (direct + transitive)
- Elixir `~> 1.19` (modern)

Architecture of bridge integrations is clean:
- REST APIs (Hue, HA) → HTTPoison
- WebSocket subscriptions (HA) → WebSockex
- Protocol-level (Caseta LEAP) → native `:ssl`
- MQTT (Z2M, HA export) → Tortoise

#### 15b. Missing Dev Tooling

| Tool | Status |
|------|--------|
| `.formatter.exs` | Present |
| `.credo.exs` | Present (extensive config) |
| `dialyxir` | **Missing** |
| `ex_doc` | **Missing** |
| `excoveralls` | **Missing** |

**Recommendation:** Add `dialyxir` first (pairs with the @spec recommendation in 13a). Skip `ex_doc` unless you want to publish docs. `excoveralls` is optional — it's only valuable if you're going to act on coverage numbers.

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

#### 15c. Tortoise Maintenance Concern

`tortoise ~> 0.10` is locked at `0.10.0` — the library has a slow release cadence and Tortoise is effectively at its last major release. It still works, but for a critical path (Z2M subscription + HA export), this is a sustainability risk.

**Options:**
- Monitor the Tortoise GitHub repo and be prepared to switch
- Alternative: `emqtt` (from EMQX) is more actively maintained
- Don't migrate preemptively — this is only worth acting on if you hit a bug

#### 15d. Phoenix LiveView Version

- Phoenix 1.7.21, LiveView 0.20.17
- LiveView 1.0 has been released as of 2025 — upgrading is eventually worth considering, but `0.20.x` is still stable and compatible
- This is a future project, not a current issue

#### 15e. HTTPoison → hackney Chain

HTTPoison pulls in hackney, which pulls in an older SSL stack (`certifi`, `ssl_verify_fun`). This is not a security issue as long as system-level certificate management is in place (which the Docker setup handles), but it's the one dependency chain worth watching.

An alternative would be `Req` (which uses `Finch` → `Mint` → native `:ssl`), but migrating the 8 files currently using HTTPoison is not a priority — the current stack works.

---

## Audit Complete

All three planned chunks are done. 15 finding sections covering:

**Chunk 1** (1-7): duplication patterns, error handling, complexity hotspots, hard-coded values, naming, architecture, positive patterns
**Chunk 2** (8-12): schemas & queries, mix tasks, application startup & infrastructure, test suite, config management
**Chunk 3** (13-15): type safety, observability, dependencies

### Recommended Next Steps

These are the highest-leverage starting points across all three chunks, in rough order:

1. **Log retry exhaustion in Executor** (14e) — small change, fixes a real operational blind spot
2. **Replace IO.puts with Logger in fetch modules** (14b) — trivial cleanup
3. **Extract string/atom dual-key helper** (1a) — 100+ lines eliminated across 6 modules
4. **Define a `LightState` struct** (13b) — unlocks type safety work and fixes 1a at its root
5. **Add `dialyxir` + @specs on the critical 5 modules** (13a, 15b) — state.ex, desired_state.ex, light_state_semantics.ex, state_parser.ex, scenes.ex
6. **Generate trace IDs by default in `apply_scene`** (14d) — activates already-built trace infrastructure
7. **Consolidate event stream managers** (1c) — ~250 lines eliminated, low risk
8. **Fix the N+1 in `picos/targets.ex`** (8b) — performance win

The architectural direction laid out in `refactoring.md` and `architecture-reset.md` remains the governing priority; this audit is meant to surface specific code-level wins that can be taken on opportunistically as those larger refactors happen.
