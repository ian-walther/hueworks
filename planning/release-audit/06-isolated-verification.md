# Chunk 6: Isolated Verification Mode & Health

Status: complete; implementation reconciled 2026-07-26. Scope: `runtime_io.ex`, `application.ex`, `config/runtime.exs` isolation block, `hueworks_app/health.ex`, `health_controller.ex`, `hueworks_app/z2m/snapshot.ex`, `hardware_smoke.ex`, and a leak-vector sweep of on-demand I/O paths under `HUEWORKS_RUNTIME_IO_DISABLED`. No open findings.

## Explicitly Fine / Leave-Alone

- **Executor honors the rehearsal boundary** (formerly IV-1, implemented): `enabled?/0` includes `not RuntimeIO.disabled?()`, so isolated control actions take the existing `{:ok, :disabled}` no-op path instead of `noproc`-crashing, and Control renders an explicit verification-mode warning callout.
- **Hardware smoke refuses isolated mode loudly** (formerly IV-2, implemented): every entrypoint runs `ensure_runtime_io!` and raises with the exact remediation ("unset HUEWORKS_RUNTIME_IO_DISABLED") before touching executor or hardware paths.
- **Z2M snapshot completion uses public `MapSet` API** (formerly IV-3, implemented): no more opaque-struct internals matching.
- **Isolation architecture**: supervision-tree exclusion of Executor, all four event streams, HA export, and HomeKit under one `runtime_io_disabled` flag — structural fail-closed isolation. `config/runtime.exs` silences mdns_lite advertising in this mode; `Import.Pipeline.create_import` gates on-demand fetches (covering setup inventory and both import LiveViews); `BridgeLive` gates discovery, pairing, and connection tests with explicit user-facing messages.
- **Health honesty** (`Hueworks.Health`): executor reports `"disabled"` (not a fake `"ok"`) and is excluded from readiness only in isolated mode; the `runtime_io` key appears only when disabled — exactly what the rollout runbook's production check asserts the absence of; 503 vs 200 driven by `ready?`; DI'd `health_module`.
- **Z2M snapshot subscription hygiene**: only `<base>/bridge/{devices,groups,info}` retained topics at QoS 0 with a bounded deadline and cleanup in `after` — the refinement doc's narrow-subscription rule implemented literally.
- **`RuntimeIO` module**: two functions, one config key, clear rehearsal-boundary moduledoc. Right size for a cross-cutting switch.
- **`hardware_smoke.ex` household-specific hardcodes** ("Main Floor", "Kitchen / Accent PIco"): pre-existing operator-tool scope; not re-litigated.
