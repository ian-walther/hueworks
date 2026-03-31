# Refactoring Audit

## Goal
Reduce complexity in the circadian, scene, and `/lights` control paths without changing product behavior accidentally.

This document is meant to do two things:
- identify the highest-value simplification opportunities
- call out "small feature, large complexity cost" areas so we can decide whether they are worth keeping as-is

## Why Now
Recent work has materially improved behavior and test coverage, but it also increased the amount of logic spread across:
- scene application
- active-scene retention
- desired-vs-physical comparison
- `/lights` manual control behavior
- source-specific kelvin handling

The growing integration suite gives us enough safety to start simplifying these areas intentionally.

## Churn Hotspots
- `lib/hueworks/scenes.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks_app/control/desired_state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks/kelvin.ex`
- `lib/hueworks_web/live/lights_live.ex`

## Primary Findings

### 1) Control semantics were historically duplicated across modules
Before the recent refactor work, the same concepts existed in multiple places:
- key alias handling for `brightness` / `kelvin` / `temperature`
- desired-state clamping for per-light kelvin limits
- desired-vs-physical equality checks
- brightness tolerance handling
- kelvin equivalence / quantization handling

That duplication lived across:
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_app/control/desired_state.ex`

This has now been addressed by:
- `lib/hueworks/control/light_state_semantics.ex`

Remaining guidance:
- keep new light-state rules centralized there instead of reintroducing comparison helpers elsewhere

### 2) `Scenes.apply_scene/2` was carrying too many responsibilities
Historically, `lib/hueworks/scenes.ex` handled:
- loads scene/component data
- computes desired state from light states
- applies default power policy
- preserves manual power overrides
- applies targeted power overrides
- commits desired state
- builds planner input
- logs tracing
- enqueues executor actions

This has been partially addressed by:
- `lib/hueworks/scenes/intent.ex`

Remaining guidance:
- keep scene intent/policy logic out of the outer orchestration path
- if `Scenes.apply_scene/2` starts growing again, prefer another layer split instead of adding more conditionals back into it

### 3) `/lights` accumulated too much domain orchestration in the LiveView
Historically, `lib/hueworks_web/live/lights_live.ex` mixed:
- UI event handling
- manual action orchestration
- active-scene reapply decisions
- desired-state writes
- executor dispatch
- UI-only display-state shaping for extended kelvin behavior

This has been partially addressed by:
- `lib/hueworks/lights/manual_control.ex`
- `lib/hueworks_web/live/lights_live/display_state.ex`
- `lib/hueworks_web/live/lights_live/editor.ex`
- `lib/hueworks_web/live/lights_live/entities.ex`
- `lib/hueworks_web/live/lights_live/loader.ex`

Remaining guidance:
- continue moving LiveView-owned domain behavior outward until the file is mostly event wiring and assign updates

### 4) `brightness_override` now means more than its name suggests
The code still uses the name `brightness_override`, but the behavior now includes more than "suppress brightness adaptation."

Current impact includes:
- suppressing brightness adaptation
- preserving manual power latches during circadian reapply
- interacting with default-off lights that are manually turned on

Risk:
- misleading naming increases mental overhead
- future changes are easier to get wrong because the name no longer describes the full behavior

Recommendation:
- rename the concept in code once the behavior settles
- or split the concept if it is actually representing two independent behaviors

## Completed Refactors

### 1) Shared light-state semantics extracted
Done on the `refactoring` branch.

New module:
- `lib/hueworks/control/light_state_semantics.ex`

This pulled shared comparison and normalization logic out of:
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_app/control/desired_state.ex`

Result:
- planner, reconcile, and scene-clear paths now use the same light-state semantics
- duplicated comparison logic has been reduced substantially

### 2) Scene intent split from scene orchestration
Done on the `refactoring` branch.

New module:
- `lib/hueworks/scenes/intent.ex`

Result:
- desired-state construction, default power behavior, and manual power preservation moved out of the main scene orchestration flow
- `Scenes.apply_scene/2` is closer to orchestration instead of policy accumulation

### 3) Manual-control and display-state helpers extracted from `LightsLive`
Done on the `refactoring` branch.

New modules:
- `lib/hueworks/lights/manual_control.ex`
- `lib/hueworks_web/live/lights_live/display_state.ex`

Result:
- manual desired-state writes and executor dispatch no longer live directly in the LiveView
- UI-only merge/presentation logic for control-state updates is isolated from manual control behavior

### 4) Edit-modal logic extracted from `LightsLive`
Done on the `refactoring` branch.

New module:
- `lib/hueworks_web/live/lights_live/editor.ex`

Result:
- edit-modal defaults, opening behavior, field normalization, and save behavior are now grouped together
- the LiveView no longer owns the edit form rules directly

### 5) Group membership and entity loading moved out of `LightsLive`
Done on the `refactoring` branch.

New and updated modules:
- `lib/hueworks/groups.ex`
- `lib/hueworks_web/live/lights_live/entities.ex`

Result:
- the LiveView no longer knows how group membership is stored
- light/group lookup and id parsing now live behind a shared helper used by both event handlers and editor flows

### 6) Page bootstrap and reload snapshot loading extracted from `LightsLive`
Done on the `refactoring` branch.

New module:
- `lib/hueworks_web/live/lights_live/loader.ex`

Result:
- mount and refresh now share one page-loading path
- the LiveView no longer rebuilds rooms/groups/lights/state snapshots inline in multiple places

## Remaining High-Leverage Refactor Targets

### 1) Keep collapsing the remaining LiveView-specific load/save wiring
Priority: high

Current holdouts:
- `save_edit/2`
- `reload_entities/1`
- the remaining event-handler-level orchestration in `lib/hueworks_web/live/lights_live.ex`

Why:
- the editor, entities, and loader helpers now own most of the supporting logic already
- continuing this extraction would let the LiveView stop coordinating as much page-bootstrap and persistence wiring directly
- it would make the `LightsLive` file even closer to pure event wiring

### 2) Simplify refresh suppression
Priority: medium

Current behavior works, but scene-clear suppression is currently a hidden time-window in control state.

Longer-term alternatives:
- source-tagged writes everywhere
- refresh token / scoped suppression context
- explicit "ignore clear for this resync batch" metadata

Why:
- hidden global timing state is effective but harder to reason about than explicit causality

### 3) Split planner loading/orchestration from a pure planning core
Priority: high

Current hotspot:
- `lib/hueworks/control/planner.ex`

Current shape:
- `plan_room/3` performs database reads
- then immediately performs the real planning logic

Why this matters:
- the planner is one of the most complex and behavior-critical modules in the app
- mixing data loading with the planning algorithm makes it harder to test planner logic in isolation
- it also makes future planner refactors feel riskier than they need to be

Preferred direction:
- keep `plan_room/3` as a thin wrapper that loads a room snapshot
- introduce a pure planner core that accepts:
  - room light snapshot
  - group membership snapshot
  - desired-state snapshot
  - physical-state snapshot
  - diff
  - trace/options

Important nuance:
- do not force purity all the way out to every current caller immediately
- preserve the existing public entrypoint first, then migrate more tests toward the pure core over time

### 4) Extract light-state editing into a shared LiveComponent
Priority: medium-high

This is partly refactoring and partly product improvement.

Goal:
- move the light-state edit UI and form behavior into a reusable LiveComponent
- allow that component to be mounted:
  - inside scene editing flows
  - on its own from other locations in the app

Why this matters:
- the same light-state editing concepts are likely to appear in more than one place
- keeping those form rules in one component should reduce duplication and keep scene editing from owning the only implementation
- it also gives us a cleaner seam for evolving light-state editing without coupling every change to scene-edit pages

Likely scope:
- shared form rendering for manual and circadian light states
- shared validation and normalization rules
- clean API for parent LiveViews to either:
  - bind directly to in-memory scene-editor state
  - or persist/update from another screen

Design concern to keep in mind:
- avoid baking scene-editor assumptions too deeply into the component API
- the component should be reusable without carrying scene-specific naming or persistence requirements everywhere

### 5) Clean up broad rescue usage in the import pipeline
Priority: medium-high

Current hotspot:
- `lib/hueworks/import/pipeline.ex`

Current shape:
- `create_import/1` and `fetch_raw/1` use broad `rescue` blocks and turn exceptions into `{:error, message}`

Why this matters:
- expected bridge/API failures and unexpected programmer bugs get flattened into the same error path
- broad `rescue` hides stacktraces and can make debugging much slower
- this weakens OTP-style crash visibility in a place where clear failure boundaries would be healthier

Preferred direction:
- let bridge/import fetchers return tagged `{:ok, value}` / `{:error, reason}` results for expected failures
- reserve actual exceptions for true bugs
- keep unexpected exceptions visible instead of swallowing them into generic strings

### 6) Move scene-component persistence and UI-specific light-state tokens to a cleaner boundary
Priority: medium

Current hotspot:
- `lib/hueworks/scenes.ex`
- specifically `replace_scene_components/2`

Current shape:
- the persistence layer still knows about editor-originated tokens like `"new"`, `"new_manual"`, and `"new_circadian"`
- scene component persistence still loops and inserts `SceneComponentLight` rows one at a time

Why this matters:
- the `"new*"` token handling is UI/editor-shaped behavior leaking into a persistence boundary
- the persistence path is doing more editor-translation work than it should

Preferred direction:
- move scene-editor-only tokens and editor-state translation closer to the LiveView/component boundary
- let `replace_scene_components/2` work with cleaner, already-resolved input where possible
- consider batched inserts later only if the persistence path actually shows up as a practical bottleneck

### 7) Bridge dispatch abstraction is a low-priority cleanup, not an urgent refactor
Priority: low

Current hotspots:
- `lib/hueworks/control/light.ex`
- `lib/hueworks/control/group.ex`

Observation:
- the repeated source dispatch logic is real
- but the current bridge count is still small, and a behaviour/protocol layer would mainly reduce repetition, not eliminate much core complexity

Guidance:
- prefer simple module-map dispatch if this area starts growing
- avoid introducing abstraction here unless bridge count or bridge-specific branching materially expands

### 8) Logger metadata may be a useful supplement, but not a full replacement for explicit traces
Priority: low

Current hotspots:
- `lib/hueworks/scenes.ex`
- `lib/hueworks/control/planner.ex`

Observation:
- `Logger.metadata/1` could reduce some same-process log boilerplate
- but explicit trace information is also being attached to planned actions before they cross into the executor path

Guidance:
- metadata is worth considering as a supplement for local logging
- do not treat it as a drop-in replacement for explicit trace propagation across queue/executor boundaries

## Features With Outsized Complexity Cost

These are not necessarily bad features. They are just the areas where a seemingly small product requirement has pushed complexity into several layers of the stack.

### 1) Extended low-end kelvin support
Impacted areas:
- state parsing
- payload generation
- kelvin mapping
- group/member aggregation
- UI display preservation logic

Question:
- is the exact current UX around sub-`2700K` preservation worth the ongoing implementation complexity?

### 2) Default-off lights that can be manually turned on without deactivating the scene
Impacted areas:
- `ActiveScenes`
- `Scenes`
- `LightsLive`
- desired-state behavior

Question:
- does the current behavior deliver enough user value to justify the amount of branching it introduces?

### 3) Reload should never clear scenes
Impacted areas:
- bootstrap/resync paths
- scene-clear suppression
- LiveView refresh behavior
- integration tests

Question:
- should this remain an implicit timing-based protection, or should the system model refresh causality more explicitly?

### 4) Manual power latches surviving circadian reapply
Impacted areas:
- active-scene state
- scene reapply behavior
- default power policy semantics

Question:
- should this remain bundled with `brightness_override`, or should it become its own explicit concept?

## Recommended Sequence

### Phase 1
- keep collapsing the remaining LiveView-specific load/save wiring
- aim to leave `LightsLive` as event wiring plus assign updates

### Phase 2
- split planner loading/orchestration from a pure planning core

### Phase 3
- extract light-state editing into a shared LiveComponent that can work both inside scene editing and standalone
- move scene-editor-specific light-state tokens and component persistence translation to a cleaner boundary

### Phase 4
- clean up broad `rescue` usage in the import pipeline

### Phase 5
- revisit refresh suppression and decide whether explicit refresh causality is worth modeling

### Phase 6
- evaluate whether the highest-cost features should be simplified or re-scoped

## Refactor Guardrails
- use the existing integration suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- do not mix semantic product changes with structural refactors unless the coupling is unavoidable
- keep source-specific parsing and payload quirks behind shared helpers where possible
- add focused regression tests when a refactor clarifies previously implicit behavior

## Open Questions
- Should `brightness_override` be renamed, split, or kept as-is?
- Is the current extended-range low-end display behavior worth its code complexity?
- Is reload suppression acceptable as implementation detail, or should refresh causality become explicit?
- Are manual-on/default-off semantics stable enough to refactor around confidently, or should they be revisited as a product decision first?

## Immediate Next Steps
- reduce the remaining direct `LightsLive` save/load wiring where practical
- plan the planner pure-core split behind the existing `plan_room/3` wrapper
- plan the shared light-state editing LiveComponent so scene editing is not the only place that owns that UI/behavior
- keep the import pipeline rescue cleanup on deck once the current LiveView-oriented refactors settle
- keep using the integration suite as the guardrail before touching refresh suppression
