import json, subprocess, sys
D = __import__("os").environ["D"]  # the survey's work folder
src, out, e0, n0, e1, n1, m = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:8])
B = json.load(open(f"{D}/blobs.json"))
cmd = ["magick", src, "-fill", "none", "-stroke", "white", "-strokewidth", "1"]
for i, b in enumerate(B):
    if e0 <= b["e"] <= e1 and n0 <= b["n"] <= n1:
        x, y = (b["e"] - e0) / m, (n1 - b["n"]) / m
        cmd += ["-stroke", "white", "-fill", "none", "-draw", f"circle {x:.0f},{y:.0f} {x+9:.0f},{y:.0f}",
                "-stroke", "none", "-fill", "yellow", "-pointsize", "13", "-draw", f"text {x+9:.0f},{y-6:.0f} '{i}'"]
cmd.append(out); subprocess.run(cmd, check=True)
