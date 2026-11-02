# IAF 2026: sounds, voices and keys

**Terms:** AB = afterburner; Betty = the cockpit's recorded voice warnings; IPA = the International Phonetic Alphabet;
particle = one word file of a radio phrase (docs/radio.md §1); TTS = text to speech; VMS = the F-16's Voice Message
System; vrms = the RMS of the samples above 2 % of the peak (the pauses left out), in dB of full scale.

2 November 2026 (item E1b). The sim plays its own sounds and voices and reads its own key table. All three are
authored in `iaf-2026/data/` and compiled by `iaf-sim own` into the files and shapes the shared readers already read
(`sound_table.gd`, `radio.gd`, `key_table.gd`). Nothing comes from the original game: every clip is an openly
licensed recording, a tone we computed or our TTS. The readers take these files under `Settings.own_dir()` and
`Settings.keys_file()`, which the sim's settings point at `converted/own/` (item A1).

| what | authored in | made by | compiled to (under `assets/`) |
|---|---|---|---|
| sound effects | `data/sounds/*.wav`, `soundprop.json` | `tools/iaf-2026/sounds.py` | `converted/own/resource/soundfiles/soundprop.trx` + clips |
| voices, radio phrases | `data/sounds/voices.json` | `tools/iaf-2026/radio_voice.py --set` | the same folder: `phrasetemplates.trx`, `phraseparticalsdata.trx` + clips |
| keys | `data/keys.json` | by hand | `converted/own/keys.json` |

```sh
cargo run -p iaf-tools --bin iaf-sim -- own        # or: all
VENV/bin/python -I tools/iaf-2026/sounds.py DL      # remakes the effects from the downloads in DL
VENV/bin/python -I tools/iaf-2026/radio_voice.py --set iaf-2026/data/sounds/voices.json VOICES iaf-2026/data/sounds
```
The scripts' headers give the setup (a venv with `piper-tts==1.8.0`, numpy and scipy; ffmpeg; the Piper models in
VOICES). Piper varies from run to run, so a new `--set` run gives slightly different clips.

## 1. The sound set
One clip per sound code the shared flight code plays (docs/sound.md §3–§5): 29 CC0 recordings from freesound[^fs] and
7 computed tones. Each clip's source, author, licence and cut: [SOURCES.md](../data/sounds/SOURCES.md).
- **Format:** 22050 Hz, 16-bit, mono WAV, the format `sound_table.gd` plays; named by code
  (`sfx_weapon_exploded_ost_bomb.wav`). `iaf-sim own` refuses a clip in any other format.
- **Processing** (`sounds.py`): the cut; 5 ms fade in and 50 ms fade out, or for a loop the last 0.25 s cross-faded
  into the start (equal power); the tail below −50 dB of the peak cut; the level set as vrms; a soft limit at −1 dBFS.
  The recordings are freesound's HQ previews (Ogg Vorbis, 44.1 / 48 kHz): the original files need a login.
- **Rows** (`soundprop.json`, 112 rows): the columns of docs/sound.md §1 by name (`category` engine / effect /
  speech, `play` loop / once, `3d`, `min_m` / `max_m`, `volume_in` / `volume_out`, `channel`). The weapon sub codes
  share clips by kind: every missile one launch, flight loop and explosion; every bomb one release, fall loop and
  explosion. `SFX_DRY_THRUST` and `SFX_AFTERBURNER_THRUST` share the AB loop (the shared code plays them at pitch 0.8
  and 1.2). Our values (inferred): the engine at 0.6 in the cockpit, the gear and flaps at 0.75, explosions heard to
  3 km.
- **By name** (`soundprop.json` `by_name`): the files the shared code opens by name, not by code: `cock_g_02.wav`
  (the G strain, `g_effects.gd`), `endworld.wav` (the map edge, `terrain_view.gd`), `kch2.wav` (the radio click,
  `radio.gd`). `g_effects.gd`'s `cock_bty_over.wav` is left out: the VMS has no Over-G voice, so it stays silent.
- **Silent on purpose:** a code with no row plays nothing (`flight_sounds.gd play`): Betty's missile, Over-G and
  spin calls (§3).
- **Not played yet:** `SFX_WIND` (shares the air-brake loop) and `SFX_DOOR_OPEN` / `SFX_DOOR_CLOSE` (the canopy)
  have rows and clips but no caller.

### 1.1 Listening notes
Measured, not heard: a human listening pass at game volume is still open. Every clip below has no clipped sample,
less than 0.4 s of near-silence at its ends, and (loops) a seam no larger than the clip's usual sample step. The
original's clips of the same codes were measured for level only: ours are mostly within 3 dB.

| clip | s | vrms dB | peak dB | listen for |
|---|---|---|---|---|
| `cock_g_02` | 3.27 | -22.0 | -11.6 | a man's effort grunts for the G strain; check it does not sound comic |
| `sfx_afterburner_thrust` | 2.50 | -10.1 | -1.0 | from a 6 s recording that fades: check the loop does not pulse every 2.5 s |
| `sfx_aircraft_exploded` | 2.34 | -11.3 | -1.0 | a DoD video blast |
| `sfx_aircraft_fired_weapon_ost_bomb` | 0.40 | -14.4 | -1.3 | a metal clonk as the rack release |
| `sfx_aircraft_fired_weapon_ost_flare` | 1.00 | -14.0 | -4.5 | a vintage flare gun; the shells falling to the floor may be in the cut |
| `sfx_aircraft_fired_weapon_ost_gunbullet` | 1.75 | -12.0 | -3.1 | M61A2 burst loop: check for a rhythm break at the seam |
| `sfx_aircraft_fired_weapon_ost_heatmissile` | 3.00 | -13.3 | -1.1 | a ground anti-tank launch standing in for an air-launched missile |
| `sfx_button` | 0.35 | -20.0 | -2.5 | a guitar-pedal toggle; longer than the original's 30 ms click |
| `sfx_door_close` | 4.25 | -18.0 | -2.7 | cut by the loudness envelope only; check the lock thump is in it |
| `sfx_door_open` | 4.00 | -18.0 | -4.2 | cut by the loudness envelope only (USC vintage optical recording, noisy) |
| `sfx_entity_fired_weapon_ost_gunbullet` | 1.25 | -14.0 | -8.8 | Phalanx burst as the AI's gun and AAA |
| `sfx_fire_extinguisher` | 1.20 | -17.2 | -1.2 | one burst of a real extinguisher |
| `sfx_flaps` | 2.50 | -14.0 | -2.2 | 3 dB quieter than the original's; a steady motor, cut at 2.5 s with a fade |
| `sfx_ir_lock` | 1.00 | -16.0 | -14.5 | our lock tone |
| `sfx_ir_seek` | 1.00 | -18.0 | -15.4 | our growl; compare with a real AIM-9 tone |
| `sfx_landing` | 0.10 | – | – | silence (engine off) |
| `sfx_landing_gear` | 4.00 | -10.1 | -1.1 | 3 dB quieter than the original's; recorded for a flight sim (Aces High II) by its author |
| `sfx_object_specific_ost_bomb` | 3.00 | -24.0 | -13.7 | a falling whistle looped: may sound odd when it repeats |
| `sfx_object_specific_ost_heatmissile` | 3.00 | -20.0 | -10.8 | rocket roar loop for every missile's flight |
| `sfx_screech` | 2.75 | -16.7 | -1.0 | a metal sheet scrape for a belly landing |
| `sfx_speed_breakes` | 1.35 | -18.3 | -1.1 | a forklift's hydraulics: check it reads as an air brake |
| `sfx_speed_breakes_loop` | 6.00 | -20.0 | -8.8 | KC-135 camera wind (also SFX_WIND): check it is not too hissy in the cockpit |
| `sfx_splash` | 2.17 | -13.0 | -1.0 | a mix of CC0 splashes |
| `sfx_start_engine` | 3.00 | -12.0 | -1.2 | a parked F-16's idle; check it still sounds right pitched up to 1.375 at full dry power |
| `sfx_touchdown` | 0.60 | -13.0 | -1.4 | a tyre chirp (bike / car brakes) |
| `sfx_warning_wrn_aoa` | 1.00 | -24.0 | -20.9 | our beeps, 7 dB louder than the original's quiet tone |
| `sfx_warning_wrn_master` | 0.45 | -20.0 | -16.9 | ours; the original had no file |
| `sfx_warning_wrn_missile_launch` | 1.00 | -20.0 | -17.0 | our warble |
| `sfx_warning_wrn_new_guy` | 0.35 | -24.0 | -20.8 | our three beeps, much louder than the original's (-38 dB) |
| `sfx_weapon_exploded_ost_bomb` | 1.68 | -10.3 | -1.1 | 1.7 s, shorter than the original's 5.5 s: may need a longer rumble |
| `sfx_weapon_exploded_ost_gunbullet` | 0.45 | -12.5 | -1.1 | coins on a music stand pitched down (bullet hits) |
| `sfx_weapon_exploded_ost_rocket` | 0.85 | -14.9 | -1.0 | a firework bang for rocket, chaff and flare bursts |
| `sfx_weapon_hit_target` | 3.62 | -14.9 | -1.0 | a debris crash |

## 2. The radio filter
`tools/iaf-2026/radio_voice.py` turns Piper's speech into a cockpit voice, on 22050 Hz mono:
1. pre-emphasis (x[n] − 0.9 x[n−1]), a headset microphone's presence lift;
2. band-pass 300–3000 Hz (4th-order Butterworth, zero phase), the voice band of a radio;
3. slight distortion: half the signal through tanh(2.5 x);
4. level: vrms to −17.9 dB (0.127, the level of `shared/extra/tower_numbers`, which match the original speech), then a
   soft limit at −2 dBFS;
5. hiss: band-passed noise at −42 dB;
6. squelch: a 2 ms key-up click and 40 ms of noise before the voice; a 120 ms noise tail and a click after it.

| mode | steps | used for |
|---|---|---|
| `radio` | 1–6 | a whole transmission in one clip (friendly-fire calls, eject, map edge) |
| `particle` | 1–5, trimmed tight | the tower's phrase parts, which `radio.gd` plays back to back |
| `intercom` | 1–4 | Betty (the intercom has no squelch) |

`kch2.wav` is the squelch alone and `twr_pause.wav` (the `,` particle) 0.2 s of hiss. All noise and clicks are
computed and seeded. Each voice clip is the median-length of five Piper runs, which drops a run with a stray sound
after the words; a particle is also cut at its first pause over 0.3 s. `--ipa` speaks IPA as written (§5).

## 3. The voices
Three Piper voices[^piper], all trained on LibriVox recordings (public domain); the Piper models are MIT:

| role | Piper voice | speaks |
|---|---|---|
| Betty | `en_US-kristin-medium` | the VMS calls |
| tower | `en_US-john-medium` | the tower's particles, the friendly-fire call, the map edge |
| pilot | `en_US-norman-medium` | "Roger", eject, the friendly-fire calls of the target and the wingman |

**Betty** follows the F-16 VMS, as [real-betty.md](../../docs/real-betty.md) §5 proposes for all three jets (the
Sufa and the Barak are F-16s; the F-35I's set is open, so it takes the same):

| sub code | says | why |
|---|---|---|
| `BTY_ALT`, `BTY_PULL_UP`, `BTY_CAUTION` | "Altitude. Altitude." / "Pull up. Pull up." / "Caution. Caution." | VMS |
| `BTY_FIRE`, `BTY_ENGINE` | "Warning. Warning." | the VMS says WARNING for a fire or an engine failure |
| `BTY_FUEL`, `BTY_BINGO` | "Bingo. Bingo." | the VMS's fuel call |
| `BTY_MISS`, `BTY_OVER_G`, `BTY_SPIN` | nothing (no row) | not in the VMS list; the launch has the RWR tone |
| `BTY_LOCK`, `BTY_CHAFF_FLARE`, `BTY_LOW`, `BTY_OUT`, `BTY_COUNTER`, `BTY_JAMMER`, `BTY_DATA`, `BTY_IFF` | the word | VMS; our sub codes, no caller yet |

Saying each warning twice is inferred. Betty is level with the original's Betty (vrms −18.3 dB against about −17).

**The tower** speaks through the original's phrase engine (docs/radio.md §1): `iaf-sim own` writes
`phrasetemplates.trx` and `phraseparticalsdata.trx` from `voices.json` (`templates`, `particles`), with our own
wording. The templates are the ones `radio.gd` calls (`ACFT_TAXI_TO_RUNWAY`, `ACFT_CLEAR_TO_LINEUP` / `_NW`,
`ACFT_HOLD_POS`, `ACFT_CLEAR_TO_TAKEOFF`, `ACFT_PROCEED_TO_RUNWAY`, `ACFT_CLEAR_TO_LAND` / `_NW`,
`ACFT_GO_AROUND_RUNWAY`, `ACFT_TAXI_TO_PARK`, `ACFT_GEARS_NOT_OPEN`, `ACFT_ROGER`) plus `ACFT_CLEAR_TO_START` for
item E3's start-up request. Example: `ACFT_TAXI_TO_RUNWAY` = `%S1 , %S2 , TAXI_RWY %D1` → "Alpha, good morning, taxi
to runway 25 right". The particles cover the callsigns Alpha–Delta, the greetings, the winds 10 / 15 / 20 kt, every
runway number 1–36 (spoken digit by digit, "two five") and the letters `RWY_L` / `RWY_R` / `RWY_C`.

## 4. Keys
`data/keys.json` holds the 117 commands of docs/controls.md §3 with our own English and Hebrew labels, the default
key as text ("Ctrl + Q"), the joystick button, the press / release commands and `shown`. `iaf-sim own` compiles it to
the shape of `iaf-convert keys`' output (records with `dik` / `modifiers` / `label` / `label_he`, `key_names`,
`modifiers`, `button_format`). It refuses:
- a key name outside our scancode table, which holds exactly the keys `key_table.gd` can press (a test reads the
  reader's `DIK_TO_KEY`);
- two records on one key and modifier;
- a shown record without a label. Records 115 and 116 have none, so the "All keys on the Keyboard page" list leaves
  them out, as the original's does.

Records 108–114 (the original's cheats) are labelled by what they do (docs/controls.md §4), and records 92 / 93 by
their press command (the doc's names for them look swapped).

## 5. Hebrew: waiting for a decision
Piper's only Hebrew voice is `he_IL-saspeech-medium`. It is trained on SASPEECH[^saspeech], whose licence is custom
and non-commercial: the recordings belong to the Israeli Public Broadcasting Corporation (Kan), the speaker is the
journalist Shaul Amsterdamski, and broadcast use and anything that suggests Kan's endorsement are not allowed. That
is not an open licence like the rest of the sim's data. The choice is the user's (2026-11-02, pending):
1. ship SASPEECH clips under its non-commercial terms;
2. English only for now;
3. record Hebrew ourselves.

Until then no Hebrew clip is rendered or committed. `voices.json` `he` holds the Hebrew lines' texts and IPA ready to
render (`radio_voice.py --ipa`). Tested 2026-11-02: Piper's Hebrew phonemizer (Nakdimon diacritics, then rule-based
IPA) puts the stress on the last syllable of almost every word ("mˈigdal" for migdˈal, "ʁuχˈa" for ʁˈuaχ), with or
without diacritics in the text; hand-written IPA fixes it, so every Hebrew line carries its IPA. A sample tower call
was made with it for the user's approval (not in the repo).

## 6. Credits the sim's wizard and credits roll need
The setup wizard (item A3) and the credits roll live outside this branch's folders; they need these lines (also in
[docs/credits.md](../../docs/credits.md)):
- **Sound effects** (freesound.org, CC0): ikbenraar, TiesWijnen, pillwave, 77Pacer, nuckan, qubodup, Seidhepriest,
  Jetrod, craigsmith (the USC Gold / Red / Sunset Editorial libraries), LilMati, Rudmer_Rotteveel, pushkin, xkeril,
  elliott.klein, DeqstersLab, RutgerMuller, SoundDesignForYou, tranzfusion.
- **Voices:** Piper text to speech (MIT), the voices kristin, john and norman (LibriVox recordings, public domain).
- **Hebrew voice:** only if option 1 of §5 is chosen: SASPEECH, © Kan, the Israeli Public Broadcasting Corporation,
  non-commercial licence.

## 7. Open
- A human listening pass at game volume (§1.1).
- The Hebrew voice (§5).
- The AWACS, wingman-command, waypoint and flight-report phrases (`radio.gd`'s other templates have no particles yet,
  so they are silent).
- The squelch at run time: a tower phrase is a chain of particles without squelch; item E3's radio menu plays
  `kch2.wav` around it or adds the clicks.
- One engine sound set for all three jets (one clip per code in the shared table).

## 8. Checks
- `cargo test -p iaf-tools --lib sim::`: every row's clip and every particle's clip exists and is a 22050 Hz 16-bit
  mono WAV; every code the shared code plays has a row and every file it opens by name exists; the templates `radio.gd`
  calls exist and name only particles; a stale file is removed; the key table has 117 records, labels where shown, no
  key bound twice, and only keys the reader can press.
- Godot's `AudioStreamWAV.load_from_file` loaded every clip of the compiled tables (2026-11-02).

[^fs]: Freesound, each sound's page linked in SOURCES.md; CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
[^piper]: Piper voices (rhasspy/piper-voices), each voice's MODEL_CARD names its dataset: https://huggingface.co/rhasspy/piper-voices
[^saspeech]: OpenSLR, "SASPEECH" (SLR134), licence summary: https://www.openslr.org/134/
