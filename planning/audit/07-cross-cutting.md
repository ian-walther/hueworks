# Audit Chunk 7: Cross-Cutting & Support

Scope: `lib/hueworks/{util,color,kelvin,rooms,groups,lights,instance,app_settings,credentials,debug_logging}*`, `lib/mix/tasks/**`, `config/**`, `test/support/**` — plus the accumulated hygiene/infra backlog below (consolidated here from parked notes in 00/01/02/04 so it lives in one place).
Status: not started as an audit; the pre-collected backlog below is already actionable. Finding IDs will use CC-*.

## Pre-Collected Backlog (from earlier chunks — implementable now)

### CC-1: Test-infra SQLite "Database busy" flake
- Severity: medium (erodes trust in every suite run)
- What: intermittent `Exqlite.Error: Database busy` on INSERTs under the full suite (~1–2 tests on some runs, different tests each time; observed in `scene_builder_component_test` and `import/fetch/common_test`). Pre-existing write contention, not tied to any change.
- Decision: in `config/test.exs`, raise the adapter `busy_timeout` and/or enable WAL journal mode; if insufficient, audit `async: true` on DB-writing suites. Verify with ~10 consecutive full-suite runs.
- Effort: S

### CC-2: Warnings-zero pass
- What: `mix compile` emits a stable set of warnings — dead clauses in `lib/hueworks/schemas/light_state/config.ex` (`existing_atom_or` cond), `lib/hueworks/color.ex` (`round_float` fallback), `lib/hueworks/control/state_parser.ex` (`is_tuple(xy)` always-true conds), `lib/hueworks/kelvin.ex` (`extended_range` always-true guard, unused `get_nested` clause), `lib/mix/tasks/hardware_smoke.ex` (unused `require Logger`, deprecated `Logger.configure_backend`), and `lib/hueworks/homekit/hap_session_handler.ex` (redundant `handle_info` clause).
- Decision: fix all EXCEPT treat the HomeKit HAP handler carefully (protocol code owned by `planning/homekit-control-quality.md` — verify at runtime or leave with a comment rather than mechanically deleting). Then add `--warnings-as-errors` to the compile step used by `mix test` so regressions can't accumulate.
- Also sweep now-dead dual-key clauses left by the atom-key invariant (e.g. `HomeKit.ValueStore` string-power matches).
- Effort: M

### CC-3: Repo hygiene
- What (from initial survey, re-verify current state): local DBs (`hueworks_dev.db`, `hueworks_test.db*`, `hueworks copy.db*`, timestamped copies) and `erl_crash.dump` in the repo root — confirm untracked/gitignored, delete strays; `secrets.env`/`secrets.json` in root — confirm gitignored, consider relocating the documented default path; `exports/` bridge captures with LAN IPs — decide fixtures (move under `test/fixtures/`) vs scratch (delete + ignore).
- Effort: S (mostly `git status`/`.gitignore` work + one owner call on `exports/`)

### CC-4: bridge_host metadata is written but never read
- What: import still writes `metadata["bridge_host"]` on Hue lights/groups (`materialize`/`reimport_apply`/`normalize/hue`); nothing reads it since Hue credentials moved to `bridge_id`.
- Decision: stop writing it (bridge-owned fact reconstructible from `bridge_id`); alternatively keep as inspectable metadata — one-line owner call, default to removal.
- Effort: S

### CC-5: Small test gaps carried forward
- Hue event stream's `maybe_refresh_indexes` — one direct test mirroring the Caseta/HA refresh tests.
- `GenericEventStream` restart-on-DOWN + readiness-retry — one test with a crashing fake connection module.
- Effort: S each

### CC-6: Readiness.bridges_table_ready? relevance check
- What: exists to tolerate boot-before-migration; releases migrate on startup. Verify it still earns its keep for dev `ecto.reset` workflows; keep unless proven dead (it's tiny).
- Effort: S

## Still To Audit (the actual chunk 7 read)

`util.ex` (grab-bag risk: it accumulated parse/normalize helpers all chunks lean on — check for duplication with the newer boundary modules), `color.ex`, `kelvin.ex` (device-profile math — high scrutiny, it encodes the extended-kelvin semantics several features depend on), `rooms.ex`, `groups.ex`, `lights.ex`, `instance.ex`, `app_settings*`, `credentials.ex`, `debug_logging.ex`, `hardware_smoke.ex` + mix tasks, `config/**`, `test/support/**`.
