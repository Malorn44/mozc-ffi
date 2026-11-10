#!/usr/bin/env bash
# Packs a release from built libraries: the archives for the GitHub Release, and the packages for
# PyPI, NuGet and npm.
#
#   scripts/package.sh VERSION LINUX_DIR WINDOWS_DIR OUT_DIR
#
# LINUX_DIR holds libmozc_ffi.so, WINDOWS_DIR mozc_ffi.dll and mozc_ffi.lib. OUT_DIR gets
#   mozc-ffi-VERSION-linux-x64.tar.gz    include/mozc_ffi.h, lib/libmozc_ffi.so
#   mozc-ffi-VERSION-windows-x64.zip     include/mozc_ffi.h, bin/mozc_ffi.dll, lib/mozc_ffi.lib
#   SHA256SUMS                           of the two archives
#   python/  a wheel per platform, the library inside
#   nuget/   MozcFfi, with both platforms' libraries
#   npm/     mozc-ffi, @mozc-ffi/linux-x64, @mozc-ffi/win32-x64, and the Unity package
#            com.malorn44.mozc-ffi (Unity reads npm as a scoped registry)
# Each one also holds LICENSE and THIRD_PARTY_NOTICES.md. VERSION must be the version in every
# package file (release-please keeps them equal). Needs python3, dotnet and npm.
set -euo pipefail

if [ $# -ne 4 ]; then
    sed -n '2,16p' "$0" >&2
    exit 2
fi
version=$1 linux=$(cd -- "$2" && pwd) windows=$(cd -- "$3" && pwd) out=$4
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
epoch=$(git -C "$root" log -1 --format=%ct)
export SOURCE_DATE_EPOCH=$epoch
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$out"
out=$(cd -- "$out" && pwd)
notices=("$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md")

# Every package file says the same version.
declare -A versions=(
    [bindings/python/pyproject.toml]=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/bindings/python/pyproject.toml")
    [bindings/rust/Cargo.toml]=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/bindings/rust/Cargo.toml")
    [bindings/node/package.json]=$(node -p "require('$root/bindings/node/package.json').version")
    [bindings/unity/package.json]=$(node -p "require('$root/bindings/unity/package.json').version")
    [bindings/csharp/MozcFfi.csproj]=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$root/bindings/csharp/MozcFfi.csproj")
)
for file in "${!versions[@]}"; do
    if [ "${versions[$file]}" != "$version" ]; then
        echo "$file says ${versions[$file]}, not $version" >&2
        exit 1
    fi
done

# --- Archives -------------------------------------------------------------------------------------

archive_stage() {  # archive_stage NAME: the header and notices, in $stage/NAME
    mkdir -p "$stage/$1/include"
    cp "$root/core/mozc_ffi.h" "$stage/$1/include/"
    cp "${notices[@]}" "$stage/$1/"
}

linux_name=mozc-ffi-$version-linux-x64
archive_stage "$linux_name"
mkdir -p "$stage/$linux_name/lib"
cp "$linux/libmozc_ffi.so" "$stage/$linux_name/lib/"

windows_name=mozc-ffi-$version-windows-x64
archive_stage "$windows_name"
mkdir -p "$stage/$windows_name/bin" "$stage/$windows_name/lib"
cp "$windows/mozc_ffi.dll" "$stage/$windows_name/bin/"
cp "$windows/mozc_ffi.lib" "$stage/$windows_name/lib/"

find "$stage" -exec touch -h -d "@$epoch" {} +
chmod -R u=rwX,go=rX "$stage"
(
    cd "$stage"
    tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$epoch" -cf - "$linux_name" |
        gzip -9 -n > "$out/$linux_name.tar.gz"
    find "$windows_name" -print | LC_ALL=C sort | zip -X -9 -q "$out/$windows_name.zip" -@
)
(cd "$out" && sha256sum "$linux_name.tar.gz" "$windows_name.zip" > SHA256SUMS)

# --- PyPI: a wheel per platform -------------------------------------------------------------------

"$root/scripts/check.sh" tools
python=$root/build/venv/bin/python
mkdir -p "$out/python"
for platform in "manylinux_2_28_x86_64 $linux/libmozc_ffi.so" "win_amd64 $windows/mozc_ffi.dll"; do
    read -r tag library <<< "$platform"
    dir=$stage/python-$tag
    mkdir -p "$dir"
    cp -r "$root/bindings/python/pyproject.toml" "$root/bindings/python/mozc_ffi" "$dir/"
    rm -rf "$dir/mozc_ffi/__pycache__"
    cp "$library" "$root/THIRD_PARTY_NOTICES.md" "$dir/mozc_ffi/"
    cp "$root/LICENSE" "$root/README.md" "$dir/"
    sed -i 's/^license = "BSD-3-Clause"$/&\nreadme = "README.md"/' "$dir/pyproject.toml"
    "$python" -m build --wheel --outdir "$dir/dist" "$dir" > /dev/null
    # The library makes it platform-specific; ctypes keeps it independent of the Python version.
    "$python" -m wheel tags --remove --platform-tag "$tag" "$dir"/dist/*.whl > /dev/null
    mv "$dir"/dist/*.whl "$out/python/"
done

# --- NuGet: one package, a library per runtime ----------------------------------------------------

dir=$stage/nuget
mkdir -p "$dir/runtimes/linux-x64/native" "$dir/runtimes/win-x64/native"
cp "$root/bindings/csharp/MozcFfi.cs" "$root/bindings/csharp/MozcFfi.csproj" "$dir/"
cp "$root/README.md" "$root/THIRD_PARTY_NOTICES.md" "$dir/"
cp "$linux/libmozc_ffi.so" "$dir/runtimes/linux-x64/native/"
cp "$windows/mozc_ffi.dll" "$dir/runtimes/win-x64/native/"
dotnet pack "$dir/MozcFfi.csproj" --configuration Release --output "$out/nuget" --nologo --verbosity quiet \
    -p:ContinuousIntegrationBuild=true

# --- npm: the bindings, and a package per platform with its library -------------------------------

mkdir -p "$out/npm"
dir=$stage/npm/mozc-ffi
mkdir -p "$dir"
cp "$root/bindings/node/package.json" "$root/bindings/node/index.js" "$root/bindings/node/index.d.ts" "$dir/"
cp "${notices[@]}" "$root/README.md" "$dir/"
node -e '
const fs = require("fs"); const [file, version] = process.argv.slice(1);
const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
pkg.files.push("THIRD_PARTY_NOTICES.md");
// npm installs only the one matching the machine, by its os and cpu fields.
pkg.optionalDependencies = { "@mozc-ffi/linux-x64": version, "@mozc-ffi/win32-x64": version };
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");' "$dir/package.json" "$version"
npm pack --silent --pack-destination "$out/npm" "$dir" > /dev/null

for platform in "linux x64 $linux/libmozc_ffi.so" "win32 x64 $windows/mozc_ffi.dll"; do
    read -r os cpu library <<< "$platform"
    dir=$stage/npm/$os-$cpu
    mkdir -p "$dir"
    cp "$library" "${notices[@]}" "$dir/"
    # shellcheck disable=SC2016 # ${os} and the like are JavaScript template strings, for node
    node -e '
const fs = require("fs"); const [dir, version, os, cpu, library] = process.argv.slice(1);
fs.writeFileSync(dir + "/package.json", JSON.stringify({
  name: `@mozc-ffi/${os}-${cpu}`,
  version,
  description: `The native library of mozc-ffi for ${os}-${cpu}`,
  license: "BSD-3-Clause",
  repository: { type: "git", url: "git+https://github.com/Malorn44/mozc-ffi.git" },
  os: [os],
  cpu: [cpu],
  files: [library, "THIRD_PARTY_NOTICES.md"],
}, null, 2) + "\n");' "$dir" "$version" "$os" "$cpu" "$(basename "$library")"
    npm pack --silent --pack-destination "$out/npm" "$dir" > /dev/null
done

# --- Unity: the C# bindings and both libraries, as a Unity package on npm --------------------------

# bindings/unity holds the package's own files and a .meta for every file in it, the ones added
# here included: Unity can't write them into an installed package, and they hold the plugins'
# platform settings.
dir=$stage/unity
cp -r "$root/bindings/unity" "$dir"
cp "$root/bindings/csharp/MozcFfi.cs" "$dir/Runtime/"
cp "$root/README.md" "$root/THIRD_PARTY_NOTICES.md" "$dir/"
cp "$root/LICENSE" "$dir/LICENSE.md"
cp "$linux/libmozc_ffi.so" "$windows/mozc_ffi.dll" "$dir/Runtime/Plugins/x86_64/"
missing=$(cd "$dir" && find . -mindepth 1 ! -name '*.meta' ! -exec test -e '{}.meta' ';' -print)
if [ -n "$missing" ]; then
    echo "the Unity package has no .meta for: $missing" >&2
    exit 1
fi
npm pack --silent --pack-destination "$out/npm" "$dir" > /dev/null

(cd "$out" && find . -type f | LC_ALL=C sort)
