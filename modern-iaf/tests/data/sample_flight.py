#!/usr/bin/env python3
"""Writes ramon_takeoff_flight.jsonl beside this file: a synthetic recording (docs/blackbox.schema.json, version 2,
once a second) of mission ramon_takeoff, the debrief's sample for the Rust scorer's tests, the front end's tests and
its pictures. The start-up on the Sufa's parking spot, the four tower calls, the taxi along the briefing map's taxi line
(IafBriefing.map of ramon_takeoff: its `taxi` in the map's metres, the map's `extent` in UTM 36N), a hold at the
holding point, the line-up and a stop on it, the roll lifting off 13 kt above the reference speed at 3,000 kg of fuel,
the gear up 4 s later, a climb to 4,000 ft above the ground and a 1.8 g turn. Run: python3 -I sample_flight.py"""

import json
import math
import pathlib

# IafBriefing.map("ramon_takeoff"): the map's north-west corner (UTM 36N) and the taxi line (the map's metres, y down);
# its last point is the line-up point on runway 25R, the one before the runway entry (the holding point).
WEST, NORTH = 615002.0, 3429107.0
TAXI = [
    (43812.4, 23824.8), (43780.5, 23701.2), (43759.1, 23653.2), (43841.7, 23616.5), (43816.6, 23540.9),
    (43817.2, 23489.7), (43844.3, 23436.6), (44073.6, 23130.3), (44785.3, 22814.3), (44805.8, 22787.4),
    (44823.9, 22797.2), (45652.4, 22429.3), (45561.1, 22469.8),
]
# Runway 07L/25R's ends (the map's `runways`): the roll runs from the 25R end toward the 07L end.
END_07L, END_25R = (43205.8, 23515.5), (45662.6, 22424.8)
RUNWAY_HEADING = math.degrees(math.atan2(END_07L[0] - END_25R[0], END_25R[1] - END_07L[1])) % 360.0
ORIGIN = (650000.0, 3400000.0)
KT = 1852.0 / 3600.0
FT = 0.3048
# The mission's training.empty_kg and takeoff_kt; the fuel at lift-off.
EMPTY_KG, FUEL_KG = 8573.0, 3000.0
REFERENCE_KT = 130.0 + (EMPTY_KG + FUEL_KG - 9072.0) / (21772.0 - 9072.0) * (214.0 - 130.0)
COLUMNS = ["t", "x", "z", "agl_m", "speed_kt", "g", "heading", "pitch", "on_ground", "engine", "throttle", "gear",
           "fuel_kg", "rpm", "avionics"]


def utm(p):
    return (WEST + p[0], NORTH - p[1])


def main():
    lines = [json.dumps({"blackbox": 2, "date": "2026-11-02T08:00:00", "mission": 2012, "jet": "F-16",
                         "name": "F-16I Sufa", "origin": list(ORIGIN), "settings": {}, "columns": COLUMNS,
                         "note": "synthetic sample: modern-iaf/tests/data/sample_flight.py"})]
    st = {"t": 0, "p": utm(TAXI[0]), "h": 335.0}

    def row(v_ms, agl=1.8, g=1.0, pitch=0.0, ground=True, thr=0.0, gear=True):
        t = st["t"]
        rpm = 0.0 if t < 10 else min(20.0 + max(t - 25, 0) * 2.7, 60.0 + thr * 40.0)
        e, n = st["p"]
        lines.append(json.dumps([t, round(e - ORIGIN[0], 1), round(ORIGIN[1] - n, 1), round(agl, 1),
                                 round(v_ms / KT, 1), round(g, 2), round(st["h"] % 360.0, 1), round(pitch, 1), ground,
                                 t >= 25, thr, gear, FUEL_KG, round(rpm, 1), t >= 45]))

    def event(e):
        e["t"] = st["t"]
        lines.append(json.dumps(e))

    def tick():
        st["t"] += 1

    # The start-up: the calls for the start-up and the taxi.
    while st["t"] < 100:
        if st["t"] in (5, 80):
            event({"event": "radio", "call": "startup" if st["t"] == 5 else "taxi"})
        row(0.0)
        tick()

    def go(to, v):
        while True:
            d = (to[0] - st["p"][0], to[1] - st["p"][1])
            left = math.hypot(*d)
            if left < 0.5:
                return
            st["h"] = math.degrees(math.atan2(d[0], d[1]))
            k = min(v / left, 1.0)
            st["p"] = (st["p"][0] + d[0] * k, st["p"][1] + d[1] * k)
            row(left * k, thr=0.15)
            tick()

    # The taxi at 8 m/s to the holding point, a two-minute hold with the line-up call, on to the line-up at 4 m/s.
    for q in TAXI[1:-1]:
        go(utm(q), 8.0)
    for i in range(120):
        if i == 100:
            event({"event": "radio", "call": "lineup"})
        row(0.0, thr=0.1)
        tick()
    go(utm(TAXI[-1]), 4.0)
    st["h"] = RUNWAY_HEADING
    for i in range(12):
        if i == 4:
            event({"event": "radio", "call": "takeoff"})
        row(0.0, thr=0.1)
        tick()
    # The roll at 2.5 m/s², the nose up from 10 kt below the reference, the lift-off 13 kt above it.
    v, pitch, h = 0.0, 0.0, math.radians(RUNWAY_HEADING)
    while v / KT < REFERENCE_KT + 13.0:
        v += 2.5
        st["p"] = (st["p"][0] + v * math.sin(h), st["p"][1] + v * math.cos(h))
        rotating = v / KT >= REFERENCE_KT - 10.0
        if rotating:
            pitch = min(pitch + 3.0, 10.0)
        row(v, g=1.4 if rotating and pitch <= 6.0 else 1.0, pitch=pitch, ground=v / KT < REFERENCE_KT + 13.0, thr=1.0)
        tick()
    event({"event": "lift-off"})
    # The climb: the gear up after 4 s, to 300 kt and 4,000 ft, a 90° turn to the right a minute on.
    agl = 1.8
    for i in range(1, 216):
        v = min(v + 1.5, 300.0 * KT)
        agl = min(agl + 7.0, 4000.0 * FT)
        turning = 60 <= i < 90
        if turning:
            st["h"] += 3.0
        g = 1.0 + 0.8 * math.sin(math.pi * (i - 60) / 30.0) if turning else 1.0
        h = math.radians(st["h"])
        st["p"] = (st["p"][0] + v * math.sin(h), st["p"][1] + v * math.cos(h))
        row(v, agl=agl, g=g, pitch=8.0 if agl < 4000.0 * FT else 1.0, ground=False, thr=1.0, gear=i <= 4)
        tick()
    pathlib.Path(__file__).with_name("ramon_takeoff_flight.jsonl").write_text("\n".join(lines) + "\n")


main()
