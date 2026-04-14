# Refactoring Targets

## Goal
Improve maintainability and reliability without giving back the product stability we have now.

The app has reached the point where real-world usage matters more than feature velocity alone, so the best refactors are the ones that:

- reduce the chance of subtle state drift
- shrink the biggest conceptual hotspots
- preserve behavior under the existing test suite

## Architectural Constraint
When this document and `/Users/ianwalther/code/hueworks/planning/architecture-reset.md` pull in different directions, the architecture-reset doc wins.

In particular:

- upstream layers should stay focused on deciding desired state
- planner/executor should own downstream operational behavior
- refactors should simplify toward that boundary, not away from it

## Current High-Value Hotspots
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/bootstrap/hue.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/bootstrap/home_assistant.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/subscription/hue_event_stream/mapper.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex`

## Priority Order

### 1) Unify bootstrap and live state mapping per source
This is the highest-value refactor target right now.

Problem:
- initial state and steady-state updates are not consistently built by the same canonical mapping path
- that creates room for "wrong at first, then correct later" behavior

Examples:
- Hue bootstrap and Hue live events do not currently share the same full state-building path
- Home Assistant bootstrap and Home Assistant live events have the same drift risk

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/bootstrap/hue.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/bootstrap/home_assistant.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/subscription/hue_event_stream/mapper.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/subscription/home_assistant_event_stream/connection.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/state_parser.ex`

Preferred direction:
- extract source-specific canonical state builders
- make bootstrap and live event ingestion call the same lower-level builders
- keep source quirks localized, but keep final control-state shape generation shared

Expected payoff:
- fewer bootstrap vs live inconsistencies
- cleaner mental model for control-state ownership
- lower risk when adding new attributes like color, temp, or future capabilities

### 2) Split `Hueworks.HomeAssistant.Export` into a real subsystem
`/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex` is now big enough that it is no longer one coherent module.

Current responsibilities include:
- MQTT connection lifecycle
- discovery payload generation
- scene/select/light/switch export modeling
- command parsing and routing
- optimistic state publishing
- cleanup and unpublish behavior

Preferred direction:
- keep a small runtime / GenServer entrypoint
- extract helpers or modules for:
  - discovery payload generation
  - state payload serialization
  - command decoding and routing
  - entity selection/query helpers
  - cleanup/unpublish logic

Expected payoff:
- easier to reason about MQTT behavior without paging through every export mode at once
- safer iteration on HA export features
- easier testing of serializer behavior independent of process lifecycle

### 3) Split `Hueworks.Picos` by responsibility
`/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex` is carrying too much at once.

Current responsibilities include:
- bridge sync/import
- device materialization
- room assignment
- binding persistence
- config cloning
- presets
- runtime button handling

Preferred direction:
- split into modules roughly along:
  - sync/materialization
  - binding/config helpers
  - runtime press handling

Expected payoff:
- easier changes to button behavior without risking sync code
- cleaner mental boundaries for future Pico features
- smaller, more testable units

### 4) Tighten the `Scenes` and editor boundary
This area is better than it used to be, but there is still too much editor-specific translation pressure around scene persistence and orchestration.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live.ex`

Preferred direction:
- keep `Scenes` focused on orchestration and persistence
- keep editor token translation and UI-only concerns at the LiveView boundary
- continue moving toward cleaner already-resolved inputs before persistence

Expected payoff:
- scene editing becomes easier to evolve without making the core scene context more magical
- fewer editor-shaped conditionals in persistence code

### 5) Delay planner/executor extraction until after upstream cleanup
These are still some of the riskiest modules in the app, but they should not be the first refactor target while the system is still being observed in real-world usage.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`

Preferred direction:
- defer major structural work here until after state-ingestion and export cleanup
- when we do touch them, prefer behavior-preserving extraction first
- preserve public entrypoints while moving logic lower into purer helpers over time

Why this is lower than it sounds:
- the planner/executor path is reliability-critical
- several currently observed oddities may still be upstream state issues rather than planner issues
- upstream cleanup will make later planner work safer and clearer

### 6) Keep LiveViews thin and move UI-specific logic outward
This is still important, just no longer the very first thing to do.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/scene_builder_component.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/light_state_editor_live.ex`

Preferred direction:
- keep LiveViews focused on:
  - event wiring
  - assign updates
  - composition of helpers/components
- keep domain orchestration and persistence translation out of the LiveView layer

### 7) Extract shared UI components only after the boundaries are cleaner
Shared UI extraction is still desirable, but it will go better after the surrounding responsibilities are less tangled.

Preferred direction:
- extract reusable light-state editing UI only after the editor/domain boundary is clearer
- avoid baking current page-specific assumptions into a shared component API

### 8) Clean up broad `rescue` usage in import/fetch paths
This is still worthwhile, but it is not where the best stability payoff is right now.

Preferred direction:
- expected failures should be returned explicitly as `{:error, reason}`
- true bugs should remain visible rather than being flattened into generic error strings

### 9) Revisit high-complexity product behaviors only after the code is easier to observe
There are a few features whose complexity cost may eventually outweigh their value, but they should be revisited deliberately, not mixed into structural cleanup.

Candidate areas:
- extended low-end kelvin support
- manual-on/default-off semantics inside active scenes
- timing-based scene-clear protection
- manual power-latch survival across scene reapply

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

### 3) Keep manual power-latch semantics explicit
The old `brightness_override` flag is gone, which is good. The remaining goal is to keep manual power-latch behavior from becoming another fuzzy ownership layer.

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

## Lower-Value Cleanup To Defer
These are fine later, but they should not displace the higher-value structural work above.

- alias ordering cleanup
- missing moduledocs on straightforward schema modules
- small `Enum.map |> Enum.join` cleanup
- minor `with` versus `case` rewrites
- similar Credo-only style churn that does not materially improve the app's reliability or boundaries

## Recommended Sequence

### Phase 1
- unify bootstrap and live state mapping per source
- add focused regression coverage where current behavior was previously only implicit

### Phase 2
- split `Hueworks.HomeAssistant.Export`
- keep export behavior identical while carving out discovery, serialization, and command helpers

### Phase 3
- split `Hueworks.Picos`
- keep sync, config, and runtime button handling easier to reason about independently

### Phase 4
- keep tightening the `Scenes` and editor boundary
- move more editor-only translation to the LiveView layer

### Phase 5
- revisit planner/executor extraction only after the upstream layers are cleaner
- focus on behavior-preserving extraction and observability, not semantics changes

### Phase 6
- continue thinning LiveViews and extracting shared UI only where the boundaries are already stable

### Phase 7
- clean up broad `rescue` usage in fetch/import paths

### Phase 8
- re-evaluate whether the highest-complexity product behaviors still justify their implementation cost

## Refactor Guardrails
- use the existing test suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- do not mix semantic product changes with structural refactors unless the coupling is unavoidable
- add focused regression tests when a refactor clarifies previously implicit behavior
- when in doubt, move logic toward clearer ownership boundaries instead of introducing more coordination layers

## Open Questions
- Should manual power-latch semantics remain in scene-intent construction, or move lower over time?
- Is the current extended-range low-end display behavior worth its code complexity?
- Is timing-based scene-clear suppression acceptable as an implementation detail, or should lower-level causality become more explicit?
- Are manual-on/default-off semantics stable enough to refactor around confidently, or should they be revisited as a product decision first?
