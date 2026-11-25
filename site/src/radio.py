#!/usr/bin/env python3
"""Makes the page's radio exchange (content.py RADIO) into site/audio/radio_<lang>.mp3 from the game's own clips, as
the sim plays them (shared/audio/radio.gd say): each call framed by key_on / key_off, the template's particles joined
where a joined clip exists in that language, the radio's gap after a call to the AWACS, then a second of quiet.
Local only (needs the built assets and ffmpeg): python3 -I site/src/radio.py"""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from content import RADIO  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(HERE)
SOUNDS = os.path.join(REPO, "assets/converted/own/resource/soundfiles")
VOICES = json.load(open(os.path.join(REPO, "modern-iaf/data/sounds/voices.json")))
PAUSE_S = 1.0  # the quiet after each call (the user, 25 Nov 2026: a second after the radio voices)


COMMON = ("key_on.ogg", "key_off.ogg", "radio_gap.ogg", "twr_pause.ogg")  # the radio's own, in both languages


def clip(name, lang, role):
    """The clip's path in the language spoken (Hebrew: in the cast's voice for the role), None when it has none."""
    p = os.path.join(SOUNDS, name) if lang == "en" or name in COMMON else os.path.join(SOUNDS, "he", RADIO["cast_he"][role], name)
    return p if os.path.exists(p) else None


def wavs(template, args, lang, role):
    """radio.gd expand + joined_wavs: the template's keys, the longest run with a clip joined."""
    keys = []
    for w in VOICES["templates"][template].split():
        keys.append(args[int(w[2:]) - 1] if w.startswith("%S") else w)
    out, i, parts = [], 0, VOICES["particles"]
    while i < len(keys):
        j = len(keys)
        while j > i + 1:
            p = parts.get("+".join(keys[i:j]))
            if p and clip(p["file"], lang, role):
                break
            j -= 1
        c = clip(parts["+".join(keys[i:j])]["file"], lang, role)
        if not c:
            sys.exit(f"no {lang} clip for {keys[i:j]}")
        out.append(c)
        i = j
    return out


def main():
    os.makedirs(os.path.join(HERE, "audio"), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        quiet = os.path.join(tmp, "quiet.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", str(PAUSE_S),
                        quiet], check=True)
        for lang in ("en", "he"):
            seq = []
            for role, template, args, *_ in RADIO["lines"]:
                seq += [clip("key_on.ogg", lang, role)] + wavs(template, args, lang, role) + [clip("key_off.ogg", lang, role)]
                seq += [clip("radio_gap.ogg", lang, role)] if template == "PILOT_CALL" else [quiet]
            seq.append(quiet)
            inputs = sum((["-i", f] for f in seq), [])
            mix = "".join(f"[{n}:a]aresample=24000,aformat=channel_layouts=mono[a{n}];" for n in range(len(seq)))
            mix += "".join(f"[a{n}]" for n in range(len(seq))) + f"concat=n={len(seq)}:v=0:a=1[out]"
            out = os.path.join(HERE, "audio", f"radio_{lang}.mp3")
            subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", mix, "-map", "[out]",
                            "-c:a", "libmp3lame", "-b:a", "64k", "-map_metadata", "-1", out], check=True)
            print(out, os.path.getsize(out))


if __name__ == "__main__":
    main()
