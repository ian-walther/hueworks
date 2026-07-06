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

Note: this doc's remaining items are being absorbed into the audit backlog in `planning/audit/` (see `00-plan.md`); new refactor targets belong there.

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
