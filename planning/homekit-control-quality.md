# HomeKit Control Quality

## User Experience Problem
The HomeKit integration is useful but not good enough yet.

Current observed behavior:
- On/off control works well.
- Scene-based usage is acceptable because on/off is usually enough when HueWorks scenes are active.
- Brightness and color control are unreliable or laggy when no HueWorks scene is active.

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

Brightness/color support should be treated as incomplete until another focused pass proves that it is reliable enough for normal use.

## Non-Goals For This Planning Note
- Do not resurrect the old HomeKit implementation plan.
- Do not choose whether to keep the current HAP library, fork it, or replace it.
- Do not design the protocol-level fix yet.
- Do not make public-readiness claims for brightness/color support.

## Open Questions
- Should HueWorks expose brightness/color controls to HomeKit only when no scene is active?
- Should unsupported or unreliable HomeKit capabilities be hidden until they meet the same reliability bar as on/off?
- What is the minimum acceptable latency for HomeKit brightness/color writes?
- What observability would make HomeKit failures diagnosable without tailing logs?
