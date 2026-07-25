# Chunk 5: Onboarding State & Guided First-Run Setup

Status: complete. Scope: `onboarding.ex`, onboarding fields on `app_settings`, `SetupLive` (`.ex` at HEAD == worktree; `.html.heex` read via `git show HEAD:` — it is dirty with Sol's work), `AreaDesign` action functions, router/redirect integration, config callout. Cross-checked against the release-gate journey and the "no rigid wizard" non-goal.

## Findings

### OB-1: Setup page performs a DB-writing sync on every render pass and crashes on its failure

- Severity: medium. Type: technical (write amplification + crash on degraded state).
- Location: `lib/hueworks_web/live/setup_live.ex` `ha_entry/1` — `{:ok, design} = AreaDesign.refresh(bridge)` inside `load_setup/1`.
- Problem: `load_setup` runs on mount **and after every setup event** (map, skip, create, choose-path…), and `AreaDesign.refresh/1` is not a read — it re-syncs external spaces (a `Repo.transaction` with upserts) per HA bridge each time. Besides the needless writes, the bare `{:ok, design} =` match means any `{:error, _}` from the sync (changeset failure, transaction error) raises `MatchError` and takes down the whole setup LiveView — the opposite of the state-matrix requirement that setup degrade legibly. The sync is already performed at the one correct moment: the `refresh_ha_inventory` async completion (line 143).
- Decision: `ha_entry/1` calls read-only `AreaDesign.design/1`; delete the `refresh` from the load path and keep it only in the async completion. If `design/1` itself errors, produce `%{bridge: bridge, inventory: inventory, design: nil}` and let the template's existing nil-design branch render.
- Guardrail: setup_live test asserting no `external_spaces` rows are written by mount/map events, plus a degraded-entry render test.
- Effort: S.

### OB-2: Concurrent HA inventory refreshes confuse the single `inventory_refreshing_id`

- Severity: low. Type: UX/state consistency.
- Location: `SetupLive` `refresh_ha_inventory` + `handle_async({:refresh_ha_inventory, ...})` — no staleness guard; one scalar assign tracks "the" refreshing bridge.
- Problem: with two HA bridges, starting a second refresh overwrites the id; the first completion then clears the spinner while the second fetch is still running, and results are applied unguarded. `BridgeLive` in the same commit range establishes the request-id-guard convention — this surface should match it.
- Decision: track refreshing bridges as a MapSet (add on start, remove on the matching completion); no request-id needed since the async key already carries `bridge_id` — just check membership before clearing.
- Effort: S.

### OB-3: "Use one Area" silently ignores the typed Area name when the floor is already mapped

- Severity: low. Type: UX.
- Location: `AreaDesign.use_floor_as_one_area/3` — `mapped_area(floor) || destination_area!(attrs)` short-circuits before the submitted name is considered; `SetupLive.use_floor_one` always submits the name field.
- Problem: a user who edits the name and resubmits gets the existing mapping under the old name; the success notice does state the actual area name (good mitigation), but the input looked authoritative.
- Decision: in the template, when the floor is already mapped, replace the name input with the mapped-area badge and relabel the action ("Keep as <name>") so the form matches what the backend will do. Keep the backend short-circuit (idempotency is correct).
- Effort: S (template-only; coordinate with Sol since `setup_live.html.heex` is dirty).

## Explicitly Fine / Leave-Alone

- **`Onboarding` module design**: progress derived from committed configuration; only path + finish/dismiss persisted; `auto_open?` requires a fully empty install so upgraded production never auto-opens (matches the rollout runbook's warning about the setup callout). This is the "state-derived contextual guidance, not a rigid wizard" non-goal implemented faithfully — `finish_setup` is available at any time, every step deep-links to the real page, and "Leave for Config"/dismiss are first-class. Resumability holds across restarts because everything is re-derived.
- **Step ordering** for the HA-assisted path (connect HA → inventory → location/areas/native import/placement/scene → HA-only entities last → optional exports): matches the refinement doc's "inventory first, native before HA-only, optional integrations outside the minimum path".
- **Honest copy**: "Home Assistant inventory refreshed. No entities were imported." directly serves the inventory-vs-import distinction requirement; the reverse-order warning (`ha_import_order_risk`) surfaces in `BridgeLive` when adding a native bridge while unlinked HA entities exist, satisfying "reverse-order risk visible before import".
- **`AreaDesign` action functions** (`use_floor_as_one_area`, `use_floor_areas_separately`, `skip_floor`, `map_space`, `create_and_map_space`, `skip_space`): all transactional with `Repo.rollback` on partial failure, idempotent via mapped-area reuse, and strictly scoped to creating Areas + managing mappings (never entity placement) per the module contract. Duplicate area *names* across floors are possible and acceptable — HA allows the same.
- **Async inventory fetch** via `start_async` with an injectable pipeline module: right pattern; the fetch stores a full `bridge_import` blob as "inventory", which is the documented fetch-without-materialize design.
- **`Onboarding.status/0` query cost** (five aggregates + per-bridge existence checks, called from `/` redirect and setup/config mounts): trivial for a single-household SQLite app; do not cache.
- **`bridge_space/2`'s vacuous `true <- kind == expected_kind`** (kind was just `Map.put` to that value) and the `count_label` pluralization special-cases: cosmetic; not worth churn.
