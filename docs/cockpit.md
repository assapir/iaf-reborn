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
  MiG-29) is not drawn; `FUELDIGITAL` (F-16) is drawn but `FUELCLOCK` (others) is not; lights (`LIGHTSON`) are not drawn.
* `game/terrain/terrain_view.gd` uses the F-16 model/flight ("F-16", `f16_h.gltf`, `_spawn_f16`),
  and `game/aircraft/aircraft_model.gd` has F-16 flaperon/stabilator mixing constants (not cockpit, listed for completeness).
