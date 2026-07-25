# Chunk 4: External Spaces, Mappings, HA Inventory

Status: complete for the domain modules (`external_spaces.ex`, `space_mappings.ex`, `space_suggestions.ex`, `inventory.ex`, `area_design.ex`, import-plane call sites in `materialize.ex`/`reimport_apply.ex`/`reimport_plan.ex`). The LiveView surfaces that render these (bridge_live HA guidance heex, setup flow) are chunk 5/7 territory.

## Findings

### ES-1: External-space `kind` is clobbered on the persisted-blob path — floor mappings crash import apply and floors get double-filed

- Severity: **high**. Type: technical (data corruption + broken release-gate journey).
- Location: `lib/hueworks/import/space_mappings.ex` `ensure_identity/2`:
  ```elixir
  space
  |> Map.put_new(:kind, default_kind(bridge_type))
  |> Map.put_new(:external_id, Normalize.fetch(space, :source_id))
  ```
- Mechanism: every real call path feeds this function **string-keyed** maps — `BridgeSetupLive.start_import` assigns `bridge_import.normalized_blob` (Ecto `:map` loaded from SQLite JSON), and `ReimportPlan.build` emits `NormalizeJson.to_map(...)` — so the atom `:kind` is *always* absent and `Map.put_new` always inserts the bridge default (`"ha_area"` for HA). `Normalize.fetch/2` prefers atom keys, so the true `"kind" => "ha_floor"` is shadowed everywhere downstream (`normalize_space`, `normalized_space_identity`).
- Verified consequences (each traced in code, not speculated):
  1. **Apply crash**: `SpaceSuggestions.space_identity/2` derives kinds *correctly* (`fetch || default`), so reviewed plan entries carry `"kind" => "ha_floor"`. At apply, `sync_bridge_spaces` has persisted that floor as `kind: "ha_area"`, so `apply_explicit_space_mappings` misses the identity lookup and hits `raise "reviewed external-space mapping refers to a missing source space"` — the materialize/reimport transaction dies whenever the user mapped a Floor. HA normalize emits floors into `external_spaces` (`floor_spaces ++ areas`) and the suggestion UI offers them, so this is a mainline HA-assisted-setup crash, not an edge case.
  2. **Duplicate rows / double-filing**: `AreaDesign.refresh` syncs the *same blob* through `ExternalSpaces.sync_bridge_spaces` **without** `ensure_identity`, storing floors correctly as `"ha_floor"`. The two paths therefore write the same floor under two identities (unique index `[bridge_id, kind, external_id]` sees different rows), and the clobbered `"ha_area"` floor rows render as *Areas* in `AreaDesign.design`'s `kind == "ha_area"` filter.
  3. **Parent links broken**: in the clobbered path, `normalize_space` reads `parent_kind` from the (unpolluted) string key `"ha_floor"`, but the batch identity map is keyed by clobbered kinds, so `parent_id/2` never resolves and area→floor edges are dropped.
  4. **Saved mappings never prefill**: `apply_plan_defaults` computes identities from fresh (atom-keyed, correct) normalization at plan time and misses rows persisted with clobbered kinds.
- Decision: create one identity function (module-level, e.g. `Hueworks.Import.SpaceIdentity.identity(space, bridge_type)`) with the `SpaceSuggestions.space_identity/2` semantics — `Normalize.fetch(space, :kind) || default_kind(type)`, `fetch(:external_id) || fetch(:source_id)`, normalize both — and use it in `SpaceMappings` (delete `ensure_identity/2` and its `Map.put_new` pattern entirely; pass explicit `%{kind:, external_id:, name:, parent_kind:, parent_external_id:, metadata:}` attrs into `sync_bridge_spaces` built via `Normalize.fetch`). Move `default_kind/1` there too — `SpaceMappings` and `SpaceSuggestions` currently carry diverged copies (`SpaceSuggestions` is missing the `:ha` clause and falls through to `"external_space"`). Never `Map.put_new` atom keys onto import-plane maps; that inverts the dual-key read order — worth recording as a boundary rule alongside the existing "only `StateParser` accepts loose payloads" rule.
- Guardrails (test-first; this is a bug fix per `AGENTS.md`): (a) an end-to-end test that runs a **string-keyed** normalized blob (floors + areas) through plan → map-a-floor → `Import.apply_review` and asserts the mapping persists and nothing raises; (b) a `sync_bridge_spaces` assertion that floor rows persist with `kind: "ha_floor"` when fed blob-shaped maps; (c) a cross-path test that `AreaDesign.refresh` and `SpaceMappings.sync_and_apply` produce identical rows for the same blob. Existing tests passed because fixtures are atom-keyed — add string-keyed variants wherever import-plane fixtures feed these modules.
- Effort: M. Do this before any HA-assisted rehearsal; it invalidates the "HA-assisted setup can inventory first, map Areas" release criterion until fixed.

### ES-2: Batch-scoped parent resolution silently severs floor links on partial syncs

- Severity: low. Type: technical (robustness).
- Location: `lib/hueworks/external_spaces.ex` `sync_bridge_spaces/3` — `parent_id/2` resolves only within the current batch's `by_identity`.
- Problem: if a source reports an area whose parent floor is absent from *this* sync payload (HA registry hiccup, partial fetch), the existing parent edge is overwritten with `nil`, contradicting the module's own "temporary source omissions [are] nondestructive" doc. (Distinct from ES-1, which breaks resolution even in full batches.)
- Decision: when `parent_kind`/`parent_external_id` are present but unresolved in the batch, fall back to `get_by_identity` against the DB; only clear the parent when the source explicitly reports no parent.
- Guardrail: unit test syncing an area alone after a prior full sync and asserting the floor edge survives.
- Effort: S.

## Explicitly Fine / Leave-Alone

- **`ExternalSpaces` contract** (sync refreshes facts, never deletes unseen spaces, never touches mappings; `last_seen_at` + `stale?/2` for rename/staleness diagnostics): matches the refinement doc's ExternalSpaceMappings rule and the moduledoc states it plainly. Upsert-in-transaction is race-safe for this single-writer SQLite deployment.
- **Placement precedence** in `SpaceMappings.target_id_for/4` — explicit reviewer choice (including explicit "unassigned") > import-plan area destination > persisted mapping default — is the right order, and it is only consulted on entity *insert* paths in `materialize`/`reimport_apply`; existing entity placement is untouched, honoring "existing placement is authored HueWorks intent". `AreaDesign`'s moduledoc states the same boundary and its code (create areas + manage mappings only) respects it.
- **`Inventory`** read-only projection with native-source detection driving the "native before HA" ordering guidance: sound separation, no persistence. The `platform == "mqtt"` → `:z2m` heuristic can over-claim non-Z2M MQTT lights as native wrappers; acceptable for guidance copy that already hedges, revisit only if a real household hits it.
- **`SpaceSuggestions`** evidence model (member-match statuses, `:conflict` on disagreeing evidence, preselect only on `:confident`, ambiguity propagation): conservative and matches the state matrix's "conflicting evidence" requirement. Its identity derivation is the correct pattern ES-1 adopts.
- **Suggestion/plan key encoding** (`Jason.encode!` + url-safe Base64 of `[kind, external_id]`): stable, collision-free, opaque to the DOM. Fine.
