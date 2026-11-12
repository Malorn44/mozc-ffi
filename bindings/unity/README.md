# mozc-ffi for Unity

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/unity/README.ja.md)

<!-- --8<-- [start:guide] -->

The C# bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter, as
a Unity package with the native library. Mozc runs inside your app, with its dictionary built in: no
`mozc_server`, no IPC, no install. Unofficial and not affiliated with Google.

## Install

Unity installs packages from npm-style registries, not from NuGet, so this package is on npm as
`com.malorn44.mozc-ffi`. Add npm as a scoped registry and the package to your project's
`Packages/manifest.json`, next to what is already there:

<!-- x-release-please-start-version -->
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
<!-- x-release-please-end -->

Later versions then show up in the Package Manager. It needs Unity 2021.3 or later.

## Platforms

The Editor and Standalone players on Windows x64 and Linux x64 (glibc 2.28 or later), with Mono or IL2CPP. Other
platforms, Linux arm64, macOS and mobile included, have no library in this package.

## Example

The bindings are in the `MozcFfi` assembly, which Unity references automatically. If your scripts have their own
assembly definition, add `MozcFfi` to its references.

```csharp
using System.IO;
using System.Linq;
using MozcFfi;
using UnityEngine;

public class MozcExample : MonoBehaviour
{
    void Start()
    {
        using var mozc = new Mozc(Path.Combine(Application.persistentDataPath, "mozc"));
        string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

        Debug.Log(Best("きょうはさむいですね"));  // 今日は寒いですね

        // Lengths fix the segments: ここで / はきものを / ぬぐ
        var segments = mozc.Convert("ここではきものをぬぐ", new[] { 3, 5, 2 });
        Debug.Log(string.Join(", ", segments[1].Candidates.Take(2)));  // は着物を, 履物を

        // What the user sent ranks first next time.
        mozc.Learn("ここではきものをぬぐ", new[] { 3, 5, 2 }, new[] { "ここで", "履物を", "脱ぐ" });
        Debug.Log(Best("ここではきものをぬぐ"));  // ここで履物を脱ぐ

        Debug.Log(string.Join(", ", mozc.Predict("ありがと").Take(2)));  // ありがとうございます, ありがとう
    }
}
```

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks. In a
real scene, open Mozc once, in `Awake`, and dispose it in `OnDestroy`.

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
`DllNotFoundException` when there is no library for the platform.

## Profiles

The profile directory holds what Mozc learns and is created if missing; `Application.persistentDataPath` is a good
place for it. Mozc keeps the profile directory per process, and in the Editor that process lives on across Play
mode: open the same profile each time, and dispose the `Mozc` when you stop. Disposing it and opening it again is
fine. `new Mozc(path, incognito: true)` learns nothing and leaves the profile untouched.

## Threads

One `Mozc` can be shared between threads: calls on it take turns. A call runs on the calling thread and takes
about a millisecond for a short sentence, so calling it from the main thread is fine.

## Finding the library

The package holds `mozc_ffi.dll` and `libmozc_ffi.so` in `Runtime/Plugins/x86_64`, set up as plugins for the
Editor and Standalone players on Windows x64 and Linux x64. Unity loads the one for the platform, and builds copy
it into the player. The bindings don't read `MOZC_FFI_LIBRARY`.

<!-- --8<-- [end:guide] -->

## API reference

The bindings are the same as the NuGet package's, and come as source (`Runtime/MozcFfi.cs`), so your editor shows
their doc comments.

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/unity/)
- [The C# bindings on NuGet](https://www.nuget.org/packages/MozcFfi), for .NET outside Unity
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md), also in this
package.
