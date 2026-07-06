# Audit Chunk 5: Integrations

Scope: `lib/hueworks/home_assistant/**`, `lib/hueworks/homekit*`, `lib/hueworks/picos*` — judged against planned_architecture.md's "integrations enter through normal control paths" rule.
Status: audit complete; **no open findings** (IDs IN-1 through IN-6 were all implemented and removed per the forward-facing rule; the SC-2 domain-event design from this chunk is implemented as `Hueworks.DomainEvents`).

Overall assessment: the integration layer passes its central architectural test — every control entry point across all three integrations routes through normal paths (`ManualControl`, `Scenes.activate_scene`, `ActiveScenes`, `PresenceInputs.set_occupied`); no bypasses found anywhere. Integration sync is event-driven (`Hueworks.DomainEvents` + the pre-existing active-scenes and control-state topics); the two deliberately synchronous exceptions are `PresenceInputs.set_occupied`'s HA republish ordering and the import/bridge post-commit removal effects — both load-bearing, do not convert them.

## Leave-Alone Notes (checked, intentional)

- The HomeKit HAP transport/session/pairing layer (`hap.ex`, `hap_session_transport.ex`, `hap_session_handler.ex`, `pairing_state.ex`) is deliberately quirky protocol code owned by the `planning/homekit-control-quality.md` product question — leave it out of refactor passes, including its known redundant-clause compile warning (chunk-7 warnings pass must treat it carefully, not mechanically).
- Pico control groups living in device `metadata` JSON is fine at this scale.
- `Import.Fetch.Common.load_enabled_bridge!`'s raise on multiple HA bridges is the deliberate single-HA-bridge product gate (the control bootstrap no longer shares that assumption).

## CP-3 rider (for the CP-3 implementer)

`Messages.State.fetch_state_value/2` and `state_power_value/1` do dual-key reads of control-state maps ([messages/state.ex](../../lib/hueworks/home_assistant/export/messages/state.ex)); once CP-3's atom-key invariant lands, collapse these to atom reads (the `state_power_value(nil)` dead clause is one of the known compile warnings).

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- All three integrations have suites, now including domain-event subscriber coverage (HA export scene CRUD, HomeKit event reloads), Caseta crash isolation, and `CasetaLeap` transport tests.
- No integration-specific gaps remain worth listing; the HomeKit brightness/color reliability question is product work (`planning/homekit-control-quality.md`), not test debt.
