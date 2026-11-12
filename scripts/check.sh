#!/usr/bin/env bash
# Runs the checks CI runs, with the same commands.
#
#   scripts/check.sh                    every lint check, then every test
#   scripts/check.sh lint [NAME...]     c, python, csharp, rust, node, scripts, docs
#   scripts/check.sh test [NAME...]     c, csharp, python, node, rust, against build/'s library
#   scripts/check.sh library [--max-glibc X.Y]   what build/'s library exports and needs
#   scripts/check.sh tools              set up build/venv only (scripts/package.sh uses it)
#
# The Python tools (scripts/requirements.txt) go into a venv at build/venv, and the docs site's
# (scripts/requirements-docs.txt) into build/docs-venv. The other checks need dotnet, cargo, node
# and a C compiler on PATH.
set -euo pipefail

scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$scripts")
cd "$root"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        windows=true library=build/mozc_ffi.dll venv_bin=build/venv/Scripts python=${PYTHON:-python} ;;
    *)
        windows=false library=build/libmozc_ffi.so venv_bin=build/venv/bin python=${PYTHON:-python3} ;;
esac

# The pinned Python tools, installed again whenever requirements.txt changes.
tools() {
    if ! cmp -s "$scripts/requirements.txt" build/venv/requirements.txt; then
        "$python" -m venv build/venv
        "$venv_bin/python" -m pip install --quiet --disable-pip-version-check -r "$scripts/requirements.txt"
        cp "$scripts/requirements.txt" build/venv/requirements.txt
    fi
    PATH=$root/$venv_bin:$PATH
}

lint_c() {
    tools
    clang-format --style=Google --dry-run --Werror core/*.cc core/*.h tests/*.c
}

lint_python() {
    tools
    ruff check --config bindings/python/pyproject.toml bindings/python scripts
    ruff format --check --config bindings/python/pyproject.toml bindings/python scripts
}

lint_csharp() {
    dotnet format bindings/csharp/MozcFfi.csproj --verify-no-changes
    dotnet format bindings/csharp/tests/MozcFfi.Tests.csproj --verify-no-changes
    dotnet build bindings/csharp/tests --nologo --verbosity quiet -warnaserror
}

lint_rust() {
    (cd bindings/rust && cargo fmt --check && cargo clippy --all-targets --quiet -- -D warnings)
}

lint_node() {
    (cd bindings/node && npm ci --silent && npx eslint . &&
        npx tsc --noEmit --strict --lib es2022,esnext.disposable index.d.ts)
}

lint_scripts() {
    tools
    shellcheck scripts/*.sh
    actionlint
}

# Builds the docs site into build/site. --strict fails on any warning, such as a broken link or a
# README section a page includes that isn't there.
lint_docs() {
    local docs_bin=build/docs-venv/${venv_bin##*/}
    if ! cmp -s "$scripts/requirements-docs.txt" build/docs-venv/requirements.txt; then
        "$python" -m venv build/docs-venv
        "$docs_bin/python" -m pip install --quiet --disable-pip-version-check -r "$scripts/requirements-docs.txt"
        cp "$scripts/requirements-docs.txt" build/docs-venv/requirements.txt
    fi
    NO_MKDOCS_2_WARNING=1 "$docs_bin/mkdocs" build --strict --site-dir build/site
}

test_c() {
    mkdir -p build/smoke-profile
    if $windows; then
        # clang from PATH (as on GitHub's runners), else the LLVM that Mozc's Windows build fetched.
        local clang=clang
        command -v clang > /dev/null || clang=build/mozc/src/third_party/llvm/bin/clang.exe
        "$clang" -std=c99 -Wall -Wextra -Werror -Icore tests/smoke.c build/mozc_ffi.lib -o build/smoke.exe
        build/smoke.exe build/smoke-profile
    else
        "${CC:-cc}" -std=c99 -Wall -Wextra -Werror -pedantic -Icore tests/smoke.c -Lbuild -lmozc_ffi -o build/smoke
        LD_LIBRARY_PATH=build build/smoke build/smoke-profile
    fi
}

test_csharp() {
    dotnet run --project bindings/csharp/tests
    readme_csharp
}

# Runs the C# example in each of bindings/csharp's READMEs as a program, with a new profile and
# build/'s library. A Console.WriteLine with a comment after it must print exactly that comment.
readme_csharp() {
    local dir=build/readme-csharp readme
    mkdir -p "$dir"
    cat > "$dir/Readme.csproj" << EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <RollForward>Major</RollForward>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../bindings/csharp/MozcFfi.csproj" />
    <None Include="../$(basename "$library")" CopyToOutputDirectory="PreserveNewest" />
  </ItemGroup>
</Project>
EOF
    # Windows consoles default to a code page that can't print Japanese.
    cat > "$dir/Utf8.cs" << 'EOF'
static class Utf8
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Set() => System.Console.OutputEncoding = new System.Text.UTF8Encoding(false);
}
EOF
    for readme in bindings/csharp/README.md bindings/csharp/README.ja.md; do
        echo "-- $readme"
        # shellcheck disable=SC2016 # the backticks are Markdown's code fence, not a command
        sed -n '/^```csharp$/,/^```$/p' "$readme" | sed '1d;$d' |
            sed 's#"/path/to/profile"#System.IO.Path.GetFullPath("build/readme-csharp/profile")#' > "$dir/Program.cs"
        rm -rf "$dir/profile"
        dotnet build "$dir/Readme.csproj" --nologo --verbosity quiet -o "$dir/out" > /dev/null
        diff <(sed -n 's#^.*Console\.WriteLine(.*); *// \(.*\)$#\1#p' "$dir/Program.cs") \
            <(dotnet "$dir/out/Readme.dll" | tr -d '\r')
    done
    echo "the READMEs' examples print what they say"
}

test_python() {
    "$python" -m unittest discover -s bindings/python
}

test_node() {
    (cd bindings/node && npm ci --silent && npm test)
}

test_rust() {
    # The doc tests (the READMEs' examples) open Mozc with the default library.
    (cd bindings/rust && MOZC_FFI_LIBRARY=${MOZC_FFI_LIBRARY:-../../$library} cargo test)
    readme_rust
}

# Runs the Rust example in each of bindings/rust's READMEs as a program with build/'s library. A
# println! with a comment after it must print exactly that comment.
readme_rust() {
    local dir=build/readme-rust readme
    mkdir -p "$dir/src"
    cat > "$dir/Cargo.toml" << 'EOF'
[package]
name = "readme"
version = "0.0.0"
edition = "2021"
publish = false

[dependencies]
mozc-ffi = { path = "../../bindings/rust" }

[workspace]
EOF
    for readme in bindings/rust/README.md bindings/rust/README.ja.md; do
        echo "-- $readme"
        # shellcheck disable=SC2016 # the backticks are Markdown's code fence, not a command
        sed -n '/^```rust$/,/^```$/p' "$readme" | sed '1d;$d' > "$dir/src/main.rs"
        diff <(sed -n 's#^.*println!(.*); *// \(.*\)$#\1#p' "$dir/src/main.rs") \
            <(MOZC_FFI_LIBRARY=${MOZC_FFI_LIBRARY:-$library} cargo run --quiet --manifest-path "$dir/Cargo.toml" | tr -d '\r')
    done
    echo "the READMEs' examples print what they say"
}

check_library() {
    tools
    python scripts/check_library.py "$library" "$@"
}

run() {  # run <lint|test> <name...>: each name's function, one after another
    local kind=$1 name
    shift
    for name in "$@"; do
        echo "== $kind $name"
        "${kind}_${name}"
    done
}

lints=(c python csharp rust node scripts docs)
tests=(c csharp python node rust)
command=${1:-all}
[ $# -gt 0 ] && shift
case "$command" in
    lint) [ $# -gt 0 ] || set -- "${lints[@]}"; run lint "$@" ;;
    test) [ $# -gt 0 ] || set -- "${tests[@]}"; run test "$@" ;;
    library) check_library "$@" ;;
    tools) tools ;;
    all) run lint "${lints[@]}"; run test "${tests[@]}" ;;
    *) sed -n '2,12p' "$0" >&2; exit 2 ;;
esac
