# Audit Chunk 6a: Scene Builder (Web)

Scope: `lib/hueworks_web/live/scene_builder_component.ex` (LiveComponent, 639 lines), `scene_builder_component/state.ex` (769), `scene_builder_component/flow.ex` (150), `scene_editor_live.ex` (434) + its heex. Adjudicates `planning/refactoring.md` item 3 ("Split Scene Builder State") — the last item in that doc.
Status: audit complete; **no open findings** (SB-1/2/4 implemented and removed per the forward-facing rule; `planning/refactoring.md` — whose last item this chunk adjudicated — is deleted).

Overall assessment: the scene builder is now the shape refactoring.md item 3 asked for — a typed `Component` struct with constructor-enforced invariants, `State` as a thin facade over `Membership`/`Policy`/`CustomState`, thin `Flow` delegation, and vocabulary/validity/topology in their domain modules (`PowerPolicy`, `Builder`, `Topology`).

---

## Explicitly Fine (checked, leave alone)

- `Flow` — exactly the thin delegation layer item 3 asked for; don't add logic to it.
- The save path (`Scenes.replace_scene_components` with rollback-by-delete for new scenes, distinct error messages per failure) enters through the domain API correctly.
- Reusing `LightStateEditorLive.FormState` for embedded manual config editing is intentional cross-feature reuse (same form semantics as the light-state editor), not coupling to remove.
- `load_scene_components` reconstructing groups purely by projection (`component_groups` finds groups fully contained in the component's light_ids) rather than persisting group membership — deliberate: groups are optimization projections per planned_architecture.md.

## Test Coverage Assessment

- Coverage is strong across state, component render/events, and full LiveView flows; the SB-1 split landed behind that net plus a single-broadcast activation regression test. Nothing worth adding.
