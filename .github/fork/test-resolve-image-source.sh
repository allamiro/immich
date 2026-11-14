#!/usr/bin/env bash
# Table tests for resolve-image-source.sh: the release tag gate, the version check, tags and labels.

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-image-source.sh"
commit=0123456789abcdef0123456789abcdef01234567
upstream=e5d6eb7be67834f59d90e4b7a86f5dec7ac9af86
failures=0

run() {
  env -i PATH="$PATH" SOURCE_COMMIT="$commit" DEFAULT_BRANCH=main REPOSITORY=allamiro/immich \
    FORK_DOC_IN_SOURCE=true "$@" "$script"
}

field() {
  sed -n "s/^$1=//p" <<< "$2"
}

check() {
  local name=$1 output=$2
  shift 2
  local problems=()
  local pair key expected actual
  for pair in "$@"; do
    key=${pair%%=*}
    expected=${pair#*=}
    actual=$(field "$key" "$output")
    [[ "$actual" == "$expected" ]] || problems+=("${key}: '${actual}' != '${expected}'")
  done
  if [[ ${#problems[@]} -eq 0 ]]; then
    echo "ok   ${name}: tags='$(field tags "$output")' version='$(field version "$output")' base='$(field base "$output")'"
  else
    echo "FAIL ${name}: ${problems[*]}"
    failures=$((failures + 1))
  fi
}

accept() {
  local name=$1
  shift
  local environment=() expectations=() seen_separator=false argument output
  for argument in "$@"; do
    if [[ "$argument" == -- ]]; then
      seen_separator=true
    elif [[ "$seen_separator" == false ]]; then
      environment+=("$argument")
    else
      expectations+=("$argument")
    fi
  done
  if output=$(run "${environment[@]}" 2> /dev/null); then
    check "$name" "$output" "${expectations[@]}"
  else
    echo "FAIL ${name}: refused: $(run "${environment[@]}" 2>&1 > /dev/null | tail -n 1 || true)"
    failures=$((failures + 1))
  fi
}

refuse() {
  local name=$1 message
  shift
  if run "$@" > /dev/null 2>&1; then
    echo "FAIL ${name}: accepted"
    failures=$((failures + 1))
  else
    message=$(run "$@" 2>&1 > /dev/null | tail -n 1 || true)
    echo "ok   ${name}: ${message}"
  fi
}

existing=$'v3.4.0-fork.1\nv3.4.0-fork.2\nv3.4.1-fork.1\nv3.5.0-rc.1-fork.1\nv3.4.1\nv3.3.9'

accept 'default branch' SOURCE_REF=main UPSTREAM_MAIN_BASE="$upstream" -- \
  release=false latest=false tags='main 0123456 edge' version=main build-image=main \
  base="upstream-main@${upstream}" \
  'description=Unofficial fork build of upstream Immich main at e5d6eb7be with the changes of allamiro/immich. Not affiliated with or endorsed by the Immich project or FUTO.' \
  docs-url="https://github.com/allamiro/immich/blob/${commit}/FORK.md" image=ghcr.io/allamiro/immich-server-allamiro \
  'title=Immich Allamiro (unofficial fork build)' source-url=https://github.com/allamiro/immich \
  'org.opencontainers.image.title=Immich Allamiro (unofficial fork build)' \
  org.opencontainers.image.source=https://github.com/allamiro/immich \
  org.opencontainers.image.url=https://github.com/allamiro/immich/pkgs/container/immich-server-allamiro \
  org.opencontainers.image.revision="$commit" org.opencontainers.image.version=main \
  org.opencontainers.image.licenses=AGPL-3.0 io.github.allamiro.fork.base="upstream-main@${upstream}" \
  io.github.allamiro.fork.unofficial=true
accept 'default branch without merge base' SOURCE_REF=main -- base=upstream-main tags='main 0123456 edge'
accept 'validation branch' SOURCE_REF=fork/identity UPSTREAM_MAIN_BASE="$upstream" -- \
  release=false tags='fork-identity 0123456' version=fork-identity cache-scope=fork-identity
accept 'stable branch, not a tag' SOURCE_REF=fork/v3.4.1 PACKAGE_VERSION=3.4.1 -- release=false tags='fork-v3.4.1 0123456'
accept 'first stable fork release' SOURCE_REF=v3.4.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1 -- \
  release=true prerelease=false latest=true tags='v3.4.1-fork.1 0123456 latest' version=v3.4.1-fork.1 base=v3.4.1 \
  previous-tag='' 'description=Unofficial fork build of upstream Immich release v3.4.1 with the changes of allamiro/immich. Not affiliated with or endorsed by the Immich project or FUTO.' \
  'org.opencontainers.image.description=Unofficial fork build of upstream Immich release v3.4.1 with the changes of allamiro/immich. Not affiliated with or endorsed by the Immich project or FUTO.' \
  org.opencontainers.image.version=v3.4.1-fork.1 io.github.allamiro.fork.base=v3.4.1 \
  org.opencontainers.image.documentation="https://github.com/allamiro/immich/blob/${commit}/FORK.md"
accept 'second build of the same release' SOURCE_REF=v3.4.1-fork.2 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.2 FORK_TAGS="$existing" -- \
  release=true latest=true tags='v3.4.1-fork.2 0123456 latest' base=v3.4.1 previous-tag=v3.4.1-fork.1
accept 'rebuild of an older release keeps latest' SOURCE_REF=v3.4.0-fork.2 IS_TAG=true PACKAGE_VERSION=3.4.0-fork.2 FORK_TAGS="$existing" -- \
  release=true latest=false tags='v3.4.0-fork.2 0123456' base=v3.4.0 previous-tag=v3.4.0-fork.1
accept 'fork.10 sorts after fork.9' SOURCE_REF=v3.4.1-fork.10 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.10 FORK_TAGS=$'v3.4.1-fork.9\nv3.4.1-fork.2' -- \
  latest=true previous-tag=v3.4.1-fork.9
accept 'release candidate' SOURCE_REF=v3.5.0-rc.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.5.0-rc.1-fork.1 FORK_TAGS="$existing" -- \
  release=true prerelease=true latest=false tags='v3.5.0-rc.1-fork.1 0123456' base=v3.5.0-rc.1
accept 'FORK.md missing in the source' SOURCE_REF=v3.4.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1 FORK_DOC_IN_SOURCE=false WORKFLOW_COMMIT=fedcba9876543210fedcba9876543210fedcba98 -- \
  docs-url=https://github.com/allamiro/immich/blob/fedcba9876543210fedcba9876543210fedcba98/FORK.md

refuse 'upstream release name v3.4.1' SOURCE_REF=v3.4.1 IS_TAG=true PACKAGE_VERSION=3.4.1
refuse 'upstream release name 3.4.1' SOURCE_REF=3.4.1 IS_TAG=true PACKAGE_VERSION=3.4.1
refuse 'upstream release name as a branch' SOURCE_REF=v3.4.1 PACKAGE_VERSION=3.4.1
refuse 'upstream release candidate' SOURCE_REF=v3.5.0-rc.1 IS_TAG=true PACKAGE_VERSION=3.5.0-rc.1
refuse 'fork tag without v' SOURCE_REF=3.4.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1
refuse 'fork tag without number' SOURCE_REF=v3.4.1-fork IS_TAG=true PACKAGE_VERSION=3.4.1-fork
refuse 'fork tag with a suffix' SOURCE_REF=v3.4.1-fork.1-hotfix IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1-hotfix
refuse 'two-part version' SOURCE_REF=v3.4-fork.1 IS_TAG=true PACKAGE_VERSION=3.4-fork.1
refuse 'other tag' SOURCE_REF=nightly IS_TAG=true
refuse 'fork name on a branch' SOURCE_REF=v3.4.1-fork.1 PACKAGE_VERSION=3.4.1-fork.1
refuse 'package.json not bumped' SOURCE_REF=v3.4.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.4.1
refuse 'package.json of another build' SOURCE_REF=v3.4.1-fork.2 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1
refuse 'package.json missing' SOURCE_REF=v3.4.1-fork.1 IS_TAG=true
refuse 'branch named latest' SOURCE_REF=latest
refuse 'branch named edge' SOURCE_REF=edge

created=$(field org.opencontainers.image.created "$(run SOURCE_REF=main)")
if [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "ok   created label ${created}"
else
  echo "FAIL created label '${created}'"
  failures=$((failures + 1))
fi
labels=$(run SOURCE_REF=v3.4.1-fork.1 IS_TAG=true PACKAGE_VERSION=3.4.1-fork.1 | sed -n '/^labels<<FORK_LABELS$/,/^FORK_LABELS$/p')
if [[ $(grep -c . <<< "$labels") -eq 13 ]] && ! grep -qiE 'immich-app|vendor' <<< "$labels"; then
  echo "ok   labels block: 11 labels, no immich-app, no vendor"
  while IFS= read -r line; do echo "     ${line}"; done <<< "$labels"
else
  echo "FAIL labels block: ${labels}"
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} case(s) failed"
  exit 1
fi
echo "all cases passed"
