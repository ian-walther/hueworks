# Refactoring Targets

## Goal
Improve maintainability and reliability without giving back the product stability we have now.

The best refactors right now are the ones that:
- reduce the chance of subtle state drift
- shrink the biggest conceptual hotspots
- preserve behavior under the existing test suite
- make the codebase easier for humans to read, own, and extend without needing hidden context

Planning docs should stay explicit enough that a future pass by a different agent or by a human maintainer can quickly recover the intended direction and tradeoffs.

## Architectural Constraint
When this document and `/Users/ianwalther/code/hueworks/planning/architecture-reset.md` pull in different directions, the architecture-reset doc wins.

In particular:
- upstream layers should stay focused on deciding desired state
- planner/executor should own downstream operational behavior
- refactors should simplify toward that boundary, not away from it

## Current High-Value Hotspots
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/runtime.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/config.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex`

## Priority Order

### 1) Normalize once at the boundary and keep downstream code atom-keyed
The preferred direction is to normalize external payloads, DB-backed config maps, and form params at the boundary where they enter the domain, then make downstream code deterministic and atom-keyed.

Preferred direction:
- normalize payloads when they are first accepted from events, files, MQTT, or imports
- normalize DB-backed config maps when they enter domain code
- normalize LiveView/form params before they are handed to domain helpers
- remove downstream mixed string/atom lookups as each boundary becomes canonical
- prefer deleting dual-key logic over centralizing more `atom-or-string` helper access
- when a shape is stable and bounded, prefer a typed boundary module or embedded schema over more ad hoc map helpers

Design rule:
- use maps for foreign input
- use structs for internal meaning

Applied more concretely:
- raw maps are acceptable at integration, file, DB JSON, and browser-param boundaries
- once data has internal meaning, prefer a struct or embedded schema over passing loose maps deeper through the app
- if a map keeps acquiring validation, normalization, or shape assumptions, it is a good candidate to become a struct

Method:
- identify one loose map surface with repeated dual-key handling
- define the canonical internal shape first
- add one boundary module that owns load, cast, validation, and dump behavior
- keep browser and persistence compatibility logic at that boundary only
- switch downstream consumers to the canonical shape
- update tests to assert deterministic internal types rather than raw stringly payload leakage
- only then decide whether to tighten the persisted shape further

Heuristics for good candidates:
- repeated `Map.get(map, :key) || Map.get(map, "key")` patterns
- repeated coercion of the same field family
- maps with a bounded vocabulary that already behave like product surfaces
- validation logic that currently lives outside the shape it validates
- modules that would get smaller if they could assume typed fields instead of loose maps

Expected payoff:
- less duplicated key-handling logic
- fewer hidden differences between payload sources
- cleaner domain code with clearer expectations about input shape

### Near-Term Embedded Schema Direction
`LightState.config` now uses a parent-level embed on the existing `light_states.config` column. The next phase is to shrink the remaining compatibility glue without giving back rollback safety.

Preferred direction:
- keep the existing `light_states.config` column while the new parent-level embed soaks
- keep manual and circadian config struct-first in parent-schema usage
- let Ecto own as much of the cast and validation flow as is practical
- keep sparse persisted-shape dumping and alias compatibility only at the boundary while old records and rollback compatibility still matter
- reduce downstream uses of `LightState.persisted_config/1` over time in favor of struct-first consumers
- prefer dedicated form/view helpers over feeding dumped persisted maps back into editor state
- decide later whether the helper boundary modules should remain thin dump/load adapters or be folded further into the parent embed
- avoid introducing a DB migration unless there is a concrete payoff beyond code clarity

Guardrails:
- do not change persisted shape casually just because the internal shape is cleaner
- prefer rollout steps that are reversible by code deploy alone
- keep tests focused on both typed internal shape and persisted compatibility shape until the compatibility layer is intentionally removed

Good future candidates for this pattern:

Poor candidates for this pattern:
- open-ended import blobs such as raw or normalized bridge payload snapshots
- metadata maps whose job is to preserve external structure rather than enforce internal shape

### Embedded Schema Rollout
The preferred rollout is incremental and compatibility-first. The goal is to replace bounded persisted map surfaces with native Ecto embed usage where that buys determinism, while keeping rollback safety and avoiding speculative schema churn.

#### Rollout Rules
- prefer parent-level `embeds_one` or `embeds_many` on the existing column before considering any DB migration
- keep the existing persisted column name and storage shape while the new embed soaks
- keep load, cast, validation, and dump behavior at the embed boundary instead of redistributing compatibility helpers downstream
- switch read paths to struct-first access before tightening any persisted shape further
- keep browser/form boundaries explicit; do not feed dumped persisted maps back inward unless that code is truly at a persistence boundary
- treat rollback-by-code-deploy as the default safety bar for each step
- if an embed migration exposes a concrete legacy persisted shape bug in bounded production data, prefer a one-time backfill migration over carrying dual-shape runtime support indefinitely

#### Phase 0: Consolidate The Current LightState Embed
This phase is already underway and should continue until `LightState.persisted_config/1` is narrow and intentional.

Goals:
- keep `LightState.config` as the reference example for future embed migrations
- keep reducing downstream compatibility-map access in UI and scene code
- keep tests asserting both typed internal shape and compatible persisted dump behavior

Exit criteria:
- most read paths use `state.config` or typed helper accessors
- `persisted_config/1` is primarily used at true persistence or compatibility boundaries

#### Next Native-Embed Candidates: Evaluate Mixed Metadata Surfaces Carefully
Some metadata maps have enough structure to be candidates later, but they should not be treated like the phase-1 conversions.

Most plausible later candidate:
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/pico_device.ex`
  - `metadata` currently carries several bounded meanings:
    - `room_override`
    - `detected_room_id`
    - `control_groups`
    - preset-related fields
  - if this moves, it should likely become:
    - a parent-level metadata embed
    - plus an embedded control-group child shape

Guardrails for this phase:
- do not force unrelated metadata concerns into a fake single schema just to eliminate maps
- only convert the metadata surface if the resulting embed shape is still easier to understand than the current map
- prefer proving the read path and helper API first before replacing all writes

Possible but lower-confidence candidates:
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/scene.ex` metadata
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/room.ex` metadata

These should only move if a stable bounded vocabulary actually emerges. Right now they are not strong enough candidates to prioritize.

#### Later: Decide Whether Compatibility Dumping Should Stay Permanent
Once parent-level embed usage is stable for a surface, decide deliberately whether to keep or retire its compatibility dump behavior.

Questions to answer per surface:
- does old persisted shape still need to be read in prod?
- is rollback safety still relying on legacy dump compatibility?
- are there tests or fixtures still depending on the old dumped shape?
- is there a real product payoff to canonicalizing the stored JSON, or only a cleanliness payoff?

Preferred direction:
- keep compatibility dumping longer than feels elegant
- only remove it after the read paths have soaked and the operational need is low
- avoid one-time backfills unless they produce more than just cosmetic cleanup

#### Surfaces To Leave As Maps
These should stay map-backed unless their role in the system changes materially.

Keep as maps:
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/bridge_import.ex`
  - `raw_blob`
  - `normalized_blob`
  - `review_blob`
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/light.ex`
  - `normalized_json`
  - `metadata`
- `/Users/ianwalther/code/hueworks/lib/hueworks/schemas/group.ex`
  - `normalized_json`
  - `metadata`

Why:
- these fields preserve external or import-oriented structure
- they are not stable internal vocabularies
- forcing them into embeds would mostly relocate complexity instead of reducing it

#### AppSettings Note
`AppSetting` is not currently a strong native-embed target because the persisted model is already flat columns, not a bounded JSON blob.

Preferred direction:
- keep using typed boundary modules like:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/app_settings/solar_config.ex`
  - `/Users/ianwalther/code/hueworks/lib/hueworks/app_settings/ha_export_config.ex`
- only consider embedded schemas there as form or boundary engines if the setting families grow more complex
- do not introduce JSON columns just to make AppSettings “more embedded-schema-like”

### 2) Finish thinning `Hueworks.HomeAssistant.Export`
Keep the export runtime shell small and explicit.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/config.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/lifecycle.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router/entity_commands.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router/scene_commands.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/runtime.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/sync.ex`

Preferred direction:
- keep `export.ex` focused on GenServer state transitions and public entrypoints
- keep runtime config as a typed internal struct instead of a loose map
- keep connection lifecycle, config transition behavior, and sync dispatch out of the GenServer shell
- keep scene/select command handling separate from light/group command handling
- move any remaining process-local policy/helpers out of the runtime shell
- decide whether `runtime.ex` should stay as a separate helper or be folded into clearer, smaller responsibilities
- keep transport, publishing, routing, and selection logic outside the runtime shell

Expected payoff:
- easier to reason about HA MQTT behavior without paging through multiple concerns at once
- safer iteration on export features and cleanup behavior
- simpler manual debugging of runtime state transitions

### 3) Finish splitting `Hueworks.Picos`
Keep `Picos` as a small facade with clear helper boundaries.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/bindings.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/clone.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/config.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/actions.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/control_groups.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/targets.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/sync.ex`

Preferred direction:
- keep `picos.ex` as a small public facade instead of a secondary implementation module
- continue reducing cross-module leakage of helper details
- keep control-group normalization and persistence behavior out of both the facade and higher-level config workflow
- keep button binding assignment, preset wiring, and cloned binding config rewriting together instead of scattering them across config helpers
- keep full device-config copy workflow in its own helper instead of leaving the higher-level config module as a hidden implementation hotspot
- keep sync, config, targets, and runtime action logic conceptually separate
- consider whether some naming or public entrypoints should be made more explicit before future Pico work lands

Expected payoff:
- easier changes to Pico behavior without risking sync code
- smaller review surface for button-binding changes
- cleaner handoff when doing manual refactors later

### 4) Tighten the `Scenes` and editor boundary
Keep editor-specific translation pressure out of scene persistence and orchestration.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/active.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/components.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/light_states.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/persistence.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component/state.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live/form_state.ex`

Preferred direction:
- keep `Scenes` focused on orchestration and persistence
- keep bounded scene helper modules responsible for active-scene refresh/recompute, replacement, validation, persistence side effects, and light-state CRUD
- keep bounded editor helper modules responsible for component mutation, normalization, and form-state shaping
- keep editor token translation and UI-only concerns at the LiveView boundary
- continue moving toward cleaner already-resolved inputs before persistence

Expected payoff:
- scene editing becomes easier to evolve without making the core scene context more magical
- fewer editor-shaped conditionals in persistence code

### 5) Delay deeper control-path extraction until after upstream cleanup
The remaining control-path hotspots are some of the riskiest modules in the app, and they should not be the first refactor target while the system is still being observed in real-world usage.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`

Preferred direction:
- defer major structural work here until after upstream state and export cleanup stabilizes
- when the control path is touched, prefer behavior-preserving extraction first
- preserve public entrypoints while moving logic lower into purer helpers over time

Why this is lower than it sounds:
- the executor and surrounding control path are reliability-critical
- several oddities may still be upstream state issues rather than planner issues
- upstream cleanup will make any later control-path work safer and clearer

#### Safe carve-outs that don't require structural changes

These are small, targeted fixes that improve observability without touching executor structure:

**Retry exhaustion is silent:** `requeue_action/4` silently drops actions when `action.attempts + 1 > state.max_retries`. No log, no metric. During a hardware outage, failed commands are invisible. Fix: add a `Logger.warning` with action details on retry exhaustion. One-line change, no structural risk.

**Trace IDs should be generated by default:** The trace infrastructure (planner events, dispatch logging, latency measurement) already exists but goes silent when callers don't pass a `:trace` option. `Scenes.apply_scene/2` should generate a trace_id by default when one isn't provided. This activates already-built plumbing without adding new plumbing. The subscription event → scene apply path is also untraced — no trace is injected at event stream boundaries.

### 6) Keep LiveViews thin and move UI-specific logic outward
Keep LiveViews focused on UI concerns rather than domain orchestration.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live/actions.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component/state.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live/form_state.ex`

Preferred direction:
- keep LiveViews focused on:
  - event wiring
  - assign updates
  - composition of helpers/components
- keep manual-control fetch/parse/dispatch branches out of the LightsLive shell
- keep domain orchestration and persistence translation out of the LiveView layer

### 7) Extract shared UI components only after the boundaries are cleaner
Shared UI extraction should wait until the surrounding responsibilities are less tangled.

Preferred direction:
- extract reusable light-state editing UI only after the editor/domain boundary is clearer
- avoid baking current page-specific assumptions into a shared component API

### 8) Clean up broad `rescue` usage and IO.puts in import/fetch paths
This matters, but it is not where the best stability payoff is right now.

Preferred direction:
- expected failures should be returned explicitly as `{:error, reason}`
- true bugs should remain visible rather than being flattened into generic error strings
- replace `IO.puts` with `Logger` in production code — 12 instances in fetch modules (`import/fetch/caseta.ex`, `import/fetch/home_assistant.ex`, `import/fetch/hue.ex`, `hardware_smoke.ex`) bypass the log formatter and log level filtering under Docker
- standardize on `Logger.warning` (remove deprecated `Logger.warn` where it still exists)

### 9) Revisit high-complexity product behaviors only after the code is easier to observe
There are a few features whose complexity cost may eventually outweigh their value, but they should be revisited deliberately, not mixed into structural cleanup.

Candidate areas:
- extended low-end kelvin support
- manual-on/default-off semantics inside active scenes
- timing-based scene-clear protection
- manual power-latch survival across scene reapply

### 10) Consolidate event stream managers
The four event stream GenServers are structurally identical (~250 lines total duplication).

Files:
- `/Users/ianwalther/code/hueworks_app/subscription/hue_event_stream.ex`
- `/Users/ianwalther/code/hueworks_app/subscription/home_assistant_event_stream.ex`
- `/Users/ianwalther/code/hueworks_app/subscription/caseta_event_stream.ex`
- `/Users/ianwalther/code/hueworks_app/subscription/z2m_event_stream.ex`

They share `@restart_delay_ms`, `@retry_delay_ms`, identical `start_link/init/handle_info` implementations, and the same `maybe_start_connections` pattern with only the `:type` filter varying.

Preferred direction:
- a single parametrized `GenericEventStream` module with bridge type as init arg
- low risk since the structure is already proven identical
- connection-specific logic stays in the per-bridge `connection.ex` modules

### 11) Deduplicate fetch modules
`fetch/0` and `fetch_for_bridge/1` in each fetch module (Hue, HA, Caseta) are 80-90% identical — they differ only in the bridge type filter and credential extraction.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/import/fetch/hue.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/import/fetch/home_assistant.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/import/fetch/caseta.ex`

Preferred direction:
- extract shared `fetch_all(type, &fetch_fn/1)` and `fetch_one(bridge, &fetch_fn/1)` wrappers
- `invalid_credential?/1` is repeated verbatim in 4+ files — extract to a shared location

### 12) Fix N+1 query in picos/targets.ex
`expand_room_targets/3` does one query per `group_id` plus one query per group for member lights — O(n) queries inside a flat_map.

File:
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/targets.ex` (lines 22-38)

Also: `scene_name_for_target/2` loads ALL scenes for a room via `Scenes.list_scenes_for_room/1` then finds one by ID in memory. Should query the specific scene directly.

Preferred direction:
- batch-load all group room_ids and member lights in a single query
- query specific scene by ID instead of loading all and filtering

### 13) Add dialyxir and begin @spec coverage
`dialyxir` is not in `mix.exs` — no static type checking is configured. Only 3 `@spec` declarations exist across 153 modules.

Preferred direction:
- add `{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}` to mix.exs
- start with @specs on the modules that matter most for correctness: `state.ex`, `desired_state.ex`, `light_state_semantics.ex`, `state_parser.ex`, `scenes.ex`
- pairs naturally with the struct/embedded schema work — specs become more useful once the data shapes are well-defined
- do not try to spec everything at once; grow coverage incrementally as modules are touched

## Architectural Constraint: No Authentication

All routes are publicly accessible — no authentication or authorization layer exists. This is intentional (local-network appliance) but should be documented as a constraint. If the app is ever exposed beyond a trusted network, an auth pipeline would be needed. Not an action item unless the deployment model changes.

## Enduring Simplification Targets

### 1) Keep light-state semantics centralized
The code should continue to avoid reintroducing duplicated logic for:
- desired-state clamping for per-light kelvin limits
- desired-vs-physical equality checks
- brightness tolerance
- kelvin equivalence and quantization behavior

Guidance:
- keep comparison and normalization rules centralized instead of letting helpers regrow in multiple modules
- once a boundary is normalized, remove downstream key-alias handling instead of preserving it indefinitely

### 2) Keep scene intent separate from scene orchestration
`Scenes.apply_scene/2` should stay mostly orchestration.

Guidance:
- keep desired-state construction and scene-policy logic out of the outer orchestration path
- if `Scenes.apply_scene/2` starts growing again, prefer another layer split instead of adding conditionals back in

### 3) Keep manual power-latch semantics explicit
Keep manual power-latch behavior from becoming another fuzzy ownership layer.

Guidance:
- prefer explicit names like `preserve_power_latches` over overloaded lifecycle flags
- keep latch semantics narrow and traceable
- do not let new hidden ownership rules accumulate in scene lifecycle code

### 4) Keep source-specific parsing and payload quirks behind shared lower-level helpers
The app will always have Hue, Z2M, HA, and bridge-specific quirks.

Guidance:
- let source-specific modules own wire-format quirks
- let shared lower-level helpers own the final normalized app-state shape
- avoid re-encoding the same rules separately in bootstrap, event stream, export, and display layers

### 5) Use logger metadata only as a supplement
`Logger.metadata/1` may reduce some same-process boilerplate, but it is not a replacement for explicit traces that cross queue and executor boundaries.

## UI Pitfalls

### LiveView dynamic form controls need stable structure
The failure pattern:
- a `phx-change` form contains dynamic selects/inputs that appear or disappear
- the nodes do not have stable ids or a stable placeholder container
- morphdom/browser reconciliation goes bad
- duplicated or corrupted dropdowns appear

Guidance:
- prefer stable wrapper containers with fixed ids
- prefer persistent controls that become disabled or change options over controls that are inserted/removed entirely
- give dynamic forms/selects explicit ids
- avoid nested forms
- keep copied LiveView form patterns simple rather than clever

## Lower-Value Cleanup To Defer
These are fine later, but they should not displace the higher-value structural work above.

- alias ordering cleanup
- missing moduledocs on straightforward schema modules
- small `Enum.map |> Enum.join` cleanup
- minor `with` versus `case` rewrites
- similar Credo-only style churn that does not materially improve the app's reliability or boundaries

## Recommended Sequence

### Phase 1
- normalize one boundary at a time and remove downstream mixed-key handling as each boundary becomes canonical
- finish thinning `Hueworks.HomeAssistant.Export`
- keep the runtime shell focused on GenServer transitions only
- fix executor retry exhaustion logging and default trace ID generation (safe carve-outs from #5)

### Phase 2
- finish splitting `Hueworks.Picos`
- keep sync, config, targets, and runtime action code easier to reason about independently
- fix the N+1 query in `picos/targets.ex` while the module is being touched

### Phase 3
- keep tightening the `Scenes` and editor boundary
- move more editor-only translation to the LiveView layer

### Phase 4
- revisit planner/executor extraction only after the upstream layers are cleaner
- focus on behavior-preserving extraction and observability, not semantics changes

### Phase 5
- continue thinning LiveViews and extracting shared UI only where the boundaries are already stable

### Phase 6
- clean up broad `rescue` usage and IO.puts in fetch/import paths
- consolidate event stream managers and fetch module duplication

### Phase 7
- add dialyxir and begin @spec coverage on critical modules

### Phase 8
- re-evaluate whether the highest-complexity product behaviors still justify their implementation cost

## Refactor Guardrails
- use the existing test suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- when a refactor changes semantics, make that explicit and deliberate instead of burying it in cleanup work
