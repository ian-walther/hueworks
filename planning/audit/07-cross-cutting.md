# Audit Chunk 7: Cross-Cutting & Support

Scope: `lib/hueworks/{util,color,kelvin,rooms,groups,lights,instance,app_settings,credentials,debug_logging}*`, `lib/mix/tasks/**`, `config/**`, `test/support/**` — plus the accumulated hygiene/infra backlog below (consolidated here from parked notes in 00/01/02/04 so it lives in one place).
Status: audit complete. Tracker:

| Sub-area | Status |
|----------|--------|
| Pre-collected backlog (CC-1..CC-5; CC-6 resolved leave-alone) | audited |
| `util`, `color`, `kelvin` | audited line-by-line |
| `rooms`, `groups`, `lights`, `instance`, `credentials`, `debug_logging` | audited line-by-line |
| `app_settings` boundary modules | audited line-by-line |
| mix tasks, `mix.exs`, config, test support, final hygiene/dependency pass | audited line-by-line |

## Pre-Collected Backlog (from earlier chunks — implementable now)

### CC-1: Test-infra SQLite "Database busy" flake
- Severity: medium
- Type: test-infra
- Where: `config/test.exs`; DB-writing async suites including `test/hueworks_web/components/scene_builder_component_test.exs` and `test/hueworks/import/fetch/common_test.exs`
- What: intermittent `Exqlite.Error: Database busy` on INSERTs under the full suite (~1–2 tests on some runs, different tests each time; observed in `scene_builder_component_test` and `import/fetch/common_test`). Pre-existing write contention, not tied to any change.
- Why: nondeterministic infrastructure failures erode confidence in every regression run and can obscure failures introduced by real changes.
- Decision: set the test Repo's `busy_timeout` to 10 seconds in `config/test.exs`; Ecto SQLite already enables WAL by default, so do not duplicate that configuration. Verify with 10 consecutive full-suite runs. If any busy failure remains, identify the DB-writing `async: true` cases from those runs and make only those modules synchronous.
- Guardrails: do not serialize the whole suite preemptively or mask non-busy database errors. Record all 10 run results in the implementation receipt.
- Effort: S

### CC-2: Warnings-zero pass
- Severity: low
- Type: hygiene
- Where: `lib/hueworks/schemas/light_state/config.ex`, `lib/hueworks/color.ex`, `lib/hueworks/control/state_parser.ex`, `lib/hueworks/kelvin.ex`, `lib/mix/tasks/hardware_smoke.ex`, `lib/hueworks/homekit/hap_session_handler.ex`, `mix.exs`
- What: `mix compile` emits a stable set of warnings — dead clauses in `lib/hueworks/schemas/light_state/config.ex` (`existing_atom_or` cond), `lib/hueworks/color.ex` (`round_float` fallback), `lib/hueworks/control/state_parser.ex` (`is_tuple(xy)` always-true conds), `lib/hueworks/kelvin.ex` (`extended_range` always-true guard, unused `get_nested` clause), `lib/mix/tasks/hardware_smoke.ex` (unused `require Logger`, deprecated `Logger.configure_backend`), and `lib/hueworks/homekit/hap_session_handler.ex` (redundant `handle_info` clause).
- Why: dead branches conceal the actual accepted shapes and let new compiler diagnostics disappear into background noise.
- Decision: simplify each warned branch to the compiler-proven reachable shape and remove the unused Logger code. For `HAPSessionHandler`, replace its catch-all delegation with exact delegation clauses for Bandit's `{:plug_conn, :sent}` and normal `{:EXIT, pid, :normal}` messages so ThousandIsland's generated socket/timeout clauses remain reachable. Sweep now-dead dual-key clauses left by the atom-key invariant (including `HomeKit.ValueStore` string-power matches). Then set test-environment `elixirc_options` in `mix.exs` to treat warnings as errors.
- Guardrails: add focused HAP session-handler tests for the two delegated Bandit messages and retain existing HomeKit session/transport tests; do not delete generated/protocol clauses or expand HomeKit product behavior. Require `mix compile --force` and the full suite to pass warning-free before enabling enforcement.
- Effort: M

### CC-3: Repo hygiene
- Severity: low
- Type: hygiene
- Where: ignored files in the repository root and `exports/`; `.gitignore`; documented `secrets.json` path in `README.md` and `docker-compose.yml`
- What: the final survey confirmed the repo root still physically contains `erl_crash.dump`, development/test/copy databases and sidecars, and a timestamped development DB copy. `exports/` contains eight dated raw/normalized bridge captures whose filenames disclose LAN IPs. All are correctly ignored and none appears in `git status`, but they are stale operational artifacts mixed into the source checkout. `secrets.env` and `secrets.json` are also present but correctly ignored; keep `secrets.json` at the documented root default because Docker Compose deliberately mounts it from there.
- Why: ignored artifacts cannot be committed accidentally, but stale databases/crash dumps obscure which local state is active and real-network captures do not belong in a durable source checkout.
- Decision: delete the current crash dump, root DB copies/sidecars, and dated `exports/` captures after confirming no local process needs them; retain the existing ignore rules so runtime/test artifacts cannot become tracked. Leave the ignored secrets files and documented default path unchanged.
- Guardrails: this is local cleanup, not fixture migration. Do not move bridge captures into `test/fixtures/`; tests do not consume them and their real network metadata does not belong in the repository. Do not print or inspect secret contents.
- Effort: S

### CC-4: bridge_host metadata is written but never read
- Severity: low
- Type: hygiene
- Where: `lib/hueworks/import/entity_attrs.ex`, `lib/hueworks/import/normalize/hue.ex`, and bridge-host assertions in `test/hueworks/materialize_test.exs`
- What: import still writes `metadata["bridge_host"]` on Hue lights/groups (`materialize`/`reimport_apply`/`normalize/hue`); nothing reads it since Hue credentials moved to `bridge_id`.
- Why: duplicating bridge identity in entity metadata makes a stale, non-authoritative network address look load-bearing and contradicts the bridge-owned credential path.
- Decision: stop writing it. The bridge-owned fact is reconstructible from `bridge_id`, and retained normalized import blobs remain the right debugging record; do not migrate old metadata solely to remove existing copies.
- Guardrails: update materialize/normalize assertions to the smaller metadata contract and retain `control_hue_bridge_test.exs` coverage proving stale historical `bridge_host` data is ignored. Do not remove other Hue identity/capability metadata.
- Effort: S

### CC-5: Small test gaps carried forward
- Severity: low
- Type: test-gap
- Where: `lib/hueworks_app/subscription/hue_event_stream.ex`, `lib/hueworks_app/subscription/generic_event_stream.ex`; corresponding stream tests under `test/hueworks/`
- What: Hue's `maybe_refresh_indexes` lacks the direct stale-index case already present for Caseta/HA, and `GenericEventStream` lacks a direct restart-on-DOWN plus readiness-retry test with a crashing connection module.
- Why: these are shared self-healing behaviors at a runtime boundary; direct tests keep future stream consolidation from silently weakening Hue or generic restart behavior.
- Decision: add one Hue stale-index refresh test mirroring the Caseta/HA reference cases and one `GenericEventStream` test using a crashing fake connection plus a controllable readiness callback to prove delayed retry and restart after DOWN.
- Guardrails: test observable reconnect/index-refresh behavior rather than private callbacks or exact timer internals; keep the existing per-bridge connection suites unchanged.
- Effort: S each

## Findings From The Chunk-7 Read

### CC-7: Enforce canonical-light topology through every update path
- Severity: high
- Type: bug-risk
- Where: `lib/hueworks/lights.ex:48-83`; `lib/hueworks_web/live/lights_live/editor.ex:89-102,110-142`; invariant tests in `test/hueworks/contexts_test.exs:167-193,494-508`
- What: `Lights.update_link/2` rejects linking a light that has linked dependents and rejects non-root targets, preventing canonical-link chains. The actual Lights editor does not call it: `Editor.save/3` includes `canonical_light_id` in the attrs passed to `Lights.update_display_name/2`, which writes the field through `Light.changeset` without either topology check. The selector hides non-root targets, but a root that already has dependents can still be linked through the normal UI, and crafted params can name any root/non-root ID. This persists a graph shape the dedicated public API and downstream controllable-light projections explicitly forbid.
- Why: canonical links are a state/topology invariant, not presentation validation. Letting one context entry point bypass it can corrupt the optimization projection and make linked lights disappear or resolve through unsupported multi-hop chains.
- Decision: centralize link-change validation inside the general `Lights` update path whenever `:canonical_light_id` is present. `Lights.update_display_name/2` (rename internally if useful, but preserve the public surface) must apply the same no-dependents, root-target, and self-link checks before the changeset write; make `update_link/2` delegate to that single validated path rather than owning a second copy. Keep all other light attrs and HA/HomeKit post-update effects in the same successful update.
- Guardrails: reproduce red first in `test/hueworks/contexts_test.exs` by sending `canonical_light_id` through `update_display_name/2` for both a light with dependents and a non-root target; retain the existing `update_link/2` tests. Add a full editor regression in `test/hueworks_web/live/lights_live_pipeline_test.exs` proving the save event cannot turn a canonical root with dependents into a child. Valid root linking and unlinking must remain green.
- Effort: S

### CC-8: Make group room cascades atomic and republish every moved HA entity
- Severity: medium
- Type: bug-risk
- Where: `lib/hueworks/groups.ex:52-120`; Home Assistant discovery embeds room identity in `lib/hueworks/home_assistant/export/messages/discovery.ex:120-127,171-178`
- What: changing a group's `room_id` first updates the root group, then performs separate `update_all` calls for its subgroups and member lights outside a transaction. Afterward it calls `HomeAssistantExport.refresh_group/1` only for the root. A mid-cascade database failure can leave topology split across rooms; on success, every moved subgroup/light retains stale Home Assistant discovery `device`, `hueworks_room_id`, and `room_name` data until an unrelated full republish. HomeKit avoids the latter only because it performs a full reload.
- Why: room membership is shared topology, so the root/subgroup/member-light move must commit as one unit. Integration exports should reflect committed domain state; stale room device grouping is silent external divergence caused by the context's incomplete post-commit fan-out.
- Decision: when `room_id` is present, compute the affected subgroup and member-light IDs once, update the root/subgroups/lights in one `Repo.transaction`, and perform external side effects only after commit. Refresh Home Assistant discovery for the root plus every affected subgroup and member light (deduplicated); retain one HomeKit reload. Non-room attribute updates should keep the current single-entity refresh behavior.
- Guardrails: characterize the existing propagation and add rollback coverage in `test/hueworks/contexts_test.exs`; add an export-sink assertion in `test/hueworks/home_assistant_export_test.exs` that a group room move republishes discovery for an affected subgroup and member light with the new room identity. Preserve `Groups.Topology` subgroup semantics and do not turn HA publishing into part of the DB transaction.
- Effort: M

### CC-9: Derive HA export master enablement from the fully merged settings
- Severity: medium
- Type: bug-risk
- Where: `lib/hueworks/app_settings.ex:23-58,102-119`; `lib/hueworks/app_settings/ha_export_config.ex:40-45,97-106`
- What: `AppSettings.upsert_global/1` is a partial-update API, but `HaExportConfig.normalize/1` recomputes `ha_export_enabled` from only the sub-toggle keys present in the incoming attrs. If persisted settings have scenes enabled and a caller submits only `%{ha_export_lights_enabled: false}`, the boundary sees one false toggle, writes `ha_export_enabled: false`, then merges that into a base that still has `ha_export_scenes_enabled: true`. The row becomes internally inconsistent and the legacy master flag disables the HA export runtime despite an enabled feature toggle.
- Why: derived state must be calculated from the final merged source fields, not a partial patch. This is a boundary-normalization invariant; the current order makes an otherwise safe narrow update silently change unrelated runtime behavior.
- Decision: keep `HaExportConfig` responsible for parsing fields, but move/finalize sub-toggle derivation in `AppSettings.upsert_global/1` after normalized updates are merged with current attrs. Recompute `ha_export_enabled` from all three final sub-toggles when any sub-toggle was present in the incoming update; when no sub-toggle is present, preserve an explicitly supplied legacy `ha_export_enabled` value and otherwise retain the current value.
- Guardrails: add a red regression in `test/hueworks/app_settings_test.exs` that starts with scenes enabled, applies a patch containing only `ha_export_lights_enabled: false`, and asserts the master/scenes flags remain true while lights becomes false. Also cover the inverse partial-enable case and preserve the existing all-toggle ConfigLive behavior and blank-password tests.
- Effort: S

Assessment so far: `SolarConfig`, `HaExportConfig`, and `HomeKitConfig` are correctly placed boundary modules that accept mixed external attrs and emit atom-keyed changeset input. `AppSettings` preserves absent fields, caches only successful writes, and keeps the flat persisted schema behind those boundaries. CC-9 is an ordering error in derived-state finalization, not a reason to collapse the boundary modules.

### CC-10: Replace destructive database "backup" and unsafe restore tasks
- Severity: high
- Type: bug-risk
- Where: `lib/mix/tasks/backup_db.ex`; `lib/mix/tasks/restore_db.ex`; task listing in `README.md:221-223`
- What: `mix backup_db` uses `File.rename/2` for the database and WAL/SHM files, so it moves the live database away instead of creating a backup. A subsequent application start can create a fresh empty DB at the configured path. `mix restore_db` selects a backup, deletes the current DB and sidecars before validating the backup, then consumes the only backup by renaming it into place. Neither task creates a recovery copy or guards against an active HueWorks process writing the SQLite files.
- Why: these task names promise data safety but implement destructive file moves around a WAL database. The failure modes are complete loss of the current database, an inconsistent snapshot, or loss of both current and backup copies during a partial restore.
- Decision: implement backup as a consistent SQLite snapshot using `VACUUM INTO` through `Exqlite.Sqlite3` (never rename or delete the source). Implement restore as an explicit `--force` operation that first opens the selected backup read-only and requires `PRAGMA integrity_check` to return `ok`, copies it to a temporary file in the destination directory, preserves the current DB as a timestamped pre-restore recovery copy, and atomically renames the validated temp file into place; retain the source backup. Refuse restore when the local Repo/application is running and document that any separately running HueWorks service must be stopped.
- Guardrails: add temp-directory integration coverage in `test/mix/tasks/backup_restore_db_test.exs` proving backup leaves the source intact and readable, includes committed WAL data, restore rejects corrupt input without touching the current DB, and successful restore preserves both the original backup and a pre-restore recovery copy. Update the README task descriptions with the stop-service/`--force` contract.
- Effort: M

### CC-11: Use the bounded import-source parser in offline JSON tasks
- Severity: low
- Type: bug-risk
- Where: `lib/mix/tasks/normalize_bridge_imports.ex:42-68`; `lib/mix/tasks/materialize_bridge_imports.ex:36-70`; `README.md:215-219`
- What: both tasks call `String.to_atom/1` on the `bridge.type` value read from JSON. These are external files and can create arbitrary permanent VM atoms; they also accept unsupported sources until a later failure. `materialize_file/1` silently returns an unmatched `{:error, message}` from `find_bridge/1` without printing it. The README still advertises `mix link_bridge_imports` as a normal pipeline step even though that task deliberately raises as retired.
- Why: import source vocabulary is already centralized and bounded by `Hueworks.Import.Source.normalize/1`; bypassing it recreates the exact external-string atom leak removed elsewhere in IM-3/WB-14. Silent CLI failures and retired documentation make an already-dangerous offline workflow harder to reason about.
- Decision: replace both `to_bridge_type` helpers with `Import.Source.normalize/1`, reject nil/unsupported source values with a clear per-file error, and ensure every `find_bridge` error is printed. Remove `link_bridge_imports` from the README pipeline and label normalize/materialize as offline legacy/file tools; manual bridge reimport remains the supported application workflow.
- Guardrails: add focused task/helper coverage under `test/mix/tasks/` for all four supported source strings, an unsupported random string (without creating an atom), and visible missing-bridge/invalid-source errors. Do not change the normalized JSON shape or the scoped manual-reimport path.
- Effort: S

### CC-12: Update tzdata and keep its network updater out of tests
- Severity: medium
- Type: dependency / test-infra
- Where: `mix.lock` (`tzdata` 1.1.3); `config/test.exs`; dependency default in `deps/tzdata/mix.exs:45`
- What: one otherwise-green 777-test run emitted a background `Tzdata.ReleaseUpdater` crash at `:calendar.time_to_seconds({24, 0, 0})` from `Tzdata.PeriodBuilder.datetime_to_utc/3`. The failure is exact, not speculative: tzdata 1.1.4's changelog says it fixes the OTP 29 `:calendar` crash for IANA `24:00` transition times, while this repo locks 1.1.3. Independently, tzdata's daily network updater is enabled by default in every environment, so the test application can make an external release check and mutate timezone data during an otherwise hermetic suite.
- Why: the upstream parser crash kills a supervised background process and can affect runtime timezone updates; allowing an unrelated network poll in tests adds nondeterminism even after the parser is fixed.
- Decision: update the lock to tzdata 1.1.4 within the existing `~> 1.1` constraint. Add `config :tzdata, :autoupdate, :disabled` only in `config/test.exs`; keep automatic updates enabled in development and production so long-running HueWorks instances still receive IANA data updates.
- Guardrails: retain Timex/timezone behavior and do not globally disable tzdata updates. After the dependency change, run the timezone-dependent focused tests and the full suite repeatedly; verify no updater process is started under `MIX_ENV=test` and that normal application startup still includes it outside tests.
- Effort: S

## Overall Assessment

The support layer is generally disciplined. `Util` is a bounded collection of display and external-input helpers rather than a shadow domain layer. `Color` and `Kelvin` encode intentional, well-tested device-profile transformations; their extended-range and inverse-mapping behavior should remain centralized there. `Rooms`, `Instance`, and `Credentials` keep persistence and runtime effects behind contexts, while the solar, HomeKit, and Home Assistant settings modules form useful input boundaries. The actionable exceptions are narrow invariant/transaction ordering bugs (CC-7..CC-9), unsafe maintenance tooling (CC-10/11), and accumulated infra hygiene (CC-1..CC-5/12), not a need for another broad architectural rewrite.

Explicitly fine: `Readiness.bridges_table_ready?/0` remains a small, justified guard for development reset/migration races; the pre-collected CC-6 question is resolved with no change. The hardware smoke task's explicit environment gate is the right safety boundary; only its warning/deprecated logger calls need cleanup. Test support keeps external integrations disabled and supplies conventional sandbox helpers. Runtime config validates required release inputs and keeps secrets outside committed configuration.
