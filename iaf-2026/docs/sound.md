# Modern IAF: sounds, voices and keys

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
One clip per sound code the shared flight code plays (docs/sound.md §3–§5): 29 CC0 recordings from freesound[^fs], one
clip made from one of them (the afterburner's light-off, §1.2) and 8 computed tones (with the JFS whine, §1.4). Each clip's source, author, licence
and cut: [SOURCES.md](../data/sounds/SOURCES.md).
- **Format:** 22050 Hz, 16-bit, mono WAV, the format `sound_table.gd` plays; named by code
  (`sfx_weapon_exploded_ost_bomb.wav`). `iaf-sim own` refuses a clip in any other format.
- **Processing** (`sounds.py`): the cut; 5 ms fade in and 50 ms fade out, or for a loop the last 0.25 s cross-faded
  into the start (equal power); the tail below −50 dB of the peak cut; the level set as vrms; a soft limit at −1 dBFS.
  The recordings are freesound's HQ previews (Ogg Vorbis, 44.1 / 48 kHz): the original files need a login.
- **Rows** (`soundprop.json`, 114 rows): the columns of docs/sound.md §1 by name (`category` engine / effect /
  speech, `play` loop / once, `3d`, `min_m` / `max_m`, `volume_in` / `volume_out`, `channel`). The weapon sub codes
  share clips by kind: every missile one launch, flight loop and explosion; every bomb one release, fall loop and
  explosion. `SFX_DRY_THRUST` and `SFX_AFTERBURNER_THRUST` (AB stages 1 and 2) share the AB loop, which the sim plays at
  its own pitch (§1.2); `SFX_AB_LIGHT` is the sim's own row for the light-off, `SFX_JFS` for the JFS whine (§1.4). Our values (inferred): the engine at 0.6
  in the cockpit, the gear and flaps at 0.75, explosions heard to 3 km.
- **By name** (`soundprop.json` `by_name`): the files the shared code opens by name, not by code: `cock_g_02.wav`
  (the G strain, `g_effects.gd`), `endworld.wav` (the map edge, `terrain_view.gd`), `kch2.wav` (the radio click,
  `radio.gd`). `g_effects.gd`'s `cock_bty_over.wav` is left out: the VMS has no Over-G voice, so it stays silent.
- **Silent on purpose:** a code with no row plays nothing (`flight_sounds.gd play`): Betty's missile, Over-G and
  spin calls (§3).
- **Not played yet:** `SFX_DOOR_OPEN` (the canopy opening) has a row and a clip but no caller. `SFX_WIND` (§1.6)
  and `SFX_DOOR_CLOSE` (§1.7) play in the sim since 9 November 2026.

### 1.1 Listening notes
Measured, not heard: a human listening pass at game volume is still open. Every clip below has no clipped sample,
less than 0.4 s of near-silence at its ends, and (loops) a seam no larger than the clip's usual sample step. The
original's clips of the same codes were measured for level only: ours are mostly within 3 dB.

| clip | s | vrms dB | peak dB | listen for |
|---|---|---|---|---|
| `cock_g_02` | 3.27 | -22.0 | -11.6 | a man's effort grunts for the G strain; check it does not sound comic |
| `sfx_ab_light` | 1.20 | -19.0 | -8.1 | the light-off thump under the rising burner (§1.2) |
| `sfx_afterburner_thrust` | 3.00 | -8.3 | -1.0 | two RNLAF F-16s taking off, equalised and flattened (§1.2) |
| `sfx_aircraft_exploded` | 2.34 | -11.3 | -1.0 | a DoD video blast |
| `sfx_aircraft_fired_weapon_ost_bomb` | 0.40 | -14.4 | -1.3 | a metal clonk as the rack release |
| `sfx_aircraft_fired_weapon_ost_flare` | 1.00 | -14.0 | -4.5 | a vintage flare gun; the shells falling to the floor may be in the cut |
| `sfx_aircraft_fired_weapon_ost_gunbullet` | 1.09 | -12.0 | -2.9 | M61A2 burst loop at 100 rounds a second (§1.5): check for a rhythm break at the seam |
| `sfx_aircraft_fired_weapon_ost_heatmissile` | 3.00 | -13.3 | -1.1 | a ground anti-tank launch standing in for an air-launched missile |
| `sfx_button` | 0.35 | -20.0 | -2.5 | a guitar-pedal toggle; longer than the original's 30 ms click |
| `sfx_door_close` | 4.25 | -18.0 | -2.7 | cut by the loudness envelope only; check the lock thump is in it |
| `sfx_door_open` | 3.75 | -18.0 | -4.2 | the canopy motor's second run (§1.7; USC vintage optical recording, noisy) |
| `sfx_entity_fired_weapon_ost_gunbullet` | 1.25 | -14.0 | -8.8 | Phalanx burst as the AI's gun and AAA |
| `sfx_fire_extinguisher` | 1.20 | -17.2 | -1.2 | one burst of a real extinguisher |
| `sfx_flaps` | 2.50 | -14.0 | -2.2 | 3 dB quieter than the original's; a steady motor, cut at 2.5 s with a fade |
| `sfx_jfs` | 1.00 | -20.0 | -9.0 | our JFS whine (§1.4): check it does not sound like an organ |
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
| `sfx_start_engine` | 3.00 | -14.0 | -2.4 | a parked F-16's idle; check it still sounds right pitched up to 1.375 at full dry power |
| `sfx_touchdown` | 0.45 | -13.0 | -2.4 | an airplane tyre skid with a 60 Hz thump (§1.8) |
| `sfx_warning_wrn_aoa` | 1.00 | -24.0 | -20.9 | our beeps, 7 dB louder than the original's quiet tone |
| `sfx_warning_wrn_master` | 0.45 | -20.0 | -16.9 | ours; the original had no file |
| `sfx_warning_wrn_missile_launch` | 1.00 | -20.0 | -17.0 | our warble |
| `sfx_warning_wrn_new_guy` | 0.35 | -24.0 | -20.8 | our three beeps, much louder than the original's (-38 dB) |
| `sfx_weapon_exploded_ost_bomb` | 1.68 | -10.3 | -1.1 | 1.7 s, shorter than the original's 5.5 s: may need a longer rumble |
| `sfx_weapon_exploded_ost_gunbullet` | 0.45 | -12.5 | -1.1 | coins on a music stand pitched down (bullet hits) |
| `sfx_weapon_exploded_ost_rocket` | 0.85 | -14.9 | -1.0 | a firework bang for rocket, chaff and flare bursts |
| `sfx_weapon_hit_target` | 3.62 | -14.9 | -1.0 | a debris crash |

### 1.2 The afterburner against a real F-16
9 November 2026 (the Mac play test's finding 27: "is the AB start really sound like that?"). Measured with ffmpeg and
numpy / scipy, not heard: spectrograms, 50 ms level envelopes and the time to 10 % and 90 % of each step, on three
references:
- an F-16 engine run with the afterburner in a hush house[^hush]: three light-offs and four cuts at close range (the
  camera's microphone clips 14 % of the burner's samples, so its steps are a lower bound);
- an F-16's afterburner take-off at Oshkosh 2021[^osh];
- two RNLAF F-16s taking off at Leeuwarden, two CC0 recordings[^rr1][^rr2].

The engine model behind the references is open (the F-16 flies the F100 or the F110). The two videos are references
only: nothing of them ships, and their audio was deleted after the measurements. FlightGear's F-16 sounds were not
compared (open).

**When the sound changes.** The shared code swaps the engine loop when the flight model's afterburner stage changes
(docs/sound.md §3): stage 1 (minimum burner) at the AB detent, stage 2 above 87.5 % throttle. The sim's 6-DoF
engine ([flight-model.md](flight-model.md) §9.7) reports stage 1 once its power passes military and stage 2 at 75 %
power, about 0.1 s later with the throttle at maximum, so the burner sounds as soon as the core is at military. The
real engine's light-off delay after the detent is open: no reference shows the throttle.

**What differed** (before = the sim until this change, after = now; `measure.py` in the review folder, below):

| | references | before | after |
|---|---|---|---|
| light-off: the level's rise, onset to 90 % | 1.2–2.4 s (hush house) | 0.2 s | 1.3 s |
| light-off: the rise | 11–15 dB (hush house), 14 dB (Oshkosh) | 3 dB | 6 dB |
| light-off: the swell below 150 Hz over the steady burner | 1–3 dB, at 0.3–1 s | none (the loop's own 3 dB wobble) | 3.7 dB |
| cut: the level's fall, onset to 90 % | 0.8–1.0 s | at once | 0.7 s |
| cut: the fall | 12–15 dB | 2 dB | 6 dB |
| the burner's power below 150 Hz / 150–1500 Hz / above 1.5 kHz | −13 / −1 / −9 dB (hush house), −17 / 0 / −16 dB (Leeuwarden), −2 / −6 / −10 dB (Oshkosh) | −2 / −5 / −13 dB | −10.5 / −1 / −11 dB |
| the burner's spectral centroid | 700–800 Hz (Oshkosh 470 Hz) | 380 Hz | 510 Hz |
| the loop | steady | a pulse every 2.1 s (a 2.5 s cut of a fading recording played at 1.2) | steady |

- **The thump.** At light-off the hush house shows the burner rising over one to two seconds, with the band below
  150 Hz swelling 1–3 dB over its steady level, not a sharp bang (inferred: the zones fill one after the other,
  [flight-model.md](../../docs/flight-model.md) §10.2). The sim swapped loops in one frame with no swell.
- **The rumble.** The old loop (a turbojet afterburner of unnamed type, played 3 semitones up) put most of its power
  below 150 Hz: a boom. Two of the three references put it at 150–1500 Hz: a tearing roar. The Oshkosh video's power
  below 150 Hz is likely wind on its microphone (inferred).
- **The level against the dry engine.** Outside, the references jump 11–15 dB at light-off; the sim's burner was 2 dB
  over its dry loop. The level in the cockpit is open (no recording).
- **The cut's tail.** The references fall over about a second; the sim cut at once, with the old loop restarted.

**What the sim does now** (`Settings.ab_sound_real()`, true in the sim, false in the original game, whose rule and
clips are unchanged; `flight_sounds.gd`):
- the burner loop is a cut of the Leeuwarden take-off[^rr1] at its closest pass, 16.5–19.5 s, the band below 150 Hz
  down 12 dB and above 1.5 kHz up 16 dB (the recording was made far down the runway, where the air takes the highs
  and the ground adds rumble: inferred), then flattened over 0.5 s so it does not pulse; played at its own pitch for
  both stages, with no restart from stage 1 to stage 2;
- at light-off the burner rises from 12 dB under its level over 1.5 s (smoothstep) while the dry loop fades out over
  the same time, and `sfx_ab_light` plays: the burner's band below 150 Hz under a swell that peaks at 0.3 s and ends
  at 1.2 s;
- at the cut the dry loop starts at once and the burner fades out over 1.3 s (raised cosine) on a second player,
  from the level it had (a cut during the rise fades from that lower level); lit again while that tail fades, the
  burner goes on from the tail's place in the loop and rises from the tail's level;
- the burner loop is set 6 dB over the dry loop (−8 and −14 dB vrms; the dry loop 2 dB quieter than before), a step
  between the references' outside jump and no change (inferred, open for the cockpit).

Before / after renders of the same throttle moves (dry at military, the burner at 3 s, the cut at 9 s), their
spectrograms, the references beside them and the spectra are in the review folder
(`~/.claude/iaf-2026-pages/sound/`, notes.md lists the files). Checks: `test_mvp.gd` (the sim's rule), the original's
`test_sounds.gd` (its rule, no thump, no tail).

### 1.3 The core sounds against real references (Approvals item A12)
9 November 2026. The same method as §1.2: each sound the sim plays, its clip, the code that plays it and its timing,
measured against references with ffmpeg and numpy / scipy, not heard. The YouTube references are for comparison only:
nothing of them ships, and their audio was deleted after the measurements. The fixes are the sim's alone: the shared
code takes them through `Settings.core_sound_real()` (true in the sim, false in the original game, whose rule and
clips are unchanged; `test_sounds.gd` checks that). Before / after renders, their spectrograms and the reference
figures are in the review folder (`~/.claude/iaf-2026-pages/sound/core/`, notes.md lists the files).

| sound | what differed (before) | the reference | now |
|---|---|---|---|
| the dry engine (§1.3) | the idle recording played 4.2 semitones up at idle (pitch 1.275) and 1.375 at military: 8 % from idle to military, at one level | an F-16's spool tone at 2.8 kHz at idle rises past 6 kHz on the run-up[^hush]: at least 2× | its own pitch at idle, 1.3 at military; 6 dB quieter at idle |
| the start (§1.4) | from the first crank the idle loop at pitch 1.13–1.18, at full level; no JFS, no light-off | the JFS whine: partials at 2126, 3252, 4247, 5259, 6401 Hz, 20–30 dB over the broadband, rising from half that pitch over about 15 s[^start] | the JFS whine, the engine's pitch and level by its RPM, a light-off thump, the JFS winding down at the generators |
| the gun (§1.5) | 48 rounds a second (the recording's own rate) | 105 rounds a second, two F-16 firing videos[^gun1][^gun2]; the M61A1 fires 6,000 a minute | 100 rounds a second |
| the wind (§1.6) | silent (no caller) | open: the cockpit videos' sound is the intercom | the KC-135 wind loop, its amplitude as the dynamic pressure |
| the canopy (§1.7) | silent (no caller); the opening clip was the library's spoken slate | — | the closing plays at the checklist's canopy step; the opening clip is the motor |
| the touchdown (§1.8) | a bicycle brake's squeal: two tones at 1.6 and 3.3 kHz, 0.55 s | an airplane tyre skid (CC0[^skid]): broadband 0.2–4 kHz, 0.35 s | that skid with a 60 Hz thump under it, 0.45 s |
| gear and flaps | the gear clip (a flight-sim recording) runs 3.5 s against the sim's 3 s gear travel; the flaps clip is a steady motor whine, its centroid at 3.8 kHz | open: no usable recording | unchanged (open) |
| the tower's key clicks | not on main: they are on the unmerged branch `wt/iaf-2026-voices` | — | skipped |

**The dry engine.** `flight_sounds.gd` plays `sfx_start_engine.wav` (a parked F-16's idle) below the burner. The
original's rule pitches it as (RPM + 0.5) × 0.25 + 1 (FUN_004c3e00), so the sim's idle (60 % RPM) played at 1.275
and military at 1.375. Now: pitch 1 at idle, rising linearly to 1.3 at military; the level 6 dB under the row's at
idle, rising linearly in dB to the row's at military, so the burner's step over military (§1.2) stays 6 dB. The
real spool tones rise at least 2× from idle (hush house[^hush]); a broadband loop pitched that far sounds like a
cartoon, so 1.3 is a middle (inferred). The idle-to-military level step in the cockpit is open; 6 dB is inferred.

### 1.4 The start
The sim's start by keys (training.md §7.1): the JFS cranks the engine 0 → 20 % RPM in 15 s, the throttle to idle,
the light-off 5 s later, 20 → 60 % in 15 s, the main generator at 52 %. Before, the engine loop started with the
crank at pitch 1.13 and full level. Two F-16 start videos[^start][^kf16] show the JFS whine first: a set of
partials, the strongest at 2126 Hz and 3252 Hz, rising from about half their pitch over 8–15 s, then steady while the
engine spools. Now:
- **The JFS:** `sfx_jfs.wav`, computed (`sounds.py` `jfs`): those five partials (and a weak 1063 Hz) at their
  measured levels, wandering 0.3 % in speed, on 1/f noise above 300 Hz. It spools from half pitch over 10 s (between
  the references' 8 and 15 s) while the start runs, and winds down over 3 s (the reference's fall takes 3–4 s[^start])
  once the RPM reaches 52 %, the main generator on line[^f16net]: the generators coming on line are heard as the JFS
  winding down (inferred). The F-35I's IPP plays the same whine (inferred).
- **The engine:** below idle the loop's pitch is RPM / 60 % (at least 0.3) and its level falls as (RPM / 60 %)^1.5:
  14 dB under idle at 20 % (inferred).
- **The light-off:** `SFX_AB_LIGHT` (the burner's low thump, §1.2) 6 dB down as the engine lights (inferred: the
  references' level rises about 6 dB over several seconds there, with no sharp bang).

### 1.5 The gun
`player_weapons.gd` loops `SFX_AIRCRAFT_FIRED_WEAPON` / `OST_GUNBULLET` from the first round to the trigger's
release. The clip (Seidhepriest's M61A2 recording) repeats 48.4 times a second: half the M61A1's 6,000 rounds a
minute. Two F-16 firing videos[^gun1][^gun2] buzz at 105 rounds a second. `sounds.py` `gun_rate` now finds each shot
on the recording's envelope and lays it down every 220 samples (100.2 a second) under a Hann window two periods long
(pitch-synchronous overlap-add): the shot keeps its sound, only the rate changes. The loop's cross-fade starts on a
shot. Its centroid moved from 716 to 848 Hz (the references: 311–675 Hz). Open: the barrels' spin-up (about 0.4 s)
and wind-down; the AI's gun (a Phalanx at 79 a second) is unchanged.

### 1.6 The wind
`SFX_WIND` had a row and no caller. Now, from 30 kt, the sim loops it (the KC-135 recording the air brake also uses)
with its amplitude as the dynamic pressure, (KCAS / 450 kt)²: 12 dB under its row's level at 225 kt (inferred: the
pressure under a turbulent boundary layer grows with the dynamic pressure). Open: the cockpit's own wind spectrum
and level, and the air brake's loop over it.

### 1.7 The canopy
`SFX_DOOR_CLOSE` (craigsmith's USC recording of a jet's canopy closing, its 4 s motor run to the lock) now plays at
the start-up checklist's canopy step (`sim_flight.gd`). `sfx_door_open.wav` was the recording's first 4 s, the
library's spoken slate (speech formants every 0.3 s); it is now the motor's second run (21.25–25 s), still with no
caller. Open: a real F-16 canopy's run time (the references could not separate it from the ground power).

### 1.8 The touchdown
`flight_sounds.gd` plays `SFX_TOUCHDOWN` when the wheels touch with the gear down. The clip was a bicycle tyre's
squeal: two steady tones at 1.6 and 3.3 kHz for 0.55 s. Now it is craigsmith's USC airplane tyre skid[^skid]
(0.15–0.6 s): broadband 0.2–4 kHz, 0.35 s, with a 60 Hz thump falling over 0.12 s under it, the struts (inferred).

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
the radio menu's start-up request (item E3b, [training.md](training.md) §8: the menu's three requests use
`ACFT_CLEAR_TO_START`, `ACFT_TAXI_TO_RUNWAY`, `ACFT_CLEAR_TO_LINEUP` / `_NW`, `ACFT_HOLD_POS`, `ACFT_CLEAR_TO_TAKEOFF`). Example: `ACFT_TAXI_TO_RUNWAY` = `%S1 , %S2 , TAXI_RWY %D1` → "Alpha, good morning, taxi
to runway 25 right". The particles cover the callsigns Alpha–Delta, the greetings, the winds 10 / 15 / 20 kt, every
runway number 1–36 (spoken digit by digit, "two five") and the letters `RWY_L` / `RWY_R` / `RWY_C`.

## 4. Keys
`data/keys.json` holds 126 commands: the 117 of docs/controls.md §3, our own Start engine (Ctrl+E, command 200, a
hidden developer shortcut: [training.md](training.md) §7), Mission card (H, command 201: [front-end.md](front-end.md)
§8), the six start-up checklist steps (Ctrl+B, J, I, A, N, K; commands 210–215: training.md §7.1) and Master arm
(Shift+A, command 202: [weapons.md](weapons.md) §3), each with our own English and Hebrew labels, the default key as text ("Ctrl + Q"), the joystick button, the press / release commands and `shown`. `iaf-sim own` compiles it to
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


The subtitles do not wait: every tower particle has its Hebrew text (`text_he`, gender-neutral: "אישור המראה",
"הסעה למסלול", "המתנה במקום"), compiled by `iaf-sim own` into `phraseparticles_he.trx`. In Hebrew `radio.gd` prints
the phrase from those while it plays the English clips ([training.md](training.md) §8).

## 6. Credits the sim's wizard and credits roll need
The setup wizard (item A3) and the credits roll live outside this branch's folders; they need these lines (also in
[docs/credits.md](../../docs/credits.md)):
- **Sound effects** (freesound.org, CC0): ikbenraar, pillwave, 77Pacer, nuckan, qubodup, Seidhepriest,
  Jetrod, craigsmith (the USC Gold / Red / Sunset Editorial libraries), LilMati, Rudmer_Rotteveel, pushkin, xkeril,
  elliott.klein, DeqstersLab, SoundDesignForYou, tranzfusion.
- **Voices:** Piper text to speech (MIT), the voices kristin, john and norman (LibriVox recordings, public domain).
- **Hebrew voice:** only if option 1 of §5 is chosen: SASPEECH, © Kan, the Israeli Public Broadcasting Corporation,
  non-commercial licence.

## 7. Open
- A human listening pass at game volume (§1.1).
- The Hebrew voice (§5).
- The AWACS, wingman-command, waypoint and flight-report phrases (`radio.gd`'s other templates have no particles yet,
  so they are silent).
- The squelch at run time: a tower phrase is a chain of particles without squelch; the radio menu (item E3b,
  [training.md](training.md) §8) plays the phrase as it is.
- The pilot's requests (start-up, taxi, take-off) are printed only: no pilot phrase for them yet.
- The core sounds (§1.3–§1.8): the cockpit's idle-to-military step, the wind's real spectrum, the gun's spin-up, a
  real canopy's run time, the gear and flaps clips against a real F-16, the F-35I's own IPP.
- One engine sound set for all three jets (one clip per code in the shared table).
- The afterburner (§1.2): the light-off delay after the detent, the level in the cockpit, a comparison with
  FlightGear's F-16 sounds, and the F-35I's F135, which shares the F-16's burner.

## 8. Checks
- `cargo test -p iaf-tools --lib sim::`: every row's clip and every particle's clip exists and is a 22050 Hz 16-bit
  mono WAV; every code the shared code plays has a row and every file it opens by name exists; the templates `radio.gd`
  calls exist and name only particles; a stale file is removed; the key table has 120 records, labels where shown, no
  key bound twice, and only keys the reader can press.
- Godot's `AudioStreamWAV.load_from_file` loaded every clip of the compiled tables (2026-11-02).

[^fs]: Freesound, each sound's page linked in SOURCES.md; CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
[^piper]: Piper voices (rhasspy/piper-voices), each voice's MODEL_CARD names its dataset: https://huggingface.co/rhasspy/piper-voices
[^hush]: "F-16 Engine run with afterburner in hush house", YouTube (reference only): https://www.youtube.com/watch?v=IYQT__FP5_w
[^osh]: "F-16 Fighting Falcon Afterburner Takeoff at Oshkosh 2021", YouTube (reference only): https://www.youtube.com/watch?v=itiPxCPupiA
[^rr1]: Rudmer_Rotteveel, "2 Royal Dutch Airforce F-16 Fighting Falcons flyby", freesound, CC0 1.0: https://freesound.org/people/Rudmer_Rotteveel/sounds/343746/
[^rr2]: Rudmer_Rotteveel, "2 RNLAF F-16 Fighting Falcons flyby (noisy/with birds)", freesound, CC0 1.0: https://freesound.org/people/Rudmer_Rotteveel/sounds/343747/
[^start]: "F16 Engine Start Sequence", YouTube (reference only): https://www.youtube.com/watch?v=dRa-Hm9D9bg
[^kf16]: "Engine starting ROKAF KF-16C", YouTube (reference only): https://www.youtube.com/watch?v=FRoIYw2rMa0
[^f16net]: F-16.net forum, "JFS and avionics question" (the flight manual: "As the engine accelerates through 50 % rpm, a sensor causes the JFS to shut down automatically"), https://www.f-16.net/forum/viewtopic.php?p=13518
[^gun1]: "F-16 Fighting Falcon Firing 20 mm M61A1 six-barrel Gatling gun", YouTube (reference only): https://www.youtube.com/watch?v=kcBfNBZ1i-4
[^gun2]: "F-16 Firing M61A1 Vulcan cannon", YouTube (reference only): https://www.youtube.com/watch?v=armF8r9fW9k
[^skid]: craigsmith, "R02-24-Airplane Tire Skid.wav", freesound, CC0 1.0: https://freesound.org/people/craigsmith/sounds/479498/
[^saspeech]: OpenSLR, "SASPEECH" (SLR134), licence summary: https://www.openslr.org/134/
