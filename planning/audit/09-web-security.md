# Audit Chunk 9: Web Security Posture

Scope: `HueworksWeb.Endpoint`, router pipelines, plugs, LiveView/WebSocket setup, runtime endpoint configuration, secret handling, network binding, and deployment-facing trust assumptions.
Status: complete. HueWorks is explicitly a private trusted-LAN appliance: application authentication is absent by design, network reachability is the authorization boundary, and plaintext HTTP is supported only inside that isolated boundary. Public exposure is forbidden and requires a new system-wide security design before it can be considered.

## Sub-Area Tracker

| Area | Status |
|------|--------|
| HTTP session, CSRF, and secure headers | complete |
| LiveView/WebSocket origin and connection posture | complete |
| Authentication and destructive-route reachability | complete |
| Endpoint binding, proxy, and secret configuration | complete |
| Production dependency advisory audit | complete |
| Product trust-boundary decision and architecture documentation | complete |

## Audit Questions

- Which protections apply to every browser and LiveView mutation, and are any mutating routes outside them?
- Can a hostile web origin create a session or LiveView connection and trigger commands?
- Is the application intentionally unauthenticated, and if so what network boundary makes destructive operations acceptable?
- Are production secrets required, non-default, and prevented from appearing in committed files or logs?
- Do runtime binding and proxy options match the documented deployment boundary?

## Product Posture

- HueWorks must never be publicly accessible. Routers, firewalls, VLANs, and host policy must prevent Internet and untrusted-network reachability; port forwarding and public tunnels are unsupported.
- Every client with network access is trusted. The unauthenticated router is intentional, and `test/hueworks_web/security_posture_test.exs` makes anonymous LiveView access an explicit product contract.
- Plain HTTP is supported on the isolated trusted LAN. A private TLS reverse proxy is optional; `PHX_SCHEME` and `PHX_URL_PORT` keep canonical URL/origin metadata truthful for either topology.
- A future remote-access requirement is an architectural security project, not a configuration toggle. Authentication, authorization, TLS, cookies/sessions, secret exposure, and abuse controls must be designed together before the endpoint is exposed.

## Explicitly Fine / Leave Alone

- All current routes pass through the sole `:browser` pipeline. It fetches the session, installs the filter-session identifier, applies `protect_from_forgery`, and adds Phoenix's secure browser headers. There are no mutating controller/API routes outside it.
- `assets/js/app.js` sends the root-layout CSRF token when connecting LiveView. Phoenix validates it against the signed cookie session before exposing session data to the socket.
- Production inherits Phoenix's `check_origin: true`; the dependency implementation compares the WebSocket Origin host with the configured endpoint host. Development disables origin checks but binds only `127.0.0.1`.
- Production refuses to boot without `SECRET_KEY_BASE`; `.env`, `secrets.json`, database files, and credential roots are ignored. The example env contains a conspicuous non-secret placeholder.
- `hw_filter_session_id` is deliberately not an authentication credential. Client selection of that opaque preference key can affect only per-session filter preferences, so signing a second cookie would not create a meaningful security boundary.

## Dependency Posture

The production lockfile uses patched Bandit 1.12, Phoenix 1.7.24, Plug 1.20, HPAX 1.0.4, and current compatible Ecto/SQLite releases. Direct minimums in `mix.exs` prevent lock regeneration from falling back into the advisory-bearing server releases.

Hackney remains on 1.x because both `tzdata` 1.1 and HTTPoison 2 require that line, while HTTPoison 3 requires incompatible Hackney 4. The published Hackney findings concern cookie option injection, query construction, URL-allowlist bypass, and SOCKS timeout behavior. HueWorks uses none of those surfaces: it sends no Hackney cookies, uses no proxy/SOCKS configuration or URL allowlist, and constructs bridge URLs from owner-configured hosts plus constant paths. Replacing the timezone database solely to remove an unreachable transitive package finding is not warranted; reassess if HTTP request construction or proxy support changes.
