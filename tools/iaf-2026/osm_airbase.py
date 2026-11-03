#!/usr/bin/env python3
"""IAF 2026's airbase layouts from OpenStreetMap (iaf-2026/docs/airbases.md).

Fetches each base's aeroway features from the Overpass API (one query per base; the raw answer is cached in
assets/source/osm/airbases/<icao>.json) and OurAirports' airports / runways tables (cached in
assets/source/ourairports/), and writes iaf-2026/data/airbases/<icao>.json. The points OSM lacks (the parking spots,
a missing tower) are placed by eye on the overlay pictures and kept in PLACED below.

    python3 -I tools/iaf-2026/osm_airbase.py [--refetch] [ICAO ...]
    python3 -I tools/iaf-2026/osm_airbase.py overlay OUT_DIR [ICAO ...]   # the layout drawn on Sentinel-2 (+ 2015)

Data © OpenStreetMap contributors, ODbL 1.0; OurAirports, public domain.
"""

import csv
import json
import math
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from real_runways import DECLINATION, designator  # noqa: E402  (tools/real_runways.py: the same rule as the CSV)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OSM_CACHE = os.path.join(ROOT, "assets/source/osm/airbases")
OA_CACHE = os.path.join(ROOT, "assets/source/ourairports")
OUT = os.path.join(ROOT, "iaf-2026/data/airbases")
SHEETS = os.path.join(ROOT, "assets/source/imagery/mapi2015")
SHEET_INDEX = os.path.join(ROOT, "assets/converted/imagery/.work/mapi2015/sheets.tsv")
# The public Overpass instances, tried in order, once each (no retries): the main one is often at capacity.
ENDPOINTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
OA_URL = "https://davidmegginson.github.io/ourairports-data/"
AGENT = "linux-iaf-airbases/1.0"

# ICAO -> the OSM aerodrome way (aeroway=aerodrome) and its bounds (south, west, north, east), which bound the query.
AERODROMES = {
    "LLRM": (292211017, (30.7304585, 34.6407245, 30.7971547, 34.700694)),
    "LLHB": (292211006, (31.212303, 34.6047645, 31.2676059, 34.7013454)),
    "LLNV": (292186859, (31.1718032, 34.9792587, 31.2241115, 35.0813775)),
    "LLRD": (292211011, (32.6537286, 35.1580837, 32.6782826, 35.202065)),
}

QUERY = """[out:json][timeout:180][bbox:%s];
(way(%d); nwr["aeroway"]; nwr["building"~"^(hangar|bunker)$"]; nwr["military"="bunker"];
 nwr["man_made"~"^(tower|mast)$"];);
out tags geom;"""

# Runway ways read as taxiways: way -> why (the note the taxiway carries).
AS_TAXIWAY = {
    130240671: "OSM aeroway=runway without a ref: the 21 m strip beside Nevatim's 08R/26L (OurAirports' 08R/26L, 70 ft "
               "wide; OurAirports calls OSM's 08R/26L 08C/26C); Wikipedia lists three runways without it (inferred: "
               "the parallel taxiway, as tools/real_runways.py leaves it out)",
}

# Where the declared runway starts (runway_start_m, inferred): the OSM ways run on over the paved overruns, so where a
# way is longer than OurAirports' length, the declared runway is taken to start at the first taxiway that joins it (a
# taxiway node within half the width + 15 m of the centreline), if that lies within the extra length + 150 m (on all
# seven such runways the two ends' entries add up to the extra length within 110 m, iaf-2026/docs/airbases.md §4).
# The lineup point is the B2b compiler's (Rust), from runway_start_m and the end's heading.

# Points OSM lacks, placed by eye on the overlay pictures (inferred; each a judgement call for the user,
# iaf-2026/docs/airbases.md §5). parking: unit id -> (lat, lon, true heading of the nose). tower: (lat, lon), or None
# where no picture shows it (open).
PLACED = {
    # The centre of the paved pad by 07R/25L's western link (OSM apron 1496591869), nose along the pad toward the
    # runway; the shelters at the loop ends are too small for the 10 m picture.
    "LLRM": {"parking": {"f16i": (30.769935, 34.6594868, 335)}, "tower": None},
    # The south ends of the two sunshade rows by the parallel taxiway (OSM aprons 1157437942, 1157437936), nose to
    # their exit; which squadron uses which row is open.
    "LLHB": {"parking": {"f15i": (31.2405172, 34.6612147, 195), "f16i": (31.2401938, 34.6624651, 195)},
             "tower": None},
    # The east end of the middle lane of the apron north of 08R/26L (OSM apron 1089049618, paved by 2021), nose
    # along the lane to the apron's west exit. Tower: the compound between 08L/26R and 08R/26L midfield (2015 photo).
    "LLNV": {"parking": {"f35i": (31.2086757, 35.0264028, 256)}, "tower": (31.2058009, 35.0125383)},
    # The free west part of the base's one OSM apron (1328724315, north of 09/27; its middle holds OSM buildings),
    # nose to the taxiway south of it.
    "LLRD": {"parking": {"f16d": (32.6679365, 35.1765842, 176)}, "tower": None},
}

def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=240) as r:
        return r.read()


def fetch_osm(icao, refetch):
    path = os.path.join(OSM_CACHE, icao + ".json")
    if os.path.exists(path) and not refetch:
        return json.load(open(path))
    way, box = AERODROMES[icao]
    body = urllib.parse.urlencode({"data": QUERY % (",".join(map(str, box)), way)}).encode()
    err = None
    for url in ENDPOINTS:
        try:
            raw = get(url, body)
            data = json.loads(raw)
            if "error" in data.get("remark", ""):  # a timed-out query answers 200 with part of the data
                raise ValueError(data["remark"])
            break
        except (OSError, ValueError) as e:
            err = e
    else:
        sys.exit("%s: Overpass failed (%s); try again later" % (icao, err))
    os.makedirs(OSM_CACHE, exist_ok=True)
    with open(path, "wb") as f:
        f.write(raw)
    return data


def fetch_oa(name, refetch):
    path = os.path.join(OA_CACHE, name)
    if not os.path.exists(path) or refetch:
        raw = get(OA_URL + name)
        os.makedirs(OA_CACHE, exist_ok=True)
        with open(path, "wb") as f:
            f.write(raw)
    return list(csv.DictReader(open(path, encoding="utf-8")))


def dist(a, b):
    """Metres between two (lat, lon) on the sphere (R 6371 km; ≤ 0.3 % off WGS-84 at these lengths)."""
    la0, lo0, la1, lo1 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la1 - la0) / 2) ** 2 + math.cos(la0) * math.cos(la1) * math.sin((lo1 - lo0) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def bearing(a, b):
    """True initial bearing from a to b, degrees."""
    la0, lo0, la1, lo1 = map(math.radians, (a[0], a[1], b[0], b[1]))
    y = math.sin(lo1 - lo0) * math.cos(la1)
    x = math.cos(la0) * math.sin(la1) - math.sin(la0) * math.cos(la1) * math.cos(lo1 - lo0)
    return math.degrees(math.atan2(y, x)) % 360.0


def along(a, b, m):
    """The point m metres from a toward b (linear in lat / lon: exact enough over a runway)."""
    t = m / dist(a, b)
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def turn(x, y):
    """The angle between two headings, degrees (0–180)."""
    return abs((x - y + 180.0) % 360.0 - 180.0)


def num(name):
    """A designator's number ("07L" -> 7)."""
    return int(re.match(r"\d+", name).group())


def r7(p):
    return [round(p[0], 7), round(p[1], 7)]


def pts(e):
    return [r7((g["lat"], g["lon"])) for g in e["geometry"]]


def ring(e):
    """A closed way's ring, or a multipolygon's first outer ring (its outer ways joined end to end)."""
    if e["type"] == "way":
        return pts(e)
    parts = [[(g["lat"], g["lon"]) for g in m["geometry"]] for m in e["members"] if m.get("role") == "outer"]
    out = parts.pop(0)
    while parts and out[0] != out[-1]:
        for i, p in enumerate(parts):
            if out[-1] in (p[0], p[-1]):
                out += (p if p[0] == out[-1] else p[::-1])[1:]
                parts.pop(i)
                break
        else:
            break
    return [r7(p) for p in out]


def centre(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def osm_id(e):
    return "%s/%d" % (e["type"], e["id"])


def named(e, rec):
    """rec with the element's name / ref tags."""
    for k in ("name", "ref"):
        if k in e["tags"]:
            rec[k] = e["tags"][k]
    return rec


def track(p, q, t):
    """t in metres along the line p → q and across it (absolute)."""
    r, b = dist(p, t), math.radians(bearing(p, t) - bearing(p, q))
    return r * math.cos(b), abs(r * math.sin(b))


def entry(p, q, half, taxi_points):
    """Metres from end p toward q to the first taxiway node on the runway (None: no taxiway joins it)."""
    length = dist(p, q)
    on = [x for x, y in (track(p, q, t) for t in taxi_points) if -20 < x < length and y < half + 15]
    return max(min(on), 0.0) if on else None


def runway(e, oa_rows, taxi_points):
    """A runway way -> its record: the ends low number first, each with its true heading and where the runway starts."""
    g = pts(e)
    a, b = g[0], g[-1]
    tags = e["tags"]

    # OurAirports' row on the same line (both its ends within 150 m of the way's centreline line): by place, not by
    # name (at Nevatim OurAirports' 08R is OSM's untagged strip and its 08C is OSM's 08R).
    def on_line(r):
        if not (r["le_latitude_deg"] and r["he_latitude_deg"]):
            return False
        ends = ((float(r[k + "_latitude_deg"]), float(r[k + "_longitude_deg"])) for k in ("le", "he"))
        return all(track(a, b, t)[1] < 150 for t in ends)

    oa = next((r for r in oa_rows if on_line(r)), None)
    ref = tags.get("ref", "")
    if "/" in ref:
        names, src = ref.split("/"), {"designator": "osm"}
    elif oa:
        names, src = [oa["le_ident"], oa["he_ident"]], {"designator": "oa"}
    else:
        names, src = designator("", a[0], a[1], b[0], b[1]).split("/"), {"designator": "inferred"}
    names.sort(key=num)
    # The low number's end is the one whose heading is nearest its number (magnetic, the declination added).
    if turn(bearing(a, b), num(names[0]) * 10 + DECLINATION) > turn(bearing(b, a), num(names[0]) * 10 + DECLINATION):
        a, b = b, a
    src["ends"] = "osm"
    width = tags.get("width")
    if width:
        width, src["width_m"] = float(width), "osm"
    elif oa and oa["width_ft"]:
        width, src["width_m"] = round(float(oa["width_ft"]) * 0.3048, 1), "oa"
    else:
        width, src["width_m"] = 45.0, "open"
    published = float(oa["length_ft"]) * 0.3048 if oa and oa["length_ft"] else None
    ends = []
    for name, p, q in ((names[0], a, b), (names[1], b, a)):
        side = "le" if oa and dist(p, (float(oa["le_latitude_deg"]), float(oa["le_longitude_deg"]))) < dist(
            p, (float(oa["he_latitude_deg"]), float(oa["he_longitude_deg"]))) else "he"
        disp = 0.0
        if oa and oa[side + "_displaced_threshold_ft"]:
            disp = round(float(oa[side + "_displaced_threshold_ft"]) * 0.3048, 1)
        elev = oa[side + "_elevation_ft"] if oa else ""
        h = bearing(p, q)
        enter = entry(p, q, width / 2, taxi_points)
        start = enter if enter is not None and published and enter <= dist(a, b) - published + 150 else 0.0
        ends.append({"designator": name, "lat": p[0], "lon": p[1], "heading": round(h, 2),
                     "displaced_threshold_m": disp, "taxiway_entry_m": None if enter is None else round(enter),
                     "runway_start_m": round(start),
                     "elevation_m": round(float(elev) * 0.3048, 1) if elev else None, "ils": None,
                     "sources": {"lat": "osm", "lon": "osm", "heading": "osm",
                                 "displaced_threshold_m": "oa" if oa else "open",
                                 "elevation_m": "oa" if elev else "open", "ils": "open",
                                 "taxiway_entry_m": "osm", "runway_start_m": "inferred"}})
    if oa and oa["length_ft"]:
        src["length_published_m"] = "oa"
    src["length_m"] = "osm"  # the way's ends apart
    src["surface"] = "osm" if "surface" in tags else "open"
    return {"designator": "/".join(names), "osm": osm_id(e), "length_m": round(dist(a, b), 1),
            "length_published_m": round(published) if published else None,
            "width_m": width,
            "surface": tags.get("surface"), "ends": ends, "sources": src}


def extract(icao, data, oa_airports, oa_runways):
    els = [e for e in data["elements"] if "tags" in e]
    ad = next(e for e in els if e["type"] == "way" and e["id"] == AERODROMES[icao][0])
    oa_ap = next(r for r in oa_airports if r["ident"] == icao)
    oa_rw = [r for r in oa_runways if r["airport_ident"] == icao]

    def tagged(v):
        return [e for e in els if e["tags"].get("aeroway") == v]

    def lines(v):
        """The open ways tagged aeroway=v: centrelines. An area (a closed way or a relation) is left out, named."""
        out = []
        for e in tagged(v):
            if e["type"] == "way" and e["geometry"][0] != e["geometry"][-1]:
                out.append(e)
            else:
                print("%s: %s %s is an area, not a centreline: left out" % (icao, v, osm_id(e)))
        return out

    def point(e):
        return {"osm": osm_id(e), "lat": round(e["lat"], 7), "lon": round(e["lon"], 7), "source": "osm"}

    taxiways = []
    for e in lines("taxiway") + [e for e in lines("runway") if e["id"] in AS_TAXIWAY]:
        t = named(e, {"osm": osm_id(e), "points": pts(e), "source": "osm"})
        if e["id"] in AS_TAXIWAY:
            t["note"] = AS_TAXIWAY[e["id"]]
        if "width" in e["tags"]:
            t["width_m"] = float(e["tags"]["width"])
        taxiways.append(t)
    shelters = []
    for e in els:
        t = e["tags"]
        kind = ("hangar" if "hangar" in (t.get("aeroway"), t.get("building"))
                else "shelter" if "bunker" in (t.get("building"), t.get("military")) else None)
        if kind and e["type"] != "node":
            shelters.append(named(e, {"kind": kind, "osm": osm_id(e), "polygon": ring(e), "source": "osm"}))
    lights = [{"kind": e["tags"].get("navigationaid", e["tags"]["aeroway"]), **point(e)} for e in els
              if e["type"] == "node" and e["tags"].get("aeroway") in ("papi", "vasi", "navigationaid")]
    towers = [e for e in els if e["tags"].get("aeroway") in ("control_tower", "tower")
              or e["tags"].get("tower:type") == "airport_control"]
    placed = PLACED[icao]
    if towers:
        t = towers[0]
        c = (t["lat"], t["lon"]) if t["type"] == "node" else centre(ring(t))
        tower = {"osm": osm_id(t), "lat": round(c[0], 7), "lon": round(c[1], 7), "source": "osm"}
    elif placed["tower"]:
        tower = {"lat": placed["tower"][0], "lon": placed["tower"][1], "source": "inferred"}
    else:
        tower = None
    tags = ad["tags"]
    return {
        "icao": icao,
        "name": {"en": tags.get("name:en", tags.get("name")), "he": tags.get("name:he", tags.get("name"))},
        "osm": osm_id(ad),
        "elevation_m": round(float(oa_ap["elevation_ft"]) * 0.3048),
        "reference": {"lat": round(float(oa_ap["latitude_deg"]), 7), "lon": round(float(oa_ap["longitude_deg"]), 7)},
        "boundary": ring(ad),
        "runways": [runway(e, oa_rw, [p for t in taxiways for p in t["points"]]) for e in lines("runway")
                    if e["id"] not in AS_TAXIWAY],
        "stopways": [{"osm": osm_id(e), "points": pts(e), "source": "osm"} for e in lines("stopway")],
        "taxiways": taxiways,
        "holding_positions": [point(e) for e in tagged("holding_position") if e["type"] == "node"],
        "aprons": [named(e, {"osm": osm_id(e), "polygon": ring(e), "source": "osm"}) for e in tagged("apron")],
        "shelters": shelters,
        "tower": tower,
        "lights": lights,
        "parking": [{"unit": u, "lat": p[0], "lon": p[1], "heading": p[2], "source": "inferred"}
                    for u, p in placed["parking"].items()],
        "sources": {"name": "osm", "boundary": "osm", "elevation_m": "oa", "reference": "oa",
                    **({} if tower else {"tower": "open"})},
        "footnotes": {
            "osm": "OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright (Overpass API, "
                   "data of %s); each item's \"osm\" names its element: https://www.openstreetmap.org/<osm>"
                   % data["osm3s"]["timestamp_osm_base"][:10],
            "oa": "OurAirports, airports.csv and runways.csv (public domain), " + OA_URL,
        },
    }


def write(icao, base):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, icao.lower() + ".json")
    with open(path, "w", encoding="utf-8") as f:
        # One line per point: a [lat, lon] pair stays on its line.
        text = json.dumps(base, ensure_ascii=False, indent=1)
        f.write(re.sub(r"\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]", r"[\1, \2]", text) + "\n")
    n = {k: len(base[k]) for k in ("runways", "stopways", "taxiways", "holding_positions", "aprons", "shelters",
                                   "lights", "parking")}
    print("wrote", os.path.relpath(path, ROOT), n, "tower" if base["tower"] else "no tower")


# --- the overlay pictures: the layout drawn on Sentinel-2 and the Survey of Israel 2015 photo (ImageMagick, GDAL) --

PX_M = 2.0  # metres per pixel of the pictures (the Survey of Israel photo's own; Sentinel-2's are 10 m)
# Every base is drawn on Sentinel-2 (ESA WorldCover's 2021 composite, the tiles the imagery step reads,
# docs/imagery.md), and the bases the Survey of Israel 2015 photo shows also on that: it blanks the other three
# (fields or desert drawn over them).
MAPI_SHOWS = {"LLNV"}
S2_TILE = ("https://esa-worldcover-s2.s3.eu-central-1.amazonaws.com/rgbnir/2021/N%02d/"
           "ESA_WorldCover_10m_2021_v200_N%02dE%03d_S2RGBNIR.tif")
M_LAT = 111320.0  # metres per degree of latitude (and of longitude × cos lat), enough for a picture
# The picture's lineup point: this far in from runway_start_m (iaf-sim's runway start, data-formats.md §5; B2b's
# compiler sets the game's).
LINEUP_M = 100.0


def sheets_for(box):
    """The Survey of Israel sheets whose ITM extent meets box (x0, y0, x1, y1), as GDAL /vsizip/ paths."""
    out = []
    for r in csv.reader(open(SHEET_INDEX), delimiter="\t"):
        x0, y0, x1, y1 = map(float, r[4].split())
        if x0 < box[2] and box[0] < x1 and y0 < box[3] and box[1] < y1:
            out.append("/vsizip/%s/%s/%s" % (SHEETS, r[0], r[3]))
    return out


def overlay(icao, outdir, mapi):
    """The picture on the Survey of Israel photo (mapi) or on Sentinel-2; written as <icao>[_2015].png / .jpg."""
    base = json.load(open(os.path.join(OUT, icao.lower() + ".json")))
    every = [[e["lat"], e["lon"]] for r in base["runways"] for e in r["ends"]]
    every += [p for t in base["taxiways"] for p in t["points"]]
    every += [p for a in base["aprons"] + base["shelters"] for p in a["polygon"]]
    m = 250.0 / M_LAT
    la0, la1 = min(p[0] for p in every) - m, max(p[0] for p in every) + m
    cosl = math.cos(math.radians((la0 + la1) / 2))
    lo0, lo1 = min(p[1] for p in every) - m / cosl, max(p[1] for p in every) + m / cosl
    dla, dlo = PX_M / M_LAT, PX_M / (M_LAT * cosl)
    w, h = round((lo1 - lo0) / dlo), round((la1 - la0) / dla)
    os.makedirs(outdir, exist_ok=True)
    stem = os.path.join(outdir, icao.lower() + ("_2015" if mapi else ""))
    # The warped photo is kept for reruns under its extent's name: a changed layout makes a new one.
    photo = "%s_photo_%.6f_%.6f_%.6f_%.6f_%d.tif" % (stem, la0, lo0, la1, lo1, PX_M)
    if not os.path.exists(photo):
        if mapi:
            corners = "".join("%r %r\n" % (lo, la) for lo in (lo0, lo1) for la in (la0, la1))
            itm = [list(map(float, s.split()[:2])) for s in subprocess.run(
                ["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", "EPSG:2039"], input=corners, capture_output=True,
                text=True, check=True).stdout.splitlines()]
            box = (min(p[0] for p in itm), min(p[1] for p in itm), max(p[0] for p in itm), max(p[1] for p in itm))
            src = ["-s_srs", "EPSG:2039", *sheets_for(box)]
        else:
            src = ["-b", "1", "-b", "2", "-b", "3", "-co", "PHOTOMETRIC=RGB"]
            src += ["/vsicurl/" + S2_TILE % (la, la, lo) for la in range(math.floor(la0), math.floor(la1) + 1)
                    for lo in range(math.floor(lo0), math.floor(lo1) + 1)]
        subprocess.run(["gdalwarp", "-q", "-overwrite", "-t_srs", "EPSG:4326", "-te", repr(lo0), repr(la0), repr(lo1),
                        repr(la1), "-ts", str(w), str(h), "-r", "cubic", *src, photo], check=True,
                       env={**os.environ, "CPL_VSIL_CURL_ALLOWED_EXTENSIONS": ".tif"})
    # Sentinel-2 is reflectance × 10⁴: its red, green and blue stretched to bytes.
    look = [] if mapi else ["-channel", "RGB", "-contrast-stretch", "0.5%x0.5%", "+channel", "-depth", "8"]
    source = ("Survey of Israel 2015 photo (2 m)" if mapi
              else "Sentinel-2 2021 (10 m, CC BY 4.0)")

    def xy(p):
        return ((p[1] - lo0) / dlo, (la1 - p[0]) / dla)

    def path(points):
        return " ".join("%.1f,%.1f" % xy(p) for p in points)

    def line(points, colour, width):
        return ["-fill", "none", "-stroke", colour, "-strokewidth", str(width), "-draw", "polyline " + path(points)]

    def area(points, colour):
        return ["-fill", colour + "40", "-stroke", colour, "-strokewidth", "2", "-draw", "polygon " + path(points)]

    def label(p, text, colour, size, below=False):
        x, y = xy(p)
        at = "+%d+%d" % (x + 9, y + size + 6 if below else y - 9)
        return ["-pointsize", str(size), "-stroke", "black", "-strokewidth", "4", "-fill", colour, "-annotate", at,
                text, "-stroke", "none", "-annotate", at, text]

    def dot(p, colour, r):
        x, y = xy(p)
        return ["-fill", colour, "-stroke", "black", "-strokewidth", "2",
                "-draw", "circle %.1f,%.1f %.1f,%.1f" % (x, y, x + r, y)]

    def ahead(p, hdg, n):
        return (p[0] + math.cos(math.radians(hdg)) * n / M_LAT, p[1] + math.sin(math.radians(hdg)) * n / M_LAT / cosl)

    d = []
    for a in base["aprons"]:
        d += area(a["polygon"], "#ffd000")
    for s in base["shelters"]:
        d += area(s["polygon"], "#ff00ff")
    for s in base["stopways"]:
        d += line(s["points"], "#ff8000", 3)
    for t in base["taxiways"]:
        d += line(t["points"], "#00e0ff", 3)
    for r in base["runways"]:
        a, b = ((e["lat"], e["lon"]) for e in r["ends"])
        for s in (90, -90):  # the edges, half the width each side of the centreline
            d += line([ahead(a, r["ends"][0]["heading"] + s, r["width_m"] / 2),
                       ahead(b, r["ends"][0]["heading"] + s, r["width_m"] / 2)], "#ff3030", 2)
        d += line([a, b], "#ff3030", 1)
    for t in base["taxiways"]:
        if "ref" in t or "name" in t:
            d += label(t["points"][len(t["points"]) // 2], t.get("ref", t.get("name")), "#00e0ff", 20)
    for p in base["holding_positions"]:
        d += dot((p["lat"], p["lon"]), "#ffffff", 4)
    for p in base["lights"]:
        d += dot((p["lat"], p["lon"]), "#ffff00", 4)
    for r in base["runways"]:
        for e in r["ends"]:
            far = next(f for f in r["ends"] if f is not e)
            start = max(e["runway_start_m"], e["displaced_threshold_m"])
            lu = along((e["lat"], e["lon"]), (far["lat"], far["lon"]), start + LINEUP_M)
            d += line([lu, ahead(lu, e["heading"], 40)], "#30ff30", 4) + dot(lu, "#30ff30", 6)
            d += label((e["lat"], e["lon"]), "RWY " + e["designator"], "#ff6060", 30)
            d += label(lu, "lineup " + e["designator"], "#30ff30", 20, below=True)
    for p in base["parking"]:
        q = (p["lat"], p["lon"])
        d += line([q, ahead(q, p["heading"], 20)], "#ffffff", 4) + dot(q, "#ff2020", 7)
        d += label(q, "park " + p["unit"], "#ffffff", 22)
    if base["tower"]:
        t = (base["tower"]["lat"], base["tower"]["lon"])
        d += dot(t, "#4060ff", 8) + label(t, "tower", "#8090ff", 24)
    # The scale bar: 100 m in 10 m steps, bottom left.
    bar = []
    for i in range(10):
        x = 30 + i * 10 / PX_M
        bar += ["-fill", "white" if i % 2 == 0 else "black", "-draw",
                "rectangle %d,%d %d,%d" % (x, h - 40, x + 10 / PX_M, h - 30)]
    note = "100 m in 10 m steps; %.0f m/px; north up" % PX_M
    title = "%s %s: OpenStreetMap (ODbL) on the %s" % (icao, base["name"]["en"], source)
    png = stem + ".png"
    subprocess.run(["magick", photo, *look, "-alpha", "off", *d, "-stroke", "black", "-strokewidth", "1", *bar,
                    "-pointsize", "20", "-stroke", "black", "-strokewidth", "4", "-fill", "white",
                    "-annotate", "+30+%d" % (h - 50), note, "-stroke", "none", "-annotate", "+30+%d" % (h - 50), note,
                    "-pointsize", "32", "-stroke", "black", "-strokewidth", "5", "-annotate", "+30+55", title,
                    "-stroke", "none", "-annotate", "+30+55", title, png], check=True)
    subprocess.run(["magick", png, "-resize", "1600x1600>", "-quality", "88",
                    stem + ".jpg"], check=True)
    print("wrote", png, "%dx%d" % (w, h))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args[:1] == ["overlay"]:
        for icao in args[2:] or AERODROMES:
            overlay(icao, args[1], False)
            if icao in MAPI_SHOWS:
                overlay(icao, args[1], True)
        return
    refetch = "--refetch" in sys.argv
    oa_airports, oa_runways = fetch_oa("airports.csv", refetch), fetch_oa("runways.csv", refetch)
    for icao in args or AERODROMES:
        write(icao, extract(icao, fetch_osm(icao, refetch), oa_airports, oa_runways))


if __name__ == "__main__":
    main()
