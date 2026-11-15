#!/usr/bin/env bash
# Resolves what a Fork Build Image run publishes, from the ref alone, so every job of the run can
# compute the same image name, tags, labels and release facts without passing job outputs. Fails
# (before anything is pushed) when the ref breaks the fork's release rules; see
# resolve-image-source.sh for the policy. Prints key=value lines for $GITHUB_OUTPUT.
#
# Environment:
#   REQUESTED_REF        workflow_dispatch input "ref", empty when not given
#   TRIGGER_REF_NAME     github.ref_name
#   TRIGGER_REF_TYPE     github.ref_type (branch or tag)
#   DEFAULT_BRANCH       default branch of this repository
#   REPOSITORY           owner/name of this repository
#   WORKFLOW_COMMIT      github.workflow_sha
#   SOURCE_DIR           checkout of the ref (at least server/package.json and FORK.md), default source
#   UPSTREAM_REPOSITORY  default immich-app/immich
#   UPSTREAM_BRANCH      default main
#   SERVER_URL           default https://github.com
#   GH_TOKEN             token for the GitHub API (gh)

set -euo pipefail

: "${DEFAULT_BRANCH:?}" "${REPOSITORY:?}"
REQUESTED_REF=${REQUESTED_REF:-}
TRIGGER_REF_NAME=${TRIGGER_REF_NAME:-}
TRIGGER_REF_TYPE=${TRIGGER_REF_TYPE:-branch}
SOURCE_DIR=${SOURCE_DIR:-source}
UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-immich-app/immich}
UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-main}
policy="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-image-source.sh"

fail() {
  echo "::error::$*" >&2
  exit 1
}

source_ref="${REQUESTED_REF:-$TRIGGER_REF_NAME}"
[[ -n "$source_ref" ]] || fail "No ref to build."
requested_as_tag=false
if [[ "$source_ref" == refs/tags/* ]] || [[ -z "$REQUESTED_REF" && "$TRIGGER_REF_TYPE" == tag ]]; then
  requested_as_tag=true
fi
source_ref="${source_ref#refs/heads/}"
source_ref="${source_ref#refs/tags/}"
source_commit=$(git -C "$SOURCE_DIR" rev-parse HEAD)

all_tags=$(gh api "repos/${REPOSITORY}/git/matching-refs/tags/" --paginate --jq '.[].ref | sub("^refs/tags/"; "")')
is_tag=false
if [[ "$requested_as_tag" == true ]] || grep -qxF "$source_ref" <<< "$all_tags"; then
  is_tag=true
  tag_commit=$(gh api "repos/${REPOSITORY}/commits/refs/tags/${source_ref}" --jq .sha)
  [[ "$tag_commit" == "$source_commit" ]] ||
    fail "Tag ${source_ref} points at ${tag_commit}, but the checkout is ${source_commit}."
fi

upstream_main_base=''
if [[ "$is_tag" != true ]]; then
  if ! upstream_main_base=$(gh api "repos/${REPOSITORY}/compare/${UPSTREAM_REPOSITORY%%/*}:${UPSTREAM_BRANCH}...${source_commit}" \
    --jq .merge_base_commit.sha); then
    echo "::warning::Could not compute the merge base with upstream ${UPSTREAM_BRANCH}; the base label reads upstream-main." >&2
    upstream_main_base=''
  fi
fi

fork_doc_in_source=false
if [[ -f "${SOURCE_DIR}/FORK.md" ]]; then
  fork_doc_in_source=true
fi
package_version=''
if [[ -f "${SOURCE_DIR}/server/package.json" ]]; then
  package_version=$(jq -r '.version // empty' "${SOURCE_DIR}/server/package.json")
fi
created=$(TZ=UTC git -C "$SOURCE_DIR" log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd)

resolved=$(
  SOURCE_REF="$source_ref" SOURCE_COMMIT="$source_commit" IS_TAG="$is_tag" PACKAGE_VERSION="$package_version" \
    FORK_TAGS="$all_tags" UPSTREAM_MAIN_BASE="$upstream_main_base" FORK_DOC_IN_SOURCE="$fork_doc_in_source" \
    CREATED="$created" "$policy"
)

upstream_base_commit=''
if [[ "$(sed -n 's/^release=//p' <<< "$resolved")" == true ]]; then
  base=$(sed -n 's/^base=//p' <<< "$resolved")
  upstream_base_commit=$(gh api "repos/${UPSTREAM_REPOSITORY}/commits/refs/tags/${base}" --jq .sha) ||
    fail "${source_ref} names upstream ${base} as its base, but ${UPSTREAM_REPOSITORY} has no tag ${base}."
  status=$(gh api "repos/${REPOSITORY}/compare/${upstream_base_commit}...${source_commit}" --jq .status)
  [[ "$status" == ahead || "$status" == identical ]] ||
    fail "${source_ref} (${source_commit}) does not contain upstream ${base} (${upstream_base_commit}); compare status '${status}'."
fi

echo "$resolved"
echo "upstream-base-commit=${upstream_base_commit}"
