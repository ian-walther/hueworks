# DB Indices + Integrity

## Goal
Add missing indices and harden schema integrity to avoid performance regressions.

## Scope
- Add listed indices on lights/groups/group_lights
- Add foreign key constraints where missing
- Document index strategy in migrations

## Out of Scope (for now)
- Major schema redesign
- Soft-delete strategy decisions

## Files to Touch (likely)
- priv/repo/migrations/*
- lib/hueworks/schemas/*

## Acceptance Criteria
- Indices exist for the hot query paths
- FK constraints prevent orphaned records
- Migrations include brief rationale comments

## Notes / Open Questions
- Do we want cascade deletes or explicit cleanup?
- Which metadata fields should be promoted to columns?
