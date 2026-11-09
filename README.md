# mozc-ffi

Unofficial C API and bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese
kana-kanji converter. Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no
install. Not affiliated with Google.

Every call is self-contained. You pass a reading and, optionally, segment lengths and the text before it, and get
back segments with candidates. Picks you `learn` rank first next time.

| | |
|---|---|
| `core/` | The C API (`mozc_ffi.h`) and its implementation over Mozc's converter |
| `python/` | Python bindings (ctypes, one module) and tests |
| `csharp/` | C# bindings (netstandard2.0, works in Unity) and tests |
| `tests/chat.tsv` | Everyday chat sentences with accepted conversions, used by both test suites |

## Build

Needs [Bazelisk](https://github.com/bazelbuild/bazelisk), Git and GCC (Linux). Windows support is next.

```sh
./build.sh          # → build/libmozc_ffi.so
```

`build.sh` fetches Mozc at the commit in `MOZC_COMMIT` into `third_party/mozc` and builds `core/` inside its source
tree. The first build downloads Mozc's dependencies and takes a while.

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

Segment lengths count Unicode characters. Mozc keeps the profile directory per process, so open one profile per
process. `incognito` learns nothing.

## Test

```sh
python3 -m unittest discover -s python
dotnet run --project csharp/tests
```

## Licence

BSD-3-Clause. The built library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
