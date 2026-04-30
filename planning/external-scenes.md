# External Scene Mapping

## Goal
Keep external-scene mapping predictable and low-friction for automation-heavy workflows without inventing a parallel control model.

## Architectural Constraint
This work should stay aligned with `/Users/ianwalther/code/hueworks/planning/architecture-reset.md`:

- external triggers decide upstream intent only
- the integration should enter the existing HueWorks scene pipeline
- external inputs should not bypass desired-state commits or create a second downstream dispatch path

## Remaining Work
- Improve the external-scene config page hierarchy and polish.
- Add clearer empty-state messaging when there are no local HueWorks scenes available to map.
- Add better runtime logging and traceability around external scene activation.
- Consider event dedupe using HA context ids if duplicate service events show up in practice.
- Decide whether one external scene should ever map to multiple HueWorks scenes in a future version.
- Decide whether stale scenes should remain disabled indefinitely or gain explicit cleanup/archive UI.

## Open Questions
- Is one-to-one mapping sufficient beyond the current model, or do we eventually need one external -> many HueWorks scenes?
- Do we want event dedupe using HA context ids?
