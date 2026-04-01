# Circadian Architecture Reset

## Purpose
Capture a fresh architectural assessment of the circadian, scene, and physical-state handling code without assuming the current progressive build-out is the only reasonable shape.

This is intentionally not an implementation plan for tonight.

The goal is to preserve a high-fidelity answer to this question:

> If we were designing the circadian system today, knowing what we now know about the edge cases, what structure would reduce the need for so many special rules?

This document is meant to help future work answer that question before more incremental fixes pile on.

## Executive Summary

The biggest architectural issue is that the system currently uses the same flat light-state map shape for several different domains that are not actually the same thing:

- scene intent
- desired control state
- physical observed state
- UI display state
- transport payloads and event reports

That single-map approach looks simple locally, but it pushes a lot of hidden complexity into:

- state parsing
- desired-vs-physical comparison
- scene-clear logic
- UI merge/rendering behavior
- source-specific payload mapping

Most of the current edge cases are symptoms of that collapse.

The strongest simplification available is to separate those domains instead of continuing to encode all of them as `%{power, brightness, kelvin}` maps and then recovering intent later with heuristics.

The clearest redesign would introduce:

1. distinct models for scene intent, observed state, and transport state
2. a per-device or per-profile adapter that owns projection, encoding, decoding, and equivalence
3. a more explicit active-scene contract model instead of overloading `brightness_override`
4. apply-revision reconciliation instead of relying so heavily on grace-window guessing
5. group state treated as a projection for truth purposes rather than a competing source of truth

## Why This Keeps Getting Weird

The system has accumulated a large number of "reasonable local fixes" because each bug has been attacked at the level where it surfaced:

- brightness drift created tolerance logic
- kelvin clamping created effective-desired logic
- low-end Z2M temperature behavior created event remapping logic
- reload/bootstrap deactivation created suppression logic
- manual power interactions created override and latch behavior
- group/member disagreements created group recomputation logic

Each of those changes was individually justified.

The problem is not that those fixes were wrong.

The problem is that they were added to a model that already conflates:

- what the scene wants
- what the device can actually do
- what the transport said
- what the UI should show

As a result, every new edge case tends to spill into multiple layers at once.

One recent example is especially illustrative:

- after an app restart, an active scene could still appear active
- desired state could already reflect the current circadian target
- but the room might not have physically converged to that target
- later poller ticks could then under-dispatch because they were effectively planning from "did desired intent change?" more than "is the scene still unmet in the real world?"
- manually toggling a small group would correct only that group, because the targeted reapply path happened to force reconciliation for that subset
- deactivating and reactivating the whole scene would fix the room immediately, because that path force-applied the full scene again

That bug was fixable in the current system by widening planning to include reconcile drift, not just intent drift.

But architecturally, it is another symptom of the same underlying problem:

- desired intent
- observed physical divergence
- and "outstanding convergence work"

are still not represented as clearly separate concepts.

## Current Shape Of The System

The current system is already more structured than it used to be. Recent refactors helped.

Important current modules include:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/intent.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/active_scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/desired_state.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/state.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/light_state_semantics.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/state_parser.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/z2m_payload.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/home_assistant_payload.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/kelvin.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live/display_state.ex`

The refactors have helped reduce duplication, but the core model is still:

- scene intent is flattened into desired-state maps
- desired state is compared directly to physical state after a few normalization steps
- physical state is derived from transport-specific events
- UI state sometimes preserves prior rendered values because physical state is not always canonical enough on its own

That last point is especially telling:

if the UI layer needs to preserve or reinterpret temperature values beyond simple rendering, it usually means the state it receives is not yet in the right domain.

## Core Diagnosis

### One Flat State Shape Is Doing Too Many Jobs

The current system uses a plain light-state map to represent all of these:

- `"the scene wants this light warm at 2630K"`
- `"the desired control state for this light is 2630K"`
- `"Hue reported 3704K"`
- `"Z2M reported color_temp 3472 plus xy coordinates"`
- `"the UI should show this as 2681K"`

Those are not the same kind of fact.

They may all eventually correspond to the same human concept, but they live at different layers:

- user-intent layer
- device-capability layer
- transport-report layer
- UI presentation layer

When those layers are represented with the same shape, the system keeps having to answer questions like:

- should `3704K` and `3715K` count as the same?
- should this `3472K` field be believed, or does the `xy` payload mean the light is effectively `2681K`?
- should the UI show what the event said, what the desired state said, or a "preserved" value?
- should an event at the native device floor be mapped back into the extended logical range?

Those are not comparison problems alone.

They are domain-boundary problems.

## Proposed Reset: Split The Domains

The strongest simplification is to stop treating intent, observation, and transport as the same kind of thing.

### 1. Scene Intent

This is the logical target that scenes and circadian adaptation produce.

Examples:

- `power: :on`
- `brightness: 100`
- `kelvin: 2630`

This layer should be:

- source-agnostic
- user-facing
- logical, not transport-specific

This is where:

- circadian curves
- scene configuration
- default power semantics
- manual scene authoring

should live.

This layer should not care whether a device expresses warm-white below `2700K` via:

- mirek
- direct kelvin
- XY color
- some remapped native floor

It should only express the desired logical outcome.

### 2. Observed State

This is the canonical interpreted physical state of the light as the system understands it.

Examples:

- "this Z2M extended-range light is effectively at `2681K`"
- "this Hue light is effectively at its `2203K` floor"
- "this light is on at `52%`"

This is the state that should be used for:

- scene divergence detection
- planner "already in state?" checks
- UI rendering
- active-scene retention logic

The key property of observed state is:

it should already be canonical enough that the UI and scene logic do not need to reinterpret it.

If observed state is trustworthy, the UI does not need special preservation rules.

### 3. Transport State

This is the raw payload/event layer:

- Hue mirek
- Hue grouped-light responses
- Z2M `color_temp`
- Z2M `color_temp_kelvin`
- Z2M `color_mode`
- Z2M `xy`
- Home Assistant payload variations

This layer is messy by nature.

That is okay.

What matters is that the mess stays here.

Transport state should be:

- decoded into canonical observed state on the way in
- encoded from controllable intent on the way out

and should not leak directly into:

- scene divergence
- planner partitioning
- UI display logic

## Introduce A Device Profile Layer

The next major simplification is to give every controllable entity a profile or adapter that owns source- and device-specific behavior.

This is the missing abstraction behind many of the current helpers.

Today the logic is spread across:

- `/Users/ianwalther/code/hueworks/lib/hueworks/control/state_parser.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/z2m_payload.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/home_assistant_payload.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/kelvin.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/light_state_semantics.ex`

A better shape would be something like:

```elixir
defmodule Hueworks.DeviceProfile do
  @callback project_intent(light, scene_intent) :: controllable_intent
  @callback encode_command(light, controllable_intent) :: payload
  @callback decode_event(light, raw_event) :: observed_state
  @callback equivalent?(light, observed_state, controllable_intent) :: boolean
end
```

This does not have to be a literal Elixir behaviour immediately.

It could begin as a plain module family or function table.

What matters is the conceptual ownership:

### `project_intent/2`

Takes logical scene intent and produces what this device can meaningfully target.

Examples:

- Hue floor clamping
- non-temp lights dropping kelvin
- extended-range devices retaining the logical `2000-2700K` band

### `encode_command/2`

Turns controllable intent into transport payloads.

Examples:

- Hue mirek conversion
- Z2M `color_temp` encoding
- Z2M low-end `xy` encoding below `2700K`

### `decode_event/2`

Turns raw transport events into canonical observed state.

Examples:

- interpreting Hue mirek into canonical observed kelvin
- interpreting Z2M `xy` plus `color_temp` into a single canonical observed kelvin
- deciding what the `2600-2700K` crossover band means

### `equivalent?/3`

Answers whether the observed physical state is practically the same as the target intent for this device.

Examples:

- Hue temperature quantization via mirek steps
- brightness tolerance
- floor-clamped equivalence
- source-specific practical equality rules

This layer would eliminate a lot of the current need to re-derive "effective desired" in multiple places.

## Why This Would Simplify The Existing Hotspots

### Planner

Current planner complexity comes from needing to compare desired and physical state while also accounting for:

- brightness tolerance
- temperature quantization
- floor clamping
- non-temp lights

Today that logic is shared via:

- `/Users/ianwalther/code/hueworks/lib/hueworks/control/light_state_semantics.ex`

That is an improvement, but it is still reasoning over generic maps.

In a profile-based model, planner logic becomes:

- take controllable intent
- compare against canonical observed state using the profile
- group only lights whose projected controllable intent truly matches

That is conceptually cleaner than:

- clamp desired
- canonicalize aliases
- compare with tolerances
- hope that the transport/domain mix has already been normalized enough

### Scene Clear Logic

Current scene-clear logic in:

- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/state.ex`

has to answer:

- is the scene still effectively active?
- was this update probably ours?
- is this just quantization drift?
- is this just a reload/bootstrap echo?
- should power-only changes be ignored?

That is a lot of policy for one place.

Closely related: the poller and apply path also need to answer a reconciliation question that is easy to blur with scene intent:

- did the scene target itself change?
- or is the target unchanged while the room still has not actually converged?

The restart/manual-toggle bug above came from that distinction not being explicit enough.

In a cleaner design:

- scene divergence compares scene contract vs canonical observed state
- source-specific equivalence belongs to the device profile
- power ownership belongs to scene contract metadata
- reload/bootstrap semantics are explicit reconciliation contexts, not special cases inside comparison

### UI Rendering

Current UI display logic in:

- `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live/display_state.ex`

still contains real domain behavior, particularly around extended-range kelvin rendering.

That is a smell.

The UI should mostly be formatting and merge plumbing.

If observed state were canonical enough, the UI could simply render:

- brightness
- kelvin
- power

without preserving previous values based on special crossover rules.

## Active Scene Contracts Instead Of A Vague Override Flag

The current `brightness_override` concept is a major signal that the model wants to split.

Relevant code:

- `/Users/ianwalther/code/hueworks/lib/hueworks/active_scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes/intent.ex`

`brightness_override` now does more than suppress brightness adaptation.

It also interacts with:

- manual power latches
- default-off lights
- reapply behavior

That means the boolean name no longer reflects the real behavior.

In a fresh design, an active scene should carry a richer contract per light or per component.

For example:

- channels owned by the scene: `[:brightness, :temperature]`
- power policy:
  - `:follow_scene`
  - `:default_on`
  - `:default_off`
  - `:latched_manual`
- divergence policy:
  - strict
  - tolerant
  - ignore
- last applied revision

Then manual actions become explicit latches or overlays.

That is much easier to reason about than a single boolean with accumulated meaning.

### Why This Matters

Several current rules are actually ownership questions:

- should manual on/off clear the scene?
- should a default-off light stay manually on during circadian reapply?
- does the scene currently own power, brightness, temperature, or only some of them?

Those are not brightness-override questions.

They are scene-ownership questions.

The code would be simpler if it said that directly.

## Replace Grace Windows With Apply Revisions

Another source of complexity is that the system currently guesses whether an external update is "ours" by looking at time windows.

This appears in:

- active-scene pending windows
- refresh suppression windows
- bootstrap suppression

These are useful, but they are heuristic.

They do not model causality directly.

### Better Model

Each scene application or planner dispatch cycle gets an apply revision.

Then:

- planner output carries that revision
- executor dispatch carries that revision
- observed event reconciliation can match updates to the latest revision

Scene clear should only happen after:

1. the latest apply revision has had a chance to settle
2. canonical observed state still violates the active scene contract

This is more explicit than:

- "we are within the pending grace window"
- "we recently refreshed, so ignore clears"

It is more stateful, but it is also simpler because the rules are causal instead of temporal guesses.

### Practical Benefit

This could reduce the need for:

- refresh suppression windows
- some pending-window deactivation false positives
- bootstrap-specific exceptions in scene-clear logic

## Groups As Projections, Not Truth Sources

Groups have repeatedly been a source of trouble, especially for Z2M.

The cleanest mental model is:

- groups are optimization units for commands
- member lights are the source of truth for observation
- group UI is derived from member lights

This is already directionally true in some parts of the code, but it is not yet a fully consistent model.

If this were made explicit, it would simplify:

- group/member UI disagreements
- reload/bootstrap ordering issues
- some Z2M aggregate-state edge cases

That does not mean group entities are useless.

It means they should not be allowed to compete with member-light truth for observed-state purposes.

## The Specific Edge Cases This Model Would Make Less Scary

### 1. Brightness Drift

Current system:

- brightness tolerance exists in comparison layers
- but desired-to-desired intent changes must still be treated strictly

In a clearer model:

- scene intent progression is strict
- observed-state equivalence is profile-defined
- planner only cares about canonical observed equivalence, not raw flat-map comparison

### 2. Hue Floor Clamping

Current system:

- effective desired is clamped before comparison
- scene clear must compare against clamped intent

In a profile model:

- `project_intent/2` yields the actual controllable target
- scene clear compares against that controllable intent directly

### 3. Extended Low-End Z2M Warm White

Current system:

- low-end remapping lives across parser, payload builder, kelvin helpers, UI, and integration tests

In a profile model:

- the extended-range Z2M profile owns both:
  - command encoding below `2700K`
  - event decoding in the warm-white crossover band

That is much more coherent than today’s spread of helpers and crossover rules.

### 4. Manual Power On Default-Off Lights

Current system:

- power policy, latching, and scene retention interact across several modules

In a scene-contract model:

- the scene can simply declare whether it owns power for that light right now
- manual latch behavior is explicit state, not recovered from previous desired maps

### 5. Reload Should Not Clear Scenes

Current system:

- suppression window
- bootstrap tagging
- some integration-test protection

In a revision/reconciliation model:

- refresh becomes an explicit resync operation
- resync updates do not count as contract violation until reconciliation is complete

## Features With The Highest Complexity Cost

These are the features that seem to contribute the most complexity relative to how small they can appear in the UI:

### 1. Extended Low-End Kelvin Support Below `2700K`

This is valuable, but expensive.

It touches:

- event decoding
- command encoding
- UI rendering
- group/member state alignment
- tests across multiple sources

### 2. Default-Off Lights That Can Be Manually Turned On Without Clearing The Scene

Also valuable, but expensive.

It touches:

- scene intent
- active-scene retention
- manual control
- reapply behavior

### 3. Automatic Scene Deactivation From Physical Divergence

This is one of the most powerful features, but it creates a lot of edge cases because:

- devices quantize
- sources disagree
- updates are asynchronous
- commands and reports are not symmetric

### 4. Reload And Bootstrap Should Never Clear Scenes

This is a very nice product behavior, but it introduces another axis of causal ambiguity into scene reconciliation.

These features are not necessarily mistakes.

They just generate a large share of the special rules.

## What A Simpler Future Version Might Look Like

This section is intentionally conceptual, not a concrete implementation roadmap.

### Layer 1: Scene Engine

Produces logical per-light scene intent.

Responsibilities:

- circadian math
- manual scene configuration
- default power semantics
- scene component composition

Output:

- logical scene intent only

No source-specific quirks here.

### Layer 2: Device Profile Projection

Each device profile takes logical scene intent and produces:

- controllable intent
- transport payload
- event decode
- equivalence rules

Responsibilities:

- temperature floors
- brightness quantization
- extended warm-white encoding
- event ambiguity resolution

### Layer 3: Observed State Store

Stores canonical interpreted physical state.

Responsibilities:

- state used for planner, UI, and scene divergence
- already source-normalized
- already profile-decoded

### Layer 4: Scene Reconciliation

Tracks:

- active contracts
- manual latches
- apply revisions
- divergence decisions
- outstanding convergence work

Responsibilities:

- should the scene remain active?
- what channels are owned?
- what is tolerated?
- what has truly diverged?
- what still needs to be dispatched even when scene intent itself has not changed?

### Layer 5: UI

Mostly renders canonical observed state and scene metadata.

Responsibilities:

- show current state
- collect edits
- dispatch user actions

Not responsible for:

- preserving weird crossover values
- deciding how to decode transport ambiguity

## Why This Is Not A Small Refactor

This would be a major redesign.

Reasons:

- state model changes ripple everywhere
- tests would need to be realigned around new boundaries
- the manual testing cost would be high
- some subtle product semantics would need to be re-decided, not merely reimplemented

This is not a "clean up a few modules" effort.

This is more like:

- stabilize current behavior
- preserve regression coverage
- pick a new model
- migrate carefully

That is exactly why this should not be undertaken casually.

## Safer Transitional Moves If This Ever Becomes Active Work

If this architecture reset is ever actually pursued, the safest sequence would likely be:

### Phase 1: Introduce Vocabulary

Without changing behavior yet:

- define explicit concepts for:
  - scene intent
  - observed state
  - controllable intent
  - transport state

Even naming these separately would improve code review and future design.

### Phase 2: Introduce Device Profiles Behind Existing Helpers

Keep the public behavior the same, but start routing:

- projection
- encoding
- decoding
- equivalence

through a device-profile boundary.

### Phase 3: Make Observed State Canonical Enough For UI

Reduce UI-specific correction logic by improving state decoding rather than adding more display preservation rules.

### Phase 4: Replace `brightness_override` With Explicit Contracts Or Latches

This is likely where the biggest scene-behavior simplification would happen.

### Phase 5: Introduce Revision-Based Reconciliation

Only after the state domains are cleaner.

Trying to add revisions on top of the current mixed model would probably add complexity rather than remove it.

## Open Questions

These are the questions that would need deliberate product/architecture decisions before a reset:

1. Should active scenes continue to auto-clear from divergence at all, or should they become more like long-lived "policies" that tolerate more manual activity?
2. Should power ownership be fully explicit per light/component?
3. Is the exact current low-end Z2M warm-white UX worth the complexity, or would a slightly more constrained model be acceptable?
4. Should groups remain command optimization only, with member lights always treated as the physical truth?
5. How much additional explicit state are we comfortable storing if it eliminates timing heuristics?

## Bottom Line

The current code is not complex because the team made bad local decisions.

It is complex because the system keeps asking one shape of data to represent several different realities at once.

The cleanest simplification available is:

- stop collapsing scene intent, physical observation, transport payloads, and UI display into the same flat map
- move source/device-specific logic behind a real profile boundary
- model active scene ownership and reconciliation explicitly instead of inferring it from broad booleans and time windows

If that happened, many of the current "gotchas" would stop being gotchas and would instead become ordinary behavior inside the right layer.

That does not make this a small project.

It does make it a coherent one.
