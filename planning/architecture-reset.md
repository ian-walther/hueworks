# Architecture Reset

## Status
This document absorbs the former split reset planning threads and should be treated as the authoritative architecture and product-direction document for the current reset.

## Purpose
Capture the current architectural direction for HueWorks after real production use of:

- circadian scenes
- mixed-bridge manual control
- external manual inputs
- Home Assistant scene integration

This document is meant to do three things in one place:

1. preserve the best insights from the earlier circadian and external-input planning work
2. record what real-world testing has proven or falsified
3. define a cleaner architectural north star before more incremental fixes pile on

## Executive Summary
The architecture should return to a stricter version of the original intended control pipeline:

1. upstream inputs decide what the desired target state should be
2. that target is committed into `DesiredState`
3. planner/executor own everything downstream of that commit
4. physical state is observed and reconciled against desired state

The critical reset principle is:

> `DesiredState` should be the only mutable control target.

That implies:

- scenes, circadian updates, manual inputs, and Home Assistant scene triggers should only compute and commit desired-state changes
- planner/executor should own optimization, dispatch, retry, sequencing, and convergence behavior
- physical state should remain observation, not a second control source
- upstream layers should not grow their own parallel control/retry engines

This is a corrective to the drift that has happened over time.

Some recent experiments were useful learning exercises, but they also confirmed that adding another runtime target layer above `DesiredState` risks complexity without solving the real problem.

## The Architectural Problem
There are really two overlapping problems.

### 1. Domain Collapse
The system still tends to collapse several different concepts into the same flat light-state shape:

- scene intent
- desired control state
- observed physical state
- transport payloads and event reports
- UI display state

That collapse is a major reason the circadian and temperature logic has accumulated so many local fixes.

### 2. Control-Behavior Drift
Operational control behavior has leaked upward out of planner/executor and into higher layers such as:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/intent.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/active_scenes.ex`
- some UI-adjacent helpers

That drift has made the code harder to reason about because upstream code is no longer just deciding targets. It is increasingly trying to own convergence behavior too.

The strongest reset is:

- keep the useful conceptual split between intent, observation, and transport
- but operationally re-center the system around one materialized control target: `DesiredState`

## Current Principles
These should be treated as the current non-negotiable design rules unless the codebase proves they are impossible.

### 1. `DesiredState` Is The Only Mutable Control Target
There should not be a second runtime target store that competes with or sits alongside desired state.

That means:

- no long-lived parallel room target layer
- no manual-control-specific shadow target model
- no planner-bypassing runtime override plane

If higher-level features need overlays or contracts, they should compile down into desired-state transactions rather than become a second control path.

### 2. Upstream Code Only Decides Target State
Upstream inputs may compute desired state from different sources:

- scene activation
- circadian progression
- UI manual changes
- external manual inputs
- Home Assistant scene triggers

But once the desired-state transaction is decided and committed, the rest of the job belongs to planner/executor.

### 3. Planner/Executor Own All Downstream Operational Behavior
Planner/executor should own:

- bridge partitioning
- group-vs-light optimization
- retries
- convergence loops
- sequencing
- mixed-bridge coordination
- interpreting "did the current action actually land?"

If the system is flaky after desired state is correctly committed, that should be treated first as a planner/executor problem.

### 4. Physical State Is Observation, Not Control Intent
Physical state exists to answer:

- what do the devices appear to be doing right now?
- how far are we from desired state?
- has convergence occurred yet?

It should not become a second source of intent.

### 5. UI Should Mostly Render And Collect Intent
UI layers should:

- display current state
- let users edit inputs
- dispatch actions

They should not keep accumulating domain semantics that belong lower in the stack.

## What Real-World Use Has Proven
The production testing has been especially valuable because it exposed which ideas actually help.

### 1. Scenes Are Still The Most Reliable Path
Scene activation is effectively near-100% reliable in real use, including relatively complex mixed-bridge state changes.

That tells us the core platform can already do this reliably when the control path is strong enough.

### 2. Manual Entry Points Should Be Architecturally Equivalent
The system should not treat different manual entry points as different runtime control models.

That means:

- direct UI manual actions
- future external manual triggers

should all funnel into the same upstream desired-state path.

The differences between those inputs should mostly live in:

- discovery/configuration
- mapping
- UI ergonomics

not in downstream control semantics.

### 3. Manual Power Control Is Still Less Reliable Than Scenes
Even after multiple improvements, manual power control remains slightly less reliable than scene activation, especially for mixed-bridge room control.

This is a core product problem, not a convenience issue. One of HueWorks' main promises is that a single control surface can reliably drive lights across bridges together.

### 4. Narrow, Evidence-Backed Fixes Still Matter
One specific bug was real and worth preserving:

- manual scene reapply needed to refresh the active scene pending window before and after targeted reapply
- otherwise normal in-flight updates could be mistaken for external divergence and clear the scene mid-action

That fix belongs to the existing architecture and should stay.

### 5. The Broader Room-Runtime Experiment Did Not Justify Itself
A broader experiment introduced a separate runtime room-target layer with power overrides and fallback room baselines.

That experiment did not materially improve the real-world mixed-bridge success rate enough to justify the extra complexity.

The lesson is important:

- not every plausible architectural idea earns its keep
- if a new layer does not clearly improve the real reliability problem, it should not become the new center of the design

### 6. Some Improvements Were Real Even If The Broader Experiment Was Not
The following narrower lessons remain valid and should not be forgotten just because the broader room-runtime experiment did not justify itself:

- `Toggle` decisions should prefer `DesiredState` over raw physical `State`
- mixed-bridge manual control benefits from better reconciliation, but that reconciliation should likely live lower in the stack
- preserving stable public APIs while refactoring internals is the right rollout style for this codebase

## Domain Model Vocabulary
Even with the stricter `DesiredState` pipeline restored, the system still benefits from clearer conceptual vocabulary.

### Scene Intent
Logical target state produced by:

- scene configuration
- circadian adaptation
- scene composition rules

This is source-agnostic and user-facing.

### Desired State
The single materialized control target that planner/executor should work from.

This is the only mutable runtime control target.

### Observed State
Canonical interpreted physical state as the system understands it.

This should be what planner/executor and the UI compare against.

### Transport State
Raw bridge payloads and event shapes.

This layer is allowed to be messy, but its mess should stay contained.

## Device Profile Boundary
The earlier circadian work correctly identified a missing boundary: source- and device-specific semantics are spread across too many helpers.

That remains true.

The most coherent lower-level abstraction is still a per-device or per-profile boundary that owns:

- projecting logical intent into controllable intent
- encoding commands
- decoding raw events
- practical equivalence between observed and desired state

The conceptual shape is still something like:

```elixir
defmodule Hueworks.DeviceProfile do
  @callback project_intent(light, scene_intent) :: controllable_intent
  @callback encode_command(light, controllable_intent) :: payload
  @callback decode_event(light, raw_event) :: observed_state
  @callback equivalent?(light, observed_state, controllable_intent) :: boolean
end
```

This does not change the reset principle above it. It reinforces it.

A profile layer belongs underneath desired-state commits, not alongside them.

### Concrete Responsibilities Of A Profile Boundary
The useful responsibility split from the earlier circadian work still holds:

- `project_intent/2`
  - apply floors, capability dropping, and practical target projection
- `encode_command/2`
  - turn controllable intent into bridge payloads
- `decode_event/2`
  - turn raw bridge payloads into canonical observed state
- `equivalent?/3`
  - decide practical equality between observed and target state for that device

This is the most coherent long-term place for:

- Hue floor clamping
- brightness tolerance
- non-temperature light handling
- Z2M low-end warm-white encoding
- Z2M `2600-2700K` crossover interpretation

## Where Current Complexity Comes From
### Circadian / Temperature Complexity
The circadian and low-end kelvin logic became complicated because the same map shape has been asked to represent:

- logical warm-white intent
- actual device floors and quantization
- Z2M crossover ambiguity around the `2600-2700K` band
- UI-readable temperature display

The long-term simplification remains:

- keep intent, observation, and transport conceptually separate
- push source/device-specific logic behind a profile boundary
- keep UI out of semantic correction work whenever possible

### Manual Reliability Complexity
The manual-control side became complicated because retries, ownership, and reconciliation started getting handled outside the clean pipeline.

This is the part that now needs a stronger reset:

- no second runtime target plane
- no increasingly fancy manual-control-specific convergence system in upstream code
- move reliability behavior down into planner/executor

## What Must Be Preserved From Circadian Work
The earlier circadian planning is still valuable, but it needs to be interpreted through the stricter control-boundary rule.

### Still Correct
These ideas remain good:

- scene intent, observed state, and transport state are conceptually different domains
- device profiles are the right place for bridge-specific and device-specific semantics
- UI should not accumulate hidden domain logic
- `brightness_override` is a smell that the ownership model wants to be more explicit
- groups are better treated as projections/optimization units than as competing truth sources

### Hotspots This Would Still Simplify
The earlier circadian analysis identified the right hotspots even though the overall control-boundary framing is now stricter:

- planner comparisons should depend on canonical observed state plus device-profile equivalence, not generic map heuristics
- scene-clear logic should be about contract violation after reconciliation, not a growing pile of tolerance guesses
- UI rendering should not need to preserve or reinterpret values because lower layers should already have canonicalized observation

### Needs Reframing
The following ideas are still useful to think about, but they should not introduce a second mutable control target:

- active-scene contracts
- manual overlays or latches
- no-scene fallback baseline behavior

If these concepts are used, they should feed into how desired-state transactions are computed rather than becoming a second runtime control layer.

### Groups As Projections, Not Truth Sources
This idea remains important enough to call out directly.

The clean model is:

- groups are optimization units for commands
- member lights are the source of truth for observation
- group UI is a projection from member lights

This is especially important for mixed-source and Z2M-heavy rooms, where group/member disagreement has repeatedly created confusing behavior.

## Circadian-Specific Technical Notes Worth Keeping
### Edge Cases That The Lower-Level Split Should Make Easier
The device-profile plus canonical-observation model is still the best long-term answer for these specific problem classes:

- brightness drift and tolerance
- Hue temperature floor clamping
- low-end Z2M warm-white encoding below `2700K`
- Z2M warm-white crossover decoding in the `2600-2700K` band
- default-off lights that can be manually turned on without immediately deactivating a scene
- reload/bootstrap flows that should not clear scenes spuriously

### Highest Complexity-Cost Features
These features are still the biggest complexity multipliers in the system:

- extended low-end kelvin support below `2700K`
- default-off lights that can be manually turned on without clearing the scene
- automatic scene deactivation from physical divergence
- reload/bootstrap behavior that should not clear scenes

These features are not necessarily mistakes. They are simply where a large share of special-case complexity comes from.

### Apply Revisions Still Make Sense As A Lower-Level Goal
The earlier circadian work was right that time-window heuristics are weaker than explicit causality.

So although the broader architecture should re-center on `DesiredState`, the lower-level evolution can still move toward:

- apply revisions attached to planner/executor work
- reconciliation keyed to explicit apply lineage rather than only time windows
- scene-clear decisions that happen after a real chance to converge

This should be pursued as planner/executor infrastructure, not as a second target model.

## Current Technical Direction
### Upstream Responsibilities
The following modules should stay upstream and mostly target-focused:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/intent.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/active_scenes.ex`

Their job should be:

- compute desired transactions
- commit them
- attach necessary metadata for lifecycle or tracing

Their job should not be:

- building increasingly special retry engines
- owning mixed-bridge convergence behavior
- accumulating more ad hoc dispatch recovery logic

### Downstream Responsibilities
The following modules are the natural place for stronger convergence behavior:

- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/apply.ex`
- executor/dispatch paths below planner
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/state.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/desired_state.ex`

This is where the real problem likely lives now:

- exact planned action sets
- bridge partitioning
- retry scope
- convergence timing
- mixed Hue + Z2M delivery behavior
- explicit apply lineage and reconciliation context

### Specific Suspected Failure Area
The remaining manual-control miss rate likely reflects one of these downstream issues:

- one bridge action not being issued when expected
- one bridge action being issued but not landing physically
- retries happening at the wrong time relative to observed state updates
- mixed-bridge partial convergence being treated as success too early

That is why the next serious debugging pass should target planner/executor timing and action traces rather than inventing more upstream intent layers.

## Things We Should Explicitly Avoid
These were explored or implied at various points, but should not be the center of the plan now.

- a second persistent or semi-persistent runtime room target layer
- manual-control-specific convergence machinery above planner/executor
- treating different manual entry points as fundamentally different classes of state change
- UI-driven semantic correction where lower layers should be canonicalizing state
- trying to infer `favorite`, `top`, or `bottom` semantics from raw button numbering

## Recommended Debugging Focus
Before any more major architectural work, the next debugging push should be brutally concrete.

For a single problematic mixed-bridge manual action, capture:

1. the input target light ids
2. the exact desired-state diff committed
3. the final planner output
4. dispatch start/end per action
5. first physical update seen per affected light
6. whether convergence was declared too early
7. whether a bridge-specific action or physical update was missing

This should be done as close to the planner/executor boundary as possible.

The remaining issue now looks more like a control-pipeline problem than an upstream target-model problem.

## Testing And Rollout Rules
These rules should continue to govern any implementation work that follows this document.

### Preserve Existing Public APIs Where Possible
Prefer changing internals under existing surfaces such as:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`

That keeps the current suite valuable.

### If Tests Break Expectedly, Reconsider Their Level
Do not blindly force new behavior back into old tests.

If a test breaks for an expected architectural reason, ask:

- is this still the right surface to test?
- should this assertion move lower or higher?

### Prefer Narrow Proven Fixes Over Big Unproven Layers
The pending-window fix is a good example of the kind of change that earns its keep.

The room-runtime experiment is a good example of a larger idea that did not yet prove enough value.

### Production Validation Still Matters
This app now controls real rooms and real daily workflows.

That means:

- mixed-bridge manual behavior has to be validated in production-like reality
- not just in tests
- rollout should stay incremental and evidence-driven

### This Is Not A Small Refactor
Even with the reset clarified, this remains a significant piece of work because:

- state-model cleanup ripples across many layers
- mixed-bridge reliability cannot be fully proven in unit tests
- production validation is required
- some older tests may need to move to a better boundary instead of being preserved literally

## Phased Reset Plan
### Phase 1: Consolidate The Architecture Direction
Done by this document.

The important outcome is one shared north star instead of separate planning threads drifting apart.

### Phase 2: Re-assert The DesiredState Pipeline
Audit current code and identify places where upstream layers own too much downstream behavior.

Goal:

- get closer again to `change desired state -> commit -> planner/executor -> device calls`

### Phase 3: Strengthen Planner/Executor Convergence
Move reliability work down where it belongs.

Potential work here includes:

- better tracing
- tighter retry rules
- clearer mixed-bridge convergence checks
- better action scoping
- explicit convergence criteria

### Phase 4: Resume Lower-Level Circadian Simplification
Once the control-boundary reset is stable again, continue the deeper circadian cleanup through:

- device profile boundaries
- clearer observed-state canonicalization
- less UI semantic leakage

This should be done without reintroducing a second mutable target layer.

### Phase 5: Revisit Apply-Reconciliation Infrastructure
After the desired-state pipeline is reasserted and planner/executor reliability is better understood, revisit:

- apply revisions
- clearer convergence criteria
- cleaner scene-clear causality

This should happen as downstream operational infrastructure, not as a new upstream state model.

## Open Questions
These are the remaining questions that are still worth keeping visible, even though they should now be answered within the stricter architecture boundaries.

1. Should active scenes continue to auto-clear from divergence exactly as they do now, or should that become a little more policy-like?
2. How explicit should power ownership become inside active-scene lifecycle code, especially as `brightness_override` is unwound?
3. Is the current exact low-end Z2M warm-white UX worth its full maintenance cost, or is a slightly narrower model acceptable?
4. How much explicit apply lineage state are we comfortable carrying if it reduces timing heuristics significantly?

## Bottom Line
The reset is not "throw away everything learned so far."

It is:

- keep the good conceptual separation from the circadian work
- keep different manual entry points on the same upstream control path
- stop letting upstream code become its own control engine
- re-center the architecture around a single desired-state target and stronger planner/executor ownership

That is the cleanest path back toward the original HueWorks idea while still keeping the hard-won lessons from real-world use.
