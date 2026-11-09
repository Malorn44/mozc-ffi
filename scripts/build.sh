#!/usr/bin/env bash
# Builds build/libmozc_ffi.so from Mozc at the commit in scripts/MOZC_COMMIT.
#
#   scripts/build.sh      needs bazelisk on PATH, or BAZELISK=/path/to/bazelisk
#
# Mozc is fetched into build/mozc (not tracked), and core/ is linked
# into its source tree as //mozc_ffi. The first build downloads Mozc's
# dependencies and takes a while.
set -euo pipefail

scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$scripts")
commit=$(tr -d '[:space:]' < "$scripts/MOZC_COMMIT")
mozc=$root/build/mozc
bazelisk=${BAZELISK:-bazelisk}

if [ ! -d "$mozc/.git" ]; then
    git clone --filter=blob:none --no-checkout https://github.com/google/mozc "$mozc"
fi
if ! git -C "$mozc" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$mozc" fetch --filter=blob:none origin "$commit"
fi
# Always: the clone has no files yet even when its HEAD is already the commit.
git -C "$mozc" checkout --quiet "$commit"
ln -sfn "$root/core" "$mozc/src/mozc_ffi"

cd "$mozc/src"
# The C++ runtime (libstdc++, libgcc) is linked in, as build.ps1 does on Windows, so the library
# needs no particular libstdc++ on the machine that loads it. Bazel's own toolchain adds -lstdc++,
# which BAZEL_LINKLIBS (default -lstdc++:-lm) replaces with the static archive.
"$bazelisk" build --config release_build \
    --repo_env=BAZEL_LINKLIBS=-l%:libstdc++.a:-lm --linkopt=-static-libgcc \
    --downloader_config="$scripts/bazel_downloader.cfg" \
    //mozc_ffi:libmozc_ffi.so
mkdir -p "$root/build"
cp -f bazel-bin/mozc_ffi/libmozc_ffi.so "$root/build/"
echo "Built $root/build/libmozc_ffi.so"
