#!/usr/bin/env python3
"""The F-35I Adir demo clip v3 from the repo, in one command (from the repo root, after
`cargo build --release -p iaf-godot`):

    python3 -I tools/demo/adir_demo.py            # 3840x2160 -> assets/converted/demo/adir_demo_v3.mp4
    python3 -I tools/demo/adir_demo.py --draft    # 960x540   -> assets/converted/demo/adir_demo_v3_draft.mp4

It renders the three parts of tests/godot/_adir_demo_v3_shot.gd (DEMO_PART 315, 223, 214; seed 35) with Godot's
movie writer at 30 fps through tools/godot_window.sh (a temporary game/override.cfg sets the size and is removed
afterwards), cuts the shots in the storyboard's order from the parts' "SEG" lines, widened so no radio call
("VOICE" lines) is cut mid-sentence, and encodes for X: H.264 High, yuv420p, 30 fps, AAC stereo, +faststart.
An existing output file is never overwritten. --work DIR keeps the parts (default /tmp/adir_demo_v3);
--skip-render cuts again from the parts already there.
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEED = 35
FPS = 30
PARTS = ["315", "223", "214"]
# The storyboard: (part, shot). Cutting between missions and times is editing; each shot is one continuous take.
STORY = [("315", "crater"), ("223", "deadsea"), ("223", "bogies"),
         ("223", "launch"), ("223", "amraam"), ("223", "falls"), ("223", "tanks"), ("223", "laser"),
         ("214", "landing")]
# A shot is widened by at most this many frames at either end to keep a radio call whole.
WIDEN_MAX = 5 * FPS
FADE = 0.08  # s, the audio fade at every cut


def render(part, work, size):
    log = os.path.join(work, f"{part}.log")
    movie = os.path.join(work, f"{part}.avi")
    for f in (log, movie):
        if os.path.exists(f):
            os.remove(f)
    cmd = ["timeout", "5400", os.path.join(ROOT, "tools/godot_window.sh"), "IAF_DEFAULT_SETTINGS=1",
           f"DEMO_PART={part}", f"DEMO_SEED={SEED}", "--", "--log-file", log, "--path", os.path.join(ROOT, "game"),
           "--write-movie", movie, "--fixed-fps", str(FPS), "-s", "../tests/godot/_adir_demo_v3_shot.gd"]
    subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL)
    text = open(log, encoding="utf-8", errors="replace").read()
    if "RESULT PASS" not in text or "SCRIPT ERROR" in text:
        sys.exit(f"part {part} failed: see {log}")


def marks(part, work):
    """{shot: [f0, f1]} and [[v0, v1]] from a part's log."""
    segs, voices = {}, []
    for line in open(os.path.join(work, f"{part}.log"), encoding="utf-8", errors="replace"):
        if m := re.match(r"SEG (\S+) (\d+) (\d+)", line):
            segs[m[1]] = [int(m[2]), int(m[3])]
        elif m := re.match(r"VOICE (\d+) (\d+)", line):
            voices.append([int(m[1]), int(m[2])])
    return segs, voices


def widen(f0, f1, voices):
    """The shot widened so that a call running over either end plays whole (within WIDEN_MAX)."""
    for v0, v1 in voices:
        if v0 < f0 < v1 and f0 - v0 <= WIDEN_MAX:
            f0 = v0
        if v0 < f1 < v1 and v1 - f1 <= WIDEN_MAX:
            f1 = v1
    return f0, f1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--draft", action="store_true")
    ap.add_argument("--work", default="/tmp/adir_demo_v3")
    ap.add_argument("--skip-render", action="store_true")
    a = ap.parse_args()
    w, h = (960, 540) if a.draft else (3840, 2160)
    out = os.path.join(ROOT, "assets/converted/demo", "adir_demo_v3_draft.mp4" if a.draft else "adir_demo_v3.mp4")
    if os.path.exists(out):
        sys.exit(f"{out} exists: not overwritten")
    os.makedirs(a.work, exist_ok=True)
    if not a.skip_render:
        cfg = os.path.join(ROOT, "game/override.cfg")
        with open(cfg, "w") as f:
            f.write(f"[display]\n\nwindow/size/viewport_width={w}\nwindow/size/viewport_height={h}\n")
        try:
            for p in PARTS:
                render(p, a.work, (w, h))
        finally:
            os.remove(cfg)
    info = {p: marks(p, a.work) for p in PARTS}
    inputs, chains, n = [], [], 0
    for p in PARTS:
        inputs += ["-i", os.path.join(a.work, f"{p}.avi")]
    for part, shot in STORY:
        segs, voices = info[part]
        if shot not in segs:
            sys.exit(f"part {part} has no shot {shot}")
        f0, f1 = widen(*segs[shot], voices)
        t0, t1 = f0 / FPS, f1 / FPS
        print(f"{part} {shot}: {t0:.2f}..{t1:.2f} s ({t1 - t0:.1f} s)")
        k = PARTS.index(part)
        chains.append(f"[{k}:v]trim=start={t0:.4f}:end={t1:.4f},setpts=PTS-STARTPTS,scale={w}:{h}:out_range=tv,format=yuv420p,fps={FPS}[v{n}];"
                      f"[{k}:a]atrim=start={t0:.4f}:end={t1:.4f},asetpts=PTS-STARTPTS,aformat=channel_layouts=stereo,"
                      f"afade=t=in:d={FADE},afade=t=out:st={t1 - t0 - FADE:.4f}:d={FADE}[a{n}]")
        n += 1
    graph = ";".join(chains) + ";" + "".join(f"[v{i}][a{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=1[v][a]"
    cmd = ["ffmpeg", "-n", "-hide_banner", "-loglevel", "warning", *inputs, "-filter_complex", graph,
           "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-color_range", "tv",
           "-preset", "slow", "-crf", "18", "-maxrate", "40M", "-bufsize", "80M", "-r", str(FPS),
           "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "48000", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print(out)


if __name__ == "__main__":
    main()
