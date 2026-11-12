"""Runs the examples in README.md and README.ja.md against the library in build/ (or MOZC_FFI_LIBRARY).

Each ```python block runs in its own process, because Mozc keeps one profile per process, with "/path/to/profile"
replaced by a new directory. A print() with a comment after it must print exactly that comment.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIBRARY = "mozc_ffi.dll" if sys.platform == "win32" else "libmozc_ffi.so"
BLOCK = re.compile(r"^```python\n(.*?)^```", re.DOTALL | re.MULTILINE)
EXPECTED = re.compile(r"^\s*print\(.*\)\s+# (.*)$")


class ReadmeTest(unittest.TestCase):
    def test_examples(self) -> None:
        env = dict(os.environ)
        env.setdefault("MOZC_FFI_LIBRARY", str(ROOT / "build" / LIBRARY))
        env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(HERE), env.get("PYTHONPATH")]))
        env["PYTHONIOENCODING"] = "utf-8"
        for readme in ("README.md", "README.ja.md"):
            blocks = BLOCK.findall((HERE / readme).read_text(encoding="utf-8"))
            self.assertTrue(blocks, f"{readme} has no python example")
            for number, code in enumerate(blocks, 1):
                with self.subTest(readme=readme, block=number), tempfile.TemporaryDirectory() as profile:
                    run = subprocess.run(
                        [sys.executable, "-c", code.replace("/path/to/profile", Path(profile).as_posix())],
                        env=env,
                        capture_output=True,
                        encoding="utf-8",
                    )
                    self.assertEqual(run.returncode, 0, run.stderr)
                    expected = [m.group(1) for m in map(EXPECTED.match, code.splitlines()) if m]
                    self.assertEqual(run.stdout.splitlines(), expected)


if __name__ == "__main__":
    unittest.main()
