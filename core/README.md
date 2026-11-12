# mozc-ffi for C

English | [日本語](https://github.com/Malorn44/mozc-ffi/blob/main/core/README.ja.md)

<!-- --8<-- [start:guide] -->

A C API for [Mozc](https://github.com/google/mozc), Google's open-source Japanese kana-kanji converter, which every
other binding wraps. Mozc runs inside your process, with its dictionary built in: no `mozc_server`, no IPC, no
install. Unofficial and not affiliated with Google.

## Install

Download the archive for your platform from [Releases](https://github.com/Malorn44/mozc-ffi/releases):

| Archive | Holds |
|---|---|
| `mozc-ffi-X.Y.Z-linux-x64.tar.gz`, `-linux-arm64.tar.gz` | `include/mozc_ffi.h`, `lib/libmozc_ffi.so` |
| `mozc-ffi-X.Y.Z-windows-x64.zip` | `include/mozc_ffi.h`, `bin/mozc_ffi.dll`, `lib/mozc_ffi.lib` (the import library) |

`SHA256SUMS` lists their checksums. The header is plain C99.

## Platforms

Linux x64 and arm64 (glibc 2.28 or later) and Windows x64. The Windows DLL links the C++ runtime statically, so it
needs no Visual C++ Redistributable. On other platforms, build the library yourself, as the
[repository's README](https://github.com/Malorn44/mozc-ffi#build) describes.

## Example

```c
#include <stdio.h>

#include "mozc_ffi.h"

// Prints the first candidate of every segment: Mozc's best conversion.
static void print_best(mozc_ffi_result* result) {
  for (int32_t s = 0; s < mozc_ffi_segment_count(result); s++) {
    fputs(mozc_ffi_candidate(result, s, 0), stdout);
  }
  putchar('\n');
  mozc_ffi_result_free(result);
}

int main(void) {
  mozc_ffi* mozc = mozc_ffi_open("/path/to/profile", 0);
  if (mozc == NULL) {
    fprintf(stderr, "%s\n", mozc_ffi_last_error());
    return 1;
  }
  print_best(mozc_ffi_convert(mozc, "きょうはさむいですね", NULL, 0, NULL));  // 今日は寒いですね

  // Lengths fix the segments: ここで / はきものを / ぬぐ
  const int32_t lengths[] = {3, 5, 2};
  mozc_ffi_result* result = mozc_ffi_convert(mozc, "ここではきものをぬぐ", lengths, 3, NULL);
  printf("%s, %s\n", mozc_ffi_candidate(result, 1, 0), mozc_ffi_candidate(result, 1, 1));  // は着物を, 履物を
  mozc_ffi_result_free(result);

  // What the user sent ranks first next time.
  const char* const texts[] = {"ここで", "履物を", "脱ぐ"};
  mozc_ffi_learn(mozc, "ここではきものをぬぐ", lengths, texts, 3, NULL);
  print_best(mozc_ffi_convert(mozc, "ここではきものをぬぐ", NULL, 0, NULL));  // ここで履物を脱ぐ

  result = mozc_ffi_predict(mozc, "ありがと", NULL);
  printf("%s, %s\n", mozc_ffi_candidate(result, 0, 0), mozc_ffi_candidate(result, 0, 1));  // ありがとうございます, ありがとう
  mozc_ffi_result_free(result);

  mozc_ffi_close(mozc);
  return 0;
}
```

The outputs are from a new profile. Once Mozc has learned from you, its first candidates follow your picks.

## Calls

Every call is self-contained. You pass the reading in hiragana and, optionally, the segment lengths and the text
just before it, and get back segments with candidates. There is no state to keep in sync with Mozc. All strings
are UTF-8.

| | |
|---|---|
| `mozc_ffi_open(profile_dir, flags)` | Opens Mozc. `flags` is `0` or `MOZC_FFI_INCOGNITO`. |
| `mozc_ffi_close(mozc)` | Saves what was learned and frees the handle. |
| `mozc_ffi_convert(mozc, reading, lengths, n_lengths, context)` | A result with the reading's segments, candidates best first. `lengths` fixes the segments; `NULL` lets Mozc choose them. `context` is the text before the reading, which helps the first segment; `NULL` for none. |
| `mozc_ffi_predict(mozc, reading, context)` | A result with one segment: completions of the reading typed so far, best first. |
| `mozc_ffi_segment_count`, `_segment_reading`, `_candidate_count`, `_candidate`, `_candidate_description` | Read a result. Its strings stay valid until `mozc_ffi_result_free`. |
| `mozc_ffi_result_free(result)` | Frees a result. |
| `mozc_ffi_learn(mozc, reading, lengths, texts, n, context)` | Learns that `texts[i]` was picked for segment `i`, so the picks rank first next time. |
| `mozc_ffi_clear_learning(mozc)` | Forgets everything learned. |
| `mozc_ffi_flush(mozc)` | Writes what was learned to the profile now. Closing does it too. |
| `mozc_ffi_last_error()` | Why the last call on this thread failed, or `""`. |
| `mozc_ffi_mozc_version()`, `mozc_ffi_abi_version()` | Mozc's version, such as `"3.35.6354.102"`, and the C API's, which must equal `MOZC_FFI_ABI_VERSION`. |

Segment lengths count Unicode characters, not bytes, and add up to the reading's length. A candidate's
description is Mozc's note on it in Japanese, such as `カタカナ`, or `""`.

## Errors

A call that can't do what was asked returns `NULL` or `0`, and `mozc_ffi_last_error()` says why, in English, such
as "the segment lengths do not add up to the reading's length". It is a fixed string that never quotes what was
typed and stays valid for the life of the process. `mozc_ffi_learn` returns `0`, and learns nothing, if a text
isn't a candidate of its segment.

`mozc_ffi_open` returns `NULL` when Mozc can't start. Compare `mozc_ffi_abi_version()` with
`MOZC_FFI_ABI_VERSION` first, to catch a library built from another version of the header.

## Profiles

The profile directory holds what Mozc learns and is created if missing. `NULL` or `""` uses Mozc's default (on
Linux `~/.mozc` if it exists, otherwise `$XDG_CONFIG_HOME/mozc` or `~/.config/mozc`). Mozc keeps the profile
directory per process, so open one profile per process; closing it and opening it again is fine.
`MOZC_FFI_INCOGNITO` learns nothing and leaves the profile untouched.

## Threads

One handle may be used from several threads; calls on it are serialized. `mozc_ffi_last_error()` is per thread. A
call runs on the calling thread and takes about a millisecond for a short sentence.

## Finding the library

Link against the library, and make it findable when the program runs:

```sh
# Linux
cc -std=c99 -Iinclude example.c -Llib -lmozc_ffi -o example
LD_LIBRARY_PATH=lib ./example
```

On Linux, either set `LD_LIBRARY_PATH`, link with an rpath such as `-Wl,-rpath,'$ORIGIN'`, or install the library
on the system's library path. On Windows, link against `lib/mozc_ffi.lib` and put `bin/mozc_ffi.dll` next to your
executable.

<!-- --8<-- [end:guide] -->

## API reference

[`mozc_ffi.h`](https://github.com/Malorn44/mozc-ffi/blob/main/core/mozc_ffi.h) documents every function. The
[documentation](https://mozc-ffi.readthedocs.io/stable/c/#api-reference) shows the whole header.

## More

- [Documentation](https://mozc-ffi.readthedocs.io/stable/c/)
- [Other languages, and building the library yourself](https://github.com/Malorn44/mozc-ffi)
- [Changelog](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause. The library contains Mozc and its dictionary, whose licences are in
[THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md).
