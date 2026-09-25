#!/usr/bin/env bash
set -euo pipefail

: "${CALVER_TOKEN:?Pass github_token to the action}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

date_prefix=$(date -u +%Y.%m.%d)
api_url=${GITHUB_API_URL:-https://api.github.com}
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

next_increment() {
  local highest=0 ref increment refs
  refs=$(git ls-remote --refs --tags origin "refs/tags/v${date_prefix}.*" | awk '{print $2}')
  while IFS= read -r ref; do
    ref=${ref##*/}
    increment=${ref#v${date_prefix}.}
    if [[ $increment =~ ^[0-9]+$ ]] && (( 10#$increment > highest )); then
      highest=$((10#$increment))
    fi
  done <<< "$refs"
  printf '%s\n' "$((highest + 1))"
}

for attempt in 1 2 3 4 5; do
  increment=$(next_increment)
  version="${date_prefix}.${increment}"
  tag="v${version}"
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
  sleep 1
done

printf 'Could not create a free CalVer tag after five attempts\n' >&2
exit 1
