# Chunk 3 — Domain Contexts

Status: CLOSED. DM1-DM17 implemented and reconciled (DM5 refuted). No open findings.

Coverage: line-by-line for `api.ex`, all of `scenes/`, `circadian.ex`, `picos/{actions,bindings,targets,control_groups}.ex`, `homekit/{bridge,value_store,accessory_graph}.ex`, `groups/topology.ex`, `lights/manual_control.ex`, `active_scenes.ex`, `schemas/bridge/credentials.ex`. Structural scan + targeted greps for: remaining picos files, remaining homekit files, `circadian/config.ex` + `circadian_preview.ex`, `app_settings/**`, remaining schemas, `bridges.ex`, `external_scenes/spaces`, `onboarding/`, `presence_inputs`, small top-level modules, and the ops/diagnostic trio (`hardware_smoke`, `database_maintenance`, `release` — deliberately light scrutiny, nothing alarming surfaced). Chunk tests: not separately audited; guardrail tests were checked at finding sites.

## Explicitly Fine / Leave-Alone

- **`api.ex` as a whole** — deliberately verbose projection layer; the moduledoc states the design intent. `bridge_reported_state` duplicating `physical_state` is documented in-line as deliberate.
- **`Util` public surface** — every function has ≥1 real caller (grep-verified). `Util.existing_atom/1` (added by DM1) is the shared safe-conversion helper.
- **Bare `String.to_existing_atom` in `Import.ReviewPlan`, `ConnectionTest.Z2M`, `IntegrationsConfigLive`** — intentionally *not* converted to `Util.existing_atom/1`: these convert internal vocabulary/known keys and should crash loudly on unknown values. The original DM1 write-up overcounted these as instances of the rescue-to-nil pattern; they never were. Do not re-flag.
- **`Scenes.Active` pipe/`then` style** (was DM5) — refuted: style-only rewrite with no complexity reduction, out of scope per `00-plan.md`. Do not re-flag `|> then(&...)`/pipe-into-case anywhere unless it hides real indirection.
- **`Scenes.Apply`** — thin orchestration. `log_trace` string-key fallbacks marginal but harmless.
- **`Intent` power-latch / power-policy ladder** — every branch is real product semantics. The typed `DesiredAttrs` boundary stays (DM4 removed only dead clauses around it).
- **`PowerPolicy`** — reference vocabulary; legacy-value `parse` clauses guard real persisted data shapes.
- **`Scenes.Builder` / `Scenes.Persistence`** — fine.
- **`Scenes.Active` `power_override_persist_fun` seam** — used by `control_state_active_scene_test.exs`; stays.
- **`Circadian.build_context` discarded-binding pre-validation** — deliberately validates all three curves up front so later per-sample code may raise instead of returning errors; the `_events` bindings are the point, not waste.
- **`Circadian.Config`, `LightState.ManualConfig`, `Bridge.Credentials`, `PicoButton.ActionConfig`** — disciplined load/normalize/dump boundary modules; the formerly duplicated shared helpers were consolidated into `Util`/`AppSettings.FieldParser` (DM15/DM16).
- **HomeKit `catch :exit` blocks** (`stop_hap`, `notify_change_token`, `pair_setup_step`) — interop with the HAP library's process lifecycle; genuinely needed.
- **`Picos` metadata dual-key access** (`ControlGroups`, `Summary`, `Bindings`) — JSON-round-tripped device metadata; boundary rule applies.
- **`external_scenes.ex` rescue** — wraps a network fetch; boundary.
- **`bridges.ex` query-builder helpers** — composable Ecto pipeline; fine.
