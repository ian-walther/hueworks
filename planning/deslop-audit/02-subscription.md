# Chunk 2 — Subscription Plane

Status: COMPLETE. All files in `lib/hueworks/subscription/**`, `lib/hueworks_app/subscription/**`, `lib/hueworks_app/z2m/**`, `lib/hueworks/mqtt/**` audited line-by-line; findings SU1-SU6, SU8, SU9 implemented and reconciled (verified against diffs, full suite green). SU7 resolved as no-change by its own decision text — recorded below so it isn't re-litigated.

No open findings.

## Explicitly Fine / Leave-Alone

- **The four 26-line `*EventStream` wrapper modules** — obvious, parallel, boring; a macro or shared child_spec builder would cost more than it saves.
- **`GenericEventStream`** — tight; the readiness_fun/delay opts are all exercised by `subscription_generic_event_stream_test.exs`.
- **Caseta `:subscribe_fun` state seam** — used by tests to observe subscription calls; it stays.
- **Hue SSE `Parser`** — clean, earns every line.
- **`Z2M.Snapshot` await/receive loop** — bounded-deadline collect at a true MQTT boundary; error formatting is reachable via Tortoise supervisor return shapes.
- **HA connection auth/subscription state machine** — small and correct; stream-noise-tolerant clauses are legitimate at an external boundary.
- **Per-connection ~2s index staleness refresh, including the caseta/ha `refresh_due?` twins** (was SU7) — reference pattern per `planning/audit/auditor-instructions.md`; each connection owns its refresh state differently and cross-transport consolidation is not worth it. Deliberate; do not re-flag.

## Durable corrections (learned during implementation)

- The SU4 extraction exposed a real latent bug: the z2m handler's index-refresh path rebuilt state from bare indexes, silently dropping `client_id`, `subscriptions`, and `subscribed?` (a later `connection/2` callback would have KeyErrored). Refresh now merges new indexes into live handler state; regression assertions live in `subscription_z2m_handler_test.exs` (refresh test asserts connection metadata survives).
