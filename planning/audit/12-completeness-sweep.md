# Audit Chunk 12: Completeness Sweep

Scope: database migrations versus changeset/association constraints, browser JavaScript hooks used by control surfaces, and Docker/release/start deployment plumbing.
Status: complete. All database unique indexes now map to changeset errors, JavaScript control hooks have dynamic coverage for shared color buffering, and the Compose/release image and startup sequence are verified. No `FS-*` findings remain open.

## Sub-Area Tracker

| Area | Status |
|------|--------|
| Unique/check/foreign-key constraints versus changesets | complete |
| Association delete behavior versus context operations | complete |
| JavaScript hooks, event contracts, teardown, and reconnect behavior | complete |
| Docker image, Compose environment/volumes/health, and release startup | complete |
| Documentation parity | complete |

## Audit Questions

- Can changes accepted by Ecto fail only at the database boundary without a mapped changeset error?
- Do migrations enforce the uniqueness and referential assumptions made by contexts, including deletion behavior?
- Do hooks clean up listeners/timers, survive LiveView replacement/reconnect, and preserve the manual-control event contract?
- Can a clean production image/release boot with documented environment and persistent paths, and does failure surface clearly?

## Database Constraint Posture

Every unique index has a corresponding changeset mapping. The sweep added the two omissions: one active scene per area and one light per scene component. `test/hueworks/schema_constraint_parity_test.exs` proves both return ordinary changeset errors rather than raising.

Foreign keys and delete behavior match the context model: bridge/area/scene ownership cascades where the owned record has no independent life; optional area/canonical/presence links nilify; saved light states restrict deletion while referenced. SQLite reports foreign-key violations without a constraint name, so Ecto cannot map generic `foreign_key_constraint/3` declarations to a field under this adapter. HueWorks therefore continues to enforce normal reference selection in context APIs and relies on SQLite for final integrity; adding declarations that still raise was explicitly refuted by the runtime probe.

## Browser Hook Posture

All hook names match rendered elements and LiveView event handlers. Slider timers and document listeners clean up on destruction; drag-local values survive LiveView patches; chart listeners rebind only when its SVG node changes; flash timers clear; geolocation values enter existing validated form handlers.

Hue and saturation previously owned separate debounce timers, so a paired adjustment emitted the same final `set_color` payload twice. They now share one target-keyed pending dispatch, and `assets/test/app_hooks_test.mjs` executes the real hook function with fake DOM inputs to enforce one event.

## Deployment Posture

Compose requires `SECRET_KEY_BASE`, supplies every runtime path, and renders with the HomeKit host-network override. The multi-stage image builds a production asset digest and release, runs as a non-root user, and built successfully from a clean Docker context.

`docker/start.sh` migrates before boot and seeds only when the configured secrets file exists. An absent file no longer creates the permanent seed marker, so mounting secrets later retries on the next start. `test/docker_start_test.sh` verifies absent-file and later-file startup with a fake release executable.
