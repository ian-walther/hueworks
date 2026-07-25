# Chunk 6: Isolated Verification Mode & Health

Status: complete. Scope: `runtime_io.ex`, `application.ex` (via `git show HEAD:` — dirty), `config/runtime.exs` isolation block, `hueworks_app/health.ex`, `health_controller.ex`, `hueworks_app/z2m/snapshot.ex`, `hardware_smoke.ex` delta, and a leak-vector sweep of every on-demand I/O path reachable while `HUEWORKS_RUNTIME_IO_DISABLED` is set.

## Findings

### IV-1: Control actions crash with `noproc` in isolated mode instead of no-opping

- Severity: medium. Type: technical (broken error state in the verification rehearsal).
- Location: `HueworksApp.Control.Executor.enabled?/0` checks only `:control_executor_enabled`; `config/runtime.exs`'s `if runtime_io_disabled` block does not set it false, and `Hueworks.Application.children/1` removes the Executor process from the tree.
- Problem: `Control.Apply.enqueue_plan/2` → `Executor.enqueue/2` passes the `enabled?()` check and issues `GenServer.call` against a name that isn't running → `noproc` exit. Every scene activation, manual adjustment, or API control call on a verification instance kills its LiveView/request with a generic crash. It's fail-closed (no real I/O can leak), but the entire point of isolated verification is rehearsing these flows, and the state-coverage matrix requires intentional error states — a process crash is not one. Contrast: `Control.State` handles the same mode with clean no-op guards on bootstrap/refresh.
- Decision: change `enabled?/0` to `Application.get_env(:hueworks, :control_executor_enabled, true) and not Hueworks.RuntimeIO.disabled?()`, so enqueue returns the existing `{:ok, :disabled}` path and activation flows complete their DB writes with dispatch skipped. Additionally, show the verification-mode banner on Control (ConfigLive already renders one from `health.body[:runtime_io]`) so "activated but nothing physical happened" is explained on the page where it's observed.
- Guardrail: test activating a scene with `runtime_io_disabled: true` and the Executor absent from the tree — asserts no exit and `{:ok, :disabled}` enqueue; ControlLive render test for the banner.
- Effort: S.

### IV-2: HardwareSmoke has no isolated-mode guard

- Severity: low. Type: technical (operator tooling).
- Location: `lib/hueworks/hardware_smoke.ex` — calls `Executor.stats()` (bare `GenServer.call`) and drives real control paths with no `RuntimeIO` check.
- Problem: running the smoke against a verification instance dies with `noproc` noise instead of a refusal. The smoke's entire purpose is real-hardware verification, so it must refuse loudly, not crash confusingly.
- Decision: first line of the smoke entrypoint: `case Hueworks.RuntimeIO.ensure_enabled() do {:error, _} -> raise "hardware smoke requires runtime I/O; unset HUEWORKS_RUNTIME_IO_DISABLED" ...`.
- Effort: S.

### IV-3: Z2M snapshot pattern-matches MapSet internals

- Severity: low. Type: style/robustness.
- Location: `lib/hueworks_app/z2m/snapshot.ex` `await_topics/4` head: `%MapSet{map: map} when map_size(map) == 0`.
- Problem: `MapSet` is opaque; its internal representation has changed across OTP/Elixir releases before. This will compile-warn or break silently on an upgrade.
- Decision: match completion with `MapSet.size(pending) == 0` (or `Enum.empty?/1`) in a guardless clause.
- Effort: S.

## Explicitly Fine / Leave-Alone

- **Isolation architecture**: supervision-tree exclusion of Executor, all four event streams, HA export, and HomeKit under one `runtime_io_disabled` flag is structural fail-closed isolation — stronger than per-call guards. `config/runtime.exs` also silences mdns_lite advertising in this mode. The on-demand I/O paths are covered: `Import.Pipeline.create_import` gates with `RuntimeIO.ensure_enabled` (which also covers SetupLive inventory refresh and both import LiveViews), and `BridgeLive` gates discovery, pairing, and connection tests at all four sites with an explicit user-facing message.
- **Health honesty** (`Hueworks.Health`): executor reports `"disabled"` (not a fake `"ok"`) and is excluded from readiness only in isolated mode; the `runtime_io` key appears only when disabled — which is exactly what the rollout runbook's production check asserts the absence of; 503 vs 200 driven by `ready?`; DI'd `health_module` for tests. Controller is minimal and correct.
- **Z2M snapshot subscription hygiene**: subscribes only `<base>/bridge/{devices,groups,info}` retained topics at QoS 0 with an 8s deadline and cleanup in `after` — precisely the refinement doc's "narrowly scoped retained bridge metadata … without subscribing indefinitely to `#`".
- **`RuntimeIO` module**: two tiny functions, one config key, clear moduledoc naming the rehearsal boundary. Right size for a cross-cutting switch.
- **`hardware_smoke.ex` delta**: purely the mechanical Room→Area rename. The household-specific hardcodes ("Main Floor", "Kitchen / Accent PIco") predate this range and are known operator-tool scope; not re-litigated here.
- **Verification-mode visibility in Config** (`verification_mode?` from health body, banner + "Runtime I/O: disabled" line): good; IV-1 extends this to Control rather than replacing it.
