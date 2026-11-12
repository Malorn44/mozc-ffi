"""MkDocs hooks for the docs site (mkdocs.yml).

A page with <!-- csharp-api --> gets the C# bindings' public API there: each public type and member of
bindings/csharp/MozcFfi.cs with its doc comment, as an editor shows them from MozcFfi.xml.
"""

from __future__ import annotations

import html
import re
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "bindings" / "csharp" / "MozcFfi.cs"
MARKER = "<!-- csharp-api -->"
TYPE = re.compile(r"public (?:sealed |static )*class (\w+)")


def on_page_markdown(markdown: str, **_) -> str:
    if MARKER not in markdown:
        return markdown
    return markdown.replace(MARKER, csharp_api(SOURCE.read_text(encoding="utf-8")))


def csharp_api(source: str) -> str:
    """The public types and members of `source`, in order, as Markdown."""
    out: list[str] = []
    doc: list[str] = []
    for line in source.splitlines():
        line = line.strip()
        if line.startswith("static class Native"):
            break  # the P/Invoke declarations, private, are last
        if line.startswith("///"):
            doc.append(line[3:].strip())
            continue
        if line.startswith("public "):
            comment = " ".join(doc)
            kind = TYPE.match(line)
            if kind:
                out += [f"### `{kind.group(1)}`", "", summary(comment), ""]
            else:
                out += ["```csharp", signature(line), "```", "", summary(comment), *params(comment), ""]
        if not line.startswith("["):  # attributes sit between a doc comment and its member
            doc = []
    return "\n".join(out)


def signature(line: str) -> str:
    """A member's declaration without its body or a constructor's base call."""
    expression_bodied = " => " in line
    line = line.split(" => ")[0].split(" : base(")[0].rstrip(";")
    if "{ get;" in line:
        return line.split("{")[0] + "{ get; }"
    if expression_bodied and "(" not in line:  # a property such as MozcVersion => ...
        return line + " { get; }"
    return line.split(" {")[0]


def summary(comment: str) -> str:
    found = re.search(r"<summary>(.*?)</summary>", comment)
    return text(found.group(1)) if found else ""


def params(comment: str) -> list[str]:
    found = re.findall(r'<param name="(\w+)">(.*?)</param>', comment)
    return ["", *(f"- `{name}`: {text(body)}" for name, body in found)] if found else []


def text(xml: str) -> str:
    """Doc comment XML as Markdown: references in code spans, other tags dropped."""
    xml = re.sub(r'<(?:see cref|paramref name)="([^"]+)"\s*/>', r"`\1`", xml)
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", xml)).split())
