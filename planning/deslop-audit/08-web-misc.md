# Chunk 8 — Web misc (components, controllers, plugs, mix tasks, app cache/location)

Status: AUDIT COMPLETE. **No findings.** Read: `cache/store.ex`, `plugs/api_auth.ex`, `api/response.ex`; structure-scanned: `home_assistant_auth_controller.ex` (OAuth session-state handling — security-sensitive, well-shaped), `entity_control_components.ex`, api controllers, `postal_code_lookup.ex`, layouts/page components, plugs, mix tasks (ops scripts, light scrutiny by design).

## Explicitly Fine / Leave-Alone

- **`Cache.Store` `:ets.whereis` guards on every operation** — the cache is used from dispatch paths that can run before/without the GenServer (tests, startup); returning `:miss`/no-op is the right degradation.
- **`ApiAuth` byte_size + secure_compare** — constant-time comparison done properly; not defensive theater.
- **`HomeAssistantAuthController` pending-state pruning/bounding** — session-boundary paranoia earning its keep.
