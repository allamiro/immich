#!/usr/bin/env bash
# Points the build metadata that server/Dockerfile bakes into the image at this repository.
#
# Usage: rebrand-dockerfile.sh <dockerfile> <owner/repo> <run-id> <source-commit> <package>
#
# Rewrites exactly one line each of
#   ENV IMMICH_BUILD_URL, ENV IMMICH_BUILD_IMAGE_URL, ENV IMMICH_REPOSITORY,
#   ENV IMMICH_REPOSITORY_URL, ENV IMMICH_SOURCE_URL
# in place and prints the diff. Exits non-zero without touching the file when a line is missing,
# duplicated or continued, and exits non-zero after the rewrite when any ENV or LABEL line still
# names immich-app. The server shows these values in /api/server/about and in the About dialog.

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <dockerfile> <owner/repo> <run-id> <source-commit> <package>" >&2
  exit 64
fi

dockerfile=$1
repository=$2
run_id=$3
source_commit=$4
package=$5
server_url=${FORK_SERVER_URL:-https://github.com}

fail() {
  echo "::error file=${dockerfile}::$*" >&2
  exit 1
}

[[ -f "$dockerfile" ]] || fail "Dockerfile not found."
[[ "$repository" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || fail "Repository '${repository}' is not owner/name."
[[ "$(tr '[:upper:]' '[:lower:]' <<< "$repository")" != immich-app/* ]] || fail "Refusing to brand a build as ${repository}."
[[ "$run_id" =~ ^[0-9]+$ ]] || fail "Run id '${run_id}' is not a number."
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail "Source commit '${source_commit}' is not a full SHA."
[[ "$package" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "Package '${package}' is not a container package name."

repository_url="${server_url}/${repository}"
keys=(IMMICH_BUILD_URL IMMICH_BUILD_IMAGE_URL IMMICH_REPOSITORY IMMICH_REPOSITORY_URL IMMICH_SOURCE_URL)
value_for() {
  case "$1" in
    IMMICH_BUILD_URL) echo "${repository_url}/actions/runs/${run_id}" ;;
    IMMICH_BUILD_IMAGE_URL) echo "${repository_url}/pkgs/container/${package}" ;;
    IMMICH_REPOSITORY) echo "${repository}" ;;
    IMMICH_REPOSITORY_URL) echo "${repository_url}" ;;
    IMMICH_SOURCE_URL) echo "${repository_url}/commit/${source_commit}" ;;
  esac
}

for key in "${keys[@]}"; do
  matches=$(grep -cE "^ENV[[:space:]]+${key}=" "$dockerfile" || true)
  if [[ "$matches" -ne 1 ]]; then
    fail "Expected exactly one 'ENV ${key}=' line, found ${matches}. Upstream changed server/Dockerfile; update .github/fork/rebrand-dockerfile.sh."
  fi
  if grep -E "^ENV[[:space:]]+${key}=" "$dockerfile" | grep -qE '\\[[:space:]]*$'; then
    fail "The 'ENV ${key}=' line continues on the next line; this script only rewrites single-line ENV instructions."
  fi
  if grep -E "^ENV[[:space:]]+${key}=" "$dockerfile" | grep -qE "^ENV[[:space:]]+${key}=[^[:space:]]*[[:space:]]+[^[:space:]]"; then
    fail "The 'ENV ${key}=' line sets more than one variable; this script only rewrites one variable per line."
  fi
done

original=$(mktemp)
rewritten=$(mktemp)
trap 'rm -f "$original" "$rewritten"' EXIT
cp "$dockerfile" "$original"

awk_arguments=()
for key in "${keys[@]}"; do
  awk_arguments+=(-v "value_${key}=$(value_for "$key")")
done

awk "${awk_arguments[@]}" '
  match($0, /^ENV[[:space:]]+IMMICH_[A-Z_]+=/) {
    key = substr($0, RSTART, RLENGTH - 1)
    sub(/^ENV[[:space:]]+/, "", key)
    if (key == "IMMICH_BUILD_URL") { print "ENV " key "=" value_IMMICH_BUILD_URL; next }
    if (key == "IMMICH_BUILD_IMAGE_URL") { print "ENV " key "=" value_IMMICH_BUILD_IMAGE_URL; next }
    if (key == "IMMICH_REPOSITORY") { print "ENV " key "=" value_IMMICH_REPOSITORY; next }
    if (key == "IMMICH_REPOSITORY_URL") { print "ENV " key "=" value_IMMICH_REPOSITORY_URL; next }
    if (key == "IMMICH_SOURCE_URL") { print "ENV " key "=" value_IMMICH_SOURCE_URL; next }
  }
  { print }
' "$original" > "$rewritten"

for key in "${keys[@]}"; do
  expected="ENV ${key}=$(value_for "$key")"
  if ! grep -qxF "$expected" "$rewritten"; then
    fail "The rewrite did not produce '${expected}'."
  fi
done

leftovers=$(grep -nE '^[[:space:]]*(ENV|LABEL)[[:space:]].*immich-app' "$rewritten" || true)
if [[ -n "$leftovers" ]]; then
  fail "ENV or LABEL lines still name immich-app after the rewrite: $(tr '\n' ' ' <<< "$leftovers")"
fi

cp "$rewritten" "$dockerfile"
diff -u --label "${dockerfile} (upstream)" --label "${dockerfile} (fork build)" "$original" "$dockerfile" || true
