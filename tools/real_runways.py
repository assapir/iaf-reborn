#!/usr/bin/env python3
"""The real runway table of World scale Real 1:1 (docs/world-scale.md §3.3).

Fetches the OpenStreetMap runway ways of the ten iaf.ibx airbases from the Overpass API (or reads a saved answer),
puts their ends into engine metres with the georeference (`iaf-terrain game`, docs/georef.md) and writes
crates/iaf-flight/data/real_runways.csv. Data © OpenStreetMap contributors, ODbL 1.0.

    python3 -I tools/real_runways.py [overpass.json]
"""

import json
import math
import os
import subprocess
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "crates/iaf-flight/data/real_runways.csv")
POINTS = os.path.join(ROOT, "crates/iaf-tools/data/georef_points.json")

# iaf.ibx section -> the real base's OSM ways (aeroway=runway unless noted).
BASES = [
    ("Ramon", "Ramon AB", [188475529, 188475532]),
    ("David", "Ramat David AB", [193609947, 193609938, 193609945]),
    ("TelNof", "Tel Nof AB", [292231592, 292231603, 292231604]),
    ("Refidim", "Bir Gifgafa", [97684500, 97684531, 1002223734]),
    ("Inshas", "Inshas AB", [30160502, 30160505, 30444201]),
    ("Damescuss", "Mezzeh", [25843643]),
    ("Kuzeir", "Al Qusayr AB", [95897209]),
    # Bley: Marj Ruhayyil AB, 6.6 km north of the village Beli (بلي), the name's only match in OSM (inferred,
    # docs/world-scale.md §1.2).
    ("Bley", "Marj Ruhayyil AB (inferred)", [95678635, 95678643]),
    ("Ryak", "Rayak AB", [23880576]),
    ("Aman", "Queen Alia", [30089088, 30089092]),
]


# OurAirports' runways.csv (public domain, https://davidmegginson.github.io/ourairports-data/runways.csv, read
# 2026-10-20) for the ways OSM has no width tag for: way -> (width_ft, designator or None), matched by designator and
# length (docs/world-scale.md §1.2).
OURAIRPORTS = {
    188475529: (148, None), 188475532: (148, None),
    193609947: (145, None), 193609938: (115, None), 193609945: (150, None),
    292231592: (150, None), 292231603: (150, None), 292231604: (150, None),
    97684531: (148, None),
    30160502: (141, None), 30444201: (131, None),
    95678643: (150, "06L/24R"), 95678635: (97, "06R/24L"),
    23880576: (148, None),
}


# The magnetic declination for an untagged runway's designator: ≈ 5° E over the theatre in 2026 (NOAA WMM, inferred
# as one value for all bases).
DECLINATION = 5.0


def designator(ref, lat0, lon0, lat1, lon1):
    """The OSM ref, else the two ends' numbers from the magnetic heading ("07/25")."""
    if ref:
        return ref
    h = math.degrees(math.atan2((lon1 - lon0) * math.cos(math.radians(lat0)), lat1 - lat0)) % 360.0
    n = [round(((x - DECLINATION) % 360.0) / 10.0) % 36 or 36 for x in (h, h + 180.0)]
    return "%02d/%02d" % tuple(sorted(n))


def overpass(ids):
    q = "[out:json][timeout:120];way(id:%s);out tags geom;" % ",".join(map(str, ids))
    req = urllib.request.Request("https://overpass-api.de/api/interpreter",
                                 data=urllib.parse.urlencode({"data": q}).encode(),
                                 headers={"User-Agent": "iaf-reborn real_runways.py"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)


def engine(lat, lon):
    out = subprocess.run(["cargo", "run", "-q", "--release", "-p", "iaf-tools", "--bin", "iaf-terrain", "--", "game",
                          POINTS, repr(lat), repr(lon)], cwd=ROOT, check=True, capture_output=True, text=True)
    x, y = out.stdout.split()
    return float(x), float(y)


def main():
    ids = [i for _, _, ws in BASES for i in ws]
    data = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else overpass(ids)
    ways = {e["id"]: e for e in data["elements"] if e["type"] == "way"}
    rows = []
    for base, real, ws in BASES:
        for w in ws:
            e = ways[w]
            a, b = e["geometry"][0], e["geometry"][-1]
            x0, y0 = engine(a["lat"], a["lon"])
            x1, y1 = engine(b["lat"], b["lon"])
            width, src = e["tags"].get("width", ""), "osm"
            oa_ft, oa_ref = OURAIRPORTS.get(w, (None, None))
            if not width:
                width, src = ("%.1f" % (oa_ft * 0.3048), "ourairports") if oa_ft else ("", "")
            ref = e["tags"].get("ref", "") or oa_ref or ""
            rows.append([base, real, w, e["tags"].get("ref", ""), width, "%.7f" % a["lat"], "%.7f" % a["lon"],
                         "%.7f" % b["lat"], "%.7f" % b["lon"], "%.1f" % x0, "%.1f" % y0, "%.1f" % x1, "%.1f" % y1,
                         designator(ref, a["lat"], a["lon"], b["lat"], b["lon"]), src])
    with open(OUT, "w") as f:
        f.write("# The real runways of the ten iaf.ibx airbases (docs/world-scale.md §3.3), from tools/real_runways.py.\n")
        f.write("# Data (c) OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright\n")
        f.write("# (aeroway=runway ways via the Overpass API, %s). x / y: the way's ends in engine metres\n"
                % data.get("osm3s", {}).get("timestamp_osm_base", "?")[:10])
        f.write("# (X east, Y north) through the georeference (docs/georef.md).\n")
        f.write("# width (m): the OSM tag (width_src osm), else OurAirports' runways.csv width_ft in metres (width_src ourairports;\n")
        f.write("# public domain, https://davidmegginson.github.io/ourairports-data/runways.csv, 2026-10-20); empty = neither (45 m).\n")
        f.write("# designator: the OSM ref, else OurAirports' (Marj Ruhayyil), else from the magnetic heading (declination %.0f° E, inferred).\n" % DECLINATION)
        f.write("base,real,osm_way,ref,width,lat0,lon0,lat1,lon1,x0,y0,x1,y1,designator,width_src\n")
        for r in rows:
            f.write(",".join(str(v) for v in r) + "\n")
    print("wrote", OUT, len(rows), "runways")


if __name__ == "__main__":
    main()
