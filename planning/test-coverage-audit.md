# Test Coverage Gaps

Forward-looking list only. The whole-code audit found the suite strong overall; add tests for the behavioral gaps below rather than pursuing coverage percentage.

## Current Gaps

- Add a direct Hue event-stream stale-index refresh case and a `GenericEventStream` restart/readiness-retry case as specified by CC-5 in `planning/audit/07-cross-cutting.md`.
- Force and assert the failure behavior of `Scenes.Active.persist_power_overrides/2`; a failed persist currently risks a later circadian tick reverting a manual power override.
- Pair the planned Caseta group-dispatch implementation with its focused regression test from `hueworks_todo.md`.
- Add the task-level safety tests specified by CC-10 and CC-11 when the database maintenance and offline import tasks are fixed.

## Test Infrastructure

- Eliminate the intermittent SQLite busy failure and enforce a warnings-zero compile as specified by CC-1 and CC-2 in `planning/audit/07-cross-cutting.md`.

## Leave Alone

- The control pipeline, all four event streams, scene intent/power policy, circadian reference parity, import/reimport contract matrix, integration subscribers, Pico configuration, scene builder, and manual-control LiveViews already have meaningful boundary coverage.
- Do not add parser permutations or internal implementation tests without a concrete regression or contract gap.
