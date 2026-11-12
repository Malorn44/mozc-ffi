# mozc-ffi for Unity

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/unity/README.ja.md)

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

Later versions then show up in the Package Manager.

It needs Unity 2021.3 or later. The library is set up for the Editor and Standalone players on Windows x64 and
Linux x64 (glibc 2.28 or later), with Mono or IL2CPP. Other platforms, Linux arm64 included, have no library in this
package.

## Use

The bindings are the same as the NuGet package's, in the `MozcFfi` assembly, which Unity references
automatically. If your scripts have their own assembly definition, add `MozcFfi` to its references.

```csharp
using System.IO;
using System.Linq;
using MozcFfi;
using UnityEngine;

public class Converter : MonoBehaviour
{
    Mozc mozc;

    void Awake() => mozc = new Mozc(Path.Combine(Application.persistentDataPath, "mozc"));

    void OnDestroy() => mozc?.Dispose();

    // 今日は寒いですね for きょうはさむいですね
    public string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

    // The user sent texts[i] for segment i: it ranks first next time.
    public void Sent(string reading, int[] lengths, string[] texts) => mozc.Learn(reading, lengths, texts);
}
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

Segment lengths count Unicode characters, not UTF-16 code units, and add up to the reading's length. A call that
can't do what was asked returns an empty list or `false`, and `LastError` says why.

## Profiles and threads

The profile directory holds what Mozc learns and is created if missing. Mozc keeps the profile directory per
process, and in the Editor that process lives on across Play mode: open the same profile each time, and dispose
the `Mozc` when you stop. `new Mozc(path, incognito: true)` learns nothing and leaves the profile untouched.

One `Mozc` can be shared between threads: calls on it take turns.

## More

- [Documentation](https://malorn44.github.io/mozc-ffi/unity/)
- [The C# bindings on NuGet](https://www.nuget.org/packages/MozcFfi), for .NET outside Unity
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md), also in this
package.
