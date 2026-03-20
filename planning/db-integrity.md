# DB Integrity and Query Health

## Goal
Address schema/query risks with clear integrity and query-performance standards.

## Scope
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

## Current Findings
- `bridge_imports` now has a history-oriented index on `[:bridge_id, :imported_at]` to support “latest import for bridge” and operator-facing import-history queries.
- `Hueworks.Bridges` exposes ordered import-history helpers so those query shapes are explicit instead of being rebuilt ad hoc in UI code.
- Current bridge-entity cleanup paths are conservative but consistent with FK behavior:
  - bridge-owned rows cascade from `bridges`
  - join rows also cascade from `lights` / `groups`
  - app-level cleanup currently deletes dependent rows explicitly before deleting entities, which is redundant but not conflicting
- Migration review guidance now lives in `README.md`.

## Open Questions
- Keep current hard-delete semantics for unchecked reimport entities, or move to disable-first?
- Which JSON metadata lookups are stable enough to promote to first-class columns?
