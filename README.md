# mozc-ffi

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)

Unofficial C API and bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese
kana-kanji converter. Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no
install. Not affiliated with Google.

Every call is self-contained. You pass a reading and, optionally, segment lengths and the text before it, and get
back segments with candidates. Picks you `learn` rank first next time.

| | |
|---|---|
| `core/` | The C API (`mozc_ffi.h`) and its implementation over Mozc's converter |
| `bindings/python/` | Python bindings (ctypes, one module) and tests |
| `bindings/csharp/` | C# bindings (netstandard2.0, works in Unity) and tests |
| `bindings/unity/` | The Unity package's own files (`package.json` and `.meta` files); `scripts/package.sh` adds the C# bindings and the library |
| `bindings/rust/` | Rust bindings (the `mozc-ffi` crate) and tests |
| `bindings/node/` | Node.js bindings (koffi, with TypeScript types) and tests |
| `scripts/` | The build scripts, `check.sh` (every lint check and test), the pinned Mozc commit (`MOZC_COMMIT`) |
| `tests/` | `chat.tsv`, everyday chat sentences used by every test suite, and `smoke.c`, a C program using the API |

## Install

Each package comes with the library already built, for Linux x64 and arm64 (glibc 2.28 or later) and Windows x64.

| | Install | Needs |
|---|---|---|
| Python | `pip install mozc-ffi` | Python 3.11+ |
| C# | `dotnet add package MozcFfi` | .NET Standard 2.0 |
| Unity | The `com.malorn44.mozc-ffi` package (below) | Unity 2021.3+, Windows or Linux x64 |
| Node.js | `npm install mozc-ffi` | Node.js 22+ |
| Rust | `cargo add mozc-ffi --features download` | Rust 1.88+ |
| C | An archive from [Releases](https://github.com/Malorn44/mozc-ffi/releases) | |

The Rust crate holds only the bindings, because the library is larger than crates.io allows. Its `download` feature
fetches the library from this version's release when building, and checks its SHA-256 (it needs `curl` and `tar`):

```sh
cargo add mozc-ffi --features download
```

To ship your program, copy the library (`mozc_ffi::DOWNLOADED_LIBRARY`) next to your executable. Without the feature,
download the archive for your platform from [Releases](https://github.com/Malorn44/mozc-ffi/releases) and either put
`libmozc_ffi.so` or `mozc_ffi.dll` next to your executable, or set `MOZC_FFI_LIBRARY` to its path.

For Unity, add npm as a scoped registry and the package to your project's `Packages/manifest.json`, next to what is
already there. The package holds the C# bindings and the library, and later versions show up in the Package Manager:

```json
{
  "scopedRegistries": [
    { "name": "npm", "url": "https://registry.npmjs.org", "scopes": ["com.malorn44"] }
  ],
  "dependencies": {
    "com.malorn44.mozc-ffi": "0.2.0"
  }
}
```

The archives hold the header, the library and, on Windows, the import library. `SHA256SUMS` lists their checksums.

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

## Use

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    mozc.convert("ここではきものをぬぐ", [3, 5, 2])  # [Segment("ここで", [...]), Segment("はきものを", ["履物を", ...]), ...]
    mozc.predict("ありがと")                     # ["ありがとう", ...]
    mozc.learn("かんじ", [3], ["感じ"])           # 感じ ranks first next time
```

```csharp
using var mozc = new MozcFfi.Mozc(profileDir);
var segments = mozc.Convert("きょうはさむいですね");   // segments[0].Candidates[0] == "今日は"
mozc.Learn("かんじ", new[] { 3 }, new[] { "感じ" });
```

```rust
let mozc = mozc_ffi::Mozc::open(Some(Path::new("/path/to/profile")), false)?;
let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], "");
mozc.learn("かんじ", &[3], &["感じ"], "");
```

```js
const { Mozc } = require('mozc-ffi');
const mozc = new Mozc('/path/to/profile');
mozc.convert('ここではきものをぬぐ', [3, 5, 2]);
mozc.learn('かんじ', [3], ['感じ']);
mozc.close();
```

Each binding loads the library when it opens Mozc: from `MOZC_FFI_LIBRARY`, next to the program (or package), or the
system's library path. It stays loaded until the process exits.

A call that can't do what was asked returns nothing (an empty list, or false); `last_error` then says why, in English,
without ever quoting what was typed.

Segment lengths count Unicode characters. Mozc keeps the profile directory per process, so open one profile per
process. `incognito` learns nothing.

## Test

```sh
scripts/check.sh              # every lint check, then every test
scripts/check.sh lint python  # one lint check: c, python, csharp, rust, node, scripts
scripts/check.sh test rust    # one binding's tests: c, csharp, python, node, rust
```

The tests use the library in `build/`. CI runs the same commands on Linux and Windows for every pull request.

## Releases

Releases are made by release-please from conventional-commit PR titles; [.github/RELEASING.md](.github/RELEASING.md) has the steps.

## Licence

BSD-3-Clause. The built library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
