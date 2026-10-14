#!/usr/bin/env python3
"""Lints the Markdown docs (README, CLAUDE.md, docs/**): broken relative links and anchors, repo paths in backticks
that don't exist, `<doc>.md §N` references to a missing section, tables with a ragged column count, unclosed code
fences, trailing whitespace, and FUN_xxxxxxxx names absent from the decompile (when assets/ghidra_v11/iafjets.c is
there). Prints `file:line: message`; exit 1 when anything is found. Usage: tools/doclint.py [files…]"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECOMPILE = ROOT / "assets/ghidra_v11/iafjets.c"
# Paths named in backticks are checked only under these roots; placeholders (<id>, *, …) are skipped.
PATH_ROOTS = ("game/", "crates/", "tests/", "tools/", "docs/")


def slug(heading: str) -> str:
    """GitHub's anchor for a heading."""
    s = re.sub(r"[`*_]|\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip().lower())
    s = re.sub(r"[^\w\- ]", "", s, flags=re.UNICODE)
    return s.replace(" ", "-")


def strip_code(line: str) -> str:
    return re.sub(r"`[^`]*`", "", line)


def headings(path: Path) -> tuple[set, set]:
    """(anchors, section numbers such as '10', '12.4')."""
    anchors, sections, seen = set(), set(), {}
    fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
        if fence or not line.startswith("#"):
            continue
        text = line.lstrip("#").strip()
        a = slug(text)
        n = seen.get(a, 0)
        seen[a] = n + 1
        anchors.add(a if n == 0 else f"{a}-{n}")
        m = re.match(r"(?:§\s*)?(\d+(?:\.\d+)*)\.?\s", text)
        if m:
            sections.add(m.group(1))
    return anchors, sections


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--fun"]
    files = [Path(f).resolve() for f in args] or sorted(
        [ROOT / "README.md", ROOT / "CLAUDE.md", *ROOT.glob("docs/**/*.md")])
    funs = set(re.findall(r"\bFUN_([0-9a-f]{8})\b", DECOMPILE.read_text(errors="replace"))) if "--fun" in sys.argv and DECOMPILE.exists() else None
    cache = {}

    def info(p: Path):
        if p not in cache:
            cache[p] = headings(p)
        return cache[p]

    problems = 0

    def report(f: Path, n: int, msg: str):
        nonlocal problems
        problems += 1
        print(f"{f.relative_to(ROOT)}:{n}: {msg}")

    for f in files:
        if not f.exists():
            continue
        lines = f.read_text(encoding="utf-8").splitlines()
        fence_at = 0
        table_cols = None
        for n, line in enumerate(lines, 1):
            if line.lstrip().startswith("```"):
                fence_at = 0 if fence_at else n
                continue
            if fence_at:
                continue
            if line != line.rstrip():
                report(f, n, "trailing whitespace")
            # Tables: every row of one table has the header's column count (escaped pipes and code spans aside).
            if line.lstrip().startswith("|"):
                cells = len(re.split(r"(?<!\\)\|", strip_code(line).strip().strip("|")))
                if table_cols is None:
                    table_cols = cells
                elif cells != table_cols:
                    report(f, n, f"table row has {cells} columns, header {table_cols}")
            else:
                table_cols = None
            plain = strip_code(line)
            for target in re.findall(r"\]\(([^)\s]+)\)", plain):
                if re.match(r"[a-z]+:", target):
                    continue
                path_part, _, anchor = target.partition("#")
                dest = (f.parent / path_part).resolve() if path_part else f
                if not dest.exists():
                    report(f, n, f"broken link {target}")
                elif anchor and dest.suffix == ".md" and anchor not in info(dest)[0]:
                    report(f, n, f"missing anchor {target}")
            for p in re.findall(r"`([^`\s]+)`", line):
                p = p.rstrip(".,:;")
                if not p.startswith(PATH_ROOTS) or re.search(r"[<>*{}…$]|\.\.\.", p):
                    continue
                if not (ROOT / p.split(":")[0].split("#")[0]).exists():
                    report(f, n, f"no such path `{p}`")
            for doc, sec in re.findall(r"([\w./-]+\.md) §\s?(\d+(?:\.\d+)*)", plain):
                dest = (f.parent / doc) if (f.parent / doc).exists() else ROOT / doc if (ROOT / doc).exists() else ROOT / "docs" / Path(doc).name
                if not dest.exists():
                    report(f, n, f"§ reference to a missing doc {doc}")
                elif sec not in info(dest)[1]:
                    report(f, n, f"{doc} has no section §{sec}")
            if funs is not None:
                for a in re.findall(r"\bFUN_([0-9a-fA-F]{8})\b", line):
                    if a.lower() not in funs:
                        report(f, n, f"FUN_{a} is not in the decompile")
        if fence_at:
            report(f, fence_at, "code fence never closed")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
