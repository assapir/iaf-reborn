#!/usr/bin/env python3
"""Kokoro text to speech for `iaf-sim voices` (modern-iaf/docs/sound.md §5): the only Python step of the voices.

Reads a JSON list on stdin, [{"text": ..., "voice": "af_nicole", "speed": 1.0, "out": "/abs/raw.wav"}, ...], and
writes each line's speech as a 24000 Hz mono 32-bit float WAV, with no processing: the radio chain, the trim and the
level are iaf-sim's. Prints a JSON list on stdout, one {"out", "split"} per line: `split` is [the end of the word
before the line's ";", the start of the word after it] in seconds (Kokoro's own word timing), or null (crates/iaf-tools/src/sim_voices.rs). The model and voice packs come from Hugging Face
(hexgrad/Kokoro-82M, Apache-2.0) into its cache on the first run.

Setup (once, outside the repo):
    python3 -m venv --system-site-packages VENV
    VENV/bin/pip install "kokoro>=0.9.4" scipy num2words spacy phonemizer-fork espeakng-loader; espeak-ng
Run through iaf-sim:  IAF_KOKORO_PYTHON=VENV/bin/python cargo run --release -p iaf-tools --bin iaf-sim -- voices
"""

import contextlib
import json
import sys

import numpy as np
from scipy.io import wavfile
from kokoro import KPipeline


def main():
    lines = json.load(sys.stdin)
    with contextlib.redirect_stdout(sys.stderr):  # stdout carries only the answer (spaCy's first-run download prints)
        pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")  # "a": American English
    done = []
    for line in lines:
        # split_pattern=None: the whole line in one pass, so it flows as one sentence.
        rs = list(pipe(line["text"], voice=line["voice"], speed=line["speed"], split_pattern=None))
        wavfile.write(line["out"], 24000, np.concatenate([r.audio.numpy() for r in rs]).astype(np.float32))
        toks = rs[0].tokens if len(rs) == 1 else []
        at = [i for i, t in enumerate(toks) if t.text == ";"]
        split = [toks[at[0] - 1].end_ts, toks[at[0] + 1].start_ts] if at else None
        done.append({"out": line["out"], "split": split})
        print(line["out"], file=sys.stderr)
    json.dump(done, sys.stdout)


if __name__ == "__main__":
    main()
