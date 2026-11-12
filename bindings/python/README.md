# mozc-ffi for Python

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/python/README.ja.md)

<!-- --8<-- [start:guide] -->

Python bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter.
Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no install. Unofficial and
not affiliated with Google.

## Install

```sh
pip install mozc-ffi
```

It needs Python 3.11 or later. Each wheel has the library inside, so there is nothing else to install.

## Platforms

Linux x64 and arm64 (glibc 2.28 or later) and Windows x64. There are no wheels for other platforms, such as macOS
or Alpine Linux (musl).

## Example

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね

    # Lengths fix the segments: ここで / はきものを / ぬぐ
    segments = mozc.convert("ここではきものをぬぐ", [3, 5, 2])
    print(segments[1].candidates[:2])  # ['は着物を', '履物を']

    # What the user sent ranks first next time.
    mozc.learn("ここではきものをぬぐ", [3, 5, 2], ["ここで", "履物を", "脱ぐ"])
    print("".join(s.candidates[0] for s in mozc.convert("ここではきものをぬぐ")))  # ここで履物を脱ぐ

    print(mozc.predict("ありがと")[:2])  # ['ありがとうございます', 'ありがとう']
```

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks.

## Calls

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc.

| | |
|---|---|
| `Mozc(profile_dir=None, *, incognito=False, library=None)` | Opens Mozc. Use it in a `with` block, or call `close()`. |
| `convert(reading, lengths=None, context="")` | A list of `Segment(reading, candidates, descriptions)`, candidates best first. `lengths` fixes the segments; without it Mozc chooses them. `context` is the text before the reading, which helps the first segment. |
| `predict(reading, context="")` | Completions of the reading typed so far, best first. |
| `learn(reading, lengths, texts, context="")` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. |
| `clear_learning()` | Forgets everything learned. |
| `flush()` | Writes what was learned to the profile now. Closing does it too. |
| `close()` | Saves what was learned and frees the engine. |
| `last_error` | Why the last call failed, or `""`. |
| `mozc_version` | Mozc's version, such as `"2.32.5994.102"`. |

Segment lengths count Unicode characters, not bytes, and add up to the reading's length. `descriptions` has Mozc's
note on each candidate in Japanese, such as `カタカナ`, or `""`.

## Errors

A call that can't do what was asked returns `[]` or `False`, and `last_error` says why, in English, such as "the
segment lengths do not add up to the reading's length". It never quotes what was typed. `learn` returns `False`,
and learns nothing, if a text isn't a candidate of its segment.

`Mozc(...)` raises `MozcError` when the library can't be loaded, speaks another version of the C API, or Mozc
can't start.

## Profiles

The profile directory holds what Mozc learns and is created if missing. `Mozc()` with no directory uses Mozc's
default (`~/.mozc` on Linux). Mozc keeps the profile directory per process, so open one profile per process;
closing it and opening it again is fine. `Mozc(path, incognito=True)` learns nothing and leaves the profile
untouched.

## Threads

One `Mozc` can be shared between threads: calls on it take turns. A call runs on the calling thread and takes
about a millisecond for a short sentence.

## Finding the library

`Mozc` loads the library the first time it opens, from the first of:

1. the `library=` argument,
2. the `MOZC_FFI_LIBRARY` environment variable,
3. next to the `mozc_ffi` module, where the wheel puts it,
4. the system's library path.

It stays loaded until the process exits.

<!-- --8<-- [end:guide] -->

## API reference

Every class and method, from the docstrings, is in the
[API reference](https://mozc-ffi.readthedocs.io/stable/python/#api-reference). Editors show the same docstrings,
and the package is typed.

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/python/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
