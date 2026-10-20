#!/usr/bin/env python3
"""The real runway table of World scale Real 1:1 (docs/world-scale.md §3.4).

Fetches the OpenStreetMap runway ways of the ten iaf.ibx airbases from the Overpass API (or reads a saved answer),
puts their ends into engine metres with the georeference (`iaf-terrain game`, docs/georef.md) and writes
crates/iaf-flight/data/real_runways.csv. Data © OpenStreetMap contributors, ODbL 1.0.

    python3 -I tools/real_runways.py [overpass.json]
"""

import json
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
    # Tha'lah has no aeroway=runway way; this straight 2.7 km way along the base, tagged taxiway, is taken as the
    # runway (inferred), and Bley as Tha'lah (inferred, docs/world-scale.md §1.2).
    ("Bley", "Tha'lah AB (inferred)", [104382761]),
    ("Ryak", "Rayak AB", [23880576]),
    ("Aman", "Queen Alia", [30089088, 30089092]),
]


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
            width = e["tags"].get("width", "")
            rows.append([base, real, w, e["tags"].get("ref", ""), width, "%.7f" % a["lat"], "%.7f" % a["lon"],
                         "%.7f" % b["lat"], "%.7f" % b["lon"], "%.1f" % x0, "%.1f" % y0, "%.1f" % x1, "%.1f" % y1])
    with open(OUT, "w") as f:
        f.write("# The real runways of the ten iaf.ibx airbases (docs/world-scale.md §3.4), from tools/real_runways.py.\n")
        f.write("# Data (c) OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright\n")
        f.write("# (aeroway=runway ways via the Overpass API, %s). x / y: the way's ends in engine metres\n"
                % data.get("osm3s", {}).get("timestamp_osm_base", "?")[:10])
        f.write("# (X east, Y north) through the georeference (docs/georef.md). width: the OSM tag (m), empty = untagged.\n")
        f.write("base,real,osm_way,ref,width,lat0,lon0,lat1,lon1,x0,y0,x1,y1\n")
        for r in rows:
            f.write(",".join(str(v) for v in r) + "\n")
    print("wrote", OUT, len(rows), "runways")


if __name__ == "__main__":
    main()
