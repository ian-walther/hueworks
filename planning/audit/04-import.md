# Audit Chunk 4: Import & Persistence

Scope: `lib/hueworks/import/**`, `lib/hueworks/bridges.ex`, `lib/hueworks/bridge_seeds.ex`. Import-owned schemas were read as encountered (`Light`/`Group` normalized_json fields, `SceneComponentLight` in chunk 3, `BridgeImport` via usage).
Status: complete. Core pipeline, plan/materialize/link/duplicates/identifiers, and both reimport modules were read line-by-line; the four `fetch/*` transport modules were read for structure, error handling, and duplication (per-line parser scrutiny was deliberately lighter — they sit at the external boundary where loose payload handling is architecturally sanctioned).

Context: the reimport backend (commit `0ed7be5`) is fresh and implements the `planning/import-resync.md` product contract with real care — field ownership respected on refresh (display_name preserved, rooms never moved), staleness validation via `expected_external_id` (now enforced for destructive resolutions), rollback on duplicate-classification drift, post-commit-only integration effects. The findings below are mostly about what that speed cost: duplication against `Materialize` and a still-incomplete characterization net on the most destructive module in the app.

---

### IM-2: Materialize and ReimportApply duplicate entity/room construction — with one real behavior divergence
- Severity: high
- Type: refactor (+ embedded bug-risk)
- Where: [materialize.ex](../../lib/hueworks/import/materialize.ex) vs [reimport_apply.ex](../../lib/hueworks/import/reimport_apply.ex): room upsert (`upsert_rooms` vs `upsert_room`, both with the lowercased-name matching and merge/skip plan actions), light/group attrs construction (inline maps at materialize.ex:123-139/194-210 vs `light_attrs`/`group_attrs`), hidden-duplicate overlays (`hidden_duplicate_light_attrs` vs `import_hidden_duplicate_light!`), `light_metadata`/`group_metadata` (verbatim), `room_id_for` (near-verbatim), `normalize_source` (see IM-3).
- What: the reimport path re-implemented materialize's construction rather than extracting it. The copies have already diverged in a user-visible way: **initial import leaves `display_name` unset** (UI falls back to bridge `name`, so bridge renames flow through until the user customizes), while **reimport-created entities pin `display_name: name` at insert** (reimport_apply.ex:453,502) — freezing the import-time name against future bridge renames. `refresh_light!`/`refresh_group!` correctly never touch `display_name`; only the insert paths disagree.
- Decision: extract `Hueworks.Import.EntityAttrs` owning `light_attrs(bridge, light)`, `group_attrs(bridge, group)`, `hidden_duplicate_overlay(attrs, canonical_id, :light | :group)`, and the metadata builders; extract `Hueworks.Import.Rooms.upsert(room, plan_entry)` for the shared room logic. Both Materialize and ReimportApply consume them. Resolve the divergence in favor of initial-import behavior: **do not set `display_name` at insert** in either path — bridge names should flow through until the user authors a display name.
- Guardrails: `materialize_test.exs` and `import_plan_application_test.exs` are the characterization net for the initial path; the reimport path needs IM-8's tests FIRST (do not refactor an untested 860-line module). Add one test asserting a reimport-created light with no user display_name reflects a subsequent bridge rename.
- Effort: M (after IM-8)

### IM-4: Identifier indexing duplicated between Link and Duplicates
- Severity: medium
- Type: refactor
- Where: [link.ex:32-89,155-161](../../lib/hueworks/import/link.ex) (mac/serial/ieee index building, `unique_match`, `identifier/2`) vs [duplicates.ex:96-115,162-176](../../lib/hueworks/import/duplicates.ex) (`identifier_index`, `unique_native_light_match`, `metadata_identifier`, `normalized_identifier`)
- What: the same "index native lights by mac/serial/ieee, find unique match" logic exists twice with slightly different accessors (DB-record metadata vs normalized-entity identifiers). Cross-source identity is the most correctness-sensitive part of import; two implementations means two drift surfaces.
- Decision: extract `Hueworks.Import.IdentifierIndex` with `build(lights_or_entities)` (accepting both shapes via the two accessor functions) and `unique_match(index, key, value)`; Link and Duplicates consume it.
- Guardrails: `link_test.exs` and `import_identifiers_test.exs` characterize current matching; port assertions rather than rewriting them.
- Effort: M

### IM-5 (residual): Z2M import fetcher still carries its own connection-config normalization
- Severity: low
- Type: refactor
- Where: [fetch/z2m.ex](../../lib/hueworks/import/fetch/z2m.ex) (`normalize_port`/`normalize_base_topic`/auth opts — the last copy now that `Z2MConfig` and `Mqtt.Options` exist; the Caseta half of this finding landed with the `CasetaLeap` migration)
- Decision: migrate `fetch/z2m.ex`'s `config_for_bridge` onto `Hueworks.Control.Z2MConfig.for_bridge/1` + `Hueworks.Mqtt.Options.put_auth/2` and delete the private copies. Check whether `Fetch.Common.invalid_credential?/1` still has callers afterwards; delete if not.
- Guardrails: `test/hueworks/import/fetch/common_test.exs` plus the existing import pipeline tests; fetchers are `rescue`-wrapped at the Pipeline boundary, so behavior-preserving extraction is low-risk.
- Effort: S

### IM-6: import-resync.md still describes the implemented reimport backend as future work
- Severity: medium
- Type: doc-drift
- Where: [planning/import-resync.md](../../planning/import-resync.md) ("Priority: This is the next major work item before the control-architecture refactor")
- What: the backend contract in that doc is now largely implemented (`ReimportPlan` + `ReimportApply`: observation persistence, identity matching with ambiguity surfacing, bridge-owned refresh, safest-default review items, staleness-validated resolutions, hidden-duplicate bookkeeping). Per AGENTS.md rule 1/2, completed items must be removed from planning docs. The UI work (`hueworks_todo.md` "Now" section: diff/resolution review page, dependency disclosure, inspectable auto-refreshes) genuinely remains.
- Decision: rewrite import-resync.md down to what remains: the UI workflow items, the future-inbox notes, and any contract bullet the implementer cannot demonstrate in code + tests (list those explicitly for the owner rather than guessing). Remove the "next major work item" priority framing. Do this AFTER IM-8 lands so "demonstrated in tests" is actually checkable.
- Effort: S

### IM-8 (residual): ReimportApply characterization suite is a foothold, not a net
- Severity: medium
- Type: test-gap
- Where: [test/hueworks/import_reimport_apply_test.exs](../../test/hueworks/import_reimport_apply_test.exs) (5 tests) vs [lib/hueworks/import/reimport_apply.ex](../../lib/hueworks/import/reimport_apply.ex)
- What: coverage now exists for refresh field-ownership, selected-new creation/unselected skip, group membership refresh, hidden-duplicate deletion, and the missing-staleness-token rollback. Still uncovered from the contract-driven matrix:
  1. ambiguous identity is skipped, not guessed;
  2. `import_hidden_duplicate` creates the hidden row; `import_real` creates a visible row; duplicate-classification drift rolls the transaction back;
  3. `disable`/`delete` with a *mismatched* (not just missing) `expected_external_id` rolls back; `delete` cleans up scene-component and group-light references;
  4. post-commit effects fire only for removals (and fire for all of them).
- Decision: add these cases to the existing suite before IM-2's Materialize/ReimportApply deduplication starts; they are exactly the behaviors that refactor could silently break.
- Effort: M

---

## Explicitly Fine (checked, leave alone)

- `BridgeSeeds` — clean boundary module (explicit shape validation, whitelisted types, good errors). Second reference example alongside `Circadian.Config`.
- `Bridges` — competent lifecycle helpers; delete paths clean up references in the right order and defer export removals to post-commit.
- The four `normalize/*` modules — complex, but the complexity is real upstream mess (ZHA group entity resolution, hue-via-HA group derivation, template filtering, mired/kelvin range juggling). Loose `Normalize.fetch` dual-key access is correct HERE (blobs round-trip through JSON, so the same map is atom-keyed fresh and string-keyed from the DB). Do not extend CP-3's atom-key invariant into the import plane.
- `EntityMatch`, `ReimportPlan` — the ambiguity rules match the contract; planning marks ambiguous entries `keep_separate`/unselected and apply skips them.

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- IM-8's residual matrix is the remaining gap here.
- Initial materialize, plan application, identifiers, link, NormalizeJson, and NormalizeFromDb are all covered — leave alone.

## Parked (noted early, belongs to later chunks)

- Chunk 5: confirmed via compile warnings that `HomeAssistant.Export.Commands` carries the third copy of the xy/kelvin harmonization helpers (`incoming_has_xy?` etc.) — strengthens the chunk-1 CP-2 parked item.
- Chunk 5: `ReimportApply.run_post_commit_effects` and `Bridges.delete_entities` both drive HA export/HomeKit reloads inline — same pattern as SC-2; fold into the SC-2 stage-2 event design.
- Chunk 7: `mix compile` emits ~20 warnings (dead fallback clauses, deprecated `Logger.configure_backend`, a redundant HAP handle_info clause). Several are shadows of known duplication (CP-2's dead clauses). After CP-2/CP-4 land, do a warnings-zero pass and turn on `--warnings-as-errors` for `mix test` runs.
- Chunk 7 hygiene reminder (from 00-plan): `exports/` fixtures with LAN IPs; `bridge_host` metadata still written but unread (chunk 1 parked note).

## Suggested Implementation Order (for cheap-model sessions)

1. IM-8 residual (completes the characterization net — unblocks IM-2)
2. IM-2 (dedupe + display_name decision, once netted)
3. IM-4; IM-5 residual (small `Z2MConfig`/`Mqtt.Options` migration, can go anytime)
4. IM-6 last (doc reconciliation against the now-demonstrable test suite)
