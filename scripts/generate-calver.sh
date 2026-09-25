#!/usr/bin/env bash
set -euo pipefail

: "${CALVER_TOKEN:?Pass github_token to the action}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

date_format=${CALVER_DATE_FORMAT:-%Y.%m.%d}
tag_prefix=${CALVER_TAG_PREFIX-v}
separator=${CALVER_SEPARATOR-.}
counter_start=${CALVER_COUNTER_START:-1}
counter_width=${CALVER_COUNTER_WIDTH:-0}
max_attempts=${CALVER_MAX_ATTEMPTS:-5}
retry_delay=${CALVER_RETRY_DELAY_SECONDS:-1}
api_url=${GITHUB_API_URL:-https://api.github.com}

for value in "$counter_start" "$counter_width" "$max_attempts"; do
  if [[ ! $value =~ ^(0|[1-9][0-9]*)$ ]]; then
    printf 'Counter start, counter width, and max attempts must be nonnegative integers\n' >&2
    exit 1
  fi
done
if (( counter_start < 1 || max_attempts < 1 || counter_width > 12 )); then
  printf 'Counter start and max attempts must be positive; counter width must be at most 12\n' >&2
  exit 1
fi
if [[ ! $retry_delay =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'Retry delay must be a nonnegative number of seconds\n' >&2
  exit 1
fi

date_token=$(date -u "+$date_format")
base="${tag_prefix}${date_token}${separator}"
if [[ ! $base =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'The configured date, prefix, and separator must form a safe Git tag prefix\n' >&2
  exit 1
fi

response_file=$(mktemp)
trap 'rm "$response_file"' EXIT
minimum_next=$counter_start

next_increment() {
  local highest=$((counter_start - 1)) ref increment refs
  refs=$(git ls-remote --refs --tags origin "refs/tags/${base}*" | awk '{print $2}')
  while IFS= read -r ref; do
    ref=${ref##*/}
    [[ $ref == "$base"* ]] || continue
    increment=${ref:${#base}}
    if [[ $increment =~ ^[0-9]+$ ]] && (( 10#$increment > highest )); then
      highest=$((10#$increment))
    fi
  done <<< "$refs"
  if (( minimum_next > highest )); then
    printf '%s\n' "$minimum_next"
  else
    printf '%s\n' "$((highest + 1))"
  fi
}

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  increment=$(next_increment)
  if (( counter_width > 0 )); then
    printf -v displayed_increment "%0${counter_width}d" "$increment"
  else
    displayed_increment=$increment
  fi
  version="${date_token}${separator}${displayed_increment}"
  tag="${tag_prefix}${version}"
  git check-ref-format "refs/tags/$tag"
  payload=$(printf '{"ref":"refs/tags/%s","sha":"%s"}' "$tag" "$GITHUB_SHA")
  status=$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $CALVER_TOKEN" \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    "$api_url/repos/$GITHUB_REPOSITORY/git/refs")

  if [[ $status == 201 ]]; then
    printf 'version=%s\ntag=%s\n' "$version" "$tag" >> "$GITHUB_OUTPUT"
    printf 'Created %s in %s\n' "$tag" "$GITHUB_REPOSITORY"
    exit 0
  fi
  if [[ $status != 422 ]]; then
    printf 'Could not create %s (GitHub API HTTP %s)\n' "$tag" "$status" >&2
    exit 1
  fi
  if ! grep -Eq '"code"[[:space:]]*:[[:space:]]*"already_exists"' "$response_file"; then
    printf 'GitHub rejected %s (HTTP 422 without a tag collision)\n' "$tag" >&2
    exit 1
  fi
  minimum_next=$((increment + 1))
  if (( attempt < max_attempts )); then
    sleep "$retry_delay"
  fi
done

printf 'Could not create a free CalVer tag after %s attempts\n' "$max_attempts" >&2
exit 1
