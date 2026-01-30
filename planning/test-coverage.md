# Test Coverage Expansion

## Goal
Raise automated coverage with meaningful tests for core domains and the control pipeline.

## Scope
- Changeset validation tests (lights, groups, rooms, scenes, bridges)
- Context tests for list/get/update flows
- Import pipeline edge cases
- Control integration tests (mocked bridge clients)

## Out of Scope (for now)
- Full hardware integration tests
- Performance/load testing

## Files to Touch (likely)
- test/hueworks/*
- test/support/*
- lib/hueworks/schemas/*
- lib/hueworks/*.ex
- lib/hueworks/control/*

## Acceptance Criteria
- Tests exist for all key schema validations and unique constraints
- Context modules have coverage for happy + error paths
- Import pipeline has tests for malformed input and duplicates
- Control layer has mocked integration tests for Hue/HA/Caseta

## Notes / Open Questions
- Do we want StreamData property tests in this phase?
- Should coverage be enforced via CI or remain local-only for now?
