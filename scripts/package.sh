#!/usr/bin/env bash
# Packs the release archives from built libraries.
#
#   scripts/package.sh VERSION LINUX_DIR WINDOWS_DIR OUT_DIR
#
# LINUX_DIR holds libmozc_ffi.so, WINDOWS_DIR mozc_ffi.dll and mozc_ffi.lib. OUT_DIR gets
#   mozc-ffi-VERSION-linux-x64.tar.gz    include/mozc_ffi.h, lib/libmozc_ffi.so
#   mozc-ffi-VERSION-windows-x64.zip     include/mozc_ffi.h, bin/mozc_ffi.dll, lib/mozc_ffi.lib
#   SHA256SUMS
# each archive with LICENSE and THIRD_PARTY_NOTICES.md. Every file gets the commit's time, so the
# same libraries pack to the same bytes.
set -euo pipefail

if [ $# -ne 4 ]; then
    sed -n '2,10p' "$0" >&2
    exit 2
fi
version=$1 linux=$2 windows=$3 out=$4
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
epoch=$(git -C "$root" log -1 --format=%ct)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$out"
out=$(cd -- "$out" && pwd)

# stage NAME: the files every archive holds, in $stage/NAME
stage() {
    mkdir -p "$stage/$1/include"
    cp "$root/core/mozc_ffi.h" "$stage/$1/include/"
    cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$stage/$1/"
}

linux_name=mozc-ffi-$version-linux-x64
stage "$linux_name"
mkdir -p "$stage/$linux_name/lib"
cp "$linux/libmozc_ffi.so" "$stage/$linux_name/lib/"

windows_name=mozc-ffi-$version-windows-x64
stage "$windows_name"
mkdir -p "$stage/$windows_name/bin" "$stage/$windows_name/lib"
cp "$windows/mozc_ffi.dll" "$stage/$windows_name/bin/"
cp "$windows/mozc_ffi.lib" "$stage/$windows_name/lib/"

find "$stage" -exec touch -h -d "@$epoch" {} +
chmod -R u=rwX,go=rX "$stage"
cd "$stage"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$epoch" -cf - "$linux_name" |
    gzip -9 -n > "$out/$linux_name.tar.gz"
find "$windows_name" -print | LC_ALL=C sort | zip -X -9 -q "$out/$windows_name.zip" -@

cd "$out"
sha256sum "$linux_name.tar.gz" "$windows_name.zip" > SHA256SUMS
cat SHA256SUMS
