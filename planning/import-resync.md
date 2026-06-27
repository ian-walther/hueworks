# Import Reimport and Idempotency

## Goal
Make repeated bridge imports safe, predictable, and boring.

## Priority
This is the next major work item before the control-architecture refactor.

The control refactor targets scene/runtime state seams, while reimport safety lives in import planning, materialization, and persistence. There is no clear ordering dependency where the control refactor makes the reimport work easier.

The product problem is sharper than architecture cleanup: bridge resync should be trustworthy enough that the operator can freely resync to discover new entities without worrying that existing configuration will be mutated or deleted.

## Working Theory
A resync with no operator changes should not change current HueWorks configuration.

The desired trust model is:
- Existing entities default to preserve.
- New entities default to not imported unless explicitly selected.
- Missing entities default to no destructive action unless explicitly removed or disabled.
- User-managed HueWorks fields stay authoritative over newly imported bridge defaults.
- Applying the same upstream import twice with the same operator choices produces no persisted churn.

This may require rethinking the current checkbox/selection model. In current terms, "unchecked" can mean "delete this existing entity," while the desired default experience is closer to "leave existing configuration alone unless I explicitly choose otherwise."

## Scope
- Guarantee that a reimport with unchanged upstream data and unchanged operator selections is a true no-op.
- Define deletion semantics for checked, unchecked, missing, disabled, and removed entities.
- Preserve user-managed fields under repeated imports:
  - `display_name`
  - `room_id`
  - `enabled`
  - `ha_export_mode`
  - `homekit_export_mode`
  - manual kelvin-range overrides
- Preserve scene memberships and group memberships unless the operator explicitly removes an entity.

## Current Implementation Concerns
The current implementation has several places where a reimport can mutate configuration even when the operator is trying to make no meaningful changes.

Observed code-path concerns:
- `HueworksWeb.BridgeSetupLive` applies reimport by updating the review blob, deleting entities, materializing the import, relinking, and marking the import applied in one flow.
- `Hueworks.Import.ReimportPlan` marks existing entities selected by default, new entities unchecked, and missing or unchecked existing entities as deletion candidates.
- `Hueworks.Import.Materialize` updates existing light/group fields from imported data, including `room_id`, capabilities, metadata, external IDs, and `normalized_json`.
- `Hueworks.Import.Materialize` inserts group memberships but does not fully reconcile stale memberships in a clearly no-op-safe way.
- `Hueworks.Import.Materialize` infers group rooms from member lights, which can rewrite group `room_id`.
- `Hueworks.Import.NormalizeFromDb` reconstructs the comparison baseline from stored `normalized_json`, so drift between stored import snapshots and current user-managed fields can hide important differences.

These concerns do not mean the current behavior is wrong in every case. They mean the import path does not yet encode the stronger invariant: a default reimport preview should preserve the existing HueWorks configuration unless the operator explicitly chooses a change.

## Out of Scope
- Full visual diff UI.
- Historical rollback/restore UI.
- Import-history redesign.
- Bridge credential editing.
- Control architecture cleanup unrelated to import safety.

## Implementation Direction
Start by characterizing current behavior with failing tests before changing the import flow.

Likely shape:
- Separate "preserve existing," "import new," "disable," and "delete" into explicit actions instead of overloading checkbox state.
- Compute an import diff before applying anything.
- Make no-op reimport a first-class test fixture and acceptance path.
- Apply user-managed field preservation at the materialization boundary.
- Make deletion/removal paths explicit and hard to trigger accidentally.
- Reconcile memberships deliberately so unchanged imports do not duplicate, stale-retain, or silently remove relationships.

## Acceptance Criteria
- Reimport is idempotent: if upstream data and operator selections are unchanged, rerunning reimport produces no user-visible or persisted churn.
- Reimport behavior is explicitly documented for checked, unchecked, and missing entities.
- User-managed fields remain stable unless explicitly changed by user action.
- Scene/component references survive repeated imports of the same upstream topology.
- Group memberships are not duplicated or silently retained after an explicit removal.
- Default reimport can be safely used to discover new bridge entities without mutating existing HueWorks configuration.
- Tests prove no-op behavior across lights, groups, room assignments, memberships, scene/component references, and user-managed fields.
- Tests cover repeated import cycles, preservation rules, and deletion edge cases.

## Open Questions
- Should unchecked entities be disabled first, then hard-deleted in a later cleanup step?
- Should missing upstream entities be disabled by default instead of immediately staged for deletion?
- What UI language makes "preserve existing," "add new," "disable," and "delete" unambiguous?
- Should bridge-reported room changes ever automatically move existing HueWorks entities, or should room movement be an explicit operator choice?
