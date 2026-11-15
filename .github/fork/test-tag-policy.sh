#!/usr/bin/env bash
# Tests for tag-policy.sh: release-like names, channel names, registry tags and helpers.

set -euo pipefail

# shellcheck source=SCRIPTDIR/tag-policy.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tag-policy.sh"
failures=0

expect() {
  local name=$1 expected=$2
  shift 2
  if "$@"; then actual=true; else actual=false; fi
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   ${name}: ${actual}"
  else
    echo "FAIL ${name}: ${actual}, expected ${expected}"
    failures=$((failures + 1))
  fi
}

for name in v3.4.1 V3.4.1 v3 v3.4 3.4 3.4.1 3.4.1-rc.1 v3.4.1-rc.1 v2-hotfix v3.4.1-fork.1; do
  expect "looks_like_release ${name}" true looks_like_release "$name"
done
for name in main edge latest fork-identity e815b89 1234567 8c979c4 123-fix release-notes vnext; do
  expect "looks_like_release ${name}" false looks_like_release "$name"
done
for name in latest Latest EDGE main release stable nightly master; do
  expect "is_reserved_tag ${name}" true is_reserved_tag "$name"
done
for name in v3.4.1 V3.4.1 3.4.1 v3 v3.4.1-rc.1 3.4.1-fork.1 V3.4.1-fork.1 Latest release stable EDGE MAIN; do
  expect "is_foreign_tag ${name}" true is_foreign_tag "$name"
done
for name in v3.4.1-fork.1 v3.5.0-rc.1-fork.2 latest edge main fork-identity e815b89 1234567; do
  expect "is_foreign_tag ${name}" false is_foreign_tag "$name"
done

first=$(random_delimiter)
second=$(random_delimiter)
if [[ "$first" =~ ^FORK_EOF_[0-9a-f]{24}$ && "$first" != "$second" ]]; then
  echo "ok   random_delimiter ${first} ${second}"
else
  echo "FAIL random_delimiter '${first}' '${second}'"
  failures=$((failures + 1))
fi

counter=$(mktemp)
trap 'rm -f "$counter"' EXIT
flaky() {
  echo x >> "$counter"
  [[ $(wc -l < "$counter") -ge 3 ]]
}
if RETRY_DELAY=0 retry flaky 2> /dev/null; then
  echo "ok   retry: succeeded after $(wc -l < "$counter" | tr -d ' ') attempts"
else
  echo "FAIL retry: gave up"
  failures=$((failures + 1))
fi
: > "$counter"
if RETRY_DELAY=0 RETRY_ATTEMPTS=2 retry flaky 2> /dev/null; then
  echo "FAIL retry: should give up after 2 attempts"
  failures=$((failures + 1))
else
  echo "ok   retry: gave up after $(wc -l < "$counter" | tr -d ' ') attempts"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} case(s) failed"
  exit 1
fi
echo "all cases passed"
