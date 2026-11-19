"""Ramon's furniture rows from the survey (Sentinel-2 objects, OSM ways): writes rows_utm.json and the data file.
usage: rows.py OUT_DATA_JSON"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import REPO, extra, layers, to_ll  # noqa: E402

D = os.environ["D"]  # the survey's work folder
B = json.load(open(f"{D}/blobs.json"))
L, X = layers(), extra()
osm_b = {str(oid): r for oid, r in X["building"]}
GAMMA = 0.85  # meridian convergence at Ramon (true = grid + GAMMA), as iaf.ibx's 334 for the file's 335


def seg_near(p, a, b):
    ax, ay, bx, by = *a, *b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy or 1)))
    return (ax + t * dx, ay + t * dy)


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
    """centre, long side, short side, long axis bearing (0-180) of an OSM ring."""
    pts = r[:-1] if r[0] == r[-1] else r
    c = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    sides = [(math.dist(a, b), bearing(a, b) % 180) for a, b in zip(pts, pts[1:] + pts[:1])]
    lng = max(sides)
    shorts = [s for s in sides if abs(((s[1] - lng[1] + 90) % 180) - 90) > 45]
    return c, lng[0], (max(s[0] for s in shorts) if shorts else lng[0]), lng[1]


def blob_size(b):
    a = b["px"] * 100.0
    return math.sqrt(a * b["elong"]), math.sqrt(a / b["elong"])


TAXI = L["taxiway"]
ACCESS = TAXI + X["road"]
rows = []


def add(kind, p, heading, note, source, size=None, **kw):
    r = {"kind": kind, "e": round(p[0], 1), "n": round(p[1], 1), "heading": round(heading % 360), "source": source,
         "note": note}
    if size:
        r["size_m"] = [round(size[0]), round(size[1])]
    r.update(kw)
    rows.append(r)
    return r


def door(p, lines=ACCESS):
    d, q = nearest(p, lines)
    return bearing(p, q), d


# 1. Shelters at the loop taxiways' ends: Sentinel-2 objects inside each loop's end (blob ids)
LOOP = [30, 31, 32, 41, 42, 59, 61, 63, 73, 79]
for i in LOOP:
    b = B[i]
    p = (b["e"], b["n"])
    h, d = door(p, TAXI)
    add("shelter", p, h, f"at the end of a loop taxiway; a bright roof of {b['px']} Sentinel-2 pixels (object s2:{i}); "
        f"door toward the loop, {d:.0f} m (inferred)", "s2", (30, 24), id=f"s2:{i}")
# 2. Shelters off the taxiway network, SW and NE dispersals (bright roofs; kind inferred)
OFF = [66, 68, 74, 75, 81, 86, 89, 90, 85, 27]
for i in OFF:
    b = B[i]
    p = (b["e"], b["n"])
    h, d = door(p)
    add("shelter", p, h, f"a bright roof of {b['px']} Sentinel-2 pixels off the mapped taxiways (object s2:{i}); kind "
        f"inferred (a shelter or a small store); door toward the nearest track, {d:.0f} m (inferred)", "s2",
        (30, 24), id=f"s2:{i}")
# 3. OSM building squares of 21-29 m in the NE dispersal: shelters (two of them sit on bright roofs s2:43, s2:49)
SQ = ["1082924563", "1082924565", "1082924566", "1082924567", "1082924568", "1082924569", "1082924570",
      "1082924572", "1082924573", "1082924574", "1082924575", "1082924580", "1082924581", "1082924582", "1082924583"]
for oid in SQ:
    c, lng, sh, ax = foot(osm_b[oid])
    if any(r["kind"] == "shelter" and math.dist(c, (r["e"], r["n"])) < 30 for r in rows):
        # the loop-end object s2:41 is this square: keep one row, with OSM's footprint
        r = next(r for r in rows if r["kind"] == "shelter" and math.dist(c, (r["e"], r["n"])) < 30)
        r["note"] += f"; OSM way/{oid} maps it {lng:.0f} × {sh:.0f} m"
        r["osm"] = f"way/{oid}"
        continue
    h, d = door(c)
    hit = [i for i in (43, 49) if math.dist(c, (B[i]["e"], B[i]["n"])) < 25]
    seen = f"; a bright roof there (s2:{hit[0]})" if hit else "; not bright in Sentinel-2 (an earth-covered roof, inferred)"
    add("shelter", c, h, f"OSM building {lng:.0f} × {sh:.0f} m in the NE dispersal{seen}; kind inferred from the size "
        f"and place; door toward the nearest track, {d:.0f} m (inferred)", "osm", (lng, sh), osm=f"way/{oid}")
# 4. The alert compound north of 07L/25R: OSM's 7 'hangar' ways (25-32 m), fenced (OSM fences), 3 gates, own link
for k, ring in enumerate(L["hangar"]):
    c, lng, sh, ax = foot(ring)
    h, d = door(c, TAXI)
    add("shelter", c, h, f"OSM hangar {lng:.0f} × {sh:.0f} m in the fenced compound north of 07L/25R with its own "
        f"link to the runway: alert shelters (inferred); door toward the link, {d:.0f} m (inferred)", "osm",
        (lng, sh), osm=json.load(open(f"{REPO}/modern-iaf/data/airbases/llrm.json"))
        ["shelters"][k]["osm"])
# 5. Hangars: the large OSM buildings and the core's large bright roofs (maintenance, inferred)
for oid in ["1082924562", "1082924571", "1082924576", "1082924578", "1082924579", "1082924564"]:
    c, lng, sh, ax = foot(osm_b[oid])
    h, d = door(c)
    add("hangar", c, ax, f"OSM building {lng:.0f} × {sh:.0f} m; a hangar or workshop (inferred from the size); "
        f"heading = the long side", "osm", (lng, sh), osm=f"way/{oid}")
for i in [71, 72, 76, 77]:
    b = B[i]
    lng, sh = blob_size(b)
    add("hangar", (b["e"], b["n"]), b["axis"], f"a large bright roof in the technical area, {b['px']} Sentinel-2 "
        f"pixels (object s2:{i}, about {lng:.0f} × {sh:.0f} m with the 10 m blur); a maintenance hangar (inferred); "
        "heading = the long side", "s2", (max(lng, 30), max(sh, 25)), id=f"s2:{i}")
# 6. The tower: the compound midfield between 07R/25L and the parallel taxiway (inferred)
b = B[37]
add("tower", (b["e"], b["n"]), bearing((b["e"], b["n"]), nearest((b["e"], b["n"]), L["runway"])[1]),
    "a walled compound midfield between 07R/25L and the parallel taxiway with a bright 9-pixel roof (s2:37): the "
    "usual place of a tower (inferred; airbases.md §7: Ramon's tower is open); faces the runway", "s2", (20, 12),
    id="s2:37")
# 7. Other buildings (generic): the smaller OSM buildings and the technical area's bright roofs
for oid in ["1082924577", "1385950366", "1385950370", "1385950371"]:
    c, lng, sh, ax = foot(osm_b[oid])
    add("building", c, ax, f"OSM building {lng:.0f} × {sh:.0f} m", "osm", (lng, sh), osm=f"way/{oid}")
for i in [58, 64, 65, 83, 87, 88, 91, 93, 97, 99]:
    b = B[i]
    lng, sh = blob_size(b)
    add("building", (b["e"], b["n"]), b["axis"], f"a bright roof, {b['px']} Sentinel-2 pixels (object s2:{i}); "
        "kind inferred; size from the blurred roof", "s2", (max(lng, 15), max(sh, 10)), id=f"s2:{i}")
# 8. Sunshade line: the 370 m dark line (a roof's shadow) beside the NE row of OSM helipads (Apache line)
a, b2 = (660780.0, 3404720.0), (661024.0, 3405000.0)
mid = ((a[0] + b2[0]) / 2, (a[1] + b2[1]) / 2)
add("sunshade", mid, bearing(a, b2), "a straight dark line 370 m long in Sentinel-2 beside the NE row of OSM "
    "helipads: the shadow of a long roof on posts (inferred); heading = the line's; repeat the module along it",
    "s2", (round(math.dist(a, b2)), 15))
# 9. Parked F-16I: inside the loop-end shelters and two alert shelters, nose at the door
for r in [r for r in rows if r["kind"] == "shelter" and r.get("id", "").split(":")[-1] in map(str, LOOP)]:
    add("f16i", (r["e"], r["n"]), r["heading"], f"in the shelter {r.get('id')}, nose out at the door (the imagery "
        "cannot show a jet: inferred)", "inferred")
alert = [r for r in rows if r["kind"] == "shelter" and "alert" in r["note"]]
for r in sorted(alert, key=lambda r: r["e"])[:2]:
    add("f16i", (r["e"], r["n"]), r["heading"], f"alert jet in {r['osm']} (inferred)", "inferred")
# 10. Ramp vehicles at the player's spot (beside, never on the way out) and a tug at the alert compound
sp = L["parking"][0]
hdg = 334.0  # the spot's grid heading (iaf.ibx HangarPtHdg0)


def off(p, h, right, fwd):
    s, c = math.sin(math.radians(h)), math.cos(math.radians(h))
    return (p[0] + right * c + fwd * s, p[1] - right * s + fwd * c)


add("gpu", off(sp, hdg, -12, -4), hdg, "beside the player's jet, left of the cockpit (inferred)", "inferred")
add("fuel_truck", off(sp, hdg, -26, -14), hdg, "parked left and behind the player's jet, clear of its way out (inferred)",
    "inferred")
add("extinguisher", off(sp, hdg, -10, 3), hdg, "off the left wingtip, as on a flight line (inferred)", "inferred")
qa = sorted(alert, key=lambda r: r["e"])[0]
add("tug", off((qa["e"], qa["n"]), qa["heading"], 12, 10), qa["heading"], "outside the first alert shelter "
    "(inferred)", "inferred")
# 11. The perimeter fence: OSM tags the aerodrome's outline as a fence
add("fence", L["boundary"][0][0], 0, "along the base's outline (`boundary` of airbases/llrm.json): OSM tags the "
    "aerodrome way barrier=fence", "osm", None, along="boundary", osm="way/292211017")

PREFIX = {"shelter": "S", "hangar": "H", "building": "B", "tower": "T", "sunshade": "U", "f16i": "J", "gpu": "G",
          "fuel_truck": "FT", "extinguisher": "X", "tug": "TG", "fence": "FN"}
cnt = {}
for r in rows:
    cnt[r["kind"]] = cnt.get(r["kind"], 0) + 1
    r["ref"] = f"{PREFIX[r['kind']]}{cnt[r['kind']]}"
for r in rows:
    if r["kind"] == "f16i" and "in the shelter" in r["note"]:
        sh = next(x for x in rows if x["kind"] == "shelter" and x["e"] == r["e"] and x["n"] == r["n"])
        r["note"] = r["note"].replace(f"in the shelter {sh.get('id')}", f"in the shelter {sh['ref']}")
    if r["kind"] == "f16i" and "alert jet" in r["note"]:
        sh = next(x for x in rows if x["kind"] == "shelter" and x["e"] == r["e"] and x["n"] == r["n"])
        r["note"] = f"alert jet in the shelter {sh['ref']} ({sh['osm']}), nose out (inferred)"
    if r["kind"] == "tug":
        r["note"] = f"outside the alert shelter {qa['ref']} (inferred)"
# checks: parked jets and vehicles against every taxiway centreline and the taxi paths of iaf.ibx
sec, cur = {}, None
for ln in open(f"{REPO}/assets/converted/own/iaf.ibx", encoding="latin-1"):
    ln = ln.strip()
    if ln.startswith("["):
        cur = ln
    elif cur == "[Ramon]" and "=" in ln:
        k, v = ln.split("=", 1)
        sec[k] = v


def path(pre, n):
    return [(float(sec[f"{pre}X{i}"]), float(sec[f"{pre}Y{i}"])) for i in range(int(sec[n]))]


paths = [[sp] + path("FromTaxiPt", "TaxiWayPtsFrom"), path("ToTaxiPt", "TaxiWayPtsTo") + [sp]]
report = []
for r in rows:
    if r["kind"] in ("f16i", "gpu", "fuel_truck", "extinguisher", "tug"):
        p = (r["e"], r["n"])
        dt, _ = nearest(p, TAXI)
        dp, _ = nearest(p, paths)
        ds = math.dist(p, sp)
        r["_check"] = {"taxiway_m": round(dt), "taxi_path_m": round(dp), "player_spot_m": round(ds)}
        report.append((r["ref"], round(dt), round(dp), round(ds)))
for x in report:
    print(x)
json.dump(rows, open(f"{D}/rows_utm.json", "w"), indent=1)

# the data file: WGS-84 places, true headings, as data/airbases (data-formats.md §10)
lls = to_ll([(r["e"], r["n"]) for r in rows])
out_rows = []
for r, (la, lo) in zip(rows, lls):
    o = {"ref": r["ref"], "kind": r["kind"], "lat": round(la, 7), "lon": round(lo, 7), "heading": round((r["heading"] + GAMMA) % 360)}
    for k in ("size_m", "along", "osm", "id"):
        if k in r:
            o[k] = r[k]
    o["source"] = r["source"]
    o["note"] = r["note"]
    if r["kind"] == "fence":
        del o["lat"], o["lon"], o["heading"]
    out_rows.append(o)
from collections import Counter  # noqa: E402

print(Counter(r["kind"] for r in rows))
doc = {
    "icao": "LLRM",
    "survey": "2026-11-17",
    "frame": "WGS-84 lat / lon, true headings, metres (as data/airbases, data-formats.md §10)",
    "rows": out_rows,
    "footnotes": {
        "s2": "ESA WorldCover 2021 Sentinel-2 RGBNIR composite, 10 m (CC BY 4.0), tile N30E034 in assets/source/imagery/"
              "sentinel2/: bright objects against the ground within 90 m (s2:<n> = the survey's object number, "
              "modern-iaf/docs/base-furniture.md §2)",
        "osm": "OpenStreetMap contributors (ODbL 1.0), the scenery step's extract israel-and-palestine-260101.osm.pbf "
               "and the airbases step's Overpass answer (assets/source/osm/airbases/LLRM.json)",
        "inferred": "our own reasoning",
    },
}
open(sys.argv[1], "w").write(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
