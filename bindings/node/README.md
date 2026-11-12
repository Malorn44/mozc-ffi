# mozc-ffi for Node.js

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/node/README.ja.md)

<!-- --8<-- [start:guide] -->

Node.js bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter.
Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no install. Unofficial and
not affiliated with Google.

## Install

```sh
npm install mozc-ffi
```

It needs Node.js 22 or later. TypeScript types are included.

The library comes in a separate package for each platform: `@mozc-ffi/linux-x64`, `@mozc-ffi/linux-arm64` and
`@mozc-ffi/win32-x64`. They are optional dependencies of `mozc-ffi`, and npm installs only the one that matches
the machine, so you never install them yourself.

## Platforms

Linux x64 and arm64 (glibc 2.28 or later) and Windows x64. On other platforms, or if you install without optional
dependencies, no library is installed: build it yourself and set `MOZC_FFI_LIBRARY` (below).

## Example

```js
const { Mozc } = require('mozc-ffi');

const mozc = new Mozc('/path/to/profile');
try {
  const segments = mozc.convert('きょうはさむいですね');
  console.log(segments.map((s) => s.candidates[0]).join('')); // 今日は寒いですね

  // Lengths fix the segments: ここで / はきものを / ぬぐ
  console.log(mozc.convert('ここではきものをぬぐ', [3, 5, 2])[1].candidates.slice(0, 2)); // [ 'は着物を', '履物を' ]

  // What the user sent ranks first next time.
  mozc.learn('ここではきものをぬぐ', [3, 5, 2], ['ここで', '履物を', '脱ぐ']);
  console.log(mozc.convert('ここではきものをぬぐ').map((s) => s.candidates[0]).join('')); // ここで履物を脱ぐ

  console.log(mozc.predict('ありがと').slice(0, 2)); // [ 'ありがとうございます', 'ありがとう' ]
} finally {
  mozc.close();
}
```

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks. Where
the runtime has `using` declarations, `using mozc = new Mozc(...)` closes it for you.

## Calls

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc.

| | |
|---|---|
| `new Mozc(profileDir?, { incognito? })` | Opens Mozc. Call `close()` when you're done, or use `using`. |
| `convert(reading, lengths?, context?)` | An array of `{ reading, candidates, descriptions }`, candidates best first. `lengths` fixes the segments; without it Mozc chooses them. `context` is the text before the reading, which helps the first segment. |
| `predict(reading, context?)` | Completions of the reading typed so far, best first. |
| `learn(reading, lengths, texts, context?)` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. |
| `clearLearning()` | Forgets everything learned. |
| `flush()` | Writes what was learned to the profile now. Closing does it too. |
| `close()` | Saves what was learned and frees the engine. |
| `lastError` | Why the last call failed, or `''`. |
| `Mozc.mozcVersion` | Mozc's version, such as `'2.32.5994.102'`. |

Segment lengths count Unicode characters, not UTF-16 code units, and add up to the reading's length.
`descriptions` has Mozc's note on each candidate in Japanese, such as `カタカナ`, or `''`.

## Errors

A call that can't do what was asked returns `[]` or `false`, and `lastError` says why, in English, such as "the
segment lengths do not add up to the reading's length". It never quotes what was typed. `learn` returns `false`,
and learns nothing, if a text isn't a candidate of its segment.

`new Mozc()` throws when the library can't be loaded, speaks another version of the C API, or Mozc can't start.

## Profiles

The profile directory holds what Mozc learns and is created if missing. `new Mozc()` with no directory uses Mozc's
default (`~/.mozc` on Linux). Mozc keeps the profile directory per process, so open one profile per process;
closing it and opening it again is fine. `new Mozc(path, { incognito: true })` learns nothing and leaves the
profile untouched.

## Threads

Calls are synchronous: they run on the calling thread and block it until they return, about a millisecond for a
short sentence. Worker threads share the process, so they also share its one profile.

## Finding the library

`mozc-ffi` loads the library the first time a `Mozc` opens, from the first of:

1. the `MOZC_FFI_LIBRARY` environment variable,
2. the `@mozc-ffi/<platform>-<arch>` package for this machine,
3. the system's library path.

It stays loaded until the process exits.

<!-- --8<-- [end:guide] -->

## API reference

The types, `index.d.ts`, carry a doc comment for every member, so your editor shows them. The
[API reference](https://mozc-ffi.readthedocs.io/stable/node/#api-reference) shows the whole file.

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/node/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
