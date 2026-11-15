#!/usr/bin/env bash
# Decides how a source ref is published as ghcr.io/<owner>/immich-server-allamiro and refuses refs
# that would publish a misleading image. Prints key=value lines for $GITHUB_OUTPUT.
#
# Environment:
#   SOURCE_REF          branch, tag or commit being built (without refs/heads/ or refs/tags/)
#   SOURCE_COMMIT       full SHA that was checked out
#   IS_TAG              true when SOURCE_REF is a tag in this repository
#   DEFAULT_BRANCH      default branch of this repository
#   REPOSITORY          owner/name of this repository
#   PACKAGE_VERSION     "version" of server/package.json at SOURCE_COMMIT
#   FORK_TAGS           existing tags of this repository, one per line (only v*-fork.* are used)
#   UPSTREAM_MAIN_BASE  merge base of SOURCE_COMMIT with upstream main, empty when unknown
#   FORK_DOC_IN_SOURCE  true when FORK.md exists at SOURCE_COMMIT
#   WORKFLOW_COMMIT     commit of the workflow file, used for FORK.md when the source lacks it
#   CREATED             value of org.opencontainers.image.created; the workflow passes the source
#                       commit's date so every job of a run computes the same labels (default: now)
#   SERVER_URL          default https://github.com
#
# Policy (patterns in tag-policy.sh):
#   - A tag, or any ref whose name or image tag looks like a release (v3, V3.4.1, 3.4.1, -v3.4.1),
#     must be a tag named vX.Y.Z[-pre]-fork.N, so an upstream release name is never published.
#   - For such a tag server/package.json must read X.Y.Z[-pre]-fork.N.
#   - A branch other than the default branch may not publish a channel name (latest, edge, main,
#     master, release, stable, nightly, in any case).
#   - tags are pushed first and checked; promote-tags are moved only after the checks pass:
#     fork release: tags <tag> <short commit>, promote latest when the tag has no prerelease part
#     and no higher stable fork tag exists; default branch: tags <short commit>, promote main
#     edge; other branches: tags <sanitized name> <short commit>, no promotion.

set -euo pipefail

# shellcheck source=SCRIPTDIR/tag-policy.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tag-policy.sh"

fail() {
  echo "::error::$*" >&2
  exit 1
}

sanitize_tag() {
  sed -E 's/[^A-Za-z0-9_.-]+/-/g; s/^[.-]+//' <<< "$1" | cut -c 1-128
}

: "${SOURCE_REF:?}" "${SOURCE_COMMIT:?}" "${DEFAULT_BRANCH:?}" "${REPOSITORY:?}"
IS_TAG=${IS_TAG:-false}
PACKAGE_VERSION=${PACKAGE_VERSION:-}
FORK_TAGS=${FORK_TAGS:-}
UPSTREAM_MAIN_BASE=${UPSTREAM_MAIN_BASE:-}
FORK_DOC_IN_SOURCE=${FORK_DOC_IN_SOURCE:-false}
WORKFLOW_COMMIT=${WORKFLOW_COMMIT:-$SOURCE_COMMIT}
SERVER_URL=${SERVER_URL:-https://github.com}
CREATED=${CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "Source commit '${SOURCE_COMMIT}' is not a full SHA."
[[ "$REPOSITORY" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || fail "Repository '${REPOSITORY}' is not owner/name."
[[ "$SOURCE_REF" =~ ^[A-Za-z0-9._/@+-]+$ ]] || fail "Source ref '${SOURCE_REF}' contains characters this workflow does not publish."

owner=$(tr '[:upper:]' '[:lower:]' <<< "${REPOSITORY%%/*}")
package=immich-server-allamiro
image="ghcr.io/${owner}/${package}"
short_commit=${SOURCE_COMMIT::7}
ref_tag=$(sanitize_tag "$SOURCE_REF")
[[ -n "$ref_tag" ]] || fail "Source ref '${SOURCE_REF}' gives an empty image tag."

release=false
prerelease=false
latest=false
previous_tag=''

if [[ "$IS_TAG" == true ]] || looks_like_release "$SOURCE_REF" || looks_like_release "$ref_tag"; then
  [[ "$SOURCE_REF" =~ $FORK_TAG_PATTERN ]] ||
    fail "Refusing to publish '${SOURCE_REF}': a release tag of this fork must be named vX.Y.Z-fork.N (or vX.Y.Z-pre-fork.N), for example v3.4.1-fork.1, so it never carries an upstream release name."
  [[ "$IS_TAG" == true ]] || fail "Refusing to publish '${SOURCE_REF}': a fork release name must be a tag in ${REPOSITORY}, not a branch or commit."

  base_version="${BASH_REMATCH[1]}"
  prerelease_part="${BASH_REMATCH[3]}"
  if [[ -n "$prerelease_part" ]]; then
    base_version="${base_version}-${prerelease_part}"
    prerelease=true
  fi
  expected_version="${SOURCE_REF#v}"
  if [[ "$PACKAGE_VERSION" != "$expected_version" ]]; then
    fail "Refusing to publish '${SOURCE_REF}': server/package.json at ${short_commit} has version '${PACKAGE_VERSION}', expected '${expected_version}'. Bump the version on the release branch, commit, and tag that commit."
  fi

  release=true
  base="v${base_version}"
  version="$SOURCE_REF"
  build_image="$SOURCE_REF"
  tags=("$SOURCE_REF" "$short_commit")
  promote_tags=()

  fork_tags=$(grep -E "$FORK_TAG_PATTERN" <<< "$FORK_TAGS" | grep -vxF "$SOURCE_REF" || true)
  if [[ "$prerelease" == false ]]; then
    stable_tags=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-fork\.[0-9]+$' <<< "$fork_tags" || true)
    newest=$(printf '%s\n' "$stable_tags" "$SOURCE_REF" | awk 'NF' | sort -V | tail -n 1)
    if [[ "$newest" == "$SOURCE_REF" ]]; then
      latest=true
      promote_tags+=(latest)
    fi
    candidates="$stable_tags"
  else
    candidates="$fork_tags"
  fi
  previous_tag=$(printf '%s\n' "$candidates" "$SOURCE_REF" | awk 'NF' | sort -V | grep -B 1 -xF "$SOURCE_REF" | grep -vxF "$SOURCE_REF" || true)
  description_base="release ${base}"
else
  if is_reserved_tag "$ref_tag" && [[ "$SOURCE_REF" != "$DEFAULT_BRANCH" ]]; then
    fail "Refusing to publish branch '${SOURCE_REF}': its image tag '${ref_tag}' is a channel name."
  fi
  if [[ -n "$UPSTREAM_MAIN_BASE" ]]; then
    [[ "$UPSTREAM_MAIN_BASE" =~ ^[0-9a-f]{40}$ ]] || fail "Upstream merge base '${UPSTREAM_MAIN_BASE}' is not a full SHA."
    base="upstream-main@${UPSTREAM_MAIN_BASE}"
    description_base="main at ${UPSTREAM_MAIN_BASE::9}"
  else
    base=upstream-main
    description_base=main
  fi
  version="$ref_tag"
  build_image="$ref_tag"
  if [[ "$SOURCE_REF" == "$DEFAULT_BRANCH" ]]; then
    tags=("$short_commit")
    promote_tags=(main edge)
  else
    tags=("$ref_tag" "$short_commit")
    promote_tags=()
  fi
fi

unique_tags=$(printf '%s\n' "${tags[@]}" | awk 'NF && !seen[$0]++' | paste -sd ' ' -)
unique_promote_tags=$(printf '%s\n' "${promote_tags[@]+"${promote_tags[@]}"}" | awk 'NF && !seen[$0]++' | paste -sd ' ' -)

created="$CREATED"
title='Immich Allamiro (unofficial fork build)'
description="Unofficial fork build of upstream Immich ${description_base} with the changes of ${REPOSITORY}. Not affiliated with or endorsed by the Immich project or FUTO."
source_url="${SERVER_URL}/${REPOSITORY}"

docs_commit="$SOURCE_COMMIT"
if [[ "$FORK_DOC_IN_SOURCE" != true ]]; then
  docs_commit="$WORKFLOW_COMMIT"
  echo "::warning::FORK.md is missing at ${short_commit}; the documentation label links to FORK.md at ${WORKFLOW_COMMIT::7} instead." >&2
fi

docs_url="${SERVER_URL}/${REPOSITORY}/blob/${docs_commit}/FORK.md"
delimiter=$(random_delimiter)

cat << EOF
image=${image}
package=${package}
cache-image=${image}-build-cache
cache-scope=${ref_tag}
default-branch-cache-scope=$(sanitize_tag "$DEFAULT_BRANCH")
source-ref=${SOURCE_REF}
source-commit=${SOURCE_COMMIT}
build-image=${build_image}
tags=${unique_tags}
promote-tags=${unique_promote_tags}
release=${release}
prerelease=${prerelease}
latest=${latest}
previous-tag=${previous_tag}
version=${version}
base=${base}
title=${title}
description=${description}
source-url=${source_url}
docs-url=${docs_url}
created=${created}
labels<<${delimiter}
org.opencontainers.image.title=${title}
org.opencontainers.image.description=${description}
org.opencontainers.image.source=${source_url}
org.opencontainers.image.url=${source_url}/pkgs/container/${package}
org.opencontainers.image.documentation=${docs_url}
org.opencontainers.image.revision=${SOURCE_COMMIT}
org.opencontainers.image.version=${version}
org.opencontainers.image.licenses=AGPL-3.0
org.opencontainers.image.created=${created}
io.github.allamiro.fork.base=${base}
io.github.allamiro.fork.unofficial=true
${delimiter}
EOF
