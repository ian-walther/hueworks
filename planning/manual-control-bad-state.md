# Manual Control Bad-State Investigation

## Problem
There is an intermittent manual-control failure mode, observed most often with Hue-driven group actions, where a manual toggle appears to do nothing and then later converges without a clean explanation.

## Current Working Theory
The right next step is still observability, not behavior change.

The most plausible buckets are:
- downstream Hue bridge or device latency / temporary bad state
- delayed executor reconciliation after the initial dispatch
- planner regrouping interacting badly with stale physical state

None of those is isolated well enough yet to justify planner changes or manual-group special-casing.

## Recommended Next Debugging Step
Add trace-only observability around manual actions and reconciliation.

Specifically capture:
- clicked target type and id from the UI
- requested light ids
- desired snapshot for those lights
- physical snapshot for those lights
- planner `actionable_diff_light_ids`
- final planned actions:
  - `type`
  - `id`
  - `bridge_id`
  - `desired`
- executor dispatch start and end timing
- convergence retry events
- eventual physical-state update timing

Primary question to answer:
- when a manual group or light "fails", what action did HueWorks actually send, and what retries or late physical updates followed?

## Recommended Non-Code Experiments
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
