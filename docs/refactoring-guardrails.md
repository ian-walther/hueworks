# Refactoring Guardrails

Use these rules alongside [the architecture rulebook](../planned_architecture.md) and [the audit workflow](../planning/audit/auditor-instructions.md). They constrain future cleanup, not future evidence-backed redesign: revisit a choice when its callers or semantics change, not merely because its shape looks repetitive.

## Require Evidence Before Deleting

- Prove an error path unreachable by tracing callers and callee return shapes. Network requests, MQTT payloads, JSON blobs, mDNS records, and library process exits are real fallible boundaries.
- Test-used injection points are not speculative generality. Executor dispatch/clock/rate/settlement options, connection readiness and subscription seams, and injectable bridge clients have concrete consumers.
- Remove indirection only when it adds no concept or boundary. A short helper, facade, or parallel function is not inherently a defect.
- Avoid style-only churn, including rewrites of the existing pipe/`then` and pipe/`Kernel.||` idioms. Visible per-test setup is deliberate; do not hide it behind clever fixtures solely to reduce repetition.

## Respect Boundary Vocabularies

- Internal control state is atom-keyed; `StateParser` is the loose-payload boundary. That invariant does not extend to JSON-round-tripped import blobs or Pico metadata: `Normalize.fetch` and their dual-key access are intentional.
- `Util.existing_atom/1` is for safe conversion where unknown values are expected. Fixed internal vocabulary conversions in `Import.ReviewPlan`, `ConnectionTest.Z2M`, and `IntegrationsConfigLive` intentionally fail loudly rather than silently accepting unknown keys.
- Reuse `Circadian.Config`, `LightState.ManualConfig`, `Bridge.Credentials`, `PicoButton.ActionConfig`, and `AppSettings.FieldParser` rather than recreating normalization in callers.
- Preserve normalized import compatibility aliases such as `external_spaces` and `areas` until their persisted consumers have an explicit migration path. Keep JSON round-trip test fixtures.

## Control And Runtime Safety

- No-op payloads (`:ignore`) must stop before bridge I/O for every transport. Preserve the payload and dispatch regression tests when changing those boundaries.
- `BridgeCredentialsCache.fetch/3` can receive a missing bridge ID from unassigned entities; that error path is reachable.
- Keep intentional projection distinctions such as bridge-reported group state versus member-derived physical state. Group averaging and intent power policies encode product semantics, not incidental complexity.
- `Circadian.build_context` validates all three curves before per-sample evaluation. Discarded bindings do not make that validation dead code.
- HAP lifecycle calls can exit; network bootstrap/client functions can fail. Their boundary handling must not be removed as generic defensive cleanup.
- Event-stream wrappers and per-connection index refresh checks may remain parallel because each transport owns different connection state. They do not replace the explicit post-import synchronization described in [the runtime-refresh plan](../planning/post-import-runtime-refresh.md).
- When refreshing Z2M indexes, merge into the live handler state; preserve `client_id`, `subscriptions`, and `subscribed?`. `test/hueworks/subscription_z2m_handler_test.exs` guards this lifecycle requirement.
- Preserve the bounded MQTT snapshot collection loop and HA authentication/subscription state machine. Their noise and timeout handling belongs at the transport boundary.
- Trace stages and their payloads differ. `TraceBuffer` accepts normalized trace maps and raw action-shaped maps, so both `:source` and `:trace_source` have callers.

## Keep Semantic Differences Visible

- Light/group planner actions, reimport reductions, and disable/delete cascades are not interchangeable solely because their scaffolding is similar. Canonical identities, dependency cleanup, and rollback branches differ.
- Keep reimport resolution-target staleness checks. They prevent a saved plan from acting on a different entity after identity changes.
- MQTT publish/unpublish pairs encode different protocol payloads and topic sets. The `Sync` lifecycle facade and struct-or-ID export entry points have real callers.
- Large multi-bridge LiveViews require an architectural argument before splitting shared wizard state. File size alone is not evidence; dynamically constructed event names also require call-path tracing before declaring handlers dead.
- `SceneBuilderComponent` and its domain `Component` struct serve different layers. The existence of both `/control` and `/lights` is a product choice, not a dead-code finding.

## Preserve Startup And Security Boundaries

- Cache operations can run before their GenServer or ETS table exists; safe cache misses are intentional during startup and tests.
- Keep API authentication's constant-time comparison and length checks, plus OAuth pending-state expiration and count bounds. These are security boundaries, not redundant defensive clauses.
- User-facing connection error messages and mDNS parsing clauses handle external inputs. Simplification must preserve useful error distinctions and tolerate malformed advertisements.
