# In-flight sound

This doc specifies which sound plays in flight, when, and how loud: the sound table, the sound manager, the engine
loop and the cockpit sounds. Addresses are `IAFJets.exe` **v1.1**; [v1.1.md](v1.1.md) maps them to v1.0.

* **Sources**: `assets/ghidra_v11/iafjets.c` plus `objdump` of `v1.1/iafjets.exe`, and the original sound table
  `resource/soundfiles/SoundProp.trx`.
* **Port**: `game/audio/` (`flight_sounds.gd`, `sound_table.gd`, `sound_buses.gd`); test
  `tests/godot/test_sounds.gd`.
* **Elsewhere**: front-end sounds (buttons, palettes, music, the Preferences previews): docs/front-end.md; mission
  voices: docs/mission-runtime.md §3.3; radio phrases: docs/radio.md.

**Rule of the port**: which sound plays when, its file, loop, volume and pitch follow the original. Two improvements:
Godot's resampler for pitch changes, and positional panning of the 3-D sounds. The distance rule is DirectSound's
(the Windows audio API the original uses, §6).

## 1. The sound table (SoundProp.trx)

`SoundProp.trx` is the table of every sound: one row per sound, tab-separated text.

* It is byte-identical to `soundprop.txt`. `soundpropertiessheet.txt` documents the columns.
* Leftover files in the folder: `soundprop.trx.old`, `oldsoundprop.trx`, `*.gpk` Cool Edit peak files, `*.mrk`
  markers and `*.bat`.
* The exe reads it from `[Sound] SoundFilesPath` (default `.\SoundFiles\`) + `SoundProp.trx`.
* Row parser: `FUN_004c82f0` (entry = 0xa4 bytes, defaults `FUN_004c8290`).

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

**Rows whose file was never shipped** are silent, in the original and here: AircraftCrash, WrnMaster, every WrnSfx*
except NewGuy / Missile / AOA, all WrnVoc*, Sys*, most backseat voices, Wheels, LandHook, DoorOpenFx /
DoorCloseFx, RadarLock, MislSeekTon, VocAircraftCrash, ….

**Shipped files that no row and no code uses**: `cock_eng_gnrlsnd`, `cock_eng_idle_air`,
`cock_eng_idle_gnd_f100/_j79`, `afterburner1/2`, `internal plane 1`, `gearup`, `geardown`, `speedbreak`,
`speedbreakloop`, `parachute open`, `mfd click`, and more. (`wind1–5` are the "Wind Water Fire" mission's
radio messages, `default6_1.bdb` messages Wind1–Wind5, such as "This is Navy 1. Two enemy helicopters are approaching
us from the east."; they play as mission messages, docs/mission-runtime.md §3.3.)

**Wind**: the table has **no SFX_WIND row**, and no code calls code 0x24: the original plays no airflow noise.

## 2. Sound manager (`DAT_0069931c`, ctor `FUN_004c4410`)

The sound manager (`DAT_0069931c`) plays, mixes and stops every in-flight sound.

* **Play by code** `FUN_004c4ea0(&code, obj)` (`FUN_004c4e80(id)` = sub codes 0):
  1. It looks up the row (`FUN_004c7b90` / `FUN_004c5cb0`).
  2. A non-resident row goes to `FUN_004c5450` → `FUN_004c5470(file, 0, channel == 101)`.
  3. A resident row plays with:
     - volume = (inside flag `manager+0x34` ? inside : outside volume) × category volume `manager+0x40+cat·4`;
     - pitch = the object sound's pitch (+0xc, flag 0x40000000) or 1.0;
     - a loop for cyclic rows;
     - for 3-D rows, the object position and the min / max distance.
  4. A row with a channel goes through the manager's channel table (`manager+0x18`, then `FUN_005447a0`);
     any other row through `FUN_00544560`.
* **Play a wav by name** `FUN_004c5470(file, 0, phrase)`: volume = the **speech** volume (`manager+0x4c`), pitch 1,
  2-D. With `phrase` ≠ 0 it plays on the phrase channel (`FUN_005448b0`, handle `manager+0x38`). Users:
  - the mission voices (`FUN_004bb10b` → `FUN_004c5470(wav, 0, 1)`; port: terrain_view `_voice` on the IafSpeech
    bus);
  - the map-edge wavs (EndWorld / Kramer18 / Kram1, `FUN_005bb9f0`). v1.1 plays EndWorld.wav and prints a console
    line in place of Kramer18 / Kram1; the port plays EndWorld.wav (`terrain_view.gd`, docs/flight-model.md §15.5a);
  - every non-resident row, so non-resident effects (`td`, `screech`, …) follow the speech slider (quirk kept).
* **Category volumes** `FUN_004c5900(cat, v)`, set from the Preferences Sound page (`FUN_004fe430`,
  `FUN_004e2960`):
  - 1 engine (`d34`, default 0.8);
  - 2 effects (`d38`, 1.0);
  - 3 speech (`d3c`, 1.0; also sets the phrase channel volume).
* **Mute** `FUN_004c5930(on)` (0x545040 / 0x545090: all sounds). The in-flight "Mute sound toggle" (command 135,
  Ctrl+M, 0x4e3442) flips `DAT_0083b8b8` and calls it.
* **Stop** `FUN_004c5420(handle)`.
* **Pause / resume all** (game events 0x75 / 0x76: Ctrl+P pause and the On-The-Fly menu):
  `FUN_004c58e0` → 0x544f50 stops every channel, `FUN_004c58f0` → 0x544f90 resumes them where they
  stopped (docs/front-end.md §16; terrain_view.gd `_freeze`, docs/views.md §1).
* **Object sounds** (`FUN_004c3ac0` / `FUN_004c3f90` / `FUN_004c3c10`): each object has up to 4 slots; slot 0 is
  the engine (§3). A code change stops the old sound and starts the new one (`FUN_004c42a0` + `FUN_004c4ea0`).
  With the same code, only the position and pitch update (`FUN_004c5220`). `FUN_004c4310` stops all slots (unit
  destroyed).
* **`[Sound]` values** read once by `FUN_004c3ac0` (`FUN_004d3b50`, defaults; the install sets none):
  PitchIntrPercent 0.25, InsideReduceVolume 0.75 (**read but never used**), PitchIntrShift 0.5,
  Ab1PitchPerc 0.8, Ab2PitchPerc 1.2.
* **Player-only gate** `FUN_0044fb10(code)`: passes when the controller is the player's (ctl+4 ∈ {2,4,5}, same
  unit as `DAT_00699320`, unit state 3 in `[unit+0x1c]+0x14`). All cockpit sounds below go through it.

**Port** (`sound_buses.gd`): three buses, IafEngine / IafSfx / IafSpeech, at the Preferences volumes. Mute mutes all
three; `toggle_mute()` serves the Ctrl+M command. `sound_table.gd` reads SoundProp.trx at run time, so our code holds
no copy of the data.

## 3. Engine (object sound slot 0, `FUN_004c3e00` via `FUN_004c3c10`)

The engine sound is object sound slot 0. Every jet uses the same engine sounds.

* **Start**: every unit with a sound object starts it at its reset (`FUN_004a8060` → `FUN_004c3f90` with code 0).
  The spawners `FUN_0059b060` / `FUN_0059bb00` / `FUN_0059c740` create the sound object.
* **Who gets a code**: only an entity with a flight model (`+0x34`) and render kind 0x1e. That is every object of
  class 0x1e: all controlled aircraft, the player's and the AI's. Vehicles keep code 0, which has no row, so they
  are silent. The per-type engine rows SFX_OBJECT_SPECIFIC / OBJ_* are for other objects.
* **Updates**: on the throttle events (GEV 4–6, `FUN_0044a240`) and in the per-frame object sound update
  (`FUN_004c42d0`).
* **Inputs**: `stage` = the flight model's afterburner stage (engine object +0x28, set by `FUN_0045abf0` from the
  aero update `FUN_005a70f0`); `rpm` = getter 0x11 · 0.01 (RPM ramp `S+0x1b0`, 0..1).

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

Pitch is a playback-rate factor (the DirectSound wrapper's default is 1.0). What the player hears:

1. On a ground start (engine off, RPM 0) the engine is silent.
2. Key "1" starts the engine. The RPM ramp (15 %/s) raises the pitch from 1.125.
3. The afterburner swaps the dry loop for the burner loop after the light-up delay.

Start-up and shut-down have no sample of their own. The engine category follows the engine volume slider (default
0.8).

## 4. Player cockpit sounds (controller `FUN_00448b20` per frame, `FUN_0044a240` events)

The real jets' voice warnings (research for a "Real Betty" option): [real-betty.md](real-betty.md).

| sound (code / sub) | file | trigger (address) | loop | vol in/out | bus | port |
|---|---|---|---|---|---|---|
| SFX_LANDING_GEAR 0x1e | `Gear.wav` 1.9 s | gear lever accepted, both ways (GEV 0xe, @44d26e; docs/flight-model.md §12) | no | 0.75 | effects | yes |
| SFX_FLAPS 0x19 | `Flaps.wav` 1.3 s | flaps lever accepted while the flaps are not moving (GEV 0xc, ind[3] 2→retract / 0→extend, @44cc36) | no | 0.75 | effects | yes |
| SFX_SPEED_BREAKES 0x1b | `Cock_Arbrks_Opn.wav` | every air-brake toggle (GEV 0x11, @44c97b) | no | 1 | effects | yes |
| SFX_SPEED_BREAKES_LOOP 0x1c | `Cock_Arbrks_Loop.wav` | toggle: brake out and airborne → start (handle ctl+0x8cc); else stop. Per frame (@4495d2): brake out: airborne → start if none; on the ground → stop | yes | 1 | effects | yes |
| SFX_WARNING / WRN_AOA 0x18011000 | `WrnSfxAOA.wav` | per frame (@449247): dragX (getter 0x12 = `S+0x2f0`) > 0.5 and airborne → start (ctl+0x8c4); else stop | yes | 1 | effects | yes (state `drag_x`) |
| VOC_BBETTY / BTY_ALT 0x2c001000 | `Cock_Bty_Alt.wav` "Altitude" | `FUN_0044fe30`: `(z − terrain(x,y))·3.281 < 100` ft and the gear handle up and ctl+0x964 → MCockpitSoundEvent (vtbl 0x600ce8) at once and every 4.0 s (`DAT_0082f468`, ctl+0x904); cancelled when the condition ends | no | 1 | speech, ch 3 | yes (ours: on the MiG-29 with Better cockpit `radar_alt`, below its radar altimeter's 70 m danger height instead of 100 ft, also with the Real HUD; docs/cockpit.md "MiG gauges") |
| VOC_BBETTY / BTY_PULL_UP 0x2c00a000 | `Cock_Bty_Pull.wav` "Pull up" | same function, outside the BTY_ALT case: the pitch (state [3] = pitch, ×57.3) < 0 and \|pitch°\| > h_ft·0.01 (0x600ae0 = 0, 0x600b2c = 0.01) in HUD mode ctl+0x5c ∈ {4, 5, 6} (A-G gun, bombs) → at once and every 4 s (ctl+0x908). The timer starts only with the gear handle up and ctl+0x964 and runs until the dive or the mode ends. The function returns 1 in that dive, with the gear up or down: `FUN_00445990` → S+0x1024, the HUD break X (docs/cockpit.md) | no | 1 | speech, ch 3 | yes (`FlightSounds.pull_up`; the X in `hud.gd`). With the Real HUD BTY_ALT / BTY_PULL_UP follow the real jet instead (`FlightSounds.REAL_VOICE`, docs/real-hud.md "Pull-up and break marks") |
| VOC_BBETTY / BTY_OVER_G 0x2c009000 | `Cock_Bty_Over.wav` | G > OverGThresh, 4 s repeat (@44951e; docs/flight-model.md §13.5) | no | 1 | speech | yes (g_effects.gd) |
| SFX_G_EFFECT 0x13 | `Cock_G_02.wav` | G > 6, 17 s repeat (@449574) | no | 1 | effects | yes (g_effects.gd) |
| VOC_BBETTY / BTY_FUEL 0x2c003000 | `Cock_Bty_Fuel.wav` | engine object `FUN_0045aa80` (every fuel update, fuel in lb = kg·2.2046): once when 500 < fuel < 1000 (flag +0x40), once when fuel < 500 (flag +0x44); not gated by ctl+0x964 | no | 1 | speech | yes |
| SFX_TOUCHDOWN 0x28 | `TD.wav` 0.5 s | `FUN_005bb9f0` @5bbd1e: touchdown, landing check passed, gear ramp fully down (\|gear\| < 1e-5), player | no | (non-resident) | speech (quirk §2) | yes |
| SFX_SCREECH 0x29 | `screech.wav` 8.9 s | same, gear **not** fully down (belly), on a runway (terrain flag & 0x30) | no | (non-resident) | speech | yes (`FlightSounds.on_runway` from `terrain.gd surface_at`) |
| SFX_AIRCRAFT_EXPLODED 0x11 | `AerialExp.wav` 2.7 s | destroyed (unit state 5, `FUN_004a8420` → `FUN_004a86b0`): explosion effect `FUN_0059df20` of an aircraft (classes 1/2/3/0x1c → code 0x11), 3-D, min 500 / max 1000 m; then `FUN_004c4310` stops the object's sounds (engine) | no | 1 | effects | yes |
| VOC_WINGMAN / WINGMAN_EJECT_EJECT 0x37007000 | `eject.wav` "Eject! Eject!" | unit state 1 → 3 (ejected), player (`FUN_004a8ae0` → `FUN_004a8100`) | no | (non-resident, ch 101) | speech, phrase channel | `FlightSounds.play_eject()` for the ejection code |
| SFX_BUTTON 0x23 | `FX_BTT.wav` | HUD / master-mode changes (`FUN_00449810` callers @44ad9b, @44b9fb) and other controller events (@44d269) | no | 1 | effects | yes (`player_weapons.gd`, master / HUD mode changes; `terrain_view.gd`, the T / D / I / U MFD pages) |
| SFX_FIRE_EXTINGUISHER 0x27 | `Cock_Extinguisher.wav` | engine object `FUN_0045ae10` (fire out, flag +0x3c) | no | — | speech | yes (`player_damage.gd` `extinguish`) |

"Betty" is the female cockpit voice warning. The per-type flag **ctl+0x964** ("has Betty") is set in
`FUN_00447e70` by type code (switch @447e95):

* 1: F-16 100, F-15 110, Lavi 140, MiG-29 180, F-4 200.
* 0: F-4 120, Kfir 130, MiG-21 150, MiG-23 160, MiG-25 170, Mirage 190, 210, 220, 225.

It gates BTY_ALT / BTY_PULL_UP and the damage Betty calls. Over-G and Fuel play on every type. Port:
`FlightSounds.BETTY_TYPES`.

## 5. Sounds tied to other systems

| sound | code | trigger in the exe | status |
|---|---|---|---|
| Betty "Warning" / master caution | VOC_BBETTY BTY_CAUTION 0x2c006000 + SFX_WARNING WRN_MASTER 0x18001000 (file missing) | end of the damage handler `FUN_0044d760` (@44de24) | ported (`player_damage.gd`) |
| Betty "Fire" | BTY_FIRE 0x2c004000 | damage handler, engine fire (@44db29, @44db9d; ctl+0x964) | ported (`player_damage.gd`) |
| Betty "Engine" | BTY_ENGINE 0x2c005000 | damage handler (@44ddf2) | ported (`player_damage.gd`) |
| damage thumps | SFX_AIRCRAFT_DAMAGED 0x10001000–0x10003000 (`Cock_Dmgd_01/03/05`) | hit handler `FUN_0044d590` (@44d6b2, @44d6d9) and damage handler `FUN_0044d760` (@44da25, @44dac0) | ported (`player_damage.gd`) |
| RWR new emitter | SFX_WARNING WRN_NEW_GUY 0x18002000 (`WrnSfxNewGuy`, channel 5) | `FUN_0044deb0`, `FUN_00450bc0` | ported (`rwr.gd`, docs/rwr.md §3; the AI's locks, `ai/combat.gd` `_pick`) |
| missile launch | SFX_WARNING WRN_MISSILE_LAUNCH 0x18003000 (`WrnSfxMissile`, loop) + Betty BTY_MISS 0x2c002000 | `FUN_0044e160` (@44e197, @44e1b6), `FUN_00448120` (@4482f9) | ported (`rwr.gd` `launch`, from `player_weapons.gd` `launch_homing`: the AI's and SAMs' missiles) |
| IR seeker / lock | SFX_IR_SEEK 0x25 / SFX_IR_LOCK 0x26 (`Wpn_IRCHIRP`, `WPN_IRCHIRPON`) | `FUN_00461b00`, `FUN_00461bf0` | ported (`player_weapons.gd`) |
| gun, weapon release / flight / hits | SFX_AIRCRAFT_FIRED_WEAPON 0xf, SFX_OBJECT_SPECIFIC 0xe, WEAPON_EXPLODED 10, … | `FUN_004579f0`, `FUN_0059d9c0`, `FUN_0059dad0`, `FUN_004d5d10` | ported (`player_weapons.gd`, AI launches through its `launch_homing`; the AI's gun bursts / AAA in `ai/combat.gd`) |
| AI jets' engines | slot 0 (§3), the player's rows | unit reset `FUN_004a8060` → `FUN_004c3f90(code 0)`; the engine rule for an entity with a flight model (`+0x34`) | ported (`flight_sounds.gd` `create_engine`, one per AI jet in `ai_flights.gd`) |
| vehicles, helicopters (OBJ_* rows) | SFX_OBJECT_SPECIFIC OBJ_VEHICLE / OBJ_ARMEDVEHICLE / OBJ_HELICOPTER … | none: the rows are parsed (`FUN_004cc540`) but no code builds them; a vehicle's slot 0 keeps code 0 (no row) | silent, as in the original |

**Defined in the table but never played** (no caller found):
* SFX_TAKE_OFF, SFX_WHEELS, SFX_LANDING_HOOK;
* SFX_DOOR_OPEN / CLOSE (the canopy is silent);
* SFX_RADAR_LOCK, SFX_MISSILE_SEEKER_TONE, SFX_WIND;
* SFX_AIRCRAFT_CRASHED (file missing anyway);
* the stall Betty BTY_SPIN;
* BTY_BINGO: the engine object keeps a bingo value at +0x20, but no comparison was found;
* all BACKSEAT voices (docs/flight-model.md §12, §13.5).

The stall buffet and touchdown / off-runway rumble are DirectInput force-feedback effects (stick vibration).

## 6. Port notes and UNCERTAIN points

* **Host**: `game/terrain/terrain_view.gd` adds `FlightSounds` (the player's type, `player.type`). `FlightSounds`
  polls the host every frame: flight state, lever variables, view, terrain height. Lever sounds fire on the host's
  accepted lever changes; the host applies the original's lever rules.
* **3-D sounds**: `AudioStreamPlayer3D` at the jet, gain = min / clamp(distance to the camera, min, max)
  (DirectSound rolloff 1), Godot panning, Doppler off. In the cockpit the listener sits at the jet.
* **Inside / outside volume**: ours follows the current view every frame. The original picks it when a sound
  starts; UNCERTAIN whether it updates running sounds.
* **UNCERTAIN**:
  - the logical-channel policy (§2). Here a new sound on a busy channel waits; queue vs replace was not traced;
  - the setter of the inside flag `manager+0x34` was not found. We take it as "listener in the cockpit", from the
    column names;
  - that the per-frame object sound update runs every frame.
* **Original quirk kept** (tell the user): non-resident effects (touchdown, screech, extinguisher) play at the speech
  volume (§2).
* **v1.1**: the sound code audited here is unchanged (engine and flight sounds `FUN_0044fe30`, `FUN_00447e70` with
  the byte table `0x448094`, the mute toggle). The only data change is the tower phrase key `CHARLY_T` → `CHARLIE_T`
  in `phraseparticalsdata.trx`. The key is built from the callsign, so with v1.0 data the tower cannot say "Charlie"
  (v1.0 behaviour, kept).
