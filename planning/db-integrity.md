# DB Integrity and Query Health

## Goal
Address schema/query risks with clear integrity and query-performance standards.

## Scope
- Audit delete/update paths for consistency between FK behavior and manual cleanup code.
- Keep migration review expectations documented as schema/query patterns evolve.
- Keep operator-facing history/query access paths explicit instead of rebuilding query shapes ad hoc in UI code.

## Out of Scope
- Full schema redesign.
- Soft-delete model redesign.

## Audit Focus
- delete/update behavior where SQL FKs and app-level cleanup both participate
- import/reimport lifecycle tables and history query shapes
- JSON metadata lookups that may deserve promotion to first-class columns
- migration review guidance for future schema changes

## Files to Touch (Likely)
- `priv/repo/migrations/*`
- `lib/hueworks/schemas/*`
- `lib/hueworks/bridges.ex`
- `lib/hueworks/import/*`

## Acceptance Criteria
- Cleanup behavior is consistent, with no orphan-prone edge paths between SQL FKs and app-level deletes.
- Query shapes that matter operationally are explicit instead of reconstructed ad hoc.
- Migration review docs/checklists exist and are referenced from planning or README docs.

## Open Questions
- Keep current hard-delete semantics for unchecked reimport entities, or move to disable-first?
- Which JSON metadata lookups are stable enough to promote to first-class columns?
