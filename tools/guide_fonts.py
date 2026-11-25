#!/usr/bin/env python3
"""Makes the pilot guide PDFs' fonts in crates/iaf-tools/fonts (guide_pdf.rs, docs/credits.md), once, with fontTools:

- Heebo-Regular.ttf and Heebo-Bold.ttf: the game's own Heebo (modern-iaf/data/fonts/Heebo-VariableFont_wght.ttf)
  as static fonts at weights 400 and 700, for all text, Hebrew included; its layout tables kept for shaping.
- NotoSansMono-Regular.ttf: Noto Sans Mono (Arch Linux's `noto-fonts`) cut to Latin, punctuation, arrows, maths and
  geometric shapes: the code text.
- DejaVuSans-Symbols.ttf: DejaVu Sans (Arch Linux's `ttf-dejavu`) cut to the arrows, maths operators, geometric shapes
  and Cyrillic, which Heebo lacks.

    python3 -I tools/guide_fonts.py [Noto Sans Mono file] [DejaVu Sans file]
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "crates/iaf-tools/fonts"


def cut(src, dst, unicodes, features):
    o = subset.Options()
    o.layout_features, o.name_IDs, o.notdef_outline = features, ["*"], True
    s = subset.Subsetter(o)
    s.populate(unicodes=unicodes)
    f = TTFont(src)
    s.subset(f)
    f.save(dst)
    print(f"{dst.name}: {dst.stat().st_size // 1024} KB")


def main():
    mono = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/noto/NotoSansMono-Regular.ttf")
    dejavu = Path(sys.argv[2] if len(sys.argv) > 2 else "/usr/share/fonts/TTF/DejaVuSans.ttf")
    heebo = ROOT / "modern-iaf/data/fonts/Heebo-VariableFont_wght.ttf"
    for name, wght in (("Regular", 400), ("Bold", 700)):
        f = instancer.instantiateVariableFont(TTFont(heebo), {"wght": wght}, updateFontNames=True)
        dst = OUT / f"Heebo-{name}.ttf"
        f.save(dst)
        print(f"{dst.name}: {dst.stat().st_size // 1024} KB")
    cut(mono, OUT / "NotoSansMono-Regular.ttf",
        [*range(0x20, 0x7F), *range(0xA0, 0x180), *range(0x2000, 0x2070), *range(0x2190, 0x2300),
         *range(0x25A0, 0x2600)], [])
    cut(dejavu, OUT / "DejaVuSans-Symbols.ttf",
        [0x20, *range(0x400, 0x530), *range(0x2190, 0x2300), *range(0x25A0, 0x2600)], ["kern"])


if __name__ == "__main__":
    main()
