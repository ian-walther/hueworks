# Chunk 9 (Phase 2): Home Assistant Browser Authorization

Status: complete; implementation reconciled 2026-07-26. Scope: `authorization.ex`, `home_assistant_auth_controller.ex`, `connection_validator.ex`, `token_provider.ex`, `host.ex`/`credentials.ex`, token-provider adoption across import/control/bootstrap/event-stream/connection-test, router and both bridge UIs. Audited against `pre-release_refinement.md` §Home Assistant Browser Authorization. No open findings.

## Verdict

The strongest subsystem in the audit. Every line of the blocker spec has a direct, verified implementation: origin-derived client/callback URLs with pre-redirect validation; crypto-random single-use session-bound state with TTL and a bounded pending set; denial/cancel/expiry without partial bridge rows; validation against the exact APIs import needs before persistence; refresh-before-expiry with 60s leeway; retry-once-after-401 at every call site via one shared helper; revoked-refresh persisted as `reauthorization_required` with a badge + reauthorize action; manual token entry demoted to an advanced fallback with the non-refreshable warning; scheme-preserving host handling with derived `ws`/`wss` URLs; legacy `token` cleared on reauthorization; zero direct `credentials.token` reads outside the provider. Tests map onto the spec's test list nearly one-to-one.

## Explicitly Fine / Leave-Alone

- **Authorize is POST-only behind Phoenix CSRF** (formerly HA-1, implemented): both authorize and reauthorize UI actions are CSRF-token forms; the callback stays GET (safe — it only acts on same-session state); controller tests prove GET is rejected and replay/state protections are unchanged. This closes the drive-by evil-bridge-injection vector from internet pages using the browser as a LAN proxy.
- **Credential secrets are redacted** (formerly HA-2, implemented): `api_key`, `token`, `password`, `access_token`, `refresh_token` carry `redact: true` and the embedded schema derives `Inspect` excluding them; tests assert no secret literal appears in changeset or struct inspection — completing the one spec test-list item that had been missing.
- **TokenProvider as a single serializing GenServer**: serialization is what makes "concurrent callers cause one refresh" true; the 10s credentials cache in `Control.HomeAssistantBridge` keeps steady-state control traffic off the provider. Revisit only if multi-HA becomes first-class.
- **Cache discipline**: `{:ha, bridge_id}` at 10s TTL, deleted before retry-with-refresh and after reauthorization; key shapes verified to match.
- **`ConnectionValidator`**: REST identity + WebSocket connect + the registry/state requests import actually uses, cleanup on every path. "Validate with the APIs required by import," implemented literally.
- **Error-reason vocabulary** (`:reauthorization_required` vs `:temporarily_unavailable` vs `:authorization_failed`): refresh treats 400/401/403 as revocation, 5xx/network as transient. Correct reading of HA's behavior.
- **Legacy-token bridges under `refresh/1`** get marked `reauthorization_required` while `token_for` keeps serving the stored token: the honest interpretation (keep serving; tell the operator). Leave.
- **IPv6 literal hosts** effectively unsupported: consistent with the IPv4-LAN scope accepted in chunk 3.
- **`Host` rewrite**: validation rejects paths/queries/fragments and unusable hosts; canonical origin matches the authorization client_id derivation; legacy `normalize/1` contract preserved.
