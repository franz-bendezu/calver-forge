#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"

cat > "$fixture_dir/bin/date" <<'MOCK'
#!/usr/bin/env bash
printf '2026.09.25\n'
MOCK

cat > "$fixture_dir/bin/git" <<'MOCK'
#!/usr/bin/env bash
cat "$TAGS_FILE"
MOCK

cat > "$fixture_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=
payload=
while (($#)); do
  case $1 in
    --output) output_file=$2; shift 2 ;;
    --data) payload=$2; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' "$payload" >> "$PAYLOADS_FILE"
printf '{}\n' > "$output_file"
if [[ $TEST_MODE == collision && ! -f $COLLISION_MARKER ]]; then
  touch "$COLLISION_MARKER"
  printf 'abc refs/tags/v2026.09.25.8\n' >> "$TAGS_FILE"
  printf '422'
else
  printf '201'
fi
MOCK

chmod +x "$fixture_dir/bin/"*
export PATH="$fixture_dir/bin:$PATH"
export CALVER_TOKEN=test-token GITHUB_REPOSITORY=example/project GITHUB_SHA=abc123
export TAGS_FILE="$fixture_dir/tags" PAYLOADS_FILE="$fixture_dir/payloads"
export COLLISION_MARKER="$fixture_dir/collision"
export GITHUB_OUTPUT="$fixture_dir/output"

printf 'abc refs/tags/v2026.09.25.2\nabc refs/tags/v2026.09.25.7\n' > "$TAGS_FILE"
: > "$PAYLOADS_FILE"
: > "$GITHUB_OUTPUT"
export TEST_MODE=normal
bash "$project_dir/scripts/generate-calver.sh"
grep -qx 'version=2026.09.25.8' "$GITHUB_OUTPUT"
grep -qx 'tag=v2026.09.25.8' "$GITHUB_OUTPUT"

: > "$PAYLOADS_FILE"
: > "$GITHUB_OUTPUT"
export TEST_MODE=collision
bash "$project_dir/scripts/generate-calver.sh"
grep -qx 'version=2026.09.25.9' "$GITHUB_OUTPUT"
grep -qx 'tag=v2026.09.25.9' "$GITHUB_OUTPUT"
grep -q 'refs/tags/v2026.09.25.8' "$PAYLOADS_FILE"
grep -q 'refs/tags/v2026.09.25.9' "$PAYLOADS_FILE"

printf 'CalVer generation tests passed\n'
