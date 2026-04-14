# Refactoring Targets

## Goal
Improve maintainability and reliability without giving back the product stability we have now.

The best refactors right now are the ones that:
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
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/runtime.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/config.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex`

## Priority Order

### 1) Finish thinning `Hueworks.HomeAssistant.Export`
Keep the export runtime shell small and explicit.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/runtime.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/router.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/home_assistant/export/sync.ex`

Preferred direction:
- keep `export.ex` focused on GenServer state transitions and public entrypoints
- move any remaining process-local policy/helpers out of the runtime shell
- decide whether `runtime.ex` should stay as a separate helper or be folded into clearer, smaller responsibilities
- keep transport, publishing, routing, and selection logic outside the runtime shell

Expected payoff:
- easier to reason about HA MQTT behavior without paging through multiple concerns at once
- safer iteration on export features and cleanup behavior
- simpler manual debugging of runtime state transitions

### 2) Finish splitting `Hueworks.Picos`
Keep `Picos` as a small facade with clear helper boundaries.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/config.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/actions.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/targets.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/picos/sync.ex`

Preferred direction:
- keep `picos.ex` as a small public facade instead of a secondary implementation module
- continue reducing cross-module leakage of helper details
- keep sync, config, targets, and runtime action logic conceptually separate
- consider whether some naming or public entrypoints should be made more explicit before future Pico work lands

Expected payoff:
- easier changes to Pico behavior without risking sync code
- smaller review surface for button-binding changes
- cleaner handoff when doing manual refactors later

### 3) Tighten the `Scenes` and editor boundary
Keep editor-specific translation pressure out of scene persistence and orchestration.

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

### 4) Delay planner/executor extraction until after upstream cleanup
These are some of the riskiest modules in the app, and they should not be the first refactor target while the system is still being observed in real-world usage.

Files:
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`

Preferred direction:
- defer major structural work here until after upstream state and export cleanup stabilizes
- when these modules are touched, prefer behavior-preserving extraction first
- preserve public entrypoints while moving logic lower into purer helpers over time

Why this is lower than it sounds:
- the planner/executor path is reliability-critical
- several oddities may still be upstream state issues rather than planner issues
- upstream cleanup will make later planner work safer and clearer

### 5) Keep LiveViews thin and move UI-specific logic outward
Keep LiveViews focused on UI concerns rather than domain orchestration.

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

### 6) Extract shared UI components only after the boundaries are cleaner
Shared UI extraction should wait until the surrounding responsibilities are less tangled.

Preferred direction:
- extract reusable light-state editing UI only after the editor/domain boundary is clearer
- avoid baking current page-specific assumptions into a shared component API

### 7) Clean up broad `rescue` usage in import/fetch paths
This matters, but it is not where the best stability payoff is right now.

Preferred direction:
- expected failures should be returned explicitly as `{:error, reason}`
- true bugs should remain visible rather than being flattened into generic error strings

### 8) Revisit high-complexity product behaviors only after the code is easier to observe
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
- finish thinning `Hueworks.HomeAssistant.Export`
- keep the runtime shell focused on GenServer transitions only

### Phase 2
- finish splitting `Hueworks.Picos`
- keep sync, config, targets, and runtime action code easier to reason about independently

### Phase 3
- keep tightening the `Scenes` and editor boundary
- move more editor-only translation to the LiveView layer

### Phase 4
- revisit planner/executor extraction only after the upstream layers are cleaner
- focus on behavior-preserving extraction and observability, not semantics changes

### Phase 5
- continue thinning LiveViews and extracting shared UI only where the boundaries are already stable

### Phase 6
- clean up broad `rescue` usage in fetch/import paths

### Phase 7
- re-evaluate whether the highest-complexity product behaviors still justify their implementation cost

## Refactor Guardrails
- use the existing test suite as the primary behavior safety net
- prefer behavior-preserving extraction first, behavior changes second
- when a refactor changes semantics, make that explicit and deliberate instead of burying it in cleanup work
