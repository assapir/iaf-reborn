"""A base's furniture rows from its survey folder (prep.py): OpenStreetMap's buildings inside the outline and the
airbase file's hangars and shelters, Sentinel-2's bright roofs at the taxiways' dead ends, the home jets in the
shelters, the ramp vehicles at the player's spot, the fence. Same rules as Ramon's (modern-iaf/docs/base-furniture.md
§2). usage: BASE=<icao> D=<folder> [THR=700 MAXPX=60] gen.py OUT_JSON JET|- [blobs|roofs]
blobs: Sentinel-2's bright roofs at the taxiways' dead ends are shelters; roofs: also its other bright roofs by the
pavement (where OpenStreetMap maps few buildings)."""
import json
import math
import os
import subprocess
import sys

import numpy as np
from matplotlib.path import Path
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo_any import D, ICAO, R, base, extra, layers, to_ll  # noqa: E402

OUT, JET = sys.argv[1], sys.argv[2]
USE_BLOBS = len(sys.argv) > 3 and sys.argv[3] in ("blobs", "roofs")
USE_ROOFS = len(sys.argv) > 3 and sys.argv[3] == "roofs"
PIX, SRCKEY = "Sentinel-2 pixels", "s2"
L, X, B = layers(), extra(), base()
ring = Path(L["boundary"][0])
lat_c = sum(p[0] for p in B["boundary"]) / len(B["boundary"])
lon_c = sum(p[1] for p in B["boundary"]) / len(B["boundary"])
GAMMA = (lon_c - 33.0) * math.sin(math.radians(lat_c))  # meridian convergence, UTM 36N: true = grid + GAMMA


def seg_near(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy or 1)))
    return (a[0] + t * dx, a[1] + t * dy)


def nearest(p, lines):
    best = (1e9, None)
    for ln in lines:
        for a, b in zip(ln, ln[1:]):
            q = seg_near(p, a, b)
            d = math.dist(p, q)
            if d < best[0]:
                best = (d, q)
    return best


def bearing(a, b):
    return math.degrees(math.atan2(b[0] - a[0], b[1] - a[1])) % 360


def foot(r):
    """centre, long side, short side, long axis bearing (0-180) of a ring."""
    pts = r[:-1] if r[0] == r[-1] else r
    c = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    sides = [(math.dist(a, b), bearing(a, b) % 180) for a, b in zip(pts, pts[1:] + pts[:1])]
    lng = max(sides)
    shorts = [s for s in sides if abs(((s[1] - lng[1] + 90) % 180) - 90) > 45]
    return c, lng[0], (max(s[0] for s in shorts) if shorts else lng[0]), lng[1]


TAXI = L["taxiway"]
APRON = [a + a[:1] for a in L["apron"]]
PAVED = TAXI + APRON
ACCESS = PAVED + X["road"]
RUNWAY = L["runway"]
rows = []


def add(kind, p, heading, note, source, size=None, **kw):
    r = {"kind": kind, "e": round(p[0], 1), "n": round(p[1], 1), "heading": round(heading % 360), "source": source,
         "note": note}
    if size:
        r["size_m"] = [round(size[0]), round(size[1])]
    r.update(kw)
    rows.append(r)
    return r


def door_size(lng, sh, ax, h):
    """[along the door's heading, across]: the footprint's sides turned to the door."""
    return (lng, sh) if abs(((h - ax + 90) % 180) - 90) <= 45 else (sh, lng)


def taken(p, d=15.0):
    return any(math.dist(p, (r["e"], r["n"])) < d for r in rows)


def clear_of_runways(c, lng, sh):
    return nearest(c, RUNWAY)[0] - math.hypot(lng, sh) / 2 > 40 + B["runways"][0].get("width_m", 45) / 2


# 1. The airbase file's hangars and shelters (OSM aeroway=hangar / building=hangar / shelters): their pads are paved.
for s, ring_ll in zip(B["shelters"], L["hangar"]):
    c, lng, sh, ax = foot(ring_ll)
    d, q = nearest(c, PAVED)
    if lng < 12:
        continue  # too small for a jet's shelter or a hangar: a hut on the pad (left out)
    if lng > 2.5 * sh and sh <= 30:
        add("sunshade", c, ax, f"OSM {s.get('kind')} {lng:.0f} × {sh:.0f} m ({s.get('osm')}): a long narrow roof over "
            "a parking row, drawn as a roof on posts (inferred)", "osm", (lng, sh), osm=s.get("osm"))
    elif lng <= 40 and sh <= 34:
        add("shelter", c, bearing(c, q), f"OSM {s.get('kind')} {lng:.0f} × {sh:.0f} m ({s.get('osm')}); a hardened "
            f"shelter by its size (inferred); door toward the nearest pavement, {d:.0f} m (inferred)", "osm",
            door_size(lng, sh, ax, bearing(c, q)), osm=s.get("osm"))
    else:
        # The door in the end nearer the pavement.
        h = ax if abs(((bearing(c, q) - ax + 180) % 360) - 180) <= 90 else ax + 180
        add("hangar", c, h, f"OSM {s.get('kind')} {lng:.0f} × {sh:.0f} m ({s.get('osm')}); doors in the end toward "
            "the pavement (inferred)", "osm", (lng, sh), osm=s.get("osm"))
# 2. OpenStreetMap's other buildings inside the outline.
for oid, r, tag, other in X["building"]:
    c, lng, sh, ax = foot(r)
    if not ring.contains_point(c) or taken(c) or lng < 5:
        continue
    if not clear_of_runways(c, lng, sh):
        continue
    if tag == "bunker" and 8 <= lng <= 45:
        d, q = nearest(c, ACCESS)
        what = "a munitions bunker" if "munitions" in other else "a bunker"
        add("shelter", c, bearing(c, q), f"OSM {what} {lng:.0f} × {sh:.0f} m (way/{oid}), drawn as an earth-covered "
            f"arch (inferred); door toward the nearest track, {d:.0f} m (inferred)", "osm",
            door_size(lng, sh, ax, bearing(c, q)),
            osm=f"way/{oid}", **({"store": True} if "munitions" in other else {}))
    elif tag == "hangar" or (lng >= 45 and lng * sh >= 1500 and nearest(c, PAVED)[0] < 60):
        d, q = nearest(c, PAVED)
        h = ax if abs(((bearing(c, q) - ax + 180) % 360) - 180) <= 90 else ax + 180
        add("hangar", c, h, f"OSM building={tag} {lng:.0f} × {sh:.0f} m (way/{oid}); a hangar by its size and place "
            "by the pavement (inferred); doors toward the pavement", "osm", (lng, sh), osm=f"way/{oid}")
    else:
        add("building", c, ax, f"OSM building={tag} {lng:.0f} × {sh:.0f} m (way/{oid})", "osm",
            (max(lng, 6), max(sh, 6)), osm=f"way/{oid}")


# 3. Sentinel-2's bright roofs (blobs.py's rule: brighter than the ground within 90 m, inside the outline).
def blobs(thr=float(os.environ.get("THR", 700)), most=int(os.environ.get("MAXPX", 60))):
    box = json.load(open(f"{D}/box.json"))
    w, h = int((box["e1"] - box["e0"]) / 10), int((box["n1"] - box["n0"]) / 10)
    subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-ot", "Float32", f"{D}/s2_10m.tif", f"{D}/s2.bin"],
                   check=True)
    a = np.fromfile(f"{D}/s2.bin", dtype=np.float32).reshape(-1, h, w)
    br = a[:3].mean(0)
    diff = br - ndimage.median_filter(br, size=9)
    ys, xs = np.mgrid[0:h, 0:w]
    E, N = box["e0"] + 5 + xs * 10, box["n1"] - 5 - ys * 10
    inside = ring.contains_points(np.c_[E.ravel(), N.ravel()]).reshape(h, w)
    lab, n = ndimage.label((diff > thr) & inside)
    out = []
    for i in range(1, n + 1):
        yy, xx = np.nonzero(lab == i)
        if len(yy) > most:
            continue
        wt = diff[yy, xx]
        cx, cy = (xx * wt).sum() / wt.sum(), (yy * wt).sum() / wt.sum()
        if len(yy) >= 2:
            ev, evec = np.linalg.eigh(np.cov(np.vstack([xx, -yy])))
            ang = np.degrees(np.arctan2(evec[0, 1], evec[1, 1])) % 180
            el = float(np.sqrt(ev[1] / max(ev[0], 1e-3)))
        else:
            ang, el = 0.0, 1.0
        out.append({"e": box["e0"] + 5 + cx * 10, "n": box["n1"] - 5 - cy * 10, "px": int(len(yy)), "axis": float(ang),
                    "elong": el})
    json.dump(out, open(f"{D}/blobs.json", "w"), indent=0)
    return out


def dead_ends():
    """Taxiway ends that join nothing (no other taxiway, apron or runway within 20 m): a shelter's loop or stub."""
    out = []
    for k, t in enumerate(TAXI):
        for end, nxt in ((t[0], t[1]), (t[-1], t[-2])):
            others = [o for j, o in enumerate(TAXI) if j != k] + APRON + RUNWAY
            if nearest(end, others)[0] > 20:
                out.append((end, bearing(nxt, end)))
    return out


if USE_BLOBS:
    BL = blobs()
    for i, (end, out_dir) in enumerate(dead_ends()):
        near = [b for b in BL if math.dist(end, (b["e"], b["n"])) < 55 and not taken((b["e"], b["n"]), 25)]
        near = [b for b in near if abs(((bearing(end, (b["e"], b["n"])) - out_dir + 180) % 360) - 180) < 70]
        if not near:
            continue
        b = max(near, key=lambda b: b["px"])
        p = (b["e"], b["n"])
        d = math.dist(p, end)
        add("shelter", p, bearing(p, end), f"at the end of a taxiway stub; a bright roof of {b['px']} {PIX}; "
            f"door toward the stub's end, {d:.0f} m (inferred)", SRCKEY, (30, 24))
    # Other bright roofs off the pavement (where OSM maps few buildings): buildings, larger ones by the pavement
    # hangars, sized by the blurred roof.
    for b in BL if USE_ROOFS else []:
        p = (b["e"], b["n"])
        # Off the pavement but by it (fields between the runways have bright soil: kept out by the 150 m).
        dp = nearest(p, PAVED)[0]
        if b["px"] < 3 or b["elong"] > 3 or taken(p, 30) or dp < 30 or dp > 120 or nearest(p, RUNWAY)[0] < 150 or nearest(
                p, X["road"])[0] < 15:
            continue
        a = b["px"] * 100.0
        lng, sh = math.sqrt(a * b["elong"]), math.sqrt(a / b["elong"])
        if b["px"] >= 12 and nearest(p, PAVED)[0] < 90:
            d, q = nearest(p, PAVED)
            h = b["axis"] if abs(((bearing(p, q) - b["axis"] + 180) % 360) - 180) <= 90 else b["axis"] + 180
            add("hangar", p, h, f"a large bright roof, {b['px']} {PIX} (about {lng:.0f} × {sh:.0f} m with "
                "the 10 m blur) by the pavement: a hangar (inferred)", SRCKEY, (max(lng, 30), max(sh, 25)))
        elif clear_of_runways(p, lng, sh):
            add("building", p, b["axis"], f"a bright roof, {b['px']} {PIX}; kind inferred; size from the "
                "blurred roof", SRCKEY, (max(lng, 15), max(sh, 10)))
# 3b. Placed by eye on the pictures at 1.3 m a pixel (manual/<icao>.json beside this script: [kind, e, n, grid
# heading, [along, across], note]; a note naming 2015 is from the Survey of Israel photo).
MANUAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "manual", ICAO.lower() + ".json")
if os.path.exists(MANUAL):
    for kind, e, n, h, size, note in json.load(open(MANUAL)):
        add(kind, (e, n), h, note + " (placed by eye; kind and size inferred)", "soi" if "2015" in note else "s2",
            size)
# 4. The tower: the airbase file's.
if B.get("tower"):
    from geo_any import to_utm
    p = to_utm([(B["tower"]["lat"], B["tower"]["lon"])])[0]
    add("tower", p, bearing(p, nearest(p, RUNWAY)[1]), "the airbase file's tower (airbases.md); faces the runway",
        B["tower"].get("source", "inferred"), (20, 12))
# 5. The home jets: in the shelters by the taxiways, nose out at the door (the imagery cannot show a jet: inferred).
if JET != "-":
    cand = [r for r in rows if r["kind"] == "shelter" and not r.get("store") and min(r["size_m"]) >= 16
            and nearest((r["e"], r["n"]), TAXI)[0] < 70]
    cand.sort(key=lambda r: nearest((r["e"], r["n"]), TAXI)[0])
    for r in cand[::2][:12]:
        add(JET, (r["e"], r["n"]), r["heading"], f"in a shelter by the taxiway, nose out at the door (inferred)",
            "inferred", shelter=id(r))
# 6. Ramp vehicles beside the player's first spot (left of it, clear of its way out).
sp, hdg = L["parking"][0], (L["parking_hdg"][0] - GAMMA)


def off(p, h, right, fwd):
    s, c = math.sin(math.radians(h)), math.cos(math.radians(h))
    return (p[0] + right * c + fwd * s, p[1] - right * s + fwd * c)


# The left side is the one away from the other spots.
side = -1.0
if len(L["parking"]) > 1:
    o = L["parking"][1]
    s, c = math.sin(math.radians(hdg)), math.cos(math.radians(hdg))
    side = -1.0 if (o[0] - sp[0]) * c - (o[1] - sp[1]) * s > 0 else 1.0
add("gpu", off(sp, hdg, 12 * side, -4), hdg, "beside the player's jet by the cockpit (inferred)", "inferred")
add("fuel_truck", off(sp, hdg, 26 * side, -14), hdg, "parked beside and behind the player's jet, clear of its way out "
    "(inferred)", "inferred")
add("extinguisher", off(sp, hdg, 10 * side, 3), hdg, "off the wingtip, as on a flight line (inferred)", "inferred")
# 7. The fence along the outline (inferred: an airbase is fenced).
add("fence", L["boundary"][0][0], 0, f"along the base's outline (`boundary` of airbases/{ICAO.lower()}.json)",
    "inferred", along="boundary")

# 8. The checks of sim_bases::tests::the_furniture_stands_clear: a footprint over 40 m from a runway's edge and over
# 25 m from the way out of each parking spot (iaf.ibx's FromTaxiPt path; the ramp vehicles 5 m). A row that fails
# is left out (and a jet whose shelter is left out).
sec, cur, lines = {}, None, open(f"{R}/assets/converted/own/iaf.ibx", encoding="latin-1").read().splitlines()
for k, ln in enumerate(lines):
    if ln.startswith("[") and k + 1 < len(lines) and f"({ICAO})" in lines[k + 1]:
        cur = ln
    elif ln.startswith("["):
        cur = None
    elif cur and "=" in ln:
        sec.update([ln.split("=", 1)])
out_path = [(float(sec[f"FromTaxiPtX{i}"]), float(sec[f"FromTaxiPtY{i}"])) for i in range(int(sec["TaxiWayPtsFrom"]))]
widths = [r.get("width_m", 45) for r in B["runways"]]


APRON_POLY = [Path(a) for a in L["apron"]]
TAXI_HALF = 12.0  # a taxiway's half width (m, inferred: 23 m wide)


def fails(r):
    p = (r["e"], r["n"])
    rad = math.hypot(*r["size_m"]) / 2 if "size_m" in r else 0.0
    # A building or shelter on a taxiway (its nearer half over the paved width), a loose building on an apron.
    if r["kind"] in ("shelter", "hangar", "building") and nearest(p, TAXI)[0] - TAXI_HALF < min(r["size_m"]) / 2:
        return "taxiway"
    if r["kind"] == "building" and any(a.contains_point(p) for a in APRON_POLY):
        return "apron"
    if min(nearest(p, [ln])[0] - w / 2 for ln, w in zip(RUNWAY, widths)) - rad <= 40:
        return "runway"
    gap = 5.0 if r["kind"] in ("gpu", "fuel_truck", "extinguisher") else 25.0
    for s in L["parking"]:
        if nearest(p, [[s] + out_path])[0] - rad <= gap:
            return "way out"
    return None


left = [(r, fails(r)) for r in rows if r["kind"] != "fence"]
gone = {id(r) for r, f in left if f}
gone |= {id(r) for r in rows if r.get("shelter") in gone}
for r, f in left:
    if f:
        print("left out:", r["kind"], round(r["e"]), round(r["n"]), f)
rows = [r for r in rows if id(r) not in gone]

PREFIX = {"shelter": "S", "hangar": "H", "building": "B", "tower": "T", "sunshade": "U", JET: "J", "gpu": "G", "fuel_truck": "FT",
          "extinguisher": "X", "tug": "TG", "fence": "FN"}
cnt = {}
for r in rows:
    cnt[r["kind"]] = cnt.get(r["kind"], 0) + 1
    r["ref"] = f"{PREFIX[r['kind']]}{cnt[r['kind']]}"
by_id = {id(r): r for r in rows}
for r in rows:
    if "shelter" in r:
        r["note"] = f"in the shelter {by_id[r.pop('shelter')]['ref']}, nose out at the door (inferred)"
    r.pop("store", None)
json.dump(rows, open(f"{D}/rows_utm.json", "w"), indent=1)
lls = to_ll([(r["e"], r["n"]) for r in rows])
out_rows = []
for r, (la, lo) in zip(rows, lls):
    o = {"ref": r["ref"], "kind": r["kind"], "lat": round(la, 7), "lon": round(lo, 7),
         "heading": round(r["heading"] + GAMMA) % 360}
    for k in ("size_m", "along", "osm"):
        if k in r:
            o[k] = r[k]
    o["source"], o["note"] = r["source"], r["note"]
    if r["kind"] == "fence":
        del o["lat"], o["lon"], o["heading"]
    out_rows.append(o)
from collections import Counter  # noqa: E402

print(ICAO, Counter(r["kind"] for r in rows))
tile = json.load(open(f"{D}/box.json")).get("tile", "")
doc = {
    "icao": ICAO,
    "survey": "2026-11-19",
    "frame": "WGS-84 lat / lon, true headings, metres (as data/airbases, data-formats.md §10)",
    "rows": out_rows,
    "footnotes": {k: v for k, v in {
        "s2": "ESA WorldCover 2021 Sentinel-2 RGBNIR composite, 10 m (CC BY 4.0), in assets/source/imagery/sentinel2/: "
              "bright objects against the ground within 90 m (modern-iaf/docs/base-furniture.md §2)",
        "osm": "OpenStreetMap contributors (ODbL 1.0), the scenery step's extract israel-and-palestine-260101.osm.pbf "
               f"and the airbases step's Overpass answer (assets/source/osm/airbases/{ICAO}.json)",
        "inferred": "our own reasoning",
        **({"soi": "Survey of Israel 2015 orthophoto, 2 m, in assets/source/imagery/mapi2015/ (Sentinel-2's tile "
                   "N31E035 is not on disk)"} if any(r["source"] == "soi" for r in rows) else {}),
    }.items() if any(r["source"] == k for r in rows)},
}
open(OUT, "w").write(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
