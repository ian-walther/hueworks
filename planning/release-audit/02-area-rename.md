# Chunk 2: Rooms→Areas Rename Fidelity

Status: complete. Scope: `e88ae84` (rename), `7f60f53` (persisted identities), `4645ee9` (pico metadata), `e9e7dfe`/`fd40400` (copy), plus the identity-preservation contract with HA MQTT. Method: exhaustive greps at HEAD for room-era vocabulary across `lib/`, heex, `assets/`, `docs/`, `mcp/`, plus line-by-line reads of the HA export sync/topics/discovery delta and the reimport blob-compatibility question parked from chunk 1.

## Findings

### AR-1: Old `/rooms` URLs 404 after upgrade with no redirect

- Severity: low. Type: UX.
- Location: `lib/hueworks_web/router.ex` (routes are `/areas`, `/areas/:area_id/scenes/...`); `RedirectController` only handles `/`.
- Problem: browser bookmarks, HA dashboard links, or notes pointing at `/rooms` (and `/rooms/:room_id/scenes/:id/edit`) break silently post-migration. Removed *API* room operations are an explicitly approved break (rollout smoke item 10), but the human-facing URLs got no grace.
- Decision: add permanent redirects `GET /rooms` → `/areas` and `GET /rooms/:room_id/scenes/*` → the `/areas/...` equivalent (IDs are stable across the rename, so a mechanical path rewrite is safe). Do not add API-route aliases.
- Guardrail: two `router_test.exs` cases asserting 301/302 targets.
- Effort: S.

### AR-2: `schema_version` was bumped but is written inconsistently and read by nobody

- Severity: low. Type: style/robustness.
- Location: `lib/hueworks/import/normalize.ex` (`@schema_version 2`, bumped with the rename) vs `lib/hueworks/import/normalize_from_db.ex` (hardcodes `schema_version: 1`).
- Problem: the bump was the right instinct (the blob vocabulary changed: `rooms`→`areas`, `group_room`→`group_area`), but no consumer checks the field, and the two producers now disagree, so the field documents nothing trustworthy.
- Decision: expose the constant once (`Normalize.schema_version/0`), have `NormalizeFromDb` use it, and leave the field as provenance metadata. Do not build a version-gated migration path for blobs — see Explicitly Fine below for why none is needed today.
- Guardrail: trivial assertion in existing normalize tests that both producers emit the same version.
- Effort: S.

### AR-3: Room-era retained MQTT messages orphaned on the broker after upgrade

- Severity: low. Type: UX/operational hygiene.
- Location: `Topics.area_select_{command,state,attributes}_topic/1` moved from `hueworks/rooms/<id>/scene/...` to `hueworks/areas/<id>/scene/...`; nothing clears the old retained `state`/`attributes` payloads.
- Problem: after the migration, retained messages linger under `hueworks/rooms/#` forever. HA won't consume them (discovery points at the new topics), but they clutter broker inspection and can mislead future debugging ("why does the broker still show room scene state?").
- Decision: document a one-time manual cleanup in `planning/area-onboarding-rollout.md` post-migration steps (publish zero-length retained payloads to `hueworks/rooms/#` topics, e.g. via `mosquitto_sub -t 'hueworks/rooms/#' -v` to enumerate then `mosquitto_pub -r -n`). Do not add application code for a one-time event.
- Effort: S (doc-only).

## Explicitly Fine / Leave-Alone

- **Rename completeness**: greps for room-era vocabulary at HEAD across `lib/`, heex templates, `assets/`, `docs/`, `README.md`, and `mcp/` return only Hue API protocol terms (`"Room"`/`"Zone"` group types), which are external vocabulary and must remain. This was a 222-file mechanical rename executed essentially perfectly.
- **HA identity preservation (the crux of `7f60f53`)**: verified end-to-end. Migration `130000` backfills `ha_scene_select_identifier = 'hueworks_room_scene_select_' || id`, and the new discovery topic is `<prefix>/select/<identifier>/config` — byte-identical to the old hardcoded room discovery topic for migrated rows, with the same `unique_id` in the payload. Retained HA discovery configs are therefore updated in place (new command/state topics), not duplicated. New areas get UUID-based `hueworks_area_*` identities. The mixed `hueworks_room_*`/`hueworks_area_*` prefixes in production are intentional identity preservation — never "clean them up".
- **Area deletion vs identifier capture**: `Areas.delete_area/1` passes the deleted struct (identifier still present) to `HomeAssistantExport.remove_area/1`, and the unpublish path takes the identifier explicitly rather than re-querying a deleted row. Correct design for the delete race.
- **Stale persisted review blobs (parked from chunk 1)**: refuted as a risk. `BridgeReimportLive` always rebuilds the review from a fresh fetch on mount (`:import_configuration`); room-era pending review blobs are never resumed, and `reimport_apply` re-validates every resolution against current DB state with `stale_resolution`/`invalid_duplicate` rollbacks surfaced as a stale-review refresh in the UI. `normalized_json` on lights/groups written by room-era code is likewise benign: reimport change detection is identity/presence-based, no code branches on `group_room`/`group_area` literals, and blobs are rewritten on next apply.
- **Pico JSON migration** (`4645ee9`): covered in chunk 1; `action_config.room_id`, `metadata.room_override`, `metadata.detected_room_id` all rewritten, asserted by the runbook's post-migration counts and migration tests.
- **Copy commits**: "a area"→"an Area" fixed with a regression test (`control_live_test.exs` asserts both presence and absence). No remaining `" a area"`/`" a Area"` matches anywhere.
- **`from(r in Area, ...)` binding names**: the single-letter `r` bindings survive from room-era code in `areas.ex`/`bridge_reimport_live.ex`. Cosmetic; not worth churn.
