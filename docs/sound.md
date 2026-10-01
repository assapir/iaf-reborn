# In-flight sound

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 and lists what the patch changed.

Source: `assets/ghidra_v11/iafjets.c` plus `objdump` of `v1.1/iafjets.exe`, and the original sound table
`resource/soundfiles/SoundProp.trx`. Port: `game/audio/` (`flight_sounds.gd`, `sound_table.gd`,
`sound_buses.gd`), test `tests/godot/test_sounds.gd`. Front-end sounds (buttons, palettes, music, the
Preferences previews) are in docs/front-end.md; mission voices in docs/mission-runtime.md.

Rule of the port: which sound plays when, its file, loop, volume and pitch follow the original. Allowed
improvements: Godot's resampler for pitch changes, and positional panning of the 3-D sounds (the
distance rule is DirectSound's, below).

## 1. The sound table (SoundProp.trx)

`SoundProp.trx` is byte-identical to `soundprop.txt` (tab-separated text; `soundpropertiessheet.txt`
documents the columns; `soundprop.trx.old`, `oldsoundprop.trx`, `*.gpk` Cool Edit peak files, `*.mrk`
markers and `*.bat` are leftovers). The exe reads it from `[Sound] SoundFilesPath` (default
`.\SoundFiles\`) + `SoundProp.trx`. Row parser `FUN_004c82f0` (entry = 0xa4 bytes, defaults
`FUN_004c8290`):

| column | entry | parse |
|---|---|---|
| sound code | +0 (code << 24) | `FUN_004cb6a0` (name → id, below) |
| sub code 1 / 2 | +0 (<< 12 / low 12 bits) | `FUN_004ca230` (BTY_), `FUN_004cad70` (WRN_), `FUN_004ca4e0` (DAMAGED_, WINGMAN_, BACKSEAT_), `FUN_004ca820` (systems) |
| category | +8 | `FUN_004c8580`: E = 1 engine, F = 2 effect, S / V = 3 speech |
| resident | +4 | Y = loaded once; N = loaded and played by file name when needed (`FUN_004c5450`) |
| cyclic | +0xc | `FUN_004c8630`: C = 0 loop, O = 1 one-shot, T = 2 periodic |
| 3d | +0x10 | Y = positioned at the object |
| channel | +0x14 | logical channel (0 = none; 101 = the phrase channel of the mission voices) |
| # random files | +0x18 | clamped to 5; one of the files is picked at random (`FUN_00566f30 % n`) |
| inside volume | **+0x84** | used while the listener is in the cockpit |
| outside volume | **+0x80** | used in the outside views |
| 3d min / max distance | +0x88 / +0x8c | DirectSound 3-D (defaults 50 / 500) |
| raw file name | +0x1c | `.wav` appended |

A code is `(category-id << 24) | (sub1 << 12) | sub2` (`FUN_00450a60`). Code ids (`FUN_004cb6a0`):
TAKE_OFF 5, LANDING 6, START_ENGINE 7, DRY_THRUST 8, AFTERBURNER_THRUST 9, WEAPON_EXPLODED 10,
WEAPON_HIT_TARGET 0xb, EXPLOSION 0xc, SPLASH 0xd, OBJECT_SPECIFIC 0xe, AIRCRAFT_FIRED_WEAPON 0xf,
AIRCRAFT_DAMAGED 0x10, AIRCRAFT_EXPLODED 0x11, AIRCRAFT_CRASHED 0x12, G_EFFECT 0x13, ENTITY_FIRED_WEAPON
0x14, ENTITY_DAMAGED 0x15, ENTITY_EXPLODED 0x16, ENTITY_CRASHED 0x17, WARNING 0x18, FLAPS 0x19,
WHEELS 0x1a, SPEED_BREAKES 0x1b, SPEED_BREAKES_LOOP 0x1c, RADAR_LOCK 0x1d, LANDING_GEAR 0x1e,
LANDING_HOOK 0x1f, DOOR_OPEN 0x20, DOOR_CLOSE 0x21, BUTTON 0x23, **WIND 0x24**, IR_SEEK 0x25, IR_LOCK 0x26,
FIRE_EXTINGUISHER 0x27, TOUCHDOWN 0x28, SCREECH 0x29, VOC_NARRATION 0x2a, VOC_WARNING 0x2b,
VOC_BBETTY 0x2c, VOC_AIRCRAFT_DAMAGED 0x2d, VOC_AIRCRAFT_CRASHING 0x2e, VOC_SYSTEM_DAMAGED 0x2f,
VOC_SYSTEM_DESTROYED 0x30, VOC_NICE_HIT 0x31, VOC_BAD_MISS 0x32, VOC_*_SAY_FRIENDLY_HIT 0x33–0x35,
VOC_BACKSEAT 0x36, VOC_WINGMAN 0x37; SND_WARNING 1 … SND_ENTITY_CRASHED 4 (no rows).
Sub codes: BTY_ALT 1, MISS 2, FUEL 3, FIRE 4, ENGINE 5, CAUTION 6, SPIN 7, BINGO 8, OVER_G 9, PULL_UP 10;
WRN_MASTER 1 … WRN_AOA 0x11, WRN_MASTER_CAUTION 0x12 (table order); DAMAGED_ELECTRICITY 1,
MISSILE_HIT 2, GUN_BULLETS 3, INSIDE 4; WINGMAN_NEGATIVE 0 … WINGMAN_EJECT_EJECT 7.

Many rows name files that were never shipped (AircraftCrash, WrnMaster, all WrnSfx* but NewGuy /
Missile / AOA, all WrnVoc*, Sys*, most backseat voices, Wheels, LandHook, DoorOpenFx / DoorCloseFx,
RadarLock, MislSeekTon, VocAircraftCrash, …): those sounds are silent in the original and here.
Shipped files that no row and no code uses: `cock_eng_gnrlsnd`, `cock_eng_idle_air`,
`cock_eng_idle_gnd_f100/_j79`, `afterburner1/2`, `internal plane 1`, `gearup`, `geardown`, `speedbreak`,
`speedbreakloop`, `parachute open`, `mfd click`, `wind1–5` (radio "wind is …" phrases), and more.
There is **no SFX_WIND row** and no caller of code 0x24: the original has no airflow / wind noise.

## 2. Sound manager (`DAT_0069931c`, ctor `FUN_004c4410`)

* **Play by code** `FUN_004c4ea0(&code, obj)` (`FUN_004c4e80(id)` = sub codes 0): look up the row
  (`FUN_004c7b90` / `FUN_004c5cb0`); non-resident rows go to `FUN_004c5450` → `FUN_004c5470(file, 0,
  channel == 101)`. Resident: volume = (inside flag `manager+0x34` ? inside : outside volume) ×
  category volume `manager+0x40+cat·4`; pitch = the object sound's pitch (+0xc, flag 0x40000000) or 1.0;
  loop for cyclic rows; 3-D rows get the object position and the min / max distance; a row with a
  channel goes through the manager's channel table (`manager+0x18`, then `FUN_005447a0`), otherwise
  `FUN_00544560`.
* **Play a wav by name** `FUN_004c5470(file, 0, phrase)`: volume = the **speech** volume
  (`manager+0x4c`), pitch 1, not 3-D; `phrase` ≠ 0 plays on the phrase channel (`FUN_005448b0`,
  handle `manager+0x38`). Used by the mission voices (`FUN_004bb10b`), the map-edge wavs
  (EndWorld / Kramer18 / Kram1, `FUN_005bb9f0`; v1.1 no longer plays Kramer18 / Kram1 there and prints a console
  line instead, docs/flight-model.md) and every non-resident row. Quirk kept: non-resident
  effects (`td`, `screech`, …) therefore follow the speech slider, not the effects slider.
* **Category volumes** `FUN_004c5900(cat, v)`: 1 engine (`d34`, default 0.8), 2 effects (`d38`, 1.0),
  3 speech (`d3c`, 1.0; also sets the phrase channel volume), from the Preferences Sound page
  (`FUN_004fe430`, `FUN_004e2960`). **Mute** `FUN_004c5930(on)` (0x545040 / 0x545090: all sounds).
  The in-flight "Mute sound toggle" (command 135, Ctrl+M, 0x4e3442) flips `DAT_0083b8b8` and calls it.
* **Stop** `FUN_004c5420(handle)`.
* **Pause / resume all** (game events 0x75 / 0x76: Ctrl+P pause and the On-The-Fly menu):
  `FUN_004c58e0` → 0x544f50 stops every channel, `FUN_004c58f0` → 0x544f90 resumes them where they
  stopped (docs/front-end.md §16; terrain_view.gd `_freeze`, docs/views.md §1).
* **Object sounds** (`FUN_004c3ac0` / `FUN_004c3f90` / `FUN_004c3c10`): up to 4 slots per object;
  slot 0 is the engine (§3). A code change stops the old sound and starts the new one
  (`FUN_004c42a0` + `FUN_004c4ea0`); otherwise the position and pitch are updated (`FUN_004c5220`).
  `FUN_004c4310` stops all slots (unit destroyed).
* **`[Sound]` values** read once by `FUN_004c3ac0` (`FUN_004d3b50`, defaults; the install sets none):
  PitchIntrPercent 0.25, InsideReduceVolume 0.75 (**read but never used**), PitchIntrShift 0.5,
  Ab1PitchPerc 0.8, Ab2PitchPerc 1.2.
* **Player-only gate** `FUN_0044fb10(code)`: the controller is the player's (ctl+4 ∈ {2,4,5}, same unit
  as `DAT_00699320`, unit state 3 in `[unit+0x1c]+0x14`) — all cockpit sounds below go through it.
* UNCERTAIN: the setter of the inside flag `manager+0x34` was not found (taken as "listener in the
  cockpit", from the column names); the logical-channel policy (a new sound on a busy channel waits
  here — queue vs replace not traced).

**Port** (`sound_buses.gd`): three buses IafEngine / IafSfx / IafSpeech at the Preferences volumes,
all muted by Mute; `toggle_mute()` for the Ctrl+M command. `sound_table.gd` reads SoundProp.trx at
run time (no copy of the data in our code).

## 3. Engine (object sound slot 0, `FUN_004c3e00` via `FUN_004c3c10`)

For every object of class 0x1e (all controlled aircraft — **the same engine sounds for every jet**;
the per-type engine rows SFX_OBJECT_SPECIFIC / OBJ_* are for other objects). Updated on the throttle
events (GEV 4–6, `FUN_0044a240`) and in the per-frame object sound update (`FUN_004c42d0`).
`stage` = the flight model's afterburner stage (engine object +0x28, set by `FUN_0045abf0` from the
aero update `FUN_005a70f0`), `rpm` = getter 0x11 · 0.01 (RPM ramp `S+0x1b0`, 0..1):

```
code = current code;  last = param_1[10] (0 at creation)
stage < 1:  if rpm != last: code = SFX_LANDING
                            if rpm > 0: pitch = (rpm + PitchIntrShift)·PitchIntrPercent + 1 ; code = SFX_START_ENGINE
                            last = rpm
            if rpm <= 0: code = SFX_LANDING
stage == 1: code = SFX_DRY_THRUST;          if last != Ab1PitchPerc: pitch = 0.8, last = 0.8
stage == 2: code = SFX_AFTERBURNER_THRUST;  if last != Ab2PitchPerc: pitch = 1.2, last = 1.2
```

| code | file | loop | 3-D (min/max m) | volume in / out | pitch |
|---|---|---|---|---|---|
| SFX_LANDING (engine off) | `Landing.wav` (86 samples of near silence) | yes | 50 / 250 | 0.75 / 1 | 1 |
| SFX_START_ENGINE (dry, RPM > 0) | `StartEngine.wav` (1.75 s) | yes | 50 / 250 | 0.75 / 1 | 1.125 (RPM → 0) … 1.375 (100 %) |
| SFX_DRY_THRUST (**AB stage 1**) | `Cock_Eng_Brnr.wav` (1.81 s) | yes | 50 / 250 | 0.75 / 1 | 0.8 |
| SFX_AFTERBURNER_THRUST (AB stage 2) | `Cock_Eng_Brnr.wav` | yes | 50 / 250 | 0.75 / 1 | 1.2 |

Pitch = a playback-rate factor (the DirectSound wrapper's default is 1.0). So a ground start (engine off,
RPM 0) is silent; "1" starts the engine, the RPM ramp (15 %/s) raises the pitch from 1.125; the
afterburner replaces the dry loop by the burner loop after the light-up delay. There is no separate
start-up or shut-down sample (SFX_TAKE_OFF 5 has a row but no caller). Engine category → engine
volume slider (default 0.8).

## 4. Player cockpit sounds (controller `FUN_00448b20` per frame, `FUN_0044a240` events)

| sound (code / sub) | file | trigger (address) | loop | vol in/out | bus | port |
|---|---|---|---|---|---|---|
| SFX_LANDING_GEAR 0x1e | `Gear.wav` 1.9 s | gear lever accepted, both ways (GEV 0xe, @44d26e; docs/flight-model.md §12) | no | 0.75 | effects | yes |
| SFX_FLAPS 0x19 | `Flaps.wav` 1.3 s | flaps lever accepted while the flaps are not moving (GEV 0xc, ind[3] 2→retract / 0→extend, @44cc36) | no | 0.75 | effects | yes |
| SFX_SPEED_BREAKES 0x1b | `Cock_Arbrks_Opn.wav` | every air-brake toggle (GEV 0x11, @44c97b) | no | 1 | effects | yes |
| SFX_SPEED_BREAKES_LOOP 0x1c | `Cock_Arbrks_Loop.wav` | toggle: brake out and airborne → start (handle ctl+0x8cc); else stop. Per frame (@4495d2): brake out: airborne → start if none; on the ground → stop | yes | 1 | effects | yes |
| SFX_WARNING / WRN_AOA 0x18011000 | `WrnSfxAOA.wav` | per frame (@449247): dragX (getter 0x12 = `S+0x2f0`) > 0.5 and airborne → start (ctl+0x8c4); else stop | yes | 1 | effects | yes (state `drag_x`) |
| VOC_BBETTY / BTY_ALT 0x2c001000 | `Cock_Bty_Alt.wav` "Altitude" | `FUN_0044fe30`: `(z − terrain(x,y))·3.281 < 100` ft and the gear handle up and ctl+0x964 → MCockpitSoundEvent (vtbl 0x600ce8) at once and every 4.0 s (`DAT_0082f468`, ctl+0x904); cancelled when the condition ends | no | 1 | speech, ch 3 | yes |
| VOC_BBETTY / BTY_PULL_UP 0x2c00a000 | `Cock_Bty_Alt.wav` (the row reuses "Altitude") | same function, above 100 ft or gear down: pitch-angle·57.3 < 0 and its magnitude > h_ft·0.01, HUD mode ctl+0x5c ∈ {4,5,6} (air-to-ground weapon modes) and ctl+0x964 → every 4 s (ctl+0x908); also sets the HUD pull-up cue (`FUN_00445980`) | no | 1 | speech | needs A-G HUD modes |
| VOC_BBETTY / BTY_OVER_G 0x2c009000 | `Cock_Bty_Over.wav` | G > OverGThresh, 4 s repeat (@44951e; docs/flight-model.md §13.5) | no | 1 | speech | yes (g_effects.gd) |
| SFX_G_EFFECT 0x13 | `Cock_G_02.wav` | G > 6, 17 s repeat (@449574) | no | 1 | effects | yes (g_effects.gd) |
| VOC_BBETTY / BTY_FUEL 0x2c003000 | `Cock_Bty_Fuel.wav` | engine object `FUN_0045aa80` (every fuel update, fuel in lb = kg·2.2046): once when 500 < fuel < 1000 (flag +0x40), once when fuel < 500 (flag +0x44); not gated by ctl+0x964 | no | 1 | speech | yes |
| SFX_TOUCHDOWN 0x28 | `TD.wav` 0.5 s | `FUN_005bb9f0` @5bbd1e: touchdown, landing check passed, gear ramp fully down (\|gear\| < 1e-5), player | no | (non-resident) | speech (quirk §2) | yes |
| SFX_SCREECH 0x29 | `screech.wav` 8.9 s | same, gear **not** fully down (belly), on a runway (terrain flag & 0x30) | no | (non-resident) | speech | needs terrain types (never here) |
| SFX_AIRCRAFT_EXPLODED 0x11 | `AerialExp.wav` 2.7 s | destroyed (unit state 5, `FUN_004a8420` → `FUN_004a86b0`): explosion effect `FUN_0059df20` of an aircraft (classes 1/2/3/0x1c → code 0x11), 3-D, min 500 / max 1000 m; then `FUN_004c4310` stops the object's sounds (engine) | no | 1 | effects | yes |
| VOC_WINGMAN / WINGMAN_EJECT_EJECT 0x37007000 | `eject.wav` "Eject! Eject!" | unit state 1 → 3 (ejected), player (`FUN_004a8ae0` → `FUN_004a8100`) | no | (non-resident, ch 101) | speech, phrase channel | `FlightSounds.play_eject()` for the ejection code |
| SFX_BUTTON 0x23 | `FX_BTT.wav` | HUD / master-mode changes (`FUN_00449810` callers @44ad9b, @44b9fb) and other controller events (@44d269) | no | 1 | effects | needs weapon / HUD modes |
| SFX_FIRE_EXTINGUISHER 0x27 | `Cock_Extinguisher.wav` | engine object `FUN_0045ae10` (fire out, flag +0x3c) | no | — | speech | needs damage / fire |

Per-type flag **ctl+0x964** ("has Betty"), set in `FUN_00447e70` by type code (switch @447e95):
F-16 100, F-15 110, Lavi 140, MiG-29 180, F-4 200 → 1; F-4 120, Kfir 130, MiG-21 150, MiG-23 160,
MiG-25 170, Mirage 190, 210, 220, 225 → 0. It gates BTY_ALT / BTY_PULL_UP and the damage Betty calls,
not Over-G or Fuel. Port: `FlightSounds.BETTY_TYPES`.

Mission instructor voices (`FUN_004bb10b` → `FUN_004c5470(wav, 0, 1)`): phrase channel, speech volume
(port: terrain_view `_voice` on the IafSpeech bus).

## 5. Sounds that need other systems

| sound | code | trigger in the exe | needs |
|---|---|---|---|
| Betty "Warning" / master caution | VOC_BBETTY BTY_CAUTION 0x2c006000 + SFX_WARNING WRN_MASTER 0x18001000 (file missing) | end of the damage handler `FUN_0044d760` (@44de24) | damage |
| Betty "Fire" | BTY_FIRE 0x2c004000 | damage handler, engine fire (@44db29, @44db9d; ctl+0x964) | damage |
| Betty "Engine" | BTY_ENGINE 0x2c005000 | damage handler (@44ddf2) | damage |
| damage thumps | SFX_AIRCRAFT_DAMAGED 0x10001000–0x10003000 (`Cock_Dmgd_01/03/05`) | hit handler `FUN_0044d590` (@44d6b2, @44d6d9) and damage handler `FUN_0044d760` (@44da25, @44dac0) | damage / weapons |
| RWR new emitter | SFX_WARNING WRN_NEW_GUY 0x18002000 (`WrnSfxNewGuy`, channel 5) | `FUN_0044deb0`, `FUN_00450bc0` | ported (`rwr.gd`, docs/rwr.md §3); waits for something that locks the player |
| missile launch | SFX_WARNING WRN_MISSILE_LAUNCH 0x18003000 (`WrnSfxMissile`, loop) + Betty BTY_MISS 0x2c002000 | `FUN_0044e160` (@44e197, @44e1b6), `FUN_00448120` (@4482f9) | ported (`rwr.gd` `launch`); waits for enemy missiles |
| IR seeker / lock | SFX_IR_SEEK 0x25 / SFX_IR_LOCK 0x26 (`Wpn_IRCHIRP`, `WPN_IRCHIRPON`) | `FUN_00461b00`, `FUN_00461bf0` | weapons |
| gun, weapon release / flight / hits | SFX_AIRCRAFT_FIRED_WEAPON 0xf, SFX_OBJECT_SPECIFIC 0xe, WEAPON_EXPLODED 10, … | `FUN_004579f0`, `FUN_0059d9c0`, `FUN_0059dad0`, `FUN_004d5d10` | weapons |
| Betty "Pull up" | BTY_PULL_UP | §4 | A-G HUD modes |
| button click | SFX_BUTTON 0x23 | §4 | HUD / weapon modes |
| extinguisher | SFX_FIRE_EXTINGUISHER 0x27 | §4 | fire |
| belly screech | SFX_SCREECH 0x29 | §4 | terrain types (runway flag) |
| other aircraft / vehicles | SFX_OBJECT_SPECIFIC (`StartEngine`, `VprRcket` helicopters, …) | object creation `FUN_004d5d10` / `FUN_004c3f90` | AI / moving units |

Defined in the table but never played (no caller found): SFX_TAKE_OFF, SFX_WHEELS, SFX_LANDING_HOOK,
SFX_DOOR_OPEN / CLOSE (canopy: no canopy sound), SFX_RADAR_LOCK, SFX_MISSILE_SEEKER_TONE, SFX_WIND,
SFX_AIRCRAFT_CRASHED (file missing anyway), the stall Betty BTY_SPIN, BTY_BINGO (the engine object keeps a
bingo value at +0x20 but no comparison was found), all BACKSEAT voices (docs/flight-model.md §12, §13.5).
The stall buffet and touchdown / off-runway rumble are DirectInput force-feedback effects, not sounds.

## 6. Port notes and UNCERTAIN points

* Host: `game/terrain/terrain_view.gd` adds `FlightSounds` (type code 100) and it polls the host every
  frame (flight state, lever variables, view, terrain height). Lever sounds fire on the host's accepted
  lever changes (the host applies the original's lever rules).
* 3-D sounds: `AudioStreamPlayer3D` at the jet, gain = min / clamp(distance to the camera, min, max)
  (DirectSound rolloff 1), Godot panning, no Doppler. In the cockpit the listener sits at the jet.
* The inside / outside volume follows the current view every frame (the original picks it when a sound
  starts; UNCERTAIN whether it updates running sounds).
* UNCERTAIN: the `BTY_PULL_UP` angle (unit state slot 0x34 +0x0c, taken as the pitch); the
  logical-channel policy; the inside flag's setter; that the per-frame object sound update runs every frame.
* Original quirk kept (tell the user): non-resident effects (touchdown, screech, extinguisher) play at
  the speech volume.
* v1.1: the sound code audited here (engine and flight sounds `FUN_0044fe30`, `FUN_00447e70` with the byte table
  `0x448094`, the mute toggle) is unchanged. The only data change is the tower phrase key `CHARLY_T` → `CHARLIE_T` in
  `phraseparticalsdata.trx`: the key is built from the callsign, so with v1.0 data the tower cannot say "Charlie"
  (v1.0 behaviour, kept). The radio phrases are not ported yet.
