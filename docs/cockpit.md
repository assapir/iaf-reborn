# Cockpit data, all aircraft (`resource/cockpits/<dir>/cockpit.ibx`)

Companion to `mfd.md` (MFD pages, defaults, per-aircraft MFD table in its §7). Source: the nine `cockpit.ibx` files plus the
reader `FUN_00520d90` in `assets/ghidra/iafjets.c`. Sections/keys are read with `GetPrivateProfileInt` (missing key = the
per-key default in the exe; an empty value such as `MiddleOffsetX =` reads as 0). The first duplicate key wins. Only the file
named `cockpit.ibx` is read (`cfir/cockpit.ini` differs by one key, `[CHAFF] OffY` 86 vs 87, and is unused).

## Sections present in every cockpit
`PANEL`, `HORIZON`, `LENHORIZON`, `HUD`, `MFD`, `LIGHTSON`, `LIGHT000..009`, `SLIGHT000..003`, gauge sections
(`SPEEDCLOCK`, `ALTITUDELOCK`, `FUELCLOCK`/`FUELDIGITAL`, `VARIOCLOCK`, `RPMCLOCK`, `TEMPCLOCK`, `THROTTLECLOCK`, `+SECONDARY`
twins), `TEXTMESSAGE`, `CHAFF`, `FLARE`. Optional: `PANELRWR` (absent = inactive), `PANELVARIO`/`PANELAOA` (Active 1 only on
F-16), `PANELST`, `LIGHTSOFF`. Light bitmaps: F-16 `Lights4.bmp`, F-15 `f15light.BMP`, F-4-2000/MiG-23/MiG-29 `lights.bmp`,
Lavi `laviligh.bmp`, Kfir `cfirligh.bmp`, Mirage `mrglight.bmp`, F-4E `f4lights.bmp`. `StateLights.bmp` (F-15, F-16, Lavi, Mirage) is
referenced but not shipped. Unreferenced extras: `cfir/cfir-lights.bmp`, `lavi/lavi-lig.bmp`, `phantom/f16adi.bmp`,
`phantom/lights-1.bmp`.

## Decoding rules
* Panel = 1920 wide, cut into 320-px slices; any panel-space X = 320*slice + x (the exe splits `ClockCenterX`,
  `LENHORIZON CenterX` with /320, %320). The screen y of a panel-space point is y + MainOffsetY + vpan
  (`mfd.md` §1); `PanelHeight` = bitmap height.
* `LENHORIZON`: lens ADI bitmap (128x128, 8-bit) behind a panel hole, Center/Radius/Factor (deg per radius); `Factor` 15 except F-15 20.
* `HUD`: glass bitmap `FileName` (Width x Height ~ bitmap size), `MaskOffsetX/Y/Y2` (glass slicing, meaning UNCERTAIN), `CenterY`,
  `BorePositionY`, `GunRetPositionY` (px above the panel top), `VertSclOffY` (stored negated), `Left/Right/Top/BottomBorder`
  (clip from centre), `TxtOffX/Y`, `Dash` (default 0), `ShowHorizon` (default 1), `ShowLRScales` (default 1).

## `[HUD]` per aircraft
| Dir | Glass | W x H | MaskX/Y/Y2 | CenterY | Bore | GunRet | VertSclOffY | L/R/T/B border | TxtOff X,Y | Flags |
|---|---|---|---|---|---|---|---|---|---|---|
| mirage | mrghud.bmp | 264x166 | 23/18/142 | 75 | 115 | 130 | 20 | 85/78/67/52 | 100,52 | - |
| cfir | cfir-h.bmp | 250x205 | 24/20/165 | 110 | 150 | 170 | 0 | 67/68/73/52 | 82,60 | - |
| phantom | f4hud.bmp | 231x141 | 57/8/140 | 70 | 100 | 110 | 0 | 69/64/53/52 | 82,45 | ShowHorizon 0, ShowLRScales 0 |
| f4-2000 | hud.bmp | 275x190 | 14/24/163 | 102 | 130 | 155 | 5 | 85/81/70/52 | 92,53 | Dash 1 |
| f15 | F15hud.bmp | 313x212 | 30/45/149 | 120 | 140 | 170 | 5 | 98/98/60/70 | 109,70 | Dash 1 |
| f16 | F16hud.bmp | 319x182 | 56/23/164 | 88 | 135 | 150 | 15 | 69/70/75/60 | 82,48 | Dash 1 |
| lavi | lavi-hud.bmp | 298x163 | 37/16/148 | 88 | 110 | 130 | -5 | 95/95/55/52 | 92,53 | Dash 1 |
| mig23 | hud.bmp | 239x165 | 35/29/141 | 90 | 110 | 138 | 0 | 65/56/58/52 | 82,45 | ShowHorizon 0, ShowLRScales 0, Dash 1 |
| mig29 | hud.bmp | 385x181 (bmp 386) | 104/15/156 | 100 | 120 | 140 | 0 | 70/67/56/52 | 82,55 | ShowHorizon 1, ShowLRScales 1, Dash 1 |

## Horizon / RWR / ADI sections
| Dir | `[HORIZON]` OnMfd, Active, ClockCenter, Radius | `[LENHORIZON]` file, Center, Radius | `[PANELRWR]` |
|---|---|---|---|
| mirage | 0, 1, X empty (=> default 0x3c0=960), Y91, r17 | mrgadi.bmp, 1094,251, r28 | absent |
| cfir | 0, 1, 1057,208, r22 | adi.bmp, 960,173, r42 | Active 1, 1094,74 r32 |
| phantom | 0, **0**, 1100,91, r17 | adi.bmp, 957,230, r38 | Active 1, 1218,69 r28 |
| f4-2000 | **1**, 1, 963,203, r40 | adi.bmp, 1099,252, r42 | Active 0 |
| f15 | **1**, 1, 784,129, r40 | adi.bmp, 795,249, r34 (Factor 20) | absent |
| f16 | 0, 1, 1100,91, r17 | F16adi.bmp, 966,261, r34 | Active 1, 805,84 r28 |
| lavi | **1**, 1, 786,150, r40 | adi.bmp, 966,292, r20 | Active 0 |
| mig23 | 0, **0**, X empty, Y91, r17 | adi.bmp, 824,133, r32 | Active 0 |
| mig29 | 0, **0**, X 0, Y91, r31 | adi.bmp, 1038,181, r32 | absent |

## What our tooling assumes F-16
* `crates/iaf-tools/src/bin/iaf-convert.rs` `convert_cockpit` is generic (dir name argument; whole ini -> `cockpit.json`; every
  `*.bmp` in the dir + `mfds.bmp`, `rwrsymb.bmp`, `isr.bmp`). Gaps: it does not convert `fsmfd/fsmfd.bmp`, `fsmfd/data.ibx`,
  `emf/map.emf`, and it ignores that `cockpit.ini` and unreferenced bitmaps exist (harmless extras). Empty ini values
  (`ClockCenterX =`, `MiddleOffsetX =`) become the JSON string `""`, not the exe default 0 / 0x3c0.
* `tools/setup.sh:29-30` converts only `f16` -> `assets/converted/cockpits/f16`.
* `game/cockpit/cockpit.gd`: `cockpit_dir` default `.../cockpits/f16`; `HUD_REAL_FOV = 25` and `HUD_GLASS_PIXELS = 200`
  (F-16 HUD width 319-2*56 = 207) are F-16 constants; `_draw_mfd_screens` paints a fixed 160x230 black box at offset -6 for each
  active MFD (real MFD is 132x132, at OffsetX/Y); `_draw_standby_horizon` ignores `[HORIZON] Active` (would draw a disc on
  phantom/mig23/mig29) and would fail on empty `ClockCenterX`; `OnMfd = 1` planes (F-15, F-4-2000, Lavi) show no ADI at all;
  `[PANELRWR]` is not drawn; `_draw_tape` covers only `PANELVARIO`/`PANELAOA` (F-16 only) and `VARIOCLOCK` (F-4-2000, Lavi, MiG-23,
  MiG-29) is not drawn; `FUELDIGITAL` (F-16) is drawn but `FUELCLOCK` (others) is not; lights (`LIGHTSON`) are not drawn (see "Panel lights" below).
* `game/terrain/terrain_view.gd` uses the F-16 model/flight ("F-16", `f16_h.gltf`, `_spawn_f16`),
  and `game/aircraft/aircraft_model.gd` has F-16 flaperon/stabilator mixing constants (not cockpit, listed for completeness).

## Panel lights (`[LIGHTSON]`, `[LIGHT000..009]`, `[SLIGHT000..003]`, `[TEXTMESSAGE]`, `[CHAFF]`/`[FLARE]`, `[PANELST]`)
Generic code, the same for every cockpit. Reader `FUN_00520d90`; light objects are built by `FUN_005208a0` inside the ini copy at
renderer+0x20c0. The light bitmap is loaded by `FUN_00526b30` and lights are drawn by `FUN_00526870` (draw pass 3, called every frame
from the cockpit frame function @181877). Offsets below are relative to renderer (R) or cockpit state S = `*(R+0x20b8)`. S is the
global `0x67fda8` (`FUN_00459e30`).

### Keys and objects
* `[LIGHT000]..[LIGHT008]` (loop, `FUN_00526ca0`): `Active` (default 0), `Left/Top/Right/Bottom/OffsetX/OffsetY` (default 1;
  an empty value reads as 0), `Blink` (default 0). Object = 0x38 bytes at R+0x226c+0x38*i: +4 OffsetX, +8 OffsetY,
  +0xc w = Right-Left, +0x10 h = Bottom-Top, +0x14 Active, +0x18 Blink, +0x1c blink phase, +0x20 blink timer, +0x24 Left, +0x28 Top,
  +0x2c last value, +0x30 re-blit flag, +0x34 slice. vtable `0x608320` = {draw `FUN_00526d90`, source rect `0x526d20`}.
* `[SLIGHT000]..[SLIGHT003]`: same keys and the same class, but `Blink` is not read (forced to 0). Objects at R+0x2464+0x38*j.
* `[LIGHT009]` is read separately into an animated object at R+0x2544 (vtable `0x608338` = {draw `FUN_005271e0`, rect `0x527320`}).
  It has no `Blink`; it reads `AnimTime` (default 2000) and `AnimFrames` (default 2), and step time = AnimTime / AnimFrames (integer,
  `FUN_00527360`).
* `[LIGHTSON]`: `FileName`, `Width`/`Height` (surface size, defaults 141x55, `FUN_00521e50`), `NightRScale/NightGScale/NightBScale`
  (defaults **0/2/4**, packed at R+0x2588). The surface (R+0x600) has colour key cyan RGB(0,255,255), like the MFDs.
* **`[LIGHTSOFF]` and `[SLIGHTS]` (`StateLights.bmp`) are never read.** The strings are not in the exe. The SLIGHTs use the
  `[LIGHTSON]` bitmap, which is why the missing `StateLights.bmp` does not matter.

### Source frames: the "off" look is in the light bitmap, not the panel
The source rect for value/frame v is `x = Left..Left+w`, `y = Top + v*h .. Top + (v+1)*h` (`0x526d20`). The frames are stacked
vertically under `Top`:
* LIGHT000..008: frame 0 = unlit art (a dim or dark lamp with its label), frame 1 = lit art. If `Blink` = 1, the frame is the blink
  phase instead of the value (see below).
* SLIGHT000..003: three frames, where frame = state 0/1/2 (any other value is treated as 0).
* LIGHT009 (gear handle): AnimFrames frames, where frame 0 = handle up and the last frame = handle down.
At load (`FUN_00526b30`), frame 0 of every active light is stamped into the panel slices. **So "off" = frame 0 of the lights bitmap
pasted over the panel, not the bare panel art.** (Cyan pixels in it stay transparent.)

### Drawing (`FUN_00526d90`)
* If `Active` = 0, the light is never drawn or stamped. (But the click hit-test `FUN_0051fc80` ignores `Active`, so the rect of an
  inactive light is still clickable.)
* When the value changes, or when the force flag R+0x2fc is set, the light is redrawn. `FUN_00526eb0` BltFasts the source rect
  (src colour key) into the 320-px panel slice: slice = OffsetX/320, x = OffsetX%320, y = OffsetY - slice top (the
  MaskOffsetY table at R+0x20c4). It is split over two slices when it crosses a 320 boundary, exactly as for the MFDs. Then
  `FUN_005270f0` also blits it straight to the back buffer at screen `(OffsetX - pan(R+0x564) - 640, OffsetY + MainOffsetY + vpan(R+0x568))`.
  If R+0xc ≠ 0 (UNCERTAIN: flip/back-buffer mode), the next frame re-blits to the screen once more (+0x30).
  Unchanged lights cost nothing: their current frame is already baked into the panel slices.
* **Blink** (`Blink` = 1): while the stored value (+0x2c) ≠ 0, the frame time dt (ms, `timeGetTime` delta R+0x574 - `DAT_00839444`)
  is added to +0x20. When the total exceeds **300 ms**, it resets and the phase +0x1c toggles, so the light alternates dark and lit
  every 300 ms (a period of about 600 ms, quantised to frames). When the light turns on it starts at phase 0 (dark). Value 0 resets
  the phase to 0. In every cockpit only LIGHT001/LIGHT002 (engine fire) have `Blink = 1`.
* **Gear handle animation** (`FUN_005271e0`): when the value changes, a global anim flag is set (`DAT_00839440`, so there is one
  animation at a time). The frame starts at 0 (going down) or at AnimFrames-1 (going up). Each time the accumulated dt exceeds the
  step time, it moves by one frame toward AnimFrames-1 (down) or toward 0 (up). F-15 `AnimTime = 0` gives a step time of 0, so it
  moves one frame per rendered frame.
* Order in `FUN_00526870`: LIGHT000..008, then LIGHT009, then the SLIGHTs. If the handle moved to down (value 1), the SLIGHTs are
  force-redrawn. If any SLIGHT redrew while the handle is up, the handle is redrawn with force. These rects overlap on the F-15
  (handle 637..695 x 227..274 over the wheel lamps).
* **Night** (`FUN_0052c420`, applied once when the bitmap is loaded): hour = t·0.001/60/60, with t = the time-of-day argument
  of `FUN_0051cf10` (from `FUN_004cf110`, apparently ms since midnight; UNCERTAIN unit). It is night if **20 ≤ hour < 24 or
  0 ≤ hour ≤ 5**. At night every non-colour-key pixel of the 16-bit surface is darkened per channel: **R >>= NightRScale,
  G >>= NightGScale, B >>= NightBScale** (the values are shift counts, `FUN_0052c290`). The panel (`[PANEL] Night*Scale`, R+0x20e8)
  and the HUD glass bitmap (`FUN_00527380`) are darkened the same way with the panel values. Note: the surface-lost reload paths
  call `FUN_0051cf10(cockpit, 0)`, i.e. hour 0, which is night (UNCERTAIN quirk).

### What drives each light (all aircraft)
S+0x518+4i = indicator i of the player controller (`ctl+0x4ec+4i`, flushed by `FUN_0045aa20` -> `FUN_00445ea0`, 10 dwords).
S+0x540+4j = the "special indicator" j (`ctl+0x548+4j`, flushed by `FUN_0045a6a0` -> `FUN_00445e70`, 4 dwords).
Indicators are set with `FUN_0045a920(i, duration)` (duration 0.0 = stays on) and cleared with `FUN_0045a9b0(i)`.

| Light | ini comment | State | On when (code) | Off when |
|---|---|---|---|---|
| LIGHT000 | master | S+0x518 | any damage event: end of the damage handler `FUN_0044ca90` -> `FUN_0045aa00` (plus warning sound 0x2c006000/0x18001000) | GEV 0x69 = clicking the light (`FUN_0051fcf0` case 0xf) |
| LIGHT001 | left eng | S+0x51c | damage 0x10 "Engine on fire"/"Left engine on fire" | GEV 0x49 fire extinguisher (clears 1 and 2, @44a9c2) |
| LIGHT002 | right eng | S+0x520 | damage 0x11 (right engine fire) | GEV 0x49 |
| LIGHT003 | ai | S+0x524 | RWR: a missile is guiding on us (`FUN_0044db40` <- missile object @4d69db sets the RWR entry launch flag +0x20) and its emitter's class (unit+0x30)+8 is **not** in {5,8,9,10,0x10}; sound 0x18002000 (`FUN_004504d0`, `FUN_0044d890`) | no such entry, RWR off or damaged (damage 0xe), emitter dropped (`FUN_0044da10`) |
| LIGHT004 | sam | S+0x528 | same, but the emitter class is in {5,8,9,10,0x10} (ground; UNCERTAIN class names) | same |
| LIGHT005 | air brake | S+0x52c | GEV 0x11 TGL_BRAKES toggles it (speed brakes out) | toggle |
| LIGHT006 | radar jammer (ecm) | S+0x530 | GEV 0x46 TGLECM when ECM is fitted (ctl[0x6e]) | toggle off; ECM damage (1) |
| LIGHT007 | landing hook | S+0x534 | **never set** (no call with i = 7); `Active = 0` in every cockpit | - |
| LIGHT008 | ap | S+0x538 | autopilot mode ctl+0x974 ≠ 0: GEV 0x10 cycles 0->1 (on)->2->0 (off); **on at an airborne start** (@447805) | stick deflection beyond ±0x33 (GEV 1), mode 2->0, on-ground press, AP damage (6) |
| LIGHT009 | gear handle | S+0x53c | handle down, `ind[9]` (flight-model.md §12) | handle up |
| SLIGHT000 | wheels mid | S+0x540 | gear leg 0: 0 up, 1 transit, 2 down & locked | - |
| SLIGHT001 | wheels left | S+0x544 | gear leg 1 | - |
| SLIGHT002 | wheels right | S+0x548 | gear leg 2 | - |
| SLIGHT003 | flaps | S+0x54c | flaps state 0/1/2 (GEV 0xc; player: 0->1->2 with a 2.0 s step, 2->1->0 on retract) | - |

Clicking lights (hit-test `FUN_0051f2a0` via `FUN_0051f930`, only in view modes 1/0x12/0x16; actions `FUN_0051fcf0`): LIGHT009 -> GEV 0xe gear, SLIGHT003 -> 0xc flaps,
LIGHT008 -> 0x10 AP, LIGHT005 -> 0x11 brakes, LIGHT006 -> 0x46 ECM, LIGHT001 -> 0x49(0) extinguisher, LIGHT002 -> 0x49(1),
LIGHT000 -> 0x69(1) master caution reset.

**Landing-gear lights: exact rule.** There are three independent lamps, SLIGHT000 (mid/nose), 001 (left) and 002 (right). Each
shows frame = its own leg state from flight-model.md §12:
* **0 (up and locked) -> frame 0 = unlit lamp** (grey/dark art from the light bitmap, not the panel).
* **1 (in transit, 2.0 s each way) -> frame 1 = red** (F-15 #ff0000, F-16 #e23412, Lavi #ff3400, Kfir/Mirage/MiG-23 red-orange,
  F-4E/F-4-2000 hatched dull orange, **MiG-29 amber #fea500**).
* **2 (down and locked) -> frame 2 = green.**

The legs move independently, so the three lamps can differ (for example a leg that cannot move). Two special cases:
* Gear damage (damage 7) sets all three legs to 1, so all three stay red permanently.
* When the flush runs (`FUN_0045a6a0`) with legs 1 and 2 both 0, leg 0 is forced to 0.

The handle (LIGHT009) animates to its down frame on ind[9] = 1, independently of the lamps. Mirage, F-15 and MiG-23 use one source
rect for all three lamps, so the art is identical.

### Per-aircraft light table
Cell = panel `OffsetX,OffsetY` (1920-wide panel px, top-left) and size WxH, or "-" when `Active` = 0. L9 adds frames/AnimTime. The
art labels of L3/L4 are "AI"/"SAM" (F-16, F-15, Lavi, F-4-2000), "AI"/"SA" (Kfir), and **"AI"/"ML"** (Mirage, F-4E, MiG-23, MiG-29).
L1 = "FIRE" (single-engine planes: the only engine). L2 is active only on F-4E, F-4-2000 and MiG-29; the F-15 is twin-engine
(logic+0x24) but its LIGHT002 is inactive, so its right-engine fire shows no light.

| Dir | L0 master | L1 eng/L-eng fire | L2 R-eng fire | L3 AI | L4 SAM | L5 air brake | L6 ECM | L7 hook | L8 AP | L9 gear handle | S0 gear mid | S1 gear left | S2 gear right | S3 flaps |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mirage | 1224,145 35x14 | 1228,199 28x9 | - | 1114,68 15x14 | 1094,68 15x15 | 1194,194 14x12 | - | - | 1187,134 12x12 | 648,254 20x59 (2f/100ms) | 654,215 9x9 | 648,226 9x9 | 661,226 9x9 | 1174,194 13x12 |
| cfir | 1144,82 45x16 | 1205,108 34x15 | - | 1081,130 12x10 | 1100,131 13x9 | 708,103 25x11 | 1148,62 25x11 | - | 743,60 14x9 | 682,211 19x59 (2f/100ms) | 684,166 7x14 | 676,188 7x13 | 693,188 8x13 | 708,88 26x11 |
| phantom | 1202,164 44x16 | 1196,146 23x11 | 1226,146 23x11 | 1166,122 15x14 | 1147,122 15x15 | 679,133 24x11 | 1137,73 21x10 | - | 721,86 28x12 | 652,224 25x87 (3f/200ms) | 673,202 15x15 | 658,202 15x15 | 688,202 15x15 | 678,154 24x11 |
| f4-2000 | 1217,135 44x16 | 1085,28 29x14 | 1127,28 29x14 | 766,35 15x10 | 791,35 22x10 | 680,111 24x10 | 826,33 24x11 | - | 680,90 24x11 | 651,193 23x83 (3f/100ms) | 673,173 15x15 | 657,173 14x15 | 688,173 15x15 | 680,131 24x11 |
| f15 | 883,22 44x14 | 668,140 27x27 | - | 993,20 27x7 | 993,30 27x7 | 649,190 33x10 | 821,27 23x10 | - | 772,27 23x10 | 637,227 58x47 (2f/0ms) | 648,222 11x6 | 637,231 11x6 | 659,231 11x6 | 649,182 33x8 |
| f16 | 684,37 53x53 | 1219,58 41x42 | - | 711,107 18x5 | 730,107 21x5 | 648,266 22x5 | 732,81 17x5 | - | 651,279 12x5 | 679,209 21x86 (3f/100ms) | 651,199 12x11 | 640,213 11x10 | 662,213 10x10 | 648,259 22x5 |
| lavi | 818,21 44x16 | 753,43 33x16 | - | 793,45 23x13 | 822,43 23x13 | 1116,41 16x7 | 1135,51 16x7 | - | 1117,51 14x7 | 661,245 13x48 (3f/100ms) | 668,214 12x7 | 661,224 12x7 | 676,224 12x7 | 1116,32 16x7 |
| mig23 | 1059,165 38x16 | 1059,185 38x15 | - | 1188,178 13x11 | 1167,178 15x12 | 797,64 31x12 | 1161,89 23x11 | - | 856,76 27x13 | 672,262 16x62 (2f/100ms) | 727,151 14x14 | 711,151 14x14 | 743,151 14x14 | 798,47 32x11 |
| mig29 | 1103,9 35x14 | 945,161 31x13 | 945,181 31x13 | 780,20 16x15 | 754,20 16x15 | 873,233 30x14 | 806,21 19x13 | - | 1257,91 24x11 | 655,210 21x88 (2f/100ms) | 663,169 7x7 | 655,184 7x7 | 670,184 7x7 | 873,212 31x14 |

Source rects (Left,Top,Right,Bottom) are in each `cockpit.ibx`; all of them fit inside their bitmaps. Every frame-0 image is an unlit
lamp and every frame-1/2 image is lit (checked by sampling the bitmaps).

### `[TEXTMESSAGE]` (`FUN_0052cd00`), `[CHAFF]`/`[FLARE]` (`FUN_0052cf90`)
* Keys and defaults: `OffsetX1` 1072, `OffsetY1` 21, `OffsetX2` 1072, `OffsetY2` 36, `LengthChar` 20 (R+0x26ec..0x26fc);
  `[CHAFF]`/`[FLARE]` `OffX`/`OffY` default 36/36 (R+0x2700..0x270c).
* Text = the NUL-terminated string at S+0x109c. Every frame `FUN_00447f50` copies it with `FUN_004465a0` =
  `strncpy(S+0x109c, *(char**)(ctl+0x64), 20)`, so at most 20 chars. What ctl+0x64 points to was not traced (UNCERTAIN).
* Pass 2 erases two boxes of `LengthChar*5` x 9 px at (X1,Y1) and (X2,Y2) by re-blitting the panel slice.
* Pass 4 uses GDI `TextOutA`, font R+0x57c (Arial h10 w5 weight 100), TA_LEFT|TA_TOP, transparent background, at screen
  (X - pan - 640, Y + MainOffsetY + vpan). The colour is not set by the routine; the caller last set 0x00ff00 green before the MFD
  pass (UNCERTAIN whether the MFD pass changes it).
* **Two lines**: if len < LengthChar, one line at (X1,Y1). Otherwise the break is at the last space at or before index LengthChar-1
  (line 1 keeps that space), and the rest goes at (X2,Y2), truncated to LengthChar chars. The search has no lower bound, so a string
  without a space would run backwards (latent bug). With 20 chars at most, only the F-16 (`LengthChar = 19`) can ever wrap.
* Chaff/flare: `sprintf("%03d")` of S+0x4bc (chaff) and S+0x4d8 (flare), drawn with the same font, colour **0xb3ffff = RGB(255,255,179)**
  (pale yellow), top-left at `OffX,OffY` (screen transform as above). These addresses are the count fields of stores stations 10 and 11
  in the stores array S+0x3a0 (0x1c stride, `mfd.md` §3), an inference from the layout. The erase box is `TEXTMESSAGE LengthChar*5`
  x 9 (it reuses that key).

| Dir | Lights bitmap (W x H) | Night R/G/B shift | Text line 1 / line 2 | LengthChar | Chaff | Flare | PANELST |
|---|---|---|---|---|---|---|---|
| mirage | mrglight.bmp 59x140 | 0/2/4 (default) | 905,19 / 905,42 | 24 | 832,155 | 832,168 | yes |
| cfir | cfirligh.bmp 64x139 | 0/2/4 (default) | 901,66 / 901,88 | 24 | 789,86 | 789,100 | yes |
| phantom | f4lights.bmp 69x261 | 0/2/4 (default) | 730,161 / 730,184 | 26 | 745,114 | 745,127 | yes |
| f4-2000 | lights.bmp 68x249 | 1/1/2 | 913,56 / 913,78 | 24 | 932,102 | 994,102 | yes |
| f15 | f15light.bmp 91x164 | 1/0/2 | 896,21 / 896,42 | 24 | 1075,33 | 1122,33 | yes |
| f16 | lights4.bmp 74x278 | 1/1/2 | 1072,21 / 1072,36 | 19 | 1172,80 | 1172,93 | yes |
| lavi | laviligh.bmp 57x165 | 1/1/2 | 903,51 / 903,72 | 24 | 1073,34 | 1073,47 | no |
| mig23 | lights.bmp 86x124 | 0/2/4 (default) | 908,65 / 908,87 | 24 | 1082,79 | 1082,93 | no |
| mig29 | lights.bmp 56x211 | 0/1/2 | 900,55 / 900,72 | 24 | 859,103 | 1030,108 | no |

The `[PANEL]` Night shifts are listed separately. File names are case-insensitive on Windows; on disk they are `lights4.bmp` and
`f15light.bmp`.

### `[PANELST]`
`NUM` (default 16) and `OFFSET00..` (default PanelHeight) are read into ini[0xb..] (R+0x20ec..). The file comment is "16 points
describing an horizon of the panel" at panel x = 0,120,…,1800, and the values are the panel's top-edge row (e.g. F-16 352 at the
edges, 4 at the centre). **No reader of R+0x20ec.. was found in the exe** (UNCERTAIN: probably unused or read via an unfound alias).

### Open
* ctl+0x64 text source; exact GEV key names for 0x46/0x49/0x69; emitter class ids behind AI vs SAM; R+0xc double-blit flag.
