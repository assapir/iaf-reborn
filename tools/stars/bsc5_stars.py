#!/usr/bin/env python3
"""The night sky's stars (shared/terrain/stars_bsc5.json) from the Yale Bright Star Catalogue, 5th revised edition
(Hoffleit & Warren 1991; public domain; docs/credits.md), its ASCII file `ybsc5.gz` from
http://tdc-www.harvard.edu/catalogs/ybsc5.gz (the CDS layout, catalogue V/50):
    python3 -I tools/stars/bsc5_stars.py ybsc5.gz shared/terrain/stars_bsc5.json
Keeps the stars to V 6.0 (the naked eye's limit under a dark sky) as one flat array: right ascension (h), declination
(deg), both J2000, the V magnitude and the B−V colour index (0 where the catalogue has none)."""
import gzip
import json
import sys

LIMIT = 6.0


def main(src: str, out: str) -> None:
    flat = []
    with gzip.open(src, "rt", encoding="latin-1") as f:
        for line in f:
            ra, vmag = line[75:83].strip(), line[102:107].strip()
            if not ra or not vmag or float(vmag) > LIMIT:
                continue  # novae and the like have no J2000 place
            h = int(line[75:77]) + int(line[77:79]) / 60 + float(line[79:83]) / 3600
            d = int(line[84:86]) + int(line[86:88]) / 60 + int(line[88:90]) / 3600
            bv = line[109:114].strip()
            flat += [round(h, 4), round(-d if line[83] == "-" else d, 3), float(vmag), float(bv) if bv else 0.0]
    with open(out, "w") as f:
        json.dump({"source": "Yale Bright Star Catalogue 5 (public domain)", "stars": flat}, f, separators=(",", ":"))
    print(f"{len(flat) // 4} stars to V {LIMIT}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
