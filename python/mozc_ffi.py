"""Python bindings for mozc-ffi: Mozc's kana-kanji converter, in process, over ctypes.

    with Mozc("/path/to/profile") as mozc:
        mozc.convert("きょうはさむいですね")         # [Segment("きょうは", ["今日は", ...]), ...]
        mozc.convert("ここではきものをぬぐ", [3, 5, 2])  # fixed segment lengths, in characters
        mozc.predict("ありがと")                     # ["ありがとう", ...]
        mozc.learn("かんじ", [3], ["感じ"])           # 感じ ranks first next time

The library is found from MOZC_FFI_LIBRARY, next to this file, or on the system's library path.
"""

from __future__ import annotations

import ctypes
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

ABI_VERSION = 1
_INCOGNITO = 1


class MozcError(Exception):
    pass


@dataclass(frozen=True)
class Segment:
    reading: str
    candidates: list[str]


def _library_path() -> str:
    if os.environ.get("MOZC_FFI_LIBRARY"):
        return os.environ["MOZC_FFI_LIBRARY"]
    name = {"win32": "mozc_ffi.dll", "darwin": "libmozc_ffi.dylib"}.get(sys.platform, "libmozc_ffi.so")
    beside = Path(__file__).with_name(name)
    return str(beside) if beside.exists() else name


def _load(path: str) -> ctypes.CDLL:
    lib = ctypes.CDLL(path)
    handle, result, text, i32 = ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int32
    signatures = {
        "mozc_ffi_abi_version": ([], i32),
        "mozc_ffi_mozc_version": ([], text),
        "mozc_ffi_open": ([text, i32], handle),
        "mozc_ffi_close": ([handle], None),
        "mozc_ffi_convert": ([handle, text, ctypes.POINTER(i32), i32, text], result),
        "mozc_ffi_predict": ([handle, text, text], result),
        "mozc_ffi_segment_count": ([result], i32),
        "mozc_ffi_segment_reading": ([result, i32], text),
        "mozc_ffi_candidate_count": ([result, i32], i32),
        "mozc_ffi_candidate": ([result, i32, i32], text),
        "mozc_ffi_result_free": ([result], None),
        "mozc_ffi_learn": ([handle, text, ctypes.POINTER(i32), ctypes.POINTER(text), i32, text], i32),
        "mozc_ffi_clear_learning": ([handle], i32),
        "mozc_ffi_flush": ([handle], i32),
    }
    for name, (args, restype) in signatures.items():
        function = getattr(lib, name)
        function.argtypes = args
        function.restype = restype
    if lib.mozc_ffi_abi_version() != ABI_VERSION:
        raise MozcError(f"{path} has ABI {lib.mozc_ffi_abi_version()}, these bindings need {ABI_VERSION}")
    return lib


def _utf8(text: Optional[str]) -> Optional[bytes]:
    return None if text is None else text.encode("utf-8")


def _lengths(lengths: Sequence[int]):
    return (ctypes.c_int32 * len(lengths))(*lengths)


class Mozc:
    """One Mozc engine. Open one profile per process: Mozc keeps the profile directory globally."""

    def __init__(self, profile_dir: Optional[str | os.PathLike] = None, *, incognito: bool = False,
                 library: Optional[str] = None) -> None:
        self._lib = _load(library or _library_path())
        profile = None if profile_dir is None else os.fspath(profile_dir)
        self._handle = self._lib.mozc_ffi_open(_utf8(profile), _INCOGNITO if incognito else 0)
        if not self._handle:
            raise MozcError("mozc_ffi_open failed")

    @property
    def mozc_version(self) -> str:
        return self._lib.mozc_ffi_mozc_version().decode("utf-8")

    def convert(self, reading: str, lengths: Optional[Sequence[int]] = None, context: str = "") -> list[Segment]:
        """Segments of `reading` with candidates, best first; [] if it can't be converted as asked."""
        lengths = list(lengths or [])
        result = self._lib.mozc_ffi_convert(self._open(), _utf8(reading), _lengths(lengths), len(lengths),
                                            _utf8(context))
        return self._read(result)

    def predict(self, reading: str, context: str = "") -> list[str]:
        """Completions of `reading` typed so far."""
        segments = self._read(self._lib.mozc_ffi_predict(self._open(), _utf8(reading), _utf8(context)))
        return segments[0].candidates if segments else []

    def learn(self, reading: str, lengths: Sequence[int], texts: Sequence[str], context: str = "") -> bool:
        """Learns the picked `texts`, one per segment of `lengths`; False (nothing learned) on a mismatch."""
        if len(lengths) != len(texts):
            return False
        encoded = (ctypes.c_char_p * len(texts))(*(_utf8(t) for t in texts))
        return self._lib.mozc_ffi_learn(self._open(), _utf8(reading), _lengths(lengths), encoded, len(texts),
                                        _utf8(context)) == 1

    def clear_learning(self) -> bool:
        return self._lib.mozc_ffi_clear_learning(self._open()) == 1

    def flush(self) -> bool:
        return self._lib.mozc_ffi_flush(self._open()) == 1

    def close(self) -> None:
        if self._handle:
            self._lib.mozc_ffi_close(self._handle)
            self._handle = None

    def __enter__(self) -> Mozc:
        return self

    def __exit__(self, *_) -> None:
        self.close()

    def __del__(self) -> None:
        if getattr(self, "_handle", None):
            self.close()

    def _open(self):
        if not self._handle:
            raise MozcError("closed")
        return self._handle

    def _read(self, result) -> list[Segment]:
        if not result:
            return []
        lib = self._lib
        try:
            return [
                Segment(
                    lib.mozc_ffi_segment_reading(result, s).decode("utf-8"),
                    [lib.mozc_ffi_candidate(result, s, c).decode("utf-8")
                     for c in range(lib.mozc_ffi_candidate_count(result, s))],
                )
                for s in range(lib.mozc_ffi_segment_count(result))
            ]
        finally:
            lib.mozc_ffi_result_free(result)
