# Import Reimport and Idempotency

## Goal
Finalize reimport semantics so behavior is predictable and documented under repeated imports.

## Scope
- Guarantee that a reimport with unchanged upstream data and unchanged operator selections is a true no-op.
- Define and document deletion semantics for entities missing/unchecked during reimport.
- Strengthen preservation rules for user-managed fields (`display_name`, `room_id`, `enabled`) under repeated imports.
- Expose import history in a queryable/operator-friendly shape (not only raw blobs).
- Clarify snapshot policy for `bridge_imports` records (mutable review state vs immutable import snapshots).

## Out of Scope
- Full visual diff UI.
- Historical rollback/restore UI.

## Acceptance Criteria
- Reimport is idempotent: if upstream data and operator selections are unchanged, rerunning reimport produces no user-visible or persisted churn.
- Reimport behavior is explicitly documented for checked, unchecked, and missing entities.
- User-managed fields remain stable unless explicitly changed by user action.
- Import history is queryable by bridge/time/status without reading raw blobs directly.
- Tests cover repeated import cycles and deletion edge cases.

## Open Questions
- Should unchecked entities be disabled first, then hard-deleted in a later cleanup step?
- Should `bridge_imports` represent immutable snapshots with separate review/application records?
