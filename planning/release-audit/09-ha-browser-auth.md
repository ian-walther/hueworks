# Chunk 9 (Phase 2): Home Assistant Browser Authorization

Status: complete against the working tree as of this session (uncommitted, in-flight — reconcile before implementing). Scope: `authorization.ex`, `home_assistant_auth_controller.ex`, `connection_validator.ex`, `token_provider.ex`, `host.ex`/`credentials.ex` deltas, token-provider adoption across import fetch, control bridge/client, bootstrap, event stream, connection test, plus router and both bridge UIs. Audited against `pre-release_refinement.md` §Home Assistant Browser Authorization point by point.

## Verdict Up Front

This is the strongest subsystem in either audit phase. Every line of the blocker spec has a direct, verified implementation: origin-derived client/callback URLs with pre-redirect validation; crypto-random single-use session-bound state with TTL and a bounded pending set; denial/cancel/expiry handled without partial bridge rows; validation against the exact APIs import needs (`config/entity_registry/list`, `get_states`) before persistence; refresh-before-expiry with 60s leeway; retry-once-after-401 at every call site via one shared helper; revoked-refresh persisted as `reauthorization_required` and surfaced as a badge + reauthorize action on bridge cards; manual long-lived-token entry demoted to an advanced fallback with the exact "cannot be refreshed automatically" warning; scheme-preserving host handling with derived `ws`/`wss` URLs; legacy `token` cleared on reauthorization; and **zero remaining direct reads of `credentials.token`** outside the provider. The test files map nearly one-to-one onto the spec's test list (replay, denial, no-partial-rows, duplicate identity, concurrent refresh sharing one refresh, revoked refresh, transient-failure retry eligibility, legacy tokens). Two findings below; neither undermines the design.

## Findings

### HA-1: `authorize` is a GET with side effects — CSRF-reachable from any internet page

- Severity: medium. Type: security.
- Location: `router.ex` `get("/config/bridges/home-assistant/authorize", ...)`; `HomeAssistantAuthController.authorize/2` accepts an arbitrary `host` param, writes session state, and redirects to that host's `/auth/authorize`.
- Problem: the trusted-LAN model assumes the attacker is not on the LAN — but a malicious *internet* page in a LAN user's browser can issue cross-origin GETs to LAN addresses. Such a page can drive `authorize?host=<attacker-host>` → attacker's fake HA issues a code → the victim's browser follows to the callback → the controller exchanges the code *at the attacker host* and inserts an attacker-controlled `:ha` bridge (which HueWorks will subsequently import from and send token refreshes to). The state parameter doesn't help because the whole flow is attacker-initiated inside the victim's session. Phoenix's CSRF protection is exactly the layer that normally blocks this, and a side-effecting GET bypasses it.
- Decision: make `authorize` a POST (`button_to`/form with CSRF token from the browser pipeline) and reject GET. The `callback` stays GET — it is safe because it only acts on a state value that a same-session `authorize` POST created. Update the two template call sites (`bridge_live.html.heex` authorize button, `bridges_config_live.html.heex` reauthorize actions).
- Guardrail: controller test asserting GET `authorize` is rejected and that callback without a session-created state still fails (already covered by the replay test).
- Effort: S.

### HA-2: Credential secrets are not marked `redact` — and the spec's redaction test is the one list item not implemented

- Severity: low-medium. Type: security hygiene.
- Location: `lib/hueworks/schemas/bridge/credentials.ex` — none of `token`, `api_key`, `password`, and now `access_token`/`refresh_token` carry `redact: true`; no `@derive Inspect` restriction.
- Problem: any `inspect` of a `%Bridge{}`/changeset (crash reports, `Logger` metadata, LiveView crash dumps, the `inspect(reason)` fallbacks flagged in BO-5) can emit live tokens. The pre-existing fields had the same posture, but the OAuth work both adds two more secrets and — per its own spec — calls for credential-redaction tests that don't exist.
- Decision: add `redact: true` to all six secret fields (Ecto redacts them in changeset inspection) and `@derive {Inspect, except: [...]}` on the embedded schema for struct inspection; add one test asserting `inspect` of a loaded credentials struct and of a failed changeset contains none of the secret values.
- Effort: S.

## Explicitly Fine / Leave-Alone

- **TokenProvider as a single serializing GenServer** (blocking HTTP refresh inside `handle_call`, 15s call timeout vs 10s request timeout): serialization is precisely what makes "concurrent callers cause one refresh" true, and the 10s credentials cache in `Control.HomeAssistantBridge` keeps steady-state control traffic off the provider. A slow HA instance can stall token calls for other HA bridges for up to ~10s — acceptable for the realistic one-instance household; revisit only if multi-HA becomes a first-class scenario.
- **Cache discipline**: `Control.HomeAssistantBridge` caches `{:ha, bridge_id}` with a 10s TTL, deletes before retry-with-refresh, and the auth controller deletes the same key after reauthorization. Key shapes verified to match. The short TTL bounds any staleness window.
- **`ConnectionValidator`**: REST identity check + WebSocket connect + the two registry/state requests import actually uses, with connection cleanup on every path including rescue. This is "validate with the APIs required by import" implemented literally.
- **Error-reason vocabulary** (`:reauthorization_required` vs `:temporarily_unavailable` vs `:authorization_failed`, HTTP-status-classified): callers can distinguish re-auth from transient; the refresh path deliberately treats 400/401/403 as revocation and 5xx/network as transient. Correct reading of HA's behavior.
- **Legacy-token bridges under `refresh/1`** get marked `reauthorization_required` while `token_for` continues serving the stored token: mildly inconsistent but the honest interpretation (the token just failed a real request; keep serving it while telling the operator to reauthorize). Leave.
- **IPv6 literal hosts** are effectively unsupported (`explicit_port?` regex and `URI.parse` behavior; `normalize/1` falls back to `127.0.0.1:8123`): consistent with the IPv4-LAN scope accepted in chunk 3. Leave until a real household needs it.
- **`Host` rewrite**: validation rejects paths/queries/fragments and unusable hosts (`0.0.0.0`, `::`), canonical origin derivation matches the authorization module's client_id derivation, and the legacy `normalize/1` contract (authority string with default port) is preserved for existing callers.
