# Upstream pull requests carried by this fork

These pull requests from `immich-app/immich` are approved upstream but not yet merged there. Each one is merged into this fork as a real merge commit of the pull request head (`refs/pull/<number>/head`), so the original commits and authors are kept. When upstream later merges the same change, git sees identical content and the scheduled upstream merge stays clean.

| PR | Title | Head SHA merged | Merged into fork |
| --- | --- | --- | --- |
| [#33239](https://github.com/immich-app/immich/pull/33239) | fix: integrity report downloads | `22c91d9fd8043fbd932074ce2913c139f8c6b0fb` | 2026-11-14 |
| [#33190](https://github.com/immich-app/immich/pull/33190) | fix(web): remove accidental raw json tooltip on large file cards | `a517f064c39ac4f4f4fc2fb88ab7ccb4c8358c08` | 2026-11-14 |
| [#33142](https://github.com/immich-app/immich/pull/33142) | chore: update flutter timezone dep | `71f7acac62def08206be9b05995af04b36638eab` | 2026-11-14 |
| [#33213](https://github.com/immich-app/immich/pull/33213) | feat: workflow tag filter children matching | `4f2c17902e5800edccd23510a519d17ef0306ea0` | 2026-11-14 |

## Adding a pull request

```sh
git fetch upstream pull/<number>/head:refs/remotes/upstream-pr/<number>
git merge --no-ff upstream-pr/<number> -m "merge: upstream PR #<number> <title>"
```

Add a row with the head SHA that was merged.

## Dropping an entry

Once upstream has merged a pull request into its `main` and that upstream commit has been merged into this fork, remove the row. If upstream merged a later version of the pull request (new commits after the SHA listed here), check the upstream merge for conflicts with the carried version before removing the row.

If upstream closes a pull request without merging it, decide whether to keep the change. To remove it from the fork, revert its merge commit with `git revert -m 1 <merge commit>` and remove the row.
