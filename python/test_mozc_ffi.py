"""Tests for mozc_ffi against the library in build/ (or MOZC_FFI_LIBRARY).

    python3 -m unittest discover -s python
"""

from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = "mozc_ffi.dll" if sys.platform == "win32" else "libmozc_ffi.so"
os.environ.setdefault("MOZC_FFI_LIBRARY", str(ROOT / "build" / LIBRARY))

from mozc_ffi import ABI_VERSION, Mozc  # noqa: E402

PROFILE = ""


def setUpModule() -> None:
    global PROFILE
    PROFILE = tempfile.mkdtemp(prefix="mozc-ffi-test-")  # Mozc keeps one profile per process


def tearDownModule() -> None:
    shutil.rmtree(PROFILE, ignore_errors=True)


def first(segments) -> str:
    return "".join(s.candidates[0] for s in segments)


def reachable(target: str, segments) -> bool:
    """Whether picking one candidate per segment can spell `target`."""
    ends = {0}
    for segment in segments:
        ends = {e + len(c) for e in ends for c in segment.candidates if target.startswith(c, e)}
    return len(target) in ends


def chat_cases() -> list[tuple[str, list[str]]]:
    rows = (ROOT / "tests" / "chat.tsv").read_text(encoding="utf-8").splitlines()
    return [(r.split("\t")[0], r.split("\t")[1].split("|")) for r in rows if r and not r.startswith("#")]


class ConvertTest(unittest.TestCase):
    def setUp(self) -> None:
        self.mozc = Mozc(PROFILE, incognito=True)

    def tearDown(self) -> None:
        self.mozc.close()

    def test_versions(self) -> None:
        self.assertEqual(ABI_VERSION, 1)
        self.assertRegex(self.mozc.mozc_version, r"^\d+\.\d+\.\d+\.\d+$")

    def test_segments_cover_the_reading(self) -> None:
        segments = self.mozc.convert("きょうはさむいですね")
        self.assertEqual("".join(s.reading for s in segments), "きょうはさむいですね")
        self.assertTrue(all(s.candidates for s in segments))
        self.assertEqual(first(segments), "今日は寒いですね")

    def test_no_candidate_twice(self) -> None:
        candidates = self.mozc.convert("かんじ", [3])[0].candidates
        self.assertEqual(len(candidates), len(set(candidates)), candidates)

    def test_lengths_fix_the_segments(self) -> None:
        segments = self.mozc.convert("ここではきものをぬぐ", [3, 5, 2])
        self.assertEqual([s.reading for s in segments], ["ここで", "はきものを", "ぬぐ"])
        self.assertIn("履物を", segments[1].candidates)
        segments = self.mozc.convert("ここではきものをぬぐ", [4, 4, 2])
        self.assertEqual([s.reading for s in segments], ["ここでは", "きものを", "ぬぐ"])
        self.assertIn("着物を", segments[1].candidates)

    def test_bad_input_gives_nothing(self) -> None:
        self.assertEqual(self.mozc.convert("ここではきものをぬぐ", [3, 3]), [])
        self.assertEqual(self.mozc.convert("ここではきものをぬぐ", [0, 10]), [])
        self.assertEqual(self.mozc.convert(""), [])

    def test_predict_completes(self) -> None:
        predictions = self.mozc.predict("ありがと")
        self.assertTrue(any(p.startswith("ありがとう") for p in predictions), predictions)

    def test_context_is_accepted(self) -> None:
        self.assertEqual(first(self.mozc.convert("さむいですね", context="今日は")), "寒いですね")

    def test_chat_quality(self) -> None:
        # Baseline from Ubuntu's Mozc 2.26 typed through mozc_emacs_helper: 82% top-1, 95% by picks.
        cases = chat_cases()
        top1 = picks = 0
        for reading, answers in cases:
            segments = self.mozc.convert(reading)
            self.assertEqual("".join(s.reading for s in segments), reading)
            top1 += first(segments) in answers
            picks += any(reachable(a, segments) for a in answers)
        print(f"\nchat.tsv: top-1 {top1}/{len(cases)}, reachable by picks {picks}/{len(cases)}")
        self.assertGreaterEqual(top1 / len(cases), 0.80)
        self.assertGreaterEqual(picks / len(cases), 0.95)


class LearnTest(unittest.TestCase):
    def test_learning_ranks_the_pick_first_and_persists(self) -> None:
        with Mozc(PROFILE) as mozc:
            before = mozc.convert("かんじ", [3])[0].candidates
            pick = before[1]
            self.assertNotEqual(pick, before[0])
            self.assertTrue(mozc.learn("かんじ", [3], [pick]))
            self.assertEqual(mozc.convert("かんじ", [3])[0].candidates[0], pick)
            self.assertTrue(mozc.flush())
        with Mozc(PROFILE) as mozc:
            self.assertEqual(mozc.convert("かんじ", [3])[0].candidates[0], pick)
            self.assertTrue(mozc.clear_learning())
            self.assertEqual(mozc.convert("かんじ", [3])[0].candidates[0], before[0])

    def test_a_text_that_is_not_a_candidate_learns_nothing(self) -> None:
        with Mozc(PROFILE) as mozc:
            before = mozc.convert("きしゃ", [3])[0].candidates[0]
            self.assertFalse(mozc.learn("きしゃ", [3], ["not a candidate"]))
            self.assertFalse(mozc.learn("きしゃ", [2, 1], ["き", "しゃ", "extra"]))
            self.assertEqual(mozc.convert("きしゃ", [3])[0].candidates[0], before)

    def test_incognito_learns_nothing(self) -> None:
        with Mozc(PROFILE, incognito=True) as mozc:
            before = mozc.convert("はし", [2])[0].candidates
            self.assertNotEqual(before[1], before[0])
            mozc.learn("はし", [2], [before[1]])
            self.assertEqual(mozc.convert("はし", [2])[0].candidates[0], before[0])


if __name__ == "__main__":
    unittest.main()
