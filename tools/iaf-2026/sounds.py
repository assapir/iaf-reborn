#!/usr/bin/env python3
"""Modern IAF's sound set (iaf-2026/docs/sound.md): the clips of iaf-2026/data/sounds/, made from openly licensed
recordings and our own synthesised tones, and that folder's SOURCES.md.

Every clip: 22050 Hz mono Ogg Vorbis, quality 4 (what the sim ships; its sound table opens ogg, docs/sound.md §1),
named by its sound code. A recording: cut [start, end] s out of the freesound HQ preview (the original files need a login; the preview
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
import tempfile
import urllib.request

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, find_peaks, sosfiltfilt

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
    "sfx_start_engine": (322178, "ikbenraar", "F16 fighter jet start up", CC0, 30.0, 33.0, -14, True,
                         "the F-16's steady idle, 30-33 s"),
    "sfx_afterburner_thrust": (343746, "Rudmer_Rotteveel", "2 Royal Dutch Airforce F-16 Fighting Falcons flyby", CC0,
                               16.5, 19.5, -8, True, "the take-off roar's closest pass, the highs lifted, its level flattened"),
    "sfx_button": (423957, "pillwave", "Toggle Switch", CC0, 0.0, 0.4, -20, False, "whole"),
    "sfx_landing_gear": (425273, "77Pacer", "Landing Gear", CC0, 0.0, 4.0, -10, False, "whole"),
    "sfx_flaps": (425274, "77Pacer", "Airplane flaps,", CC0, 0.0, 2.5, -14, False, "first 2.5 s"),
    "sfx_speed_breakes": (212941, "nuckan", "hydraulics.wav", CC0, 0.25, 1.6, -18, False,
                          "the first hydraulic stroke"),
    "sfx_speed_breakes_loop": (162417, "qubodup", "Jet Plane Wind Noise Loop of a KC-135 Stratotanker 1", CC0,
                               0.0, 6.2, -20, True, "whole (US Government video, public domain)"),
    "sfx_aircraft_fired_weapon_ost_gunbullet": (611449, "Seidhepriest", "M61A2 Minigun", CC0, 0.75, 3.25, -12, True,
                                                "the steady burst, its shots re-spaced to 100 a second"),
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
    "sfx_touchdown": (479498, "craigsmith", "R02-24-Airplane Tire Skid.wav", CC0, 0.15, 0.6, -13, False,
                      "the skid, with a 60 Hz strut thump under it"),
    "sfx_screech": (646698, "SoundDesignForYou", "Scraping Metal Sheet in an Underpass", CC0, 0.25, 3.0, -16, False,
                    "the scrape"),
    "sfx_fire_extinguisher": (642961, "tranzfusion", "Fire Extinguisher", CC0, 0.0, 1.2, -17, False,
                              "the first burst"),
    "sfx_door_open": (479492, "craigsmith", "R02-48-Jet Fighter Canopy Closing", CC0, 21.25, 25.0, -18, False,
                      "the canopy motor's second run, 21.25-25 s (0-6.5 s is the library's spoken slate)"),
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


def jfs():
    """The JFS whine (iaf-2026/docs/sound.md §1.4): the partials an F-16's JFS shows at its governed speed, 2126 Hz and
    3252, 4247, 5259, 6401 Hz, each at its level over the broadband, wandering 0.3 % in speed, on circular noise
    shaped 1/f above 300 Hz at the partials' level (the turbine's air rush; inferred). Whole cycles in 1 s and a
    wander that ends where it starts: a seamless loop."""
    t = np.arange(SR) / SR
    rng = np.random.default_rng(7)
    # a wander of about 0.3 % in speed: slow whole-Hz sines, so the loop stays seamless
    wander = sum(np.sin(2 * np.pi * k * t + rng.random() * 6.3) / k for k in range(1, 8))
    wander = 0.003 * wander / np.abs(wander).max()
    x = sum(10 ** (db / 20) * tone(f, t, i + f * np.cumsum(wander) / SR * 2 * np.pi) for i, (f, db) in
            enumerate(((2126, 0), (3252, -5), (4247, -12), (5259, -13), (6401, -14), (1063, -18))))
    f = np.fft.rfftfreq(SR, 1 / SR)
    mag = np.where(f > 300, 1 / np.maximum(f, 1), 0) ** 0.5
    noise = np.fft.irfft(mag * np.exp(2j * np.pi * rng.random(len(f))), SR)
    return x / vrms(x) + noise / vrms(noise)


# name: (what it is, function, level dB vrms, loop)
TONES = {
    "sfx_jfs": ("the JFS whine: 2126 Hz and its partials, a 0.3 % wander, on 1/f air noise", jfs, -20, True),
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


def flatten(x, w=0.5):
    """The level evened out: x over its RMS envelope smoothed over w s, so a loop cut from a pass does not pulse."""
    n = int(w * SR)
    env = np.sqrt(np.convolve(x * x, np.ones(n) / n, "same"))
    return x / np.maximum(env, 1e-4 * env.max())


def ab_roar(x, low_db=-12, high_db=16):
    """The burner loop: the band below 150 Hz down low_db and above 1.5 kHz up high_db, so its spectrum sits between
    the F-16 references' (iaf-2026/docs/sound.md §1.2; the recording was made far down the runway, where the air takes
    the highs and the ground adds rumble: inferred), then flattened."""
    lo = sosfiltfilt(butter(2, 150, fs=SR, output="sos"), x)
    hi = sosfiltfilt(butter(2, 1500, "highpass", fs=SR, output="sos"), x)
    return flatten(x + (10 ** (low_db / 20) - 1) * lo + (10 ** (high_db / 20) - 1) * hi)


def ab_light(x):
    """The light-off thump (iaf-2026/docs/sound.md §1.2): the roar below 150 Hz under a swell that peaks at 0.3 s and
    dies by 1.2 s, the low-band overshoot the F-16's light-off shows over its steady burner."""
    t = np.arange(int(1.2 * SR)) / SR
    low = sosfiltfilt(butter(4, 150, fs=SR, output="sos"), x[: len(t)])
    return low * (t / 0.3) * np.exp(1 - t / 0.3) * np.minimum(1, (1.2 - t) / 0.2)


# name: (the CLIPS recording it is made from, what it is, function of that cut, level dB vrms)
DERIVED = {
    "sfx_ab_light": ("sfx_afterburner_thrust", "the light-off thump: the roar below 150 Hz under a 1.2 s swell",
                     ab_light, -19),
}


def gun_rate(x, period=220):
    """The M61's buzz at 100 rounds a second (iaf-2026/docs/sound.md §1.5): each shot of the recording (about 48 a
    second) found on its envelope and laid down every `period` samples (220 at 22050 Hz: 100.2 a second) under a Hann
    window two periods long (pitch-synchronous overlap-add), so the shot keeps its sound and only the rate changes."""
    e = np.abs(sosfiltfilt(butter(2, 300, "highpass", fs=SR, output="sos"), x))
    e = np.convolve(e, np.hanning(int(0.002 * SR)), "same")
    peaks = find_peaks(e, distance=int(0.7 * SR / 48.4))[0]
    w = np.hanning(2 * period)
    y = np.zeros(len(peaks) * period + 2 * period)
    for i, p in enumerate(peaks):
        g = x[max(p - period, 0): p + period]
        if len(g) == 2 * period:
            y[i * period: i * period + 2 * period] += g * w
    y = y[period: -period]
    return y[: len(y) - (len(y) - int(XFADE * SR)) % period]  # the loop's cross-fade starts on a shot


def touchdown(x):
    """The tyre skid with the struts' thump under it: 60 Hz falling over 0.12 s (inferred)."""
    t = np.arange(len(x)) / SR
    thump = tone(60, t) * np.exp(-t / 0.04) * (t < 0.12)
    return x / vrms(x) + 1.5 * thump


# CLIPS processed before the fades and the level
PROCESS = {"sfx_afterburner_thrust": ab_roar, "sfx_aircraft_fired_weapon_ost_gunbullet": gun_rate,
           "sfx_touchdown": touchdown}


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


def ogg(path, y):
    """The clip as Ogg Vorbis, quality 4 (the format the sim ships, iaf-2026/docs/sound.md §1)."""
    with tempfile.TemporaryDirectory() as d:
        wavfile.write(os.path.join(d, "a.wav"), SR, np.round(np.clip(y, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(d, "a.wav"), "-c:a", "libvorbis", "-q:a", "4",
                        path], check=True)


def main():
    dl = sys.argv[1]
    rows, cuts = [], {}
    for name, (sid, user, title, lic, a, b, level, loop, note) in CLIPS.items():
        x = decode(preview(dl, sid, user))
        x = x[int(a * SR): int((b + (XFADE if loop else 0)) * SR)]
        x = PROCESS.get(name, lambda y: y)(x)
        cuts[name] = x
        ogg(os.path.join(OUT, name + ".ogg"), finish(x, level, "loop" if loop else "once"))
        url = f"https://freesound.org/people/{user}/sounds/{sid}/"
        how = f"{a:g}-{b:g} s ({note}), {'loop, ' if loop else ''}{level} dB vrms"
        rows.append(f"| `{name}.ogg` | [{title}]({url}) | {user} | {lic} | {how} |")
    for name, (src, what, fn, level) in DERIVED.items():
        ogg(os.path.join(OUT, name + ".ogg"), finish(fn(cuts[src]), level, "once"))
        sid, user, title, lic = CLIPS[src][:4]
        url = f"https://freesound.org/people/{user}/sounds/{sid}/"
        rows.append(f"| `{name}.ogg` | [{title}]({url}) | {user} | {lic} | {what} (from `{src}`), {level} dB vrms |")
    for name, (what, fn, level, loop) in TONES.items():
        ogg(os.path.join(OUT, name + ".ogg"), finish(fn(), level, "as-is" if loop else "once"))
        rows.append(f"| `{name}.ogg` | {what} | Modern IAF (computed by this script) | {CC0} | "
                    f"{'loop, ' if loop else ''}{'' if level is None else f'{level} dB vrms'} |")
    with open(os.path.join(OUT, "voices.json"), encoding="utf-8") as f:
        v = json.load(f)
    vrows = [f"| {k} | [{d['model']}]({d['url']}) | {d['licence']} | {d['use']} |" for k, d in v["voices"].items()]
    with open(os.path.join(OUT, "SOURCES.md"), "w") as f:
        f.write(SOURCES_HEAD + "\n".join(rows) + "\n" + VOICES_HEAD + "\n".join(vrows) + "\n")
    print(f"{len(rows)} clips -> {OUT}")


VOICES_HEAD = """
## Voices

The speech clips (`voc_*`, `twr_*`, `num*`, `rwy*`, `acft_roger`, `endworld`) are Kokoro text to speech through
Betty's chain or the radio chain, made by `iaf-sim voices` (`crates/iaf-tools/src/sim_voices.rs`, Kokoro through
`tools/iaf-2026/kokoro_tts.py`; iaf-2026/docs/sound.md §5); their texts and voices are in [voices.json](voices.json).
Kokoro-82M v1.0 and its voice packs are Apache-2.0; its training data is public-domain, permissively licensed and
synthetic speech plus two CC BY sets, Koniwa `tnc` (CC BY 3.0) and SIWIS (CC BY 4.0). `kch2` (the radio click),
`key_on` / `key_off` (the press-to-talk click and the squelch tail around a call) and `twr_pause` (0.2 s of radio
hiss) are computed.

| voice | Kokoro voice | licence | speaks |
|---|---|---|---|
"""

SOURCES_HEAD = """# Modern IAF sound clips: sources

Every clip in this folder, where it comes from, its author and licence, and how it was made. The table is written
by `tools/iaf-2026/sounds.py`, which also makes the clips (see its header for the processing: the cut, fades or
loop cross-fade, the level as dB of the voiced RMS, a soft limit at -1 dBFS; 22050 Hz mono Ogg Vorbis, quality 4).
The recordings are freesound's HQ previews (Ogg Vorbis, 44.1 / 48 kHz) of each sound; CC0 needs no credit, and we
name every author anyway. "US Government video, public domain" is the uploader's statement of the recording's origin.
The rows that use each clip: [soundprop.json](soundprop.json).

| clip | source | author | licence | processing |
|---|---|---|---|---|
"""

if __name__ == "__main__":
    main()
