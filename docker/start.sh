#!/bin/sh
set -eu

SEED_MARKER_PATH="${SEED_MARKER_PATH:-/data/.bridges_seeded}"

echo "[hueworks] running database migrations"
/app/bin/hueworks eval "Hueworks.Release.migrate()"

if [ -f "$SEED_MARKER_PATH" ]; then
  echo "[hueworks] bridge seed marker found at $SEED_MARKER_PATH; skipping bridge bootstrap"
else
  echo "[hueworks] seeding bridges if secrets are available"
  /app/bin/hueworks eval "Hueworks.Release.seed_bridges()"
  touch "$SEED_MARKER_PATH"
fi

echo "[hueworks] starting server"
exec /app/bin/hueworks start
