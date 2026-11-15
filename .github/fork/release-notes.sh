#!/usr/bin/env bash
# Writes the GitHub release notes of a fork release tag from facts of the build. It never copies
# upstream's release notes; it links to them as the base.
#
# Environment:
#   TAG                   fork release tag, vX.Y.Z[-pre]-fork.N
#   BASE                  upstream release the tag is based on, vX.Y.Z[-pre]
#   UPSTREAM_BASE_COMMIT  commit of the upstream release tag
#   SOURCE_COMMIT         commit the image was built from
#   PREVIOUS_TAG          previous fork release tag, empty for the first one
#   REPOSITORY            owner/name of this repository
#   IMAGE                 image name without tag
#   DIGEST                manifest list digest
#   PLATFORMS             space separated platforms
#   DOCS_URL              link to FORK.md
#   MIGRATION_CHANGES     files under server/src/schema/migrations that differ from upstream BASE,
#                         one per line; empty when none; "unknown" when it could not be checked
#   UPSTREAM_REPOSITORY   default immich-app/immich
#   SERVER_URL            default https://github.com

set -euo pipefail

: "${TAG:?}" "${BASE:?}" "${UPSTREAM_BASE_COMMIT:?}" "${SOURCE_COMMIT:?}" "${REPOSITORY:?}"
: "${IMAGE:?}" "${DIGEST:?}" "${PLATFORMS:?}" "${DOCS_URL:?}"
PREVIOUS_TAG=${PREVIOUS_TAG:-}
MIGRATION_CHANGES=${MIGRATION_CHANGES:-}
UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-immich-app/immich}
SERVER_URL=${SERVER_URL:-https://github.com}

repository_url="${SERVER_URL}/${REPOSITORY}"
upstream_url="${SERVER_URL}/${UPSTREAM_REPOSITORY}"
platform_list=$(sed -E 's/[[:space:]]+/, /g' <<< "$PLATFORMS")

cat << EOF
**Unofficial fork build.** This is a release of the personal fork [${REPOSITORY}](${repository_url}), not a release of Immich. It is not affiliated with, endorsed by or supported by the Immich project or FUTO.

## Base

- Upstream release: [${BASE}](${upstream_url}/releases/tag/${BASE}) of ${UPSTREAM_REPOSITORY} (upstream), commit [\`${UPSTREAM_BASE_COMMIT::9}\`](${upstream_url}/commit/${UPSTREAM_BASE_COMMIT}). Upstream's release notes describe upstream's changes only.
- Fork changes on top of upstream ${BASE}: [${BASE}...${TAG}](${repository_url}/compare/${UPSTREAM_BASE_COMMIT}...${TAG})

## Source

- Commit: [\`${SOURCE_COMMIT::9}\`](${repository_url}/commit/${SOURCE_COMMIT})
EOF

if [[ -n "$PREVIOUS_TAG" ]]; then
  echo "- Changes since the previous fork release: [${PREVIOUS_TAG}...${TAG}](${repository_url}/compare/${PREVIOUS_TAG}...${TAG})"
else
  echo "- This is the first fork release of this line."
fi

cat << EOF

## Container image

\`\`\`
docker pull ${IMAGE}:${TAG}
\`\`\`

- Digest: \`${DIGEST}\`
- Platforms: ${platform_list}
- The image contains the server and the bundled web app. Use it in place of the server image in upstream's \`docker-compose.yml\` for ${BASE}; the machine-learning container stays upstream's image of ${BASE}.
- Check that this repository's workflow built and signed it:

  \`\`\`
  gh attestation verify oci://${IMAGE}:${TAG} -R ${REPOSITORY}
  \`\`\`

## Database

EOF

if [[ -z "${MIGRATION_CHANGES//[[:space:]]/}" ]]; then
  echo "A ${TAG%-fork.*}-fork.N build uses the same database schema as upstream ${BASE}, because the fork adds no database migration. Switching between upstream ${BASE} and this build runs no database migration. Back up your database before any upgrade."
elif [[ "$MIGRATION_CHANGES" == unknown ]]; then
  echo "Whether this build changes database migrations compared with upstream ${BASE} could not be checked. Back up your database before trying it."
else
  echo "This build changes database migrations compared with upstream ${BASE}:"
  echo
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      echo "- \`${file}\`"
    fi
  done <<< "$MIGRATION_CHANGES"
  echo
  echo "Its schema differs from upstream ${BASE}. Back up your database before trying it."
fi

cat << EOF

## License and warranty

Published under the GNU Affero General Public License v3 (AGPL-3.0), like upstream; upstream copyright notices are unchanged. There is no warranty and no support. See [FORK.md](${DOCS_URL}) for what differs from upstream and how to report problems to this fork, never to the upstream project.
EOF
