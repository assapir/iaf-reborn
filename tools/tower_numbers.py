#!/usr/bin/env python3
"""The tower's runway-number clips the install lacks (docs/radio.md §1, "Num").

The tower says the runway as RunwayNumber / 10 through the particle NumNNN (num001..num036). The install ships only
some of them; this speaks the missing ones with Piper TTS and the voice en_US-john-medium (public-domain LibriVox data), then
matches the originals: 22050 Hz 16-bit mono, the radio band (300-3000 Hz, nothing of the originals is above 4 kHz
or below 200 Hz), the voiced RMS of the install's NumNNN clips, the peak at their 0.79, the silence trimmed.
The wording follows the originals: digit by digit with a leading zero ("zero three", "two seven"). It also speaks a
parallel runway's letter (left, right, center). A clip already in game/extra/tower_numbers is kept: delete it to
make it again.

Setup (once, under ~/.cache, not system-wide):
    python3 -m venv ~/.cache/iaf-tts/venv && ~/.cache/iaf-tts/venv/bin/pip install piper-tts==1.8.0 numpy scipy
    voice: https://huggingface.co/rhasspy/piper-voices/tree/c10ece1aade47bb51c153c893d14e5bf8e5b7117/en/en_US/john/medium
      (en_US-john-medium.onnx + .onnx.json) into ~/.cache/iaf-tts/voices
Run:
    ~/.cache/iaf-tts/venv/bin/python -I tools/tower_numbers.py [voice.onnx]
"""

import os
import sys

import numpy as np
from piper import PiperVoice, SynthesisConfig
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTALL = os.path.join(ROOT, "assets/install/resource/soundfiles")
OUT = os.path.join(ROOT, "game/extra/tower_numbers")
VOICE = os.path.expanduser("~/.cache/iaf-tts/voices/en_US-john-medium.onnx")
SR = 22050
PEAK = 0.79  # the originals' peak (-2 dBFS)
TILT = 0.9  # pre-emphasis: the originals' spectrum centre is 0.7-1.8 kHz, the TTS's ~0.5 kHz
TAKES = 7  # the TTS varies from run to run
DIGITS = "zero one two three four five six seven eight nine".split()
# A parallel runway's letter after the number ("two five left"; docs/radio.md §1): rwyl / rwyr / rwyc.wav.
LETTERS = ["left", "right", "center"]


def voiced(x):
    """The clip between the first and last 10 ms frame whose RMS is above 10 % of the loudest
    frame's, up to the first quiet run over 0.3 s."""
    h = SR // 100
    e = np.sqrt(np.mean(x[:len(x) // h * h].reshape(-1, h) ** 2, axis=1))
    idx = np.nonzero(e > 0.1 * e.max())[0]
    gaps = np.nonzero(np.diff(idx) > 30)[0]  # a quiet run over 0.3 s: the TTS's stray trailing sound follows
    last = idx[gaps[0]] if len(gaps) else idx[-1]
    return x[idx[0] * h:(last + 1) * h]


def say(voice, word):
    cfg = SynthesisConfig(length_scale=1.0)
    return np.concatenate([c.audio_int16_array for c in voice.synthesize(word, cfg)]).astype(float) / 32768


def load(path):
    sr, x = wavfile.read(path)
    assert sr == SR and x.dtype == np.int16 and x.ndim == 1, path
    return x.astype(float) / 32768


def main():
    voice = PiperVoice.load(sys.argv[1] if len(sys.argv) > 1 else VOICE)
    assert voice.config.sample_rate == SR
    have = {f.lower() for f in os.listdir(INSTALL)}
    refs = sorted(f for f in have if f.startswith("num0") and f.endswith(".wav"))
    rms = float(np.median([np.sqrt(np.mean(voiced(load(os.path.join(INSTALL, f))) ** 2)) for f in refs]))
    band = butter(4, [300, 3000], btype="bandpass", fs=SR, output="sos")
    os.makedirs(OUT, exist_ok=True)
    clips = [("num%03d.wav" % n, " ".join(DIGITS[int(d)] for d in "%02d" % n)) for n in range(1, 37)]
    clips += [(f"rwy{w[0]}.wav", w) for w in LETTERS]
    for name, words in clips:
        if name in have or os.path.exists(os.path.join(OUT, name)):
            continue
        takes = []
        for _ in range(TAKES):
            x = say(voice, words + ".")
            takes.append(voiced(sosfiltfilt(band, np.append(x[0], x[1:] - TILT * x[:-1]))))
        x = sorted(takes, key=len)[TAKES // 2]  # the median length: a take with a stray sound or a lost digit is an outlier
        for _ in range(4):  # the RMS, then a soft limit at the originals' peak, until both hold
            x = PEAK * np.tanh(x * rms / np.sqrt(np.mean(x ** 2)) / PEAK)
        x = np.concatenate([np.zeros(int(0.01 * SR)), x, np.zeros(int(0.01 * SR))])
        wavfile.write(os.path.join(OUT, name), SR, np.round(x * 32767).astype(np.int16))
        print(f"{name}  {words:12s} {len(x) / SR:.2f} s")
    print(f"target RMS {rms:.3f} (median of {len(refs)} install clips)")


if __name__ == "__main__":
    main()
