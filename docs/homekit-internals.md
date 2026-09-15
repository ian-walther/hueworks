# HomeKit Internals

Reference for how the HomeKit bridge is built, why it is built that way, and how it compares with other HomeKit accessory implementations. Forward-looking decisions live in `planning/homekit-control-quality.md`.

## Stack

App side:

- `lib/hueworks/homekit.ex` — facade: reload, pairing status, reset pairings.
- `lib/hueworks/homekit/bridge.ex` — GenServer that builds the accessory graph, starts and stops the HAP supervisor, holds HAP change tokens, reconciles the value cache against observed state, and sends debounced, deduplicated change notifications. Also runs the pairing watchdog.
- `lib/hueworks/homekit/accessory_graph.ex` — builds `HAP.AccessoryServer` from exposed lights, groups, and scenes, laid out by persisted accessory ID. Lights and groups become a LightBulb service with `on`; `homekit_export_mode: :light` adds `brightness`, plus `hue` and `saturation` when the entity has `supports_color` and `color_temperature` when it has `supports_temp`. Scenes become a Switch service.
- `lib/hueworks/homekit/accessory_ids.ex` and `lib/hueworks/schemas/homekit_accessory_id.ex` — permanent identities per serial number (`light-12`, `group-3`, `scene-7`): the accessory ID and the instance ID of every characteristic ever published, stored in the `homekit_accessory_ids` table.
- `lib/hueworks/homekit/light_bulb_service.ex` and `lib/hueworks/homekit/characteristics/color_temperature.ex` — the LightBulb service built on the library's `HAP.ServiceSource` extension point, emitting explicit instance IDs and the 140 to 500 mired color temperature range instead of the library's 50 to 400.
- `vendor/hap/` — the vendored, identity-only fork of the hap library (see `vendor/hap/FORK.md`).
- `lib/hueworks/homekit/value_store.ex` — `HAP.ValueStore` implementation. Validates writes, answers reads, and returns HAP integer status codes on failure.
- `lib/hueworks_app/homekit/writer.ex` — applies writes off the HAP request path, coalescing per entity, each apply in its own supervised task under `Hueworks.HomeKit.TaskSupervisor`.
- `lib/hueworks_app/homekit/value_cache.ex` — ETS cache of the last value HomeKit wrote per characteristic. Each write carries a generation so a failed apply drops only its own entry, never a newer write of the same value.
- `lib/hueworks/homekit/status.ex` — HAP status code constants.
- `lib/hueworks/homekit/hap.ex` — supervisor that starts the library's children plus Bandit with the app's own handler and transport and `read_timeout: :infinity`.
- `lib/hueworks/homekit/hap_session_transport.ex` — app override of the library transport: chunks outbound data into 1024-byte encrypted frames and reassembles inbound frames across TCP reads. Once a session is encrypted, `recv/3` reads whatever is on the wire, decrypts whole frames, and serves plaintext from a buffer (at most the requested byte count, or everything buffered for a zero-length read) within the caller's timeout budget, because Bandit's body reader asks for plaintext byte counts that say nothing about encrypted frame sizes.
- `lib/hueworks/homekit/hap_session_handler.ex` — app override of the library handler: buffers partial inbound frames, delegates requests to `Bandit.HTTP1.Handler`, pushes HAP `EVENT` messages.
- `lib/hueworks/homekit/entities.ex`, `config.ex`, `pairing_state.ex` — entity queries, stable identifiers and pairing code, pairing persistence.

Library side (`hap` 0.6.0 fork, `vendor/hap`, a path dependency):

- `HAP.AccessoryServerManager` — one global GenServer holding the accessory tree. Every read, write, and value-changed notification is a call or cast into it, and value-store callbacks run inside it.
- `HAP.AccessoryServer` — `get_characteristics`, `put_characteristics`, `value_changed`.
- `HAP.EventManager` — subscription registry from `{aid, iid}` to connection pids.
- `HAP.EncryptedHTTPServer` — Plug router for `/accessories`, `/characteristics`, `/pairings`, `/prepare`.

## Write path

1. The Home app sends `PUT /characteristics`. The session handler decrypts the frame (buffering a partial one until the rest arrives) and hands the request to Bandit.
2. The library calls `Hueworks.HomeKit.ValueStore.put_value/2` inside its manager process. The value store resolves the control target (area and member lights), normalizes the value, and checks whether the characteristic is writable right now. Brightness is refused with `-70404` while a HueWorks scene owns the area. Failures are HAP integer codes.
3. On acceptance the value store records the value in `Hueworks.HomeKit.ValueCache` (which returns a generation for the entry), submits it with that generation to `Hueworks.HomeKit.Writer`, and returns `:ok`. The HAP response goes out at this point; no planner, executor, or bridge work has happened yet.
4. The writer buffers writes per entity for `homekit_write_coalesce_ms` (default 25 ms). `On` and `Brightness` sent together in one request, or in quick succession, become one desired-state transaction: power on at the manual baseline color temperature with the requested brightness, rather than a power-on at baseline brightness followed by a dim. A write only merges into an earlier pending write for the same entity if nothing for that area was accepted in between; an intervening write for the area is a coalescing boundary and the new write becomes a separate later entry, so an older power instruction is never carried past a newer command just because a later brightness write shares its accessory.
5. Once its window elapses the write is ready. Pending writes are kept in acceptance order and everything in an area shares state (the active scene, its power-override map, overlapping groups), so a ready write starts only when its area has no in-flight apply and no earlier pending write, ready or not. Applies within one area therefore run one at a time in acceptance order (a later-accepted scene for the area always ends up active, and two lights turned off under a shared scene both land in the override map), while different areas proceed concurrently. The task applies the write through `Hueworks.Lights.ManualControl` with a `homekit` trace, then the normal planner and executor path dispatches to the bridge. A failed or crashed apply, including an `Executor.enqueue` call timing out behind a stalled bridge, is logged and only the cache entries owned by that write's generation are invalidated, so reads fall back to observed state without disturbing a newer accepted write, and no other apply is affected.
6. The bridge event stream reports the new state. `Hueworks.Control.State` broadcasts it, the bridge drops any cached value the observation now agrees with, and schedules a notification.

Scene switches follow the same shape: the value store records the intended state, the writer activates or deactivates the scene, and the entry for that write's generation is dropped as soon as the database has the new active scene.

## Read and notification path

- `get_value` returns the cached last-written value when one exists and is younger than `homekit_value_cache_ttl_ms` (default 5000 ms); otherwise it maps observed control state (`power` to `on`, `brightness` clamped to 0..100, defaulting to 100 when unknown).
- The bridge records the current value of every characteristic when HomeKit subscribes to it. On each control-state broadcast it schedules one notification per entity after `homekit_notify_debounce_ms` (default 100 ms), then notifies only the characteristics whose readable value differs from the last value it notified. A burst of group re-derivations collapses to one event, and HomeKit's own write does not echo back with a stale value.
- The cache broadcasts every write (with its characteristic and value) and every clear on `Hueworks.HomeKit.ValueCache.topic/0`. On a write the bridge first records the written value as what the writing controller now believes, then pushes the current readable value at once, without the debounce: normally that is the written value, so other controllers learn it (the library cannot exclude the originator, which receives an echo of what it wrote); if a fast failure has already cleared the cache, the push carries the observed value and corrects the writer immediately. The bridge then re-reads when the entry's TTL expires, and on every clear or invalidation, so a controller that was told the written value learns what the bridge actually settled on, whether the device quantized it (72 after a write of 73) or never moved at all (back to 42 after a dropped command), without waiting for another hardware report.
- `HAP.value_changed/1` still fans the event out to every subscribed controller, including the one that wrote, because the library has no originator exclusion. The value it carries is the same one the writer already has, so this is harmless.

## Tuning and diagnostics

| Key | Default | Effect |
|---|---|---|
| `:homekit_write_coalesce_ms` | 25 | Window in which writes for one entity merge into one transaction |
| `:homekit_value_cache_ttl_ms` | 5000 | How long a written value is served to reads before observed state takes over |
| `:homekit_notify_debounce_ms` | 100 | Delay before notifying HomeKit of a state change, per entity |
| `:homekit_write_transition_ms` | 100 | Fade applied to HomeKit brightness and color writes; 0 uses the manual fade |
| Thousand Island `read_timeout` | `:infinity` | HAP connections are never closed for being idle |

Bridge-side pacing of the commands these writes produce, and why slider drags needed it, is in `docs/hue-command-pacing.md`.

With `ADVANCED_DEBUG_LOGGING=true` each write logs `[homekit] write_accepted` (time to answer HAP) and `[homekit] write_applied` (coalesce wait, apply time, result). The apply then appears in the control-trace logs under a `homekit-<kind>-<id>-<n>` trace id.

## Stable identities

Apple Home keys rooms, custom names, scenes, and automations on an accessory's ID and on the instance IDs of its characteristics. Upstream hap derives both from list position (accessories by index in the list, services and characteristics by index within the accessory after unset characteristics are dropped), so exposing, removing, or reordering anything renumbered whatever came after it and the Home app treated the renumbered controls as replaced. Placeholders and persisted orderings were tried first and could not cover capability loss; the fix is the vendored fork.

`Hueworks.HomeKit.AccessoryIds` is the source of truth. `assign/1` gives every serial number a permanent accessory ID on first sight; `instance_ids/1` gives every characteristic type an entity publishes a permanent instance ID (plus one for the control service). Neither is ever reused or reassigned: an entity that stops being exposed keeps its accessory ID for when it returns, leaving a gap the fork handles, and a characteristic that stops being published keeps its instance ID and gets it back when the capability returns. Requests for an unpublished ID fail with `-70409` instead of resolving to a neighbour. Reset Pairing leaves the table alone.

HAP requires accessory ID 1 to represent the bridge itself. A fresh install reserves ID 1 for a bridge accessory (bridge name, model, the bridge identifier as serial number; Accessory Information and Protocol Information only) before any entity is numbered, so entities start at 2 as they do in HAP-NodeJS. Until pairing completes, including after Reset Pairing, only a bridge accessory at ID 1 is published, then the children follow; Apple Home's add flow is unchanged. The shell is built independently of the full graph, so an upgraded install whose first entity normally holds ID 1 pairs against a bridge accessory there and gets the entity back at ID 1, with its own instance IDs, once paired. An install that was already paired when identities were first persisted keeps the positional numbering it has always published, with its first entity at 1; the bridge accessory fills ID 1 only while that entity is not exposed, so a primary accessory always exists and the entity gets its own ID back when it returns. The two cases are told apart by pairing state at first assignment.

First assignment otherwise reproduces what the positional scheme published before: accessories in lights, groups, scenes order (each by name); the control service at 1025; its characteristics at 1027, 1029, ... in the service's default order (On, Brightness, Name, then Color Temperature, Hue, Saturation), which for the shapes an existing install publishes gives exactly the old numbers. `test/hueworks/homekit_test.exs` proves it by comparing the explicit tree against the positional one for the same configuration. Scenes use the library's Switch service positionally; its shape never changes.

## Color and temperature

Exposure follows capability, as in Home Assistant: in `:light` export mode, `supports_color` publishes Hue and Saturation and `supports_temp` publishes Color Temperature. HomeKit speaks hue (0 to 360), saturation (0 to 100), and mireds; HueWorks stores CIE xy and kelvin.

- Reads: xy becomes hue/saturation through `Hueworks.Color.xy_to_hs/2`; kelvin becomes mireds clamped to 140..500. When the light is in temperature mode (kelvin, no xy) the hue/saturation reported are those of the color temperature, so the Home app color wheel matches the warm white instead of showing a stale color.
- Writes: mireds become kelvin clamped to the entity's effective range from `Hueworks.Kelvin.derive_range/1` (calibrated over reported, extended where configured, the same range the web UI, API, and Home Assistant export use). Hue and saturation become xy. When only one of the pair arrives, the other comes from committed intent: the desired state of the target's lights as the previous apply in the area's sequence left it, falling back to observed state only for lights with no color intent. The readback cache is never used for this, since it may already hold a later pending write. A brightness of 0 is a power-off request. A power-on that carries a color replaces the manual baseline color temperature rather than sitting beside it.
- Mode changes, Home Assistant's rule: while a write is buffered, a color temperature write cancels a pending hue/saturation and a hue or saturation write cancels a pending color temperature. Beyond the buffer, accepting a write in one color mode invalidates every cache entry of the other mode written before it (by generation), including entries from applies already completed or still in flight, so a confirmed temperature is not masked by a stale hue and never feeds into a later partial color write. Newer accepted writes are never touched.
- Cache reconciliation compares hue and saturation within 2 and mireds within 5, because color round-trips through xy and kelvin.
- The scene-active refusal applies to hue, saturation, and color temperature exactly as it does to brightness.

## Error codes

HomeKit requires integer status codes in characteristic responses. The value store uses: `-70402` target not controllable, `-70404` brightness or color refused because a scene owns the area, `-70409` unknown target or characteristic, `-70410` invalid value.

## Why exposure is static

While a HueWorks scene owns an area, brightness and color writes from HomeKit are refused with `-70404` and the Home app reverts the control. This matches the web UI, which refuses manual adjustment in that state, and the scene switches HomeKit already sees are the way to leave a scene. The alternative of hiding brightness or making it read-only whenever a scene is active was evaluated and rejected:

- HAP does allow it: adding or removing a characteristic, or changing its permissions, is an attribute-database change signalled by incrementing `c#` in the mDNS record, after which controllers re-fetch the tree. Homebridge uses it for plugin configuration changes.
- It is a configuration change, not a state change. The Home app stores its scenes and automations per characteristic, so actions that set that light's brightness are dropped or fail whenever brightness disappears, and deactivating the HueWorks scene does not restore them.
- Every paired controller refreshes the whole bridge on each change and shows the accessories as updating meanwhile.
- The library computes the tree once at startup, so each change would restart the HAP supervisor and drop every session for a few seconds, unless the library is forked to update the tree in place.
- Characteristic IDs within the accessory would shift on every change.

## Library assessment

`hap` (mtrudel/hap) is the only known Elixir HAP implementation. It is usable but minimal. Its shortcomings relevant to control latency: one global process serializes all value-store work; no originator exclusion; no event coalescing; no service-level setter; no timeout configuration; no inbound frame reassembly; outbound frames not chunked to 1024 bytes in 0.6.0; `put_value` errors documented as strings.

Everything except identities and the shared manager process is wrapped from the app side by the modules above, and the manager stops mattering once `put_value` returns in microseconds. Identities needed the library itself, so HueWorks carries an identity-only fork at `vendor/hap` (base 0.6.0, explicit `aid`/`iid` support with positional fallback, plus two backported upstream compatibility fixes so the library's own suite runs; details in `vendor/hap/FORK.md`). Keep the fork to that scope; the remaining structural items (manager-process serialization, originator exclusion, a service-level setter) are not needed today.

The fork is based on 0.6.0. Version 0.7.0 was published to Hex on 2026-08-19 from the "Version bump to 0.7.0" commit (5f7f0df) on `main`; no git tag or GitHub release was pushed, which is why Hex and GitHub appear to disagree. The repository is active (Dependabot bumps of Bandit and mdns_lite). Core changes since 0.6.0: a `bandit_opts` field merged over the library's Bandit defaults (moot for HueWorks, which replaces the supervisor); `handle_connection/2` and `connection_information/1` compatibility shims; a debug-level `Plug.Logger`; write-response support (`put_value` may return `{:ok, response}`); Television, Input Source, and Television Speaker services; a Thermostat characteristic fix. None of the latency shortcomings changed, and the `put_value` error typespec still says `String.t()`. Upgrading pulls `mdns_lite ~> 0.9.0`, `hkdf ~> 0.3.0`, and `eqrcode ~> 0.2.0`.

## Comparison with other implementations

| Behavior | Home Assistant / HAP-python | HAP-NodeJS (Homebridge) | HueWorks + hap |
|---|---|---|---|
| Write blocks on device command | No, service call fired async, 204 returned immediately | Plugin dependent | No, writer applies off the request path |
| On + Brightness merged into one command | Yes, service-level setter, 10 ms coalesce window | Plugin dependent | Yes, 25 ms window in the writer |
| Echo event to originating controller | No (sender excluded) | No (originator excluded) | Yes, but only with the value it wrote |
| Event coalescing | No | Yes, 250 ms window, queued during in-flight request | Yes, 100 ms per entity plus value dedupe |
| Value returned on read after write | Last value written to the characteristic | Cached characteristic value | Last written value until confirmed or 5 s |
| Accessory-side idle close | Never | 1 hour, only above 16 connections | Never |
| Error status on failed write | Integer HAP code | Integer HAP code | Integer HAP code |
| Value-store callbacks run in | Connection handler | Connection handler | One global GenServer (fast path only) |

Home Assistant's light (`homeassistant/components/homekit/type_lights.py`) registers one setter for the whole service, merges On/Brightness/Hue/Saturation/ColorTemperature with newest-wins conflict rules (a color-temperature change cancels pending hue/saturation and vice versa), flushes after `CHANGE_COALESCE_TIME_WINDOW = 0.01` s into one `light.turn_on`, and pushes HA state back through `char.set_value`/`notify`. HAP-python's `accessory_driver.py` skips the client that made the change when publishing events. HAP-NodeJS batches events over `EVENT_COALESCING_DELAY = 250` ms, queues them while a request is in flight, and closes idle connections only after `MAX_CONNECTION_IDLE_TIME` of one hour and only when more than `CONNECTION_TIMEOUT_LIMIT = 16` connections are open.

## Design rationale: what the 2026-09 control-path changes fixed

Recorded so the reasons behind the current shape are not lost. All timings were code-derived; no runtime measurements were taken.

Before these changes a brightness write ran the full control pipeline synchronously inside the library's manager process: three or four SQLite queries, the planner, and `Executor.enqueue`, itself a `GenServer.call` into an executor that performs bridge HTTP dispatches synchronously with a 10-second client timeout. The HAP response waited for all of it, every other HomeKit request (reads, event delivery, other controllers) waited behind it, and because the manager call timeout (5 s) was shorter than the bridge timeout (10 s) one slow bridge call dropped the HomeKit session.

Findings, ranked by likely impact on brightness lag:

1. **Idle connections closed after 60 seconds.** Neither the library nor the app set Thousand Island's `read_timeout` (default 60000 ms). After each request Bandit returned `{:continue, state}`, Thousand Island re-armed the timer and silently closed the socket with `{:shutdown, :read_timeout}`. The hub reconnected and re-ran pair-verify every idle minute, lost every event subscription each time, and the first action after idle could land on a half-open socket. Fixed with `read_timeout: :infinity`. Not confirmed on the production host before the fix (the `ss -tnio` snapshot never ran).
2. **On + Brightness in one request ran the pipeline twice.** The library has no service-level setter, so each characteristic was a separate `put_value`. `On` applied the manual baseline (brightness 100, 3000 K) and `Brightness` then applied the level: two transactions, two plans, two executor entries, and a visible flash to full when the first had already dispatched. Fixed by the writer's coalesce window.
3. **Reads and events reflected only bridge-observed state, and events echoed to the writer.** `get_value` read `Control.State`, written only by bridge event streams, so reads returned the old value until the bridge reported. Every control-state broadcast fired `HAP.value_changed` for every token on the entity, and the library pushed the event to all subscribers including the originator. Group writes produced a burst (one re-derivation per member light). During a slider drag the Home app snapped back to stale values. Fixed by the value cache, cache reconciliation, and debounced deduplicated notifications.
4. **Failed writes returned a string status.** `{:error, "HueWorks brightness command failed"}` became `"status": "..."` in JSON; HomeKit requires integer codes and showed No Response. This was the reply for every brightness write while a scene was active (an intentional block with a malformed reply). Fixed with `Hueworks.HomeKit.Status` codes.
5. **Every request serialized through one library process.** Structural to the library; made harmless by returning from `put_value` before any pipeline work.
6. **Only On and Brightness were published.** Color and temperature never travelled through this stack until the 2026-09 color work; git history has no earlier commit that set them.
7. **Inbound encrypted frames were not reassembled.** Both the library and the earlier app override assumed each TCP read held whole frames and crashed the session otherwise. Fixed with a per-connection buffer in the transport and handler.
8. **Smaller items.** The handler's `handle_info` lacked a catch-all and crashed on unexpected messages (now delegates to Bandit). `clear_process_dict: false` is required because session keys live in the process dictionary. `Bridge.rebuild/1` restarts the whole HAP supervisor on topology change, dropping every session; keep that in mind before adding reload triggers. Scene reads hit SQLite twice inside the manager; `GET /accessories` does so for every scene serially.

Rates and timeouts that shaped the analysis: manager call timeout 5000 ms; Hue client `recv_timeout` 10000 ms; executor Hue rate 10 commands/s; executor settlement floor 750 ms; executor retries 3 with 250 ms base backoff; manual power-on baseline brightness 100 at 3000 K; encrypted frame payload max 1024 bytes.

## Verification status

The control-path changes are covered by deterministic tests (`test/hueworks/homekit_test.exs` and `test/hueworks/homekit_regression_test.exs`, the latter from three rounds of peer review that found the executor-timeout, encrypted body read, cache-expiry, apply-ordering, write-generation, shared-override-row, coalescing-boundary, and fast-failure notification gaps; `test/hueworks/homekit_color_review_test.exs` from a fourth round covering partial color intent, color-mode supersession, calibrated temperature ranges, and characteristic ID stability) On hardware, on/off and brightness have been used against Apple Home (a group slider drag exposed the bridge pacing defects recorded in `docs/hue-command-pacing.md`); color, temperature, the fresh-install bridge accessory, and identity survival across un-expose and re-expose have not yet been verified there. Manual smoke test: with `ADVANCED_DEBUG_LOGGING=true`, drag a brightness slider on a light with no active scene and confirm `write_accepted` completes in single-digit milliseconds, one `write_applied` carries both `on` and `brightness` when starting from off, the slider does not snap back, and `ss -tnio state established '( sport = :51827 )'` on the host shows connections older than 60 seconds idle. Then, on a color light: pick a color and confirm the light and the Home app wheel agree, and pick a temperature and confirm the wheel shows the matching warm or cool white. Finally, un-expose and re-expose a light and confirm its room, name, and any Home automation survive.
