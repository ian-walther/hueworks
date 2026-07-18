# Audit Chunk 6b: Web (everything except the scene builder)

Scope: remaining `lib/hueworks_web/**` (~9,700 lines) — lights/control/areas/config/pico LiveViews, light-state editor, components, controllers, plugs, filter prefs.
Status: audit complete — findings flushed per sub-area. Tracker:

| Sub-area | Files | Status |
|----------|-------|--------|
| 6b-1: manual control surfaces (lights_live.ex + lights_live/* submodules, control_live.ex) | ~1,900 lines | done |
| 6b-2: config surfaces (config_live, bridge_live, bridge_setup_live — the reimport review UI) | ~1,700 lines + heex | done |
| 6b-3: pico_config_live + areas_live + external_scene_config_live | ~1,500 lines + heex | done |
| 6b-4: light_state_editor (+ form_state, preview), components, controllers, plugs, filter_prefs, heex sweep | remainder | done |

Finding IDs are stable (WB-*); gaps in numbering mean the finding was implemented and removed.

Focus questions for this chunk: (1) do manual-control surfaces share the semantic path with Pico/HA/HomeKit as planned_architecture.md requires; (2) does the reimport review UI match the `import-resync.md` contract (that doc's remaining work is UI); (3) LiveView-state hygiene (assigns sprawl, Repo access from views).

---

## 6b-1: Manual Control Surfaces

Assessment: `LightsLive` is the best-structured LiveView in the app — 122 lines delegating to nine focused submodules, with all actions entering through `ManualControl` (focus question 1: **confirmed shared semantic path**, including scene-active adjustment locks surfaced as user-facing messages). `ControlLive` reuses those submodules and enforces the same locks in both UI affordances and handlers, with activation traces. All four findings from this sub-pass (WB-1..WB-4) were implemented and removed per the forward-facing rule — no open findings from 6b-1.

Explicitly fine: the `DisplayState.preserve_extended_display_kelvin?` quirk is deliberate device-profile display behavior (extended-kelvin lights reporting the ambiguous boundary value) — leave it; `Loader`/`FilterState`/`FilterPrefs` session-persistence is clean; `Entities` fetch helpers enter through the Lights/Groups contexts.

---

## 6b-2 (part 1): Bridge Setup / Reimport Review UI

Assessment vs the `import-resync.md` contract (focus question 2): the safety-critical review flow is implemented. The page has status-driven review (new/existing/duplicate/missing/ambiguous with a summary bar), explicit duplicate/missing resolution selects and bulk actions with safe defaults, dependency-disclosing confirmation for destructive resolutions, and stale-review recovery: apply-time rollbacks (`stale_resolution`, `duplicate_classification_changed`, `invalid_duplicate`) refresh the review in place with a per-reason message. The forward-looking UX residual is narrower: new entities still use checkboxes, current-versus-bridge details and auto-refreshed fact deltas are not shown, and unchanged/auto-refresh/membership-warning visibility remains incomplete. Those product refinements stay in `planning/import-resync.md` and `hueworks_todo.md`; no additional audit finding is needed.

## 6b-2 (part 2): Config page

All config-page findings (WB-9/10/11) implemented and removed. Explicitly fine (config page): the `update_*`/`save_*` param-mirroring pairs are verbose but explicit, tested, and consistent — not worth a changeset-driven rewrite; the hardcoded timezone list is a product choice; settings persistence correctly funnels through `AppSettings.upsert_global` with per-section normalize modules.

## 6b-2 (part 3): Add-Bridge Wizard (bridge_live)

Assessment: a clean test-before-save wizard — connection tests are properly delegated to per-source `ConnectionTest` modules, Caseta cert uploads are staged-then-promoted, and duplicate bridges are blocked by the `[:type, :host]` unique constraint (verified: index + changeset constraint). All three findings (WB-12/13/14) implemented and removed per the forward-facing rule.

## 6b-3 (part 1): Areas + External Scene Config

Assessment: both clean context-consumers — areas CRUD, presence inputs, and scene activation (traced) all enter through domain APIs; the external-scene page delegates sync/mapping entirely to `ExternalScenes`. Both findings (WB-15/16) implemented and removed per the forward-facing rule.

## 6b-3 (part 2): Pico Config

Status: `pico_config_live.ex` audited line-by-line; HEEx audited with full structural scrutiny.

Assessment: the Pico configuration write boundary is sound. Area/name changes use the `Picos` facade's focused device APIs, while clone, control-group, binding, and clear-config mutations all pass through `Picos.Config`; the LiveView does not reach into Pico metadata or button persistence directly. Runtime button actions remain below this surface and were already verified in chunk 5 to enter through normal control paths. Target pickers correctly reuse `Picos.Targets` expansion and filter disabled/canonical-linked entities rather than reimplementing hardware vocabulary. Async sync, focused editor coordinators, destructive confirmations, and context-aware binding-form normalization have landed. No open findings remain in 6b-3.

Explicitly fine: control-group metadata storage remains an accepted chunk-5 choice; immediate persistence when adding/removing control-group targets is clearly disclosed in the UI; Pico press learning is PubSub-driven and does not bypass runtime control semantics; direct `Repo.get(Bridge, ...)` is a single page-loader query consistent with the other bridge config surfaces and does not justify a new bridge-context abstraction by itself.

## 6b-4 (part 1): Light State Editor

Status: `light_state_editor_live.ex`, `form_state.ex`, and `preview.ex` audited line-by-line; HEEx audited with full structural scrutiny.

Assessment: the editor respects the architecture boundaries. Persistence stays behind `Scenes`; updates to light states used by active scenes re-enter `Scenes.refresh_active_scenes_for_light_state/1`, which recompiles through the normal desired-state/planner/executor path rather than dispatching hardware from the LiveView. `FormState` is a legitimate shared web boundary used by both this editor and the scene builder, and its manual/circadian vocabulary delegates to `LightState` and `Circadian.Config` rather than duplicating domain parsing. `Preview` is pure presentation projection over `CircadianPreview`. Dirty state now tracks persisted intent only, protects Back/Revert when needed, and ignores preview-only changes. The extensive LiveView suite covers both manual modes, the full circadian field set, validation, preview errors, save variants, revert, usage disclosure, and unsaved-change protection. No open findings remain in this sub-area.

Explicitly fine: the synchronous post-save active-scene refresh is local domain/control work, not bridge I/O, and stays on the established apply pipeline; its best-effort return does not justify moving scene semantics into the UI. The hardcoded preview-timezone shortlist matches the already accepted config-page product choice while retaining any current custom timezone. Chart hook payloads contain only server-produced numeric/time labels, and preview failures retain all form inputs rather than collapsing the editor.

## 6b-4 (part 2): Web Infrastructure + Final HEEx Sweep

Assessment: the remaining web layer is intentionally small. `FilterPrefs` and `SessionId` provide non-sensitive, per-browser presentation persistence and are adequately bounded for a single-house deployment; controllers, endpoint, and error rendering are conventional; the shared flash component correctly uses LiveView's built-in `lv:clear-flash` event. The final template sweep checked explicit button types, form nesting, literal IDs, route targets, and every destructive-looking event. Three buttons omit `type`, but all are outside forms and therefore cannot accidentally submit. Scene-builder remove controls alter only unsaved editor state. Stale exploration/telemetry/Cowboy scaffolding is gone, the live route set is characterized, and unused light-state deletion is styled and confirmed. No open findings remain in this sub-area.

Explicitly fine: the unsigned filter-session UUID is only a cache partition for display preferences, not authentication or authorization state; server-side mutation APIs still validate their own IDs and ownership. Plain navigation links are consistent across this local application and do not by themselves warrant converting the layout to LiveView navigation. Error pages deliberately remain minimal plain text.
