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

The package targets .NET Standard 2.0 and has the library inside. For Unity, use the Unity package instead, since
Unity can't install from NuGet: see [Unity](https://mozc-ffi.readthedocs.io/stable/unity/).

## Platforms

Linux x64 and arm64 (glibc 2.28 or later) and Windows x64. On other platforms, build the library yourself and put
it next to your program.

## Example

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

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks.

## Calls

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc.

| | |
|---|---|
| `new Mozc(profileDir = null, incognito = false)` | Opens Mozc. Dispose it, or use `using`. |
| `Convert(reading, lengths = null, context = null)` | The `Segment`s (`Reading`, `Candidates`, `Descriptions`), candidates best first. `lengths` fixes the segments; without it Mozc chooses them. `context` is the text before the reading, which helps the first segment. |
| `Predict(reading, context = null)` | Completions of the reading typed so far, best first. |
| `Learn(reading, lengths, texts, context = null)` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. |
| `ClearLearning()` | Forgets everything learned. |
| `Flush()` | Writes what was learned to the profile now. `Dispose()` does it too. |
| `Dispose()` | Saves what was learned and frees the engine. |
| `LastError` | Why the last call failed, or `""`. |
| `Mozc.MozcVersion` | Mozc's version, such as `"3.35.6354.102"`. |

Segment lengths count Unicode characters, not UTF-16 code units, and add up to the reading's length.
`Descriptions` has Mozc's note on each candidate in Japanese, such as `カタカナ`, or `""`.

## Errors

A call that can't do what was asked returns an empty list or `false`, and `LastError` says why, in English, such
as "the segment lengths do not add up to the reading's length". It never quotes what was typed. `Learn` returns
`false`, and learns nothing, if a text isn't a candidate of its segment.

`new Mozc()` throws `MozcException` when the library speaks another version of the C API or Mozc can't start, and
`DllNotFoundException` when the library can't be found.

## Profiles

The profile directory holds what Mozc learns and is created if missing. `new Mozc()` with no directory uses Mozc's
default (on Linux `~/.mozc` if it exists, otherwise `$XDG_CONFIG_HOME/mozc` or `~/.config/mozc`). Mozc keeps the
profile directory per process, so open one profile per process; disposing it and opening it again is fine.
`new Mozc(path, incognito: true)` learns nothing and leaves the profile untouched.

## Threads

One `Mozc` can be shared between threads: calls on it take turns. A call runs on the calling thread and takes
about a millisecond for a short sentence.

## Finding the library

The bindings load `mozc_ffi` through P/Invoke. The package puts each platform's library under `runtimes/`, and
.NET loads the one for the machine. Elsewhere, put `mozc_ffi.dll` or `libmozc_ffi.so` next to your program or on
the system's library path. The C# bindings don't read `MOZC_FFI_LIBRARY`.

<!-- --8<-- [end:guide] -->

## API reference

The package carries its doc comments (`MozcFfi.xml`), so your editor shows them. The bindings are one source file,
[`MozcFfi.cs`](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/csharp/MozcFfi.cs).

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/csharp/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
