"""Checks a built library: it exports exactly the functions in core/mozc_ffi.h, and needs nothing
beyond the operating system (no C++ runtime of its own).

    python scripts/check_library.py build/libmozc_ffi.so [--max-glibc 2.28]
    python scripts/check_library.py build/mozc_ffi.dll
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HEADER = Path(__file__).resolve().parent.parent / "core" / "mozc_ffi.h"

# Shared libraries a Linux build may need: glibc's own.
LINUX_LIBRARIES = {
    "libc.so.6",
    "libm.so.6",
    "libpthread.so.0",
    "libdl.so.2",
    "librt.so.1",
    "ld-linux-x86-64.so.2",
    "ld-linux-aarch64.so.1",
}
# DLLs that mean the Visual C++ runtime is linked dynamically.
WINDOWS_RUNTIME = re.compile(r"^(msvcp|vcruntime|ucrtbase|api-ms-win-crt-)", re.IGNORECASE)


def api_functions() -> set[str]:
    return set(re.findall(r"MOZC_FFI_API\s[^;(]*?\b(mozc_ffi_\w+)\s*\(", HEADER.read_text(encoding="utf-8")))


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def check_elf(path: Path, max_glibc: str | None) -> list[str]:
    from elftools.elf.elffile import ELFFile

    problems = []
    with path.open("rb") as file:
        elf = ELFFile(file)
        needed = {
            tag.needed for tag in elf.get_section_by_name(".dynamic").iter_tags() if tag.entry.d_tag == "DT_NEEDED"
        }
        problems += [f"needs {name}" for name in sorted(needed - LINUX_LIBRARIES)]

        versions = elf.get_section_by_name(".gnu.version_r")
        for _, auxiliaries in versions.iter_versions() if versions else []:
            for auxiliary in auxiliaries:
                name = auxiliary.name
                if name.startswith(("GLIBCXX_", "CXXABI_", "GCC_")):
                    problems.append(f"needs the C++ runtime's {name}")
                elif max_glibc and name.startswith("GLIBC_") and name[6:][0].isdigit():
                    if version(name[6:]) > version(max_glibc):
                        problems.append(f"needs {name}, newer than glibc {max_glibc}")

        exported = {
            symbol.name
            for symbol in elf.get_section_by_name(".dynsym").iter_symbols()
            if symbol.name
            and symbol["st_info"]["bind"] in ("STB_GLOBAL", "STB_WEAK")
            and symbol["st_shndx"] != "SHN_UNDEF"
        }
    return problems + check_exports(exported)


def check_pe(path: Path) -> list[str]:
    import pefile

    pe = pefile.PE(str(path), fast_load=True)
    pe.parse_data_directories(
        directories=[
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"],
        ]
    )
    imported = [entry.dll.decode() for entry in getattr(pe, "DIRECTORY_ENTRY_IMPORT", [])]
    problems = [f"imports {name}, the Visual C++ runtime" for name in imported if WINDOWS_RUNTIME.match(name)]
    exported = {symbol.name.decode() for symbol in pe.DIRECTORY_ENTRY_EXPORT.symbols if symbol.name}
    return problems + check_exports(exported)


def check_exports(exported: set[str]) -> list[str]:
    expected = api_functions()
    return [f"exports {name}, which is not in mozc_ffi.h" for name in sorted(exported - expected)] + [
        f"does not export {name}" for name in sorted(expected - exported)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("library", type=Path)
    parser.add_argument("--max-glibc", help="the newest glibc version a Linux build may need, such as 2.28")
    args = parser.parse_args()

    with args.library.open("rb") as file:
        magic = file.read(4)
    if magic == b"\x7fELF":
        problems = check_elf(args.library, args.max_glibc)
    elif magic[:2] == b"MZ":
        problems = check_pe(args.library)
    else:
        print(f"{args.library}: neither ELF nor PE", file=sys.stderr)
        return 1

    for problem in problems:
        print(f"{args.library}: {problem}", file=sys.stderr)
    if not problems:
        print(f"{args.library}: exports the {len(api_functions())} API functions and needs no C++ runtime")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
