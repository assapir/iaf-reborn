# Cockpit MFDs (Jane's IAF, `iafjets.exe`)

How the original game draws and drives the cockpit's multi-function displays (MFDs): geometry, text and colours,
every page, the full-screen weapon MFD, the radar MAP picture, the keys, a short HUD note and the per-aircraft cockpit
table. Use it to re-implement or check `game/cockpit/mfd.gd`, `game/cockpit/fs_mfd.gd`
and the EO / HARM sensors in `crates/iaf-avionics`.

Key facts:
- Each MFD is a 132 × 132 px surface, blitted into the panel bitmap; MFD index **0 = Left, 1 = Right, 2 = Middle**.
- Pages: 0 NAV, 1 stores, 2 radar, 3 TSD, 4 damage, 5 TV, 6 FLIR, 7 RWR, 8 MENU, 9 ADI, 10 HARM (§3).
- MFD text uses a 5 × 5 sprite font; `mfd.fnt` is never loaded (§2).
- The HUD colour starts at index 0 (the darkest green) every launch; key H cycles 11 colours (§2).

Terms used here:

| Term | Meaning |
|---|---|
| MFD | Multi-function display: a square cockpit screen with pages chosen by buttons |
| OSB | Option select button: one of the 20 bezel buttons around an MFD |
| HUD | Head-up display |
| TSD | Tactical situation display (page 3, the "TACT" map) |
| RWR | Radar warning receiver (page 7 or a panel dial; docs/rwr.md) |
| ADI | Attitude director indicator (the artificial horizon, page 9) |
| EO | Electro-optical: the TV and FLIR camera pictures |
| FLIR | Forward-looking infrared (the targeting pod, page 6) |
| HARM | The AGM-88 anti-radiation missile and its sensor page (page 10) |
| SMS | Stores management system (the stores page 1) |
| STT, BORE, LRS, TWS, ACM | Radar air-to-air modes: single-target track, boresight, long-range search, track-while-scan, air combat mode |
| GMT, MAP | Radar air-to-ground modes: ground moving target, ground map |
| DLZ | Dynamic launch zone: a weapon's min / max launch range (docs/weapons.md §11) |
| MRM, SRM | Medium- and short-range (air-to-air) missiles |
| PPI | Plan position indicator: a fan-shaped, heading-up radar picture |
| ETA | Estimated time of arrival |
| FoV | Field of view |
| renderer | The cockpit render object (ctor `FUN_0051e500`, init `FUN_0051ea20`) |
| state, S | The per-frame cockpit state at `*(renderer+0x20c0)` |
| ctl | The player controller object |
| mcp | One of the two EO camera objects (TV, FLIR) owned by the controller |

Sources and conventions:
- Addresses are `IAFJets.exe` **v1.1** (the reference version). [v1.1.md](v1.1.md) maps them to v1.0 and lists what
  the patch changed. Addresses are function entry points.
- The facts come from the Ghidra dump (`assets/ghidra_v11/iafjets.c`) plus objdump / `.rdata` reads. Source files
  named in asserts: `CockpitRender\CockpitMfdHandle.cpp`, `CockpitMfdRadar.cpp`, `CockpitMfdHarm.cpp`.
- **UNCERTAIN** marks anything not read directly from code.
- The renderer's copy of `cockpit.ibx` lives at renderer+0x20c8 (ini index k at 0x20c8+4k, parsed in `FUN_005228a0`).
- The state holds the ownship X, Y, Z floats at +0, +4, +8 and pitch / roll / heading in radians at +0xc / +0x10 /
  +0x14.
- Colours are Windows COLORREF `0x00BBGGRR` unless written RGB().

## 1. Geometry and compositing

- Each MFD is a **132 x 132** px DirectDraw surface (renderer+0x5d8, `FUN_0051ea20`), colour key **cyan
  RGB(0,255,255)** (0xffff00). `mfds.bmp` is loaded into a 264x924 surface (renderer+0x5f8, `FUN_005295f0`), same key;
  `rwrsymb.bmp` into a 10x300 surface (+0x5fc).
- Panel: the `[PANEL] FileName` bitmap (1920 x PanelHeight; every cockpit is 1920 wide, height 352 except mig23 360 and
  phantom 374) is cut into six 320-px-wide slices (+0x5b8..+0x5cc); slice i starts at panel row
  {MaskOffsetY1, MaskOffsetY2, 0, 0, MaskOffsetY2, MaskOffsetY1}[i] (F-16: {288,93,0,0,93,288}; per-plane values in §7).
- **Placement** (`FUN_0052ae30`): the finished MFD surface is BltFast'ed (src colour key) *into the panel slice*
  at panel pixel (OffsetX, OffsetY) from `[MFD]` (slice = OffsetX/320, x = OffsetX%320, y = OffsetY − slice top; split
  over two slices if it crosses 320). The rounded cyan tile corners therefore show the panel.
  F-16: Left occupies panel [722,854)x[146,278), Right [1083,1215)x[147,279). Middle inactive.
- **Screen position** of an MFD (`FUN_0052abb0`): `x1 = OffsetX − pan(+0x564) − 640`, `y1 = OffsetY + MainOffsetY(190)
  + vpan(+0x568)`. With pans 0: Left (82,336), Right (443,337) on the 640x480 screen. vpan is clamped ≥
  480 − MainOffsetY − PanelHeight = −62 (`FUN_0051f610`); its straight-ahead value comes from the view — UNCERTAIN.
- **Draw passes** (`FUN_0052abb0(pass, hdc, idx)`):
  - 0: compose the 132x132 surface (`FUN_005296d0`): background tile + sprite-font label + range sprite; only when
    the page/mode changed (or forced by +0x2fc). Then blit into the panel (`FUN_0052ae30`).
  - 1: direct back-buffer pixels (radar MAP background only).
  - 2: click handling / hit tests (`FUN_0052a960`).
  - 3: sprite overlays (text, symbols) blitted straight to the back buffer at (x1,y1)+offset.
  - 4: GDI vectors on the back-buffer DC; clip rect (x1,y1)-(x1+131,y1+131); default pen +0x58c.
- **Bezel buttons (OSBs)** — the panel art shows them; the code only hit-tests them. Hit test `FUN_00520db0`, table
  `DAT_0065c758`. Strips relative to the MFD origin: top x22..107,y−16..0; bottom x22..107,y131..146; left
  x−16..−1,y21..107; right x132..148,y21..107. Button = coord/20 + base, only if coord%20 < 8, i.e. 8-px buttons at
  20,40,60,80,100. Ids: top 1–5, bottom 6–10, left 11–15 (0xb–0xf), right 16–20 (0x10–0x14). Actions `FUN_005219e0`.
  Clicking inside the display area (+10..+122) makes that MFD own the mouse cursor (`FUN_00521700`).
- **Button 6 (bottom-left, under "MENU") on every page** posts event 0x5b(value 8, mfd) → MENU page.
- Full-screen weapon MFD (key Z, v1.1; S+0x1088 = 0xb): replaces the whole cockpit with `fsmfd/FsMfd.bmp` and the TV /
  FLIR picture in (128,49)-(513,431) — §3 "Full-screen weapon MFD".

### mfds.bmp (264x924, 24-bit) — source rectangles (table at `0x65d068`, RECT l,t,r,b)

| Rect | Content | Used for |
|---|---|---|
| (0,0,132,132) | blank frame, "MENU" | NAV, damage, MENU, HARM, ADI, TV-inactive, pages 11–13 |
| (132,0,264,132) | RWR: circle, ticks, "RWR" | RWR page 7 |
| (0,132,132,264) | aircraft outline, ×MRM ×SRM, GUN box | stores page 1 |
| (132,132,264,264) | circle + "Debug" | unused (UNCERTAIN) |
| (0,264,132,396) | A-A B-scope: corner brackets, edge ticks, arrows | radar OFF/STBY/STT/BORE/LRS/TWS/ACM |
| (132,264,264,396) | "LAS OPR" + X | not referenced by the renderer (UNCERTAIN) |
| (0,396,132,528) | "TACT", SAM/WPT/MAP/SCL labels, ownship | TSD page 3 |
| (132,396,264,528) | "TWS OPR" + X | not referenced (UNCERTAIN) |
| (0,528,132,660) | blank | not referenced |
| (132,528,264,660) | "MAP OPR", cyan (transparent) fan + grid | radar MAP |
| (0,660,132,792) | "FLIR", cyan video box, reticle, "NM" | FLIR page 6 |
| (132,660,264,792) | "GMT OPR" fan grid | radar GMT |
| (0,792,132,924) | "TV", cyan video box, cross | TV page 5 when active |

Misc sprites in (132..264, 792..924):
- (132,792)-(164,824) 32x32 "sun" circle → surface +0x5f4, recoloured to the HUD colour; a HUD sprite (`FUN_00530040`).
- (164,792,172,796)/(164,796,172,800): upper/lower halves of the green diamond = list scroll arrows (NAV page).
- (132,840)-(217,845) digits+symbols and (132,850)-(262,855) A–Z: the 5x5 sprite font (below).
- (132+8i,845)-(140+8i,850), i=0..5: range numbers 5/10/20/40/80/160 (table `0x65d610`).
- (132+6i,855)-(138+6i,862), i=0..3: 6x7 compass letters S,E,N,W.

## 2. Text and colours

- **`mfd.fnt` is never referenced by `iafjets.exe`**: the exe has no such string. It loads only `%s\Fnt\hud.fnt` and
  `key.fnt`, and a menu / log object (`FUN_005190xx`) loads those. mfd.fnt itself: face "MFD", 11 px tall, ascent 9,
  proportional (max 9 px). Treat it as unused.
- **MFD text = 5x5 sprite font** built in `FUN_0051ea20` into two 224x5 surfaces (+0x5d0 green as drawn, +0x5d4
  recoloured to the HUD colour; +0x274c selects which). Letter row → x=0..129, digit row → x=130..214. Char→x table
  `FUN_00525890`: 'A'–'Z' and 'a'–'z' → 5·(c−'A'); '0'–'9' → 130+5·d; blank 180; '.' 185; ':' 190; '+' 195; '-' 200;
  '%' 205; anything else → 180 (blank). Advance 5 px, no gap (glyphs contain their own spacing).
  `FUN_00525a30(x,y,str,n)` left-aligned; `FUN_00525920(x,y,…)` right-aligned (string ends at x). Page label is
  always at **(17,3)**.
- GDI objects (ctor `FUN_0051e500`): pens +0x58c 1px 0x00ff00 (MFD default, RGB(0,255,0)); +0x5a4 dashed 0x8000;
  +0x590 red 0xff; +0x594 blue 0xff0000; +0x598 0x95ffff; +0x59c white; +0x5a0 black; +0x27a0 0x8000; +0x27a4 0xff00;
  +0x27a8 0x360080 (purple); +0x27ac 0x2400ff (red). Fonts: Arial h10 w5 wt100 (+0x57c), Arial h12 w4 (+0x580),
  ANSI_VAR_FONT (+0x578). HUD colour table +0x2864 indexed by +0x2890 (`FUN_00520890` rebuilds pens +0x584/+0x588):
  0x2400,0x3400,0x5400,0x6c00,0x8800,0xa400,0xe400,0xfc00,0xf0f4f8,0xf8,0xbcf8 (greens dark→bright, white, red, amber).
- Tile art colours: bright green RGB(0,255,0), dim green RGB(0,132,0)/(0,128,0), black background.
- **HUD colour index — source, default, cycling** (objdump-verified):
  - Chain: cockpit state (global ptr `0x82f544`, = renderer+0x20c0, set by `FUN_0051f610` from `0x4d96e3`)
    field **+0x10a0** → each frame `0x51f961` compares with renderer+0x16b0; if different, clamps to ≤10 and calls
    `FUN_00520890(idx)` (renderer+0x2890 = idx; recreates pens +0x584 (1px) / +0x588 (2px) with `table[idx]`;
    recolours the 5x5 font copy +0x5d4 and sun sprite +0x5f4 via `FUN_0052d680`, which packs the COLORREF to RGB565).
    Renderer ctor starts +0x2890 = 0 (`0x51e68d`, ebp = 0).
  - Only setter of state+0x10a0 is `0x4467a0` (`this+0x10a0 = arg`; the other +0x1098 writes at 0x40396f/0x41d3bb/
    0x41de7c are other classes). Two callers, both with `ecx = [0x82f544]` and the value of the flight/sim object's
    field **+0x74**:
    1. `0x448019` in `FUN_00447e70` (virtual, vtable slot at 0x600b50 — flight start/load): pushes `this+0x74`.
    2. `0x44d22b`, event dispatcher `0x44a2e4` (byte table `0x44d390` maps event 0x7b → case 0x3e → `0x44d20c`).
  - `this+0x74` is zeroed in the ctor (`0x447900`) then set from the static **`0x82f4c4`** (`0x447b7f`; also in
    `FUN_00448120` at `0x448133`, the sibling virtual at 0x600b54). `0x82f4c4` lies in .data's uninitialised tail
    (raw data ends 0x6847b8) and has no load-time initialiser and no other writer (only 3 references: 2 reads + the key
    handler) → **starts at 0 every time the program is launched**. It is one global value for all aircraft. Nothing on
    the path reads prefs, ini, registry or the time of day.
  - **Key H (event 0x7b)**: `idx = (idx + 1) % 11`, stored back to `this+0x74` **and** to `0x82f4c4`, then setter.
    Order 0→1→…→10→0: 8 greens dark→bright (0x24,0x34,0x54,0x6c,0x88,0xa4,0xe4,0xfc in G), 8 = near-white
    RGB(248,244,240), 9 = red RGB(248,0,0), 10 = amber RGB(248,188,0). The choice persists to later flights in the same
    session (via `0x82f4c4`) but is never saved to disk.
  - **Default = index 0 = COLORREF 0x002400 = RGB(0,36,0)** (darkest green) for HUD symbology, HUD/MFD sprite text and
    the in-flight subtitle console text, at the first flight of each run. The value is certain from the code. That
    it really looks this dark on screen is UNCERTAIN: a later brightening or additive blend was not traced.

## 3. Pages (state+0x504+idx·4; dispatch `FUN_005296d0`, passes 3/4 in `FUN_0052abb0`)

Default pages (`FUN_00448120`, all aircraft; rule and per-plane result in §7): Left = radar (2) always; Right/Middle depend on
the MFD count and `[PANELRWR] Active`. F-16: Left = radar, Right = TSD (3).

| Id | Page | Tile | Label | Code |
|---|---|---|---|---|
| 0 | NAV (waypoint list) | blank | – | `FUN_0052b410`, `FUN_0052c450` |
| 1 | stores/SMS | (0,132) | – | `FUN_0052c740` |
| 2 | radar | per sub-mode | mode name | `FUN_005333d0` + helpers |
| 3 | TSD ("TACT") | (0,396) | – | `FUN_00531a50` |
| 4 | damage | blank | – | `FUN_0052bc00` |
| 5 | TV / EO weapon | (0,792) or blank | – | `FUN_005369e0` |
| 6 | FLIR | (0,660) | – | `FUN_00536c10` |
| 7 | RWR | (132,0) | – | `FUN_00531290` → `FUN_00531470` |
| 8 | MENU | blank | – | `FUN_0052b800` |
| 9 | ADI | blank | – | `FUN_00526fe0` (only on cockpits with [HORIZON] OnMfd: F-4-2000, F-15, Lavi; §7): horizon disc + speed / heading / height, docs/cockpit.md "Attitude indicators" |
| 10 | HARM | blank | "harm" | `FUN_005358b0` |
| 11/12/13 | placeholder | blank | "inventory"/"lt"/"comm" | label only |

**MENU (8)** (`FUN_0052b800`) — left labels at x=5, right labels right-aligned to x=124; a black colour-fill
(14,124)–(33,129) erases the tile's "MENU". Labels: "FLIR" (5,22) only if MenuFlirOn (ini+0x226c) and the FLIR pod
(state+0x610); "NAV" (124,42); "stores" (5,62); "damage" (124,62); "rwr" (5,82) only if PANELRWR inactive (+0x21e4)
→ hidden on F-16; "tactical" (124,82); "adi" (124,102) only if [HORIZON] OnMfd (+0x217c) → hidden on F-16; "radar"
(5,102). Buttons (`FUN_005219e0` case 8, event 0x5b(page, mfd)): 0xb "FLIR"→6 (same gates); 0xd→1; 0xe→7; 0xf→2;
0x11→0; 0x12→4; 0x13→3; 0x14→9.

**NAV (0)** (`FUN_0052b410`, `FUN_0052c450`) — "ETA   :" at (72,124). 3 rows at y=42,62,82 from scroll index
+0x27b0: "%1d" waypoint number right-aligned at x=8; name (state+0x88+i·0x2c, ≤12 chars) at (12,y+1). Pass 3 (sprite
font) per row at y = 43 + 20·row: "% 3dM" = ftol(distance·(1/1853)) NM at x 77 and "%03d" = ftol(bearing°) (+360 if
negative) at x 102, where the nav update `FUN_004459f0` fills each waypoint record (state+0x7c + 0x2c·i) with the
bearing atan2(dx, dy) from the ownship (+0x9c, rad, true north) and the 3-D distance (+0xa0, m). ETA "%02d %02d" =
hours, minutes of the double state+0x318 (h = ftol(t/3600), m = ftol((t − 3600h)/60)) right-aligned at (117,124).
state+0x318 is the time of day at arrival (`FUN_00452e60`, the nav object's state-5 handler; 0x4530a0 is inside it):
- ETA = now (clock+0x38 + clock+0x18) + the horizontal distance to the current waypoint / the horizontal ground speed.
- The travel time is 1000 s when stopped, and the ETA is at most now + 36000 s (0x600e40).
- The ETA keeps counting past 24 h (no wrap).
- Port: hud.gd `nav_cues` `eta`, the time of day = mission start 0x460 + the mission clock (UNCERTAIN: that
  clock+0x18 is 0x460).
Scroll arrows at (1,22)/(1,107); buttons 0xb/0xf scroll (clamped 0..count). Pass 4: the current waypoint (state+0x320,
clamped to the count) when visible: box (1, 20·(row+2))–(8, 20·(row+2)+8). After every page (`FUN_005296d0`) a new
current waypoint scrolls the list to keep it visible: above the rows it becomes the top row, below them the bottom row
(scroll = cur − 2). Port: `mfd.gd` `_process`, on a change of the current waypoint (UNCERTAIN: the trigger field,
renderer +0x930).

**Stores (1)** — stations = 0x1c-byte {type,count,name[20]} at state+0x3a8. Count/name positions: st0 (4,62)/(4,72),
st1 (4,42)/(4,52), st2 (4,22)/(4,32), st3 (24,3)/(17,12), st4 (64,3)/(57,12), st5 (104,3)/(97,12), st6..8 right-
aligned to 128 at y 22/32, 42/52, 62/72. MRM total (types 600/0x262) right-aligned (59,53); SRM (0x23a/0x244) (59,63).
GDI: "%dQnt" (1,94), "int%d" right-aligned (131,94), gun rounds "%03d" (68,85), "Fuel : %5dLB" (55,124). Selected
station (+0x4f8) boxed 15x8 (gun: 36x10 at (48,82)). Buttons: station select (0xd,0xc,0xb,1,3,5,0x10,0x11,0x12 →
stations 0..8, event 0x4c), 0xe quantity +1 / 0xf −1 (0x4a(1) / (0)), 0x13 interval +10 / 0x14 −10 (0x4b(1) / (0));
quantity 1..14, interval 10..200, defaults 2 / 10 (weapons.md §9).

**Damage (4)** — "NAME GO"/"NAME NOGO" rows (flags → rows: docs/damage.md §5.2); left x=12: ENG (y10), [ENG R y19
twin only], FUEL 43, AILN 52, FLTC 61,
FLAP 70, GEAR 79, HUD 88, BRAK 97; right x=72: AB 10, [AB R 19], INS 34, RDR 43, RWR 52, WPNS 61, GUN 70, ECM 79,
A/P 88, ELCT 97, GNRT 106. Redrawn when state+0x558.. flags change.

### Radar (2) — sub-mode state+0xa04

| Value | Mode | Tile | Label at (17,3) |
|---|---|---|---|
| 0/1 | OFF / STBY | (0,264) | "OFF"/"STBY" |
| 2 | STT | (0,264) | "STT" |
| 3 | BORE | (0,264) | "BORE" |
| 4 | LRS | (0,264) | "LRS" |
| 5 | TWS | (0,264) | "TWS" |
| 6 | ACM | (0,264) | "ACM" |
| 7 | GMT | (132,660) | (baked in tile) |
| 8 | MAP | (132,528) | (baked in tile) |

- Range sprite at (1,33) (modes ≥ 2 and TSD; `FUN_00533990`: 5 / 10 / 20 / 40 / 80 / 160 NM → sprites 0..5, rects
  `0x65d610`). Range R (NM) = {5,10,20,40,80,160}[state+0xa08 − 1] (`FUN_00522190`).
- Horizon bars (`FUN_00533620`): polylines (−31,4)(−31,0)(−5,0) and mirror, centre (66,66), rotated by roll, shifted
  1 px/deg pitch, pitch clamped ±40 (blink every 300 ms beyond).
- Antenna carets (`FUN_00533500`): v = clamp(ftol(val·106),0,106); azimuth: x=13+v, y117..120 + bar x11+v..16+v at
  y117 (val state+0xa0c); elevation: y=13+v, x11..14 + bar at x14 (state+0xa10).
- Steer triangle (`FUN_005338b0`, called by STT, LRS, TWS, BORE / ACM) to the steerpoint state+0x70 (the current
  waypoint: the nav update `FUN_004459f0` param 8, next to the waypoint list and index): d = ⌊distance / (R·16.5446)⌋,
  b = ⌊atan2(dx, dy)°⌋ − ⌊heading°⌋ (+0x2728, +360 if negative) wrapped to ±180; only when −60 < b < 60: base
  (x−3, 125−d)–(x+4, 125−d), sides (x−3, 124−d)–(x, 119−d)–(x+4, 126−d) at x = 66 + b. The same triangle shape (about
  (x, y): (x−3, y+3)–(x+4, y+3), (x−3, y+2)–(x, y−3)–(x+4, y+4)) marks the steerpoint on the GMT and MAP pages.
- **B-scope blip**: x = 66 + (az + state+0xa14)·112/state+0xa24; y = 115 − range_m/(R·16.5446) (16.5446 = 1853/112,
  i.e. R NM = 112 px); drawn only inside 8<x,y<124. Contacts (≤15, state+0x640.., stride 0x40): X +0x640, Y +0x644,
  altitude +0x648 (m; shown ×0.0032808 = kft), locked +0x658, tracked +0x65c, id +0x664, speed +0x668, aspect +0x66c
  (rad), az +0x670, range +0x678, Mach +0x67c.
- **Aspect stub** (TWS / STT): bin = ⌊aspect°⌋ % 360 (truncated), wrapped at ±210, / 45 (truncated) → −4..4; a line
  from 2 px out to 6 px: 0 up, 1 up-right, 2 right, 3 down-right, ±4 down, −3 down-left, −2 left, −1 up-left.
- BORE/ACM (`FUN_005352c0`): 3x3 box with the \ diagonal (−1,−1)→(1,1) per contact.
- LRS (`FUN_00534840`): 5x5 box + inner 3x3 with the \ diagonal; cursor = two vertical bars at mouse x±4, y−5..y+5;
  a press on a blip (button held, +0x27d8) → event 0x2a (lock, id).
- TWS (`FUN_00534b20`): unselected 5x5 box, the selected contact a ~7 px filled disc; every contact its aspect stub;
  the LRS cursor bars. A press (+0x27d8) on a contact (±4 px) other than the selected one → event 0x32 (select it,
  unlocked: `FUN_004add20` → the mode's vt+0x38(id, 0) → `FUN_004b05a0`); a double-click (+0x27e0) → 0x2a (lock →
  STT). While the mouse is over a contact: "%02d" altitude (kft) right-aligned at (mouse+17, mouse−3) and "%02d"
  Mach × 10 right-aligned at (mouse−4, mouse−3); the manual (EN 4.17) names both. The selected contact in the window
  also gets the STT block of `FUN_00533db0` (the scale, caret, DLZ and text below).
- STT (`FUN_00534160`): the first locked contact only: disc + aspect stub; no antenna carets: the carets sit at the
  target, x = clamp(tx − 13, 0, 106) + 13, y = clamp(ty − 13, 0, 106) + 13 (the antenna carets' shapes); "%02d"
  altitude right-aligned at (tx+15, ty−3), "%02d" Mach × 10 at (tx−3, ty−3), each while its anchor (tx+10 / tx−8) is
  in the window. `FUN_00533db0` (text right-aligned, `FUN_00525920`): range scale line x=121 y10..122 with three
  black ticks at y 39 / 65 / 91 (x 117..121), the selected store's DLZ max / min (S+0x348 / +0x350, docs/weapons.md
  §11.2) as ticks x 121..117 at y = 122 − ⌊v·112/(R·1853)⌋ while 0 < 112 − ⌊v·k⌋ < 112; n = 105 − ⌊r·112/(R·1853)⌋,
  while 0 < n < 112 (no clamping) a ">" caret with its tip at (116, 10+n) and arms to (113, 10+n±3) and the closure
  "%3dK" ending at x 111, y = n+8 (the caret's row − 2); "%3dK" speed (≥ 0) ending at x 86, aspect "%2dL"/"%2dR"
  ending at x 62 (y 3).
- GMT (`FUN_00535400`): heading-up PPI, origin (66,109), R·1853/56 m/px; per contact a ±10 cross when locked, then
  the 3x3 box (always); the steerpoint triangle; the horizon bars and the antenna carets; while the MFD owns the
  cursor: the cross-hair to the edges with a 3-px gap and 5-px ticks at ±31, and a double-click (+0x27e0, the
  WM_LBUTTONDBLCLK handler `FUN_004dc8a0` → `FUN_00522120`) within ±4 px of an unlocked contact sends 0x2a (lock it).
- MAP (`FUN_00535ea0`, switch on the pass): 0 loads isr.bmp (`FUN_0053ae00(…, 1)`: green palette); 1 the picture
  (§4); 2 OSB 3 (top middle) → event 0x30 (NORM ↔ EXP, latched per press); 3 label "NORM" / "EXP" (0x65d744 /
  0x65d740, state+0xa18) at (60,3); 4 the symbols, clipped to the window (15,15)–(116,109) (so the antenna carets
  never show): the cross-hair (ticks only in NORM), per contact a ±10 cross when locked then the 3x3 box with the
  \ diagonal; the designation cross at the last clicked point when the radar has a designated point (state+0xa1c)
  and no contact is locked; the steerpoint triangle; the horizon bars. Symbols at R·19.7128 m/px about (66,109)
  (NORM: the ownship, current heading) or (66,66) (EXP: the latched point and heading). A click on an unlocked
  contact (±4 px) → 0x2a and that contact's X / Y become the clicked point; else → 0x2f with the world point under
  the cursor (angle atan2(dx, −dy)·R·19.71 + heading about the centre), which becomes the clicked point.

### TSD (3) — `FUN_00531a50`
- Map = **`Emf\map.emf`** (the radar MAP uses isr.bmp, §4) (load `FUN_0053a630`, draw `FUN_00539f20`, clip (10,10)-(122,122)). 20
  POLYGON16 records, brushes 0xc7c7c8, 0x878889, 0x5b2222. EMF units: `u = ftol(ftol((X+166850)/819200·12601)·1.0071394)`,
  `v = ftol(ftol((1043816−Y)/1064960·16383)·1.0071394)` (floats `0x60c3e8..0x60c400`; ×1.0071394 meaning UNCERTAIN).
- **Heading-up**, ownship fixed at **(65,85)**. Scale: 112 px = scale NM, scale +0x279c ∈ {10,20,40,80}, default 40,
  OSB 0xb/0xc = next/prev, wrapping 80 → 10 and 10 → 80 (`FUN_00531850`/`FUN_00531950`); range sprite 1..4
  (`FUN_00533b80`). World offset (ex = X−ownX, ny = Y−ownY): `x = 65 + (ex·C − ny·S)/k`, `y = 85 − (ex·S + ny·C)/k`,
  k = scale·16.5446 m/px (0x60c410, @531d92 / @532216), S/C = sin/cos heading (+0x2734/+0x2738).
  So the number is the window's width (112 px), not the range to its edge: at 40 the window shows 26.8 NM ahead
  (75 px), 13.2 NM behind (37 px) and about 20 NM each side; the circle r=22 is 7.9 NM and the SCL ring r=44 is
  15.7 NM. The map (`FUN_00539f20`, factor 65.004 / (scale·1853) · 112, `0x60c408..0x60c40c`) is drawn at the same
  scale within 0.7 % (the ×1.0071394). Labels (`FUN_00533b80`, rects `0x65d610`): mfds.bmp's cells read 5, 10, 20,
  40, 80, 80 (the 160 cell repeats 80), and the TSD uses cells 1..4. Test: test_mfd.gd (label and waypoint
  positions at every scale).
- Fixed GDI (pen 0x58c, null brush): circle r=22 (43,63)-(87,107); ownship lines (60..71,81), (65,78..91), tail
  (63..68,91); outer ring r=44 (21,41)-(109,129) when SCL on.
- Compass letters S/E/N/W (sprites) on radius 18 around (65,85), rotating with heading.
- Right OSBs toggle (default all on): 0x10 SAM (+0x278c), 0x11 WPT (+0x2790), 0x12 MAP (+0x2794), 0x13 SCL
  (+0x2798); highlight box (111,20+20i)-(128,29+20i) when on. With MAP on, pass 3 redraws the labels "sa", "wp",
  "ma", "sc" left-aligned at (113, 22+20i) over the map.
- Waypoints (state+0x7c/+0x80, stride 0x2c, count +0x310, current +0x320, type +0xa4): polyline in 0x58c; current
  filled 5x5 green (0x27a4); action 5 (the target waypoint, EN 4.15): a red filled triangle when current (0x27ac,
  0x2400ff), else a purple filled 5x5 (0x27a8, 0x360080); others hollow 5x5 dark green (0x27a0). Pass 4 clips to the
  region (10,10)–(122,122).
- SAM sites (state+0x1148.., stride 0x14, count +0x1288, ≤ 16; SAM option): `FUN_00446270` copies them every frame
  from the TSD unit table (`FUN_004d2900`, docs/front-end.md §8.1): the class-8 units (alive, controlled, known to the
  player) with X, Y, the ring radius ([0x1a]: 290 / 340 → 37080 m, 300 → 16686, 320 → 22248, others 0) and an
  active flag ([0x1b], always 1). Each: the 3x3 box with the \ diagonal and, when ⌊r/k⌋ > 0, a ring of that radius.

### RWR (7) and panel RWR
(The RWR itself, the positions and the per-cockpit dials: docs/rwr.md.)
- Symbols centred (66,66), radius 56 (`FUN_00531470`). When state+0x590 (damage flag 14) ≠ 0, it draws "Mal" at
  (101,3) in place of the symbols.
- rwrsymb.bmp glyphs 10x10 at src (0,Y,10,Y+10), drawn at pos−5. Threat type → Y: 0x122→0 "2", 300→10 "3",
  0x136→20 "5", 0x140→30 "6", 0x14a→40 "8", 0x154→50 "H", 0x168/0x17c/0x186→60 (AAA, two chevrons;
  EN 4.24), 0x15e→70 "A", then the aircraft glyphs: 150→80 "21", 160→90 "23", 180→100 "29", 170→110 "25", 120/200→120
  "4", 110→130 "15", 100→140 "16", 130/190→150 "C" (Kfir and Mirage), 140→160 "L" (Lavi).
- Distance clamped to 37060 m → rim; heading-up; entries with +0xe90 blink at 300 ms.
- Panel RWR (`FUN_00531330`): same drawer at [PANELRWR] Center (805,84) in panel coords, radius 28; background from
  the panel bitmap.

### FLIR (6), TV (5): the EO sensor and its camera

The FLIR pod and the TV-guided weapons share one camera (view slot 1): the normal 3D scene drawn into the MFD's
video box.

**Who owns what.** The controller's EO mode `ctl+0x7f4` (0 none, 1 TV weapon, 2 FLIR) picks one of two "mcp"
objects (`ctl+0x7cc + 4·mode`: +0x7d0 TV, vtable 0x600c28, update `FUN_004604c0`; +0x7d4 FLIR, vtable 0x601360, update
`FUN_0045d7f0`); their `+0xc` is the store the camera sits on. The picture is **view-manager camera slot 1**
(`DAT_00699304 + 0x498`, type **0xb**, set up by `FUN_005817a0`, pose `FUN_00582880` case 1/2, angles `FUN_005805e0`),
rendered by the 3D engine as **viewport 1** into the MFD's screen rect (10,10)–(122,122) (`FUN_004d9080` →
`FUN_004d9590` / `FUN_005209d0`; `FUN_004d9790(1)`) **after** the tile was blitted with its cyan key, so the
picture shows only through the tile's cyan box. The viewport is the ordinary 3D scene: **in full colour, from the same
renderer** (the exe has no polarity, greyscale or green-mode call). Its resolution is the 112 × 112 screen px of the
rect, rendered once per frame. Its field of view = renderer `+0x1ac[1]` = **50° / zoom** across the rect width (`FUN_004dc990(1,
zoom)`: `0x605250` = 50.0, the main view's 50°).

**Availability.**
- **FLIR** = a FLIR pod on a pylon: `ctl+0x93c` (= `FUN_004586b0` at the flight start `0x4487ac`) is set when any of
  stations 0..8 holds a store whose name **contains "FLIR"** (`0x600eb8`); `FUN_00446ac0` copies it to state+0x610 (the
  MENU "FLIR" label / button). In the shipped bdb only store 55 "FLIR" (660 "Shell") is one, loadable on the **F-16
  (station 3), F-4 2000 (station 4) and Lavi (station 3)** (`CDMEWeaponLoadItem`s of default6_1.bdb). `FUN_004592d0`
  finds (and caches at `ctl+0x280`) that pod store.
- **TV** = the selected store is a 635 Maverick (0x27b) or 640 TV missile (AGM-62 / POPEYE / GBU15 in the bdb; 0x280);
  the status code also accepts 650 (0x28a) (`FUN_00460470`).
- Entering: master mode 5 (650 laser bomb) **with** the pod → HUD mode 6, EO mode 2, page 6 (`FUN_00449810` case 5);
  without it HUD 5, stores page. Master mode 6 (635 / 640) → HUD 7, EO mode 1, page 5 (case 6). The replaced page is
  remembered (`ctl+0x930` for 5, `+0x934` for 6) and put back when a master mode change to modes 1..4 leaves 5 / 6
  (`FUN_0044e6e0`, which also sets EO mode 0). NAV (mode 0) skips `FUN_0044e6e0`: the EO mode stays on and the
  NAV page or the M key's layout replaces the page.
- Case 6 also puts a page 6 that is still shown back to `+0x934` (the stores page 1 when that is 5), after placing
  page 5.
- `+0x934` is also set by the MENU "FLIR" OSB (0x5b(6, mfd): that MFD's page before) and by key I (0x5a(6): the
  Right's page before when the Left shows the radar; else the exe stores 6 itself, so a later put-back keeps page 6).
- Key **I** (event 0x5a(6)) and the MENU "FLIR" OSB (event 0x5b(6, mfd)) open page 6 when neither page 6 nor page 5 is
  shown and the pod is fitted: EO mode 2, aimed as master mode 5. I only opens the page: a shown page 6 ignores it.
- Event 0x5a(5) is refused: page 5 opens only through master mode 6.

**Initial aim** (`FUN_00449810` / event 0x5a): when the radar has a target (`ctl+0xc4` = 0 and (TWS with a selection
`FUN_004adab0` or a lock `FUN_004ada80`), target `FUN_0044e430`) the camera **tracks that object**; FLIR only: else
with the laser on (`ctl+0x960`) it tracks the EO centre point (below); else it starts **free** at az 0, el −5°.
TV: only a Maverick takes the radar target; the others start free. `FUN_00450280(store, point)` → `FUN_005817a0`.

**Camera (slot 1, `FUN_005817a0`)**, per start with a store: az `+0x1ec` = 0, el `+0x1f0` = −5° (0xbdb2b8c2),
rates 0, start time `+0x1d8` = now, zoom `+0xc` = 1 when the slot was not already type 0xb (kept otherwise), tracking
`+0x50` = 1 free / 2 a point (`+0x1e0`) or an object (`+0x60`), frozen base off (`+0x220` = 0). **Gimbal limits by the
store's class** (`+0x30`→+8): **0x1a (660: the pod) az ±45°, el +30° / −80°**; any other (the weapons) **az ±30°, el
+15° / −45°** (`+0x1fc` / `+0x200` / `+0x204`).
- **Angles** (`FUN_005805e0(t, &az, &el, pose)`): free: az = az0 + rate_az·(t − t0), el = el0 + rate_el·(t − t0);
  tracking: az = atan2(dx, dy) − pose heading, el = atan2(dz, √(dx² + dy²)) − pose pitch (wrapped to ±π), d = target −
  eye, and stored as az0 / el0; then **clamped** to the limits (the output, so a stored value never winds up).
- **Pose** (`FUN_00582880` case 1/2): eye = the store's world position (`+0x224` node), heading = the base heading +
  az, pitch = the base pitch + el, **roll 0**; base = the jet's live heading / pitch, or the frozen base (`+0x208`)
  when `+0x220` is set.
- **Slew** (keys Ctrl+arrows, records 48–51: ids 0x8b / 0x8c rewritten into **0x8a(x, y)** with the other axis's last
  value from their own store `DAT_008338f8` / `+0x8338fc`, ±100; release 0): controller case 0x8a, only with an EO
  mode and slot 1 of type 0xb. With |x| < 10 and |y| < 10 (the keys released) **and** (the store's `+0x48` = 1, i.e. a
  launched TV weapon, or FLIR) it **locks**: tracks the EO centre point (`FUN_00450480`, below) — for a launched TV
  weapon other than the Maverick that point also becomes the weapon's aim (vfunc +0x2c). Otherwise `FUN_00581b30(t,
  y, x)`, only when (x, y) changed since the last call (`DAT_00843b84 / 88`, reset to 6 / 6 by every camera start):
  from tracking it switches to free with the **base frozen** at the current pose (world-stabilised: the picture stays
  fixed in the world while the jet turns), else az0 / el0 = the current angles; t0 = now; rates **az = 0.09·x / zoom °/s, el =
  0.09·y / zoom °/s** (0.09 = `weapons.ibx [DEBUGDATA] _debugParam008` "CAMERA: reduceParam of tv missile", read at
  `0x8415a8 + 0x40`; ×π/180 `0x610ee4`), so full deflection is **9°/s at zoom 1**. Right / up are positive
  (atan2(dx, dy) − heading: clockwise). A pre-launch TV weapon therefore only slews (release = stop).
- **Zoom** (events 0x14 / 0x15 with p1 = 0 while slot 1 is type 0xb — the zoom keys' **release** records (p1 0; the
  press has p1 −1 and zooms the main view) and the MFD OSBs 0xb / 0xc): in `FUN_005820e0` ×2 while < 8, rates ×0.5;
  out `FUN_00582160` ×0.5 while > 1, rates ×2 → **1, 2, 4, 8** (FoV 50°, 25°, 12.5°, 6.25°). az0 / t0 keep their
  values (original quirk: zooming during a slew makes the picture jump), then `FUN_004dc990(1, zoom)`.
- **WIDE / SPOT** (event 0x20, FLIR OSB 5): flips the FLIR object's `+0x14` (`FUN_00545a90` / `FUN_0057e830` on
  `ctl+0x7d4`; starts 0 = WIDE) and zooms **3 steps** in (to SPOT) or out (to WIDE).
- **Laser** (key L / FLIR OSB 3, event 0x6a): `ctl+0x960` flips, only with the pod fitted. (What it designates for the
  laser bombs: with the bombs.)
- **EO centre point** (`FUN_00450480`): in the cockpit-like main views (1, 0x12, 0x16) or with `ctl+0x938` the world
  point under the centre pixel of viewport 1 (`FUN_00401fc0` depth pick in `FUN_004d9080`, saved at game window
  +0x198; nothing hit → 1e8 m along the line of sight); in other views a point 1e7 m along the camera's line of sight.

**FLIR page** (`FUN_00536c10`, data `FUN_0045d7f0` → `FUN_00446a60`, state+0x5e0..0x600):
- Pass 3 (sprite font): zoom "%1d" (ftol(zoom) clamped 1..10) right-aligned at (11,33); "WIDE" / "SPOT" (state+0x600)
  right-aligned at (114,3); "LASER OFF" / "LASER ON" (+0x5f8) at (42,3); range = |centre point − eye|·(1/1853)
  (`0x60c4a0`) NM: "%3.1f", or "XXX.X" from 20 NM, right-aligned at (98,124).
- Pass 4 (pen): the gimbal marker, a 5×5 blob of lines (x−1..x+1 at y−2, x−2..x+2 at y−1..y+1, x−1..x+2 at y+2) at
  **x = 66 − 56u, y = 66 + 56v**, u = az·4/π (`0x601354`), v = (el + 5°)·4/π (`0x601358` = −5°): ±45° = ±56 px about
  the −5° boresight. (As the code: a pod looking right puts the marker left of centre.)
- OSBs (`FUN_005219e0` case 6): 0xb zoom in (0x14), 0xc zoom out (0x15), top 5 WIDE / SPOT (0x20), top 3 laser (0x6a).
- The tile (0,660) has "FLIR", the cyan video box, a centre reticle and "NM".

**TV page** (`FUN_005369e0`, data `FUN_004604c0` → `FUN_00446450`): status state+0x5e8 = the TV mcp's vfunc +0x1c
`FUN_00460940`: 0 when the store is not 635 / 640 / 650, **1 "RDY"** before launch (store `+0x48` ≠ 1) and for a
launched Maverick, else the launched weapon's own vfunc +0x30 (2 "TRA" / 3 "TER", with the TV weapons); and 0 when
no round of that store is left (`FUN_00456cd0` → `FUN_0053bcd0`) unless a launched non-Maverick weapon still flies.
- Tile (0,792) ("TV", the cyan box, a cross) only while the status ≠ 0, else the blank tile (no picture).
- Pass 3: with status ≠ 0: zoom "%1d" right-aligned at (11,33); "%3d" right-aligned at (111,110) = ftol of the
  weapon's motion object vfunc +0x80, its time left (guided `FUN_00564f10`, homing burn − age; `FUN_004d6ac0`: < 0 → 0,
  > 300 → 60; docs/weapons.md §12.3); always: "RDY" /
  "TRA" / "TER" / "NO SOURCE" right-aligned at (114,3).
- Pass 4, status ≠ 0: the seeker ticks — a vertical one at x = 66 − 56u, y 64..69, and a horizontal one at y = 66 +
  56v, x 63..69; u = az·6/π, v = el·6/π (`0x601524`): ±30° = ±56 px.
- OSBs (case 5): 0xb zoom in, 0xc zoom out. No pass 2.
- Key Z (event 0x1f): the full-screen weapon MFD (`ctl+0x938`, next section), only with an EO mode whose mcp vfunc
  +0x1c ≠ 0.

### Full-screen weapon MFD (key Z, v1.1) — `FullScreenRender.cpp`, object at cockpit+0x18

Key Z replaces the whole cockpit view with the TV / FLIR picture at 385 × 382 px inside the `fsmfd/FsMfd.bmp` bezel,
with its own symbology layer.

**Flag.** `ctl+0x938` (player controller, dword 0x24e). Cleared at the flight start (`FUN_00447890`).

**Toggle** (event 0x1f; `FUN_004cd630` case 0x1f, only with a player controller `DAT_00699308`):
1. Controller `FUN_0044a240` case 0x1f: flag set → clear it. Flag clear → set it only when the EO mode
   `ctl+0x7f4` ≠ 0 **and** that mode's mcp vfunc +0x1c ≠ 0. TV: `FUN_00460940`, the TV status (0 none, 1 RDY,
   2 TRA, 3 TER). FLIR: `0x450df0` always returns 1. The extra "or EO mode 2" test is therefore redundant.
   Otherwise nothing happens.
2. Then, **always** (entering, leaving or refused): the main view is set to the cockpit (`FUN_0057f2a0` type 1), or to
   HUD-only (type 5) when `DAT_0083370c` (the last F1 choice) is set. Z keeps that choice (F1 toggles it). The head
   returns to straight ahead. So Z from an external view without an EO weapon acts like an F1 that keeps the
   cockpit / HUD choice.

**View mode 0xb.** The main view stays 1 / 5. Every frame `FUN_00448b20` (@449330) writes S+0x1088
(`FUN_004465b0`) = the type of **view-manager camera slot 1** (`DAT_00699304[0x23a]` +8 = 0xb, the weapon camera of §3
FLIR/TV) while the flag is set, else the main view's type. The cockpit keys every draw rule on S+0x1088:
- `FUN_0051f8e0` case 0xb → `FUN_0051fae0`.
- `FUN_00520980`: viewport 0 (the world view) is **skipped**.
- `FUN_005209d0` → `FUN_00525370`: viewport 1 = RENDER_RECT.
- `FUN_00521440` case 0xb: mouse.

**Exits.**
- Z again.
- Any view key (event 0x1c): `FUN_00450440` clears the flag after that case's gates (player flying, no snap view).
- Per frame (`FUN_00448b20` @449334): EO mode 0, or the TV status 0. EO mode 0 comes from any master mode change
  leaving 5 / 6 (`FUN_0044e6e0`). TV status 0: no round of the store left and no launched TV weapon flying, or the
  store is not 635 / 640 / 650. FLIR never drops out this way.
- **Weapon impact.** Event 0x4d (object destroyed; controller case 0x4d) with the mcp's store (`+0xc`, the camera
  carrier) as the object: when the flag was set, it is cleared and the main view becomes a **fly-by (type 0x13)** of
  the wreck, `FUN_005808c0(t, obj, {300, 700, 300} m with two random angles in ±π, 6.0, 0x13, 1)`. UNCERTAIN: the
  exact angle slots and the meaning of 6.0; compare the F11 fly-by in docs/views.md. Without the flag there is no
  view change. In both cases, with 640 selected the camera then restarts on the next store (`FUN_00450280(store, 0)`).
- Nothing else exits: the zoom, slew, WIDE / SPOT and laser keys keep working.

**Load** (`FUN_0051f610`, every frame from `0x4d96e3`).
- When S+0x1088 becomes 0xb (previous frame's copy cockpit+0x1698 ≠ 0xb): the MFD index = the **last** of the 3 MFDs
  whose page (S+0x504+i·4) is 5 or 6, else 0. Stored at fs[0xb7] = cockpit+0x2f4. Then
  `FUN_00523d70(<cockpit dir>FsMfd\\)`:
  - `FUN_00523b60` reads `Data.ibx`: CORNER000..003 → fs[0xb..0x1a], RENDERCORNER000..003 → fs[0x1b..0x2a],
    RENDER_RECT → fs+0xac..0xb8.
  - `FsMfd.bmp` (640x480) is loaded and cut into 4 CORNER surfaces fs[6..9] (key 0xffff00, unused) and 4
    RENDERCORNER surfaces fs[2..5] (key **0xffffff**).
  - fs[0xb2] = `GetStockObject(DEFAULT_GUI_FONT)` is never selected. fs[0xb3] = `CreatePen(PS_SOLID, 2, 0x00ff00)`.
    fs[10] = 0.
- Freed by `FUN_00523d00` when 0xb ends.
- Reloaded by `FUN_00524070` whenever the cockpit is dirty: +0x2fc, which includes the first 0xb frame, or
  +0x300 / +0x285c.
- The shipped `data.ibx`:

  | piece | rect |
  |---|---|
  | CORNER000 | 0,0–128,480 |
  | CORNER001 | 512,0–640,480 |
  | CORNER002 | 128,0–512,49 |
  | CORNER003 | 128,431–512,480 |
  | RENDERCORNER000 | 128,49–169,192 (with the two green zoom arrows) |
  | RENDERCORNER001 | 467,49–517,94 |
  | RENDERCORNER002 | 128,383–177,431 |
  | RENDERCORNER003 | 469,392–517,431 |
  | RENDER_RECT | 128,49–513,431 |

- The art: the bezel, 20 OSBs, DAY / BRT knob, NGT / CTR rockers (dead art), white = key in the rounded screen
  corners, black screen.

**Frame order.**
1. `FUN_004d9080`: viewport 1 (slot 1 camera, §3 Camera) rendered straight into **RENDER_RECT, 385×382 px at native
   resolution** (no scaling). Horizontal FoV = 50°/zoom across the 385 px. The EO-centre depth pick is at the rect
   centre (+193, +191); with `ctl+0x938` the EO centre point is that pick (§3 FLIR/TV), so the laser point and the
   TV lock use the full-screen picture.
2. `FUN_0051fae0`, on the back-buffer DC:
   - Font cockpit+0x578 (ANSI_VAR_FONT), NULL_BRUSH, transparent background.
   - `FUN_00524430`: clip region RENDER_RECT; pen fs[0xb3]; text colour **0x00ff00**, always (fixed; the HUD colour
     index has no effect); TA_LEFT|TA_TOP.
   - Then the TV (`FUN_00524570`) or FLIR (`FUN_00524a60`) layer, picked by page 5 / 6 of the MFD fs[0xb7]. Any
     other page: no symbology, only the picture and the frame.
   - Then `FUN_00520490`: the debug FPS text and MP lines only.
   - **Hidden:** panel, HUD, the three MFDs, the message console (`FUN_005201b0`).
3. `FUN_00524090`:
   - The 4 CORNERs, opaque (`BltFast` flag 0x10 = WAIT), only on the first 3 frames after a (re)load (fs[10]
     0→1→2→3, one per flip-chain buffer), then released. The frame outside RENDER_RECT stays as drawn: nothing
     redraws or clears it afterwards (viewport 0 is skipped).
   - The 4 RENDERCORNERs **every frame**, white-keyed (flag 0x11 = WAIT|SRCCOLORKEY), so the rounded corners and
     the zoom arrows cover the picture **and the symbology**.

**Layer geometry.** x0, y0 = RENDER_RECT left / top + 2 = (130, 51); w, h = size − 4 = 381 × 378; cx, cy = x0 + w/2,
y0 + h/2 = **(320, 240)**. The MFD's 56 px half-scale becomes w/2 = 190 (x) and h/2 = 189 (y). Lines below end
exclusively (GDI LineTo).

TV (`FUN_00524570`, state as the TV page: +0x5e8 status, +0x5e0 / +0x5e4 = u / v = az / el·6/π, +0x5f4 zoom,
+0x5ec time left):
- Cross-hair: gap g = 10, **20 at TER**. Vertical x 320 from y 51 to cy − g, and from cy + g to 429. Horizontal
  y 240 from x 130 to cx − g, and from cx + g to 511.
- Ticks, each only when outside the gap:
  - Azimuth: X = 320 − 190u, when |190u| > g; vertical (X, 236) → (X, 245).
  - Elevation: Y = 240 + 189v, when |189v| > g; horizontal (315, Y) → (325, Y).
- Text at its top-left corner:

  | text | at |
  |---|---|
  | "TV" | (187, 59) |
  | "%1d %s " (S+0x36c count, S+0x354 name of the selected store, as the HUD weapon line) | (254, 59) |
  | "RDY" / "TRA" / "TER" / "NO SOURCE" | (403, 59) |
  | "X%1d" ftol(zoom) | (140, 145) (between the arrows) |
  | "%3d SEC" ftol(time), or "XXX SEC" when time ≥ 250 | (378, 399) |

- Waypoint marker (below) only when time > 15 or status = RDY.
- Attitude bar (below).

FLIR (`FUN_00524a60`, FLIR page state: +0x5e0 / +0x5e4 = u / v = az·4/π, (el + 5°)·4/π, +0x5f4 zoom, +0x5f8 laser,
+0x5fc range m, +0x600 SPOT):
- Short cross-hair, gap 10: x 320 from y 191 to 230 and 250 to 289; y 240 from x 270 to 310 and 330 to 371.
- Four corner brackets: (cx ∓ 80, cy ∓ 50) → (cx ∓ 80, cy ∓ 80) → (cx ∓ 50, cy ∓ 80), mirrored for each corner.
- Gimbal marker: the page's 5×5 blob at **X = 320 − 190u, Y = 240 + 189v**.
- Text:

  | text | at |
  |---|---|
  | "FLIR" | (187, 59) |
  | "LASER OFF" / "LASER ON" | (284, 59) |
  | "WIDE" / "SPOT" | (403, 59) |
  | "X%1d" | (140, 145) |
  | "%3.1f" range·0.00053967 NM, or "XXX.X" from 20 NM | (378, 399) |

- Waypoint marker always; attitude bar.

Waypoint marker (`FUN_005256f0`): the current waypoint's projection S+0x328 / +0x32c. Producer: `FUN_00446320`; in
0xb it uses `FUN_00402000` with flag 0, otherwise the HUD's `FUN_0045a790`.
- Clamp: when the point is outside the rect (148,69)–(493,411) (RENDER_RECT inset 20), it is moved along the line
  from (cx, cy) onto that edge (bisection `FUN_0052db30`, per edge).
- Hollow `Ellipse(x ± 15, y ± 15)`, skipped when coordinates would overflow 16 bits.
- Label "%d" (index + 1, index = min(S+0x320, S+0x310)), or "T" for action 5, TA_CENTER|TA_TOP at (x, y − 7):
  inside the circle.
- UNCERTAIN: the projection uses the engine's current camera. `FUN_004d9080` puts viewport 0's camera back only when
  viewport 0 was drawn, so in 0xb it is the weapon camera of the previous frame. The marker therefore lies on the
  picture.

Attitude bar (`FUN_00525030`): the DASH symbol's bar (docs/cockpit.md), scaled up.
- Two polylines (∓162, 10) → (∓162, 0) → (∓10, 0) about (320, 240) at **4 px/°**.
- Same fold, rotation and ±40° clamp. It blinks by flipping `DAT_0065cd10` after > 300 ms of the frame clock
  (fs+0xbc = cockpit+0x574, accumulator `DAT_0083de7c` / `DAT_0083de78`).

**Mouse** (`FUN_00521440` case 0xb → `FUN_005253a0`; table `0x65cd18`).
- Strips: top (193,12)–(447,39), bottom (192,441)–(449,470), left (88,108)–(116,367), right (522,109)–(550,366).
- Buttons every 57 px, live only on the first 27 px. Ids = the small MFD's: top 1–5, bottom 6–10, left 11–15,
  right 16–20.
- Over a button: cursor 2. A click (`FUN_00521800` case 5 → `FUN_005219e0`) runs that page's OSB action for MFD
  fs[0xb7], exactly as on the panel:
  - TV: 11 / 12 zoom in / out (the green arrows).
  - FLIR: 11 / 12 zoom, 5 WIDE / SPOT, 3 laser.
  - 6 MENU posts 0x5b(8), which the controller drops while `ctl+0x938` is set, so the page cannot change in full
    screen. Event 0x5b is ignored entirely.
- Inside RENDER_RECT: cursor hidden, clicks do nothing (the mouse cannot designate). Elsewhere: arrow cursor.

**Keys in full screen.** The usual EO keys keep working, because they test slot 1's type or the EO mode (the flag
plays no part):
- Ctrl+arrows slew / lock (0x8a).
- The zoom keys' release records (0x14 / 0x15, p1 0).
- WIDE / SPOT (0x20), laser L (0x6a), I (0x5a(6), a no-op with page 6 shown).

**v1.0.** The same renderer exists (`C:\BlueStar\Source\CockpitRender\FullScreenRender.cpp`, loader `FUN_00522250`,
`FsMfd` strings), and the controller's `mov [ctl+0x938], 1` exists. v1.0's dispatcher `FUN_004cce00` did not forward
event 0x1f, so the mode was unreachable. v1.1 only wired Z (docs/v1.1.md).

**iaf-reborn:** built: `eo.rs` `full_screen_ok`, `player_weapons.gd` `full_screen_key` / `_update_full_screen`
(Z, the per-frame exits, the impact fly-by via `terrain_view.gd` `full_screen_impact`), `terrain_view.gd`
`_update_full_screen` (the overlay, the cockpit hidden, the main viewport's 3D off, the EO viewport at 385×382 ×
the window height / 480, the waypoint projected through the EO camera) and `game/cockpit/fs_mfd.gd` (the layers,
fsmfd.bmp and data.ibx read from the install, the OSB strips). Differences: the cursor stays visible over the
picture; ANSI_VAR_FONT is Arial 13 px; the frame is redrawn every frame. Test: tests/godot/test_tv_weapons.gd (Z, F1,
Z, the hit's fly-by).

### HARM (10) — `FUN_005358b0`, data `FUN_0045bb00` → `FUN_00446050`
The HARM page lists the candidate targets inside a ±15° cone ahead and lets the pilot pick the HARM's target.

- Source: the **HARM sensor** (ctl+0x44c, vtable 0x601190, a subclass of the AI target sensor of docs/ai.md §14: ctor
  `FUN_0045b850(0, 3, 20)`: its own 15-slot list (`FUN_004b0790(0xf)`), query kind 3, range 20 NM; scan
  `FUN_004af300`, list vfunc +0x20 `FUN_004af260`) with a cone of **±15°** (cos 15° at sensor +0x60 / +0x64, from
  `0x601168` = 15.0 in the static init `0x45b68e`). On only in HUD mode 8 (master 4 with 590 selected: `FUN_00449810`
  → `FUN_0045c2b0` on, `FUN_0045c2f0` off).
- **Scan** (vfunc +0x60 `FUN_0045b960`: clears +0x50, then `FUN_004af300`, state 5): when the sensor comes on and on
  the RWR's 2 s refresh (`FUN_0044a1a0` → the RWR, the radar, this). Units from the spatial query (sphere of kind 3,
  37037 m, `FUN_004b0020`, centred R/2 ahead) through the class filter (vfunc +0x3c `FUN_0045b980`): classes **9, 10,
  11**, and class **8 only when its name holds "RADAR"** (`0x631f3c`, CString::Find, case sensitive: the missions name
  their sites "RADARSA6", "sa13 0RADAR"…; "hawk 2 radar" is not seen). Skipped: the owner, units in state 4 / 5. Range
  R = 20·1854 m; with the own jammer on R·0.8 against a jamming unit, else R·0.5; without it a jamming unit is seen at
  any range (the player-quiet 0.7 R rule never applies: the owner is the player). Accept (vfunc +0x48
  `FUN_004aeb90`; +0x50 = 0, so no "30 m above the terrain" test): inside the cone about the nose and a terrain line of
  sight (both ends +1.5 m). **Every side is listed**, friendlies too, and **emitting or silent alike**: the scan
  skips the side and emitter tests and ignores the RWR.
  Score 100 / dist, best 15. The selected target is kept while alive and still accepted (forced into the list, range
  not re-tested); otherwise the first (nearest).
- State: list count state+0xde8 (≤ 15 entries of 0x40 from state+0xa28), +0xdf8 = the field width = **2·acos(+0x64)
  = 30°**, +0xe00 = **"no source" flag** = no round of the selected store left (`FUN_00456cd0` = 0), or the sensor
  off; +0xdf4 / +0xdfc = the heading / pitch change since the list was captured (`DAT_0082f574` / `0x82f568`, latched
  when the mcp refreshes (state 5: a selection, a sensor notification), wrapped to ±π) — so between refreshes the
  symbols move with the jet's turns; +0xdf0 = **"In Range"** = distance to the sensor's target < the selected weapon's
  DLZ max range (`FUN_00460ac0`, weapon vfunc +0x24).
- Entry: +0xa38 type (the unit's bdb type, or its class when the type is −1), +0xa44 selected, +0xa4c id, +0xa58 az,
  +0xa5c el (rad, relative to the nose at capture).
- Pass 4: while this MFD owns the cursor, the cross-hair to the display edges with 3 px gaps (no ticks); per selected
  entry an **8×8 box** (x−4..x+4, y−4..y+4); positions **x = 66 + (az + dpsi)·112/30°, y = 66 − (el + dtheta)·112/30°**
  (`0x60c478` = 112), only when 8 < x, y < 124 (MFD px).
- Pass 3: per entry inside that window one sprite-font character at (x−2, y−2): type 290 "2", 300 "3", 310 "5", 320
  "6", 330 "8", 340 "H", 350 "A", 360 "G", class 9 "I" (SA-13), class 0xb "R" (ground radar), anything else "0";
  360 "G" is the Gun Dish site (ZSU-23) (EN 4.32). A click (cursor in the ±4 px
  box, `+0x27d8`) on an entry sends **event 0x37(id)** → `FUN_0045c280`: the sensor selects it (vfunc +0x38) and
  refreshes; `DAT_0083e344` blocks a repeat until that id is the selected one. Status right-aligned at (114,3):
  **"no source"** when +0xe00, else **"In Range"** when +0xdf0, else **"No Range"** when the list is not empty, else
  nothing.
- Ctrl+Return (cmd 0x33, HUD mode 8, more than one entry) / cmd 0x34 (no key): next / previous target (vfunc +0x2c
  `FUN_0045b930` → `FUN_004aefd0(1 / 0)`: the list iterator to the next / previous entry, wrapping; none selected →
  the first; then state 5).

**iaf-reborn** (`crates/iaf-avionics/src/eo.rs` via `weapons/eo_sensor.gd`, `cockpit/mfd.gd`,
`terrain/terrain_view.gd`) builds all of the above. The TV weapons fly (`player_weapons.gd` `tv_weapon` /
`tv_status`): the eye rides the launched weapon and "%3d" shows its time left. Differences from the original:
- The EO centre point is the nearest of the terrain under the line of sight (ray-marched) and the shown units' /
  buildings' model bounds on it (ray-tested, `eo.rs` `unit_pick`). The original reads back the depth buffer.
- Before launch the eye is the jet's position (the original: the pylon). The picture is a SubViewport camera of the
  same world at the display's on-screen resolution. Both: [deviations.md](deviations.md) §1.
- HARM: the sensor's scan as above (`crates/iaf-avionics/src/harm.rs`). The distance is tested from the jet (the
  original: inside the query sphere; UNCERTAIN radius), with the radar's line of sight. It rescans with the RWR (2 s),
  when it comes on and on a click (the original only re-captures the page on a click). "In Range" comes from the
  HARM's DLZ (docs/weapons.md §11.5). Ctrl+Return steps the list.
- Extras "HARM targets: Real" lists the RWR's emitters instead: [deviations.md](deviations.md) §2.

## 4. isr.bmp / MAPFRAME georeference

The radar MAP page's ground picture: world coordinates to `isr.bmp` pixels, and how the page samples it.

- `cockpits.ibx [MAPFRAME]` read in `FUN_005226e0` into ini+0x61c left, +0x620 top, +0x628 bottom, +0x624 right
  (F-16 file: 0, 1064960, 0, 819200; exe defaults 0x39080/0xaf500/0x3ef8a/0x75801).
- isr.bmp is 640x832 8-bit, loaded by `FUN_0053ae00` (rows flipped so row 0 = north), displayed as **green channel
  only** (palette entry i → 16-bit RGB(0,G_i,0)).
- **Exact code** (objdump `0x53608b..0x536120`, `FUN_00535ea0`), X/Y = ftol(state+0/+4):
  `col = (X + 166828 − left)/(right − left)·640`,  `row = (top − (Y + 21164))/(top − bottom)·832`
  ⇒ **col = (X + 166828)/1280, row = (1043796 − Y)/1280** — 1280 world units (m) per isr pixel on both axes.
- Compare TSD/map.emf: (X+166850), (1043816−Y); config DataXShiftPR −166850, DataYShiftPR 1043780. The ~20 m
  differences are in the exe as written.
- 640/832 = 655360/1024 and 851968/1024, so one isr pixel = 1024 PTT units and isr.bmp spans exactly the map.ptt
  theatre; MAPFRAME/PTT extent = 1.25. Hence, UNCERTAIN: `X = 1.25·ptt_x − 166828`, `Y = 1043796 − 1.25·ptt_y` (ptt_y
  from north).
- Radar MAP rendering (`FUN_0053b0a0`, pass 1, straight to the back buffer before the tile; the MMX sampler
  `FUN_0053ac60` plays no part): window (15,15)-(116,109) = 101x94 px, shows only through the tile's cyan
  fan. The picture is isr.bmp alone, redrawn whole every frame: it has no sweep and uses no terrain heights. Per window pixel (dx, dy) from
  the centre: col = col0 + (dx·C − dy·S)·s, row = row0 + (dx·S + dy·C)·s (C, S = cos, sin of the heading ×65536,
  `>>16`), col0 / row0 = the centre's isr pixel (truncated); outside the image → 0 (black). NORM (state+0xa18 = 0): centre = ownship at window (50,94) = MFD (65,109), rotated by
  heading (heading-up). EXP: centre = the clicked point (DAT_0083e360 / 364) latched when the EXP flag changes
  (DAT_0083e350 / 354), heading frozen then (DAT_0083e368), window centre (50,47), symbol origin (66,66). Both use
  the same scale (EXP only moves the centre). Sampling step `S = R·1853·832/((top−bottom)·94)` isr px per MFD px (94 px = R NM; 1853 m/NM at
  `0x60c480`); outside the image → black. Symbol scale k = R·19.7128 m/px (`0x60c490`).

## 5. Keys and events (keys.trx = 117 command names, one per line = key-table record; docs/controls.md)

| keys.trx command | Default key | Event → effect |
|---|---|---|
| Activate TSD on MFD | T | 0x5a SET_MFD_SCREEN(3) |
| FLIR on/off | I | 0x5a(6) (needs the FLIR pod and no TV page shown) |
| Damage report | D | 0x5a(4) |
| Cheat: toggle target cheat view (the label is wrong) | U | 0x5a(7): the RWR page |
| Full screen weapon MFD | Z | 0x1f toggle `ctl+0x938` (only with a TV status ≠ 0 or FLIR; §3) and view 1 / 5 |
| Radar modes | Q | 0x24 cycle A-A 4→5→6→4 (LRS/TWS/ACM), A-G 7↔8 (GMT/MAP) |
| Radar on/AA/AG | R | 0x2b toggle A-A/A-G (restores last mode) |
| Radar standby | S | 0x2c → STBY |
| Boresight mode on | \ | 0x2d press / 0x2e release |
| Increase / Decrease radar range | . / , | 0x21 / 0x22 |
| Master modes / NAV mode on | M / N | 0x63 / 0x62(0) |
| Laser on/off | L | 0x6a |
| Next / Previous waypoint | W / Shift+W | 0x65 / 0x66 |
| Change HUD color | H | 0x7b (`idx=(idx+1)%11`, see §2; default 0) |

- Event 0x5a(page) replaces the Left page; when Left shows radar and there is more than one MFD, it replaces the Right
  page. It is ignored when the page is already shown or page = 5. A placed page plays SFX_BUTTON (`FUN_0044a240` case
  0x5a, tail @44d269).
- Radar events first put the radar page on an MFD if none shows it.
- STT comes from a lock (event 0x2a).
- Master mode → page (`FUN_00449810`): the table in [weapons.md](weapons.md) §2.3. A page no active MFD shows
  (`FUN_00449f90`) goes to the first MFD not showing the radar, slot order Left, Right, Middle (`FUN_00449f20`, `IafModes.free_slot`). All three on the
  radar: the Left. Two MFDs both on the radar: the exe writes the unused slot `ctl+0x70`, so no MFD shows the page.
  One MFD: the Left. Page 10 keeps the page it replaced in `ctl+0x92c`. When the HUD mode
  was 8 (HARM), the sensor goes off (`FUN_0045c2f0`) unless a 590 stays selected, and page 10 goes back to `+0x92c`
  (that page 5 / 6: to `+0x930` / `+0x934`); a 590 still selected places page 10 again.
- M (event 0x63, `FUN_0044a240` after `FUN_00449810`, `LAB_0044b9fb`) then sets every MFD's page for the new cycle
  position. Slot 0 is the Left MFD, slot 1 the Right, slot 2 the Middle (`ctl+0x68 + i·4`, the order of
  `FUN_00448120`'s defaults); a cockpit with another count than 2 or 3 sets slot 0 only:

| Cycle | 3 MFDs (Left / Right / Middle) | 2 MFDs (Left / Right) | 1 MFD |
|---|---|---|---|
| NAV | radar / NAV / TSD | radar / TSD | TSD |
| AA | radar / RWR / TSD | radar / TSD with a panel RWR (`ctl+0x18`), else RWR | radar |
| AG | radar / stores / TSD | radar / stores | stores |

  In AG with a 590 selected the stores page is the HARM page (10): the slot's page before goes to `+0x92c` and the
  sensor comes on (`FUN_0045c2b0`). `FUN_00449810` has usually placed page 10 on that slot already, so `+0x92c`
  becomes 10 and leaving HARM later keeps page 10 (exe behaviour, kept).
- M also sets the radar (`FUN_004ad8f0`, the R key's A-A / A-G switch; `IafModes.m_key_radar`), from its A-A flag
  `ctl+0xc4` (radar+0x40) and mode `ctl+0xb4` (radar+0x30). NAV and AA: one switch when the radar is in A-G or OFF,
  so it ends in its last A-A mode. AG with 2 or 3 MFDs: one switch when in A-A, and a second one while still in A-A
  (a radar in OFF / STBY first goes to A-A). AG with another count leaves the radar.
- M then plays SFX_BUTTON (code `FUN_00450a60(0x23, 0, 0)`, played by `FUN_0044fb10` for the player's jet only).
  The HARM sensor call of M (`FUN_0045c2b0`) repeats the one in `FUN_00449810`; it acts only on a sensor that is
  off, so the second call does nothing.
- A click on the HARM page's entry that is already selected sends nothing (`FUN_005358b0`, `DAT_0083e348`).
- Radar-page OSBs: 0xb range+, 0xc range−, top 1 = cycle mode (0x24).

## 6. HUD (brief)

- Main `FUN_00530b70`. Centre x = 320 − pan, centre y = MainOffsetY + vpan − [HUD] CenterY; gun cross and boresight
  from GunRetPositionY/BorePositionY; clip = centre + (−LeftBorder, −TopBorder, +RightBorder, +BottomBorder).
  Glass = `[HUD] FileName` (e.g. `F16hud.bmp`), sliced by MaskOffsetX/Y/Y2 (`FUN_00528eb0`/`FUN_005293b0`).
- Elements: text block at TxtOffX/Y (`FUN_0052ef20`: "R %2.1f", "W%02d  %02.1f", "%3.1f MIN", "%2d SEC",
  "T %03d%", "AB %1d", "%4.1fG"); speed scale (`FUN_005386c0`), altitude scale (`FUN_005381c0`), heading tape
  (`FUN_00537cd0`), pitch ladder / FPM (flight path marker; `FUN_00538c90`; the v1.1 rules are in cockpit.md "HUD
  symbology"). Colour = HUD table above.
- HUD text also uses the 5x5 sprite font (HUD-coloured copy +0x5d4); the cockpit never draws with `hud.fnt`.

## 7. Per-aircraft cockpit table (all cockpits; general layout/HUD/gauge data in `docs/cockpit.md`)

Which cockpit each jet gets, and how its `cockpit.ibx` sets the MFDs, default pages, RWR and ADI.

### General decoding rule
To find a jet's cockpit layout:
1. **Aircraft -> cockpit dir.** `FUN_00447e70` switches on the aircraft type (`veh+0x24`, ids in part-animation.md) and stores
   the cockpit index at logic+0x10. That index is the `k` of `Cockpit00k = <dir>` in `cockpits.ibx`. `FUN_00520c20` ->
   `FUN_005228a0` reads `<CockpitDir>\<dir>\cockpit.ibx`, the only file name it opens, so `cfir/cockpit.ini` is unused. Types: 100 F-16 -> 1;
   110 F-15 -> 0; 120 F-4 -> 5; 130 Kfir -> 4; 140 Lavi -> 3; 160 MiG-23 -> 8; 180 MiG-29 -> 7; 190 Mirage -> 6;
   200 F-4-2000 -> 2; 150/170/210/220/225 (MiG-21/25/17, Tu-22, C-130) -> 3 (Lavi cockpit, fallback; UNCERTAIN whether ever
   shown). It also sets logic+0x24 = 1 for F-15, F-4, F-4-2000, MiG-29 (the twin-engine ones: damage page "twin only"; UNCERTAIN
   naming) and logic+0x964 = 1 for F-16, F-15, Lavi, MiG-29, F-4-2000 (meaning UNCERTAIN).
2. **Menu jet -> type** (`menu/dat/sjet.trx` order Mirage, Kfir, F4, F42000, F15, F16, Lavi; the id mapping F42000 = 200 is by
   elimination of the two F-4 ids, F4 = 120).
3. **MFDs.** `[MFD]` keys `LeftActive/RightActive/MiddleActive` (default 1), `<Side>OffsetX/Y`, `<Side>MouseActive` (default 1;
   consumer UNCERTAIN, presumably enables clicking) -> MFD index **0 Left, 1 Right, 2 Middle** (ini idx 0x5d, 0x5e, 0x5f;
   confirmed by the default-page code). Panel pixel = (OffsetX, OffsetY) as in §1; **screen** top-left =
   (OffsetX - 640, OffsetY + MainOffsetY) at pan 0 (`FUN_0052abb0`, hit test loops at ini+0x223c/+0x2258). Inactive MFDs keep
   junk offsets in the file (ignore them). `MenuFlirOn`/`MenuTvOn` (default 1) gate the MENU "FLIR" button (`state+0x610` and
   ini+0x226c); MenuTvOn consumer not traced.
4. **Default pages** (`FUN_00448120`): n = number of active MFDs (`FUN_00520c20`), r = `[PANELRWR] Active` (default 0 when
   the section is missing): Left = 2 (radar) always; **n = 3: Right = RWR (7), Middle = TSD (3)**; **n = 2: Right = RWR (7) if
   r = 0, else TSD (3)**; n = 1: nothing else set.
5. **RWR** is a separate panel dial when `[PANELRWR] Active = 1` (Center/Radius in panel px); otherwise it is only an
   MFD page (7). The MENU page shows "rwr" only when r = 0.
6. **ADI** (attitude) is an MFD page (9, reachable via MENU "adi" only) when `[HORIZON] OnMfd = 1`; page ball centre (65,74) in
   the MFD, radius = `[HORIZON] Radius` (`FUN_00526fe0`, ini+0x218c). With OnMfd = 0 and `[HORIZON] Active` (default 1) it is
   the panel horizon disc at ClockCenter (X split into 320-px slice, `FUN_005268b0`). `Active = 0` -> neither. `[LENHORIZON]`
   (lens ADI bitmap on the panel) is independent. On OnMfd planes ClockCenter equals the centre of one MFD (F-15 Left, Lavi
   Left; F-4-2000 approx Right); the page code does not use it (it draws at (65,74) of whichever MFD shows page 9).

### Table
Screen = top-left on the 640x480 screen at pan 0 (MFD is 132x132). "Panel" = panel bitmap / HUD glass bitmap.

| Menu jet | Dir (Cockpit k) | Panel / HUD glass | MFDs (idx: panel x,y -> screen) | Default pages | RWR | ADI |
|---|---|---|---|---|---|---|
| Mirage | `mirage` (6) | mirage.bmp / mrghud.bmp | 0 Left: 898,157 -> (258,327); MouseActive 1 | L radar | MFD page only (via MENU) | panel disc (Active 1), lens mrgadi.bmp |
| Kfir | `cfir` (4) | cfirpnl.bmp / cfir-h.bmp | 0 Left: 754,134 -> (114,334) | L radar | panel dial (1094,74 r32) | panel disc, lens adi.bmp |
| F4 (F-4E) | `phantom` (5) | f4panel.bmp (h 374) / f4hud.bmp | 0 Left: 889,21 -> (249,201); MouseActive 0; MenuFlir 0, MenuTv 0 | L radar | panel dial (1218,69 r28) | none ([HORIZON] Active 0); lens adi.bmp |
| F42000 | `f4-2000` (2) | panel.bmp / hud.bmp | 0 Left: 730,69 -> (90,269); 1 Right: 903,136 -> (263,336) | L radar, R RWR | MFD page 7 | **MFD page 9** (r40); lens adi.bmp |
| F15 | `f15` (0) | f15panel.bmp / f15hud.bmp | 0 Left: 718,64 -> (78,270); 2 Middle: 890,123 -> (250,329); 1 Right: 1061,62 -> (421,268) | L radar, R RWR, M TSD | MFD page 7 (no [PANELRWR]) | **MFD page 9** (r40); lens adi.bmp |
| F16 | `f16` (1) | f16panel.bmp / f16hud.bmp | 0 Left: 722,146 -> (82,336); 1 Right: 1083,147 -> (443,337) | L radar, R TSD | panel dial (805,84 r28) | panel disc (1100,91 r17); lens f16adi.bmp |
| Lavi | `lavi` (3) | lavi-p.bmp / lavi-hud.bmp | 0 Left: 720,85 -> (80,265); 2 Middle: 894,111 -> (254,291); 1 Right: 1071,88 -> (431,268) | L radar, R RWR, M TSD | MFD page 7 | **MFD page 9** (r40); lens adi.bmp |
| (not in menu) | `mig23` (8) | panel.bmp (h 360) / hud.bmp | 0 Left: 903,120 -> (263,310); MouseActive 0 | L radar | MFD page only | none ([HORIZON] Active 0); lens adi.bmp |
| (not in menu) | `mig29` (7) | panel.bmp / hud.bmp | 0 Left: 707,138 -> (67,328); 1 Right: 1115,139 -> (475,329) | L radar, R RWR | MFD page 7 (no [PANELRWR]) | none ([HORIZON] Active 0); lens adi.bmp |

Per-plane panel geometry (`[PANEL]`): MaskOffsetY1/MaskOffsetY2/MainOffsetY - Mirage 301/33/170; Kfir 300/95/200; F-4E 300/95/180;
F-4-2000 292/85/200; F-15 264/69/206 (+ ElevationAngleDeg 50, AzimutAngleDeg 100, not traced); F-16 288/93/190; Lavi 296/92/180;
MiG-23 298/126/190; MiG-29 297/44/190. HUD `[HUD]` values are in docs/cockpit.md.

Reachability: the Jet list offers only the seven jets above. `mig23` and `mig29` (types 160/180) are reached through a
mission that makes the player's flight MiGs: the Mission Creator's Alpha / Bravo TYPE lists hold both (docs/front-end.md
§19), the TSD's flyable list `FUN_00505730` has them, and `FUN_00447e70` gives them cockpits 8 (`mig23`) and 7 (`mig29`).
Ours flies them the same way (game/aircraft/player_aircraft.gd FLYABLE). `Cockpit009..012 = F16` in cockpits.ibx are
never returned by `FUN_00447e70` (indices only 0..8). `fsmfd/` (full-screen MFD art + `data.ibx`) and
`mfds.bmp/rwrsymb.bmp/isr.bmp` are shared by all cockpits; `emf/map.emf` is the TSD map for all.

## 8. Ours: crisp pages ("Better cockpit" `crisp_mfd`)
With Better cockpit and its `crisp_mfd` item on (docs/cockpit.md "Better cockpit"), `mfd.gd` draws every page at the
MFD's screen resolution. The page code is the same in both modes: every page draws through the primitives of `mfd.gd`
in MFD px (`_seg`, `_polyline`, `_frame`, `_fill`, `_disc`, `_circle`, `_polygon`, `_blit`, `_text`), so a later page
set (the "Real MFDs" option, docs/roadmap.md) can reuse them.
- **Original:** the canvas is scaled by the MFD's screen scale; the art comes from the converted 4× atlas.
- **Crisp:** the canvas is at screen px, `_k` (screen px per MFD px) scales each coordinate. A GDI stroke is a line
  1 MFD px wide, antialiased, over the pixels GDI lights: through the pixel centres, from the first pixel up to the
  last (LineTo leaves its end pixel unlit). Original draws its strokes half a pixel up and left of those pixels.
  Fills (rectangles, the TSD map, the waypoint boxes) cover the same area in both modes.
- **The pixel art** comes from the original `mfds.bmp` / `rwrsymb.bmp` (install `resource/cockpits`), one texture per
  sprite with a clear 1-px border (`crisp_sprite`), drawn through `mfd_crisp.gdshader` (`mfd_crisp.gdshaderinc`). The shader draws each lit pixel's centre joined to its lit
  neighbours by a stroke 1 px wide (a diagonal only where no straight step joins the two). A pixel on a stair (one
  straight and one diagonal neighbour, opposite) joins the two half-way points instead, so shallow lines and arcs
  turn smooth while square corners stay square. The black ground is the opaque pixels' coverage cut at one half, so
  straight edges stay on the pixel edges and the rounded tile corners and the radar fans turn smooth. The colour keys
  RGB(0,255,255) and RGB(0,210,255) are transparent.
- **The pictures** (the EO camera, the radar MAP's isr.bmp) are drawn on a canvas under the page (`_draw_pictures`),
  unchanged in both modes.
- Test: tests/godot/test_mfd.gd (every page records the same primitives with the same MFD-px geometry in both
  modes; crisp draws at `_k` = the screen scale through the shader). Pictures: tests/godot/_mfd_shot.gd (every page,
  Original and crisp).

## Open questions
- Unreferenced tiles (132,132) "Debug", (132,264) LAS, (132,396) TWS, (0,528): leftovers?
- Straight-ahead vertical pan (+0x568) → exact on-screen MFD y.
- Meaning of the TSD ×1.0071394 factor and the ~20 m offsets between TSD, MAP and DataShift constants.
- state+0x3a0 (the STT closure source).
- That the NAV ETA's clock offset (clock+0x18) is the mission start time 0x460.
