# Caseta Transition Support

## Hardware Acceptance

Arrange an attended test before rolling out native Caseta fades. See the [Caseta compatibility notes](../docs/compatibility.md#lutron-caseta) for duration limits.

Use the powder-room Caseta PD-6WCL dimmer. Re-resolve HueWorks light `83`, bridge `3`, zone `22`, and HA entity `light.powder_room_vanity_lights` before testing.

- Use an explicit scene activation transition to request a visible three-second fade in each direction. Keep global transition settings in place during the test.
- Require visual confirmation. A successful response or reported target level alone does not prove the device performed a fade.
- Confirm no retry storm, flicker, or delayed correction while transitioning.
- Check how the one-second minimum feels for presence-driven activation and vacancy-driven shutoff. Test at normal and lower scene brightness to exercise brightness-delta scaling.
- Keep the door/motion logic unchanged: door open OR motion with ten-minute clear hold, no occupancy overrides.
- Leave the light in its normal scene-driven state after testing.

If the bridge rejects the explicit fade command or the hardware ignores it, stop and document that limitation rather than silently treating it as working. Decide any compatibility fallback separately from the initial implementation.

## Shutoff Convergence Follow-up

Use powder-room trace `scene-7-303851522` from 2026-11-06 23:22:25-29 UTC as a regression scenario for redundant off commands. HueWorks had already observed off before each of the three retries. The planner treats explicit off as actionable even when the observation matches. Preserve intentional initial off dispatches while making post-dispatch verification distinguish confirmed off from missing or disagreeing feedback.

## Deferred Decision

After native fade support is verified, decide whether existing global/scene transition controls provide the desired presence fade. Only add a scoped presence/per-light setting if necessary and approved. A broader transition-policy redesign is outside this task.
