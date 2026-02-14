# DB Integrity and Query Health (Remaining)

## Goal
Address remaining schema/query risks now that baseline indices and FKs are in place.

## Scope (Remaining)
- Add targeted indices for high-frequency operational queries not yet covered (for example, import history/status lookups).
- Audit delete/update paths for consistency between FK behavior and manual cleanup code.
- Define migration review checklist for future schema changes (index impact, rollback, data safety).

## Out of Scope
- Full schema redesign.
- Soft-delete model redesign.

## Files to Touch (Likely)
- `priv/repo/migrations/*`
- `lib/hueworks/schemas/*`
- `lib/hueworks/bridges.ex`
- `lib/hueworks/import/*`

## Acceptance Criteria
- `EXPLAIN` on known hot queries shows index-backed plans.
- Cleanup behavior is consistent (no orphan-prone edge paths between SQL FKs and app-level deletes).
- New migration docs/checklist exist and are referenced from planning/readme docs.

## Open Questions
- Keep current hard-delete semantics for unchecked reimport entities, or move to disable-first?
- Which JSON metadata lookups are stable enough to promote to first-class columns?
