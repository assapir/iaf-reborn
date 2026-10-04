# Cockpit data, all aircraft (`resource/cockpits/<dir>/cockpit.ibx`)

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 and lists what the patch changed.

Companion to `mfd.md` (MFD pages, defaults, per-aircraft MFD table in its §7). Source: the nine `cockpit.ibx` files plus the
reader `FUN_005228a0` in `assets/ghidra_v11/iafjets.c`. Sections/keys are read with `GetPrivateProfileInt` (missing key = the
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
* `LENHORIZON`: lens ADI bitmap (128x128, 8-bit) behind a panel hole, Center/Radius/Factor (the lens depth, see
  "Attitude indicators"); `Factor` 15 except F-15 20.
* `HUD`: glass bitmap `FileName` (Width x Height ~ bitmap size), `MaskOffsetX/Y/Y2` (glass slicing, meaning UNCERTAIN), `CenterY`,
  `BorePositionY`, `GunRetPositionY` (px above the panel top), `VertSclOffY` (stored negated), `Left/Right/Top/BottomBorder`
  (clip from centre), `TxtOffX/Y`, `Dash` (default 0), `ShowHorizon` (default 1), `ShowLRScales` (default 1).

## `[HUD]` per aircraft
| Dir | Glass | W x H | MaskX/Y/Y2 | CenterY | Bore | GunRet | VertSclOffY | L/R/T/B border | TxtOff X,Y | Flags |
|---|---|---|---|---|---|---|---|---|---|---|
| mirage | mrghud.bmp | 264x166 | 23/18/142 | 75 | 115 | 120 (v1.0 130) | 20 | 85/78/67/52 | 100,52 | - |
| cfir | cfir-h.bmp | 250x205 | 24/20/165 | 110 | 150 | 160 (v1.0 170) | 0 | 67/68/73/52 | 82,60 | - |
| phantom | f4hud.bmp | 231x141 | 57/8/140 | 70 | 100 | 110 | 0 | 69/64/53/52 | 82,45 | ShowHorizon 0, ShowLRScales 0 |
| f4-2000 | hud.bmp | 275x190 | 14/24/163 | 102 | 130 | 145 (v1.0 155) | 5 | 85/81/70/52 | 92,53 | Dash 1 |
| f15 | F15hud.bmp | 313x212 | 30/45/149 | 120 | 140 | 160 (v1.0 170) | 5 | 98/98/60/70 | 109,70 | Dash 1 |
| f16 | F16hud.bmp | 319x182 | 56/23/164 | 88 | 135 | 140 (v1.0 150) | 15 | 69/70/75/60 | 82,48 | Dash 1 |
| lavi | lavi-hud.bmp | 298x163 | 37/16/148 | 88 | 110 | 130 | -5 | 95/95/55/52 | 92,53 | Dash 1 |
| mig23 | hud.bmp | 239x165 | 35/29/141 | 90 | 110 | 138 | 0 | 65/56/58/52 | 82,45 | ShowHorizon 0, ShowLRScales 0, Dash 1 |
| mig29 | hud.bmp | 385x181 (bmp 386) | 104/15/156 | 100 | 120 | 140 | 0 | 70/67/56/52 | 82,55 | ShowHorizon 1, ShowLRScales 1, Dash 1 |

The v1.1 patch lowered `GunRetPositionY` by 10 px in these five cockpits (the gun now fires 1° up onto the cross,
docs/damage.md §4.4); nothing else in `cockpit.ibx` changed.

### HUD symbology (v1.1, `FUN_00530b70`)
Traced from v1.1 (objdump for the FPU operands and push order). R = the renderer, S = the cockpit state
(`0x82f544`); the `[HUD]` keys sit at R+0x2208.. (`FUN_0051ff70`): CenterY +0x2208, GunRetPositionY +0x220c,
BorePositionY +0x2210, −VertSclOffY +0x2214, TxtOffX / Y +0x2218 / +0x221c, −LeftBorder, −TopBorder, RightBorder,
BottomBorder +0x2220..+0x222c, Dash +0x2230, ShowHorizon +0x2234, ShowLRScales +0x2238. **Every cockpit uses the
same code; only these keys differ** (table above); nothing in the HUD path tests the aircraft type, and all units are
kt / ft / NM for every jet.

* **Frame** (`FUN_00530b70`, views 1 / 0x12 / 0x16 = cockpit): HUD centre (cx, cy) = (320 − pan, MainOffsetY − CenterY +
  vpan); the field = cx − LeftBorder .. cx + RightBorder, cy − TopBorder .. cy + BottomBorder (R+0x2770 RECT); scale k = 1.
  View 5 (HUD only) draws at k = 2 around (320, 240) (ours keeps the cockpit scale and place, deviations.md). With `Dash` 1 and the panel panned
  ≥ 250 px aside or ≥ 200 px down the HUD becomes the helmet display (below). Two passes: 4 (GDI lines and Arial h10 w5 text, R+0x57c, 1 px pen in the HUD colour, null
  brush) and 3 (the 5x5 sprite font, recoloured to the HUD colour, `FUN_00525920` right-aligned / `FUN_00525a30`
  left-aligned, glyph tops at y). GDI text align TA_BASELINE (0x18, 0x1a with TA_RIGHT).
* **HUD dash repeater = the helmet display** (`FUN_00530b70` @530bd0, views 1 / 0x12 / 0x16): with `Dash` 1
  (F-15, F-16, F-4 2000, Lavi, MiG-23, MiG-29) and pan(+0x564) ≥ 250 or ≤ −250 or vpan(+0x568) ≥ 200 (head yaw
  ≥ 11.7°, F-15 13°; or the head looking up ≈ 7°), the HUD centre is the fixed screen point **(320, 220)** (not panned), the field
  R+0x2770 around it, and R+0x2788 = 1. Drawn: the speed and altitude boxes **without** tapes (ShowLRScales forced 0),
  the text block, the mode symbols of `FUN_0052fa10` minus those that test R+0x2788 (mode 1: missile circle and
  seeker diamond; the target box, waypoint marker, range bar), and the DASH symbol `FUN_00539ac0`. Not drawn: the
  heading tape, the ladder and flight path marker, the ILS, the gun cross, the mode 3 / 4 pipper (`FUN_00530040`), the
  mode 5 / 6 bomb symbols (`FUN_005302d0`). The glass bitmap pans away with the panel.
  **DASH symbol** (`FUN_00539ac0`, pass 4, 1 px HUD pen): at (cx, cy) = (320, 220) the aircraft symbol
  Ellipse(cx − 2, cy − 2, cx + 3, cy + 3), wings (cx ∓ 4 → cx ∓ 1, cy), tail (cx, cy − 4 → cy − 1) (the marker's
  shape); and an **attitude bar**: r = roll°, p = pitch° (S+0x10, S+0xc, fmod 360 into [0, 360); p in (90, 270) →
  p = 180 − p and r += 180; p > 270 → p − 360); two polylines (−42, 2)→(−42, 0)→(−5, 0) and (42, 2)→(42, 0)→(5, 0),
  each point (X, Y) drawn at (cx + X·cos r + Y·sin r, cy + 1.5·p + Y·cos r − X·sin r) (`0x60c58c` 1.5 px per degree;
  nose up moves the bar down, the 2 px end ticks point to the ground). |p| > 40° (`0x60c584`): p held at ±40 and the
  bar blinks (a flag flips when > 300 ms of the frame clock R+0x574 have run, DAT_0083e550 / DAT_0065d7a4; steady
  again within ±40).

* **Clip**: only the pitch ladder and marker are clipped to the field (a region); everything else is drawn where it
  falls: the tapes and boxes sit on and beyond the field's edges, the text block below it.
* **Altitude** (`FUN_005381c0`) at x = cx + RightBorder, y = cy − VertSclOffY: in HUD modes 0 / 4 / 5 with the gear
  handle up (S+0x544 = 0) the radar altitude S+0x3c (ft above the ground, ≥ 0) `"%5d R"`, otherwise the barometric
  S+8 · 3.28084 (m when ≤ 0) `"%5d B"`. Text TA_RIGHT at (x + 43, y + 4); box (x, y ± 6)–(x + 34, y ± 6). With
  ShowLRScales: the line (x, y ± 51); 20 ticks every 5 px = 100 ft (20 ft per px, off = ⌊A/20⌋ % 5, tick i at
  (i − 10)·5 + off), 3 px long on the ⌊A/100⌋ % 5 + 5n ones (every 500 ft) and 4 px otherwise, rightwards; labels
  `"%4.1f"` (thousands of ft) every 25 px: y = (⌊A/20⌋ % 25 + 5) + 25(i − 2), value ⌊A/500⌋·0.5 − (i − 2)·0.5,
  i = −1..3, shown for −46 < y < 0 or 10 < y < 53, sprite text ending at x + 25, top y − 7.
* **Speed** (`FUN_005386c0`) at x = cx − LeftBorder, same y: by the HUD mode (S+0xfec): 0 NAV ground speed `"% 3dG"`
  (true airspeed `"% 3dT"` with the gear handle down), 1–3 / 9 indicated `"% 3d"`, 4–8 true `"% 3dT"`, none above 9.
  Text TA_RIGHT at (x − 2, y + 4); box (x − 34 .. x, y ± 6). With ShowLRScales: line (x, y ± 51); unless gun mode 3
  the **required-speed caret** at c = ⌊clamp((S+0x324 − V)·0.6, ±51)⌋: (x + 4, y − c − 3)–(x + 1, y − c)–(x + 5, y − c +
  4); 17 ticks of 6 px = 10 kt (0.6 px per kt, off = ⌊0.6V⌋ % 6), 3 px on the 50 kt ones, else 4, leftwards; labels
  `"%d"` every 50 kt (≥ 0) at y = (⌊0.6V⌋ % 30 + 5) + 30(i − 1), i = −1..2, same visibility rule, ending at x − 3.
* **Heading tape** (`FUN_00537cd0`), y0 = cy − TopBorder: line cx ± 57, centre tick (cx, y0 .. y0 + 4), box (cx ± 11,
  y0 − 12 .. y0) with `"%03d"` of ⌊heading°⌋ mod 360 at (cx − 8, y0 − 2); **2 px per degree**: ticks every 5° (2 px up)
  and `"%02d"` labels (tens) every 10° (sprite, ending at x + 6, top y0 − 7), both only for 11 < |x| < 57 (outside the
  box); the **steering caret** (cx + x − 3, y0 + 4)–(cx + x, y0 + 1)–(cx + x + 4, y0 + 5), x = ⌊2·wrap180(S+0x58° −
  heading)⌋ clamped ±57.
* **NAV cues** (waypoint object `FUN_00452e60` → `FUN_004459f0`): S+0x58 = bearing to the current waypoint
  (atan2(Δx, Δy), clockwise from north), S+0x5c = its 2-D distance · 0.00053937 (NM), S+0x60 = distance / horizontal
  speed / 60 (minutes; 1000 s when not moving), S+0x320 = its index, S+0x324 = distance / (its time T − now) · 1.9428
  (kt; 0 once T has passed).
* **Pitch ladder / flight path marker** (`FUN_00538c90`, v1.1): the marker is the velocity projected (producer in
  `FUN_00448b20` @448cf9: pos + 200·velocity direction → S+0x1c/0x20), Ellipse(x − 2, y − 2, x + 3, y + 3) with wings
  x ∓ 4 → x ∓ 1 and a tail y − 4 → y − 1, drawn only when inside the field. The ladder (ShowHorizon only) hangs on it at
  **12 px/deg**, rolled with the jet: with γ the flight path angle (pitch minus the marker's angular offset,
  `(S+0xc − (S+0x40·R+0x272c + S+0x50·R+0x2730))·57.3`), the rung for angle e sits (e − γ)·12 px above the marker
  along the rolled vertical, so the γ rung passes through the marker. Seven 5° rungs from ⌊γ⌋₅ + 15° to ⌊γ⌋₅ − 15°
  (none past ±90°). In the rung's frame (u along it, r down): positive rungs solid from u = ±9 to ±32 with 3 px end
  ticks toward the horizon (r + 3); the horizon ±9 to ±46; negative rungs dashed ±9–20, ±22–25, ±27–32 with the end
  ticks up (r − 3); `"%02d"` of |e| on every 10° rung but the horizon, sprite text ending at P(±39, 0) + (5, −2), shown
  when that point lies in the field. v1.0 anchored the ladder on the boresight.
* **ILS** (`FUN_005309a0`, NAV HUD mode 0 only, with the **gear handle down** (S+0x544) and the HUD not a dash
  repeater; no distance limit): the NAV mode object's update (`FUN_00460130`, vtable 0x600cc0 slot 4) takes the
  airbase whose **Lineup** point (iaf.ibx) is nearest in 2-D (`FUN_005511a0`, TowersManager `0x699344`) and its
  `RunwayNumber` (read as an int, record +0x4e0); u = unit vector from the jet to the Lineup point (`FUN_00444d30`
  returns 1/|d|);
  **glideslope** = wrap(−5° − asin(u.z)) clamped ±5° (`0x82f678` = −5°, `0x82f67c` = 5°), **localizer** =
  wrap(atan2(u.x, u.y) − RunwayNumber) clamped ±19° (`0x82f670`), both radians in S+0x1034 / S+0x1030 (`FUN_004463f0`).
  Drawn: the glideslope line y = cy − ⌊−12·gs°⌋ (held in [top + 1, bottom − 1]) from cx − 16 to cx + 16 with end ticks
  (y − 1 .. y + 2); the localizer line x = cx − ⌊−12·loc°⌋ (held in [left + 1, right − 1]) from cy − 16 to cy + 16
  with end ticks (x − 1 .. x + 2). **Both lines cross at the HUD centre when the jet is on the runway's extended
  centre line and on a 5° glide path to the Lineup point**; high → the glideslope line drops, the runway to the right →
  the localizer moves right (12 px per degree, the ladder's scale). The 312 briefing ("glide slope 4° below the
  horizon") describes the picture: the HUD centre is ~4° below the boresight (F-16 (135 − 88)/12). The briefing's
  final-approach illustration (`brief/bmp/final_ap.bmp`, a pre-release HUD) shows the same 32 px cross.
* **FUN_0052f690** (every mode): the target box with a lock (`FUN_00537330`); the **gun cross** with the gear handle
  **up** at (cx, MainOffsetY − GunRetPositionY + vpan): (x − 4 .. x + 5, y) and (x, y − 5 .. y + 10); the **waypoint
  marker** in NAV and modes 4–8 (S+0x102c, `FUN_00450460`): the current waypoint on the ground (S+0x70 at the terrain
  height, `FUN_00402080`) projected (S+0x328), held on the field's edge along the line from the HUD centre
  (`FUN_0052db30`), a 10 px circle with `"%d"` (its number) or `"T"` (action 5) in Arial at (+6, +6); weapon cues of
  the bombs / radar (S+0x1460 text, S+0xe68 marks, S+0x100c designator, S+0xa04 = 3 cross, S+0x1024 break X:
  docs/weapons.md).
* **Text block** (`FUN_0052ef20`, k = 1: sprite font; left column left-aligned at cx − TxtOffX, right column ending at
  cx + TxtOffX, rows at cy + TxtOffY + 0 / 7 / 14): left 0 `"AB %1d"` while the afterburner is lit (S+0x1054; with two
  engines (S+0x1038 > 1) the larger of both), else `"T %03d%"` of ⌊rpm·100⌋ (S+0x1040; the lone `%` prints nothing,
  as the briefing's "T 060"); left 1 `"AP LVL"` / `"AP NAV"` (autopilot S+0x1028 1 / 2) or the load factor S+0x344
  `"+%3.1fG"` (≥ 0) / `"%4.1fG"`; left 2 `"NAV"` in NAV, else `"%1d %s %s"` (store total, name, RDY / MAL); right 0
  `"R %2.1f"` (lock range, NM) with a lock (S+0xa20); right 1: NAV and modes 2, 4–8 `"W%02d  %02.1f"` (waypoint number,
  NM), modes 1 / 3 the lock's aspect `"%2dL"` / `"%2dR"` (or `"AUD"` in 1 without a lock, S+0x3a4); right 2: NAV
  `"%3.1f MIN"` below 60 min, modes 1 / 2 / 8 `"%2d SEC"` and 4 `"%2d"` of S+0x380, mode 5 `"%2d SEC"` / `"XX SEC"`
  (≥ 90) of S+0x638 when S+0x620 = 1. **No Mach, AoA or G-limit readout** exists in the original HUD.
* **Per jet** (the keys above): the F-4E (phantom) and MiG-23 have **ShowHorizon 0** (no ladder, the marker stays)
  and **ShowLRScales 0** (the speed / altitude boxes without tapes or carets); the others show both. VertSclOffY
  moves both boxes (F-16 15 px above the centre, Mirage 20, F-15 / F-4 2000 5, Lavi 5 below, others at the centre).
  Dash 1 (helmet display) on F-15, F-16, F-4 2000, Lavi, MiG-23, MiG-29. The ILS, cues and text block are the same for all.
* **Port** (`game/cockpit/hud.gd`, tests/godot/test_hud.gd; the ILS in Rust `iaf_flight::airbase::ils`,
  `IafFlight.ils()`): the field and ladder in the Hud control (clipped), the tapes / boxes / text block on the
  unclipped sibling `HudOuter`; the original geometry in 640x480 pixels × the ui scale. The marker is the velocity
  projected through our camera, which uses the original projection (next section); with it the 12 px/deg ladder
  matches the world (focal length 686.2 px = 11.98 px/deg). Deviations: docs/deviations.md (HUD rows).
* **Gun cross with v1.0 cockpit data**: the file's `GunRetPositionY` is 10 px higher than the v1.1 bullet line
  (~0.8°); ours subtracts 10 when one of the five cockpits above still has its v1.0 value.

### Real HUD (ours, Extras > HUD)
Not in the original: each jet's real HUD / sight / helmet symbology. The per-aircraft reference with every source
and its confidence is [docs/real-hud.md](real-hud.md). Laid out in Rust (`crates/iaf-avionics/src/real_hud/`,
`IafRealHud`) as lines / circles / dots / arcs / texts in the HUD's pixels and drawn by `hud.gd` (`real_hud()`,
`_draw_prims`). The display follows the cockpit: `f16`, `lavi`, `f4-2000`, `cfir` the F-16C/D HUD (dash-34; Lavi,
Kurnass 2000 and Kfir as reconstructions), `f15` the F-15A/C HUD (TO 1F-15A-1), `phantom` the F-4E's ASG-26 optical
sight (red reticle only), `mirage` the CSF gyro gunsight (orange reticle only), the F-35I its helmet's forward virtual
HUD (green, its own 32° × 22° field, not clipped to the glass). Symbol sizes are the real ones in milliradians at the
view's scale. In Real mode the original's ladder, marker, scales, text block, gun cross, waypoint marker, target box
and weapon symbols are not drawn (the ILS, the BORE cross and the TV / HARM diamonds stay); the sight-only jets draw
nothing else. Weapon cues per jet: F-16 SRM reticle + seeker diamond, MRM ASEC + steering dot, DLZ (closure, target
range), EEGS funnel (ours: 35 ft wingspan, M61A1 muzzle speed) with the TD circle, strafe / CCIP pipper and fall line,
steerpoint diamond; F-15 TD box, ASE circle and dot, range scale with IN RNG, LCOS reticle, bomb fall line to the
target square; F-35 target X, steering circle, DLZ bracket with the range; the sights' reticles ride the LCOS / CCIP
pipper (ours: the bombing depression set automatically). Tests: `tests/godot/test_real_hud.gd`, unit tests in each
module; screenshots: `tests/godot/_real_hud_jets_shot.gd` (every jet), `_hud_compare_shot.gd` (original vs real).

### 3D view: the cockpit camera's projection (v1.1)
The world is drawn by TgenAPI (`DAT_0069942c`, 16-bit renderer vtable `0x5fd900`) into viewport 0, every frame from
`FUN_004d9790` (`CFlightWnd::prepareTerrainData`).
* **Field of view**: `FUN_00401f90(0, renderer+0x1ac)` → slot 0x54 `FUN_00404fb0` → `FUN_00403a20(fov)` →
  `FUN_00413490(tan(fov·π/360))`: `0x6284dc = 0.5 / tan(fov/2)`. renderer+0x1ac = **50°** (`0x605250`, set in
  `FUN_004dc9d0` and never changed for viewport 0; `FUN_004dc990` (zoom `50 / z`) is called only for viewport 1, the
  weapon view). The TgenAPI init value 40° (`0x403225`) is overwritten.
* **Projection** (`FUN_00413f90`, used by `FUN_004142b0` / `FUN_004143d0` = slot 0x38, which also projects the
  flight path marker in `FUN_00448b20` @448f82): focal length `0x7d2e54 = (x0 − x1) · 0x6284dc`, i.e.
  **640 / 2 / tan 25° = 686.2 px** (the sign flips the axis), the same for x and y (square pixels; the Direct3D
  matrix `FUN_004133b0` and viewport `FUN_0040b3c0` use the same value). The centre is the viewport's middle:
  `0x7d2e58 = (x0 + x1)/2`, `0x7d2e40 = (y0 + y1)/2`. Near plane 4, far 30000 (`0x6284d0`, `0x6284cc`).
  The 50° is horizontal over the full 640 px; vertically the angle follows from the viewport height.
* **Viewport** (`FUN_00520980` → `FUN_00405b10` → slot 0x58 → `FUN_0040b3c0`): x 0..640, y 0..renderer+0x5b0. In the
  cockpit views (S+0x1088 = 1, 0x12, 0x16; else 480) `FUN_0051f610` sets
  `+0x5b0 = min(480, (D + MainOffsetY + 7 + vpan) & ~7)`, where D (`FUN_0052e750`) is, for the panel columns under
  the two screen edges (panel x = pan + 640 and pan + 1280), the panel row just below the column's lowest
  transparent pixel (colour key RGB(0,210,255), `FUN_0052e6a0` scans the 320-px slice from its bottom), the larger of
  the two; a column without one gives its slice's top row. So the 3D view ends where the panel's see-through
  area ends at the screen edges, and its centre is half that height. Straight ahead (pan = vpan = 0):

  | Dir | D (x 640 / 1280) | viewport rows | centre y | centre above the panel top |
  |---|---|---|---|---|
  | f16 | 104 / 94 | 0..296 | 148 | 42 |
  | f15 | 64 / 79 | 0..288 | 144 | 62 |
  | f4-2000 | 106 / 88 | 0..312 | 156 | 44 |
  | lavi | 95 / 95 | 0..280 | 140 | 40 |
  | cfir | 102 / 104 | 0..304 | 152 | 48 |
  | mirage | 66 / 36 | 0..240 | 120 | 50 |
  | phantom | 136 / 118 | 0..320 | 160 | 20 |
  | mig23 | 128 / 138 | 0..328 | 164 | 26 |
  | mig29 | 45 / 45 | 0..240 | 120 | 70 |

* **Pans** (`FUN_0051f610`): pan(+0x564) = round(20·S+0x1094) + round(1920 / AzimutAngleDeg(rad) · S+0x108c),
  vpan(+0x568) = round(20·S+0x1098) + round((PanelHeight + [HUD] CenterY) / ElevationAngleDeg(rad) · S+0x1090),
  vpan ≥ 480 − MainOffsetY − PanelHeight. `[PANEL] AzimutAngleDeg` (default 90) and `ElevationAngleDeg` (default
  15) are read by `FUN_005228a0` (only the F-15 sets them: 100 / 50). S+0x108c/0x1090 are the head yaw / pitch and
  S+0x1094/0x1098 the view pan (`FUN_0057ff60`, `FUN_00580420`, stored by `FUN_004465c0` @449400); in the forward
  cockpit view (`FUN_0057f2a0` case 1, targets 0 in `FUN_0057fa10`) all four are 0, so **pan = vpan = 0**.
* **Eye and orientation** (`FUN_00582880`, orientation case 0 @5841e9): the eye is the aircraft's position (no
  cockpit offset; kept ≥ 1 m above the terrain, `0x610e14`). The camera has the aircraft's heading and roll and is
  rotated by the head yaw and by `FUN_00585270(head pitch, head yaw) = max(pitch − 5.5°, 0.1·(|yaw| − 90°))`
  (`0x610fa8` = 0.0959931 rad; v1.0 `FUN_00582c20`: 8°). Straight ahead the camera **looks 5.5° below the nose**,
  so the nose axis is 686.2·tan 5.5° = 66 px above the centre (F-16: y 82; the HUD boresight symbol is at
  190 − 135 = 55, the gun cross at 50).
* **Port** (`cockpit.gd` `focal_length` / `projection_centre`, `terrain_view.gd` `_apply_view`): a frustum camera
  with the 686.2 px focal length and the straight-ahead centre (rows measured from the converted panel art at load),
  both in original pixels × the 2D art's scale (`ui_scale`, zoom included) and placed relative to the panel top like
  the art, pitched 5.5° down. The world therefore keeps its place under the HUD when the panel slides (PgUp/PgDn/V,
  ours) or zooms (+/−). A window wider than 4:3 (or the zoomed-out cockpit) shows more world around the original
  frame at the same focal length; nothing is stretched.

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

## Round gauges (traced, v1.1)
* **Records**: the reader stores each needle gauge as a 0x20-byte record in the cockpit data (`SPEEDCLOCK` +0x4ec,
  `ALTITUDELOCK` +0x4cc, `FUELCLOCK` +0x50c, `VARIOCLOCK` +0x52c, `RPMCLOCK` +0x54c, `RPMCLOCKSECONDARY` +0x56c,
  `TEMPCLOCK` +0x58c, `TEMPCLOCKSECONDARY` +0x5ac, `THROTTLECLOCK` +0x5cc, `THROTTLECLOCKSECONDARY` +0x5ec;
  `FUELDIGITAL` +0x60c, reader calls @523608..523736). Setup `FUN_00523a40`: +0 Active, +4/+8 OffsetX/Y, +0xc Radius,
  +0x10 OffsetX / 320 (panel slice), +0x14 AngleOffset, +0x18 2π / FullClock (`0x60c1f8` = 6.283185), +0x1c pen.
* **Needle** `FUN_00527e50`: `angle = max(value · 2π / FullClock, 0) + AngleOffset` (the floor is `0x60c2b0` = 0.0), a
  line of length Radius from the centre (MoveToEx / LineTo). Linear, and **no needle turns below its zero**: the
  vario rests at 0 in a descent.
* **Panel draw** `FUN_00527a40` (records copied at +0x20c8 into the window, so record +0x4ec is at window +0x25b4;
  `S` = the cockpit state `*(window+0x20c0)`, the global `0x684760`): mode 2 = redraw the backgrounds, mode 4 = needles.
  | gauge | input | what it is (writer) |
  |---|---|---|
  | `ALTITUDELOCK` | S+8 | own drawer `FUN_00527c10`, below |
  | `SPEEDCLOCK` | S+0x330 | speed · 1.9428 = **kt** (`FUN_004459a0`, `0x600a70`) |
  | `FUELCLOCK` | S+0x1058 | **total fuel / internal capacity, capped at 1** (@45acb9) |
  | `VARIOCLOCK` | S+0x54 | vertical speed · 196.848 = **ft/min** (`FUN_004459a0`, `0x600a74`) |
  | `THROTTLECLOCK` / `…SECONDARY` | S+0x1040 / +0x1060 | **rpm** (0..1) |
  | `RPMCLOCK` / `…SECONDARY` | S+0x1044 / +0x1064 | **clamp(rpm, 0.6, 0.97)** (`FUN_0045aa10`) |
  | `TEMPCLOCK` / `…SECONDARY` | S+0x1048 / +0x1068 | **clamp(rpm, 0.5, 0.8)** (`FUN_0045aa40`) |
  All the round needles are drawn, `THROTTLECLOCKSECONDARY` included (it is active only on the twin-engine cockpits).
* **Engine values** (@45ac00, the player controller: damage flags at +0x3d8): `rpm` = FM query 0x11 · 0.01 (`FUN_0045a9d0` → FM
  vtable `0x611dc8` slot 26 `0x5a9280`, case 0x11 @5a997a: the RPM ramp `S+0x1b0` of the FM read copy `veh+0xc30`,
  docs/flight-model.md "RPM ramp" — 100·rpm at 15 %/s). The setter `FUN_00446490` (left engine → S+0x103c..+0x1058) and
  `FUN_004464f0` (right → S+0x105c..+0x1078) get **the same rpm**: the original has one engine state too. Only the
  damage flags differ (docs/damage.md §5, left / right): cut out 2 / 3 → RPM 0; fire 16 / 17 → TEMP 0.9; permanent
  damage 22 / 23 → THROTTLE 0 and RPM 0 (and the AB flag S+0x1054 0, with AB damage 8 / 9 too). The other setter fields:
  +0x103c = controller +0xc, +0x104c = total fuel lb, +0x1050 = controller +0x24.
* **Fuel** (`FUN_0045aa80`, controller +0x1c, lb): set from the FM fuel ramp ·2.2046 (@5a21a6, @5a82cc, @5a8c78; at the
  start internal + tank fuel); the capacity +0x20 = the FM's internal fuel (`+0xc4c`+0xc0, kg) · 2.2046, once. Below
  1000 lb and again below 500 lb it plays `0x2c003000` once (the player's own jet only).
* **Altimeter** `FUN_00527c10`: two needles from S+8 · 3.28084 = ft, **FullClock is not used**: a long one at one turn
  per 1000 ft (·0.001·2π) and one 3 px shorter at one turn per 10,000 ft (·0.0001·2π), both from AngleOffset, floor 0.
  (The MiG-29's `[ALTITUDELOCK]` has no FullClock; a missing one reads 0.)
* **Port**: the values in Rust (`iaf_flight::instruments::engine_needles`, the fuel fill; unit tests there), the
  needles drawn by `cockpit.gd` `_draw_needle`.
  Checked on all nine cockpits (tests/godot/test_player_aircraft.gd): every active needle but the altimeter has a
  FullClock > 0 and the scale its input expects (engines ≈ 1, fuel 1.3..1.9, vario 30000, speed 1000).

## Attitude indicators and tapes (traced, v1.1)
Window offsets (R) as in "Round gauges"; the ini copy is at R+0x20c8 (`[HORIZON]` R+0x2178.., `[LENHORIZON]`
R+0x219c.., `[PANELVARIO]` R+0x21b4.., `[PANELAOA]` R+0x21cc..). S = the cockpit state: S+0xc / +0x10 / +0x14 =
pitch / roll / heading (rad, copied from the unit's attitude by `FUN_004458b0`), S+8 = height (m), S+0x3c = height
above the ground in ft (`(z − ground)·3.28084 − clearance·3.28084`, 0 below 1), S+0x50 = AoA (rad; the HUD's
flight-path angle pairs it with cos roll, S+0x40 = sideslip with sin roll), S+0x54 = vertical speed in ft/min.
`FUN_00522190` caches roll / pitch / heading as whole degrees mod 360 (truncated, `0x566ef0` chops) at R+0x2720 /
+0x2724 / +0x2728 and their sin / cos.

* **Lens ADI** `[LENHORIZON]` (`FUN_005276f0`; every cockpit but those with Active 0): the 128×128 ball bitmap is
  sampled through a lens table built once (`FUN_00532fc0(2R, Factor)`): for a pixel (x, y) from the centre of the 2R
  square, inside the disc `z = sqrt(F² − (x² + y² − R²)) + 1` and `(u, v) = (x, y)·(1 + 2F / (z + F))`, outside
  `(u, v) = 2·(x, y)`. Each frame (mode 1, `FUN_00532ad4`) with s, c = sin / cos(S+0x10) · 32766 in 16-bit fixed point:
  texture column `(u·c − v·s) >> 16` + 64, row `((v·c + u·s) >> 16) + 62 − fmod(pitch°, 360)·128/360`, the row
  wrapping at 128: **the ball's 128 rows are 360° of pitch (0.36 texel per degree), the horizon at row 62; Factor is
  the lens depth, not degrees per radius.** Mode 2 blits the 2R square (colour key cyan) under the panel, which shows
  it through its hole (key `0xffd200` = RGB 0,210,255).
* **Panel horizon disc** `[HORIZON]` with OnMfd 0 (`FUN_005268b0` mode 4, the GDI pass; mode 3 then blits the panel
  square back with its colour key, so it shows only through the hole): pitch p and roll r from R+0x2724 / R+0x2720
  (−ve + 360; 90 < p < 270 → p = 180 − p, r + 180; p > 270 → p − 360, never reached with |pitch| ≤ 90°); sn, cs =
  sin / cos(r) · `Scale`; a point (x, y) → (trunc(sn·y + cs·x), trunc(cs·y − sn·x)) + (trunc(p·sn/2), trunc(p·cs/2)) +
  centre: **0.5 px per degree of pitch at Scale 1**. Clipped to the ±Radius square: FillRect `GndColor`, the `SkyColor`
  polygon (−30, 0) (30, 0) (30, −90) (−30, −90) with the white 1 px pen (R+0x59c, `0xffffff`), then 12 white lines
  (0x65cec0): (0,0)→(±20,6) and (0,0)→(±15,15) (ground perspective), ticks at y = ±4, ±8, ±12, ±16 (8° apart, ±3 and ±8
  wide alternately).
* **MFD ADI page** (9, `FUN_00526fe0`, `[HORIZON]` OnMfd 1: F-15, F-4 2000, Lavi): the same disc centred at (65,74)
  of the MFD; then white, right-aligned on the baseline (`SetTextAlign 0x1a`): the indicated airspeed `%03d` at
  (31,27) (S+0x33c, below), heading `%03d` at
  (74,12) (S+0x14 in degrees mod 360), height above the ground `%05d` at (124,27) (S+0x3c).
* **Tapes** (`FUN_005280b0` vario, `FUN_00528270` AoA; F-16 only): the PanelHeight rows of the tape from
  `Height/2 − PanelHeight/2 ∓ trunc(·)`, clamped to the tape, are blitted to (OffsetX, OffsetY): vario −trunc(S+0x54 ·
  Height / 60000), AoA +trunc(Height · 0.02 · S+0x50·57.2958) (Height / 50 px per degree). At 0 both show the tape's
  middle.
* **Speeds** (`FUN_00448b20` → `FUN_004459a0(q5, q6, q7, q0x10)`, FM getter `0x5a9280` = vtable `0x611dc8` slot 26):
  S+0x330 = query 5 (the airspeed V, vtable +0x3c) · 1.9428 = **true airspeed, kt** (SPEEDCLOCK); S+0x334 = query 6
  (sqrt(vx² + vy²)) · 1.9428 = **ground speed**; S+0x338 = query 7 (vz) · 1.9428; S+0x54 = vz · 196.848 (ft/min);
  S+0x33c = query 0x10 · 1.9428 = **indicated airspeed**: with V in kt and h the Z axis height in ft (sampled as the
  attitude, τ clamped to 0..1.1), `r = ((−1.305e-5 + 3.1825e-9·V)·h + 1.0017)·V − 3.122`; query 0x10 returns r·0.5147
  (m/s) when 50 ≤ r ≤ 999, else V **in kt**, which the caller converts once more: below 50 kt indicated (taxiing) the
  cockpit shows 1.94 × the speed (an original unit slip, kept with Flight data = Original; Real fixes it,
  docs/real-aircraft.md §2.3).
* **HUD speed** (`FUN_005386c0` @538739, by the HUD mode S+0xfec = the weapon handler's, through the byte table
  0x538c78 → 0x538c64): mode 0 NAV `% 3dG` (ground speed; `% 3dT` true airspeed with the gear handle down, S+0x544),
  1..3 (SRM, MRM, AA gun) and 9 `% 3d` (indicated), 4..8 `% 3dT`, above 9 none. (Mode 9 is not in the master-mode
  table, docs/weapons.md §2.3.)
* **Port**: the values in Rust, `iaf_flight::instruments` (speeds, vario, height above ground, fuel fill, engine
  needles with the damage flags; `IafFlight.instruments(damage flags)` → the cockpit state each frame); the drawing in
  Godot: `cockpit.gd` `_draw_adi` (shader `lens_adi.gdshader` on a child behind the panel, continuous instead of per
  original pixel), `draw_horizon_disc` (panel and MFD page), `_draw_tape`; `mfd.gd` `_draw_adi`; `hud.gd`
  `speed_text`. Checked on all
  nine cockpits (tests/godot/test_player_aircraft.gd) and in posed captures (F-16, F-15, F-4 2000, Kfir).

## What our tooling assumes
* `crates/iaf-tools/src/bin/iaf-convert.rs` `convert_cockpit` is generic (dir name argument; whole ini -> `cockpit.json`; every
  `*.bmp` in the dir + `mfds.bmp`, `rwrsymb.bmp`, `isr.bmp`; `emf/map.emf` -> `map.json`). Gaps: it does not convert
  `fsmfd/fsmfd.bmp`, `fsmfd/data.ibx`, and it ignores that `cockpit.ini` and unreferenced bitmaps exist (harmless extras). Empty ini values
  (`ClockCenterX =`, `MiddleOffsetX =`) are left out of the JSON, so the reader's default (the exe's) applies:
  `GetPrivateProfileInt` returns the default when the value reads as an empty string (Wine's `GetPrivateProfileIntW`;
  0 only for text that is not a number). The Mirage's empty `ClockCenterX` is therefore 960, under the opaque panel:
  its standby disc is hidden (read as 0 it showed at the panel's left edge).
* `tools/setup.sh` converts every cockpit (step "cockpits": f16, f15, f4-2000, phantom, cfir, lavi, mirage, mig23, mig29).
* `game/cockpit/cockpit.gd`: `cockpit_dir` defaults to `.../cockpits/f16` and is replaced by the player's cockpit;
  MFDs placed from `[MFD]` (`_create_mfds`, mfd.md §7); the attitude indicators and the vario / AoA tapes follow the
  original (see "Attitude indicators"); all round needles are drawn with the original's inputs (see "Round gauges");
  lights drawn (`_draw_lights`, "Panel lights" below).
* `game/terrain/terrain_view.gd` flies the player's type (`aircraft/player_aircraft.gd`, docs/aircraft.md §5) and
  loads its cockpit (`cockpit.load_cockpit`),
  and `game/aircraft/aircraft_model.gd` keeps the per-type mixing constants (not cockpit, listed for completeness).

## Panel lights (`[LIGHTSON]`, `[LIGHT000..009]`, `[SLIGHT000..003]`, `[TEXTMESSAGE]`, `[CHAFF]`/`[FLARE]`, `[PANELST]`)
Generic code, the same for every cockpit. Reader `FUN_005228a0`; light objects are built by `FUN_005223b0` inside the ini copy at
renderer+0x20c8. The light bitmap is loaded by `FUN_00528660` and lights are drawn by `FUN_005283a0` (draw pass 3, called every frame
from the cockpit frame function @181877). Offsets below are relative to renderer (R) or cockpit state S = `*(R+0x20c0)`. S is the
global `0x684760` (`FUN_0045a900`).

### Keys and objects
* `[LIGHT000]..[LIGHT008]` (loop, `FUN_005287d0`): `Active` (default 0), `Left/Top/Right/Bottom/OffsetX/OffsetY` (default 1;
  an empty value reads as 0), `Blink` (default 0). Object = 0x38 bytes at R+0x2274+0x38*i: +4 OffsetX, +8 OffsetY,
  +0xc w = Right-Left, +0x10 h = Bottom-Top, +0x14 Active, +0x18 Blink, +0x1c blink phase, +0x20 blink timer, +0x24 Left, +0x28 Top,
  +0x2c last value, +0x30 re-blit flag, +0x34 slice. vtable `0x60c1e8` = {draw `FUN_005288c0`, source rect `0x528850`}.
* `[SLIGHT000]..[SLIGHT003]`: same keys and the same class, but `Blink` is not read (forced to 0). Objects at R+0x246c+0x38*j.
* `[LIGHT009]` is read separately into an animated object at R+0x254c (vtable `0x60c200` = {draw `FUN_00528d10`, rect `0x528e50`}).
  It has no `Blink`; it reads `AnimTime` (default 2000) and `AnimFrames` (default 2), and step time = AnimTime / AnimFrames (integer,
  `FUN_00528e90`).
* `[LIGHTSON]`: `FileName`, `Width`/`Height` (surface size, defaults 141x55, `FUN_00523960`), `NightRScale/NightGScale/NightBScale`
  (defaults **0/2/4**, packed at R+0x2590). The surface (R+0x600) has colour key cyan RGB(0,255,255), like the MFDs.
* **`[LIGHTSOFF]` and `[SLIGHTS]` (`StateLights.bmp`) are never read.** The strings are not in the exe. The SLIGHTs use the
  `[LIGHTSON]` bitmap, which is why the missing `StateLights.bmp` does not matter.

### Source frames: the "off" look is in the light bitmap, not the panel
The source rect for value/frame v is `x = Left..Left+w`, `y = Top + v*h .. Top + (v+1)*h` (`0x528850`). The frames are stacked
vertically under `Top`:
* LIGHT000..008: frame 0 = unlit art (a dim or dark lamp with its label), frame 1 = lit art. If `Blink` = 1, the frame is the blink
  phase instead of the value (see below).
* SLIGHT000..003: three frames, where frame = state 0/1/2 (any other value is treated as 0).
* LIGHT009 (gear handle): AnimFrames frames, where frame 0 = handle up and the last frame = handle down.
At load (`FUN_00528660`), frame 0 of every active light is stamped into the panel slices. **So "off" = frame 0 of the lights bitmap
pasted over the panel, not the bare panel art.** (Cyan pixels in it stay transparent.)

### Drawing (`FUN_005288c0`)
* If `Active` = 0, the light is never drawn or stamped. (But the click hit-test `FUN_00521790` ignores `Active`, so the rect of an
  inactive light is still clickable.)
* When the value changes, or when the force flag R+0x2fc is set, the light is redrawn. `FUN_005289e0` BltFasts the source rect
  (src colour key) into the 320-px panel slice: slice = OffsetX/320, x = OffsetX%320, y = OffsetY - slice top (the
  MaskOffsetY table at R+0x20cc). It is split over two slices when it crosses a 320 boundary, exactly as for the MFDs. Then
  `FUN_00528c20` also blits it straight to the back buffer at screen `(OffsetX - pan(R+0x564) - 640, OffsetY + MainOffsetY + vpan(R+0x568))`.
  If R+0xc ≠ 0 (UNCERTAIN: flip/back-buffer mode), the next frame re-blits to the screen once more (+0x30).
  Unchanged lights cost nothing: their current frame is already baked into the panel slices.
* **Blink** (`Blink` = 1): while the stored value (+0x2c) ≠ 0, the frame time dt (ms, `timeGetTime` delta R+0x574 - `DAT_0083dfcc`)
  is added to +0x20. When the total exceeds **300 ms**, it resets and the phase +0x1c toggles, so the light alternates dark and lit
  every 300 ms (a period of about 600 ms, quantised to frames). When the light turns on it starts at phase 0 (dark). Value 0 resets
  the phase to 0. In every cockpit only LIGHT001/LIGHT002 (engine fire) have `Blink = 1`.
* **Gear handle animation** (`FUN_00528d10`): when the value changes, a global anim flag is set (`DAT_0083dfc8`, so there is one
  animation at a time). The frame starts at 0 (going down) or at AnimFrames-1 (going up). Each time the accumulated dt exceeds the
  step time, it moves by one frame toward AnimFrames-1 (down) or toward 0 (up). F-15 `AnimTime = 0` gives a step time of 0, so it
  moves one frame per rendered frame.
* Order in `FUN_005283a0`: LIGHT000..008, then LIGHT009, then the SLIGHTs. If the handle moved to down (value 1), the SLIGHTs are
  force-redrawn. If any SLIGHT redrew while the handle is up, the handle is redrawn with force. These rects overlap on the F-15
  (handle 637..695 x 227..274 over the wheel lamps).
* **Night** (`FUN_0052df40`, applied once when the bitmap is loaded): hour = t·0.001/60/60, with t = the time-of-day argument
  of `FUN_0051ea20` (`FUN_004d8eb0`: the clock `FUN_004cf8c0` in seconds × 1000, ms since midnight). It is night if **20 ≤ hour < 24
  or 0 ≤ hour ≤ 5.0** on the fractional hour (05:30 is not night). Three callers: the panel, the lights bitmap, the HUD glass;
  nothing else in the cockpit (HUD symbology, MFDs) changes at night. At night every non-colour-key pixel of the 16-bit surface is darkened per channel: **R >>= NightRScale,
  G >>= NightGScale, B >>= NightBScale** (the values are shift counts, `FUN_0052ddc0`). The panel (`[PANEL] Night*Scale`, R+0x20f0)
  and the HUD glass bitmap (`FUN_00528eb0`) are darkened the same way with the panel values. Note: the surface-lost reload paths
  call `FUN_0051ea20(cockpit, 0)`, i.e. hour 0, which is night (UNCERTAIN quirk).

### What drives each light (all aircraft)
S+0x520+4i = indicator i of the player controller (`ctl+0x4ec+4i`, flushed by `FUN_0045b4d0` -> `FUN_00445e90`, 10 dwords).
S+0x548+4j = the "special indicator" j (`ctl+0x548+4j`, flushed by `FUN_0045b150` -> `FUN_00445e60`, 4 dwords).
Indicators are set with `FUN_0045b3d0(i, duration)` (duration 0.0 = stays on) and cleared with `FUN_0045b460(i)`.

| Light | ini comment | State | On when (code) | Off when |
|---|---|---|---|---|
| LIGHT000 | master | S+0x520 | any damage event: end of the damage handler `FUN_0044d760` -> `FUN_0045b4b0` (plus warning sound 0x2c006000/0x18001000) | GEV 0x69 = clicking the light (`FUN_00521800` case 0xf) |
| LIGHT001 | left eng | S+0x524 | damage 0x10 "Engine on fire"/"Left engine on fire" | GEV 0x49 fire extinguisher (clears 1 and 2, @44b506) |
| LIGHT002 | right eng | S+0x528 | damage 0x11 (right engine fire) | GEV 0x49 |
| LIGHT003 | ai | S+0x52c | RWR (docs/rwr.md §3): an **active** RWR entry (a lock or a launch) whose emitter class (unit+0x30)+8 is **not** in {5,8,9,10,0x10}; WRN_NEW_GUY 0x18002000 when it comes on (`FUN_00450bc0`, `FUN_0044deb0`; ≤ once per 1 s) | no such entry (every frame), the list empty, RWR damage 14 (cleared) |
| LIGHT004 | sam | S+0x530 | same, but the emitter class is in {5,8,9,10,0x10} (ground) | same |
| LIGHT005 | air brake | S+0x534 | GEV 0x11 TGL_BRAKES toggles it (speed brakes out) | toggle |
| LIGHT006 | radar jammer (ecm) | S+0x538 | GEV 0x46 TGLECM when ECM is fitted (ctl[0x6e]) | toggle off; ECM damage (1) |
| LIGHT007 | landing hook | S+0x53c | **never set** (no call with i = 7); `Active = 0` in every cockpit | - |
| LIGHT008 | ap | S+0x540 | autopilot mode ctl+0x974 ≠ 0: GEV 0x10 cycles 0->1 (on)->2->0 (off); **on at an airborne start** (@4483f5) | stick deflection beyond ±0x33 (GEV 1), mode 2->0, on-ground press, AP damage (6) |
| LIGHT009 | gear handle | S+0x544 | handle down, `ind[9]` (flight-model.md §12) | handle up |
| SLIGHT000 | wheels mid | S+0x548 | gear leg 0: 0 up, 1 transit, 2 down & locked | - |
| SLIGHT001 | wheels left | S+0x54c | gear leg 1 | - |
| SLIGHT002 | wheels right | S+0x550 | gear leg 2 | - |
| SLIGHT003 | flaps | S+0x554 | flaps state 0/1/2 (GEV 0xc; player: 0->1->2 with a 2.0 s step, 2->1->0 on retract) | - |

Clicking lights (hit-test `FUN_00520db0` via `FUN_00521440`, only in view modes 1/0x12/0x16; actions `FUN_00521800`): LIGHT009 -> GEV 0xe gear, SLIGHT003 -> 0xc flaps,
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
* When the flush runs (`FUN_0045b150`) with legs 1 and 2 both 0, leg 0 is forced to 0.

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

### `[TEXTMESSAGE]` (`FUN_0052e820`), `[CHAFF]`/`[FLARE]` (`FUN_0052eab0`)
* Keys and defaults: `OffsetX1` 1072, `OffsetY1` 21, `OffsetX2` 1072, `OffsetY2` 36, `LengthChar` 20 (R+0x26f4..0x2704);
  `[CHAFF]`/`[FLARE]` `OffX`/`OffY` default 36/36 (R+0x2708..0x2714).
* Text = the NUL-terminated string at S+0x10a4. Every frame `FUN_00448b20` copies it with `FUN_00446590` =
  `strncpy(S+0x10a4, *(char**)(ctl+0x64), 20)`, so at most 20 chars. What ctl+0x64 points to was not traced (UNCERTAIN).
* Pass 2 erases two boxes of `LengthChar*5` x 9 px at (X1,Y1) and (X2,Y2) by re-blitting the panel slice.
* Pass 4 uses GDI `TextOutA`, font R+0x57c (Arial h10 w5 weight 100), TA_LEFT|TA_TOP, transparent background, at screen
  (X - pan - 640, Y + MainOffsetY + vpan). The colour is not set by the routine; the caller last set 0x00ff00 green before the MFD
  pass (UNCERTAIN whether the MFD pass changes it).
* **Two lines**: if len < LengthChar, one line at (X1,Y1). Otherwise the break is at the last space at or before index LengthChar-1
  (line 1 keeps that space), and the rest goes at (X2,Y2), truncated to LengthChar chars. The search has no lower bound, so a string
  without a space would run backwards (latent bug). With 20 chars at most, only the F-16 (`LengthChar = 19`) can ever wrap.
* Chaff/flare: `sprintf("%03d")` of S+0x4c4 (chaff) and S+0x4e0 (flare), drawn with the same font, colour **0xb3ffff = RGB(255,255,179)**
  (pale yellow), top-left at `OffX,OffY` (screen transform as above). These addresses are the count fields of stores stations 10 and 11
  in the stores array S+0x3a8 (0x1c stride, `mfd.md` §3), an inference from the layout. The erase box is `TEXTMESSAGE LengthChar*5`
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
`NUM` (default 16) and `OFFSET00..` (default PanelHeight) are read into ini[0xb..] (R+0x20f4..). The file comment is "16 points
describing an horizon of the panel" at panel x = 0,120,…,1800, and the values are the panel's top-edge row (e.g. F-16 352 at the
edges, 4 at the centre). **No reader of R+0x20f4.. was found in the exe** (UNCERTAIN: probably unused or read via an unfound alias).

### Open
* ctl+0x64 text source; exact GEV key names for 0x46/0x49/0x69; emitter class ids behind AI vs SAM; R+0xc double-blit flag.
