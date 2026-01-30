# Group Command Batching (Core Value Prop)

## Goal
Implement bridge-aware batching and coordinated execution to eliminate popcorning.

## Scope
- Batch commands by bridge for groups
- Parallel execution across bridges
- Timing coordination for visible consistency
- Error handling for partial failures and offline bridges

## Out of Scope (for now)
- Full planner/diff engine (planned architecture)
- Advanced retries/circuit breakers beyond minimal handling

## Files to Touch (likely)
- lib/hueworks/control/*
- lib/hueworks/groups/*
- lib/hueworks/control/state.ex
- test/hueworks/*

## Acceptance Criteria
- Group action results in single bridge call per bridge
- Multiple bridges are executed in parallel
- Partial failures are surfaced clearly without crashing
- Tests cover batching behavior and failure handling

## Notes / Open Questions
- Do we add a dedicated batching module or keep in control layer?
- What should the error return shape be?
