# 06b Web Other Implementation Notes

Temporary reconciliation note for `planning/audit/06b-web-other.md`.
Delete this file after the audit doc has been updated to remove or revise the completed items below.

## Implemented

- WB-21: Light-state editor dirty state now reflects persisted intent only.
  - `update_form` derives dirty state by comparing `light_state_name` and `light_state_config` with the saved baseline.
  - Preview-only changes do not mark the editor dirty.
  - Back to Config and Revert get conditional `data-confirm` protection when dirty.
  - Revert is disabled when the editor is clean and still restores the saved baseline when dirty.
  - Added LiveView coverage for manual dirty edits, circadian config edits, preview-only clean edits, save-to-clean behavior, and revert-to-clean behavior.

- WB-22: Removed stale exploration/web scaffolding.
  - Deleted the broken `/explore` route and stale exploration comments.
  - Removed unused `floating_flash_group/1`.
  - Deleted unused `HueworksWeb.Telemetry`.
  - Removed direct `plug_cowboy`, `telemetry_metrics`, and `telemetry_poller` dependencies and unlocked now-unused Cowboy/Telemetry helper lock entries.
  - Added router route-set coverage proving primary routes remain and `/explore` is absent.

- WB-23: Confirmed deletion of unused light states.
  - The delete control now uses `hw-delete-button`.
  - The confirmation names the light state via the existing label helper and says deletion cannot be undone.
  - Existing in-use disabled behavior and server-side in-use refusal are unchanged.

## Verification

- Red first: `mix test test/hueworks_web/live/light_state_editor_live_test.exs test/hueworks_web/live/config_live_test.exs test/hueworks_web/router_test.exs`
  - Failed on missing dirty confirmations/disabled Revert, stale `/explore`, and missing light-state delete confirmation.
- Green focused suite after fix: same command, `34 passed`.
- Format gate: `mix format --check-formatted`, passed.
- Full suite after WB/CC fixes: `mix test`, `788 passed`.

## Auditor Notes

- `mix deps.unlock --unused` removed `cowboy`, `cowboy_telemetry`, `cowlib`, `plug_cowboy`, `ranch`, `telemetry_metrics`, and `telemetry_poller` from the lock.
