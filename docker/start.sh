#!/bin/sh
set -eu

SEED_MARKER_PATH="${SEED_MARKER_PATH:-/data/.bridges_seeded}"
BRIDGE_SECRETS_PATH="${BRIDGE_SECRETS_PATH:-secrets.json}"

echo "[hueworks] running database migrations"
/app/bin/hueworks eval "Hueworks.Release.migrate()"

if [ -f "$SEED_MARKER_PATH" ]; then
  echo "[hueworks] bridge seed marker found at $SEED_MARKER_PATH; skipping bridge bootstrap"
elif [ ! -f "$BRIDGE_SECRETS_PATH" ]; then
  echo "[hueworks] bridge seed file not found at $BRIDGE_SECRETS_PATH; leaving bootstrap unmarked"
else
  echo "[hueworks] seeding bridges from $BRIDGE_SECRETS_PATH"
  /app/bin/hueworks eval "Hueworks.Release.seed_bridges()"
  touch "$SEED_MARKER_PATH"
fi

echo "[hueworks] starting server"
exec /app/bin/hueworks start
