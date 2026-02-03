# Import Resync / Idempotency

## Goal
Make re-import safe and predictable while preserving user edits.

## Scope
- Define upsert rules for re-imports
- Preserve user edits (display_name, room_id, enabled)
- Detect new/removed devices
- Track import history and timestamps

## Out of Scope (for now)
- Full diff UI or historical rollback

## Files to Touch (likely)
- lib/hueworks/import/materialize.ex
- lib/hueworks/import/plan.ex
- lib/hueworks/schemas/bridge_import.ex
- test/hueworks/*

## Acceptance Criteria (Remaining)
- Import history can be queried from DB

## Notes / Open Questions
- How do we represent deleted entities: disabled vs removed?
- Should imports be immutable snapshots?
