#!/usr/bin/env python3
"""A flight recording (the blackbox, docs/blackbox.schema.json) as a readable timeline and a summary.

    python3 -I tools/flight_timeline.py <flight.jsonl> [--html out.html]

Recordings are in the game's user folder (macOS: ~/Library/Application Support/Godot/app_userdata/iaf-reborn/flights).
The timeline lists each event with the time, height above the terrain and speed; the summary gives, per leg of the
planned route, the farthest the jet was off the leg and its lowest height, and the threats that engaged it.
"""
import argparse
import html
import json
import math
import sys


def load(path):
    head, rows, events = None, [], []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            v = json.loads(line)
            if head is None:
                head = v
            elif isinstance(v, list):
                rows.append(dict(zip(head["columns"], v)))
            else:
                events.append(v)
    return head, rows, events


def km(m):
    return f"{m / 1000:.1f} km"


def describe(e):
    """One event as a sentence ("" to skip)."""
    k, who = e["event"], e.get("unit") or e.get("key") or "?"
    weapon = f" ({e['weapon']})" if e.get("weapon") else ""
    dist = f" at {km(e['dist_m'])}" if "dist_m" in e else ""
    match k:
        case "lift-off":
            return "lift-off"
        case "touchdown":
            return f"touchdown, sink {e.get('sink_ms', 0):.1f} m/s"
        case "crash":
            return f"CRASH: {e.get('reason', '?')}"
        case "autopilot":
            return f"autopilot {e.get('mode')}"
        case "mission":
            return f"mission event: {e.get('name', '')}"
        case "message":
            return f"\"{e.get('text', '')}\""
        case "weapon":
            return f"master mode {e.get('master')}, store {e.get('store') or '-'}"
        case "lock":
            return f"{who}{weapon} locks you{dist}"
        case "unlock":
            return f"{who} drops its lock{dist}"
        case "launch":
            return f"LAUNCH: {who} fires {e.get('weapon', '?')} at you{dist}"
        case "hit":
            fatal = ", fatal" if e.get("kill") else ""
            return f"HIT by {who}{weapon} ({e.get('kind', '?')}), damage {e.get('damage', 0):.2f}{fatal}"
        case "system":
            return f"  -> {e.get('text', 'system ' + str(e.get('system')))}"
        case "kill":
            return f"you destroyed {who}{dist}"
        case "shot_down":
            return f"SHOT DOWN by {who}" if e.get("key") else "SHOT DOWN"
        case "in_sight":
            return f"{who}{weapon} has line of sight to you{dist}"
        case "masked":
            return f"masked from {who}{dist}"
        case "seeker":
            if not e.get("key"):
                return f"IR seeker {e.get('tone')} ({e.get('weapon', '?')}), no target"
            ab = ", afterburner" if e.get("afterburner") else ""
            slaved = ", radar-slaved" if e.get("slaved") else ""
            return (f"IR seeker {e.get('tone')} ({e.get('weapon', '?')}): {who}{dist}, "
                    f"{e.get('off_nose_deg', 0):.1f}° off the nose{ab}{slaved}")
    return k


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = dx * dx + dy * dy
    t = 0.0 if n == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / n))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def summary(head, rows, events):
    out = []
    route = [(w["x"], w["y"]) for w in head.get("route", [])]
    ox, oy = head.get("origin", [None, None])
    if len(route) >= 2 and ox is not None:
        legs = {}
        for r in rows:
            if r.get("on_ground"):
                continue
            p = (ox + r["x"], oy - r["z"])
            d = [seg_dist(p, route[i], route[i + 1]) for i in range(len(route) - 1)]
            i = min(range(len(d)), key=d.__getitem__)
            leg = legs.setdefault(i, {"off": 0.0, "agl": math.inf})
            leg["off"] = max(leg["off"], d[i])
            if r.get("agl_m") is not None:
                leg["agl"] = min(leg["agl"], r["agl_m"])
        names = [w["name"] for w in head["route"]]
        out.append("Legs (farthest off the leg, lowest height above the terrain):")
        for i in sorted(legs):
            leg = legs[i]
            agl = f"{leg['agl'] * 3.281:.0f} ft" if leg["agl"] != math.inf else "-"
            out.append(f"  {names[i]} -> {names[i + 1]}: {km(leg['off'])} off, lowest {agl}")
    engaged = {}
    for e in events:
        if e["event"] in ("lock", "launch", "hit") and e.get("unit"):
            engaged.setdefault(e["unit"], set()).add(e["event"])
    if engaged:
        out.append("Threats that engaged you:")
        for u, ks in sorted(engaged.items()):
            out.append(f"  {u}: {', '.join(sorted(ks))}")
    return out


def timeline(events):
    lines = []
    for e in events:
        text = describe(e)
        if not text:
            continue
        agl = e.get("agl_m")
        agl = f"{agl * 3.281:6.0f} ft" if agl is not None else "      - "
        lines.append(f"{e['t']:8.1f} s {agl} {e.get('speed_kt', 0):5.0f} kt  {text}")
    return lines


def write_html(path, head, rows, events):
    w, h = 1000, 220
    t1 = max([r["t"] for r in rows] + [1.0])
    top = max([r["agl_m"] or 0 for r in rows] + [100.0])
    pts = " ".join(f"{r['t'] / t1 * w:.1f},{h - (r['agl_m'] or 0) / top * h:.1f}" for r in rows)
    marks = "".join(
        f'<line x1="{e["t"] / t1 * w:.1f}" x2="{e["t"] / t1 * w:.1f}" y1="0" y2="{h}" class="{e["event"]}"/>'
        for e in events if e["event"] in ("lock", "launch", "hit", "crash", "shot_down"))
    items = "".join(f"<li>{html.escape(l)}</li>" for l in timeline(events))
    summ = "".join(f"<li>{html.escape(l)}</li>" for l in summary(head, rows, events))
    title = f"Flight {head.get('date', '')}, mission {head.get('mission')}, {head.get('jet', '')}"
    with open(path, "w") as f:
        f.write(f"""<!doctype html><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>body{{font:14px system-ui;margin:16px;max-width:1040px}} svg{{background:#f4f4f4;width:100%}}
polyline{{fill:none;stroke:#246;stroke-width:1.5}} line{{stroke-width:1}} .lock{{stroke:#c90}} .launch{{stroke:#e60}}
.hit,.shot_down{{stroke:#c00;stroke-width:2}} .crash{{stroke:#000;stroke-width:2}} li{{font-family:ui-monospace,monospace;white-space:pre}}</style>
<h1>{html.escape(title)}</h1><p>Height above the terrain (max {top * 3.281:.0f} ft) over {t1:.0f} s; lines: lock (amber),
launch (orange), hit (red), crash (black).</p>
<svg viewBox="0 0 {w} {h}" preserveAspectRatio="none"><polyline points="{pts}"/>{marks}</svg>
<h2>Summary</h2><ul>{summ}</ul><h2>Timeline</h2><ul>{items}</ul>""")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("recording")
    ap.add_argument("--html", help="also write a self-contained HTML timeline with the height profile")
    a = ap.parse_args()
    head, rows, events = load(a.recording)
    print(f"Flight {head.get('date', '')}: mission {head.get('mission')}, {head.get('jet', '')}, pilot {head.get('pilot', '')}")
    print("\n".join(timeline(events)))
    print()
    print("\n".join(summary(head, rows, events)))
    if a.html:
        write_html(a.html, head, rows, events)
        print(f"\nHTML: {a.html}")


if __name__ == "__main__":
    sys.exit(main())
