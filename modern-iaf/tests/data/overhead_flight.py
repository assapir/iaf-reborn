#!/usr/bin/env python3
"""Mock only (branch wt/train-mocks, never merged): writes overhead_flight.jsonl beside this file, a synthetic
recording (blackbox version 2) of an overhead-break pattern at Ramon, runway 25R, for the training debrief's mock-up:
take-off, out and back to the initial at 1,500 ft, the break to the right at 4.6 g, downwind, the final turn and a
landing 1,350 ft past the threshold. Prints the times of the two faults (initial speed, touchdown)."""

import json
import math
import pathlib

WEST, NORTH = 615002.0, 3429107.0
LINEUP = (45561.1, 22469.8)
# The start's taxi line (sample_flight.py's), walked back to the parking spot after the landing.
TAXI = [
    (43812.4, 23824.8), (43780.5, 23701.2), (43759.1, 23653.2), (43841.7, 23616.5), (43816.6, 23540.9),
    (43817.2, 23489.7), (43844.3, 23436.6), (44073.6, 23130.3), (44785.3, 22814.3), (44805.8, 22787.4),
    (44823.9, 22797.2), (45652.4, 22429.3), (45561.1, 22469.8),
]
END_07L, END_25R = (43205.8, 23515.5), (45662.6, 22424.8)
HDG = math.degrees(math.atan2(END_07L[0] - END_25R[0], END_25R[1] - END_07L[1])) % 360.0
ORIGIN = (650000.0, 3400000.0)
KT = 1852.0 / 3600.0
FT = 0.3048
COLUMNS = ["t", "x", "z", "agl_m", "speed_kt", "g", "heading", "pitch", "on_ground", "engine", "throttle", "gear",
           "fuel_kg", "rpm", "avionics"]


def utm(p):
    return (WEST + p[0], NORTH - p[1])


def main():
    lines = [json.dumps({"blackbox": 2, "date": "2026-11-26T08:00:00", "mission": 2012, "jet": "F-16",
                         "name": "F-16I Sufa", "origin": list(ORIGIN), "settings": {}, "columns": COLUMNS,
                         "note": "mock: modern-iaf/tests/data/overhead_flight.py"})]
    thr = utm(END_25R)
    st = {"t": 0, "p": utm(TAXI[0]), "h": HDG, "v": 0.0, "agl": 1.8, "g": 1.0, "ground": True, "gear": True}
    marks = {}

    def row():
        e, n = st["p"]
        lines.append(json.dumps([st["t"], round(e - ORIGIN[0], 1), round(ORIGIN[1] - n, 1), round(st["agl"], 1),
                                 round(st["v"] / KT, 1), round(st["g"], 2), round(st["h"] % 360.0, 1), 0.0,
                                 st["ground"], True, 0.8, st["gear"], 3000.0, 90.0, True]))

    def step(turn=0.0, dv=0.0, climb=0.0, g=1.0):
        st["h"] += turn
        st["v"] = max(st["v"] + dv, 0.0)
        st["agl"] = max(st["agl"] + climb, 1.8)
        st["g"] = g
        h = math.radians(st["h"])
        st["p"] = (st["p"][0] + st["v"] * math.sin(h), st["p"][1] + st["v"] * math.cos(h))
        row()
        st["t"] += 1

    def along():  # metres from the 25R threshold along the take-off direction
        h = math.radians(HDG)
        return (st["p"][0] - thr[0]) * math.sin(h) + (st["p"][1] - thr[1]) * math.cos(h)

    def taxi(points):  # at 8 m/s along `points`
        for q in points:
            to = utm(q)
            while math.dist(to, st["p"]) > 0.5:
                d = (to[0] - st["p"][0], to[1] - st["p"][1])
                st["h"] = math.degrees(math.atan2(d[0], d[1]))
                st["v"] = min(8.0, math.hypot(*d))
                step()
        st["v"] = 0.0

    for _ in range(10):
        step()
    taxi(TAXI[1:])
    st["h"] = HDG
    for _ in range(10):
        step()
    while st["v"] < 165 * KT:  # the roll
        step(dv=1.8)
    st["ground"] = False
    lines.append(json.dumps({"event": "lift-off", "t": st["t"]}))
    for i in range(30):
        step(dv=1.5, climb=15.0)
        st["gear"] = i < 4
    while along() < 1500:
        step(dv=1.0 if st["v"] < 300 * KT else 0.0, climb=10.0 if st["agl"] < 1500 * FT else 0.0)
    for _ in range(30):  # left 180 at 6 deg/s
        step(turn=-6.0, g=1.9)
    while along() > -3000:
        step(dv=0.3 if st["v"] < 320 * KT else 0.0)
    for _ in range(30):
        step(turn=-6.0, g=1.9)
    st["h"] = HDG
    marks["initial_fast"] = st["t"] + 3
    while along() < 400:  # the initial, 22 kt fast
        step(dv=0.3 if st["v"] < 322 * KT else 0.0)
    for _ in range(12):  # the break: 180 deg right at 4.6 g, slowing
        step(turn=15.0, dv=-4.0, g=4.6)
    st["h"] = HDG + 180.0
    while along() > -1500:  # downwind, the gear down, sinking to 1,320 ft
        if "downwind_low" not in marks and st["agl"] <= 1330 * FT:
            marks["downwind_low"] = st["t"]
        step(dv=-2.0 if st["v"] > 200 * KT else 0.0, climb=-3.0 if st["agl"] > 1320 * FT else 0.0, g=1.0)
        st["gear"] = True
    for _ in range(20):  # the final turn, descending
        step(turn=9.0, dv=-0.8, climb=-16.0, g=2.2)
    st["h"] = HDG
    while st["agl"] > 2.0:  # final on the 3 deg path
        step(climb=-max(st["agl"] / max(410 - along(), 50) * st["v"], 0.5))
    st["agl"], st["ground"] = 1.8, True
    marks["touchdown"] = st["t"]
    while st["v"] > 0:
        step(dv=-3.0)
    taxi([LINEUP, TAXI[-2]])  # back along the runway, stopped at the 25R end
    for _ in range(5):
        step()
    pathlib.Path(__file__).with_name("overhead_flight.jsonl").write_text("\n".join(lines) + "\n")
    print(json.dumps(marks), round(along()), st["t"])


main()
