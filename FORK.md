# About this fork

This repository is an unofficial, personal fork of [immich-app/immich](https://github.com/immich-app/immich). It is not affiliated with, endorsed by or supported by the Immich project or its maintainers. For the official project, use the upstream repository and its documentation.

The fork is published under the same license as upstream, the GNU Affero General Public License v3 (see [LICENSE](LICENSE)). All upstream copyright notices are unchanged. The source for every published image or app build is this repository, at the commit named in the image tag.

There is no warranty and no support. Use it at your own risk, and back up your data first.

## What is different from upstream

Changes begin on 14 November 2026.

- **Move to album.** Select assets in an album and move them to another existing or new album in one step. The server adds the assets to the target album and removes them from the source album in a single database transaction, so a failed request moves nothing. The endpoint is `PUT /albums/{id}/assets/move`. It is available in the web app and the mobile app. The feature adds no database migration.
- **Fork automation** in `.github/workflows/fork-*.yml`: image builds, a scheduled merge of upstream, and regression and mutation tests that check Move to album after every merge.
- **Carried upstream pull requests** that are approved but not yet merged upstream are listed in [.github/fork/upstream-prs.md](.github/fork/upstream-prs.md). Each is dropped once upstream merges it.

Everything else is upstream code. The fork merges upstream regularly, and conflicts are tracked as issues in this repository.

## Container image

```
ghcr.io/allamiro/immich-server-allamiro
```

The image contains the server and the bundled web app. The machine-learning container is the unmodified upstream image.

| Tag | Meaning |
| --- | --- |
| `vX.Y.Z-fork.N` | A build of upstream release `vX.Y.Z` plus this fork's changes. |
| `latest` | The newest `vX.Y.Z-fork.N` build. |
| `edge`, `main` | The newest build of this fork's default branch, which follows upstream development. Its version label can be ahead of or behind the latest release, and it can carry database migrations that the latest release does not. |
| `<short commit>` | The exact commit the image was built from. |

A `vX.Y.Z-fork.N` build uses the same database schema as upstream release `vX.Y.Z`, because the fork adds no migration. An `edge` build follows upstream development, whose migrations only move forward. Use a separate test instance or back up your database before trying it.

To use it, replace the server image in the upstream `docker-compose.yml` and leave everything else as it is:

```yaml
immich-server:
  image: ghcr.io/allamiro/immich-server-allamiro:latest
```

To build the image yourself from a checkout, run from the repository root:

```bash
docker build -f server/Dockerfile -t immich-server-allamiro .
```

## Mobile apps

No official or signed mobile builds are published from this fork. Build the app from source following the upstream mobile documentation. Builds from this repository use the upstream application identifiers unless you change them, so do not install one over the official app.

## Reporting problems

Open an issue in this repository: <https://github.com/allamiro/immich/issues>. Do not report problems with this fork to the upstream project.
