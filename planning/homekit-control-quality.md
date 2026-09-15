# HomeKit Control Quality

Reference for the current design, the library assessment, and the history behind it: `docs/homekit-internals.md`.

## User Experience Problem
The HomeKit integration is useful but not yet proven good enough for daily brightness control.

Observed before the 2026-09 control-path changes:
- On/off control works well.
- Scene-based usage is acceptable because on/off is usually enough when HueWorks scenes are active.
- Brightness control is laggy to the point of not being usable when no HueWorks scene is active.

The control-path changes (non-blocking writes, On + Brightness coalescing, optimistic reads, deduplicated notifications, persistent HAP connections, integer status codes, frame reassembly), stable accessory IDs, and color/temperature exposure are in and covered by tests, but have not been exercised against Apple Home on hardware yet.

## Desired Outcome
HomeKit should feel trustworthy for daily control, not just technically connected.

From the user's perspective:
- On/off control should stay reliable.
- Brightness changes should apply consistently when direct HomeKit control is allowed.
- Color and temperature changes should either work predictably or not be exposed as supported controls.
- HomeKit state should recover cleanly after app restarts, Home app restarts, and bridge reconnections.
- HomeKit should not create confusing duplicate or stale controls.

## Current Product Stance
On/off support is the stable baseline.

Brightness, color, and temperature support stay "available, not release-quality" until the hardware smoke test in `docs/homekit-internals.md` passes.

Blocking brightness, color, and temperature writes while a HueWorks scene is active in the area is intentional: the scene owns those attributes. Decided 2026-09-07: HomeKit is told the write is refused (HAP status `-70404`) and the Home app reverts the control, matching the web UI. Exposure is not changed dynamically; the reasons are in `docs/homekit-internals.md`.

## Library Stance
The app uses an identity-only fork of the `hap` library (mtrudel/hap 0.6.0), vendored at `vendor/hap` as a path dependency and documented in `vendor/hap/FORK.md`. Decided 2026-09-14: the fork exists because stable accessory and characteristic identities could not be achieved from the app side without placeholders and layout tricks that still failed on capability loss. Keep the fork to identity. No upstream PR; the work stays local. Rolling our own HAP server remains on the table only if a further structural limitation (manager-process serialization, originator exclusion, a service-level setter) is actually hit on hardware.

## Remaining Work
- Hardware checks still open (steps in `docs/homekit-internals.md`, "Verification status", and `docs/hue-command-pacing.md`, "What to verify on hardware"): color and temperature round-trips, identity survival across un-expose and re-expose, a group slider drag after the pacing fixes, several groups on one bridge, a multi-group scene, and a slow bridge beside a healthy one. Update `README.md` and `docs/compatibility.md` as each is verified.
- Measure, on hardware, how long a multi-group scene's last group dispatch trails its first under the one-per-second-per-bridge group budget, before deciding whether the planner should weigh group-command cost against individual light commands (`docs/hue-command-pacing.md`, "The tradeoff this leaves").
- Local development databases created on this branch before the fork carry the earlier `homekit_accessory_ids` shape; `mix ecto.reset` brings them current. Production has never run either shape.
- Confirm on the production host that HAP connections now persist past 60 seconds idle.
- Decide whether to upgrade `hap` to 0.7.0. It changes nothing for control latency and pulls newer `mdns_lite`, `hkdf`, and `eqrcode`.

## Open Decisions
- **Group-command cost in the planner.** The group budget is one request per second per bridge, shared by every control path. The planner prefers hardware groups without weighing that cost. Decide from the measurement above whether to weigh it, and whether sliders should drive groups at all. Do not raise the group rate or disable group promotion to make one slider look faster.
- **Rewrite trigger.** Only worth deciding if the forked, wrapped design still shows latency on hardware.

## Non-Goals For This Planning Note
- Do not resurrect the old HomeKit implementation plan.
- Do not make public-readiness claims for brightness, color, or temperature support before the hardware smoke test.

## Open Questions
- What is the minimum acceptable latency for HomeKit brightness writes?
- Should unsupported or unreliable HomeKit capabilities be hidden until they meet the same reliability bar as on/off?
- What observability beyond the `[homekit]` debug log lines would make HomeKit failures diagnosable without tailing logs?
