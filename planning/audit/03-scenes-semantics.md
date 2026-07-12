# Audit Chunk 3: Scenes & Semantics

Scope: `lib/hueworks/scenes/**`, `lib/hueworks/scenes.ex`, `lib/hueworks/circadian.ex`, `lib/hueworks/circadian/config.ex`, `lib/hueworks/circadian_preview.ex`, `lib/hueworks/presence_inputs.ex`, `lib/hueworks/external_scenes.ex`. (`scenes/apply.ex` and `active_scenes.ex` were read in chunk 1; their findings live there.)
Status: complete (all files in scope read).

Overall assessment: this layer is in better architectural shape than expected. Scene intent compiles cleanly into desired-state transactions (power policy via the shared `Scenes.PowerPolicy` module), manual-power latch and force/follow semantics match planned_architecture.md, integration sync flows through `Hueworks.DomainEvents` rather than inline calls, and `Circadian.Config` is the best boundary module in the codebase — it is the reference pattern for the normalize-at-boundaries work (CP-3). Test coverage here is the strongest in the app (intent, components, builder, activation round-trip, queueing, presence, and circadian *reference-parity* suites). The only open finding is the deliberately deferred SC-5.

Parked question resolved during this chunk: chunk 2's "verify external scene activation enters through normal paths" — confirmed: `ExternalScenes.activate_home_assistant_scene` resolves the mapping and calls `Scenes.activate_scene`. No parallel path. Nothing to do. (Finding IDs are stable; gaps in numbering mean the finding was implemented and removed.)

---

### SC-5: Circadian.calculate recomputes solar events several times per call
- Severity: low
- Type: refactor (deliberate no-op until cost shows up — document, don't fix speculatively)
- Where: [lib/hueworks/circadian.ex:66-84](../../lib/hueworks/circadian.ex) (`build_context` computes all three curves' events purely to validate, then discards them), [circadian.ex:208-246](../../lib/hueworks/circadian.ex) (`prev_and_next_events` recomputes ±1-day event sets on every evaluation; `calculate/3` triggers this separately for shared/brightness/temperature curves)
- What: one `calculate/3` call computes sun-event sets on the order of a dozen times. It runs per circadian component per active scene per poller tick (60s default) — measured in microseconds-to-milliseconds at home scale, so currently harmless, but it is the hottest pure function in the app and the structure hides that the context already *had* the events.
- Decision: no change now. If the poller ever shows up in profiles or the tick interval shrinks, the fix is: compute the per-curve 3-day event windows once in `build_context` and thread them through `sun_position`/`brightness_pct`/`color_temp_kelvin`. The `circadian_reference_test.exs` parity suite makes that refactor safe whenever it happens.
- Effort: — (M when triggered)

---

## Explicitly Fine (checked, leave alone)

- `Circadian.Config` — exemplary boundary module: accepts loose maps, validates via embedded schema changeset, emits typed runtime maps with defaults. **Reference pattern for CP-3.** Do not "simplify" it.
- Manual-power latch semantics in `Intent` (`maybe_preserve_manual_power_latch` + `overridable?` gating) match planned_architecture.md's manual-control rules exactly, including collapsing the latched state to power-only (consistent with desired-state `drop_light_levels`).
- `Scenes.Builder` — pure projection with good validity rules.
- `ExternalScenes` — mixed-key handling is at a genuine external boundary (HA entity payloads), which the architecture explicitly permits; managed-scene filtering prevents HueWorks-exported scenes from looping back in. Leave as is.
- `PresenceInputs.set_occupied` ordering (persist → HA republish → active-scene refresh) is correct and load-bearing.

## Test Coverage Assessment

- This chunk has the best coverage in the app; explicitly leave the circadian reference-parity suite alone — it is what makes SC-5 safely deferrable.

## Parked (noted early, belongs to later chunks)

- Chunk 6a: the scene-builder state split (refactoring.md item 3) is now unblocked — the policy vocabulary lives in `Scenes.PowerPolicy` and `scene_builder_component/state.ex` only delegates to it; re-scope the split during the 6a audit.
- Distillation: name `Circadian.Config` as the boundary-module template when sequencing CP-3.

## Suggested Implementation Order (for cheap-model sessions)

Nothing actionable: SC-5 stays deferred until a real perf trigger.
