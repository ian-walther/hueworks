# Import Review UI (Wizard Step)

## Goal
Let users review normalized entities before materialization and apply selective changes.

## Scope
- Show normalized rooms/lights/groups
- Allow accept/decline per entity
- Room merge/override workflow
- Highlight duplicates/conflicts
- Progress + results summary

## Out of Scope (for now)
- Advanced conflict resolution rules
- Full audit trail UI

## Files to Touch (likely)
- lib/hueworks_web/live/config/bridge_setup_live.ex
- lib/hueworks_web/live/config/bridge_setup_live.html.heex
- lib/hueworks/import/plan.ex

## Acceptance Criteria
- User can review and toggle entities before materialization
- Room merge workflow works end-to-end
- Results page clearly shows success/warnings/errors

## Notes / Open Questions
- Should we persist review decisions on each change or only on apply?
