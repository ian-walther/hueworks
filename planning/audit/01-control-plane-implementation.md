# Control Plane Implementation Notes

Temporary reconciliation note for `planning/audit/01-control-plane.md`.
Delete this file after the audit doc has been updated to remove or revise the completed items below.

## Implemented

- CP-3 partial: added the atom-key boundary invariant for control state maps.
  - Added `Hueworks.Control.LightStateSemantics.normalize_keys/1`.
  - `LightStateSemantics.merge_state/2` now canonicalizes known keys before merge/harmonization.
  - Known string keys are normalized to atoms; `temperature` is normalized to `:kelvin`; string/boolean power values are normalized to `:on`/`:off`.
  - Unknown keys are preserved.
  - `State.ensure/3` now normalizes defaults before inserting physical state.
  - `DesiredState.put/4` and `DesiredState.apply/4` inherit normalization through `merge_state/2`.

- CP-3 downstream cleanup, first pass.
  - `GroupState` now reads atom-keyed internal state only.
  - `Planner.Context.diff_light_ids/2` now accepts atom tuple diff keys only.
  - `Planner` explicit-off checks now read `:power` only.
  - `Apply.count_power/2` now reads `:power` only.

## Not Implemented

- CP-3 is not complete.
  - Remaining dual-key/tolerance areas include trace-map reads in `Apply`/`Planner`, HA export message state helpers, some `LightStateSemantics` helper compatibility paths, and external parser boundary code that should remain permissive.
  - Do not treat this as the final CP-3 cleanup; it is only the boundary normalization stage plus a small downstream pass.

- CP-11 remains a documented no-op.

## Auditor Notes

- Added `test/hueworks/control_light_state_semantics_test.exs`.
- Added `test/hueworks/control_desired_state_test.exs`.
- Expanded `test/hueworks/control_state_test.exs`.
- Red evidence: the new boundary tests failed before `normalize_keys/1` and `State.ensure/3` normalization were implemented.
- Focused verification:
  - `mix test test/hueworks/control_light_state_semantics_test.exs test/hueworks/control_desired_state_test.exs test/hueworks/control_state_test.exs`
  - `mix test test/hueworks/control_group_state_test.exs test/hueworks/control_state_test.exs test/hueworks/subscription_home_assistant_event_stream_connection_test.exs test/hueworks/subscription_z2m_handler_test.exs`
  - `mix test test/hueworks/control_planner_test.exs test/hueworks/control_apply_test.exs test/hueworks/control_desired_state_test.exs`
