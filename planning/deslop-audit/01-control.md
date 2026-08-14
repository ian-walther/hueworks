# Chunk 1 — Control Plane

Status: COMPLETE. All of `lib/hueworks/control/**` and `lib/hueworks_app/control/**` audited line-by-line; findings CT1-CT22 implemented and reconciled (verified against diffs, full suite 1085 green, clean `--warnings-as-errors` compile). Chunk tests received a structural skim; the CT-driven test edits were verified during reconciliation.

No open findings.

## Explicitly Fine / Leave-Alone

- **`StateParser` dual-key access and clause fan-out** — it is the sanctioned loose-payload boundary (`auditor-instructions.md`); every public function has real callers (verified by grep). The kelvin extended-range cond ladders are irreducible domain logic.
- **`Executor` init opts injection** (`dispatch_fun`, `now_fn`, `bridge_rate_fun`, settlement knobs) — all exercised by tests; deliberate seam design, not speculative generality.
- **`Trace` four same-shaped log functions** — payloads differ per stage; a generalization would obscure more than it saves.
- **`TraceBuffer.event/4` dual-source key reads** (`:source` || `:trace_source`) — record() receives both normalized trace maps and raw action-shaped maps from different stages.
- **Bootstrap `run_bootstrap_module` rescue** — bootstrap modules do real network IO; catch-and-log is correct at this boundary (now a single rescue after CT8).
- **Bridge/client modules' error tuples and injectable `*_module()` seams** (`Z2MClient`, `CasetaLeap`, `CasetaClient`) — real IO boundaries with real test doubles.
- **`GroupState` averaging logic** — genuine domain rules; its `normalize_power`/`fetch_value` fallbacks are marginal re-defense of the atom-key invariant but too cheap to be worth churn.
- **`CircadianPoller.run_tick` `other ->` clause** — logs loudly rather than swallowing; acceptable telemetry safety-net.
- **Planner test file** (`control_planner_test.exs`) — large but substantive; scenario fixtures encode real regressions.
- **Executor/convergence test setup repetition** — matches the codebase's visible-setup test style; deliberately not flagged.
- **`Planner.Action` constructors' repeated optional-field conditionals** (post-CT11 shape) — the two if-chains in `light/6` and `group/7` mirror each other; a shared helper was considered and declined as churn on a net-simpler module. Do not re-flag.
- **`BridgeCredentialsCache.fetch` misuse clause** returning `{:error, :missing_bridge_id}` — carries the four deleted per-module fallback clauses (CT21); reachable via entities without a bridge_id.

## Durable corrections (learned during implementation)

- The formerly-parked `:ignore` dispatch leak was real: `payload <- XPayload.action_payload(...)` plain binds let `:ignore` reach the caseta/z2m clients. Fixed test-first (`payload when is_map(payload) <-`), and HuePayload now returns `:ignore` for empty payloads like the other three sources. No-op dispatches now stop before bridge IO across all four sources. Coverage: `control_hue_payload_test.exs`, `control_caseta_dispatch_test.exs`, `control_z2m_dispatch_test.exs`.
- `DesiredState.snapshot/1` spec now includes `updated_at` (was drifted).
