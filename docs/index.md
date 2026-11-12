# mozc-ffi

Unofficial C API and bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese
kana-kanji converter. Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no
install. Not affiliated with Google.

Every call is self-contained. You pass a reading and, optionally, segment lengths and the text before it, and get
back segments with candidates. Picks you learn rank first next time.

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね
```

## Languages

Each package comes with the library already built, for Linux x64 and arm64 (glibc 2.28 or later) and Windows x64.

| | Install | Needs |
|---|---|---|
| [Python](python.md) | `pip install mozc-ffi` | Python 3.11+ |
| [C#](csharp.md) | `dotnet add package MozcFfi` | .NET Standard 2.0 |
| [Unity](unity.md) | The `com.malorn44.mozc-ffi` package on npm | Unity 2021.3+, Windows or Linux x64 |
| [Node.js](node.md) | `npm install mozc-ffi` | Node.js 22+ |
| [Rust](rust.md) | `cargo add mozc-ffi --features download` | Rust 1.88+ |
| [C](c.md) | An archive from [Releases](https://github.com/Malorn44/mozc-ffi/releases) | |

[How the calls work](concepts.md) is the same in every language: readings, segments, learning and profiles.

## Links

- [Source on GitHub](https://github.com/Malorn44/mozc-ffi), where the README also covers building the library
  yourself
- [Releases](https://github.com/Malorn44/mozc-ffi/releases) and the
  [changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)
- [Licences](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md): mozc-ffi is BSD-3-Clause, and
  the library contains Mozc and its dictionary
