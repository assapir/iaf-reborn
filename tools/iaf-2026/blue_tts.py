#!/usr/bin/env python3
"""BlueTTS text to speech for `iaf-sim voices --he` (modern-iaf/docs/sound.md §5.4): the Hebrew radio lines.

Reads a JSON list on stdin, [{"text": "<Hebrew>", "voice": "david", "speed": 1.0, "ipa": {"<word>": "<IPA>"},
"out": "/abs/raw.wav"}, ...], and writes each line's speech as a 24000 Hz mono 32-bit float WAV (BlueTTS speaks at
44100 Hz; ffmpeg resamples), with no other processing: the radio chain, the trim and the level are iaf-sim's, as for
Kokoro (kokoro_tts.py). `ipa` replaces the G2P's reading of those words (voices.json `he.ipa`). Prints a JSON list on
stdout, one {"out", "split": null} per line. Each line starts from the same seed, so a run repeats.

Setup (once, outside the repo; modern-iaf/docs/research/hebrew-voices.md §6 lists each file with its licence):
    IAF_BLUE_DIR (default ~/.cache/hebrew-tts-eval) holding src/BlueTTS (github.com/maxmelichov/BlueTTS, git 91b1789),
    models/bluev3/{onnx,voices} (the BlueV3 ONNX release, int8 vector estimator) and
    models/renikudplus/model_int8.onnx (RenikudPlus G2P); a venv with onnxruntime, numpy, soundfile, renikud-plus.
Run through iaf-sim:  IAF_BLUE_PYTHON=VENV/bin/python target/release/iaf-sim voices --he
"""

import json
import os
import re
import subprocess
import sys

import numpy as np
import soundfile

E = os.path.expanduser(os.environ.get("IAF_BLUE_DIR", "~/.cache/hebrew-tts-eval"))
sys.path.insert(0, f"{E}/src/BlueTTS")
from src.blue_onnx import BlueTTS, load_voice_style  # noqa: E402
from renikud_onnx import G2P  # noqa: E402

SR = 24000
SEED = 2026
WORD = re.compile(r"[^\s,.!?]+")


def ipa(g2p, text, fix):
    """The G2P's IPA of `text`, the words of `fix` read as given."""
    out = g2p.phonemize(text)
    if not fix:
        return out
    he, ph = WORD.findall(text), list(WORD.finditer(out))
    if len(he) != len(ph):
        sys.exit(f"blue_tts: {text!r}: {len(he)} words but {len(ph)} in the IPA {out!r}")
    for w, m in reversed(list(zip(he, ph))):
        if w in fix:
            out = out[: m.start()] + fix[w] + out[m.end() :]
    return out


def main():
    lines = json.load(sys.stdin)
    # The answer goes to the real stdout; anything the model's code prints goes to stderr.
    answer = os.fdopen(os.dup(1), "w")
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    tts = BlueTTS(onnx_dir=f"{E}/models/bluev3/onnx", style_json=f"{E}/models/bluev3/voices/david.json",
                  renikud_path=f"{E}/models/renikudplus/model_int8.onnx")
    g2p = G2P(f"{E}/models/renikudplus/model_int8.onnx")
    styles = {}
    done = []
    for line in lines:
        v = line["voice"]
        if v not in styles:
            styles[v] = load_voice_style([f"{E}/models/bluev3/voices/{v}.json"])
        np.random.seed(SEED)
        x, sr = tts.synthesize(ipa(g2p, line["text"], line.get("ipa") or {}), lang="he", style=styles[v],
                               speed=line["speed"], text_is_phonemes=True)
        raw = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
                              "-ar", str(SR), "-f", "f32le", "-"], input=np.asarray(x, np.float32).tobytes(),
                             capture_output=True, check=True).stdout
        soundfile.write(line["out"], np.frombuffer(raw, np.float32), SR, subtype="FLOAT")
        done.append({"out": line["out"], "split": None})
        print(line["out"], file=sys.stderr)
    json.dump(done, answer)
    answer.close()


if __name__ == "__main__":
    main()
