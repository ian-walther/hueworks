# Import Reimport and Idempotency (Remaining)

## Goal
Finalize reimport semantics so behavior is predictable and documented under repeated imports.

## Scope (Remaining)
- Define and document deletion semantics for entities missing/unchecked during reimport.
- Strengthen preservation rules for user-managed fields (`display_name`, `room_id`, `enabled`) under repeated imports.
- Expose import history in a queryable/operator-friendly shape (not only raw blobs).
- Clarify snapshot policy for `bridge_imports` records (mutable review state vs immutable import snapshots).

## Out of Scope
- Full visual diff UI.
- Historical rollback/restore UI.

## Files to Touch (Likely)
- `lib/hueworks/import/materialize.ex`
- `lib/hueworks/import/reimport_plan.ex`
- `lib/hueworks/import/normalize_from_db.ex`
- `lib/hueworks/schemas/bridge_import.ex`
- `lib/hueworks_web/live/config/bridge_setup_live.ex`
- `test/hueworks/import_reimport_plan_test.exs`
- `test/hueworks/import_plan_application_test.exs`

## Acceptance Criteria
- Reimport behavior is explicitly documented for checked, unchecked, and missing entities.
- User-managed fields remain stable unless explicitly changed by user action.
- Import history is queryable by bridge/time/status without reading raw blobs directly.
- Tests cover repeated import cycles and deletion edge cases.

## Open Questions
- Should unchecked entities be disabled first, then hard-deleted in a later cleanup step?
- Should `bridge_imports` represent immutable snapshots with separate review/application records?
