# HomeKit Control Quality

Reference for the current design, library assessment, and hardware smoke procedure: [HomeKit Internals](../docs/homekit-internals.md). Bridge pacing and its remaining hardware checks are documented in [Hue Command Pacing](../docs/hue-command-pacing.md).

## Scope
This is a hardware-validation and future-quality backlog, not an implementation checklist for the existing control path. On/off and brightness have been used against Apple Home; that evidence does not establish color/temperature quality, identity lifecycle behavior, or multi-bridge performance. Keep unverified cases explicit rather than treating either the entire integration as untested or the entire smoke checklist as passed.

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

Blocking brightness, color, and temperature writes while a HueWorks scene is active in the area is intentional: the scene owns those attributes. Preserve refusal with HAP status `-70404`, allowing the Home app to revert the control, rather than changing exposure dynamically.

## Library Stance
Keep the vendored `hap` fork scoped to identity, as documented in `vendor/hap/FORK.md`. No upstream PR is planned. Only consider expanding the fork or replacing the server if hardware testing demonstrates a further structural limitation, such as manager-process serialization, originator exclusion, or the lack of a service-level setter.

## Remaining Work
- Hardware checks still open: color and temperature round-trips, the fresh-install bridge accessory, identity survival across un-expose and re-expose, a group slider drag after the pacing fixes, several groups on one bridge, a multi-group scene, and a slow bridge beside a healthy one. Follow the reference procedures above and update `README.md` and `docs/compatibility.md` only as each is verified.
- Measure, on hardware, how long a multi-group scene's last group dispatch trails its first under the one-per-second-per-bridge group budget, before deciding whether the planner should weigh group-command cost against individual light commands (`docs/hue-command-pacing.md`, "The tradeoff this leaves").
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
