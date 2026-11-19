"""usage: prep.py ICAO OUT_ROOT. Per-base survey inputs from files on disk: S2 10 m and the SoI 2015 photo (2 m) in UTM 36N, the OSM extract's layers."""
import json, math, os, subprocess, sys
R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, os.path.join(R, "tools/iaf-2026"))
import osm_airbase as oa  # noqa: E402
S2 = R + "/assets/source/imagery/sentinel2/ESA_WorldCover_10m_2021_v200_N%02dE%03d_S2RGBNIR.tif"
PBF = R + "/assets/source/scenery/israel-and-palestine-260101.osm.pbf"
icao = sys.argv[1]
D = os.path.join(sys.argv[2], icao.lower())
os.makedirs(D, exist_ok=True)
b = json.load(open(f"{R}/modern-iaf/data/airbases/{icao.lower()}.json"))["boundary"]
la0, la1 = min(p[0] for p in b) - 0.004, max(p[0] for p in b) + 0.004
lo0, lo1 = min(p[1] for p in b) - 0.004, max(p[1] for p in b) + 0.004
out = subprocess.run(["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", "EPSG:32636"], input="".join(
    f"{lo} {la}\n" for lo in (lo0, lo1) for la in (la0, la1)), capture_output=True, text=True, check=True).stdout
pts = [tuple(map(float, l.split()[:2])) for l in out.splitlines()]
e0, n0 = math.floor(min(p[0] for p in pts) / 10) * 10, math.floor(min(p[1] for p in pts) / 10) * 10
e1, n1 = math.ceil(max(p[0] for p in pts) / 10) * 10, math.ceil(max(p[1] for p in pts) / 10) * 10
tiles = [S2 % (la, lo) for la in range(math.floor(la0), math.floor(la1) + 1) for lo in range(math.floor(lo0), math.floor(lo1) + 1)]
have = [t for t in tiles if os.path.exists(t)]
print(icao, "box", e0, n0, e1, n1, "tiles missing:", [os.path.basename(t) for t in tiles if t not in have])
te = ["-te", str(e0), str(n0), str(e1), str(n1)]
if not os.path.exists(f"{D}/s2_10m.tif") and have:
    subprocess.run(["gdalwarp", "-q", "-t_srs", "EPSG:32636", *te, "-tr", "10", "10", "-r", "near", *have, f"{D}/s2_10m.tif"], check=True)
    subprocess.run(["gdal_translate", "-q", "-b", "1", "-b", "2", "-b", "3", "-scale", "0", "2500", "0", "255", "-ot", "Byte", f"{D}/s2_10m.tif", f"{D}/s2_rgb.png"], check=True)
itm = subprocess.run(["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", "EPSG:2039"], input="".join(
    f"{lo} {la}\n" for lo in (lo0, lo1) for la in (la0, la1)), capture_output=True, text=True, check=True).stdout
ip = [tuple(map(float, l.split()[:2])) for l in itm.splitlines()]
sh = oa.sheets_for((min(p[0] for p in ip), min(p[1] for p in ip), max(p[0] for p in ip), max(p[1] for p in ip)))
if not os.path.exists(f"{D}/soi_2m.tif") and sh:
    subprocess.run(["gdalwarp", "-q", "-s_srs", "EPSG:2039", "-t_srs", "EPSG:32636", *te, "-tr", "2", "2", "-r", "cubic", *sh, f"{D}/soi_2m.tif"], check=True)
for lay in ("multipolygons", "lines", "points"):
    f = f"{D}/osm_{lay}.geojson"
    if not os.path.exists(f):
        subprocess.run(["ogr2ogr", "-q", "-f", "GeoJSON", "-spat", str(lo0), str(la0), str(lo1), str(la1), f, PBF, lay], check=True)
json.dump({"e0": e0, "n0": n0, "e1": e1, "n1": n1}, open(f"{D}/box.json", "w"))
