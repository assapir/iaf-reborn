"""Shared helpers: WGS-84 <-> UTM 36N through gdaltransform, Ramon's layers in UTM."""
import json
import subprocess

import os

# The repo (assets/ beside it, as in the main checkout) and the survey's work folder (D: the extracts, blobs.json).
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
D = os.environ["D"]
OSM = f"{REPO}/assets/source/osm/airbases/LLRM.json"


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


def layers():
    d = json.load(open(f"{REPO}/modern-iaf/data/airbases/llrm.json"))
    out = {"runway": [], "taxiway": [], "apron": [], "hangar": [], "boundary": [to_utm(d["boundary"])]}
    for r in d["runways"]:
        out["runway"].append(to_utm([(e["lat"], e["lon"]) for e in r["ends"]]))
    for t in d["taxiways"]:
        out["taxiway"].append(to_utm(t["points"]))
    for a in d["aprons"]:
        out["apron"].append(to_utm(a["polygon"]))
    for s in d["shelters"]:
        out["hangar"].append(to_utm(s["polygon"]))
    raw = json.load(open(OSM))
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in raw["elements"] if e["type"] == "node"}
    hp, fence = [], []
    for e in raw["elements"]:
        t = e.get("tags", {})
        if t.get("aeroway") == "helipad":
            if e["type"] == "node":
                hp.append((e["lat"], e["lon"]))
            elif "nodes" in e:
                pts = [nodes[n] for n in e["nodes"] if n in nodes]
                if pts:
                    hp.append((sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)))
            elif "center" in e:
                hp.append((e["center"]["lat"], e["center"]["lon"]))
            elif "geometry" in e:
                g = e["geometry"]
                hp.append((sum(p["lat"] for p in g) / len(g), sum(p["lon"] for p in g) / len(g)))
        if t.get("barrier") == "fence":
            g = e.get("geometry") or [{"lat": nodes[n][0], "lon": nodes[n][1]} for n in e.get("nodes", []) if n in nodes]
            fence.append(to_utm([(p["lat"], p["lon"]) for p in g]))
    out["helipad"] = to_utm(hp)
    out["fence"] = fence
    out["parking"] = to_utm([(p["lat"], p["lon"]) for p in d["parking"]])
    return out


def extra():
    """The scenery extract's (OSM 2026-01-01) buildings, gates, solar fields and roads in the box, in UTM."""
    out = {"building": [], "gate": [], "pv": [], "road": [], "helipad_area": []}
    for f in json.load(open(f"{D}/osm_mp.geojson"))["features"]:
        p, g = f["properties"], f["geometry"]
        ring = [(la, lo) for lo, la in g["coordinates"][0][0]]
        if p.get("building") == "yes":
            out["building"].append((p.get("osm_way_id") or p.get("osm_id"), to_utm(ring)))
        elif p.get("aeroway") == "helipad":
            out["helipad_area"].append(to_utm(ring))
    for f in json.load(open(f"{D}/osm_pts.geojson"))["features"]:
        if f["properties"].get("barrier") == "gate":
            lo, la = f["geometry"]["coordinates"]
            out["gate"].append(to_utm([(la, lo)])[0])
    for f in json.load(open(f"{D}/osm_ln.geojson"))["features"]:
        p, g = f["properties"], f["geometry"]
        pts = [(la, lo) for lo, la in g["coordinates"]]
        o = p.get("other_tags") or ""
        if "photovoltaic" in o:
            out["pv"].append(to_utm(pts))
        elif p.get("highway") in ("unclassified", "service", "tertiary", "tertiary_link", "track"):
            out["road"].append(to_utm(pts))
    return out
