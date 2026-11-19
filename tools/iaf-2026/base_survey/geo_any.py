"""Any base's helpers for prep.py, gen.py and plot.py: WGS-84 <-> UTM 36N (gdaltransform), the base's layers in UTM.
BASE=<icao>, D=<the base's survey folder>."""
import json
import os
import subprocess

R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
ICAO = os.environ["BASE"].upper()
D = os.environ["D"]


def _gt(pts, s, t):
    if not pts:
        return []
    inp = "".join(f"{a} {b}\n" for a, b in pts)
    out = subprocess.run(["gdaltransform", "-s_srs", s, "-t_srs", t], input=inp, capture_output=True, text=True,
                         check=True).stdout.split("\n")
    return [tuple(float(v) for v in ln.split()[:2]) for ln in out if ln.strip()]


def to_utm(latlons):
    return _gt([(lo, la) for la, lo in latlons], "EPSG:4326", "EPSG:32636")


def to_ll(ens):
    return [(la, lo) for lo, la in _gt(ens, "EPSG:32636", "EPSG:4326")]


def base():
    return json.load(open(f"{R}/modern-iaf/data/airbases/{ICAO.lower()}.json"))


def layers():
    d = base()
    out = {"runway": [], "taxiway": [], "apron": [], "hangar": [], "boundary": [to_utm(d["boundary"])]}
    for r in d["runways"]:
        out["runway"].append(to_utm([(e["lat"], e["lon"]) for e in r["ends"]]))
    for t in d["taxiways"]:
        out["taxiway"].append(to_utm(t["points"]))
    for a in d["aprons"]:
        out["apron"].append(to_utm(a["polygon"]))
    for s in d["shelters"]:
        out["hangar"].append(to_utm(s["polygon"]))
    out["shelter_osm"] = [s.get("osm") for s in d["shelters"]]
    out["shelter_kind"] = [s.get("kind", s.get("type")) for s in d["shelters"]]
    sp = json.load(open(f"{R}/modern-iaf/data/parking.json"))[ICAO]
    out["parking"] = to_utm([(p["lat"], p["lon"]) for p in sp])
    out["parking_hdg"] = [p.get("heading") for p in sp]
    return out


def extra():
    """The scenery extract's (OSM 2026-01-01) buildings, gates and roads in the box, in UTM."""
    out = {"building": [], "gate": [], "road": [], "fence": []}
    for f in json.load(open(f"{D}/osm_multipolygons.geojson"))["features"]:
        p, g = f["properties"], f["geometry"]
        if p.get("building"):
            ring = [(la, lo) for lo, la in g["coordinates"][0][0]]
            out["building"].append((p.get("osm_way_id") or p.get("osm_id"), to_utm(ring), p.get("building"),
                                    p.get("other_tags") or ""))
    for f in json.load(open(f"{D}/osm_points.geojson"))["features"]:
        if "gate" in (f["properties"].get("other_tags") or "") or f["properties"].get("barrier") == "gate":
            lo, la = f["geometry"]["coordinates"]
            out["gate"].append(to_utm([(la, lo)])[0])
    for f in json.load(open(f"{D}/osm_lines.geojson"))["features"]:
        p, g = f["properties"], f["geometry"]
        pts = [(la, lo) for lo, la in g["coordinates"]]
        o = p.get("other_tags") or ""
        if '"barrier"=>"fence"' in o or p.get("barrier") == "fence":
            out["fence"].append(to_utm(pts))
        elif p.get("highway") in ("unclassified", "service", "tertiary", "tertiary_link", "track", "residential"):
            out["road"].append(to_utm(pts))
    return out
