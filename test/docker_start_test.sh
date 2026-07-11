#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

sed "s#/app/bin/hueworks#$tmp_dir/bin/hueworks#g" \
  "$repo_root/docker/start.sh" > "$tmp_dir/start.sh"

cat > "$tmp_dir/bin/hueworks" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HUEWORKS_TEST_LOG"
EOF

chmod +x "$tmp_dir/start.sh" "$tmp_dir/bin/hueworks"

marker="$tmp_dir/bridges-seeded"
secrets="$tmp_dir/secrets.json"
log="$tmp_dir/release.log"

SEED_MARKER_PATH="$marker" \
BRIDGE_SECRETS_PATH="$secrets" \
HUEWORKS_TEST_LOG="$log" \
  "$tmp_dir/start.sh"

if [ -e "$marker" ]; then
  echo "seed marker must not be created when the secrets file is absent" >&2
  exit 1
fi

printf '{}\n' > "$secrets"

SEED_MARKER_PATH="$marker" \
BRIDGE_SECRETS_PATH="$secrets" \
HUEWORKS_TEST_LOG="$log" \
  "$tmp_dir/start.sh"

test -f "$marker"
test "$(grep -c 'Hueworks.Release.seed_bridges' "$log")" -eq 1
