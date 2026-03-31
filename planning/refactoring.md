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

### 1) Control semantics are duplicated across modules
The same concepts currently exist in multiple places:
- key alias handling for `brightness` / `kelvin` / `temperature`
- desired-state clamping for per-light kelvin limits
- desired-vs-physical equality checks
- brightness tolerance handling
- kelvin equivalence / quantization handling

This duplication currently lives across:
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_app/control/desired_state.ex`

Risk:
- bug fixes have to be repeated in several places
- behavior can drift subtly between planner, reconcile, and active-scene clear paths

Recommendation:
- extract a shared control-semantics module

Candidate responsibilities:
- canonical key alias lookup
- brightness equality
- temperature equality
- divergence-key calculation
- effective desired-state shaping for a single light
- kelvin extraction / insertion helpers

### 2) `Scenes.apply_scene/2` is carrying too many responsibilities
`lib/hueworks/scenes.ex` currently:
- loads scene/component data
- computes desired state from light states
- applies default power policy
- preserves manual power overrides
- applies targeted power overrides
- commits desired state
- builds planner input
- logs tracing
- enqueues executor actions

Risk:
- each new edge case gets added into one increasingly central function
- scene behavior is harder to reason about in isolation

Recommendation:
- split scene application into smaller layers

Suggested shape:
1. scene intent builder
2. desired-state commit / diff step
3. planner + dispatch orchestration

### 3) `/lights` is doing domain orchestration that does not belong in the LiveView
`lib/hueworks_web/live/lights_live.ex` currently mixes:
- UI event handling
- manual action orchestration
- active-scene reapply decisions
- desired-state writes
- executor dispatch
- UI-only display-state shaping for extended kelvin behavior

Risk:
- small UI tweaks can accidentally affect control behavior
- manual-control behavior is harder to test outside LiveView tests

Recommendation:
- extract domain helpers out of the LiveView

Suggested split:
- `LightsManualControl` style helper or context for manual actions
- `LightsDisplayState` style helper for UI merging / kelvin presentation

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

## High-Leverage Refactor Targets

### 1) Extract shared light-state semantics
Priority: highest

Candidate module:
- `lib/hueworks/control/light_state_semantics.ex`

Potential responsibilities:
- `values_equal?`
- `diverging_keys`
- `value_or_alias`
- key alias maps
- kelvin parsing/extraction helpers
- per-light desired-state clamping

Why first:
- it removes the most dangerous duplication
- it directly lowers the chance of repeating planner/reconcile/scene-clear drift bugs

### 2) Split scene intent from scene dispatch
Priority: high

Candidate modules:
- `lib/hueworks/scenes/intent.ex`
- `lib/hueworks/scenes/apply.ex`

Potential split:
- pure intent generation from scene components
- side-effectful commit/plan/enqueue orchestration

Why:
- simplifies reasoning about active-scene behavior
- makes scene application easier to test without exercising the whole stack each time

### 3) Extract manual-control orchestration from `LightsLive`
Priority: high

Candidate modules:
- `lib/hueworks/lights/manual_control.ex`
- `lib/hueworks/lights/display_state.ex`

Why:
- reduces LiveView complexity
- makes manual on/off/default-off/scene-reapply logic easier to test without going through LiveView handlers

### 4) Simplify refresh suppression
Priority: medium

Current behavior works, but scene-clear suppression is currently a hidden time-window in control state.

Longer-term alternatives:
- source-tagged writes everywhere
- refresh token / scoped suppression context
- explicit "ignore clear for this resync batch" metadata

Why:
- hidden global timing state is effective but harder to reason about than explicit causality

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
- extract shared light-state semantics
- leave behavior unchanged
- migrate planner, control state, and desired state to the shared helpers

### Phase 2
- split scene intent building from apply/dispatch orchestration
- keep `Scenes.apply_scene/2` as the public entry point initially

### Phase 3
- extract manual action orchestration from `LightsLive`
- extract display-state shaping from `LightsLive`

### Phase 4
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

## Immediate Candidate First Step
Extract a shared light-state semantics module and migrate:
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks_app/control/desired_state.ex`

This looks like the best first move because it reduces duplication without changing the user-facing model.
