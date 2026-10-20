# Tower runway numbers

The tower's runway-number clips (`numNNN.wav`, NNN = runway 01-36) that the original install lacks. The game plays
one only when the install has no clip of that name (docs/radio.md §1). They are spoken digit by digit ("two five"),
like the install's.

- **Made with:** `tools/tower_numbers.py` (setup and run in its header), Piper TTS 1.8.0 (`piper-tts`, GPL-3.0-or-later).
- **Voice:** `en_US-john-medium` from rhasspy/piper-voices, revision `c10ece1aade47bb51c153c893d14e5bf8e5b7117`
  (`en_US-john-medium.onnx` sha256 `789c6c875726e627ddee93d51d8727859abe9c091c3d141591f4b83c2072e988`).
  - Model card: US English male, trained by Bryce Beattie on about 12.5 hours of LibriVox recordings
    (public domain), fine-tuned from his `kristin` voice (LibriVox recordings, public domain, trained from scratch).
  - The piper-voices repository is MIT licensed.
- **Processing:** 22050 Hz 16-bit mono like the install's clips; a 0.9 pre-emphasis and a 300-3000 Hz band-pass
  (the install's clips have no energy above 4 kHz or below 200 Hz); trimmed silence; scaled and soft-limited to the
  install's median voiced RMS (0.119) under its 0.79 peak. The median-length one of 7 takes per number.

## Licence

The clips are generated from public-domain training data with an MIT-licensed model and are released under this
repository's licence (GPL-3.0, `LICENSE` at the repository root). Attribution: the voice `john` by Bryce Beattie
(https://brycebeattie.com/files/tts/), LibriVox readers (https://librivox.org).
