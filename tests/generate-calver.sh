#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"

cat > "$fixture_dir/bin/date" <<'MOCK'
#!/usr/bin/env bash
case ${*: -1} in
  +%Y%m%d) printf '20260925\n' ;;
  *) printf '2026.09.25\n' ;;
esac
MOCK

cat > "$fixture_dir/bin/git" <<'MOCK'
#!/usr/bin/env bash
case $1 in
  ls-remote) cat "$TAGS_FILE" ;;
  check-ref-format) exit 0 ;;
  *) exit 1 ;;
esac
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
case $TEST_MODE in
  collision)
    if [[ ! -f $COLLISION_MARKER ]]; then
      touch "$COLLISION_MARKER"
      printf '{"errors":[{"code":"already_exists"}]}\n' > "$output_file"
      printf '422'
    else
      printf '201'
    fi
    ;;
  always_collision)
    printf '{"errors":[{"code":"already_exists"}]}\n' > "$output_file"
    printf '422'
    ;;
  invalid_ref) printf '422' ;;
  *) printf '201' ;;
esac
MOCK

chmod +x "$fixture_dir/bin/"*
export PATH="$fixture_dir/bin:$PATH"
export CALVER_TOKEN=test-token GITHUB_REPOSITORY=example/project GITHUB_SHA=abc123
export TAGS_FILE="$fixture_dir/tags" PAYLOADS_FILE="$fixture_dir/payloads"
export COLLISION_MARKER="$fixture_dir/collision"
export GITHUB_OUTPUT="$fixture_dir/output"
export CALVER_RETRY_DELAY_SECONDS=0

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

: > "$TAGS_FILE"
: > "$GITHUB_OUTPUT"
export TEST_MODE=normal CALVER_DATE_FORMAT=%Y%m%d CALVER_TAG_PREFIX=release- CALVER_SEPARATOR=-
export CALVER_COUNTER_START=4 CALVER_COUNTER_WIDTH=3
bash "$project_dir/scripts/generate-calver.sh"
grep -qx 'version=20260925-004' "$GITHUB_OUTPUT"
grep -qx 'tag=release-20260925-004' "$GITHUB_OUTPUT"

: > "$GITHUB_OUTPUT"
export TEST_MODE=always_collision CALVER_MAX_ATTEMPTS=2
if bash "$project_dir/scripts/generate-calver.sh"; then
  printf 'Expected retry exhaustion\n' >&2
  exit 1
fi
[[ $(wc -l < "$GITHUB_OUTPUT") -eq 0 ]]

export CALVER_COUNTER_START=invalid
if bash "$project_dir/scripts/generate-calver.sh"; then
  printf 'Expected invalid counter input to fail\n' >&2
  exit 1
fi

export CALVER_COUNTER_START=4 TEST_MODE=invalid_ref
if bash "$project_dir/scripts/generate-calver.sh"; then
  printf 'Expected non-collision validation error to fail\n' >&2
  exit 1
fi

printf 'CalVer generation tests passed\n'
