# Refactoring Targets

## Goal
Reduce code complexity without reducing feature complexity.

This document is for the current control-architecture refactor only. Do not use it as a general dumping ground for future nice-to-have cleanup.

## Architectural Constraint
Follow the rules in `/Users/ianwalther/code/hueworks/planned_architecture.md`.

In particular:
- upstream layers decide intent
- `DesiredState` is the only mutable target plane
- planner/executor own hardware-facing behavior
- observed physical state is not a second source of truth

## Current Refactor Pass

### 1) Extract Scene Power Policy Semantics
Current smell:
- `Default On`, `Default Off`, `Force On`, `Force Off`, and `Follow Presence` parsing/resolution is spread across scene intent, scene persistence, and scene-builder UI state.

Target shape:
- one domain module owns policy parsing, labels, defaulting, override behavior, and presence resolution
- persistence and UI call that module rather than reimplementing the vocabulary
- scene intent consumes already-normalized policy semantics

Guardrails:
- start with characterization tests for current behavior
- do not change scene storage shape in this pass
- do not weaken `force_on`, `force_off`, or `follow_presence` semantics while extracting

### 2) Centralize State-Map Normalization
Current smell:
- physical state, desired state, and HA export command handling each know how to merge incoming state and drop stale kelvin/xy keys.

Target shape:
- one lower-level state semantics helper owns color/temperature harmonization
- desired-state and physical-state writers call the same helper
- HA export command handling uses the same helper for optimistic state

Guardrails:
- preserve current atom-keyed public behavior
- keep external payload parsing at integration boundaries
- avoid broad rewrites of state parser behavior in this pass

### 3) Split Scene Builder State
Current smell:
- `lib/hueworks_web/live/scene_builder_component/state.ex` combines component membership, embedded manual config, nested group presentation, and per-light power policy state.

Target shape:
- smaller modules for component membership, embedded manual state, and per-light/group policy editing
- LiveView event flow stays thin and delegates to these helpers
- tests assert behavior through existing LiveView/component flows where practical

Guardrails:
- preserve the current UI behavior while extracting
- keep recursive group presentation intact
- avoid introducing shared UI components until the state boundary is clearer

## Testing Rule
When refactoring changes a seam, prefer relocating assertions to the right public boundary over preserving an outdated internal contract.
