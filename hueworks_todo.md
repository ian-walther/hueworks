# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

This file should stay short. If a future idea is not likely to be acted on soon, leave it out until it becomes real planning work.

## Now

### Reimport Idempotency
Reference: `planning/import-resync.md`

- [ ] Replace the legacy checkbox-shaped reimport review page with explicit diff and resolution controls.
- [ ] Add dependency disclosure and confirmation UI for destructive disable/delete resolutions.
- [ ] Make bridge-owned auto-refresh details inspectable without presenting them as decisions.

### Control Architecture Refactor
Reference: `planning/refactoring.md` and `planning/audit/`

- [ ] Point HA export optimistic-state handling at the shared state-map normalization helper.
- [ ] Split scene-builder state into smaller typed surfaces for membership, embedded manual state, and per-light policy state.
- [ ] Preserve existing behavior with characterization tests before changing semantics.

## Experience Backlog

### Transition Smoothness
Reference: `planning/transition-smoothness.md`

- [ ] Revisit how transition timing feels across scene changes, circadian adaptation, and manual control.
- [ ] Define the desired user experience before choosing implementation details.

### HomeKit Control Quality
Reference: `planning/homekit-control-quality.md`

- [ ] Improve HomeKit behavior beyond reliable on/off control.
- [ ] Define the expected user experience for brightness/color control when no HueWorks scene is active.

## Maintenance Backlog

### Test Coverage Audit
Reference: `planning/test-coverage-audit.md`

- [ ] Audit current test coverage against the code that has changed since the last deliberate coverage pass.
- [ ] Identify meaningful behavior, regression, and integration gaps before adding new tests.

## Concrete Runtime Gaps

- [ ] Implement Caseta group dispatch in `Hueworks.Control.Group`.
- [ ] Add a regression test for the runtime gap above.
