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

### 2) Keep LiveViews thin and move UI-specific logic outward
Keep LiveViews focused on UI concerns rather than domain orchestration.

Preferred direction:
- keep LiveViews focused on:
  - event wiring
  - assign updates
  - composition of helpers/components
- keep domain orchestration and persistence translation out of the LiveView layer

### 3) Extract shared UI components only after the boundaries are cleaner
Shared UI extraction should wait until the surrounding responsibilities are less tangled.

Preferred direction:
- extract reusable light-state editing UI only after the editor/domain boundary is clearer
- avoid baking current page-specific assumptions into a shared component API

### 4) Clean up broad `rescue` usage in import paths
This matters, but it is not where the best stability payoff is right now.

Preferred direction:
- expected failures should be returned explicitly as `{:error, reason}`
- true bugs should remain visible rather than being flattened into generic error strings
- keep narrowing broad rescue behavior in import code until error handling is explicit and local

### 5) Revisit high-complexity product behaviors only after the code is easier to observe
There are a few features whose complexity cost may eventually outweigh their value, but they should be revisited deliberately, not mixed into structural cleanup.

Candidate areas:
- extended low-end kelvin support
- manual-on/default-off semantics inside active scenes
- manual control reliability when no scene is active
  - observed behavior: direct manual control commands seem to fail intermittently when the room has no active scene
  - keep this visible as a product/reliability investigation so it does not get lost before feature work resumes
- timing-based scene-clear protection
- manual power-latch survival across scene reapply

### 6) Work down the Dialyzer baseline and expand @spec coverage
`dialyxir` is available now, but the codebase still has a large baseline of Dialyzer findings and only a small amount of useful `@spec` coverage.

Preferred direction:
- keep working down the current Dialyzer warning baseline in small, correctness-focused batches rather than trying to “make Dialyzer green” all at once
- continue adding @specs on the modules that matter most for correctness: `state.ex`, `desired_state.ex`, `light_state_semantics.ex`, `state_parser.ex`, `scenes.ex`
- pairs naturally with the struct/embedded schema work — specs become more useful once the data shapes are well-defined
- do not try to spec everything at once; grow coverage incrementally as modules are touched

### 7) Run a deliberate test coverage phase before new features
The next phase should improve confidence, especially after the large refactor stretch. The goal is not just "more tests" but better protection for user-visible behavior, failure paths, and correctness-critical internals.

Preferred direction:
- prioritize direct tests for route-backed CRUD behavior before adding more feature surface
- add failure-path coverage anywhere a UI or domain operation can silently no-op, partially apply, or return a generic error
- prefer focused tests for specific helpers and context modules when behavior is currently only covered indirectly through larger integration tests
- keep using bug-driven red-green tests for regressions, then fill the remaining asymmetries proactively

Suggested sequence:
- finish auditing route-backed CRUD symmetry so create/read/update/delete paths are directly exercised where the UI exposes them
- add more direct tests for context/query modules that are currently mostly protected indirectly
- add failure-path tests for import, bridge setup, external-scene mapping, and other admin/config flows
- add property-style tests for calculation-heavy modules like `Circadian`, `Color`, and `Kelvin`
- then keep expanding `@spec` coverage and reducing the Dialyzer baseline on correctness-critical modules

High-value coverage targets:
- destructive UI actions
  - delete, clear, remove, clone-copy, and reimport paths
- edit flows with existing persisted records
  - especially embed-backed and typed-boundary forms
- context modules with meaningful query or lifecycle behavior
  - `Bridges`, `Rooms`, `Groups`, `Lights`
- failure scenarios
  - validation errors
  - missing records
  - stale UI targets
  - import/setup failures
  - queue/retry/recovery edges

Guardrails:
- prefer direct tests over assuming one large integration test covers every branch of a UI surface
- keep large integration tests where state interaction matters, but add smaller tests when they make regressions easier to localize
- when a new coverage pass exposes a real bug, fix the bug instead of weakening the test
- do not chase coverage numbers for their own sake; prioritize correctness and regression resistance

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

### Phase 2
- continue thinning LiveViews and extracting shared UI only where the boundaries are already stable

### Phase 3
- clean up broad `rescue` usage in import paths

### Phase 4
- run the deliberate test coverage phase across remaining CRUD, failure-path, and correctness-critical modules

### Phase 5
- add dialyxir and begin @spec coverage on critical modules

### Phase 6
- re-evaluate whether the highest-complexity product behaviors still justify their implementation cost

## Refactor Guardrails
- use the existing test suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- when a refactor changes semantics, make that explicit and deliberate instead of burying it in cleanup work
