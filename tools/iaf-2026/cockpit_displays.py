#!/usr/bin/env python3
"""Modern IAF's own cockpit display data (iaf-2026/docs/cockpit.md "Display data"), for every jet's
iaf-2026/data/planes/_shared/cockpit/ (every jet's) and <jet>/cockpit/ (its own), which `iaf-sim own` compiles into
each jet's cockpit dir the shared readers take.

    python3 -I tools/iaf-2026/cockpit_displays.py map [--refetch]   # tsd_map.json from OpenStreetMap
    python3 -I tools/iaf-2026/cockpit_displays.py art               # the SVG sources and their PNGs

map: the TSD map's land, Israel, the West Bank's Area C, the Palestinian Authority's areas and the lakes in
longitude / latitude. The downloads go to their own folder, assets/source/osm/tsd_map/: OSM's simplified land
polygons (osmdata.openstreetmap.de, made from the coastline), the boundary relations (OSM API, `relation/<id>/full`)
and the theatre's large lakes (Overpass API). GDAL's ogr2ogr cuts and simplifies them (each boundary relation within
the land polygons, so its outline follows the coast).
art: tools/iaf-2026/cockpit/rwrsymb.svg (the RWR glyph sheet), adi.svg (the ADI ball) and mfds.svg (the MFD atlas),
drawn here, rendered by rsvg-convert at the sizes the readers expect.

Data © OpenStreetMap contributors, ODbL 1.0. No email or personal data goes into any request.
"""

import json
import math
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "assets/source/osm/tsd_map")
ART = os.path.join(ROOT, "tools/iaf-2026/cockpit")
# Every jet's files (iaf-sim own copies them into each jet's cockpit dir; a jet's own file of the same name wins).
SHARED = os.path.join(ROOT, "iaf-2026/data/planes/_shared/cockpit")
AGENT = "iaf-2026-cockpit-displays/1.0"
ENDPOINTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
LAND_URL = "https://osmdata.openstreetmap.de/download/simplified-land-polygons-complete-3857.zip"
LAND_SHP = "simplified-land-polygons-complete-3857/simplified_land_polygons.shp"
OSM_API = "https://api.openstreetmap.org/api/0.6/relation/%d/full.json"
ISRAEL = 1473946  # OSM relation: Israel, boundary=administrative, admin_level=2 (the Golan to the 1974 A-Line)
# The West Bank's Oslo II areas (boundary=administrative, admin_level=6, source geomolg.ps), Hebron's H1 (the PA's
# part of the city, outside Area A) and the Gaza Strip (admin_level=4 of the Palestinian Territories, 1703814).
AREA_A, AREA_B, AREA_C, HEBRON_H1, GAZA = 3791783, 3791784, 3791785, 7391021, 1473938
# The sim's theatre (crates/iaf-tools/src/sim_terrain.rs BOX, UTM 36N E 507,904..855,040, N 3,255,296..3,766,272): its
# edges' lon / lat bounds (gdaltransform EPSG:32636 -> EPSG:4326: 33.081..36.842, 29.377..34.037) and a margin.
WEST, SOUTH, EAST, NORTH = 33.05, 29.35, 36.9, 34.07
LAKE_KM2 = 15.0  # smaller lakes are below a TSD pixel at the shortest range (inferred)
SIMPLIFY_DEG = 0.0015  # about 150 m: under one MFD pixel at the HSD's shortest range (inferred)
# The fills, in paint order: the original TSD map's colours (sea and lakes navy, the neighbours dark grey, Israel light
# grey) and two greys between them for the West Bank and Gaza (the user's decision of 2026-11-03,
# iaf-2026/docs/cockpit.md §8): Area C (Israeli control, outside Israel's OSM border) a darker light grey, the PA's
# areas (A, B, H1; Gaza) a mid grey. `radar` = the GM picture's (isr.png) brightness: land returns, water does not.
# Each layer's smallest ring (km2): 2 for land and Israel (islands), 0.3 for the PA's enclaves (about 4 HSD pixels
# across at its shortest range, inferred).
SEA = [34, 34, 91]
LAYERS = [
    ("land", [137, 136, 135], 150, 2.0),
    ("israel", [200, 199, 199], 150, 2.0),
    ("area_c", [186, 185, 184], 150, 2.0),
    ("pa", [157, 156, 154], 150, 0.3),
    ("lakes", SEA, 0, 2.0),
]
# The relations each boundary layer joins.
RELATIONS = {"israel": [ISRAEL], "area_c": [AREA_C], "pa": [AREA_A, AREA_B, HEBRON_H1, GAZA]}


def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def cached(name, fetch, refetch):
    path = os.path.join(CACHE, name)
    if refetch or not os.path.exists(path):
        raw = fetch()
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "wb") as f:
            f.write(raw)
    return path


def overpass(query):
    body = urllib.parse.urlencode({"data": query}).encode()
    err = None
    for url in ENDPOINTS:
        try:
            raw = get(url, body)
            data = json.loads(raw)
            if "error" in data.get("remark", ""):  # a timed-out query answers 200 with part of the data
                raise ValueError(data["remark"])
            return raw
        except (OSError, ValueError) as e:
            err = e
    sys.exit("Overpass failed (%s); try again later" % err)


def rings(members):
    """The closed rings the ways make (their geometries joined end to end), as [[lon, lat], ...]."""
    open_ = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in members if m.get("geometry")]
    out = []
    while open_:
        ring = open_.pop()
        while ring[0] != ring[-1]:
            for i, w in enumerate(open_):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[-2::-1]
                else:
                    continue
                open_.pop(i)
                break
            else:
                break  # an unclosed piece (cut off by the query): left out
        if ring[0] == ring[-1] and len(ring) >= 4:
            out.append([list(p) for p in ring])
    return out


def area_km2(ring):
    lat0 = math.radians(sum(p[1] for p in ring) / len(ring))
    k = 111.32 * 111.32 * math.cos(lat0)
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:]))) / 2 * k


def relation(rid, refetch):
    """An OSM relation (the API's /full: its ways and their nodes): (its version, its members with their geometry, as
    Overpass's `out geom` gives them)."""
    path = cached("rel_%d.json" % rid, lambda: get(OSM_API % rid), refetch)
    els = json.load(open(path))["elements"]
    nodes = {e["id"]: e for e in els if e["type"] == "node"}
    ways = {e["id"]: e for e in els if e["type"] == "way"}
    rel = next(e for e in els if e["type"] == "relation" and e["id"] == rid)
    members = [
        {"role": m["role"], "geometry": [{"lon": nodes[n]["lon"], "lat": nodes[n]["lat"]} for n in ways[m["ref"]]["nodes"]]}
        for m in rel["members"]
        if m["type"] == "way"
    ]
    return rel["version"], members


def write_geojson(path, polys):
    feats = [{"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [r]}} for r in polys]
    with open(path, "w") as f:
        json.dump({"type": "FeatureCollection", "features": feats}, f)


def ogr(*args):
    """ogr2ogr to GeoJSON; args end with the output and the input (the GeoJSON driver cannot overwrite a file)."""
    if os.path.exists(args[-2]):
        os.remove(args[-2])
    subprocess.run(["ogr2ogr", "-f", "GeoJSON", *args], check=True)


def outer_rings(path):
    """Every polygon's outer ring of a GeoJSON file (the readers fill a polygon's first ring only)."""
    out = []
    for f in json.load(open(path))["features"]:
        g = f["geometry"]
        if g is None:
            continue
        polys = {"Polygon": [g["coordinates"]], "MultiPolygon": g["coordinates"]}.get(g["type"], [])
        out += [[[round(x, 5), round(y, 5)] for x, y in p[0]] for p in polys]
    return out


def build_map(refetch):
    bbox = "%s,%s,%s,%s" % (SOUTH, WEST, NORTH, EAST)
    land_zip = cached("simplified-land-polygons-complete-3857.zip", lambda: get(LAND_URL), refetch)
    # Lakes in two steps (one query with their geometry times out): every lake's bounds, then the geometry of those
    # whose bounds could hold LAKE_KM2.
    lakes_q = (
        '[out:json][timeout:300][bbox:%s];nwr["natural"="water"]["water"~"^(lake|lagoon|reservoir|salt_lake)$"];' % bbox
    )
    bounds = json.load(open(cached("lake_bounds.json", lambda: overpass(lakes_q + "out ids bb;"), refetch)))

    def big(e):
        b = e.get("bounds")
        if not b:
            return False
        h = (b["maxlat"] - b["minlat"]) * 111.32
        return h * (b["maxlon"] - b["minlon"]) * 111.32 * math.cos(math.radians(b["minlat"])) >= LAKE_KM2

    keep = [e for e in bounds["elements"] if e["type"] in ("way", "relation") and big(e)]
    ids = "".join("%s(%d);" % (e["type"][:3] if e["type"] == "relation" else "way", e["id"]) for e in keep)
    lakes_q = "[out:json][timeout:300];(%s);out geom;" % ids
    lk = cached("lakes.json", lambda: overpass(lakes_q), refetch)
    work = os.path.join(CACHE, "work")
    os.makedirs(work, exist_ok=True)
    w = lambda n: os.path.join(work, n)  # noqa: E731
    box = [str(v) for v in (WEST, SOUTH, EAST, NORTH)]
    # Land: the polygons over the theatre, in lon / lat, cut at the box and simplified.
    ogr("-t_srs", "EPSG:4326", "-spat", *box, "-spat_srs", "EPSG:4326", "-clipdst", *box,
        "-explodecollections", w("land_full.geojson"), "/vsizip/" + land_zip + "/" + LAND_SHP)
    ogr("-simplify", str(SIMPLIFY_DEG), w("land.geojson"), w("land_full.geojson"))
    # The boundaries: each relation's outer ways joined into rings, cut by the land (their waters left out). Area C's
    # outer ring is the whole West Bank but East Jerusalem; the PA's areas, painted over it, are its holes (Hebron's H2
    # stays Area C).
    versions = []
    for name, ids in RELATIONS.items():
        rs = []
        for rid in ids:
            version, members = relation(rid, refetch)
            versions.append("%d v%d" % (rid, version))
            rs += rings([m for m in members if m["role"] == "outer"])
        write_geojson(w(name + "_rel.geojson"), rs)
        ogr("-clipsrc", w("land_full.geojson"), "-explodecollections", w(name + "_land.geojson"), w(name + "_rel.geojson"))
        ogr("-simplify", str(SIMPLIFY_DEG), w(name + ".geojson"), w(name + "_land.geojson"))
    # Lakes: closed ways and the multipolygons' outer rings, the large ones only.
    polys = []
    for e in json.load(open(lk))["elements"]:
        if e["type"] == "way":
            polys += rings([e])
        else:
            polys += rings([m for m in e["members"] if m.get("role") == "outer"])
    write_geojson(w("lakes_all.geojson"), [r for r in polys if area_km2(r) >= LAKE_KM2])
    ogr("-clipdst", *box, "-explodecollections", "-simplify", str(SIMPLIFY_DEG), w("lakes.geojson"),
        w("lakes_all.geojson"))
    layers = []
    for name, brush, radar, min_km2 in LAYERS:
        rs = [r for r in outer_rings(w(name + ".geojson")) if len(r) >= 4 and area_km2(r) >= min_km2]
        layers.append({"name": name, "brush": brush, "radar": radar, "rings": rs})
        print("%s: %d rings, %d points" % (name, len(rs), sum(len(r) for r in rs)))
    out = {
        "_doc": "The TSD map (iaf-2026/docs/cockpit.md \"Display data\"): polygons in longitude / latitude (WGS84), "
        "filled in order over the background; iaf-sim own compiles it into map.json (the EMF-JSON shape cockpit.gd "
        "reads) and isr.png (the GM picture, each layer's radar brightness). Made by "
        "tools/iaf-2026/cockpit_displays.py map.",
        "source": "OpenStreetMap: simplified land polygons (osmdata.openstreetmap.de, %s); the relations (id version) "
        "%s: Israel %d, Area C %d, the PA's areas %d (A), %d (B), %d (Hebron H1), %d (Gaza), fetched %s (OSM API); "
        "natural=water lakes of %g km2 or more, OSM data of %s (Overpass)"
        % (LAND_URL, ", ".join(versions), ISRAEL, AREA_C, AREA_A, AREA_B, HEBRON_H1, GAZA,
           time.strftime("%Y-%m-%d", time.gmtime(os.path.getmtime(os.path.join(CACHE, "rel_%d.json" % ISRAEL)))),
           LAKE_KM2, osm_date(lk)),
        "license": "Data (c) OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright",
        "background": SEA,
        "background_radar": 0,
        "layers": layers,
    }
    text = json.dumps(out, separators=(",", ":"))
    os.makedirs(SHARED, exist_ok=True)
    with open(os.path.join(SHARED, "tsd_map.json"), "w") as f:
        f.write(text + "\n")
    print("tsd_map.json: %d bytes" % len(text))


def osm_date(path):
    return json.load(open(path))["osm3s"]["timestamp_osm_base"][:10]


# --- art ---------------------------------------------------------------------------------------------------------

# A stroke font on a 4 x 6 grid (x right, y down): the characters the RWR symbols use, as polylines.
FONT = {
    "0": [[(0, 0), (4, 0), (4, 6), (0, 6), (0, 0)]],
    "1": [[(1, 1), (2, 0), (2, 6)], [(1, 6), (3, 6)]],
    "2": [[(0, 0), (4, 0), (4, 3), (0, 3), (0, 6), (4, 6)]],
    "3": [[(0, 0), (4, 0), (4, 6), (0, 6)], [(1, 3), (4, 3)]],
    "4": [[(0, 0), (0, 3), (4, 3)], [(4, 0), (4, 6)]],
    "5": [[(4, 0), (0, 0), (0, 3), (4, 3), (4, 6), (0, 6)]],
    "6": [[(4, 0), (0, 0), (0, 6), (4, 6), (4, 3), (0, 3)]],
    "8": [[(0, 0), (4, 0), (4, 6), (0, 6), (0, 0)], [(0, 3), (4, 3)]],
    "9": [[(4, 3), (0, 3), (0, 0), (4, 0), (4, 6), (0, 6)]],
    "A": [[(0, 6), (0, 2), (2, 0), (4, 2), (4, 6)], [(0, 4), (4, 4)]],
    "F": [[(4, 0), (0, 0), (0, 6)], [(0, 3), (3, 3)]],
    "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
    "K": [[(0, 0), (0, 6)], [(4, 0), (0, 3), (4, 6)]],
    "M": [[(0, 6), (0, 0), (2, 3), (4, 0), (4, 6)]],
    "U": [[(0, 0), (0, 6), (4, 6), (4, 0)]],
}
# The sheet's slots (docs/rwr.md §4: 10 x 10 at y = 10·i, by the bdb type code cockpit.gd RWR_GLYPH maps), each
# [text, airborne]: the ALR-56M's way (the threat by its number, airborne emitters under a hat; UOAF codex),
# the letters ours (inferred).
SLOTS = [
    ("2", False),  # 290 SA-2
    ("3", False),  # 300 SA-3
    ("5", False),  # 310 SA-5
    ("6", False),  # 320 SA-6
    ("8", False),  # 330 SA-8
    ("HK", False),  # 340 Hawk (inferred)
    ("A", False),  # 360 / 380 / 390 the gun-dish radar and the ships' (AAA, inferred)
    ("A", False),  # 350 AAA
    ("21", True),  # 150 MiG-21
    ("23", True),  # 160 MiG-23
    ("29", True),  # 180 MiG-29
    ("25", True),  # 170 MiG-25
    ("F4", True),  # 120 / 200 F-4
    ("15", True),  # 110 F-15
    ("16", True),  # 100 F-16
    ("M2", True),  # 130 / 190 Kfir / Mirage (inferred)
    ("U", True),  # 140 the Lavi: an unknown airborne radar (inferred)
]
SCALE = 4  # the converted sheet's image_scale: 40 x 680 px
GREEN = "#00e000"  # the ALR-56M's green display (inferred from the original's 0,200,0 glyphs and cockpit photos)


def text_paths(text, x0, y0, h):
    """Polyline path data of `text` (glyph height h, centred at x0, top y0)."""
    k = h / 6.0
    w = 4 * k
    gap = 1.6 * k
    total = len(text) * w + (len(text) - 1) * gap
    d = []
    for i, ch in enumerate(text):
        ox = x0 - total / 2 + i * (w + gap)
        for line in FONT[ch]:
            d.append("M" + " L".join("%.2f %.2f" % (ox + px * k, y0 + py * k) for px, py in line))
    return " ".join(d)


def rwr_svg():
    s = 10 * SCALE
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
        % (s, s * len(SLOTS), s, s * len(SLOTS)),
        "<!-- Modern IAF's RWR glyph sheet (tools/iaf-2026/cockpit_displays.py art; iaf-2026/docs/cockpit.md):",
        "     17 slots of 40 x 40 px top to bottom in docs/rwr.md's order; green strokes on transparent. -->",
        '<g fill="none" stroke="%s" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round">' % GREEN,
    ]
    for i, (text, air) in enumerate(SLOTS):
        y = i * s
        if air:  # the hat: an inverted V over the number
            parts.append('<path d="M9 %.1f L20 %.1f L31 %.1f"/>' % (y + 10, y + 3, y + 10))
            parts.append('<path d="%s"/>' % text_paths(text, 20, y + 17, 19))
        else:
            h = 22 if len(text) == 1 else 17
            parts.append('<path d="%s"/>' % text_paths(text, 20, y + 20 - h / 2, h))
    parts += ["</g>", "</svg>"]
    return "\n".join(parts) + "\n"


# The ADI ball (lens_adi.gdshader): 128 x 128 at 1x, columns 64 the centre, rows 360° of pitch wrapping, the
# horizon at row 62, pitch up toward row 0. Drawn at 4x (512 px).
def adi_svg():
    s, row = 4, lambda p: (62 - p * 128.0 / 360.0) * 4  # noqa: E731
    sky, ground = "#8f9497", "#141414"  # the F-16 ADI's grey over black (inferred from cockpit photos)
    o = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">',
        "<!-- Modern IAF's ADI ball (tools/iaf-2026/cockpit_displays.py art; iaf-2026/docs/cockpit.md): the texture",
        "     lens_adi.gdshader samples, 4x. Rows wrap through 360 deg of pitch, the horizon at y 248, +90 at y 120,",
        "     -90 at y 376, +-180 at y 504. Grey sky, black ground, a pitch line every 10 deg, numbered every 30. -->",
        '<rect x="0" y="0" width="512" height="%.2f" fill="%s"/>' % (row(0), sky),
        '<rect x="0" y="%.2f" width="512" height="%.2f" fill="%s"/>' % (row(0), row(-180) - row(0), ground),
        '<rect x="0" y="%.2f" width="512" height="%.2f" fill="%s"/>' % (row(-180), 512 - row(-180), sky),
        '<rect x="0" y="%.2f" width="512" height="6" fill="#f2f2f2"/>' % (row(0) - 3),
    ]
    for p in range(-170, 180, 10):
        if p == 0:
            continue
        y = row(p)
        ink = "#101010" if p > 0 else "#f0f0f0"
        if abs(p) == 90:
            o.append('<circle cx="256" cy="%.2f" r="9" fill="none" stroke="%s" stroke-width="3"/>' % (y, ink))
            if p < 0:
                o.append('<path d="M249.6 %.2f L262.4 %.2f M262.4 %.2f L249.6 %.2f" stroke="%s" stroke-width="3"/>'
                         % (y - 6.4, y + 6.4, y - 6.4, y + 6.4, ink))
            continue
        half = 40 if p % 30 == 0 else 22
        o.append('<rect x="%d" y="%.2f" width="%d" height="3" fill="%s"/>' % (256 - half, y - 1.5, 2 * half, ink))
        if p % 30 == 0:
            n = "%d" % (abs(p) // 10 if abs(p) <= 90 else (180 - abs(p)) // 10)
            for x in (256 - half - 14, 256 + half + 14):
                o.append('<text x="%d" y="%.2f" font-family="DejaVu Sans, sans-serif" font-weight="bold" '
                         'font-size="16" '
                         'fill="%s" text-anchor="middle">%s</text>' % (x, y + 6, ink, n))
    o.append("</svg>")
    return "\n".join(o) + "\n"


# The MFD atlas (mfds.png, docs/mfd.md §1 "mfds.bmp"): 264 x 924 at 1x, drawn at 4x, in the original's layout so the
# readers' source rects (mfd.gd TILE_*, _text, the range and compass sprites, hud.gd's pipper and 5 x 5 font) map
# identically; transparent where the original has its colour key. Ours: the tiles' frames and marks, and a pixel font
# of our own. The real formats (f16_mfd.gd, pcd_formats.gd) draw without it; it serves the 1998 pages and HUD.
MFD = "#00ff00"  # the MFD art's bright green (docs/mfd.md §2)
MFD_DIM = "#008400"
# The 5 x 5 sprite font (mfd.gd _text, hud.gd _glyph): each glyph 4 x 5 lit pixels and a blank column; the
# letters at (132, 850) in A..Z order, the digits and symbols at (132, 840): 0..9, blank, ".", ":", "+", "-", "%".
GLYPHS = {
    "A": [".##.", "#..#", "####", "#..#", "#..#"], "B": ["###.", "#..#", "###.", "#..#", "###."],
    "C": [".###", "#...", "#...", "#...", ".###"], "D": ["###.", "#..#", "#..#", "#..#", "###."],
    "E": ["####", "#...", "###.", "#...", "####"], "F": ["####", "#...", "###.", "#...", "#..."],
    "G": [".###", "#...", "#.##", "#..#", ".###"], "H": ["#..#", "#..#", "####", "#..#", "#..#"],
    "I": ["###.", ".#..", ".#..", ".#..", "###."], "J": ["...#", "...#", "...#", "#..#", ".##."],
    "K": ["#..#", "#.#.", "##..", "#.#.", "#..#"], "L": ["#...", "#...", "#...", "#...", "####"],
    "M": ["#..#", "####", "####", "#..#", "#..#"], "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": [".##.", "#..#", "#..#", "#..#", ".##."], "P": ["###.", "#..#", "###.", "#...", "#..."],
    "Q": [".##.", "#..#", "#..#", "#.#.", ".#.#"], "R": ["###.", "#..#", "###.", "#.#.", "#..#"],
    "S": [".###", "#...", ".##.", "...#", "###."], "T": ["####", ".#..", ".#..", ".#..", ".#.."],
    "U": ["#..#", "#..#", "#..#", "#..#", ".##."], "V": ["#..#", "#..#", "#..#", ".##.", ".##."],
    "W": ["#..#", "#..#", "####", "####", "#..#"], "X": ["#..#", ".##.", ".##.", ".##.", "#..#"],
    "Y": ["#..#", "#..#", ".##.", ".#..", ".#.."], "Z": ["####", "..#.", ".#..", "#...", "####"],
    "0": [".##.", "#.##", "#..#", "##.#", ".##."], "1": [".#..", "##..", ".#..", ".#..", "###."],
    "2": ["###.", "...#", ".##.", "#...", "####"], "3": ["###.", "...#", ".##.", "...#", "###."],
    "4": ["#..#", "#..#", "####", "...#", "...#"], "5": ["####", "#...", "###.", "...#", "###."],
    "6": [".##.", "#...", "###.", "#..#", ".##."], "7": ["####", "...#", "..#.", ".#..", ".#.."],
    "8": [".##.", "#..#", ".##.", "#..#", ".##."], "9": [".##.", "#..#", ".###", "...#", ".##."],
    " ": ["....", "....", "....", "....", "...."], ".": ["....", "....", "....", "....", ".#.."],
    ":": ["....", ".#..", "....", ".#..", "...."], "+": ["....", ".#..", "###.", ".#..", "...."],
    "-": ["....", "....", "###.", "....", "...."], "%": ["#..#", "..#.", ".#..", "#...", "#..#"],
}
# The range sprites (mfd.gd: 8 x 5 at (132 + 8i, 845)): 5..160 in narrow 3 x 5 digits, "1" one pixel wide.
NARROW = {"0": ["###", "#.#", "#.#", "#.#", "###"], "1": ["#", "#", "#", "#", "#"], "2": ["##.", "..#", ".#.", "#..", "###"],
          "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
          "6": ["###", "#..", "###", "#.#", "###"], "8": ["###", "#.#", "###", "#.#", "###"]}
# The compass letters (mfd.gd: 6 x 7 at (132 + 6i, 855), S E N W): 5 x 7 and a blank column.
COMPASS = {
    "S": [".###.", "#....", "#....", ".###.", "....#", "....#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
}


def _pixels(rows, x0, y0, colour=MFD):
    """Lit pixels of `rows` ('#') at (x0, y0), 1x units, as rects (crisp at the 4x scale)."""
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                out.append('<rect x="%d" y="%d" width="1" height="1" fill="%s"/>' % (x0 + x, y0 + y, colour))
    return out


def _label(text, x0, y0, colour=MFD):
    out = []
    for i, ch in enumerate(text):
        out += _pixels(GLYPHS[ch], x0 + 5 * i, y0, colour)
    return out


def _screen(x, y):
    """Path data of a tile's screen: 132 x 132 with its corners rounded (r 9)."""
    return ("M%d %d h114 a9 9 0 0 1 9 9 v114 a9 9 0 0 1 -9 9 h-114 a9 9 0 0 1 -9 -9 v-114 a9 9 0 0 1 9 -9 Z"
            % (x + 9, y))


def _tile(x, y, title="", menu=True, hole=""):
    """A 132 x 132 tile: the black screen with rounded corners (less the path `hole`: transparent, the picture under it
    shows), its title at (17, 3), MENU over button 6."""
    out = ['<path d="%s %s" fill="#000" fill-rule="evenodd"/>' % (_screen(x, y), hole)]
    if title:
        out += _label(title, x + 17, y + 3)
    if menu:
        out += _label("MENU", x + 13, y + 124)
    return out


def _side_arrows(x, y):
    """The list arrows by the left buttons 11 / 12 (up, down)."""
    return ['<path d="M%d %d l3 -3 l3 3 z M%d %d l3 3 l3 -3 z" fill="%s"/>' % (x + 2, y + 25, x + 2, y + 41, MFD)]


def _brackets(x, y):
    """The A-A scope's corner brackets and edge ticks."""
    d = []
    for cx, cy, sx, sy in [(10, 12, 1, 1), (122, 12, -1, 1), (10, 120, 1, -1), (122, 120, -1, -1)]:
        d.append("M%d %d v%d M%d %d h%d" % (x + cx, y + cy + 10 * sy, -10 * sy, x + cx, y + cy, 10 * sx))
    for ty in (40, 66, 92):
        d.append("M%d %d h4 M%d %d h-4" % (x + 10, y + ty, x + 122, y + ty))
    return ['<path d="%s" fill="none" stroke="%s" stroke-width="1"/>' % (" ".join(d), MFD)]


FAN = (66, 118, 104, 32)  # the ground-map fan: its apex (x, y in the tile), radius and half-angle (deg)


def _fan_pt(x, y, a, rr):
    return x + FAN[0] + rr * math.sin(math.radians(a)), y + FAN[1] - rr * math.cos(math.radians(a))


def _fan_area(x, y):
    """Path data of the ground-map fan's sector."""
    (ax, ay), (bx, by) = _fan_pt(x, y, -FAN[3], FAN[2]), _fan_pt(x, y, FAN[3], FAN[2])
    return "M%d %d L%.2f %.2f A%d %d 0 0 1 %.2f %.2f Z" % (x + FAN[0], y + FAN[1], ax, ay, FAN[2], FAN[2], bx, by)


def _fan(x, y):
    """The ground-map fan's grid: its edges, the nose's spoke and range arcs every quarter."""
    cx, cy, r = x + FAN[0], y + FAN[1], FAN[2]
    pts = lambda a, rr: _fan_pt(x, y, a, rr)  # noqa: E731
    out = []
    d = []
    for a in (-FAN[3], -FAN[3] / 2, 0, FAN[3] / 2, FAN[3]):
        px, py = pts(a, r)
        d.append("M%d %d L%.2f %.2f" % (cx, cy, px, py))
    for k in (0.25, 0.5, 0.75, 1.0):
        (sx, sy), (ex, ey) = pts(-FAN[3], r * k), pts(FAN[3], r * k)
        d.append("M%.2f %.2f A%.1f %.1f 0 0 1 %.2f %.2f" % (sx, sy, r * k, r * k, ex, ey))
    out.append('<path d="%s" fill="none" stroke="%s" stroke-width="1"/>' % (" ".join(d), MFD))
    return out


def _video(x, y, title):
    """A sensor page: the video box (transparent: the picture under it), its title, the zoom arrows."""
    out = _tile(x, y, title, hole="M%d %d v112 h112 v-112 Z" % (x + 10, y + 10))
    out.append('<rect x="%d.5" y="%d.5" width="111" height="111" fill="none" stroke="%s"/>' % (x + 10, y + 10, MFD))
    return out + _side_arrows(x, y)


def mfds_svg():
    s = SCALE
    o = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 264 924" '
        'shape-rendering="crispEdges">' % (264 * s, 924 * s),
        "<!-- Modern IAF's MFD atlas (tools/iaf-2026/cockpit_displays.py art; iaf-2026/docs/cockpit.md): the original",
        "     mfds.bmp's layout (docs/mfd.md §1), 264 x 924 units drawn at 4x; transparent outside the tiles. -->",
    ]
    o += _tile(0, 0)  # NAV, damage, MENU and the other text pages
    o += _tile(132, 0, "RWR")  # the RWR scope: rings, ticks every 30 deg, the centre
    d = ["M%d %d h7 M%d %d v7" % (132 + 62, 66, 132 + 66, 62)]
    for a in range(0, 360, 30):
        r0, r1 = (52, 58) if a % 90 else (48, 58)
        sa, ca = math.sin(math.radians(a)), math.cos(math.radians(a))
        d.append("M%.2f %.2f L%.2f %.2f" % (198 + r0 * sa, 66 - r0 * ca, 198 + r1 * sa, 66 - r1 * ca))
    o.append('<circle cx="198" cy="66" r="58" fill="none" stroke="%s"/>' % MFD)
    o.append('<circle cx="198" cy="66" r="29" fill="none" stroke="%s"/>' % MFD_DIM)
    o.append('<path d="%s" fill="none" stroke="%s"/>' % (" ".join(d), MFD))
    # Stores: the jet from above (its nine stations' counts and names written by mfd.gd), MRM / SRM, the gun's box.
    o += _tile(0, 132) + _side_arrows(0, 132)
    y = 132
    o.append('<path d="M66 %d L70 %d L70 %d L106 %d L106 %d L62 %d L26 %d L26 %d L62 %d L62 %d Z" fill="none" stroke="%s"/>'
             % (y + 20, y + 28, y + 36, y + 44, y + 48, y + 48, y + 48, y + 44, y + 36, y + 28, MFD))
    o += _label("MRM", 62, 132 + 53) + _label("SRM", 62, 132 + 63)
    o.append('<rect x="48.5" y="%d.5" width="35" height="9" fill="none" stroke="%s"/>' % (132 + 82, MFD))
    o += _label("GUN", 50, 132 + 85)
    o += _tile(132, 132)  # unused: a blank screen
    o += _tile(0, 264) + _brackets(0, 264) + _side_arrows(0, 264)  # A-A radar
    o += _tile(132, 264) + _brackets(132, 264)  # unused
    # TSD: the labels by the right buttons 16..19, the ownship ring.
    o += _tile(0, 396, "TACT") + _side_arrows(0, 396)
    for i, t in enumerate(["SAM", "WPT", "MAP", "SCL"]):
        o += _label(t, 132 - 3 - 5 * len(t), 396 + 20 * (i + 1) + 2)
    o.append('<circle cx="66" cy="%d" r="11" fill="none" stroke="%s"/>' % (396 + 84, MFD))
    o.append('<path d="M66 %d v10 M61 %d h10 M63 %d h6" fill="none" stroke="%s"/>'
             % (396 + 78, 396 + 81, 396 + 88, MFD))
    o += _tile(132, 396)  # unused
    o += _tile(0, 528)  # unused
    o += _tile(132, 528, "MAP", hole=_fan_area(132, 528)) + _fan(132, 528)  # the GM picture (isr.png) under the fan
    o += _video(0, 660, "FLIR")
    c = 660 + 66  # the reticle: corner brackets 20 out, a cross on the centre
    o.append('<path d="M46 %d v-8 h8 M86 %d v-8 h-8 M46 %d v8 h8 M86 %d v8 h-8 M56 %d h20 M66 %d v20" '
             'fill="none" stroke="%s"/>' % (c - 12, c - 12, c + 12, c + 12, c, c - 10, MFD))
    o += _label("NM", 132 - 14, 660 + 124)
    o += _tile(132, 660, "GMT") + _fan(132, 660)
    o += _video(0, 792, "TV")
    o.append('<path d="M66 %d v111 M10 %d h112" fill="none" stroke="%s"/>' % (792 + 10, 792 + 66, MFD))
    # The gun pipper (hud.gd: 32 x 32 at (132, 792), recoloured to the HUD's colour): a ring, eight ticks, the dot.
    d = []
    for a in range(0, 360, 45):
        sa, ca = math.sin(math.radians(a)), math.cos(math.radians(a))
        d.append("M%.2f %.2f L%.2f %.2f" % (148 + 12 * sa, 808 - 12 * ca, 148 + 15 * sa, 808 - 15 * ca))
    o.append('<g shape-rendering="geometricPrecision"><circle cx="148" cy="808" r="10" fill="none" stroke="%s"/>'
             '<path d="%s" fill="none" stroke="%s"/><circle cx="148" cy="808" r="0.8" fill="%s"/></g>'
             % (MFD, " ".join(d), MFD, MFD))
    # The NAV list's scroll arrows (8 x 4 each at (164, 792) and (164, 796)): the halves of a diamond.
    o.append('<path d="M164 796 L168 792 L172 796 L168 800 Z" fill="%s"/>' % MFD)
    for i, ch in enumerate("0123456789 .:+-%"):
        o += _pixels(GLYPHS[ch], 132 + 5 * i, 840)
    for i, ch in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        o += _pixels(GLYPHS[ch], 132 + 5 * i, 850)
    for i, n in enumerate(["5", "10", "20", "40", "80", "160"]):
        x = 132 + 8 * i
        for ch in n:
            o += _pixels(NARROW[ch], x, 845)
            x += len(NARROW[ch][0]) + (0 if ch == "1" else 1)
    for i, ch in enumerate("SENW"):
        o += _pixels(COMPASS[ch], 132 + 6 * i, 855)
    o.append("</svg>")
    return "\n".join(o) + "\n"


def build_art():
    os.makedirs(ART, exist_ok=True)
    os.makedirs(SHARED, exist_ok=True)
    # The ADI ball serves the F-16s' [LENHORIZON]; the F-35I's layout has none, so its copy is never read.
    for name, svg in [("rwrsymb", rwr_svg()), ("adi", adi_svg()), ("mfds", mfds_svg())]:
        src = os.path.join(ART, name + ".svg")
        with open(src, "w") as f:
            f.write(svg)
        subprocess.run(["rsvg-convert", "-o", os.path.join(SHARED, name + ".png"), src], check=True)
        print("%s.svg -> %s" % (name, os.path.relpath(SHARED, ROOT)))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "map":
        build_map("--refetch" in sys.argv)
    elif cmd == "art":
        build_art()
    else:
        sys.exit(__doc__)
