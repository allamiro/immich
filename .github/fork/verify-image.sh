#!/usr/bin/env bash
# Checks a published multi-arch image of this fork from the registry: every platform must carry the
# fork's build metadata, labels, provenance and SBOM, the index the fork's annotations, and the tags
# must follow the fork's tag policy.
#
# Usage: verify-image.sh <image> <manifest-list-digest>
#
# Environment:
#   EXPECTED_REPOSITORY  owner/name of this repository
#   EXPECTED_RUN_ID      run id of the build
#   EXPECTED_COMMIT      full source commit
#   EXPECTED_BUILD_IMAGE value of IMMICH_BUILD_IMAGE
#   EXPECTED_SOURCE_REF  value of IMMICH_SOURCE_REF
#   EXPECTED_PACKAGE     container package name
#   EXPECTED_LABELS      key=value lines every platform and the index must carry
#   EXPECTED_TAGS        space separated tags that must point at the digest; the channel tags
#                        latest, edge and main must not point at it unless listed here
#   EXPECTED_PLATFORMS   space separated platforms, default "linux/amd64 linux/arm64"
#   REGISTRY_USER, REGISTRY_TOKEN  optional credentials for listing tags; anonymous otherwise
#   SERVER_URL           default https://github.com

set -euo pipefail

# shellcheck source=SCRIPTDIR/tag-policy.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tag-policy.sh"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <image> <manifest-list-digest>" >&2
  exit 64
fi

image=$1
digest=$2
: "${EXPECTED_REPOSITORY:?}" "${EXPECTED_RUN_ID:?}" "${EXPECTED_COMMIT:?}" "${EXPECTED_BUILD_IMAGE:?}"
: "${EXPECTED_PACKAGE:?}" "${EXPECTED_LABELS:?}" "${EXPECTED_TAGS:?}" "${EXPECTED_SOURCE_REF:?}"
platforms=${EXPECTED_PLATFORMS:-linux/amd64 linux/arm64}
server_url=${SERVER_URL:-https://github.com}
repository_url="${server_url}/${EXPECTED_REPOSITORY}"
problems=0

ok() { echo "ok   $*"; }
problem() {
  echo "::error::${image}@${digest}: $*"
  problems=$((problems + 1))
}

[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "::error::'${digest}' is not a sha256 digest" >&2
  exit 1
}

reference="${image}@${digest}"
manifest=$(retry docker buildx imagetools inspect "$reference" --format '{{json .Manifest}}')
configs=$(retry docker buildx imagetools inspect "$reference" --format '{{json .Image}}')
provenance=$(retry docker buildx imagetools inspect "$reference" --format '{{json .Provenance}}')
sbom=$(retry docker buildx imagetools inspect "$reference" --format '{{json .SBOM}}')

expected_env=$(
  cat << EOF
IMMICH_BUILD=${EXPECTED_RUN_ID}
IMMICH_BUILD_URL=${repository_url}/actions/runs/${EXPECTED_RUN_ID}
IMMICH_BUILD_IMAGE=${EXPECTED_BUILD_IMAGE}
IMMICH_BUILD_IMAGE_URL=${repository_url}/pkgs/container/${EXPECTED_PACKAGE}
IMMICH_REPOSITORY=${EXPECTED_REPOSITORY}
IMMICH_REPOSITORY_URL=${repository_url}
IMMICH_SOURCE_REF=${EXPECTED_SOURCE_REF}
IMMICH_SOURCE_COMMIT=${EXPECTED_COMMIT}
IMMICH_SOURCE_URL=${repository_url}/commit/${EXPECTED_COMMIT}
EOF
)

published_platforms=$(jq -r '.manifests[] | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"' <<< "$manifest" | sort)
if [[ "$published_platforms" == "$(tr ' ' '\n' <<< "$platforms" | sort)" ]]; then
  ok "platforms: $(paste -sd ' ' - <<< "$published_platforms")"
else
  problem "platforms are '$(paste -sd ' ' - <<< "$published_platforms")', expected '${platforms}'"
fi

for platform in $platforms; do
  config=$(jq --arg platform "$platform" '.[$platform] // empty' <<< "$configs")
  if [[ -z "$config" ]]; then
    problem "${platform}: no image config"
    continue
  fi

  while IFS= read -r pair; do
    key=${pair%%=*}
    actual=$(jq -r --arg key "$key" '.config.Env[] | select(startswith($key + "=")) | sub("^[^=]*="; "")' <<< "$config")
    if [[ "$actual" == "${pair#*=}" ]]; then
      ok "${platform}: ENV ${pair}"
    else
      problem "${platform}: ENV ${key}='${actual}', expected '${pair#*=}'"
    fi
  done <<< "$expected_env"

  repository_env=$(jq -r '.config.Env[] | select(startswith("IMMICH_REPOSITORY_URL="))' <<< "$config")
  if [[ "$repository_env" == *"$EXPECTED_REPOSITORY"* && "$repository_env" != *immich-app* ]]; then
    ok "${platform}: ${repository_env} names this repository and not immich-app"
  else
    problem "${platform}: ${repository_env:-IMMICH_REPOSITORY_URL missing}"
  fi

  upstream_env=$(jq -r '.config.Env[] | select(test("immich-app"))' <<< "$config")
  if [[ -z "$upstream_env" ]]; then
    ok "${platform}: no ENV names immich-app"
  else
    problem "${platform}: ENV names immich-app: ${upstream_env}"
  fi

  while IFS= read -r pair; do
    [[ -n "$pair" ]] || continue
    key=${pair%%=*}
    actual=$(jq -r --arg key "$key" '.config.Labels[$key] // "<missing>"' <<< "$config")
    if [[ "$actual" == "${pair#*=}" ]]; then
      ok "${platform}: LABEL ${pair}"
    else
      problem "${platform}: LABEL ${key}='${actual}', expected '${pair#*=}'"
    fi
  done <<< "$EXPECTED_LABELS"

  upstream_labels=$(jq -r '.config.Labels // {} | to_entries[] | select(.value | test("immich-app"; "i")) | "\(.key)=\(.value)"' <<< "$config")
  if [[ -z "$upstream_labels" ]]; then
    ok "${platform}: no LABEL names immich-app"
  else
    problem "${platform}: LABEL names immich-app: ${upstream_labels}"
  fi
  vendor=$(jq -r '.config.Labels["org.opencontainers.image.vendor"] // ""' <<< "$config")
  if grep -qiE 'immich|futo' <<< "$vendor"; then
    problem "${platform}: vendor label '${vendor}' names upstream"
  else
    ok "${platform}: vendor label '${vendor}'"
  fi

  slsa=$(jq -c --arg platform "$platform" '.[$platform].SLSA // empty' <<< "$provenance")
  if [[ -z "$slsa" ]]; then
    problem "${platform}: no provenance attestation"
  else
    vcs=$(jq -c '.runDetails.metadata.buildkit_metadata.vcs // .metadata["https://mobyproject.org/buildkit@v1#metadata"].vcs // {}' <<< "$slsa")
    vcs_revision=$(jq -r '.revision // empty' <<< "$vcs")
    vcs_source=$(jq -r '.source // empty' <<< "$vcs")
    builder=$(jq -r '.runDetails.builder.id // .builder.id // empty' <<< "$slsa")
    if [[ "$vcs_revision" == "$EXPECTED_COMMIT" && "${vcs_source%.git}" == "$repository_url" ]]; then
      ok "${platform}: provenance names ${vcs_source} at ${vcs_revision}"
    else
      problem "${platform}: provenance names '${vcs_source}' at '${vcs_revision}'"
    fi
    if [[ "$builder" == "${repository_url}/actions/runs/${EXPECTED_RUN_ID}/"* ]]; then
      ok "${platform}: provenance builder ${builder}"
    else
      problem "${platform}: provenance builder '${builder}'"
    fi
  fi
  if jq -e --arg platform "$platform" '.[$platform].SPDX // empty | length > 0' <<< "$sbom" > /dev/null; then
    ok "${platform}: SBOM attestation present"
  else
    problem "${platform}: no SBOM attestation"
  fi
done

while IFS= read -r pair; do
  [[ -n "$pair" ]] || continue
  key=${pair%%=*}
  actual=$(jq -r --arg key "$key" '.annotations[$key] // "<missing>"' <<< "$manifest")
  if [[ "$actual" == "${pair#*=}" ]]; then
    ok "index: annotation ${key}"
  else
    problem "index: annotation ${key}='${actual}', expected '${pair#*=}'"
  fi
done <<< "$EXPECTED_LABELS"

tag_digest() {
  local output errors
  errors=$(mktemp)
  if output=$(retry docker buildx imagetools inspect "${image}:$1" --format '{{json .Manifest}}' 2> "$errors"); then
    jq -r '.digest // empty' <<< "$output"
  elif grep -qi 'not found' "$errors"; then
    echo ''
  else
    echo "error: $(tail -n 1 "$errors")"
  fi
  rm -f "$errors"
}

for tag in $EXPECTED_TAGS; do
  actual=$(RETRY_ATTEMPTS=3 tag_digest "$tag")
  if [[ "$actual" == "$digest" ]]; then
    ok "tag ${tag} -> ${digest}"
  else
    problem "tag ${tag} points at '${actual}'"
  fi
done

for tag in $PROMOTED_TAGS; do
  if grep -qxF "$tag" <<< "$(tr ' ' '\n' <<< "$EXPECTED_TAGS")"; then
    continue
  fi
  actual=$(RETRY_ATTEMPTS=1 tag_digest "$tag")
  if [[ "$actual" == "$digest" ]]; then
    problem "${tag} points at this build, which should not move it"
  else
    ok "${tag} not moved to this build (${actual:-absent})"
  fi
done

repository_path=${image#*/}
registry=${image%%/*}
scope="repository:${repository_path}:pull"
if [[ -n "${REGISTRY_TOKEN:-}" ]]; then
  token=$(retry curl -fsS -u "${REGISTRY_USER:-token}:${REGISTRY_TOKEN}" "https://${registry}/token?scope=${scope}" | jq -r .token)
else
  token=$(retry curl -fsS "https://${registry}/token?scope=${scope}" | jq -r .token)
fi
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
all_tags=''
next="/v2/${repository_path}/tags/list?n=1000"
pages=0
while [[ -n "$next" ]]; do
  page=$(retry curl -fsS -D "$headers" -H "Authorization: Bearer ${token}" "https://${registry}${next}")
  all_tags+=$(jq -r '.tags[]?' <<< "$page")$'\n'
  next=$(sed -nE 's/^[Ll]ink: *<([^>]+)>.*rel="?next"?.*/\1/p' "$headers" | tr -d '\r')
  pages=$((pages + 1))
  if [[ "$pages" -gt 100 ]]; then
    problem "registry: more than 100 pages of tags"
    break
  fi
done
all_tags=$(awk 'NF' <<< "$all_tags")
bad_tags=''
while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  if is_foreign_tag "$tag"; then
    bad_tags+="${tag} "
  fi
done <<< "$all_tags"
if [[ -z "$bad_tags" ]]; then
  ok "registry: $(grep -c . <<< "$all_tags") tags in ${pages} page(s), none looks like an upstream release or a foreign channel"
else
  problem "registry: tags that look like upstream releases or channels this fork does not publish: ${bad_tags}"
fi

if [[ "$problems" -gt 0 ]]; then
  echo "::error::${problems} check(s) failed for ${reference}"
  exit 1
fi
echo "all checks passed for ${reference}"
