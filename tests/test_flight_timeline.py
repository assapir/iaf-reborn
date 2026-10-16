"""tools/flight_timeline.py on a hand-written recording (no game data): python3 -I tests/test_flight_timeline.py"""
import os
import pathlib
import runpy
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
ft = runpy.run_path(str(root / "tools/flight_timeline.py"))
head, rows, events = ft["load"](str(root / "tests/fixtures/flight_sample.jsonl"))
lines = ft["timeline"](events)
assert any("site 1 (SA3) locks you at 7.0 km" in l for l in lines), lines
assert any("LAUNCH: site 1 fires SA3 at you at 6.1 km" in l for l in lines), lines
assert any("HIT by site 1 (SA3) (missile), damage 0.30" in l for l in lines), lines
assert any("-> After burner damage" in l for l in lines), lines
assert any("CRASH: sink rate" in l for l in lines), lines
summ = ft["summary"](head, rows, events)
# The leg A -> B runs along y = 0; the row at (6000, 1500) is 1.5 km off it; the lowest height 15 m = 49 ft.
assert "  A -> B: 1.5 km off, lowest 49 ft" in summ, summ
assert "  site 1: hit, launch, lock" in summ, summ
out = os.path.join(tempfile.mkdtemp(), "t.html")
ft["write_html"](out, head, rows, events)
assert "<polyline" in open(out).read()
print("flight_timeline: ok")
