# Audit Chunk 6b: Web (everything except the scene builder)

Scope: remaining `lib/hueworks_web/**` (~9,700 lines) — lights/control/rooms/config/pico LiveViews, light-state editor, components, controllers, plugs, filter prefs.
Status: in progress — findings flushed per sub-area. Tracker:

| Sub-area | Files | Status |
|----------|-------|--------|
| 6b-1: manual control surfaces (lights_live.ex + lights_live/* submodules, control_live.ex) | ~1,900 lines | done |
| 6b-2: config surfaces (config_live, bridge_live, bridge_setup_live — the reimport review UI) | ~1,700 lines + heex | done |
| 6b-3: pico_config_live + rooms_live + external_scene_config_live | ~1,500 lines + heex | rooms + external-scene done; pico_config_live pending |
| 6b-4: light_state_editor (+ form_state, preview), components, controllers, plugs, filter_prefs, heex sweep | remainder | not-started |

Finding IDs are stable (WB-*); gaps in numbering mean the finding was implemented and removed.

Focus questions for this chunk: (1) do manual-control surfaces share the semantic path with Pico/HA/HomeKit as planned_architecture.md requires; (2) does the reimport review UI match the `import-resync.md` contract (that doc's remaining work is UI); (3) LiveView-state hygiene (assigns sprawl, Repo access from views).

---

## 6b-1: Manual Control Surfaces

Assessment: `LightsLive` is the best-structured LiveView in the app — 122 lines delegating to nine focused submodules, with all actions entering through `ManualControl` (focus question 1: **confirmed shared semantic path**, including scene-active adjustment locks surfaced as user-facing messages). `ControlLive` reuses those submodules and enforces the same locks in both UI affordances and handlers, with activation traces. All four findings from this sub-pass (WB-1..WB-4) were implemented and removed per the forward-facing rule — no open findings from 6b-1.

Explicitly fine: the `DisplayState.preserve_extended_display_kelvin?` quirk is deliberate device-profile display behavior (extended-kelvin lights reporting the ambiguous boundary value) — leave it; `Loader`/`FilterState`/`FilterPrefs` session-persistence is clean; `Entities` fetch helpers enter through the Lights/Groups contexts.

---

## 6b-2 (part 1): Bridge Setup / Reimport Review UI

Assessment vs the `import-resync.md` contract (focus question 2): **substantially further along than `hueworks_todo.md` implies.** The page has status-driven review (new/existing/duplicate/missing/ambiguous with a summary bar), per-entity and bulk resolution selects with safe defaults, bridge-owned refresh disclosed as fact ("Existing entities refresh bridge-owned facts") rather than as a decision, and stale-review recovery: apply-time rollbacks (`stale_resolution`, `duplicate_classification_changed`, `invalid_duplicate`) refresh the review in place with a per-reason message. Owner should re-read the three reimport bullets in `hueworks_todo.md` against this: all three items now look satisfied (destructive confirmation landed as a dependency-disclosure panel with explicit confirm); owner should trim that todo section after a hands-on pass.

## 6b-2 (part 2): Config page

All config-page findings (WB-9/10/11) implemented and removed. Explicitly fine (config page): the `update_*`/`save_*` param-mirroring pairs are verbose but explicit, tested, and consistent — not worth a changeset-driven rewrite; the hardcoded timezone list is a product choice; settings persistence correctly funnels through `AppSettings.upsert_global` with per-section normalize modules.

## 6b-2 (part 3): Add-Bridge Wizard (bridge_live)

Assessment: a clean test-before-save wizard — connection tests are properly delegated to per-source `ConnectionTest` modules, Caseta cert uploads are staged-then-promoted, and duplicate bridges are blocked by the `[:type, :host]` unique constraint (verified: index + changeset constraint). All three findings (WB-12/13/14) implemented and removed per the forward-facing rule.

## 6b-3 (part 1): Rooms + External Scene Config

Assessment: both clean context-consumers — rooms CRUD, presence inputs, and scene activation (traced) all enter through domain APIs; the external-scene page delegates sync/mapping entirely to `ExternalScenes`. Both findings (WB-15/16) implemented and removed per the forward-facing rule.

(6b-3 part 2 — pico_config_live — and 6b-4 findings appear here as those sub-areas complete)
