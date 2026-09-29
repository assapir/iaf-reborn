# Cockpit MFDs (Jane's IAF, `iafjets.exe`)

Reverse-engineered from the Ghidra dump (`assets/ghidra/iafjets.c`) plus objdump/`.rdata` reads. Source files named in
asserts: `CockpitRender\CockpitMfdHandle.cpp`, `CockpitMfdRadar.cpp`, `CockpitMfdHarm.cpp`. Addresses are function
entry points. Anything not directly read from code is marked **UNCERTAIN**.

Conventions: "renderer" = cockpit render object (ctor `FUN_0051c9f0`, init `FUN_0051cf10`); its copy of
`cockpit.ibx` lives at renderer+0x20c0 (ini index k at 0x20c0+4k, parsed in `FUN_00520d90`); "state" = per-frame
cockpit state at `*(renderer+0x20b8)` (ownship X,Y,Z floats at +0,+4,+8; pitch/roll/heading radians at +0xc/+0x10/+0x14).
Colours are Windows COLORREF `0x00BBGGRR` unless written RGB(). MFD index: **0 = Left, 1 = Right, 2 = Middle**.

## 1. Geometry and compositing

- Each MFD is a **132 x 132** px DirectDraw surface (renderer+0x5d8, `FUN_0051cf10`), colour key **cyan
  RGB(0,255,255)** (0xffff00). `mfds.bmp` is loaded into a 264x924 surface (renderer+0x5f8, `FUN_00527ac0`), same key;
  `rwrsymb.bmp` into a 10x300 surface (+0x5fc).
- Panel: `f16panel.bmp` 1920x352 is cut into six 320-px-wide slices (+0x5b8..+0x5cc); slice i starts at panel row
  {MaskOffsetY1, MaskOffsetY2, 0, 0, MaskOffsetY2, MaskOffsetY1}[i] = {288,93,0,0,93,288} for the F-16.
- **Placement** (`FUN_00529300`): the finished MFD surface is BltFast'ed (src colour key) *into the panel slice*
  at panel pixel (OffsetX, OffsetY) from `[MFD]` (slice = OffsetX/320, x = OffsetX%320, y = OffsetY − slice top; split
  over two slices if it crosses 320). The rounded cyan tile corners therefore show the panel.
  F-16: Left occupies panel [722,854)x[146,278), Right [1083,1215)x[147,279). Middle inactive.
- **Screen position** of an MFD (`FUN_00529080`): `x1 = OffsetX − pan(+0x564) − 640`, `y1 = OffsetY + MainOffsetY(190)
  + vpan(+0x568)`. With pans 0: Left (82,336), Right (443,337) on the 640x480 screen. vpan is clamped ≥
  480 − MainOffsetY − PanelHeight = −62 (`FUN_0051db00`); its straight-ahead value comes from the view — UNCERTAIN.
- **Draw passes** (`FUN_00529080(pass, hdc, idx)`):
  - 0: compose the 132x132 surface (`FUN_00527ba0`): background tile + sprite-font label + range sprite; only when
    the page/mode changed (or forced by +0x2fc). Then blit into the panel (`FUN_00529300`).
  - 1: direct back-buffer pixels (radar MAP background only).
  - 2: click handling / hit tests (`FUN_00528e30`).
  - 3: sprite overlays (text, symbols) blitted straight to the back buffer at (x1,y1)+offset.
  - 4: GDI vectors on the back-buffer DC; clip rect (x1,y1)-(x1+131,y1+131); default pen +0x58c.
- **Bezel buttons (OSBs)** — not drawn by code (they are on the panel art); hit test `FUN_0051f2a0`, table
  `DAT_006583a0`. Strips relative to the MFD origin: top x22..107,y−16..0; bottom x22..107,y131..146; left
  x−16..−1,y21..107; right x132..148,y21..107. Button = coord/20 + base, only if coord%20 < 8, i.e. 8-px buttons at
  20,40,60,80,100. Ids: top 1–5, bottom 6–10, left 11–15 (0xb–0xf), right 16–20 (0x10–0x14). Actions `FUN_0051fed0`.
  Clicking inside the display area (+10..+122) makes that MFD own the mouse cursor (`FUN_0051fbf0`).
- **Button 6 (bottom-left, under "MENU") on every page** posts event 0x5b(value 8, mfd) → MENU page.
- Full-screen weapon MFD (view mode +0x1080 == 0xb; key "Full screen weapon MFD"): `FUN_00522250` loads
  `fsmfd/FsMfd.bmp` 640x480 with `data.ibx` corner rects, render rect (128,49)-(513,431), pen width 2 0xff00; used for the
  MFD showing page 5/6 (TV/FLIR).

### mfds.bmp (264x924, 24-bit) — source rectangles (table at `0x658cd8`, RECT l,t,r,b)

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
- (132,792)-(164,824) 32x32 "sun" circle → surface +0x5f4, recoloured to the HUD colour; a HUD sprite (`FUN_0052e520`).
- (164,792,172,796)/(164,796,172,800): upper/lower halves of the green diamond = list scroll arrows (NAV page).
- (132,840)-(217,845) digits+symbols and (132,850)-(262,855) A–Z: the 5x5 sprite font (below).
- (132+8i,845)-(140+8i,850), i=0..5: range numbers 5/10/20/40/80/160 (table `0x659298`).
- (132+6i,855)-(138+6i,862), i=0..3: 6x7 compass letters S,E,N,W.

## 2. Text and colours

- **`mfd.fnt` is never referenced by `iafjets.exe`** (no string; only `%s\Fnt\hud.fnt` and `key.fnt` are loaded, by a
  menu/log object `FUN_005190xx`, not the cockpit). mfd.fnt itself: face "MFD", 11 px tall, ascent 9, proportional
  (max 9 px). Treat as unused.
- **MFD text = 5x5 sprite font** built in `FUN_0051cf10` into two 224x5 surfaces (+0x5d0 green as drawn, +0x5d4
  recoloured to the HUD colour; +0x2744 selects which). Letter row → x=0..129, digit row → x=130..214. Char→x table
  `FUN_00523d70`: 'A'–'Z' and 'a'–'z' → 5·(c−'A'); '0'–'9' → 130+5·d; blank 180; '.' 185; ':' 190; '+' 195; '-' 200;
  '%' 205; anything else → 180 (blank). Advance 5 px, no gap (glyphs contain their own spacing).
  `FUN_00523f10(x,y,str,n)` left-aligned; `FUN_00523e00(x,y,…)` right-aligned (string ends at x). Page label is
  always at **(17,3)**.
- GDI objects (ctor `FUN_0051c9f0`): pens +0x58c 1px 0x00ff00 (MFD default, RGB(0,255,0)); +0x5a4 dashed 0x8000;
  +0x590 red 0xff; +0x594 blue 0xff0000; +0x598 0x95ffff; +0x59c white; +0x5a0 black; +0x2798 0x8000; +0x279c 0xff00;
  +0x27a0 0x360080 (purple); +0x27a4 0x2400ff (red). Fonts: Arial h10 w5 wt100 (+0x57c), Arial h12 w4 (+0x580),
  ANSI_VAR_FONT (+0x578). HUD colour table +0x285c indexed by +0x2888 (`FUN_0051ed80` rebuilds pens +0x584/+0x588):
  0x2400,0x3400,0x5400,0x6c00,0x8800,0xa400,0xe400,0xfc00,0xf0f4f8,0xf8,0xbcf8 (greens dark→bright, white, red, amber).
- Tile art colours: bright green RGB(0,255,0), dim green RGB(0,132,0)/(0,128,0), black background.

## 3. Pages (state+0x4fc+idx·4; dispatch `FUN_00527ba0`, passes 3/4 in `FUN_00529080`)

F-16 defaults (`FUN_00447530`): **Left = radar (2), Right = TSD (3)** (Right would be RWR if [PANELRWR] Active=0).

| Id | Page | Tile | Label | Code |
|---|---|---|---|---|
| 0 | NAV (waypoint list) | blank | – | `FUN_005298e0`, `FUN_0052a920` |
| 1 | stores/SMS | (0,132) | – | `FUN_0052ac10` |
| 2 | radar | per sub-mode | mode name | `FUN_005318b0` + helpers |
| 3 | TSD ("TACT") | (0,396) | – | `FUN_0052ff30` |
| 4 | damage | blank | – | `FUN_0052a0d0` |
| 5 | TV / EO weapon | (0,792) or blank | – | `FUN_00534eb0` |
| 6 | FLIR | (0,660) | – | `FUN_005350e0` |
| 7 | RWR | (132,0) | – | `FUN_0052f770` → `FUN_0052f950` |
| 8 | MENU | blank | – | `FUN_00529cd0` |
| 9 | ADI | blank | – | `FUN_005254c0` (only if [HORIZON] OnMfd; not F-16) |
| 10 | HARM | blank | "harm" | `FUN_00533d90` |
| 11/12/13 | placeholder | blank | "inventory"/"lt"/"comm" | label only |

**MENU (8)** — left labels at x=5, right labels right-aligned to x=124; black rect erases "MENU" at (14,124)
(extent UNCERTAIN). Buttons: 0xb "FLIR"→6 (only if MenuFlirOn and FLIR available, state+0x608); 0xd "stores"→1;
0xe "rwr"→7 (only if PANELRWR inactive → hidden on F-16); 0xf "radar"→2; 0x11 "NAV"→0; 0x12 "damage"→4;
0x13 "tactical"→3; 0x14 "adi"→9 (only if OnMfd → hidden on F-16). Label y = 22/42/62/82/102 for left 0xb..0xf,
42/62/82/102 for right 0x11..0x14.

**NAV (0)** — "ETA   :" at (72,124). 3 rows at y=42,62,82 from scroll index +0x27a8: "%1d" waypoint number
right-aligned at x=8; name (state+0x80+i·0x2c, ≤12 chars) at (12,y+1); GDI pass: "% 3dM" distance at x+77 and "%03d"
bearing at x+102, y+43+20·row; ETA "%02d %02d" right-aligned (117,124). Scroll arrows at (1,22)/(1,107); buttons
0xb/0xf scroll. Current waypoint (state+0x318) boxed (x1..x8). List auto-scrolls to keep it visible.

**Stores (1)** — stations = 0x1c-byte {type,count,name[20]} at state+0x3a0. Count/name positions: st0 (4,62)/(4,72),
st1 (4,42)/(4,52), st2 (4,22)/(4,32), st3 (24,3)/(17,12), st4 (64,3)/(57,12), st5 (104,3)/(97,12), st6..8 right-
aligned to 128 at y 22/32, 42/52, 62/72. MRM total (types 600/0x262) right-aligned (59,53); SRM (0x23a/0x244) (59,63).
GDI: "%dQnt" (1,94), "int%d" right-aligned (131,94), gun rounds "%03d" (68,85), "Fuel : %5dLB" (55,124). Selected
station (+0x4f0) boxed 15x8 (gun: 36x10 at (48,82)). Buttons: station select (0xd,0xc,0xb,1,3,5,0x10,0x11,0x12 →
stations 0..8, event 0x4c), 0xe/0xf quantity ±1 (0x4a), 0x13/0x14 interval ±10 (0x4b).

**Damage (4)** — "NAME GO"/"NAME NOGO" rows; left x=12: ENG (y10), [ENG R y19 twin only], FUEL 43, AILN 52, FLTC 61,
FLAP 70, GEAR 79, HUD 88, BRAK 97; right x=72: AB 10, [AB R 19], INS 34, RDR 43, RWR 52, WPNS 61, GUN 70, ECM 79,
A/P 88, ELCT 97, GNRT 106. Redrawn when state+0x550.. flags change.

### Radar (2) — sub-mode state+0x9fc

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

- Range sprite at (1,33) (modes ≥3 and TSD). Range R (NM) = {5,10,20,40,80,160}[state+0xa00 − 1] (`FUN_00520680`).
- Horizon bars (`FUN_00531b00`): polylines (−31,4)(−31,0)(−5,0) and mirror, centre (66,66), rotated by roll, shifted
  1 px/deg pitch, pitch clamped ±40 (blink every 300 ms beyond).
- Antenna carets (`FUN_005319e0`): v = clamp(ftol(val·106),0,106); azimuth: x=13+v, y117..120 + bar x11+v..16+v at
  y117 (val state+0xa04); elevation: y=13+v, x11..14 + bar at x14 (state+0xa08).
- Steer/bearing triangle (`FUN_00531d90`) to state+0x68 when |bearing|<60°: x = 66+bearing°, y from distance.
- **B-scope blip**: x = 66 + (az + state+0xa0c)·112/state+0xa1c; y = 115 − range_m/(R·16.5446) (16.5446 = 1853/112,
  i.e. R NM = 112 px); drawn only inside 8<x,y<124. Contacts (≤15, state+0x638.., stride 0x40): X +0x638, Y +0x63c,
  locked +0x650, tracked +0x654, id +0x65c, speed +0x660, aspect +0x664, az +0x668, range +0x670.
- BORE/ACM (`FUN_005337a0`): 3x3 box with diagonal per contact.
- LRS (`FUN_00532d20`): 5x5 box + inner 3x3; cursor = two vertical bars at mouse x±4, y±5; click on blip → event 0x2a
  (lock, id).
- TWS (`FUN_00533000`): untracked 5x5 box, tracked ~7 px filled disc; 4-px aspect stub quantised to 45°; hover text
  "%02d" (altitude kft and +0x674·10, UNCERTAIN which side).
- STT (`FUN_00532290`/`FUN_00532640`): disc + aspect stub; carets follow the target; range scale line x=121 y10..122
  with two envelope ticks (UNCERTAIN Rmin/Rmax) and "<" caret at y = 115 − r·112/(R·1853); text "%3dK" speed at
  (86,3), aspect "%2dL"/"%2dR" at (62,3), closure "%3dK" at (111, caret+8).
- GMT (`FUN_005338e0`): heading-up PPI, origin (66,109), R·1853/56 m/px; 3x3 boxes, locked = ±10 cross; mouse
  crosshair to the edges with 3-px gap and 5-px ticks at ±31.
- MAP (`FUN_00534380`): isr.bmp ground map (§4); label "NORM"/"EXP" at (60,3); contacts 3x3 box+diagonal,
  locked cross, designation cross, unrotated ownship triangle; click → 0x2a on contact or 0x2f with world x,y.

### TSD (3) — `FUN_0052ff30`
- Map = **`Emf\map.emf`**, not isr.bmp (load `FUN_00538c50`, draw `FUN_00538530`, clip (10,10)-(122,122)). 20
  POLYGON16 records, brushes 0xc7c7c8, 0x878889, 0x5b2222. EMF units: `u = ftol(ftol((X+166850)/819200·12601)·1.0071394)`,
  `v = ftol(ftol((1043816−Y)/1064960·16383)·1.0071394)` (floats `0x608518..0x608530`; ×1.0071394 meaning UNCERTAIN).
- **Heading-up**, ownship fixed at **(65,85)**. Scale: 1 px = 112·scale m, scale +0x2794 ∈ {10,20,40,80}, default 40,
  OSB 0xb/0xc = next/prev (`FUN_0052fd30`/`FUN_0052fe30`). World offset (ex = X−ownX, ny = Y−ownY):
  `x = 65 + (ex·C − ny·S)/k`, `y = 85 − (ex·S + ny·C)/k`, k = 112·scale, S/C = sin/cos heading (+0x272c/+0x2730).
- Fixed GDI (pen 0x58c, null brush): circle r=22 (43,63)-(87,107); ownship lines (60..71,81), (65,78..91), tail
  (63..68,91); outer ring r=44 (21,41)-(109,129) when SCL on.
- Compass letters S/E/N/W (sprites) on radius 18 around (65,85), rotating with heading.
- Right OSBs toggle (default all on): 0x10 SAM (+0x2784), 0x11 WPT (+0x2788), 0x12 MAP (+0x278c), 0x13 SCL
  (+0x2790); highlight box (111,20+20i)-(128,29+20i) when on.
- Waypoints (state+0x74/+0x78, stride 0x2c, count +0x308, current +0x318, type +0x9c): polyline in 0x58c; current
  filled 5x5 green (0x279c), type 5 (target? UNCERTAIN) red triangle (0x27a4)/purple 5x5 (0x27a0), others hollow
  5x5 dark green (0x2798).
- SAM sites (state+0x1140.., stride 0x14, count +0x1280): 3x3 box+diagonal and ring of radius r/k px.

### RWR (7) and panel RWR
- Symbols centred (66,66), radius 56 (`FUN_0052f950`); if state+0x588 ≠ 0 draws "Mal" at (101,3) instead.
- rwrsymb.bmp glyphs 10x10 at src (0,Y,10,Y+10), drawn at pos−5. Threat type → Y: 0x122→0 "2", 300→10 "3",
  0x136→20 "5", 0x140→30 "6", 0x14a→40 "8", 0x154→50 "H", 0x168/0x17c/0x186→60 (ship? UNCERTAIN), 0x15e→70 "A",
  150→80, 160→90, 180→100, 170→110, 120/200→120, 110→130, 100→140, 130/190→150, 140→160 (aircraft glyphs).
- Distance clamped to 37060 m → rim; heading-up; entries with +0xe88 blink at 300 ms.
- Panel RWR (`FUN_0052f810`): same drawer at [PANELRWR] Center (805,84) in panel coords, radius 28; background from
  the panel bitmap.

### HARM (10), TV (5), FLIR (6)
- HARM: emitters as one sprite-font char at (x−2,y−2), x = 66+(a50+pan)·112/range, y = 66−(…); status right-aligned
  at (114,3): "no source"/"In Range"/"No Range"; 8x8 box on selected; click → event 0x37.
- TV: tile used only when state+0x5e0 ≠ 0; status right-aligned (114,3): "RDY"/"TRA"/"TER"/"NO SOURCE"; zoom
  "%1d" right-aligned (11,33); "%3d" at (111,110) (UNCERTAIN meaning); seeker ticks at x = 66−56u / y = 66+56v.
- FLIR: zoom (11,33); "WIDE"/"SPOT" right (114,3); "LASER OFF"/"LASER ON" at (42,3); range NM "%3.1f" (or "XXX.X"
  ≥20) right-aligned (98,124); 5x5 blob at (66−56u, 66+56v). Video = screen rect MFD (10,10)-(122,122) rendered
  by the 3D view (`FUN_0051eec0`); cyan box is the colour key. OSB 0xb/0xc zoom (events 0x14/0x15), top 3 = laser
  (0x6a), top 5 = event 0x20 (UNCERTAIN).

## 4. isr.bmp / MAPFRAME georeference

- `cockpits.ibx [MAPFRAME]` read in `FUN_00520bd0` into ini+0x61c left, +0x620 top, +0x628 bottom, +0x624 right
  (F-16 file: 0, 1064960, 0, 819200; exe defaults 0x39080/0xaf500/0x3ef8a/0x75801).
- isr.bmp is 640x832 8-bit, loaded by `FUN_00539430` (rows flipped so row 0 = north), displayed as **green channel
  only** (palette entry i → 16-bit RGB(0,G_i,0)).
- **Exact code** (objdump `0x53456b..0x534600`, `FUN_00534380`), X/Y = ftol(state+0/+4):
  `col = (X + 166828 − left)/(right − left)·640`,  `row = (top − (Y + 21164))/(top − bottom)·832`
  ⇒ **col = (X + 166828)/1280, row = (1043796 − Y)/1280** — 1280 world units (m) per isr pixel on both axes.
- Compare TSD/map.emf: (X+166850), (1043816−Y); config DataXShiftPR −166850, DataYShiftPR 1043780. The ~20 m
  differences are in the exe as written.
- 640/832 = 655360/1024 and 851968/1024, so one isr pixel = 1024 PTT units and isr.bmp spans exactly the map.ptt
  theatre; MAPFRAME/PTT extent = 1.25. Hence, UNCERTAIN: `X = 1.25·ptt_x − 166828`, `Y = 1043796 − 1.25·ptt_y` (ptt_y
  from north).
- Radar MAP rendering (`FUN_005396d0`, MMX sampler `FUN_00539290`): window (15,15)-(116,109) = 101x94 px, shows only
  through the tile's cyan fan. NORM (state+0xa10 = 0): centre = ownship at window (50,94) = MFD (65,109), rotated by
  heading (heading-up). EXP: centre = designated point latched on entry, heading frozen, window centre (50,47), symbol
  origin (66,66). Sampling step `S = R·1853·832/((top−bottom)·94)` isr px per MFD px (94 px = R NM; 1853 m/NM at
  `0x6085b0`); outside the image → black. Symbol scale k = R·19.7128 m/px (`0x6085c0`).

## 5. Keys and events (keys.trx = 115 command names, one per line; bindings table `0x648010 + k·0x24`)

| keys.trx command | Default key | Event → effect |
|---|---|---|
| Activate TSD on MFD | T | 0x5a SET_MFD_SCREEN(3) |
| FLIR on/off | I | 0x5a(6) (needs FLIR, not TV) |
| Damage report | D | 0x5a(4) |
| Full screen weapon MFD | Z | 0x1f (only with EO/FLIR weapon) |
| Radar modes | Q | 0x24 cycle A-A 4→5→6→4 (LRS/TWS/ACM), A-G 7↔8 (GMT/MAP) |
| Radar on/AA/AG | R | 0x2b toggle A-A/A-G (restores last mode) |
| Radar standby | S | 0x2c → STBY |
| Boresight mode on | \ | 0x2d press / 0x2e release |
| Increase / Decrease radar range | . / , | 0x21 / 0x22 |
| Master modes / NAV mode on | M / N | 0x63 / 0x62(0) |
| Laser on/off | L | 0x6a |
| Next / Previous waypoint | W / Shift+W | 0x65 / 0x66 |
| Change HUD color | H | 0x7b (cycles +0x2888, UNCERTAIN) |

Event 0x5a(page) replaces Left unless Left shows radar, then Right; ignored if the page is already shown or page = 5.
Radar events first put the radar page on an MFD if none shows it. STT comes from a lock (event 0x2a). Master mode →
page (`FUN_00448970`): NAV→0; modes 1/2→stores; 3→radar; 4→HARM(10)/radar by weapon; 5→FLIR or stores; 6→TV
(names of modes 1–6 UNCERTAIN). Radar-page OSBs: 0xb range+, 0xc range−, top 1 = cycle mode (0x24).

## 6. HUD (brief)

- Main `FUN_0052f050`. Centre x = 320 − pan, centre y = MainOffsetY + vpan − [HUD] CenterY; gun cross and boresight
  from GunRetPositionY/BorePositionY; clip = centre + (−LeftBorder, −TopBorder, +RightBorder, +BottomBorder).
  Glass `F16hud.bmp` sliced by MaskOffsetX/Y/Y2 (`FUN_00527380`/`FUN_00527880`).
- Elements: text block at TxtOffX/Y (`FUN_0052d400`: "R %2.1f", "W%02d  %02.1f", "%3.1f MIN", "%2d SEC",
  "T %03d%", "AB %1d", "%4.1fG"); speed scale (`FUN_00536ba0`), altitude scale (`FUN_005366a0`), heading tape
  (`FUN_005361b0`), pitch ladder/FPM (`FUN_00537170`). Colour = HUD table above. HUD text also uses the 5x5 sprite
  font (HUD-coloured copy +0x5d4); `hud.fnt` is not used by the cockpit.

## Open questions
- Unreferenced tiles (132,132) "Debug", (132,264) LAS, (132,396) TWS, (0,528): leftovers?
- Straight-ahead vertical pan (+0x568) → exact on-screen MFD y.
- Meaning of the TSD ×1.0071394 factor and the ~20 m offsets between TSD, MAP and DataShift constants.
- state+0x68 (steerpoint vs ownship copy); contact +0x674; state+0x340/+0x398 (STT envelope/closure).
- FLIR OSB 5 (event 0x20); names of master modes 1–6; RWR aircraft glyph identities.
