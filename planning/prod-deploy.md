# Production Deployment (Docker)

## Goal
Maintain a reliable, repeatable Docker-based production deployment path for HueWorks, with only minor operational hardening left to do.

## Current Baseline
- Deployment target is Dockerized Phoenix release.
- SQLite remains the DB in V1, stored at `/data/hueworks.db`.
- Initial deployment mode is single app container (no orchestrator requirement).
- Runtime config is primarily environment-driven, with bridge bootstrap data coming from a mounted `secrets.json`.
- Security hardening is incremental; baseline first, then tighten.
- Runtime pieces now in place:
  - `docker-compose.yml`
  - release helper module in `lib/hueworks/release.ex`
  - startup wrapper in `docker/start.sh`
  - `.env.example`
  - README deployment/bootstrap instructions

## Locked Decisions
- SQLite stays for v1 operations and should remain easy to inspect and back up.
- Docker deployment should stay simple enough that a fresh clone can be booted with `docker compose up -d` after secrets/env setup.
- Bridge bootstrap should happen from mounted `secrets.json` on first boot only.
- Credential artifacts should live outside the image and remain usable both by manual file copy and UI upload flows.

## Scope
- Keep the runtime contract documented and accurate.
- Keep backup / restore, upgrade / rollback, and smoke-check docs aligned with the real runtime behavior.
- Finish the remaining hardening work around file permissions and recovery confidence.

## Out of Scope (V1)
- Kubernetes/ECS orchestration patterns.
- Multi-node clustering/distributed state.
- Automatic certificate management in-app.
- External managed DB migration away from SQLite.

## Runtime Requirements
- Persistent storage:
  - `/data/hueworks.db`
  - `/data/.bridges_seeded`
- Mounted secrets:
  - `/run/hueworks/secrets.json` (or override via `BRIDGE_SECRETS_PATH`)
  - `/credentials/*` for Caseta cert/key material when needed
- Required env:
  - `SECRET_KEY_BASE`
  - `DATABASE_PATH`
  - `PHX_HOST`
  - `PORT` (optional, default 4000)
  - `POOL_SIZE` (optional)
- Recommended:
  - bind app behind reverse proxy/TLS terminator
  - mount backup target path or external backup job

## Current Compose Shape
- `./data:/data`
- `./credentials:/credentials`
- `./secrets.json:/run/hueworks/secrets.json:ro`
- `CREDENTIALS_ROOT=/credentials`
- one-time bridge bootstrap marker written to `/data/.bridges_seeded`

## Migration Strategy
Current startup flow:
  1. pull/build new image
  2. container runs release migrations on boot
  3. bridge seed bootstrap runs if no seed marker exists yet
  4. app starts

Standard manual commands remain:
- `bin/hueworks eval "Hueworks.Release.migrate()"`
- `bin/hueworks eval "Hueworks.Release.seed_bridges()"`

## Backup / Recovery Baseline
- README now includes:
  - backup command/path
  - restore steps
  - pre-upgrade backup guidance
  - rollback notes
- File permissions for DB and credential artifacts still need a hardening pass.
- A real restore drill is still worth doing once the deployment is used routinely.

## Security Baseline
- Run as non-root user in container.
- Keep image minimal and pinned.
- Do not bake secrets into image.
- Add guidance for secret injection at runtime.
- Add network exposure guidance (LAN-only or reverse proxy).

## Observability Baseline
- Current logs cover:
  - app start
  - migration start/finish
  - bridge bootstrap
- README now includes a deployment smoke-check checklist.
- Remaining useful polish:
  - optional deployment sanity checks beyond log inspection
- Basic “is it alive” checks:
  - HTTP endpoint reachability
  - DB file writable

## Deliverables
- Already delivered:
  - `docker-compose.yml`
  - release migration helper module
  - deployment/bootstrap section in `README.md`
  - backup/restore runbook section
  - upgrade/rollback notes
  - smoke-check checklist
- Remaining deliverables:
  - permission-hardening guidance
  - restore-drill confidence pass

## Remaining Execution Plan
1. Revisit permissions/secrets hardening after the baseline flow is stable in daily use.
2. Do a real restore drill and tighten the runbook if anything surprising shows up.
3. Decide whether a dedicated health endpoint is worth adding beyond the current log/browser smoke checks.

## Open Questions
- What backup retention window is acceptable for first deployment?
- Do we want a dedicated health endpoint, or is the current endpoint/log-based verification enough for now?
