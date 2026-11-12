#!/usr/bin/env bash
# Runs the checks CI runs, with the same commands.
#
#   scripts/check.sh                    every lint check, then every test
#   scripts/check.sh lint [NAME...]     c, python, csharp, rust, node, scripts
#   scripts/check.sh test [NAME...]     c, csharp, python, node, rust, against build/'s library
#   scripts/check.sh library [--max-glibc X.Y]   what build/'s library exports and needs
#   scripts/check.sh tools              set up build/venv only (scripts/package.sh uses it)
#
# The Python tools (scripts/requirements.txt) go into a venv at build/venv. The
# other checks need dotnet, cargo, node and a C compiler on PATH.
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
}

test_python() {
    "$python" -m unittest discover -s bindings/python
}

test_node() {
    (cd bindings/node && npm ci --silent && npm test)
}

test_rust() {
    (cd bindings/rust && cargo test)
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

lints=(c python csharp rust node scripts)
tests=(c csharp python node rust)
command=${1:-all}
[ $# -gt 0 ] && shift
case "$command" in
    lint) [ $# -gt 0 ] || set -- "${lints[@]}"; run lint "$@" ;;
    test) [ $# -gt 0 ] || set -- "${tests[@]}"; run test "$@" ;;
    library) check_library "$@" ;;
    tools) tools ;;
    all) run lint "${lints[@]}"; run test "${tests[@]}" ;;
    *) sed -n '2,11p' "$0" >&2; exit 2 ;;
esac
