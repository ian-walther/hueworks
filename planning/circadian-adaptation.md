# Circadian Validation and Follow-Up

## Goal
Take circadian behavior from "works in real rooms" to "understood, trusted, and easier to evolve" while keeping the implementation aligned with `/Users/ianwalther/code/hueworks/planning/architecture-reset.md`.

## Architectural Constraint
Circadian work should follow the reset architecture:

- circadian logic decides desired target state
- desired-state commits remain the only mutable control target
- planner/executor own retries, convergence, grouping, and downstream reconciliation behavior
- this doc should not be used to justify a second mutable target layer or manual-control-specific runtime ownership above planner/executor

## Locked Decisions
- Circadian config remains scene-level on `light_states.config` for `type: :circadian`.
- Global solar inputs stay global for now; no per-room or per-scene geolocation overrides in v1.
- No smoothing or interpolation engine is required for v1.
- Config key names should continue to track Home Assistant Adaptive Lighting names where practical.
- Scene component power policy continues to use the existing internal enum values:
  - `:force_on`
  - `:force_off`
  - `:follow_occupancy`
- User-facing labels for those policies are:
  - `Default On`
  - `Default Off`
  - `Follow Occupancy`

## Primary Validation Areas

### 1) Per-Light Accuracy vs Room Coherence
Planner behavior still needs a clear product answer when mixed capability/range rooms do not land on one perfectly coherent visual fade.

Question:
- keep exact per-light circadian correctness as the default
- or add a room-coherent mode that intentionally trades some per-light precision for synchronized transitions

### 2) Group Layout Expectations
Circadian behavior can look substantially better when bridge groups line up with capability/range partitions.

Follow-up:
- decide whether grouping guidance is enough
- or whether planner/convergence work should compensate more aggressively for imperfect topology

### 3) Occupancy Input
Occupancy behavior should move toward HA-driven presence input while preserving the existing scene component power-policy semantics.

### 4) Active Scene Persistence vs User Intent
Circadian behavior still needs continued validation around:

- automatic scene deactivation thresholds
- preservation of intentional manual power changes
- whether current retention behavior still feels intuitive over longer daily use

## Out of Scope
- Sleep-mode-specific circadian options
- RGB or adaptive color-mode output
- Per-room or per-scene timezone/geolocation overrides
- A smoothing or interpolation engine
- Migration or backfill tooling

## Testing Follow-Up
- Prioritize real-world validation of:
  - manual -> circadian and circadian -> manual transitions
  - manual off/on semantics while a circadian scene is active
  - active-scene survival during refresh/bootstrap activity
  - mixed temp-range rooms and intentionally overlapping groups
- Keep expanding circadian integration coverage where behavior has proven failure-prone:
  - scene-clear thresholds
  - kelvin clamp/crossover edges
  - compressed-day adaptation windows
  - DST transitions
  - mixed manual + circadian scene components
  - scene edits while active during an ongoing circadian ramp

## Remaining Decisions
- Is log-based observability enough for ongoing production use, or do circadian apply attempts and scene clears need first-class telemetry?
- Does the product actually need a room-coherent circadian mode, or is careful grouping the better long-term answer?
- Once HA-driven occupancy exists, do `Default Off` and `Follow Occupancy` still feel like the right mental model for scene component power policy?
