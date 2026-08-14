# Chunk 7 — Web (config LiveViews)

Status: CLOSED. No chunk-exclusive findings were ever raised; the cross-cutting WM4 (blank-to-nil consolidation) covered this chunk's files and is implemented and reconciled.

## Explicitly Fine / Leave-Alone

- **`BridgeLive` at ~1150 lines** — a four-bridge-type onboarding wizard organized as per-type clause families (`build_connection_request`, `run_connection_test`, `validate_required_fields`, per-type discovery). Splitting into per-type modules is an *architecture* choice with real tradeoffs (shared wizard state), not a de-slop deletion; the injectable `*_module()` seams are all test-used. If it keeps growing, revisit.
- **Dynamically-built event names** (`bridge_setup_live.ex` toggle_light/toggle_group) — legitimate; noted so a future dead-handler sweep doesn't false-positive on them.
- **`IntegrationsConfigLive` bare `to_existing_atom`** — ruled intentional (chunk 3 Leave-Alone, DM1 refutation).
