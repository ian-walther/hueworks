# Production Deployment (Docker)

## Goal
Maintain a reliable, repeatable Docker-based production deployment path for HueWorks with only minor operational hardening left to do.

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

## Runtime Contract
### Persistent Storage
- `/data/hueworks.db`
- `/data/.bridges_seeded`

### Mounted Secrets
- `/run/hueworks/secrets.json` (or override via `BRIDGE_SECRETS_PATH`)
- `/credentials/*` for Caseta cert/key material when needed

### Required Environment
- `SECRET_KEY_BASE`
- `DATABASE_PATH`
- `PHX_HOST`
- `PORT` (optional, default `4000`)
- `POOL_SIZE` (optional)

### Recommended Deployment Shape
- bind app behind reverse proxy/TLS terminator
- mount a backup target path or run an external backup job
- keep the container non-root
- keep secret material out of the image

## Startup / Migration Expectations
Expected startup flow:
1. pull/build new image
2. run release migrations on boot
3. seed bridges if no seed marker exists yet
4. start app

Standard manual commands should remain available:
- `bin/hueworks eval "Hueworks.Release.migrate()"`
- `bin/hueworks eval "Hueworks.Release.seed_bridges()"`

## Backup / Recovery Expectations
- Keep backup/restore instructions current in `README.md`.
- Preserve pre-upgrade backup guidance.
- Preserve rollback notes.
- Treat a real restore drill as required confidence work, not optional polish.

## Security Expectations
- Run as non-root user in the container.
- Keep the image minimal and pinned.
- Do not bake secrets into the image.
- Keep secret injection runtime-driven.
- Keep network exposure guidance explicit (LAN-only or reverse proxy).

## Observability Expectations
- Deployment docs should continue to include a smoke-check checklist.
- Logs should be sufficient to verify:
  - app start
  - migration start/finish
  - bridge bootstrap
- Useful optional follow-up:
  - a dedicated health endpoint if the current browser/log-based smoke checks stop being enough

## Remaining Work
- tighten file-permission guidance for DB and credential artifacts
- do a real restore drill and tighten the runbook based on what it reveals
- decide whether a dedicated health endpoint is worth adding

## Open Questions
- What backup retention window is acceptable for first deployment?
- Do we want a dedicated health endpoint, or is the current endpoint/log-based verification enough for now?
