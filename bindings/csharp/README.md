# mozc-ffi for C#

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/csharp/README.ja.md)

<!-- --8<-- [start:guide] -->

C# bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter. Mozc
runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no install. Unofficial and not
affiliated with Google.

## Install

```sh
dotnet add package MozcFfi
```

The package targets .NET Standard 2.0 and holds the library for Linux x64 and arm64 (glibc 2.28 or later) and
Windows x64.

For Unity, use the Unity package instead: Unity can't install from NuGet. See
[the Unity README](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/unity/README.md).

## Use

```csharp
using System;
using System.Linq;
using MozcFfi;

using var mozc = new Mozc("/path/to/profile");
string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

Console.WriteLine(Best("きょうはさむいですね"));  // 今日は寒いですね

// Lengths fix the segments: ここで / はきものを / ぬぐ
var segments = mozc.Convert("ここではきものをぬぐ", new[] { 3, 5, 2 });
Console.WriteLine(string.Join(", ", segments[1].Candidates.Take(2)));  // は着物を, 履物を

// What the user sent ranks first next time.
mozc.Learn("ここではきものをぬぐ", new[] { 3, 5, 2 }, new[] { "ここで", "履物を", "脱ぐ" });
Console.WriteLine(Best("ここではきものをぬぐ"));  // ここで履物を脱ぐ

Console.WriteLine(string.Join(", ", mozc.Predict("ありがと").Take(2)));  // ありがとうございます, ありがとう
```

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc.

| | |
|---|---|
| `Convert(reading, lengths = null, context = null)` | The `Segment`s (`Reading`, `Candidates`, `Descriptions`), candidates best first. `lengths` fixes the segments; without it Mozc chooses them. `context` is the text before the reading, which helps the first segment. |
| `Predict(reading, context = null)` | Completions of the reading typed so far, best first. |
| `Learn(reading, lengths, texts, context = null)` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. `false`, and nothing learned, if a text isn't a candidate of its segment. |
| `ClearLearning()` | Forgets everything learned. |
| `Flush()` | Writes what was learned to the profile now. `Dispose()` does it too. |
| `LastError` | Why the last call failed, in English, or `""`. It never quotes what was typed. |
| `Mozc.MozcVersion` | Mozc's version, such as `"2.32.5994.102"`. |

Segment lengths count Unicode characters, not UTF-16 code units, and add up to the reading's length.
`Descriptions` has Mozc's note on each candidate in Japanese, such as `カタカナ`, or `""`.

A call that can't do what was asked returns an empty list or `false`, and `LastError` says why. `new Mozc()` throws
`MozcException` when the library speaks another ABI or Mozc can't start, and `DllNotFoundException` when the
library can't be found.

## Profiles

The profile directory holds what Mozc learns and is created if missing. `new Mozc()` with no directory uses Mozc's
default (`~/.mozc` on Linux). Mozc keeps the profile directory per process, so open one profile per process.
`new Mozc(path, incognito: true)` learns nothing and leaves the profile untouched.

One `Mozc` can be shared between threads: calls on it take turns.

## Finding the library

The bindings load `mozc_ffi` through P/Invoke. The package puts each platform's library under `runtimes/`, and
.NET loads the one for the machine. Elsewhere, put `mozc_ffi.dll` or `libmozc_ffi.so` next to your program or on
the system's library path. The C# bindings don't read `MOZC_FFI_LIBRARY`.

<!-- --8<-- [end:guide] -->

## More

- [Documentation](https://malorn44.github.io/mozc-ffi/csharp/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
