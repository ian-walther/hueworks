# Refactoring Targets

## Goal
Reduce complexity in the circadian, scene, planner, and `/lights` paths without accidentally changing product behavior.

## Architectural Constraint
When this document and `/Users/ianwalther/code/hueworks/planning/architecture-reset.md` pull in different directions, the architecture-reset doc wins.

In particular:

- upstream layers should stay focused on deciding desired state
- planner/executor should own downstream operational behavior
- refactors should simplify toward that boundary, not away from it

## Churn Hotspots
- `lib/hueworks/scenes.ex`
- `lib/hueworks/active_scenes.ex`
- `lib/hueworks_app/control/state.ex`
- `lib/hueworks_app/control/desired_state.ex`
- `lib/hueworks/control/planner.ex`
- `lib/hueworks/kelvin.ex`
- `lib/hueworks_web/live/lights_live.ex`

## Enduring Simplification Targets

### 1) Keep light-state semantics centralized
The code should continue to avoid reintroducing duplicated logic for:

- key alias handling
- desired-state clamping for per-light kelvin limits
- desired-vs-physical equality checks
- brightness tolerance
- kelvin equivalence and quantization behavior

Guidance:
- keep comparison and normalization rules centralized instead of letting helpers regrow in multiple modules

### 2) Keep scene intent separate from scene orchestration
`Scenes.apply_scene/2` should stay mostly orchestration.

Guidance:
- keep desired-state construction and scene-policy logic out of the outer orchestration path
- if `Scenes.apply_scene/2` starts growing again, prefer another layer split instead of adding conditionals back in

### 3) Keep LiveViews thin
`/lights` should keep moving toward:

- event wiring
- assign updates
- composition of helpers/components

not toward:

- domain orchestration
- convergence logic
- persistence translation logic

### 4) Keep manual power-latch semantics explicit
The old `brightness_override` flag is gone, which is good. The remaining goal is to keep manual power-latch behavior from becoming another fuzzy ownership layer.

Guidance:
- prefer explicit names like `preserve_power_latches` over overloaded lifecycle flags
- keep latch semantics narrow and traceable
- do not let new hidden ownership rules accumulate in scene lifecycle code

### 5) Keep planner loading/orchestration separate from a pure planning core
The planner remains one of the highest-value places to simplify.

Preferred direction:
- keep `plan_room/3` as a thin wrapper if needed
- keep growing a pure planning core underneath it
- make planner logic easier to test without DB setup

Important nuance:
- preserve the public entrypoint first
- move tests lower over time where that helps clarity

### 6) Move scene-editor-specific translation closer to the editor boundary
Scene-component persistence should not keep owning editor-specific token translation such as:

- `"new"`
- `"new_manual"`
- `"new_circadian"`

Preferred direction:
- keep persistence working with cleaner, already-resolved input where possible
- keep editor-only translation near the LiveView/component boundary

### 7) Extract light-state editing into a shared LiveComponent
This is partly refactoring and partly product improvement.

Goal:
- move light-state edit UI and form behavior into a reusable LiveComponent
- allow it to be mounted:
  - inside scene editing flows
  - on its own from other locations in the app

Guidance:
- avoid baking scene-editor assumptions too deeply into the component API
- keep shared validation and normalization rules in one place

### 8) Clean up broad rescue usage in the import pipeline
Broad `rescue` blocks in the import pipeline still flatten expected failures and true bugs into the same shape.

Preferred direction:
- let fetchers return `{:ok, value}` / `{:error, reason}` for expected failures
- keep true bugs visible as crashes instead of swallowing them into generic strings

### 9) Treat bridge-dispatch abstraction as low priority
Repeated source dispatch logic is real, but not one of the highest-value simplification targets.

Guidance:
- use a simple module-map style if this area grows
- avoid building abstraction here unless bridge count or bridge-specific branching materially expands

### 10) Use logger metadata only as a supplement
`Logger.metadata/1` may reduce some same-process boilerplate, but it is not a replacement for explicit traces that cross queue and executor boundaries.

## UI Pitfalls

### LiveView dynamic form controls need stable structure
This has already caused repeated bugs.

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

## Features With Outsized Complexity Cost
These are not necessarily bad features. They are just where a small-looking requirement tends to spread complexity across many layers.

### 1) Extended low-end kelvin support
Question:
- is the exact current UX around sub-`2700K` preservation worth the ongoing implementation complexity?

### 2) Default-off lights that can be manually turned on without deactivating the scene
Question:
- does the current behavior deliver enough user value to justify the amount of branching it introduces?

### 3) Reload should never clear scenes
Question:
- should this remain timing-based protection, or should lower-level apply/reconciliation causality become more explicit?

### 4) Manual power latches surviving circadian reapply
Question:
- should this remain expressed in scene-intent construction, or eventually move lower into planner/executor reconciliation?

## Recommended Sequence

### Phase 1
- keep collapsing remaining LiveView-specific load/save wiring
- keep moving editor/loading/persistence translation out of `LightsLive`

### Phase 2
- strengthen planner purity and planner/executor observability
- move more reliability reasoning downward rather than upward

### Phase 3
- extract the shared light-state editing LiveComponent
- move scene-editor-specific token translation to a cleaner boundary

### Phase 4
- clean up broad `rescue` usage in the import pipeline

### Phase 5
- revisit refresh causality and active-scene power-latch ownership only in ways that stay aligned with `architecture-reset.md`

### Phase 6
- evaluate whether the highest-cost features should be simplified or re-scoped

## Refactor Guardrails
- use the existing integration suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- do not mix semantic product changes with structural refactors unless the coupling is unavoidable
- keep source-specific parsing and payload quirks behind shared lower-level helpers where possible
- add focused regression tests when a refactor clarifies previously implicit behavior

## Open Questions
- Should manual power-latch semantics remain in scene-intent construction, or move lower over time?
- Is the current extended-range low-end display behavior worth its code complexity?
- Is timing-based scene-clear suppression acceptable as an implementation detail, or should lower-level causality become more explicit?
- Are manual-on/default-off semantics stable enough to refactor around confidently, or should they be revisited as a product decision first?
