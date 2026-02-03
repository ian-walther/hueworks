# Test Coverage Expansion

## Goal
Raise automated coverage with meaningful tests for core domains and the control pipeline.

## Scope (Remaining)
- Control integration tests (mocked bridge clients)
- Subscription/event stream tests (Hue SSE, HA WebSocket, Caseta LEAP)

## Out of Scope (for now)
- Full hardware integration tests
- Performance/load testing

## Files to Touch (likely)
- test/hueworks/*
- test/support/*
- lib/hueworks/schemas/*
- lib/hueworks/*.ex
- lib/hueworks/control/*

## Acceptance Criteria (Remaining)
- Control layer has mocked integration tests for Hue/HA/Caseta
- Subscriptions have tests for event parsing + state updates

## Notes / Open Questions
- Do we want StreamData property tests in this phase?
- Should coverage be enforced via CI or remain local-only for now?
