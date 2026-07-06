# Import & Persistence Implementation Notes

Temporary reconciliation note for `planning/audit/04-import.md`.
Delete this file after the audit doc has been updated to remove or revise the completed items below.

## Implemented

- IM-8 residual characterization tests.
  - Added coverage for ambiguous identity being skipped rather than guessed.
  - Added coverage for `import_hidden_duplicate`, `import_real`, and duplicate-classification drift rollback.
  - Added coverage for mismatched `expected_external_id` rollback.
  - Added coverage for delete cleanup of `scene_component_lights` and `group_lights`.
  - Added coverage for post-commit HA/HomeKit removal effects firing only for destructive resolutions and covering every removed entity.

- IM-2 partial: extracted shared import construction.
  - Added `Hueworks.Import.EntityAttrs` for shared light/group attrs, metadata builders, and hidden-duplicate overlays.
  - Added `Hueworks.Import.Rooms` for shared room upsert and target-room resolution.
  - `Materialize` and `ReimportApply` now consume those shared modules.
  - This removes the duplicated attrs/metadata/room construction code paths that could drift.

- IM-4: extracted shared identifier indexing.
  - Added `Hueworks.Import.IdentifierIndex`.
  - `Import.Link` and `Import.Duplicates` now use the same native identifier index and unique-match semantics.

- IM-5 Caseta portion: import fetcher now consumes the shared Caseta LEAP helper.
  - `Import.Fetch.Caseta` now uses `Hueworks.Control.CasetaLeap` for connect, socket options, request send, and message-mode reads.
  - Send errors now return the same normal endpoint error payload shape instead of silently waiting for a timeout.

- IM-5 Z2M residual: import fetcher now consumes the shared Z2M config/auth helpers.
  - `Import.Fetch.Z2M` now uses `Hueworks.Control.Z2MConfig.for_bridge/1` for broker host/port/base-topic/auth normalization.
  - MQTT auth option construction now flows through `Hueworks.Control.Z2MConfig.tortoise_auth_opts/1`, which delegates to `Hueworks.Mqtt.Options.put_auth/2`.
  - Added focused coverage for `Z2MConfig` normalization and auth option behavior.
  - `Fetch.Common.invalid_credential?/1` was intentionally kept because Hue and Home Assistant import fetchers still call it.

- IM-6: reconciled `planning/import-resync.md` with the implemented backend.
  - Rewrote the doc around remaining review-UI work, future inbox/dedup/reset ideas, and guardrails to preserve.
  - Removed the stale "next major work item" framing and the completed rollout verification procedure.

## Not Implemented

- IM-2 display-name behavior was not changed.
  - `planning/audit/04-import.md` says initial import leaves `display_name` unset, but the current code and `planning/import-resync.md` say the opposite: light/group changesets populate `display_name`, a migration backfills blanks, and `display_name` is HueWorks-owned while bridge `name` refreshes silently.
  - Added characterization for the current documented behavior instead of changing schema/display-name semantics inside a refactor.
  - This needs auditor reconciliation, not a blind code change.

## Auditor Notes

- Red evidence:
  - The attempted audit-directed test for nil `display_name` failed because the schema currently forces `display_name` to the imported name.
  - The test was revised to characterize the current documented `display_name` contract.
- Focused verification:
  - `mix test test/hueworks/import_reimport_apply_test.exs`
  - `mix test test/hueworks/import_reimport_apply_test.exs test/hueworks/materialize_test.exs test/hueworks/import_plan_application_test.exs test/hueworks/import_edge_cases_test.exs test/hueworks/import_json_edge_cases_test.exs test/hueworks/import_json_shape_test.exs`
  - `mix test test/hueworks/link_test.exs test/hueworks/import_identifiers_test.exs test/hueworks/import_reimport_apply_test.exs test/hueworks/materialize_test.exs`
  - `mix test test/hueworks/control_z2m_config_test.exs`
  - `mix test test/hueworks/control_z2m_config_test.exs test/hueworks/import/fetch/common_test.exs test/hueworks/control_z2m_dispatch_test.exs test/hueworks/control_bootstrap_z2m_test.exs test/hueworks/subscription_z2m_event_stream_test.exs`
