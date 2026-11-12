# mozc-ffi for Rust

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/rust/README.ja.md)

<!-- --8<-- [start:guide] -->

Rust bindings for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter. Mozc
runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no install. Unofficial and not
affiliated with Google.

## Install

```sh
cargo add mozc-ffi --features download
```

It needs Rust 1.88 or later.

The crate holds only the bindings, because the native library is larger than crates.io allows. The `download`
feature fetches this version's library from its
[GitHub release](https://github.com/Malorn44/mozc-ffi/releases) when building and checks its SHA-256 (it needs
`curl` and `tar`). Without the feature, download the archive for your platform from the release yourself.

## Platforms

Linux x64 and arm64 (glibc 2.28 or later) and Windows x64. On other platforms the `download` feature stops the
build with an error: build the library yourself and set `MOZC_FFI_LIBRARY` (below).

## Example

```rust
use std::path::Path;

use mozc_ffi::Mozc;

fn main() -> Result<(), mozc_ffi::Error> {
    let mozc = Mozc::open(Some(Path::new("/path/to/profile")), false)?;
    let best = |reading: &str| -> String {
        let segments = mozc.convert(reading, &[], "");
        segments.iter().map(|s| s.candidates[0].as_str()).collect()
    };
    println!("{}", best("きょうはさむいですね")); // 今日は寒いですね

    // Lengths fix the segments: ここで / はきものを / ぬぐ
    let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], "");
    println!("{:?}", &segments[1].candidates[..2]); // ["は着物を", "履物を"]

    // What the user sent ranks first next time.
    mozc.learn("ここではきものをぬぐ", &[3, 5, 2], &["ここで", "履物を", "脱ぐ"], "");
    println!("{}", best("ここではきものをぬぐ")); // ここで履物を脱ぐ

    println!("{:?}", &mozc.predict("ありがと", "")[..2]); // ["ありがとうございます", "ありがとう"]
    Ok(())
}
```

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks.

## Calls

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc.

| | |
|---|---|
| `Mozc::open(profile_dir, incognito)` | Opens Mozc. Dropping it saves what was learned. |
| `convert(reading, lengths, context)` | The `Segment`s (`reading`, `candidates`, `descriptions`), candidates best first. `lengths` fixes the segments; `&[]` lets Mozc choose them. `context` is the text before the reading, which helps the first segment; `""` for none. |
| `predict(reading, context)` | Completions of the reading typed so far, best first. |
| `learn(reading, lengths, texts, context)` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. |
| `clear_learning()` | Forgets everything learned. |
| `flush()` | Writes what was learned to the profile now. Dropping the `Mozc` does it too. |
| `last_error()` | Why the last call failed, or `""`. |
| `mozc_version()` | Mozc's version, such as `"2.32.5994.102"`. |

Segment lengths count Unicode characters, not bytes, and add up to the reading's length. `descriptions` has Mozc's
note on each candidate in Japanese, such as `カタカナ`, or `""`.

## Errors

A call that can't do what was asked returns an empty `Vec` or `false`, and `last_error()` says why, in English,
such as "the segment lengths do not add up to the reading's length". It never quotes what was typed. `learn`
returns `false`, and learns nothing, if a text isn't a candidate of its segment.

`Mozc::open` returns an `Error` when the library can't be loaded (`Load`), speaks another version of the C API
(`Abi`), the profile path isn't UTF-8 (`Path`), or Mozc can't start (`Open`).

## Profiles

The profile directory holds what Mozc learns and is created if missing. `None` uses Mozc's default (`~/.mozc` on
Linux). Mozc keeps the profile directory per process, so open one profile per process; dropping it and opening it
again is fine. Opening with `incognito` set to `true` learns nothing and leaves the profile untouched.

## Threads

`Mozc` is `Send` and `Sync`, so one can be shared between threads: calls on it take turns. A call runs on the
calling thread and takes about a millisecond for a short sentence.

## Finding the library

`Mozc::open` loads the library from the first of:

1. the `MOZC_FFI_LIBRARY` environment variable,
2. next to the executable,
3. where the `download` feature put it (`mozc_ffi::DOWNLOADED_LIBRARY`),
4. the system's library path.

`Mozc::open_with_library` takes the path instead. The library stays loaded until the process exits. The `download`
feature's copy is in Cargo's build directory, so copy the library next to your executable when you hand the
program to someone else.

<!-- --8<-- [end:guide] -->

## API reference

The [API reference](https://docs.rs/mozc-ffi) is on docs.rs, built from the crate's doc comments.

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/rust/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
