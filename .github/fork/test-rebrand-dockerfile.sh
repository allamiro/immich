#!/usr/bin/env bash
# Runs rebrand-dockerfile.sh against server/Dockerfile of the given git refs (default: HEAD) and
# against broken copies that must be refused.
#
# Usage: test-rebrand-dockerfile.sh [git-ref...]

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rebrand-dockerfile.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

repository=allamiro/immich
run_id=123456789
commit=0123456789abcdef0123456789abcdef01234567
package=immich-server-allamiro
failures=0

pass() { echo "ok   $*"; }
flunk() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

expect_success() {
  local name=$1 file=$2
  if output=$("$script" "$file" "$repository" "$run_id" "$commit" "$package" 2>&1); then
    pass "$name"
    while IFS= read -r line; do echo "     ${line}"; done <<< "$output"
  else
    flunk "$name: $output"
  fi
}

expect_failure() {
  local name=$1 file=$2
  shift 2
  local before
  before=$(cat "$file")
  if output=$("$script" "$file" "$@" 2>&1); then
    flunk "$name: accepted"
  elif [[ "$(cat "$file")" != "$before" ]]; then
    flunk "$name: refused but changed the file"
  else
    pass "$name: $(tail -n 1 <<< "$output")"
  fi
}

refs=("$@")
[[ ${#refs[@]} -gt 0 ]] || refs=(HEAD)

for ref in "${refs[@]}"; do
  base="${work}/$(tr '/' '_' <<< "$ref").Dockerfile"
  git show "${ref}:server/Dockerfile" > "$base"

  file="${base}.ok"
  cp "$base" "$file"
  expect_success "${ref}: rewrite" "$file"
  for key in IMMICH_BUILD_URL IMMICH_BUILD_IMAGE_URL IMMICH_REPOSITORY IMMICH_REPOSITORY_URL IMMICH_SOURCE_URL; do
    line=$(grep -E "^ENV ${key}=" "$file")
    if [[ "$line" == *"$repository"* && "$line" != *immich-app* ]]; then pass "${ref}: ${line}"; else flunk "${ref}: ${line}"; fi
  done
  changed=$(diff "$base" "$file" | grep -c '^>' || true)
  if [[ "$changed" -eq 5 ]]; then pass "${ref}: exactly 5 lines changed"; else flunk "${ref}: ${changed} lines changed"; fi

  file="${base}.again"
  cp "${base}.ok" "$file"
  expect_success "${ref}: second run on a rewritten file" "$file"

  file="${base}.missing"
  grep -v '^ENV IMMICH_SOURCE_URL=' "$base" > "$file"
  expect_failure "${ref}: missing IMMICH_SOURCE_URL" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.duplicate"
  { cat "$base"; grep '^ENV IMMICH_REPOSITORY=' "$base"; } > "$file"
  expect_failure "${ref}: duplicated IMMICH_REPOSITORY" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.renamed"
  sed 's/^ENV IMMICH_BUILD_IMAGE_URL=/ENV IMMICH_IMAGE_URL=/' "$base" > "$file"
  expect_failure "${ref}: renamed IMMICH_BUILD_IMAGE_URL" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.new-upstream-line"
  awk '{ print } /^ENV IMMICH_SOURCE_URL=/ { print "ENV IMMICH_DOCS_URL=https://github.com/immich-app/immich/tree/main/docs" }' "$base" > "$file"
  expect_failure "${ref}: new ENV line naming immich-app" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.label"
  awk '{ print } /^ENV IMMICH_SOURCE_URL=/ { print "LABEL org.opencontainers.image.source=https://github.com/immich-app/immich" }' "$base" > "$file"
  expect_failure "${ref}: LABEL naming immich-app" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.run-line"
  awk '{ print } /^ENV IMMICH_SOURCE_URL=/ { print "RUN echo https://github.com/immich-app/immich > /etc/immich-source" }' "$base" > "$file"
  expect_failure "${ref}: RUN line naming immich-app" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.other-image"
  awk '{ print } /^ENV IMMICH_SOURCE_URL=/ { print "COPY --from=ghcr.io/immich-app/immich-server:release /x /x" }' "$base" > "$file"
  expect_failure "${ref}: COPY from another immich-app image" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.other-from"
  sed 's|^FROM ghcr.io/immich-app/base-server-prod:|FROM ghcr.io/immich-app/immich-server-prod:|' "$base" > "$file"
  expect_failure "${ref}: FROM another immich-app image" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.continued"
  sed 's|^ENV IMMICH_REPOSITORY=.*|ENV IMMICH_REPOSITORY=immich-app/immich \\|' "$base" > "$file"
  expect_failure "${ref}: continued ENV line" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.two-vars"
  sed 's|^ENV IMMICH_REPOSITORY=.*|ENV IMMICH_REPOSITORY=immich-app/immich IMMICH_X=1|' "$base" > "$file"
  expect_failure "${ref}: two variables on one line" "$file" "$repository" "$run_id" "$commit" "$package"

  file="${base}.args"
  cp "$base" "$file"
  expect_failure "${ref}: upstream repository" "$file" immich-app/immich "$run_id" "$commit" "$package"
  expect_failure "${ref}: short commit" "$file" "$repository" "$run_id" 0123456 "$package"
  expect_failure "${ref}: run id with text" "$file" "$repository" "1; rm" "$commit" "$package"
done

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "all checks passed"
