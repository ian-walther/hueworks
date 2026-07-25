# Chunk 5: Onboarding State & Guided First-Run Setup

Status: complete; implementation reconciled 2026-07-26. Scope: `onboarding.ex`, onboarding fields on `app_settings`, `SetupLive`, `AreaDesign` action functions, router/redirect integration, config callout. No open findings.

## Explicitly Fine / Leave-Alone

- **Read-only load path** (formerly OB-1): `ha_entry/1` uses `AreaDesign.design/1`; the DB-writing sync runs only at the inventory-refresh boundary.
- **Per-bridge refresh bookkeeping** (formerly OB-2, implemented): `inventory_refreshing_ids` is a MapSet with continuation destinations keyed by bridge id; completions clear and redirect only their matching request, covered by an overlapping-refresh test.
- **Mapped floors offer an explicit keep action** (formerly OB-3, implemented): a resolved floor shows "Keep as <Area>" instead of an editable name that would be silently ignored; the backend idempotent short-circuit is unchanged.
- **`Onboarding` module design**: progress derived from committed configuration; only path + finish/dismiss persisted; `auto_open?` requires a fully empty install so upgraded production never auto-opens. "State-derived contextual guidance, not a rigid wizard" implemented faithfully — `finish_setup` available any time, steps deep-link to real pages, dismiss is first-class, resumability holds across restarts.
- **Step ordering** for the HA-assisted path (connect HA → inventory → area design → location → native import/placement/scene → HA-only last → optional exports): matches "inventory first, native before HA-only, optional integrations outside the minimum path".
- **Honest copy**: "No entities were imported." on inventory refresh; the reverse-order warning (`ha_import_order_risk`) surfaces when adding a native bridge while unlinked HA entities exist.
- **`AreaDesign` action functions**: transactional with `Repo.rollback` on partial failure, idempotent via mapped-area reuse, strictly scoped to Areas + resolutions (never entity placement). Duplicate area *names* across floors are possible and acceptable.
- **Async inventory fetch** via `start_async` with an injectable pipeline module; the fetch stores a full `bridge_import` blob as "inventory" — the documented fetch-without-materialize design.
- **`Onboarding.status/0` query cost** (five aggregates + per-bridge existence checks on `/` redirect and setup/config mounts): trivial for single-household SQLite; do not cache.
- **`bridge_space/2`'s vacuous kind check** and pluralization helpers: cosmetic; not worth churn (the label helpers are now shared via `SetupHelpers`, see chunk 11).
