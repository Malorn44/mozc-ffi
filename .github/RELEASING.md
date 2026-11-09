# Releasing

A release is two steps: merge release-please's release PR, then publish the draft release it makes.

## How a release happens

1. Every push to `main` runs CI (`.github/workflows/ci.yml`). Once `ci ok` passes, the `release` job
   runs [release-please](https://github.com/googleapis/release-please). It keeps a PR open titled
   `chore(main): release X.Y.Z`, with the changelog since the last release and the new version in
   every package file (`.github/release-please/config.json` lists them).
2. Merging that PR runs CI again. This time `release` tags `vX.Y.Z` on the merged commit and drafts a
   GitHub Release with the changelog.
3. `release-build-linux` and `release-build-windows` build that commit with the same steps as CI
   (`.github/actions/`), usually straight from cache.
4. `release-assets` packs the archives (`scripts/package.sh`), records build provenance for them and
   attaches them to the draft:
   - `mozc-ffi-X.Y.Z-linux-x64.tar.gz`: `include/mozc_ffi.h`, `lib/libmozc_ffi.so`
   - `mozc-ffi-X.Y.Z-windows-x64.zip`: `include/mozc_ffi.h`, `bin/mozc_ffi.dll`, `lib/mozc_ffi.lib`
   - `SHA256SUMS`

   Each archive also holds `LICENSE` and `THIRD_PARTY_NOTICES.md`.
5. Check the draft (files attached, changelog right), then publish it on GitHub.

Versions follow [semantic versioning](https://semver.org/) from the conventional-commit PR titles:
while the version is 0.x, a breaking change (`feat!:`) bumps the minor version and a `feat` or `fix`
bumps the patch. `MOZC_FFI_ABI_VERSION` in `core/mozc_ffi.h` is separate: it changes only when the C
API does.

## Checking a release's files

```sh
gh release download vX.Y.Z -R Malorn44/mozc-ffi
sha256sum -c SHA256SUMS
gh attestation verify mozc-ffi-X.Y.Z-linux-x64.tar.gz -R Malorn44/mozc-ffi
```

## Setup

- `RELEASE_PLEASE_TOKEN`, a secret of the `release-please` environment (deployment branches: `main`):
  a fine-grained token for this repository with **Contents** and **Pull requests** read and write.
  release-please needs its own token because PRs opened with the Actions token start no CI. It
  expires after a year; renew it before then. Without it, `release` skips with a notice.
- The `releases` ruleset keeps `v*` tags from being moved or deleted.

## When it goes wrong

- **`release` skipped with "main has moved on".** Another PR merged before this run's release job.
  The newer commit's run does the release instead.
- **"release-please tagged … which is not on main".** The tag points somewhere unexpected; nothing
  was built. Look at the tag and the draft release before doing anything else.
- **A build or `release-assets` failed.** Fix the cause on a branch if needed, then use "Re-run failed
  jobs" on the run: the tag and draft stay as they are, and the files are attached again.
