# Jane's IAF front end (pre-flight menus), reverse-engineered spec

Source: `assets/ghidra/iafjets.c`, plus `objdump` of `install/iafjets.exe` for routines Ghidra skipped
(the message box `4e2cc0`, the button paint `4f1810`, the main-menu hover `4faa70`, the TSD paint
`4ff710`, the link opener `5013b0`, and MFC message maps read from `.rdata`). Paths are relative to
`install/resource/menu/` unless they start with `brief/`. Every colour is a Win32 COLORREF
`0x00BBGGRR`, written here as RGB. `UNCERTAIN` marks a guess.

## 1. Window and coordinate model

* The menu is a GDI/MFC window, **640×480**, centred on the desktop (`FUN_004e7560`). `bmp/back.bmp`
  is the full-screen frame. `bmp/back0.bmp` is the startup splash, drawn once in `FUN_004e11c0`.
* The **content area** is a child window at **(155,42), size 453×357** (`FUN_004e7560`:
  `0x9b,0x2a,0x1c5,0x165`). Each screen's header in `dat/<screen>.trx` repeats this as
  `155 42 608 399`.
* **All button coordinates in `.trx` files are screen coordinates (640×480)**, not panel-local.
  A button rectangle is `[x, y, x+w, y+h)` (`FUN_004e8f30` adds `w` and `h`).
* `.trx` screen header: `sName tTitle x0 y0 x1 y1 N`. `N` is the **number of panels** that follow,
  not a flag. `sName` selects `bmp/screens/<sName>.bmp` as the content background (`FUN_004f7290`).
  If that file is missing, the background is black. `sName` also selects `dat/<sName>.trx` as the
  list data. `tTitle` selects `bmp/titles/<tTitle>_0..2.bmp`.
* Panel line: `side pName x y count`, where `side` is `left`, `bottom1` or `bottom2`. Button line:
  `Label x y w h Kind [group]`. Kinds are `Push`=1, `Check`=2, `CheckGroup`=3 (followed by an int
  group id) and `Radio`=4. The button's action is looked up by its **Label** string (`FUN_004ebee0`).
* Screen ids (`FUN_004ebc30`): 0 Log, 1 Main, 3 Pref, 5 Ref, 6 Training, 7 Basic, 8 Combat,
  9/10 Jet, 0xb Camp, 0xc His, 0xd Fut, 0xe–0x13 His1–3Mis/Fut1–3Mis, 0x14 MC, 0x15 CType,
  0x16 TCP, 0x17 IPX, 0x18 NetMis, 0x1b NetAOW, 0x1c SpMMis, 0x1d Side, **0x1e TSD**, **0x1f Arm**,
  0x20 FlyTSD (in flight), 0x21 Pref (in flight), 0x22–0x26 Deb, 0x27 Jump.

## 2. Static frame pieces (paint `FUN_004ea910`, composited into an off-screen copy of back.bmp)

| piece | art | screen pos | notes |
|---|---|---|---|
| title tab | `titles/t<title>_2.bmp` 119×26 | **(485,16)** | `FUN_004e9dd0`. On entry it shows `_0,_1,_2`, 50 ms apart. On exit it shows `_2,_1,_0`, then the back.bmp region is restored. |
| left panel | `palettes/p<name>_0.bmp` 141×414 | (0,35), from the trx | masked: `misc/maskleft.bmp` (1-bit, 141×414) drawn SRCAND, then the panel drawn SRCPAINT |
| upper clip | `misc/upclip5.bmp` 78×29 | (17,18) | resting frame |
| lower clip | `misc/lowclip5.bmp` 97×47 | (17,433) | also contains the BACK plate. `lowclipc5` (blank plate) replaces it on screens 0, 1, 0x22–0x27 and on a multiplayer client (`FUN_004e8a80`). |
| bottom1 panel | `palettes/p<name>_0.bmp` (e.g. pformation 360×62) | (115,418) | mask `misc/maskbottom1.bmp` 357×62 |
| bottom2 panel | `palettes/ptools_0.bmp` 109×63 | (494,418) | mask `misc/maskbottom2.bmp` 108×62 |

**Panel transitions** (`FUN_004e9f40`; hide before the new trx is loaded, show after):
* The left panel slides horizontally (`FUN_004ea510`), revealed from its right edge.
  Clip animation frame = `offset/50` (`upclip1..5`, `lowclip1..5`); 1 is closed, 5 is open with the
  yellow-black stripes.
* The bottom panels slide vertically (`FUN_004e9fa0`, `FUN_004ea260`).
* The slide duration equals the length of the wav that plays with it. Left panel shown:
  `PaletteOut.wav`. Left panel hidden: `PaletteIn.wav`. Bottom panels, both ways: `PaletteOut.wav`.

## 3. Buttons

### 3.1 Panel buttons (palette art; labels are baked into the bitmaps)
Each panel loads `palettes/p<name>_0..3.bmp`, full-panel images. Drawing a button copies its
rectangle from the image for its state (`FUN_004eac10`):
* `_0` = **normal / idle**
* `_1` = intermediate frame, used only during the press and release animation
* `_2` = **pressed / checked** (lit green LEDs on the TSD)
* `_3` = **disabled** (clamps drawn over the button)

The prompt's reading "state 0 highlighted" is wrong.

* Push, mouse down (`FUN_004e7f40`/`4ead70`): frames `_1`, then `_2`. `ButtonIn.wav` plays, and each
  frame is held for a time derived from the wav length.
* Push, mouse up: frames `_2,_1,_0` with `ButtonOut.wav`. The action runs on release, and only if the
  cursor is still inside the button (`FUN_004e8500`). Dragging out of the button releases it; dragging
  back in presses it again.
* Check: stays at `_2` while on.
* **Buttons never change art on hover.** Hover only calls the content window (§5).

### 3.2 Bottom-bar buttons (child windows, class `FUN_004f13b0`, 4 images `<prefix>_0..3`)
| button | art | pos | size | when |
|---|---|---|---|---|
| BACK | `misc/backbut_0..3` | **(0,458)** | 114×22 | disabled (shows `_3`, a blank plate) on Log/Main/Debrief/Jump and on MP clients |
| MAIN | `misc/mainbut_0..2` (vertical "MAIN") | **(605,421)** | 35×59 | every screen except Log and Main |
| QUIT | `misc/quitbut_0..2` | (605,421) | 35×59 | Log (0) and Main (1) |

Positions come from `.rdata` `0x60242c` (BACK) and `0x602430` (MAIN); the objects are created in
`FUN_004e7560` and their art is chosen in `FUN_004e8a80`.

Paint (`4f1810`): `_0`, or `_3` when disabled. Press animation (`FUN_004f1b30`): `_0→_1→_2` with
ButtonIn; release `_2→_1→_0` with ButtonOut. There is no hover state. `logbut_*` 114×22 belongs to
the Log screen (not traced).

* **BACK** (`FUN_004eb990`) goes to the parent screen:
  * Pref/Ref/Training/CType → Main
  * Basic/Combat → Training
  * Jet 9 → Basic; Jet 10 → Combat
  * His/Fut → Camp; mission lists → their war
  * TSD → the previous screen, after the dialog "Are you sure you want to quit the mission?" (Yes/No).
  * On Arm, BACK has no case, so it does nothing (UNCERTAIN; use the TacticalDisplay button).
* **MAIN** (`FUN_004eb7d0`) goes to Main. From TSD or Arm it first asks msg 8 (Yes/No).
* **QUIT** sends WM_CLOSE to the frame. A "quit the game?" (msg 7) confirmation is UNCERTAIN.

### 3.3 Message box (`CIAFMenuMsgBoxDlg`, `FUN_004e2b40`/`4e2cc0`, called via `FUN_004e2790(msg,…,type)`)
* Background: `misc/mbgback.bmp` 320×140.
* Text: `txt/msgs.trx` line `msg` (0-based). Arial size-param 11, weight 700, white, `DT_CENTER|DT_WORDBREAK`,
  in rect `(10,20,W-10,H-50)`.
* Buttons: `misc/mbg<X>_0/_2` 60×30. The labels (YES NO OK CANCEL DEBRIEF CONTINUE EXIT) are baked
  into the art; **"CONTINUE" is `mbgfly`**. Top edge `y = H - bh*5/3 = 90`.
  * 1 button: `x = W/2 - bw/2 = 130`.
  * 2 buttons: `x = W/2 - bw - bw/4 = 85` and `W/2 + bw/4 = 175`.
* Types:
  * 0 OK
  * 1 OK+Cancel (loads `MBGCancel`, which is not in the install, UNCERTAIN)
  * 3 Yes/No/Can
  * 4 Yes/No
  * 0x10000 Debrief+Fly (CONTINUE)
  * 0x20000 Debrief+Fly+Exit
* **DEBRIEF/CONTINUE/EXIT appear only in the post-mission box. They are not part of the pre-flight flow.**
* Pre-flight uses msg 8 (Yes/No) and msg 25 "Choose a jet before flying." (OK).

## 4. Fonts and text colours
* All menu text is **Arial**, from `FUN_004ed600(p, …)`. That function measures
  `"ABC…XYZabc…xyz"` at `lfHeight=-100` to get `cy`, then creates
  `lfHeight = -round(cy*p/100 + 0.5)` (constants `0x602660` = 0.01, `0x602664` = -0.5). With
  Arial, `cy≈112`, so p=10 → about 11 px em and p=11 → about 12 px (UNCERTAIN: exact `cy`).
* **`fnt/cr0..cr4.ttf` (Gill Sans variants) are only `AddFontResource`d for the credits sequence**
  (`FUN_004e11c0` around `4e1700`, removed at `4e179f`). No menu screen uses them.
* Button labels are bitmaps (palette, misc, mbg art). They are not text.
* Mission/course list (`FUN_00508590`), transparent background:
  * title: Arial p11 weight 500, RGB(0,255,0), `DT_SINGLELINE|DT_BOTTOM`
  * description: Arial p10 weight 400, `DT_WORDBREAK`. RGB(0,128,0) when not highlighted,
    RGB(0,255,0) when highlighted.
* TSD overlay text: Arial p10 weight 600, white. MP player names are yellow RGB(255,255,0).
  Ruler text is red RGB(255,0,0).
* Briefing RTF: its own fonts (Arial, `\cf1` white); rich-edit background RGB(94,94,104)
  (`EM_SETBKGNDCOLOR 0x685e5e`, `FUN_0050be40`).
* `II PAUSE` in-flight text: RGB(0,255,0) at (30,450) (`FUN_004e7a90`), for reference.

## 5. Content windows

### 5.1 Main menu (`FUN_004fa8c0`, hover `4faa70`)
The background is `screens/smain.bmp` (457×357, 24-bit). **Hovering** a left-panel button replaces
the whole content with `main/main_N.bmp`:

| N | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| button | Training | Campaigns | Jump_In (art "SCRAMBLE") | MultiPlayer | MissionCreator | Reference | PilotRecords | Preferences |

Moving off a button restores smain. Hover is driven by the frame's MOUSEMOVE (`4e7f40`) over any
**enabled** panel button. It calls content vtable `+0xd0(panel, idx, on)`.

### 5.2 List screens (Training, Basic, Combat, Jet, campaigns…; class `FUN_00508590`)
* Backbuffer = `mis/mis_0.bmp` (454×357; `mismp_*` for NetAOW).
* Every row's rectangle is copied from **`mis_1`** (the normal row). Titles and descriptions are
  pre-rendered into both `mis_1` and `mis_2`.
* **Highlight = the row rectangle copied from `mis_2`** (`508fe0`). It happens **only while the
  mouse hovers the same-named left-panel button**; the row is found by matching the row name to the
  button label.
* Clicking a row does nothing: LBUTTONDOWN maps to the empty `FUN_004eb760`. **Selection is made by
  pressing the panel button.**
* `s<screen>.trx` rows: `id f1 f2 f3 f4 Name  rx ry rw rh  tl tt tr tb tKey  dl dt dr db dKey`.
  * Coordinates are content-local.
  * The row rect is x,y,w,h. The title and description rects are left,top,right,bottom.
  * The text comes from `txt/mis/<key>.trx`, first line.
  * `id` becomes the mission id (`DAT_00836c88`) when the button is pressed (`508f30`).
  * If `f2`≠0 (the Jet list), pressing the button also starts **loading the mission**
    (`FUN_004ec6a0`): content shows `mis/wait.bmp` and the music fades out over 6 s.
  * Rows are disabled (button `_3`) for missions whose prerequisite is not passed (`FUN_004efcd0`, `4f5440`).
  * `FUN_005082b0` disables certain jets per mission (e.g. id 314, 322, 323, 325).

### 5.3 Screen flow (`FUN_004eaf50`, button-release dispatcher)
* Main → **Training** (6), a list of 2 courses.
* **Basic_Course** → Basic (7). Combat_Course → Combat (8).
* Any mission button (e.g. Takeoff, id 311) → **Jet** (9 or 10), a list of 7 aircraft.
* Jet button → load the mission (Wait.bmp) → **TSD** (0x1e).
* On TSD:
  * `Arm` → **Arming** (0x1f). Arming's `Fly`/`TacticalDisplay` handlers are in `FUN_005057e0`.
  * **`Fly`** (`FUN_00502c90`): if a flight (formation) is selected, the menu closes with exit code 2
    and flight starts. Otherwise msg 25 is shown.
* **There is no CONTINUE button in pre-flight.**
* The briefing window opens automatically when the TSD opens (§6).

## 6. Briefing window (TSD child)
* Created by `FUN_00502ec0`. It is called from TSD `OnCreate` (`FUN_004ff4e0`) when the Briefing
  flag `DAT_00836cd4` is set.
  * The flag defaults to 1 (`FUN_004efc60`, reset on every mission load).
  * It is later set to "the briefing file exists".
  * The TSD's **`Briefing` Check button** toggles the window. Unchecking destroys it and every link
    window.
  * The button is disabled when the file is missing (`FUN_00502e40`).
* File: `<BriefingPath>\Txt\<missionId>.rtf`, i.e. **`brief/txt/<id>.rtf`**. `BriefingPath` is a
  registry value, `4e030f`.
* Position/size (TSD client coordinates): **(0,0), width = 2·453/3 = 302, height = 357**. Style
  `0xb0000` = close + minimise + maximise buttons.
* Tab title art: **`framewnd/brief_t.bmp`**.
* Contents: a RichEdit (`RICHED32`) loaded with `EM_STREAMIN SF_RTF`. The first `<header>`
  (case-insensitive) is replaced by `"<rank> <callsign>"` (`DAT_00836c98`, `DAT_00836cac`; ranks are
  "Second Lieutenant"…"General").
* **Links** (`FUN_0050c880`): text that is underlined and yellow RGB(255,255,0) is clickable. Hovering
  it shows `Cur/Point.cur`. Clicking takes the underlined run and matches it by name against
  **`<same path>.brl`** (records of 516 bytes: `name[256], int type, path[256]`; paths are relative to
  the install root). The TSD then opens a window by type (`FUN_005013b0`, W,H = TSD client):

| brl type | content | window | pos, size | TSD slot |
|---|---|---|---|---|
| 0 | another RTF (e.g. the **lesson** `\Brief\Text\311_1.rtf`, war history `67.rtf`) | brief_t frame | (W/3, H/2), 2W/3 × H/2 | +0x140 |
| 1 | UNCERTAIN (`FUN_0050cf80`), no records | frame | (W/2,H/2), W/2×H/2 | +0x148 |
| 3 | bitmap (e.g. **instructor card `\Brief\Bmp\card.BMP`**, diagrams) | `FUN_0050d310`, style close+min | (W/2, 0), W/2 × H/2 | +0x144 |
| 2 | 3D model `.x` (aircraft/SAM) | **`obj_t`** frame, 3D view (`FUN_005169f0`) | (12,16) 415×260 | +0x150 |
| 5 | target: `\Brief\Tar\<id>_N.txt`, whose first line is an object name looked up in the mission (`FUN_00439bb0`) | **`targ_t`** frame (`FUN_005164f0`) | (22,16) 406×322 | +0x14c |

* A slot that is already open is reused and reloaded. The 3D-model window and the target window are
  mutually exclusive.
* **There are no Brief/Objective/Target tabs.** `brief_t`, `obj_t` and `targ_t` are the tab-title art
  of three separate floating windows. `chat_t` is the multiplayer chat window (`FUN_004f6ab0`).
* The instructor name in training (e.g. "Jonathan" in `txt/311.rtf`) is a type-3 link to `card.bmp`.
  `brief/text/3xx_N.rtf` lessons are reached through type-0 links, and have their own `.brl`.
  Nothing in the exe references `3xx_0.rtf` directly (UNCERTAIN whether it is shown anywhere).
* Scrolling: a custom vertical bar at the right edge of the rich edit (x = clientW−10, full height):
  * track `framewnd/scroll.bmp` 10×480
  * thumb `slider.bmp` 10×23
  * arrows `slupb_0..2` and `sldownb_0..2` 10×8
  * range = `EM_GETLINECOUNT`
  * keyboard (KEYDOWN) and VSCROLL are handled
  * step sizes UNCERTAIN

## 7. Floating frame window construction (`FUN_00509a40`, paint `FUN_0050a9f0`)
* Black background. Min 150×100, max 640×480.
* Top and bottom borders: `horzborder.bmp` (640×4), **centre-cropped**: source x = 320 − cx/2, drawn
  at y=0 and y=cy−4.
* Left and right borders: `vertborder.bmp` (5×420), centre-cropped vertically, drawn at x=0 and cx−5.
* Corners `crnr_ul/ur/bl/br` (5×5) are drawn last, at the four corners.
* **Title bar** (child, `FUN_0050ae00`): at (5,4), width = clientW−10, height 11.
  * Image: `title_a.bmp` when active, `title_na.bmp` when inactive (both 640×11).
  * The tab-title bitmap (e.g. brief_t 43×11) is pre-blitted into both at x=(640−w)/2
    (`FUN_0050b180`).
  * The bar shows the 640-wide image cropped with source x = (640 + buttonsW − barW)/2.
* Title-bar buttons, right to left, 1 px apart, each 9×8, `_0/_1/_2` states:
  * `closebut` (style 0x80000) at x = barW−1−9
  * `maxbut` (0x10000) 10 px further left
  * `minbut` (0x20000) 10 px further left (only `minbut_0/_2` exist)
  * `normbut_*` replaces max while maximised (UNCERTAIN)
* Activation: a click anywhere raises the window (SetWindowPos top) and sends msg 0x54a to switch
  to `title_a`. Others switch to `title_na` (`FUN_00509ef0`, `50ba50`). Dragging the title bar moves
  the window.
* `mvcrnr*` / `mvbrdr*` (3 px) are the resize/move outline drawn while dragging (`FUN_0050db8b`;
  details UNCERTAIN).
* `framewnd/back.bmp`, `logo.bmp`, `tvw_on/off.bmp` and `buttonfordialogue.bmp` belong to other
  windows (chat, 3D viewer); not traced.

## 8. TSD map (`FUN_004fe280` ctor, paint `4ff710` = map `4ff7c0` + overlay `4ff9e0`)
* **The map is an EMF vector metafile**, not isr.bmp or terrain: `menu/emf/82.emf`. Missions
  110–119 use `67.emf` and 120–129 use `73.emf` (1967 and 1973 maps).
  * Overlays: `emf/grid.emf` when **Grid** is on; `emf/text.emf` when **Text** is on.
    * Text records (EMR_EXTTEXTOUTW) are re-issued as `TextOutA` at their EMF position (`4ff740`), so
      the labels do not scale.
* World extent is **454×590** map units (`0x6040e0/e4`). The metafile is played into
  `(-sx·z, -sy·z, 454z−sx·z, 590z−sy·z)`, where `z` is the zoom and `(sx,sy)` the scroll.
* **Default zoom = 1.0**, scroll (0,0) (`FUN_004efc60`). The view is then centred on the selected
  flight (`FUN_005043e0`).
* Zoom_In: ×1.5, max 32. Zoom_Out: ×2/3, min 1. Both keep the selected unit, or the view centre,
  fixed (`5019b0`). Each button is disabled at its limit.
* Scrollbars (screen coordinates):
  * V: `tsd/vscroll.bmp` 10×356 at (608,42); thumb `vslider` 10×75; `vslupb`/`vsldownb`
  * H: `hscroll.bmp` 462×10 at (146,399); thumb `hslider` 74×10
  * Dragging the map with `Cur/move.cur` and `grab.cur` pans it (UNCERTAIN).
* **Waypoints** (Waypoint check), one route per flight 1..4, with the selected flight drawn last:
  * a filled circle of radius 10 (pen PS_INSIDEFRAME 2 px and a brush in the flight colour)
  * the 1-based number, centred at (x, y+4) (TA_BASELINE|TA_CENTER), white
  * lines to the previous waypoint only if the gap is more than 20 px
  * flight colours: 1 Alpha RGB(226,0,180), 2 Bravo RGB(4,178,39), 3 Charlie RGB(0,82,250),
    4 Delta RGB(215,134,1), 5–6 white
* **Units** (`FUN_005035c0`), drawn with a plain copy (no transparency):
  * Ground icons are 27×34 with two rows of 17. The top row (blue) is used for sides 0 and 1, the
    bottom row (red) for side 2. Types: 2 ship `icshp`, 3 structure `icstr` (`icairport` when the
    class is 0x23), 4 vehicle `icveh`, 5 SAM `icsam`, 6 AAA `icaaa`.
  * Aircraft use `icair` 216×63: 8 columns of 27 px (heading/45°, 0 = north, clockwise) × 3 rows of
    21. Row 0 blue, row 1 red for side 2, row 2 light blue when side ≤1 and field `[0x18]==0`
    (UNCERTAIN meaning).
  * Aircraft in flight 1..4 get a 2 px outline rectangle in the flight colour.
  * The selected unit gets `icselair`/`icselveh` (`FUN_00503ae0`).
  * The 18 filter checks (Aircrafts/Vehicles/Ships/SAM/AAA/Structures/Airports × side 1/2) gate the
    drawing (`FUN_00503130`).
* Top-left text: two lines at (4,4) and (4, lineH+6), from `DAT_006947b0`, `DAT_006948b0` and
  `this+0x1204`. The content is UNCERTAIN (probably mission name, date/time).
* A ruler drag draws a line and arrow in red with `"%.2f NM"` and bearing `"%03d T"` (m × 0.00053996).
* Defaults (`FUN_004efc60`): all 18 unit filters on, and Text, Waypoint, Grid and Briefing on.
  Stored in `DAT_00836cd4..d18`.
* Formation panel `pformation` (bottom1): Alpha–Delta CheckGroup selects the player's flight
  (`DAT_00836d1c`). In single-player it is pre-set from the mission.
* Arm is disabled when no valid flight is selected (`FUN_00504330`).

## 9. Sounds (`menu/wav`)
* `Menu_M.WAV` is the menu music. It starts on entering any screen except TSD, Arm, FlyTSD and
  in-flight Pref, if not already playing (`FUN_004e8a80`). It fades out over 6000 ms when a mission
  loads (`FUN_004ec6a0`).
* `ButtonIn.wav` plays on button press, `ButtonOut.wav` on release (`FUN_004e11c0`, globals
  `0083644c/50`).
* `PaletteIn.wav` and `PaletteOut.wav` play with the panel slides (§2).
* `credits.wav` plays with the credits.
* `menu_mo.wav` and `menu_mo.pk` are not referenced by name in the exe (UNCERTAIN).
