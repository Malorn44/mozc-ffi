# mozc-ffi

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)

Unofficial C API and bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese
kana-kanji converter. Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no
install. Not affiliated with Google.

Every call is self-contained. You pass a reading and, optionally, segment lengths and the text before it, and get
back segments with candidates. Picks you `learn` rank first next time.

## Languages

Each package comes with the library already built, for Linux x64 and arm64 (glibc 2.28 or later) and Windows x64.
Each language's README covers installing it, an example and how it finds the library.

| | Install | Needs | |
|---|---|---|---|
| Python | `pip install mozc-ffi` | Python 3.11+ | [README](bindings/python/README.md) |
| C# | `dotnet add package MozcFfi` | .NET Standard 2.0 | [README](bindings/csharp/README.md) |
| Unity | The `com.malorn44.mozc-ffi` package on npm | Unity 2021.3+, Windows or Linux x64 | [README](bindings/unity/README.md) |
| Node.js | `npm install mozc-ffi` | Node.js 22+ | [README](bindings/node/README.md) |
| Rust | `cargo add mozc-ffi --features download` | Rust 1.88+ | [README](bindings/rust/README.md) |
| C | An archive from [Releases](https://github.com/Malorn44/mozc-ffi/releases) | | [below](#c) |

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね
```

A call that can't do what was asked returns nothing (an empty list, or false); `last_error` then says why, in
English, without ever quoting what was typed. Segment lengths count Unicode characters. Mozc keeps the profile
directory per process, so open one profile per process. `incognito` learns nothing.

## C

The archives hold the header, the library and, on Windows, the import library. `SHA256SUMS` lists their checksums.
[`mozc_ffi.h`](core/mozc_ffi.h) documents every function.

```c
#include <stdio.h>

#include "mozc_ffi.h"

int main(void) {
  mozc_ffi* mozc = mozc_ffi_open("/path/to/profile", 0);
  if (mozc == NULL) {
    fprintf(stderr, "%s\n", mozc_ffi_last_error());
    return 1;
  }
  mozc_ffi_result* result = mozc_ffi_convert(mozc, "きょうはさむいですね", NULL, 0, NULL);
  for (int32_t s = 0; s < mozc_ffi_segment_count(result); s++) {
    fputs(mozc_ffi_candidate(result, s, 0), stdout);  // 今日は寒いですね
  }
  putchar('\n');
  mozc_ffi_result_free(result);
  mozc_ffi_close(mozc);
  return 0;
}
```

```sh
cc -std=c99 -Iinclude example.c -Llib -lmozc_ffi -o example
LD_LIBRARY_PATH=lib ./example
```

Strings are UTF-8. A result's strings stay valid until `mozc_ffi_result_free`. One handle may be used from several
threads; calls on it are serialized.

## Repository

| | |
|---|---|
| `core/` | The C API (`mozc_ffi.h`) and its implementation over Mozc's converter |
| `bindings/python/` | Python bindings (ctypes, one module), their README and tests |
| `bindings/csharp/` | C# bindings (netstandard2.0, works in Unity), their README and tests |
| `bindings/unity/` | The Unity package's own files (`package.json`, the README and `.meta` files); `scripts/package.sh` adds the C# bindings and the library |
| `bindings/rust/` | Rust bindings (the `mozc-ffi` crate), their README and tests |
| `bindings/node/` | Node.js bindings (koffi, with TypeScript types), their README and tests |
| `scripts/` | The build scripts, `check.sh` (every lint check and test), the pinned Mozc commit (`MOZC_COMMIT`) |
| `tests/` | `chat.tsv`, everyday chat sentences used by every test suite, and `smoke.c`, a C program using the API |

Each package's README is the one in its `bindings/` directory, and is what PyPI, NuGet, npm and crates.io show.

## Build

To build the library yourself instead: both scripts fetch Mozc at the commit in `scripts/MOZC_COMMIT` into `build/mozc` and build `core/` inside its source
tree. The first build downloads Mozc's dependencies and takes a while. Everything built lands in `build/`, so deleting
it is a full clean.

Linux needs [Bazelisk](https://github.com/bazelbuild/bazelisk), Git and GCC:

```sh
scripts/build.sh            # → build/libmozc_ffi.so
```

Windows needs Bazelisk, Git, Python 3.12+, Visual Studio 2022 or 2026 with the C++ tools and C++ ATL, and Developer
Mode. Build from a clone on a Windows drive (not `\\wsl.localhost`):

```powershell
.\scripts\build.ps1         # → build\mozc_ffi.dll
```

The DLL links the C++ runtime statically, so it needs no Visual C++ Redistributable.

## Test

```sh
scripts/check.sh              # every lint check, then every test
scripts/check.sh lint python  # one lint check: c, python, csharp, rust, node, scripts
scripts/check.sh test rust    # one binding's tests: c, csharp, python, node, rust
```

The tests use the library in `build/`. Each binding's tests also run the examples in its READMEs and check they
print what their comments say (Rust's are compiled, not run). CI runs the same commands on Linux and Windows for
every pull request.

## Releases

Releases are made by release-please from conventional-commit PR titles; [.github/RELEASING.md](.github/RELEASING.md) has the steps.

## Licence

BSD-3-Clause. The built library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
