#!/usr/bin/env python3
"""IAF 2026's sound set (iaf-2026/docs/sound.md): the clips of iaf-2026/data/sounds/, made from openly licensed
recordings and our own synthesised tones, and that folder's SOURCES.md.

Every clip: 22050 Hz, 16-bit, mono WAV (what the game's sound table plays, docs/sound.md §1), named by its sound
code. A recording: cut [start, end] s out of the freesound HQ preview (the original files need a login; the preview
is a 44.1 / 48 kHz Ogg Vorbis), the tail below -50 dB of the peak cut, fades 5 ms in / FADE_OUT s out, or for a loop the last XFADE s cross-faded into the
start (equal power) so it repeats with no seam; then the voiced RMS (vrms, the samples above 2 % of the peak) set to
the row's level and a soft limit at -1 dBFS. A tone: computed here (`TONES`), ours (CC0).

Run (downloads each preview into its own new folder under DL, never inside the repo):
    VENV/bin/python -I tools/iaf-2026/sounds.py DL      # VENV: numpy + scipy; ffmpeg on the PATH
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "iaf-2026/data/sounds")
SR = 22050
UA = {"User-Agent": "linux-iaf-research/1.0"}
CC0 = "CC0 1.0"
FADE_OUT = 0.05
XFADE = 0.25
LIMIT = 0.89  # -1 dBFS

# name: (freesound id, author, title, licence, start s, end s, level dB vrms, loop, note)
CLIPS = {
    "sfx_start_engine": (322178, "ikbenraar", "F16 fighter jet start up", CC0, 30.0, 33.0, -12, True,
                         "the F-16's steady idle, 30-33 s"),
    "sfx_afterburner_thrust": (413312, "TiesWijnen", "Afterburner", CC0, 0.5, 3.0, -10, True,
                               "the burner's steady first seconds"),
    "sfx_button": (423957, "pillwave", "Toggle Switch", CC0, 0.0, 0.4, -20, False, "whole"),
    "sfx_landing_gear": (425273, "77Pacer", "Landing Gear", CC0, 0.0, 4.0, -10, False, "whole"),
    "sfx_flaps": (425274, "77Pacer", "Airplane flaps,", CC0, 0.0, 2.5, -14, False, "first 2.5 s"),
    "sfx_speed_breakes": (212941, "nuckan", "hydraulics.wav", CC0, 0.25, 1.6, -18, False,
                          "the first hydraulic stroke"),
    "sfx_speed_breakes_loop": (162417, "qubodup", "Jet Plane Wind Noise Loop of a KC-135 Stratotanker 1", CC0,
                               0.0, 6.2, -20, True, "whole (US Government video, public domain)"),
    "sfx_aircraft_fired_weapon_ost_gunbullet": (611449, "Seidhepriest", "M61A2 Minigun", CC0, 1.0, 2.75, -12, True,
                                                "the steady burst"),
    "sfx_entity_fired_weapon_ost_gunbullet": (163119, "qubodup",
                                              "Navy MK 15 Phalanx CIWS Anti-Air Fast Burst", CC0, 0.25, 1.5, -14,
                                              True, "the steady burst (US Government video, public domain)"),
    "sfx_aircraft_fired_weapon_ost_heatmissile": (184274, "qubodup", "Launching Anti-Tank Missiles", CC0, 10.0,
                                                  13.0, -13, False,
                                                  "the second launch (US Government video, public domain)"),
    "sfx_aircraft_fired_weapon_ost_bomb": (362506, "Jetrod", "clonk1.aiff", CC0, 0.0, 0.4, -14, False, "whole"),
    "sfx_aircraft_fired_weapon_ost_flare": (675636, "craigsmith", "S31-28 Flares gun fires; shells fall to floor",
                                            CC0, 3.2, 4.2, -14, False, "one shot"),
    "sfx_object_specific_ost_heatmissile": (515122, "LilMati", "Rocket Thrust 02", CC0, 10.0, 13.0, -20, True,
                                            "a steady 3 s"),
    "sfx_object_specific_ost_bomb": (479924, "craigsmith", "R12-27-Falling Bombs Whistle", CC0, 2.5, 5.5, -24, True,
                                     "a steady 3 s of the whistle"),
    "sfx_weapon_exploded_ost_bomb": (182429, "qubodup", "Explosion", CC0, 0.0, 3.0, -10, False,
                                     "whole (US Government video, public domain)"),
    "sfx_weapon_exploded_ost_rocket": (336011, "Rudmer_Rotteveel", "Sharp Explosion 4 (of 5)", CC0, 0.0, 1.0, -10,
                                       False, "whole"),
    "sfx_weapon_exploded_ost_gunbullet": (144444, "pushkin", "bullet impacts", CC0, 0.0, 0.45, -12, False,
                                          "the first impact"),
    "sfx_weapon_hit_target": (703248, "xkeril", "Fall debris (crash)", CC0, 0.0, 3.9, -14, False, "whole"),
    "sfx_splash": (442773, "qubodup", "Big Water Splash", CC0, 0.0, 2.2, -12, False, "whole"),
    "sfx_aircraft_exploded": (182432, "qubodup", "Explosive 1 v1 [DOD 130303]", CC0, 0.25, 4.0, -8, False,
                              "from the blast (US Government video, public domain)"),
    "sfx_aircraft_damaged_damaged_electricity": (189630, "elliott.klein", "Spark", CC0, 0.0, 0.2, -16, False,
                                                 "whole"),
    "sfx_aircraft_damaged_damaged_gun_bullets": (675951, "craigsmith", "S31-15 Shooting gallery; hitting metal targets",
                                                 CC0, 1.5, 2.5, -14, False, "the first hits"),
    "sfx_aircraft_damaged_damaged_missile_hit": (703247, "xkeril", "Big falling debris (crash)", CC0, 0.0, 2.0, -9,
                                                 False, "the first 2 s"),
    "cock_g_02": (680135, "DeqstersLab", "Grunting effort pushing something.wav", CC0, 0.0, 3.7, -22, False,
                     "whole"),
    "sfx_touchdown": (104026, "RutgerMuller", "Tires Squeaking.aif", CC0, 0.0, 0.6, -13, False, "the first chirp"),
    "sfx_screech": (646698, "SoundDesignForYou", "Scraping Metal Sheet in an Underpass", CC0, 0.25, 3.0, -16, False,
                    "the scrape"),
    "sfx_fire_extinguisher": (642961, "tranzfusion", "Fire Extinguisher", CC0, 0.0, 1.2, -17, False,
                              "the first burst"),
    "sfx_door_open": (479492, "craigsmith", "R02-48-Jet Fighter Canopy Closing", CC0, 0.0, 4.0, -18, False,
                      "the canopy motor's first 4 s"),
    "sfx_door_close": (479492, "craigsmith", "R02-48-Jet Fighter Canopy Closing", CC0, 12.75, 17.0, -18, False,
                       "the run to the lock, 12.75-17 s"),
}


def tone(f, t, phase=0.0):
    return np.sin(2 * np.pi * f * t + phase)


def beeps(freq, on, off, n, total):
    t = np.arange(int(total * SR)) / SR
    gate = ((t % (on + off)) < on) & (t < n * (on + off))
    ramp = np.convolve(gate.astype(float), np.hanning(int(0.004 * SR)), "same")
    return tone(freq, t) * ramp / ramp.max()


def ir_growl(f0, depth):
    """The seeker tone: a square-ish tone at f0 Hz, its level wobbling with low-passed noise (the growl)."""
    t = np.arange(SR) / SR  # 1 s: f0 whole cycles, a seamless loop
    rng = np.random.default_rng(9)
    w = sosfiltfilt(butter(2, 30, fs=SR, output="sos"), rng.standard_normal(SR))
    w = w - np.linspace(w[0], w[-1], SR)  # the wobble ends where it starts
    w = w / np.abs(w).max()
    return np.tanh(3 * tone(f0, t)) * (1 - depth + depth * (0.5 + 0.5 * w))


def warble(f1, f2, rate):
    """Two tones alternating `rate` times a second, each half period starting at phase 0. With whole cycles per half
    period (f / (2 rate) whole) every switch and the loop's wrap fall on a zero crossing."""
    assert (f1 / (2 * rate)).is_integer() and (f2 / (2 * rate)).is_integer()
    t = np.arange(SR) / SR
    half = 1 / (2 * rate)
    return np.sin(2 * np.pi * np.where((t * rate) % 1 < 0.5, f1, f2) * (t % half))


# name: (what it is, function, level dB vrms, loop)
TONES = {
    "sfx_landing": ("engine off: 0.1 s of silence", lambda: np.zeros(int(0.1 * SR)), None, True),
    "sfx_ir_seek": ("IR seeker search growl: 400 Hz, level wobble below 30 Hz", lambda: ir_growl(400, 0.6), -18, True),
    "sfx_ir_lock": ("IR seeker lock tone: 1000 Hz, light wobble", lambda: ir_growl(1000, 0.2), -16, True),
    "sfx_warning_wrn_aoa": ("AoA warning: 1600 Hz, 4 beeps a second", lambda: beeps(1600, 0.125, 0.125, 4, 1.0),
                            -24, True),
    "sfx_warning_wrn_new_guy": ("RWR new emitter: three 60 ms beeps at 1200 Hz",
                                lambda: beeps(1200, 0.06, 0.06, 3, 0.4), -24, False),
    "sfx_warning_wrn_missile_launch": ("RWR launch warning: 1024 / 1536 Hz alternating 8 times a second",
                                       lambda: warble(1024, 1536, 8), -20, True),
    "sfx_warning_wrn_master": ("master warning: two 150 ms beeps at 800 Hz", lambda: beeps(800, 0.15, 0.1, 2, 0.5),
                               -20, False),
}


def preview(dl, sid, user):
    """The HQ preview of freesound sound `sid`, downloaded once into its own folder dl/<sid>/."""
    d = os.path.join(dl, str(sid))
    done = [f for f in os.listdir(d) if f.endswith(".ogg")] if os.path.isdir(d) else []
    if done:
        return os.path.join(d, done[0])
    page = urllib.request.urlopen(
        urllib.request.Request(f"https://freesound.org/people/{user}/sounds/{sid}/", headers=UA), timeout=30
    ).read().decode()
    url = re.search(rf"https://cdn\.freesound\.org/previews/\d+/{sid}_\d+-lq\.ogg", page)[0].replace("-lq", "-hq")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, os.path.basename(url))
    with open(path + ".part", "wb") as f:  # renamed once whole: an interrupted download is never reused
        f.write(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read())
    os.replace(path + ".part", path)
    return path


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.int16).astype(float) / 32768


def vrms(x):
    a = np.abs(x)
    return np.sqrt(np.mean(x[a > 0.02 * a.max()] ** 2))


def finish(x, level, mode):
    """mode "loop": cross-fade the last XFADE s into the start; "once": fades; "as-is": a computed seamless loop."""
    if mode == "loop":
        n = int(XFADE * SR)
        x, tail = x[:-n].copy(), x[-n:]
        k = np.linspace(0, np.pi / 2, n)
        x[:n] = x[:n] * np.sin(k) + tail * np.cos(k)
    elif mode == "once":
        loud = np.nonzero(np.abs(x) > 0.003 * np.abs(x).max())[0]  # the tail below -50 dB of the peak goes
        x = x[: max(loud[-1] + int(FADE_OUT * SR), int(0.1 * SR))].copy() if len(loud) else x.copy()
        x[: int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))
        x[-int(FADE_OUT * SR):] *= np.linspace(1, 0, int(FADE_OUT * SR))
    if level is not None:
        x = x * 10 ** (level / 20) / vrms(x)
        x = np.where(np.abs(x) > 0.7, np.sign(x) * (0.7 + (LIMIT - 0.7) * np.tanh((np.abs(x) - 0.7) / (LIMIT - 0.7))),
                     x)
    return np.round(x * 32767).astype(np.int16)


def main():
    dl = sys.argv[1]
    rows = []
    for name, (sid, user, title, lic, a, b, level, loop, note) in CLIPS.items():
        x = decode(preview(dl, sid, user))
        x = x[int(a * SR): int((b + (XFADE if loop else 0)) * SR)]
        wavfile.write(os.path.join(OUT, name + ".wav"), SR, finish(x, level, "loop" if loop else "once"))
        url = f"https://freesound.org/people/{user}/sounds/{sid}/"
        how = f"{a:g}-{b:g} s ({note}), {'loop, ' if loop else ''}{level} dB vrms"
        rows.append(f"| `{name}.wav` | [{title}]({url}) | {user} | {lic} | {how} |")
    for name, (what, fn, level, loop) in TONES.items():
        wavfile.write(os.path.join(OUT, name + ".wav"), SR, finish(fn(), level, "as-is" if loop else "once"))
        rows.append(f"| `{name}.wav` | {what} | IAF 2026 (computed by this script) | {CC0} | "
                    f"{'loop, ' if loop else ''}{'' if level is None else f'{level} dB vrms'} |")
    with open(os.path.join(OUT, "voices.json"), encoding="utf-8") as f:
        v = json.load(f)
    vrows = [f"| {k} | [{d['model']}]({d['url']}) | {d['licence']} | {d['use']} |" for k, d in v["voices"].items()]
    with open(os.path.join(OUT, "SOURCES.md"), "w") as f:
        f.write(SOURCES_HEAD + "\n".join(rows) + "\n" + VOICES_HEAD + "\n".join(vrows) + "\n")
    print(f"{len(rows)} clips -> {OUT}")


VOICES_HEAD = """
## Voices

The speech clips (`voc_*`, `twr_*`, `num*`, `rwy*`, `acft_roger`, `endworld`, `kch2`) are Piper text to speech
through the radio filter, made by `tools/iaf-2026/radio_voice.py --set voices.json`; their texts and voices are in
[voices.json](voices.json). The Piper models are MIT licensed; each voice's training data is named below. `kch2` (the
radio click) and `twr_pause` (0.2 s of radio hiss) are computed.

| voice | Piper model | licence | speaks |
|---|---|---|---|
"""

SOURCES_HEAD = """# IAF 2026 sound clips: sources

Every clip in this folder, where it comes from, its author and licence, and how it was made. The table is written
by `tools/iaf-2026/sounds.py`, which also makes the clips (see its header for the processing: the cut, fades or
loop cross-fade, the level as dB of the voiced RMS, a soft limit at -1 dBFS; 22050 Hz, 16-bit, mono WAV).
The recordings are freesound's HQ previews (Ogg Vorbis, 44.1 / 48 kHz) of each sound; CC0 needs no credit, and we
name every author anyway. "US Government video, public domain" is the uploader's statement of the recording's origin.
The rows that use each clip: [soundprop.json](soundprop.json).

| clip | source | author | licence | processing |
|---|---|---|---|---|
"""

if __name__ == "__main__":
    main()
