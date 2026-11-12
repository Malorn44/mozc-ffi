# How the calls work

Every binding wraps the same C API, so the calls behave the same in every language. Only the names change:
`convert` in Python, Node.js, Rust and C, `Convert` in C#.

## Readings and segments

A reading is what was typed, in hiragana. Converting it gives segments (文節). Each segment covers part of the
reading and has candidates, best first:

| Segment | Reading | Candidates |
|---|---|---|
| 1 | きょうは | 今日は, きょうは, 教は, … |
| 2 | さむいですね | 寒いですね, さむいですね, サムいですね, … |

The first candidate of every segment, joined, is Mozc's best conversion: 今日は寒いですね. Each candidate can also
have a description, Mozc's note on it in Japanese, such as カタカナ; most have none.

## Segment lengths

Mozc chooses where segments start, unless you pass their lengths. The lengths count Unicode characters (not bytes
or UTF-16 code units), one per segment, and must add up to the reading's length. A conversion with lengths
`[3, 5, 2]` cuts ここではきものをぬぐ into ここで / はきものを / ぬぐ, whose second segment then offers both は着物を
and 履物を.

This is how an input method lets the user move a segment boundary: convert again with the new lengths.

## Context

`context` is the text just before the reading, such as what the user already sent. Mozc uses it as history, so the
first segment converts as a continuation rather than the start of a sentence. Leave it empty when there is none.

## Prediction

`predict` gives completions of a reading that is still being typed: ありがと gives ありがとうございます, ありがとう
and more. They come as one list, not as segments.

## Learning

When the user sends a conversion, `learn` it: the reading, the lengths of its segments, and the text picked for
each one. Those picks rank first the next time the same reading is converted. `learn` only accepts texts that are
candidates of their segment; otherwise it learns nothing and returns false.

`clear_learning` forgets everything learned. `flush` writes what was learned to the profile now; closing does it
too.

## Profiles

A profile is the directory where Mozc keeps what it learns. It is created if missing, and no directory means
Mozc's default (on Linux `~/.mozc` if it exists, otherwise `$XDG_CONFIG_HOME/mozc` or `~/.config/mozc`). The
default is the profile an installed Mozc uses too, so pass a directory to keep your app's learning apart.

Mozc keeps the profile directory per process, so open one profile per process. Closing and opening the same
profile again is fine.

Incognito mode learns nothing and leaves the profile untouched, for text that shouldn't be remembered.

## Errors

A call that can't do what was asked returns an empty list or false (`NULL` or `0` in C). `last_error` then says
why, in English, such as "the segment lengths do not add up to the reading's length". It is a fixed sentence and
never quotes what was typed, and the library never logs readings or learning data.

Opening fails, with an exception or an error value depending on the language, when the library can't be loaded,
speaks another version of the C API, or Mozc can't start.

## Threads

One handle may be used from several threads; calls on it are serialized.