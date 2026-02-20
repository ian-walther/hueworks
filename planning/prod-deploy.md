# Production Deployment (Docker) Plan

## Goal
Ship a reliable, repeatable Docker-based production deployment path for HueWorks, with explicit operational steps for startup, migrations, backups, and upgrades.

## Locked Decisions
- Deployment target is Dockerized Phoenix release.
- SQLite remains the DB in V1, stored on a persistent volume.
- Initial deployment mode is single app container (no orchestrator requirement).
- Environment-driven runtime config remains the primary config mechanism.
- Security hardening is incremental; baseline first, then tighten.

## Baseline Architecture
- Dockerized Phoenix release deployment.
- SQLite on persistent volume.
- Runtime config from environment variables.

## Scope
- Define and document canonical production env vars.
- Add migration/run command strategy for releases.
- Add base `docker-compose` flow for local-prod style operations.
- Add operational runbook:
  - first boot
  - restart
  - upgrade
  - rollback
  - backup/restore
- Add deployment verification checklist.

## Out of Scope (V1)
- Kubernetes/ECS orchestration patterns.
- Multi-node clustering/distributed state.
- Automatic certificate management in-app.
- External managed DB migration away from SQLite.

## Runtime Requirements
- Persistent storage:
  - `/data/hueworks.db`
- Required env:
  - `SECRET_KEY_BASE`
  - `DATABASE_PATH`
  - `PHX_HOST`
  - `PORT` (optional, default 4000)
  - `POOL_SIZE` (optional)
- Recommended:
  - bind app behind reverse proxy/TLS terminator
  - mount backup target path or external backup job

## Migration Strategy
- Preferred:
  - release helper command (e.g. `bin/hueworks eval "...migrate..."`) documented as standard.
- Deployment flow:
  1. pull/build new image
  2. run migrations
  3. start/restart app container
  4. verify health and logs

## Backup / Recovery Baseline
- Nightly DB backup of SQLite file with retention policy.
- Pre-upgrade backup before migration runs.
- Restore drill documented and tested.
- Ensure file permissions for DB and credential artifacts are explicit.

## Security Baseline
- Run as non-root user in container.
- Keep image minimal and pinned.
- Do not bake secrets into image.
- Add guidance for secret injection at runtime.
- Add network exposure guidance (LAN-only or reverse proxy).

## Observability Baseline
- Structured logs for:
  - app start
  - migration start/finish
  - bridge connection failures
  - scene apply failures
- Basic “is it alive” checks:
  - HTTP endpoint reachability
  - DB file writable

## Deliverables
- `docker-compose.yml`
- release migration helper module
- deployment runbook section in `README.md`

## Phased Execution Plan
1. Lock env contract + migration command.
2. Add compose baseline with persistent volume + env file support.
3. Add release migrate helper and simplify run commands.
4. Write runbook and recovery docs.
5. Add smoke tests/checklist for release validation.

## Open Questions
- Should migrations run as a separate one-shot container by default?
- Do we want a health endpoint before first production rollout?
- What backup retention window is acceptable for first deployment?
