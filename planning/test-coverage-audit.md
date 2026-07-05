# Test Coverage Gaps

Forward-looking list only. The whole-code audit found the suite strong overall; add tests for the behavioral gaps below rather than pursuing coverage percentage.

## Current Gaps

- Force and assert the failure behavior of `Scenes.Active.persist_power_overrides/2`; a failed persist currently risks a later circadian tick reverting a manual power override.
- Pair the planned Caseta group-dispatch implementation with its focused regression test from `hueworks_todo.md`.

## Leave Alone

- The control pipeline, all four event streams, scene intent/power policy, circadian reference parity, import/reimport contract matrix, integration subscribers, Pico configuration, scene builder, and manual-control LiveViews already have meaningful boundary coverage.
- Do not add parser permutations or internal implementation tests without a concrete regression or contract gap.
