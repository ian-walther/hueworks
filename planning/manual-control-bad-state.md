# Manual Control Bad-State Investigation

## Summary
There is an intermittent manual-control failure mode, observed mostly with Hue bulbs, where a light or smaller group does not respond immediately to a manual toggle from HueWorks.

The system does not appear to enter a permanently poisoned state.

The most recent observation is:
- a manual toggle can appear to fail
- HueWorks UI does not immediately reflect a state change
- the affected light can later turn on by itself after roughly tens of seconds
- once it does, HueWorks control becomes responsive again

This currently feels like a minor annoyance rather than a system-stability emergency, so this doc is intended to preserve the current understanding without forcing an immediate fix.

## Observed Behavior

### Initial Observations
- Manual controls sometimes fail.
- When this happens, the affected lights seem to enter a bad state where direct controls stop working.
- Toggling another group that also contains those lights often seems to recover them.
- The UI does not report the state as having changed when the initial toggle appears to fail.

### Later Refinements
- The problem is observed mostly while controlling groups, not individual lights.
- The common pattern is:
  - a smaller group fails
  - a larger overlapping group can recover the same Hue bulbs
- A direct single-light toggle in HueWorks did **not** immediately unstick an affected Hue bulb.
- In one captured case, the light recovered by itself after about 30 seconds, without needing another manual group toggle.

## Current Hypotheses

At the moment there are three plausible explanations. The evidence does not fully isolate one yet.

### 1. Hue bridge/device/reporting latency or temporary bad state
This is the strongest current candidate.

Why:
- the light eventually became responsive again without another manual intervention
- that suggests a delayed command apply, delayed bridge recovery, or delayed physical/reporting convergence
- Hue bulbs are the main offenders in the observed failures

What this would mean:
- HueWorks may be behaving correctly in intent/retry terms
- the downstream Hue bridge or bulbs may temporarily ignore, delay, or defer application of a command

### 2. HueWorks reconciliation eventually succeeds after a delay
This is also plausible.

Why:
- the executor schedules convergence checks and can enqueue recovery actions after a dispatch succeeds
- the code path is in:
  - `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex`
- relevant functions:
  - `handle_info({:verify_convergence, action}, state)`
  - `recovery_actions_for/2`
  - `maybe_schedule_convergence_check/2`

What this would mean:
- the initial action does not fully converge
- executor rechecks and replans against current desired state
- a later recovery action eventually lands successfully

Important nuance:
- the checked-in fallback convergence delay is short, not ~30 seconds
- relevant code:
  - `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex:578`
  - `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/executor.ex:584`
- so if the observed delay is truly around 30 seconds and repeatable, there may be:
  - a runtime override not reflected in repo config, or
  - downstream Hue delay rather than executor timing

### 3. Planner/group-selection behavior contributes to the failure pattern
This still looks suspicious, but it no longer seems sufficient by itself to explain the full behavior.

Why it was initially suspicious:
- manual group actions do **not** preserve the exact clicked group
- the UI passes only member `light_ids` into manual control:
  - `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex:283`
- manual control then commits desired state by light id:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex:65`
- the planner is then free to re-derive an optimized group action from overlapping room groups:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex:136`
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex:257`

What was suspicious:
- a smaller group failing and a larger overlapping group recovering it felt software-shaped

Why this is now a weaker primary explanation:
- when a light later turns on by itself, that implies something did eventually retry, apply, or recover
- a pure "planner decided there was no action" explanation does not naturally explain delayed later success

## Important Code Findings

### Manual control commits desired state before planning
- `/Users/ianwalther/code/hueworks/lib/hueworks_app/control/desired_state.ex:66`

This means:
- desired state can advance even if physical state has not converged yet
- later reconciliation behavior depends heavily on physical state freshness

### Explicit `off` is always actionable, `on` is not
- `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex:307`

Specifically:
- explicit off intents are kept actionable even if physical already appears off
- non-off actions depend on `desired_differs_from_physical?`
- if physical state is stale and incorrectly looks like the desired on-state, the planner can suppress follow-up action

This is still an important potential contributor whenever Hue reporting is stale.

### Single-light UI actions are not guaranteed to stay single-light at dispatch
- manual light path:
  - `/Users/ianwalther/code/hueworks/lib/hueworks_web/live/lights_live.ex:270`
- planner regrouping:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex:129`
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/planner.ex:153`

This means:
- a click on one light in the UI does **not** prove we sent a `/lights/:id/state` Hue request
- the planner may still choose a group action if that is the optimized outcome

### Hue light and Hue group dispatch go to different endpoints
- light dispatch:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/light.ex:39`
  - `/lights/#{light.source_id}/state`
- group dispatch:
  - `/Users/ianwalther/code/hueworks/lib/hueworks/control/group.ex:37`
  - `/groups/#{group.source_id}/action`

This matters because:
- if the planner chooses a different action type than expected, the Hue bridge may behave differently even though the UI action looked similar

## What We Know So Far
- The issue is real.
- It seems more visible with Hue bulbs than with other bridges.
- The system does not appear to corrupt itself permanently.
- There is currently **not** enough evidence to justify changing planner architecture or preserving manual group identity as a special-case exception.
- The safest next step is observability, not behavior change.

## Recommended Next Debugging Step

Add trace-only observability around manual actions and reconciliation.

Specifically capture:
- clicked target type/id from the UI
- requested light ids
- desired snapshot for those lights
- physical snapshot for those lights
- planner `actionable_diff_light_ids`
- final planned actions:
  - `type`
  - `id`
  - `bridge_id`
  - `desired`
- executor dispatch start/end timing
- convergence retry events
- eventual physical-state update timing

This should answer the key unresolved question:
- when a small group or single light "fails", what action did HueWorks actually send, and what retries did it later perform?

## Recommended Non-Code Experiments

If the issue becomes worth digging into again before adding traces:

1. When a light is in the bad state, try toggling it from the Hue app directly.
- If Hue app also cannot unstick it, that strongly implicates bridge/device state.
- If Hue app works immediately while HueWorks does not, that strongly implicates HueWorks planning/dispatch/reconcile behavior.

2. Note whether the spontaneous recovery delay is consistent.
- If it happens after a repeatable interval, compare that interval to runtime executor retry timing.
- If it is highly variable, that points more toward downstream Hue behavior.

## What Not To Do Yet
- Do not change planner architecture yet.
- Do not special-case manual groups to preserve the clicked group identity yet.
- Do not treat this as proven hardware-only behavior yet.

Those may become the right moves later, but the evidence is not clean enough yet to justify them.
