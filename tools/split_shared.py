#!/usr/bin/env python3
"""A0, the split (iaf-2026/docs/plan.md "Three folders, one symlink each"): moves the Godot project game/ to
iaf-reborn/, moves the engine folders out of it into shared/, links iaf-reborn/shared -> ../shared, then rewrites
every path in the repo: res://<moved>/... -> res://shared/<moved>/..., game/<moved>/... -> shared/<moved>/...,
any other game/... -> iaf-reborn/..., and `--path game` -> `--path iaf-reborn`. res://../assets paths and
iaf.gdextension's res://../target paths stay. Idempotent: a second run changes nothing. Prints every rewrite.
Usage: python3 tools/split_shared.py [--dry-run]"""
import hashlib
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OLD, PROJ, SHARED = "game", "iaf-reborn", "shared"
# What moves to shared/ (each with its .uid files); everything else in game/ stays in iaf-reborn/.
MOVED_DIRS = ["aircraft", "ai", "audio", "cockpit", "controls", "extra", "mission", "terrain", "util", "weapons"]
MOVED_FILES = ["settings.gd", "settings.gd.uid", "default_bus_layout.tres"]
MOVED = set(MOVED_DIRS + MOVED_FILES)
# The plan describes the move itself (its `game/` is the folder before the split); this script names the old paths.
SKIP = {"iaf-2026/docs/plan.md", "tools/split_shared.py"}
TEXT_EXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".gdextension", ".cfg", ".json", ".md", ".sh",
            ".py", ".rs", ".ps1", ".toml", ".yml", ".yaml", ".godot", ".import", ".glsl", ".txt"}
TEXT_NAMES = {"iafjets", "mission-editor", "setup", ".gitignore", "gdlintrc"}

RES = re.compile(r"res://(%s)(?![\w.-])" % "|".join(re.escape(n) for n in sorted(MOVED, key=len, reverse=True)))
GAME = re.compile(r"(?<![\w.-])game([/\\])([\w.-]*)")
PATH_ARG = re.compile(r"(--path\s+)game\b")
PATH_ARG_LIST = re.compile(r"""(['"]--path['"],\s*['"])game(['"])""")
# One-off spellings of the folder that no general rule sees (the folder as a word, not followed by a separator).
LITERAL = [
    ("find game -path", "find -L iaf-reborn -path"),  # -L: the .import files under the shared link too
    ("Get-ChildItem game -Recurse", "Get-ChildItem iaf-reborn, shared -Recurse"),
    ('os.path.join(ROOT, "game")', 'os.path.join(ROOT, "iaf-reborn")'),
    ('"..", "..", "game", "extra"', '"..", "..", "shared", "extra"'),
]


def git(*args: str, dry: bool) -> None:
    print("  git " + " ".join(args))
    if not dry:
        subprocess.run(["git", "-C", str(ROOT), *args], check=True)


def move(dry: bool) -> None:
    print("move:")
    if (ROOT / OLD).is_dir() and not (ROOT / PROJ).exists():
        git("mv", OLD, PROJ, dry=dry)
    proj = ROOT / (PROJ if (ROOT / PROJ).exists() else OLD)  # a dry run before the move: still game/
    for name in MOVED_DIRS + MOVED_FILES:
        src = proj / name
        if src.exists() and not src.is_symlink() and not (ROOT / SHARED / name).exists():
            if not dry:
                (ROOT / SHARED).mkdir(exist_ok=True)
            git("mv", f"{PROJ}/{name}", f"{SHARED}/{name}", dry=dry)
    link = ROOT / PROJ / SHARED
    if not link.is_symlink():
        print(f"  ln -s ../{SHARED} {PROJ}/{SHARED}")
        if not dry:
            os.symlink(f"../{SHARED}", link)
            git("add", f"{PROJ}/{SHARED}", dry=dry)


def game_path(m: re.Match, ps: bool, counts: Counter) -> str:
    sep, rest = m.group(1), m.group(2)
    if sep == "\\" and (not ps or rest in ("n", "t") or not rest):
        return m.group(0)  # a backslash path only in PowerShell; never an escape such as "game\n"
    dest = SHARED if rest.rstrip(".") in MOVED else PROJ  # a trailing full stop ends a sentence, not the name
    counts[f"game{sep} -> {dest}{sep}"] += 1
    return f"{dest}{sep}{rest}"


def rewrite_text(text: str, ps: bool, counts: Counter) -> str:
    out = []
    for line in text.splitlines(keepends=True):
        for a, b in LITERAL:
            if a in line:
                line = line.replace(a, b)
                counts["literal: " + a] += 1

        def res(m: re.Match) -> str:
            counts["res://<moved> -> res://shared/<moved>"] += 1
            return f"res://{SHARED}/{m.group(1)}"

        line = RES.sub(res, line)
        for rx, repl, key in ((PATH_ARG, rf"\g<1>{PROJ}", "--path game"), (PATH_ARG_LIST, rf"\g<1>{PROJ}\g<2>", "'--path', 'game'")):
            line, n = rx.subn(repl, line)
            counts[key] += n
        # game/ paths, outside URLs (a web address may hold a /game/ of its own).
        parts = re.split(r"(\bhttps?://\S+)", line)
        line = "".join(p if p.startswith("http") else GAME.sub(lambda m: game_path(m, ps, counts), p) for p in parts)
        out.append(line)
    return "".join(out)


def import_hashes(text: str, counts: Counter) -> str:
    """An .import file names its imported copy <file>-<md5 of the source's res:// path>; Godot renames it on import."""
    m = re.search(r'^source_file="(res://[^"]+)"', text, re.M)
    if not m:
        return text
    name, digest = Path(m.group(1)).name, hashlib.md5(m.group(1).encode()).hexdigest()
    new, n = re.subn(r"(res://\.godot/imported/%s-)[0-9a-f]{32}" % re.escape(name), rf"\g<1>{digest}", text)
    if new != text:
        counts[".import copy name"] += n
    return new


def rewrite(dry: bool) -> Counter:
    print("rewrite:")
    total = Counter()
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, text=True, check=True)
    for rel in files.stdout.split("\0"):
        if not rel or rel in SKIP:
            continue
        path = ROOT / rel
        if path.is_symlink() or not path.is_file():
            continue
        if path.suffix.lower() not in TEXT_EXT and path.name not in TEXT_NAMES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        counts = Counter()
        new = rewrite_text(text, path.suffix.lower() == ".ps1", counts)
        if path.suffix == ".import":
            new = import_hashes(new, counts)
        if new != text:
            print(f"  {rel}: " + ", ".join(f"{k} ×{n}" for k, n in sorted(counts.items()) if n))
            total.update(counts)
            total["files"] += 1
            if not dry:
                path.write_text(new, encoding="utf-8")
    return total


def main() -> int:
    dry = "--dry-run" in sys.argv[1:]
    move(dry)
    total = rewrite(dry)
    print("summary%s:" % (" (dry run)" if dry else ""))
    for k, n in sorted(total.items()):
        if n:
            print(f"  {k}: {n}")
    if not total:
        print("  nothing to rewrite")
    elif not dry:
        # A longer path can push a Rust line past rustfmt's width.
        subprocess.run(["cargo", "fmt", "--all"], cwd=ROOT, check=True)
        print("  cargo fmt --all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
