# 07 Cross-Cutting Implementation Notes

Temporary reconciliation note for `planning/audit/07-cross-cutting.md`.
Delete this file after the audit doc has been updated to remove or revise the completed items below.

## Implemented

- CC-1: Increased SQLite test busy timeout.
  - Set the test Repo `busy_timeout` to 10 seconds.
  - The first 10-run verification attempt still found `Database busy` in three DB-writing async modules, so only those modules were made synchronous: `test/hueworks/import/fetch/common_test.exs`, `test/hueworks/control_z2m_config_test.exs`, and `test/hueworks/materialize_test.exs`.
  - Added a test-environment config assertion so the setting stays visible.

- CC-4: Stopped writing stale `bridge_host` metadata.
  - Removed `bridge_host` injection from import materialization attrs.
  - Removed `bridge_host` from Hue normalization metadata.
  - Updated materialize assertions to preserve the smaller metadata contract.

- CC-9: Derived HA export master enablement from final merged settings.
  - `AppSettings.upsert_global/1` now finalizes `ha_export_enabled` after normalized partial attrs are merged with persisted attrs.
  - `HaExportConfig` still owns parsing and the derivation helper.
  - Added a red/green regression for partial toggle updates preserving unrelated enabled sub-toggles.

- CC-11: Used the bounded import-source parser in offline JSON tasks.
  - Added `Hueworks.Import.Source.parse/1`.
  - `mix normalize_bridge_imports` and `mix materialize_bridge_imports` now reject missing/unsupported bridge types without `String.to_atom/1`.
  - `mix materialize_bridge_imports` now prints missing-bridge/find errors.
  - Removed retired `mix link_bridge_imports` from the README pipeline and labeled normalize/materialize as legacy/offline file tools.

- CC-12: Updated tzdata and disabled its network updater in tests.
  - Updated `tzdata` from 1.1.3 to 1.1.4; Hex also updated transitive `mimerl` from 1.4.0 to 1.5.0.
  - Disabled `:tzdata, :autoupdate` in `config/test.exs`.
  - Added a test asserting the updater is disabled and not started in tests.

## Verification

- Red first: `mix test test/hueworks/materialize_test.exs test/hueworks/app_settings_test.exs test/hueworks/import_source_test.exs test/hueworks/import_json_handling_test.exs test/hueworks/test_environment_config_test.exs`
  - Failed on missing busy timeout/tzdata config, missing `Source.parse/1`, stale `bridge_host`, atom-creating task paths, silent missing-bridge materialize errors, and partial HA-export derivation.
- Green focused suite after fix: same command, `50 passed`.
- Format gate: `mix format --check-formatted`, passed.
- Normal full suite after WB/CC fixes: `mix test`, `788 passed`.
- CC-1 first 10-run attempt:
  - Runs 1-2 passed.
  - Run 3 failed with `Database busy` in `Hueworks.Import.Fetch.CommonTest`, `Hueworks.Control.Z2MConfigTest`, and `Hueworks.Import.MaterializeTest`.
- CC-1 retry after making only those three modules synchronous:
  - Runs 1-10 all passed, each with `788 passed`.

## Not Implemented

- CC-2, CC-3, CC-5, CC-7, CC-8, and CC-10 remain open.
- CC-3 is intentionally untouched because deleting ignored local DB/export artifacts is destructive local-machine cleanup.

## Auditor Notes

- Updating `tzdata` recompiled dependencies and emitted third-party warnings from `hackney`, `tzdata`, `timex`, and `solarex`; those are dependency compile warnings, not HueWorks app warnings.
- The expected async Pico sync crash-path error log still appears during full-suite runs; the test passes.
