# Releasing

A release is two clicks: merge release-please's release PR, then approve the `release` deployment.
CI builds, packs and publishes everything else.

## How a release happens

1. Every push to `main` runs CI (`.github/workflows/ci.yml`). Once `ci ok` passes, the `release` job
   runs [release-please](https://github.com/googleapis/release-please). It keeps a PR open titled
   `chore(main): release X.Y.Z`, with the changelog since the last release and the new version in
   every package file (`.github/release-please/config.json` lists them).
2. Merging that PR runs CI again. This time `release` tags `vX.Y.Z` on the merged commit and drafts a
   GitHub Release with the changelog.
3. `release-build-linux` and `release-build-windows` build that commit with the same steps as CI
   (`.github/actions/`), usually straight from cache.
4. `release-assets` packs everything (`scripts/package.sh`), records build provenance for all of it,
   and attaches the archives to the draft:
   - `mozc-ffi-X.Y.Z-linux-x64.tar.gz` and `-linux-arm64.tar.gz`: `include/mozc_ffi.h`, `lib/libmozc_ffi.so`
   - `mozc-ffi-X.Y.Z-windows-x64.zip`: `include/mozc_ffi.h`, `bin/mozc_ffi.dll`, `lib/mozc_ffi.lib`
   - `SHA256SUMS`

   It also packs a wheel per platform, the NuGet package, and the npm packages (`mozc-ffi` and one per
   platform). Every archive and package holds `LICENSE` and `THIRD_PARTY_NOTICES.md`.
5. The publish jobs wait in the `release` environment. Approve them: in the run, **Review
   deployments**, tick `release`, **Approve and deploy**. They publish to PyPI, NuGet, npm and
   crates.io through trusted publishing, so no token is stored anywhere.
6. Once every registry has the release, `release-publish` makes the draft public.

Versions follow [semantic versioning](https://semver.org/) from the conventional-commit PR titles:
while the version is 0.x, a `feat` or a breaking change (`feat!:`) bumps the minor version and a `fix`
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
- The `release` environment (deployment branches: `main`; required reviewer: Malorn44) holds the
  variable `NUGET_USER`, the nuget.org username.
- Each registry trusts owner `Malorn44`, repository `mozc-ffi`, workflow `ci.yml`, environment
  `release`:
  - PyPI: a (pending) trusted publisher for `mozc-ffi`.
  - NuGet: a trusted publishing policy for the account.
  - npm: a trusted publisher on each of `mozc-ffi`, `@mozc-ffi/linux-x64`, `@mozc-ffi/linux-arm64` and
    `@mozc-ffi/win32-x64` (owned by the `mozc-ffi` organisation).
  - crates.io: a trusted publisher on the `mozc-ffi` crate.
- The `releases` ruleset keeps `v*` tags from being moved or deleted.

### A package's first version on npm or crates.io

npm and crates.io can only trust a workflow for a package that already exists, so a new package's
first version goes up by hand. Their publish jobs run only while the repository variables
`NPM_TRUSTED` and `CRATES_TRUSTED` are `true`.

When a release adds an npm package (a new platform, say), reserve its name with a placeholder, so
the release's own publish is the first through the trusted publisher. npm asks for a new trusted
publisher to be used within two days, so do this shortly before merging the release PR:

1. Publish an empty `0.0.0` under the new name:
   ```sh
   npm login
   dir=$(mktemp -d)
   printf '{"name":"%s","version":"0.0.0","description":"Placeholder; the first real version follows.","license":"BSD-3-Clause"}\n' \
     "<new package name>" > "$dir/package.json"
   npm publish "$dir" --access public
   ```
2. On npmjs.com, add the trusted publisher to the new package (allow publish only) and set its
   publishing access to "Require two-factor authentication and disallow tokens".
3. Merge the release PR and approve the deployment. `publish-npm` publishes the release's version
   of every package, the new one included.
4. Remove the placeholder (npm allows this for 72 hours), so it isn't offered as a version:
   ```sh
   npm unpublish "<new package name>@0.0.0"
   ```

For crates.io, the first version of the crate was published the same way: `cargo publish` from the
tag's `bindings/rust`, with a short-lived token, and then the trusted publisher added.

## When it goes wrong

- **`release` skipped with "main has moved on".** Another PR merged before this run's release job.
  The newer commit's run does the release instead.
- **"release-please tagged … which is not on main".** The tag points somewhere unexpected; nothing
  was built. Look at the tag and the draft release before doing anything else.
- **A build, `release-assets` or a publish job failed.** Fix the cause on a branch if needed, then use
  "Re-run failed jobs" on the run. The tag and draft stay as they are, and each publish job skips a
  version its registry already has.
