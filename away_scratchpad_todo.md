# Away Scratchpad TODO (Temporary)

Not for commit. Short-lived checklist for travel week work.

## Do While Away (Remote-Verifiable)
- [ ] External scenes: add `external_scenes` + `external_scene_mappings` schemas/context APIs.
- [ ] External scenes: HA import/resync for `scene.*` entities.
- [ ] External scenes: mapping UI + sync actions.
- [ ] External scenes: HA `scene.turn_on` event handling -> `Scenes.activate_scene/1`.
- [ ] External scenes: add end-to-end tests (sync, mapping, activation, disabled mapping no-op).
- [ ] Circadian: implement dedicated calculator module and config validation.
- [ ] Circadian: wire scene apply path for `:circadian` brightness/kelvin targets.
- [ ] Circadian: wire global solar config (`lat/lon/timezone`) reads.
- [ ] Circadian: add regression tests for active-scene + manual power semantics.
- [ ] Production: finalize Docker runtime contract and compose baseline.
- [ ] Production: add release migration command flow + README runbook draft.
- [ ] Quality: expand subscription/control failure-path tests.
- [ ] Refactor: move GenServers under top-level `hueworks_app`.
- [ ] Seeds: design/implement arbitrary bridge secret loading (`*_1..N` or `secrets.json`).
- [ ] Seeds: add initial Z2M seeding support.

## Leave For Home (Needs Visual Validation)
- [ ] Transition-time behavior for scene on/off feels right on real lights.
- [ ] No-popcorning behavior looks synchronized across bridges in-room.
- [ ] Final circadian perceptual checks at low-end kelvin transitions.
- [ ] Final manual override UX behavior validation in real usage.

## Remote Verification Checklist
- [ ] Confirm expected outbound payloads in logs for HA/Hue/Z2M actions.
- [ ] Confirm desired vs physical state convergence in logs/state tables.
- [ ] Confirm active scene activation/deactivation events are emitted as expected.
- [ ] Confirm no repeated unexpected active-scene deletions during idle periods.

