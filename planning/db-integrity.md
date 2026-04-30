# DB Integrity and Query Health

## Goal
Address schema/query risks with clear integrity and query-performance standards.

## Scope
- Audit delete/update paths for consistency between FK behavior and manual cleanup code.
- Keep migration review expectations documented as schema/query patterns evolve.
- Identify JSON-backed lookups that are stable enough to justify promotion to first-class columns.

## Out of Scope
- Full schema redesign.
- Soft-delete model redesign.

## Audit Focus
- delete/update behavior where SQL FKs and app-level cleanup both participate
- JSON metadata lookups that may deserve promotion to first-class columns
- migration review guidance for future schema changes

## Acceptance Criteria
- Cleanup behavior is consistent, with no orphan-prone edge paths between SQL FKs and app-level deletes.
- Migration review docs/checklists exist and are referenced from planning or README docs.

## Open Questions
- Keep current hard-delete semantics for unchecked reimport entities, or move to disable-first?
- Which JSON metadata lookups are stable enough to promote to first-class columns?
