#!/usr/bin/env python3
"""Modern IAF's voices: Piper TTS through the radio filter (iaf-2026/docs/sound.md §2).

The chain, in order, on 22050 Hz mono (the game's speech format, docs/radio.md §1):
  1. pre-emphasis (x[n] - 0.9 x[n-1]): a headset mic's presence lift; the TTS's spectrum centre is ~0.5 kHz;
  2. band-pass 300-3000 Hz, 4th-order Butterworth, zero phase: the voice band of an aviation radio / intercom;
  3. slight distortion: soft clip tanh(DRIVE x) / tanh(DRIVE) after normalising the peak to 1, mixed MIX wet;
  4. level: voiced RMS to TARGET_RMS, then a soft limit at PEAK (-2 dBFS), repeated until both hold;
  5. hiss: band-passed white noise at NOISE_DB under the voice, for the whole clip (radio only);
  6. squelch (radio only): a key-up click (2 ms) + 40 ms noise before the voice, a 120 ms noise tail with a
     click after it (the receiver's squelch closing).
Modes: "radio" all six steps; "intercom" (Betty) 1-4; "particle" 1-5: a part of a tower phrase, which radio.gd plays
back to back with the others, so the hiss runs through and no squelch cuts in between. "kch2.wav" (the radio
click radio.gd plays when no tower answers) is the squelch alone; "twr_pause.wav" (the "," particle) 0.2 s of hiss.
Every sound in the chain is computed here (no sample from anywhere). The noise is seeded, so a run is repeatable.

Setup (once, outside the repo):
    python3 -m venv VENV && VENV/bin/pip install piper-tts==1.8.0 numpy scipy
    voices: https://huggingface.co/rhasspy/piper-voices (model .onnx + .onnx.json)
Run:
    VENV/bin/python -I tools/iaf-2026/radio_voice.py --voice V.onnx --text "..." [--intercom] out.wav
    VENV/bin/python -I tools/iaf-2026/radio_voice.py --voice V.onnx --ipa --text "miɡdˈal ..." out.wav
    VENV/bin/python -I tools/iaf-2026/radio_voice.py --in raw.wav [--intercom] out.wav   # filter only
    VENV/bin/python -I tools/iaf-2026/radio_voice.py --set iaf-2026/data/sounds/voices.json VOICES iaf-2026/data/sounds
        # every clip of voices.json ("clips": file, voice, say, mode) with VOICES/<model>.onnx
"""

import argparse
import functools
import json
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfiltfilt

SR = 22050
TILT = 0.9
BAND = (300, 3000)
DRIVE = 2.5
MIX = 0.5
TARGET_RMS = 0.127  # the voiced RMS (vrms) of shared/extra/tower_numbers, which match the original speech level
PEAK = 0.79
NOISE_DB = -42.0
SEED = 2026


def tts(model, text, length_scale=1.0, ipa=False):
    """Piper's speech of `text`; with `ipa` the text is IPA phonemes, spoken as written (the Hebrew phonemizer
    puts the stress on the last syllable of almost every word: "mˈigdal" for migdˈal)."""
    from piper import SynthesisConfig

    v = load_voice(model)
    cfg = SynthesisConfig(length_scale=length_scale)
    if ipa:
        x = v.phoneme_ids_to_audio(v.phonemes_to_ids(list(text)), cfg)
    else:
        x = np.concatenate([c.audio_int16_array for c in v.synthesize(text, cfg)]).astype(float) / 32768
    return to_sr(x, v.config.sample_rate)


@functools.cache
def load_voice(model):
    from piper import PiperVoice

    return PiperVoice.load(model)


def to_sr(x, sr):
    g = np.gcd(sr, SR)
    return x if sr == SR else resample_poly(x, SR // g, sr // g)


def read(path):
    sr, x = wavfile.read(path)
    x = x.astype(float) / (32768 if x.dtype == np.int16 else 1)
    return to_sr(x.mean(axis=1) if x.ndim == 2 else x, sr)


def trim(x, rel=0.02):
    """The clip between the first and last sample above `rel` of the peak, 10 ms margin each side."""
    idx = np.nonzero(np.abs(x) > rel * np.abs(x).max())[0]
    m = SR // 100
    return x[max(idx[0] - m, 0) : idx[-1] + m]


def trim_tight(x):
    """A particle: the 10 ms frames from the first to the last one above 10 % of the loudest frame's RMS (as
    tools/tower_numbers.py) up to the first quiet run over 0.3 s, so the parts of a phrase follow each other
    without dead air."""
    h = SR // 100
    e = np.sqrt(np.mean(x[: len(x) // h * h].reshape(-1, h) ** 2, axis=1))
    idx = np.nonzero(e > 0.1 * e.max())[0]
    gaps = np.nonzero(np.diff(idx) > 30)[0]  # a quiet run over 0.3 s: Piper's stray sound after a short phrase follows
    last = idx[gaps[0]] if len(gaps) else idx[-1]
    return x[idx[0] * h : (last + 1) * h]


def take(model, text, takes=5):
    """Piper varies from run to run, and a run may add a stray sound after the words: of `takes` runs, the one of
    median length."""
    xs = sorted((tts(model, text) for _ in range(takes)), key=len)
    return xs[takes // 2]


def vrms(x):
    """The RMS of the samples above 2 % of the peak (the pauses left out)."""
    return np.sqrt(np.mean(x[np.abs(x) > 0.02 * np.abs(x).max()] ** 2))


def noise(n, rng, db):
    sos = butter(2, BAND, btype="bandpass", fs=SR, output="sos")
    w = sosfiltfilt(sos, rng.standard_normal(n))
    return w / np.sqrt(np.mean(w**2)) * 10 ** (db / 20)


def click(rng):
    n = int(0.002 * SR)
    return rng.standard_normal(n) * np.hanning(n) * 0.25


def squelch(rng):
    tail = noise(int(0.12 * SR), rng, -24) * np.linspace(1, 0.3, int(0.12 * SR))
    return np.concatenate([click(rng), tail, click(rng)])


def radio(x, mode="radio"):
    rng = np.random.default_rng(SEED)
    x = trim_tight(x) if mode == "particle" else trim(x)
    x = np.append(x[0], x[1:] - TILT * x[:-1])
    x = sosfiltfilt(butter(4, BAND, btype="bandpass", fs=SR, output="sos"), x)
    x = x / np.abs(x).max()
    x = (1 - MIX) * x + MIX * np.tanh(DRIVE * x) / np.tanh(DRIVE)
    for _ in range(4):
        x = PEAK * np.tanh(x * TARGET_RMS / vrms(x) / PEAK)
    pad = np.zeros(int(0.01 * SR))
    if mode == "intercom":
        return np.concatenate([pad, x, pad])
    if mode == "particle":
        x = np.concatenate([pad, x, pad])
        return x + noise(len(x), rng, NOISE_DB)
    x = x + noise(len(x), rng, NOISE_DB)
    return np.concatenate([pad, click(rng), noise(int(0.04 * SR), rng, -26), x, squelch(rng), pad])


def write(path, y):
    wavfile.write(path, SR, np.round(np.clip(y, -1, 1) * 32767).astype(np.int16))
    print(f"{path}: {len(y) / SR:.2f} s, peak {np.abs(y).max():.2f}")


def render_set(spec, voices, out):
    """Every clip of the voice set `spec` (voices.json) into `out`, with the Piper models in `voices`."""
    d = json.load(open(spec, encoding="utf-8"))
    rng = np.random.default_rng(SEED)
    write(os.path.join(out, "kch2.wav"), np.concatenate([np.zeros(int(0.01 * SR)), squelch(rng)]))
    write(os.path.join(out, "twr_pause.wav"), noise(int(0.2 * SR), rng, NOISE_DB))
    for c in d["clips"]:
        model = os.path.join(voices, d["voices"][c["voice"]]["model"] + ".onnx")
        write(os.path.join(out, c["file"]), radio(take(model, c["say"]), c["mode"]))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out", nargs="+", help="out.wav, or with --set: VOICES OUT_DIR")
    p.add_argument("--set", help="voices.json: render its whole set")
    p.add_argument("--voice")
    p.add_argument("--text")
    p.add_argument("--ipa", action="store_true", help="--text is IPA phonemes (e.g. a Hebrew stress fix)")
    p.add_argument("--in", dest="inp")
    p.add_argument("--length-scale", type=float, default=1.0)
    p.add_argument("--intercom", action="store_true", help="no hiss, no squelch (Betty)")
    a = p.parse_args()
    if a.set:
        render_set(a.set, *a.out)
        return
    x = read(a.inp) if a.inp else tts(a.voice, a.text, a.length_scale, a.ipa)
    write(a.out[0], radio(x, "intercom" if a.intercom else "radio"))


if __name__ == "__main__":
    main()
