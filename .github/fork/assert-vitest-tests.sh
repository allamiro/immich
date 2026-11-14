#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <vitest-json-report> <describe-title> <minimum-passed> [required-test-title-regex]" >&2
  exit 2
fi

report="$1"
describe_title="$2"
minimum_passed="$3"
required_title="${4:-}"

if [[ ! -s "$report" ]]; then
  echo "::error::${report} is missing or empty, so the tests in '${describe_title}' did not run."
  exit 1
fi

read -r total passed failed required < <(jq -r --arg block "$describe_title" --arg title "$required_title" '
  [.testResults[].assertionResults[] | select(.ancestorTitles | index($block))] as $tests
  | [
      ($tests | length),
      ($tests | map(select(.status == "passed")) | length),
      ($tests | map(select(.status == "failed")) | length),
      ($tests | map(select(.status == "passed" and ($title == "" or (.title | test($title))))) | length)
    ]
  | @tsv' "$report")

echo "'${describe_title}': ${total} tests, ${passed} passed, ${failed} failed."

status=0
if ((failed > 0)); then
  echo "::error::${failed} test(s) in '${describe_title}' failed."
  status=1
fi
if ((passed < minimum_passed)); then
  echo "::error::Only ${passed} test(s) in '${describe_title}' passed, expected at least ${minimum_passed}. Tests were removed, renamed or skipped."
  status=1
fi
if ((passed != total - failed)); then
  echo "::error::$((total - failed - passed)) test(s) in '${describe_title}' were skipped."
  status=1
fi
if [[ -n "$required_title" ]] && ((required == 0)); then
  echo "::error::No passing test in '${describe_title}' matches '${required_title}'."
  status=1
fi
exit "$status"
