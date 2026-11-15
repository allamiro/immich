#!/usr/bin/env bash
# Runs resolve.sh against throwaway git repositories with a stub gh that answers the GitHub API calls
# from the local history: the default branch, fork release tags, upstream release names and a
# release candidate.

set -euo pipefail

resolve="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir -p "${work}/bin"
cat > "${work}/bin/gh" << 'STUB'
#!/usr/bin/env bash
# Stub for: gh api <path> [--paginate] --jq <filter>
set -euo pipefail
path=$2
cd "$SOURCE_DIR"
case "$path" in
  repos/*/git/matching-refs/tags/)
    git tag --list | grep -v '^upstream-' || true
    ;;
  repos/immich-app/immich/commits/refs/tags/*)
    git rev-parse --verify --quiet "upstream-${path##*/}^{commit}" || { echo "HTTP 404" >&2; exit 1; }
    ;;
  repos/*/commits/refs/tags/*)
    git rev-parse --verify --quiet "${path##*/}^{commit}" || { echo "HTTP 404" >&2; exit 1; }
    ;;
  repos/*/compare/immich-app:main...*)
    git rev-parse upstream-main
    ;;
  repos/*/compare/*)
    range=${path##*/compare/}
    base=${range%%...*}
    head=${range##*...}
    if [[ "$(git rev-parse "$base")" == "$(git rev-parse "$head")" ]]; then
      echo identical
    elif git merge-base --is-ancestor "$base" "$head"; then
      echo ahead
    else
      echo diverged
    fi
    ;;
  *)
    echo "stub gh: unexpected $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "${work}/bin/gh"

repo="${work}/source"
git init -q "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
commit() {
  mkdir -p "${repo}/server"
  printf '{ "version": "%s" }\n' "$1" > "${repo}/server/package.json"
  git -C "$repo" add -A
  GIT_COMMITTER_DATE="$2" git -C "$repo" commit -q -m "$1" --date "$2"
}
commit 3.4.0-rc.0 '2026-11-01T10:00:00Z'
git -C "$repo" tag upstream-main
commit 3.4.1 '2026-11-02T10:00:00Z'
git -C "$repo" tag upstream-v3.4.1
git -C "$repo" tag v3.4.1
git -C "$repo" tag 3.4.1
echo fork > "${repo}/FORK.md"
commit 3.4.1-fork.1 '2026-11-15T09:30:00Z'
git -C "$repo" tag v3.4.1-fork.1
commit 3.5.0-rc.1-fork.1 '2026-11-16T09:30:00Z'
git -C "$repo" tag upstream-v3.5.0-rc.1 HEAD~3
git -C "$repo" tag v3.5.0-rc.1-fork.1
commit 3.6.0-fork.1 '2026-11-17T09:30:00Z'
git -C "$repo" tag v3.6.0-fork.1
commit 3.5.0-fork.1 '2026-11-18T09:30:00Z'
git -C "$repo" tag v3.5.0-fork.1
git -C "$repo" checkout -q --detach upstream-main
commit 3.5.0 '2026-11-18T10:00:00Z'
git -C "$repo" tag upstream-v3.5.0

run() {
  local ref=$1 checkout=$2
  git -C "$repo" checkout -q --detach "$checkout"
  env PATH="${work}/bin:${PATH}" RETRY_DELAY=0 SOURCE_DIR="$repo" REQUESTED_REF="$ref" TRIGGER_REF_NAME=main \
    DEFAULT_BRANCH=main REPOSITORY=allamiro/immich WORKFLOW_COMMIT=fedcba9876543210fedcba9876543210fedcba98 \
    "$resolve"
}

show() {
  grep -E '^(tags|promote-tags|release|prerelease|latest|version|base|previous-tag|upstream-base-commit|org.opencontainers.image.created|org.opencontainers.image.documentation)=' <<< "$1" |
    while IFS= read -r line; do echo "     ${line}"; done
}

expect() {
  local name=$1 ref=$2 checkout=$3 expected=$4 output
  if output=$(run "$ref" "$checkout" 2>&1); then
    if [[ "$expected" == ok ]]; then
      echo "ok   ${name}"
      show "$output"
    else
      echo "FAIL ${name}: accepted"
      failures=$((failures + 1))
    fi
  elif [[ "$expected" == fail ]]; then
    echo "ok   ${name}: $(grep '::error::' <<< "$output" | tail -n 1)"
  else
    echo "FAIL ${name}: $(tail -n 1 <<< "$output")"
    failures=$((failures + 1))
  fi
}

expect 'default branch main' main v3.4.1-fork.1 ok
expect 'good fork tag v3.4.1-fork.1' v3.4.1-fork.1 v3.4.1-fork.1 ok
expect 'fork release candidate v3.5.0-rc.1-fork.1' v3.5.0-rc.1-fork.1 v3.5.0-rc.1-fork.1 ok
expect 'upstream release name v3.4.1' v3.4.1 v3.4.1 fail
expect 'upstream release name 3.4.1' 3.4.1 3.4.1 fail
expect 'tag given as refs/tags/v3.4.1' refs/tags/v3.4.1 v3.4.1 fail
expect 'fork tag but checkout elsewhere' v3.4.1-fork.1 v3.4.1 fail
expect 'fork tag whose upstream base does not exist' v3.6.0-fork.1 v3.6.0-fork.1 fail
expect 'fork tag that does not contain its upstream base' v3.5.0-fork.1 v3.5.0-fork.1 fail
expect 'branch -v3.4.1 (image tag v3.4.1)' -v3.4.1 v3.4.1-fork.1 fail
expect 'branch --3.4.1 (image tag 3.4.1)' --3.4.1 v3.4.1-fork.1 fail
expect 'branch V3.4.1' V3.4.1 v3.4.1-fork.1 fail
expect 'branch v3' v3 v3.4.1-fork.1 fail
expect 'branch release' release v3.4.1-fork.1 fail
expect 'branch Latest' Latest v3.4.1-fork.1 fail
expect 'branch fork/identity' fork/identity v3.4.1-fork.1 ok

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} case(s) failed"
  exit 1
fi
echo "all cases passed"
