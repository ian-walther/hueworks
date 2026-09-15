# Hue Command Pacing And Slider Drags

Why the control pipeline paces and retries bridge commands the way it does. Written for
reviewers of the 2026-09 HomeKit work; the decisions apply to every control path (web UI,
scenes, HomeKit, Home Assistant export) because they all dispatch through the same
executor and Hue client.

## The symptom

After the HomeKit control path became fast, dragging a brightness slider in the Home app
on the living room lamps showed two problems: the lamps lagged the finger noticeably, and
the value at the end of the drag sometimes did not take effect (a few seconds later the
slider snapped back to an intermediate level). Tapping the slider once, after the previous
change had settled, always worked.

## What was verified and what is inferred

The symptom above is observed. What follows separates the defects verified by reading and
testing the code from the explanation that ties them to the symptom; no trace tying one
particular lost final write to a specific Hue refusal was captured before the change, and a
type 901 error on its own is the bridge reporting an internal error, not proof of overload.

Verified defects: the executor paced group commands at the light rate; the Hue client
accepted any HTTP 200 without reading the error list; every drag write carried the manual
fade; the executor's pacing clocks advanced only on success and were sampled once per tick
(both found in review and fixed). Plausible explanation for the symptom, given those
defects: a drag is a stream of writes, one every hundred milliseconds or so. Each is
accepted instantly, the HomeKit writer collapses them into one apply at a time per entity,
and the applies become bridge commands at close to the executor's ceiling for the bridge.
Four things then compound:

1. **Group commands were paced like light commands.** The executor had one pacing interval
   per bridge, chosen by bridge type: 100 ms for Hue. Philips' published guidance is
   roughly 10 commands per second to `/lights` with a 100 ms gap, but at most 1 per second
   to `/groups` ([Philips Hue developer support](https://developers.meethue.com/support/);
   the same figures appear in [node-hue-api](https://www.npmjs.com/package/node-hue-api)
   and in Home Assistant's own [rate discussion](https://github.com/home-assistant/core/issues/60745)).
   A group, or a set of lights the planner promoted to a group command, was being driven
   at ten times its budget, and a bridge over budget can shed commands.
2. **Shed commands looked like successes.** The Hue v1 API answers HTTP 200 even when it
   refuses a command; the refusal is an `error` object inside the result list. The client
   accepted any 200 without reading the body, so the executor's retry never fired and
   nothing was logged. The last command of a drag is the one most likely to be shed, which
   is exactly the "final point does not take effect" symptom: the readback cache then
   expires and the slider is corrected to where the bridge actually stopped.
3. **Every command carried the manual fade.** The manual transition setting (500 ms in the
   deployed configuration) applied to each write of the drag, so the lamp was always in the
   middle of an overlapping fade and visibly trailed the slider.
4. **Convergence could not always repair it.** The executor verifies a dispatch after it
   should have settled and re-sends when physical state disagrees with desired state, but
   its brightness tolerance is 2 percent, so a small final adjustment could sit inside the
   tolerance and never be corrected.

None of this is HomeKit-specific. The web UI's sliders and scene activations use the same
executor; the web slider was simply slow enough to apply that the group ceiling was rarely
approached.

## Decisions

### 1. Read the Hue response body and classify refusals

`Hueworks.Control.HueClient.interpret_body/1` decodes the result list. Any `error` object
makes the request a failure. Error type 901 is the bridge's internal error (HTTP 503
semantics: busy, over budget) and is returned as `{:error, {:hue_busy, errors}}`, which
the executor retries with its existing backoff. Every other type is a refusal of the
command as sent (unknown resource, invalid value, "device is set to off", ...) and is
returned as `{:error, {:hue_rejected, errors}}`, which the executor logs as
`executor_dispatch_rejected` and drops rather than retrying, since a retry would only
repeat the refusal. A body that is not a Hue result list is still accepted as before.

Alternative considered: treating every error as retryable. Rejected because parameter
refusals are deterministic and three retries with backoff would triple the bridge load
for no gain.

### 2. Pace group commands separately, at 1 per second

The executor keeps a second timestamp per bridge for the last group request and a group
rate per bridge type (`@default_group_rates %{hue: 1}`; other bridge types have none and
keep pacing group commands like any other). The group rate is looked up only when a bridge
actually receives a group command, because the default lookup reads the bridge record.

Pacing measures requests sent, not requests that succeeded: a busy or rejected answer
still advances both the bridge clock and the group clock, so a retry waits for both its
backoff and the budget, and a refusal does not let the next group command out early.
Actions discarded as stale without a dispatch consume nothing. Each bridge is admitted
against the clock as it stands when its turn in the tick comes, so a slow synchronous
dispatch to one bridge does not hand the next bridge a stale timestamp. A group command at the head of a bridge's
queue that the bridge is not yet ready for lets a light command behind it go first and
keeps its place; nothing is reordered otherwise. The queue's existing replace-targets rule
means only the newest value per target waits, so a drag still ends at the last value.

Both rate tables can be overridden through application configuration
(`:bridge_command_rates` and `:bridge_group_command_rates`, maps from bridge type to
commands per second). The Hue light rate stays at the documented 10 per second; anyone who
wants to be more conservative can set it lower without a code change.

Alternative considered: lowering the whole-bridge rate to 1 per second. Rejected because it
would make individual light control ten times slower than Hue allows.

### 3. Give HomeKit level writes a short transition

`Hueworks.HomeKit.Writer` applies brightness and color writes with a fixed 100 ms
transition (`:homekit_write_transition_ms`; 0 means use the manual fade) instead of the
manual default. It is passed as an unscaled transition policy: the manual fade may be
scaled by brightness delta, which suits a deliberate change from the web UI but would turn
a drag's small steps into near-zero fades and a large tap into a long one. Home Assistant
sends HomeKit brightness with no transition at all; 100 ms keeps a single tap from stepping
visibly while letting a drag track the finger. Power on and off from HomeKit keep the
manual fade. `Hueworks.Lights.ManualControl.apply_updates/4` now forwards `:transition_ms`
and `:transition_policy` options so any caller can do the same.

### 4. Keep the HomeKit coalescing window at 25 ms

Lengthening the writer's coalescing window was considered as a way to send fewer commands
during a drag. It was left at 25 ms because the window applies to every write, including a
single tap, and the two mechanisms above already bound the traffic: while an apply is in
flight, further writes for the same entity merge into one pending apply, and the executor's
pacing bounds what reaches the bridge regardless of how many applies run. The window stays
configurable (`:homekit_write_coalesce_ms`).

## The tradeoff this leaves

The group budget is one request per second per bridge, counting refused attempts, not one
per group or per HomeKit accessory. Four group commands queued for one bridge therefore
take at least three seconds from first to last dispatch, before any retry. Every control
path shares that budget: scenes, Pico buttons, presence changes, and the Home Assistant
export as well as HomeKit. The planner still prefers a compatible hardware group over
individual light commands without weighing that a group command costs ten times a light
command in budget, and even a single light can be sent as a one-member group. Whether the
planner should weigh dispatch cost, and whether a slider should ever drive a group at all,
are open questions to be answered from hardware measurements (see the planning note), not
by raising the group rate or turning group promotion off to make one slider look faster.

## What to verify on hardware

With `ADVANCED_DEBUG_LOGGING=true`, capture three things for each check: the accepted
write (`[homekit] write_accepted`), the actual dispatch (control-trace `dispatch` lines,
with their timestamps), and the observed final value (the light itself and the value the
Home app settles on), rather than judging only the immediate Home app response.

- Drag a brightness slider on a single lamp: it should track the finger with at most a
  short lag and the end value should hold without the slider snapping back seconds later.
- Drag a slider on a group, then on two or three distinct groups on the same bridge in
  quick succession: group dispatches for that bridge should be at least one second apart
  including any refused attempts, and the last value for each group should land.
- Activate a scene that produces several group actions and note how long the last group
  dispatch trails the first; this is the tradeoff above, measured.
- Turn a lamp off and on again immediately after a drag: the power command must not be
  lost behind the drag's remaining writes.
- With one bridge slow or busy (or unreachable) and another healthy, control a light on
  the healthy bridge: it should not wait on the slow one, and its dispatch timestamps
  should reflect when it was actually sent.
- Any `executor_dispatch_rejected` warning means the bridge refused a command as sent and
  is worth reading; a busy bridge shows as a retry in the trace, not a warning.
