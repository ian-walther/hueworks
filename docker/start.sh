#!/bin/sh
set -eu

SEED_MARKER_PATH="${SEED_MARKER_PATH:-/data/.bridges_seeded}"
BRIDGE_SECRETS_PATH="${BRIDGE_SECRETS_PATH:-secrets.json}"
DATABASE_PATH="${DATABASE_PATH:-/data/hueworks.db}"
CREDENTIALS_ROOT="${CREDENTIALS_ROOT:-/credentials}"

ensure_writable_dir() {
  dir="$1"
  label="$2"
  probe="$dir/.hueworks-write-test-$$"

  if ! mkdir -p "$dir" || ! (umask 077 && : > "$probe"); then
    echo "[hueworks] $label is not writable: $dir" >&2
    echo "[hueworks] grant UID 1000 write access to the mounted directory, then restart" >&2
    exit 1
  fi

  rm -f "$probe"
}

ensure_writable_dir "$(dirname "$DATABASE_PATH")" "database directory"
ensure_writable_dir "$CREDENTIALS_ROOT" "credentials directory"

echo "[hueworks] running database migrations"
/app/bin/hueworks eval "Hueworks.Release.migrate_with_backup()"

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
