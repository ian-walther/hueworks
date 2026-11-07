# Circadian Timing And Global Bounds

This document describes how circadian light states resolve sunrise and sunset, and the Home Assistant contract for the house-wide bounds.

## Global Bounds

General Configuration holds four optional bounds: sunrise minimum and maximum, and sunset minimum and maximum. They are local wall-clock times in the configured timezone, entered as `HH:MM` or `HH:MM:SS` and stored as `HH:MM:SS`. A fraction, UTC suffix, or offset is rejected rather than stored or discarded.

- Blank means unconstrained. Midnight is a real value, never a stand-in for disabled.
- Each min/max pair is a same-day window. A minimum later than its maximum is rejected, not read as an overnight range. Equal bounds pin the event to that time.
- All four start blank. HueWorks ships no default bound.

## Inheritance

Each circadian light state has independent `override_sunrise_timing` and `override_sunset_timing` flags. These live on the light state, so a profile edit reaches every scene that uses the profile.

| Event | Base | Shared offset | Bounds | Curve offsets | Ramp durations |
| --- | --- | --- | --- | --- | --- |
| Inherited (`false`) | Astronomical | None | Global pair | None | Defaults: 900 s dark, 3600 s light |
| Overridden (`true`) | Stored fixed time, or astronomical | Stored | Local pair only | Stored | Stored |

- Inheritance disables all profile-specific timing shaping for that event, even when the global bounds are blank. Values stored for an inherited event are kept and take effect again when its override is re-enabled.
- The local pair replaces the global pair entirely. A blank local bound never falls back to a global one.
- With mixed flags, the stored durations apply only around the overridden event.
- Brightness curve type, brightness and Kelvin ranges, and the temperature ceiling are always per-profile.
- Noon and midnight anchors use effective timing. Any effective fixed time or bound moves noon to the midpoint of sunrise and sunset, even when the bound does not bind. Inheritance alone, or an ignored stored value, does not.
- Overridden events apply the shared offset before clamping and curve offsets after it, so a curve offset can move that curve outside the local bounds.

`Hueworks.Circadian.Timing` is the single resolver. `Circadian.prepare/2` loads it once, and runtime, preview samples, and every preview marker evaluate that same result.

Flag values:

- New profiles are created with explicit `false` flags.
- A profile missing a flag keeps local behavior. The upgrade to global bounds wrote explicit `true` flags on existing circadian profiles.
- Duplicating a profile copies its flags and stored values.

The editor locks the controls of an inherited event and shows its effective values. Stored values stay underneath, and the server ignores submitted values for locked controls. Shared ramp controls are locked only when both events inherit.

A stored local window is checked only while its event is overridden. An inherited event may keep an inverted window, which has no effect; re-enabling the override is rejected until the pair is valid. Stored times must still be well formed.

## Calendar Dates

Sun events resolve for the configured local calendar date, including near the date line. Bounds and fixed times that fall in a daylight saving gap use the instant after the gap. Ambiguous times use the first occurrence.

## Validation And Failures

- `AppSettings` reads come straight from the database, so nobody sees an uncommitted write. Writers patch the latest persisted row in their own immediate transaction, and subscribers read current values after the `{:global_settings_changed, fields}` domain event that follows the commit.
- Settings writers refuse to run inside a surrounding transaction and return `{:error, :nested_settings_transaction}`, because that transaction could still roll back after the change is announced.
- An edit is rejected if it introduces an invalid sun event order for a profile on the current local date, and the error names the profile. A conflict that already existed does not block unrelated edits. Nothing is disabled or rewritten to resolve a conflict.
- The order check is the existing cyclic-day check: sunrise, noon, sunset, and midnight must follow each other in that rotation, starting from any of them. It is not an absolute sunrise-before-sunset rule, so a sunrise bound later than a sunset bound is valid and sets noon and midnight from that order.
- Astronomical unavailability, such as a polar day here or on a neighboring day, is a calculation failure, not a validation error. It does not block settings edits.
- When a calculation fails, explicit off intent is still honored. Otherwise each light's existing desired state stands: HueWorks never fabricates targets or emits an on command without them, so a light that is off stays off until targets are available. A manual power command returns display attributes only when every requested light was applied, so the web controls and Home Assistant leave a held light showing its observed state. HomeKit answers writes before applying them, so it can show a held light as on until its 5-second value cache expires.

Active scenes pick up accepted changes on the normal circadian poll. A settings change dispatches nothing itself, and it does not switch scenes or clear manual power retention.

## Home Assistant Contract

When Home Assistant export is enabled, HueWorks publishes one MQTT `text` entity per bound. HueWorks owns the values; Home Assistant edits them through HueWorks.

| Entity | Name | Setting |
| --- | --- | --- |
| `text.hueworks_sunrise_minimum` | Sunrise minimum | `min_sunrise_time` |
| `text.hueworks_sunrise_maximum` | Sunrise maximum | `max_sunrise_time` |
| `text.hueworks_sunset_minimum` | Sunset minimum | `min_sunset_time` |
| `text.hueworks_sunset_maximum` | Sunset maximum | `max_sunset_time` |

The entities belong to a `HueWorks` device with entity category `config`. Unique IDs are `hueworks_setting_<setting>`.

### Reading

The entity state is the accepted value as `HH:MM:SS`, or an empty string when the bound is unset. `unknown` and `unavailable` never mean unset: `unavailable` means HueWorks is offline.

### Writing

Use the normal service. An empty value clears the bound:

```yaml
service: text.set_value
target:
  entity_id: text.hueworks_sunset_minimum
data:
  value: "18:00"
```

Accepted formats are `HH:MM` and `HH:MM:SS` with two-digit hours, so a published value never exceeds the entity's eight characters. Home Assistant shows only what HueWorks accepted. A rejected value leaves the last accepted value in place, and HueWorks logs the reason and republishes that value. Repeating an accepted value changes nothing and dispatches nothing.

Commands use the same validation as General Configuration, including pair order and event order conflicts.

### Topics

| Purpose | Topic | Retained | Payload |
| --- | --- | --- | --- |
| Discovery | `<discovery_prefix>/text/hueworks_setting_<setting>/config` | Yes | Discovery JSON |
| State | `hueworks/ha_export/settings/<setting>/state` | Yes | `{"value":"18:00:00"}` or `{"value":""}` |
| Command | `hueworks/ha_export/settings/<setting>/set` | No | `{"value":"18:00","session":"<session>"}` |
| Availability | `hueworks/ha_export/status` | Yes | `online` or `offline` |

- The state payload is an envelope because an empty retained MQTT payload would delete the message instead of reporting an unset bound.
- A blank or `null` command value clears the bound. An empty MQTT payload is a retained-message deletion and is ignored on every command topic.
- The broker publishes `offline` through the connection's last will when HueWorks disconnects uncleanly. HueWorks reports `online` after each connection.

### Stale Commands

A retained command must not replay over newer settings, and the MQTT client does not expose the retain flag to its handler. Every connection therefore gets a new random session, written into the discovery `command_template` so Home Assistant sends it with each command. HueWorks accepts a command only if its session is the current one.

The handler forwards the connection event and every message from one process, so a new connection is always processed before anything its subscription replays. A command published during a reconnect, before Home Assistant has the new discovery payload, is rejected and has to be sent again. Sending commands by hand requires the session from the current discovery payload.

Unique IDs and entity IDs do not change when the session does. Disabling export deletes the discovery and state messages.
