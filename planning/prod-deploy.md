# Production Deployment (Docker)

## Goal
Maintain a reliable, repeatable Docker-based production deployment path for HueWorks with only minor operational hardening left to do.

## Locked Decisions
- SQLite stays for v1 operations and should remain easy to inspect and back up.
- Docker deployment should stay simple enough that a fresh clone can be booted with `docker compose up -d` after secrets and env setup.
- Bridge bootstrap should happen from mounted `secrets.json` on first boot only.
- Credential artifacts should live outside the image and remain usable both by manual file copy and UI upload flows.

## Scope
- Finish the remaining hardening work around file permissions and recovery confidence.
- Keep deployment guidance aligned with the real release and runtime path.

## Out of Scope (V1)
- Kubernetes/ECS orchestration patterns.
- Multi-node clustering/distributed state.
- Automatic certificate management in-app.
- External managed DB migration away from SQLite.

## Remaining Work
- Tighten file-permission guidance for DB and credential artifacts.
- Do a real restore drill and tighten the runbook based on what it reveals.
- Decide whether a dedicated health endpoint is worth adding.

## Open Questions
- What backup retention window is acceptable for first deployment?
- Do we want a dedicated health endpoint, or are the current endpoint/log-based smoke checks enough for now?
