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
* **QUIT** is handled by the same function as MAIN, `FUN_004eb7d0`, and **does ask for confirmation**.
  * On screens 0/1 it first checks the content window's "can leave" query (vtable `+0xd8`). It then
    sends `WM_CLOSE` to `GetParent(frame)`, the main application window.
  * That window's message map (`.rdata 0x6017e0`) routes WM_CLOSE to **`4e1110`**. If the menu frame
    (`DAT_00836444`) or the game window (`DAT_00694920`) exists, `4e1110` shows **msg 7 "Are you sure
    you want to quit the game?"** as a **Yes/No** box (type 4, reply message `0x556`). Otherwise
    WM_CLOSE is swallowed: there is no default close.
  * `0x556` → **`4e1660`** acts only on IDYES (lParam 6): engine command 0x74 (unload),
    `FUN_004d7670(0)`, `FUN_004e7c40`, then the credits sequence if `FUN_00542e60()` ≠ 0 (cr0..4.ttf,
    credits.wav; condition UNCERTAIN), `FUN_00542260`, DestroyWindow (vtable `+0x60`). NO does nothing.
  * Alt+F4 / system close reach the same OnClose. msg 7 is also used by the in-flight pause menu,
    item 5 (`FUN_004da920`, same reply message `0x556`).

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

### 5.4 Navigation tables (decoded)
Button-release dispatcher `FUN_004eaf50`. Labels are compared ignoring case, spaces and `_`.

| screen | button → screen |
|---|---|
| Main (1) | Training→6, Campaigns→0xb, Preferences→3, MissionCreator→0x14, PilotRecords→0 (Log), Reference→5, MultiPlayer→0x15, Jump_In→random scramble mission 0x191–0x197 (message box "Scramble Mission") |
| Training (6) | Basic_Course→7, Combat_Course→8 |
| Basic (7) / Combat (8) | any mission button → Jet 9 / 10 |
| Jet (9, 10), His1–3Mis, Fut1–3Mis (0xe–0x13) | load the mission → TSD 0x1e (single player). **Campaign missions skip the Jet list.** |
| Camp (0xb) | Historical→0xc, Future→0xd |
| His (0xc) | Six_Day_War→0xe, Yom_Kipur_War→0xf, Lebanon_War→0x10 |
| Fut (0xd) | Syrian_Front→0x11, Iraqi_Front→0x12, Lebanese_Front→0x13 |
| TSD (0x1e) | Arm→0x1f |

BACK (`FUN_004eb990`): 3/5/6/0x15→Main; 7/8→6; 9→7; 10→8; 0xb→Main (single player); 0xc/0xd→0xb;
0xe–0x10→0xc; 0x11–0x13→0xd; 0x14→Main; 0x16/0x17→0x15; TSD→previous screen (msg 8 Yes/No first;
mission 0x213 → MC).

**Jet list** (`FUN_00508470` sets the aircraft id `DAT_00836c90`; the labels were read from the exe
`.rdata`): Mirage 6, Kfir 5, F4 2, F42000 3, F15 0, F16 1, Lavi 4. Aircraft id → cockpit: see
docs/cockpit.md.

Jets disabled per mission (`FUN_005082b0`; rows 0x11c bytes apart in the list object):

| mission | disabled |
|---|---|
| 314 Basic Air To Air | Mirage, Kfir |
| 322 Advanced Air To Ground | Mirage, Kfir, F15 |
| 323 Guided Weapon | Mirage, Kfir, F4, F15 |
| 325 Multi Force Strike | Mirage, Kfir, F4, F16, Lavi |

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
  * step sizes: see §8.1

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
* `mvcrnr*` / `mvbrdr*` (3 px) are the bevel around a 3D viewport (`FUN_0050db8b`/`50e9a8`, §11),
  not a resize outline.
* `logo.bmp` belongs to the 3D-model window (§11) and `tvw_on/off.bmp` to the target window (§10).
  `framewnd/back.bmp` and `buttonfordialogue.bmp` belong to other windows (chat?); not traced.

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
* Zoom_In: ×1.5, max 32. Zoom_Out: ×2/3, min 1. Both then **centre** the selected unit (or keep the
  view centre) (`5019b0`, see §8.1). Each button is disabled at its limit.
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
  * The 14 filter checks (Aircrafts/Vehicles/Ships/SAM/AAA/Structures/Airports × side 1/2) gate the
    drawing (`FUN_00503130`).
* Top-left text: mission title at (4,4); mission clock `HH:MM:SS` at (14, lineH+6) (decoded in §8.1).
* A ruler drag draws a line and arrow in red with `"%.2f NM"` and bearing `"%03d T"` (m × 0.00053996).
* Defaults (`FUN_004efc60`): all 14 unit filters on, and Text, Waypoint, Grid and Briefing on.
  Stored in `DAT_00836cd4..d18`; flight `d1c`=0, zoom `d20`=1.0, scroll `d24/d28`=0.
* Formation panel `pformation` (bottom1): Alpha–Delta CheckGroup selects the player's flight
  (`DAT_00836d1c`). In single-player it is pre-set from the mission.
* Arm is disabled when no valid flight is selected (`FUN_00504330`).

### 8.1 TSD data mapping (decoded)

**Data source.** The TSD does not read the .mis. After the mission loads, `FUN_004d21f0` (object
`0x681878`, called from `FUN_005161e0` on every paint) walks the spawned engine objects and fills:
* a unit table at `0x681880`: 0x70-byte records, count `DAT_00689bc0`, maximum 300;
* a flight table at `0x689bc8 + n·0x370`.

So the TSD shows what the spawner created from the mission (docs/formats/mis.md).

#### World → map units → pixels (`FUN_004ff5a0`; inverse `FUN_004ff650`)

```
mx = (X − X0) · 454 · kx / W          my = 590 − (Y − Y0) · 590 / H
px = z · (mx − sx)                    py = z · (my − sy)
```

| const | value | source |
|---|---|---|
| X0 | −166850 (= terrain `DataXShiftPR`) | `.rdata 0x604300` |
| Y0 | −21144 | `0x604308` |
| kx | 1.0071394 (inverse uses 0.9929112 at `0x60430c`) | `0x604304` |
| W | 819200 = 0 − (−819200) | `0x6042f0`, stored `0x839174` by `4fe220` |
| H | 1064960 = 0 − (−1064960) | `0x6042f4`, stored `0x839170` by `4fe250` |
| 454, 590 | map extent in map units | `0x6040e0/e4` |

* The EMF is played into the rect `(−sx·z, −sy·z, 454z − sx·z, 590z − sy·z)`.
* `FUN_004ff5a0` returns `(mx − sx, my − sy)`. `FUN_005161e0` caches that per unit at
  `this+0x8a4+8i` and per waypoint at `this+0x16c+0xa8·f+8i`. Drawing multiplies by `z`.
* Unit icon top-left = `(trunc(z·(mx−sx) − w/2), trunc(z·(my−sy) − h/2))`, where `w/2` and `h/2`
  are integer halves (`__ftol` truncates). The icon is therefore centred on the unit.
* Scroll clamp (paint `4ff7c0`): `0 ≤ sx ≤ 454 − Wc/z` and `0 ≤ sy ≤ 590 − Hc/z`, where
  Wc×Hc is the content client size (453×357).

**Worked example: takeoff.mis Player1, X=356226, Y=600689.** It maps to **(291.96, 245.50)**.
* For comparison, the Ramat David spawn point (356404, 602402) maps to (292.06, 244.55), and the
  Alpha waypoint (347870, 602383) maps to (287.29, 244.56).
* text.emf places "SEA OF GALILEE" at about (308, 231) after scaling its 478×620 bounds to 454×590.
  This is 21 map units east and 14 units north of the RD point, about 1.79 km per map unit. The real
  offset is about 38 km east and 17 km north, so the placement is consistent.
* Other checks: Tel Nof → (267.8, 301.0), Ramon → (270.3, 350.5).
* On entry (z=1), centring gives `sx = trunc(291.96) − 453/2 = 65`, clamped to 1, and
  `sy = 245 − 178 = 67`.
* The F-16 icon (27×21) is drawn at (277, 168). The waypoint "1" circle is centred at (286, 177).

#### Unit record (`FUN_004d21f0`; runtime descriptor `obj+0x30`, state `obj+0x1c`)

| rec | meaning | mission / bdb origin |
|---|---|---|
| [0] | object class | bdb Objects `0x5aa` of entity `0x2c6` (28 Controlled aircraft, 3 Aircraft, 2 Helicopter, 5 Armed vehicle, 6 Vehicle, 8 Radar SAM, 9 IR SAM, 10 Gundish, 11 Ground radar, 12 Building, 13 Target building, 14 Tree/marker, 15 Boat, 16 Armed boat, 18 Fire sensor) |
| [1] | type code | bdb Objects `0x5b4` (100 F16, 110 F15, 120 F4, 130 Kfir, 140 Lavi, 150…220 MiGs/bombers, 230/240 transports, 250–280 vehicles, 290–340 SAMs, 350/360 AAA, 370–390 boats, 400 building, 410 strategic, 420 bridge, 430 road, 440 taxiway "Airport", 450 runway, −1 none) |
| [8] | unique object id (`desc+0x18`); `DAT_006504d4` = selected unit | runtime id (UNCERTAIN: equals entity `0x1e`) |
| [9] | TSD icon class | from [0]: 2,3,0x1c→1 aircraft; 0xf,0x10→2 ship; 0xc,0xd,0x1d,0x1e→3 structure; 5,6→4 vehicle; 8,9→5 SAM; 10→6 AAA. **Any other class gets no record.** |
| [10],[11] | world X, Y | entity `0x2e4`, `0x2ee` |
| [0xd] | heading, float radians | entity `0x302` (UNCERTAIN: runtime yaw equals compass heading) |
| [0xe..] | object name, 20 chars | shown only for runways |
| [0x15] | flight number (formation `0x3f2`) of the formation that lists this object as a member | `CDMEFormationItem` members `0x41a` |
| [0x16]/[0x17] | object is member 0 / member 1 of its flight | |
| [0x18] | **object is its flight's current leader**: member 0 if alive, else member 1 (`FUN_004d2eb0`) | |
| [0x19] | side (`desc+0x1c`) | entity `0x2d0` |
| [0x1a] | SAM ring radius (world units), set only for class 8: type 290/340 → 37080, 300 → 16686, 320 → 22248, 310/330 → 0 | hard-coded |

**Records created.** An object gets a record only if all of these hold:
* its state `+0x44 ≠ 0`, `+0x14 ≠ 0` and `+0xc ∉ {4,5}`;
* its class is one of those listed for [9].

The state fields:
* `+0x44` is initialised from spawn slot `[0x43]` = **entity `0x35c`**, the "known to player" flag.
  It is set to 1 later when the player's radar detects the unit (`FUN_004aea40` @4af141).
* `+0x14` is 1 for aircraft and 2 for surface units (from entity `0x320`).
* `+0xc` values 4 and 5 are dead/removed states (UNCERTAIN).

Units that are never shown:
* markers (civilhouse audio markers have `0x35c`=0);
* sensors (class 18);
* ground radars (class 11);
* trees and parachutes (class 14);
* player slots that were not spawned. Only slots marked used in the session slot table are spawned,
  `FUN_0058cb50` @58d23c (UNCERTAIN for SP; takeoff's Player2..7 are at −1,−1).

**Drawing** (`FUN_005035c0`). Record i is drawn only if `FUN_00503130` passes:
* icon class 1..6 × (side==1 → the `…1` filter, else → the `…2` filter);
* icon class 3 is split: category 0x23 (type 450 runway) → `Airports1/2`, else `Structures1/2`.

Bitmap choice (in `FUN_005035c0`; note `FUN_004f54a0` is the type → category-index function of
"Selected-unit label" below, not the bitmap chooser):

| icon class | bitmap |
|---|---|
| 1 aircraft | `icair` |
| 2 ship | `icshp` |
| 3 structure | `icairport` for type 450, else `icstr` (taxiways, type 440, use `icstr`) |
| 4 vehicle | `icveh` |
| 5 SAM | `icsam` |
| 6 AAA | `icaaa` |

Row choice:

| side | ground icons | aircraft |
|---|---|---|
| 0 or 1 | row 0 (blue) | row 0 if [0x18]=1 (**flight leader**); row 2 (light blue) for wingmen and aircraft in no flight |
| any other | row 1 (red) | row 1 (red) |

* `icair` column = `trunc(deg(heading mod 2π)) / 45`. The art columns are 0 N, 1 NE, 2 E … 7 NW,
  clockwise. The value is **floored**, so a 150° heading uses column 3 (SE).
* Class 8 units also get a hollow white ring of radius `trunc(trunc(r)·454/819200)·z` px about the
  icon centre.
* Aircraft in flights 1..4 get a 2 px rectangle in the flight colour, inflated by 2 px.
* The selected unit is drawn last, with a selection icon and a two-line label (see
  "Selected-unit label" below).
* Double-clicking an own-side **flight-leader** aircraft whose type is flyable
  (`FUN_00503e50`: 100,110,120,130,140,160,180,190,200) selects that flight and **flies** it
  immediately (exit code 2, `FUN_005005d0`).

#### Selected-unit label (`FUN_004f5d70`)

`FUN_00503ae0` draws this label. `FUN_005035c0` calls it only for the record whose
`[8] == DAT_006504d4`, and that record is drawn after all the others (`4ff9e0`).

**Selection icon**
* The icon is `icselair` (31×48) when rec[9] == 1. Every other icon class gets `icselveh` (31×42).
* Each file holds two halves: the bottom half is the mask (SRCAND) and the top half is the image
  (SRCPAINT). The displayed size is 31×24 for aircraft and 31×21 for everything else.
* Icon top-left: `x = trunc(z·px − W/2)`, `y = trunc(z·py − (H/2)/2)`, where W×H is the full bitmap
  and `(H/2)/2` uses integer halves.

**Font and colour**
* Font: the overlay font already selected by `4ff9e0` (`this+0xdc`, Arial p10 weight 600),
  transparent background.
* Colour: `SetTextColor(0x00FFFF)` = **RGB(255,255,0) yellow**, the same for both lines.
* Alignment: `SetTextAlign(6)` = TA_CENTER|TA_TOP.

**Line 1**
* Position: `(x + W/2, y + 2 + H/2)`, i.e. centred and 2 px below the displayed icon.
* Text: `idx = FUN_004f5930(FUN_004f54a0({rec[1] type, rec[0] class}))`. `FUN_004f5930` passes
  0..0x24 through unchanged; anything above becomes 0x25.
  * If `idx == 0x23` (runway), the text is the object name `rec+0xe` (20 chars).
  * Otherwise the text is `FUN_004f5d70(idx)`, copied into the 32-byte buffer `0x839128`.

Type code → index → string (`4f54a0` switch; strings from `.rdata 0x64cfec..0x64d110`):

| type code | idx | string |
|---|---|---|
| 110 | 0 | F-15 |
| 100 | 1 | F-16 |
| 120 | 2 | F-4E |
| 130 | 3 | Kfir |
| 140 | 4 | Lavi |
| 150 | 5 | MiG21 |
| 160 | 6 | MiG23 |
| 170 | 7 | MiG25 |
| 180 | 8 | MiG29 |
| 190 | 9 | Mirage |
| 200 | 10 | F-42000 |
| 210 | 0xb | MiG17 |
| 220 | 0xc | Bomber |
| 225, 230, 240 | 0xe | Transport |
| 250 | 0x10 | Tank |
| 260 | 0x11 | Truck |
| 270 | 0x12 | Armored |
| 280 | 0x13 | Soft |
| 290 | 0x14 | SA-2 |
| 300 | 0x15 | SA-3 |
| 310 | 0x16 | SA-5 |
| 320 | 0x17 | SA-6 |
| 330 | 0x18 | SA8 (no hyphen in the exe) |
| 340 | 0x1a | Hawk |
| 350 | 0x1b | AAA |
| 360 | 0x1c | Gundish |
| 370 | 0x1d | Boat |
| 380, 390 | 0x1e | Ship |
| 400 | 0x1f | Building |
| 410 | 0x20 | Strategic |
| 420 | 0x21 | Bridge |
| 430 | 0x22 | Road |
| 440 | 0x24 | Airport (taxiway) |
| 450 | 0x23 | Runway (the object name is shown instead) |

Any other type code falls back to the unit's class (rec[0]):

| class | idx | string |
|---|---|---|
| 2 (helicopter) | 0xf | Helo |
| 6 (vehicle) | 0x11 | Truck |
| 9 (IR SAM) | 0x19 | IR-SAM |
| 0xb, 0xc, 0xd, 0x1d, 0x1e | 0x1f | Building |
| anything else | 0x25 | "" (`DAT_00789370`, empty) |

* Index 0xd "Cargo" is never produced by `4f54a0`.
* `FUN_004f5fd0` is a separate 0..10 table (Fighter, Adv Fighter, Bomber, Support, Helo, Tank, Soft,
  Armored, Anti Aircraft, Naval, Structure). This label does not use it.

**Line 2 (flight name)**
* Drawn only if flight slot `n = rec[0x15]` exists (`0x689eec + n·0x370` ≠ 0, i.e. flight-table
  `+0x324`).
* Text: `0x689ef0 + n·0x370`, i.e. flight-table `+0x328` ("Alpha"…"Foxtrot").
* Position: `(x + W/2, line1_y + L + 2)`, where `L = this+0x60` is the overlay line height (see
  "Top-left text"). Font, colour and alignment are the same as line 1.
* UNCERTAIN: flight numbers 7+ do not index the table directly (formations beyond 6 take slots 7+),
  and names exist only for 1..6. Line 2 is therefore empty or unrelated for enemy/"Other" flights.
  For units in no flight, the slot-0 exists flag is presumably 0, so no line 2 is drawn.

#### Flights

**Flight number.** It is the formation's `0x3f2` (runtime `+0x38`, `FUN_005b9ee0`): 1..10 kept,
−1→8. Names come from `FUN_005b9ff0`:

| number | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| name | Alpha | Bravo | Charlie | Delta | Echo | Foxtrot | Enemy | Other | Hotel | India |

Over all missions: 1×86, 2×58, 3×42, 4×28, 5×9, 6×3, 8×239.

**Flight table.** Flights 1..6 are stored at slot n. Other formations take slots 7+. Record layout:

| offset | content |
|---|---|
| +0 | up to 20 waypoints × 0x28: {x, y, alt, ?, speed, action, name[16]}, copied from the formation's CList in route order |
| +0x320 | waypoint count |
| +0x324 | exists |
| +0x328 | name ("Alpha"…; only for 1..6) |
| +0x338/+0x354 | member 0 / member 1 descriptor |
| +0x348/+0x364 | member 0 / member 1 object id |
| +0x350/+0x36c | member 0 / member 1 type code |

* Flight membership is the formation's **two** member slots (`0x41a` ids).
* A flight exists if either member is spawned and alive.

**Player's default flight in SP** (ctor `4fe280`, unless returning from Arm):
* `DAT_00836d1c = DAT_006947a8`, the number of the formation that contains the player object
  `DAT_00694960` (`FUN_005b9bc0`). It is 0 if the player is in no formation.
* Then `FUN_00502390(n)`:
  * sets the selected unit to member 0's id, or member 1's;
  * checks the matching button (`FUN_00504130`);
  * updates Arm (`FUN_00504330`);
  * centres the view (`FUN_005043e0`).

**Button enable** (`FUN_00503f40`). Alpha..Foxtrot are enabled only if all of these hold:
* the flight exists;
* its leader type code (member 0's, else member 1's) is flyable;
* `FUN_00503cc0(n)`: n ≤ 4 and the member's record has side == 1. Missions 0x213 and 0x1ff–0x204
  use MP side rules; mission 0x29a allows 1..2.

So Echo/Foxtrot and enemy flights can never be picked in SP. The single-player `tsd.trx` has only
Alpha–Delta.

**Arm disabled** (`FUN_00504330`) when any of these hold:
* `DAT_00838420 == 0` and the mission is 0x29a or 0x213 (UNCERTAIN meaning);
* no flight is selected (0);
* the selected flight does not exist.

Multiplayer adds slot checks.

**Fly** (`FUN_00502c90`):
* SP with a valid flight: make the flight leader the player object (`FUN_004d2ae0`), then exit code 2.
* Otherwise: msg 25 "Choose a jet before flying."

**Waypoints** are drawn for flights 1..4 only, then the selected flight. In SP, pressing the left
button within 10 px of a waypoint of the selected flight (`FUN_005034f0`) starts a drag. The drag
moves the waypoint through the inverse transform (`FUN_004ff650`, `FUN_004d2a20`). This is the
purpose of `move.cur` and `grab.cur` (UNCERTAIN).

#### Top-left text (overlay `4ff9e0`)

* Font: `this+0xdc` = Arial p10 weight 600, white, transparent background.
* `L = tmHeight − tmExternalLeading − tmInternalLeading` (`this+0x60`).
* `C = extra + (tmAveCharWidth + tmMaxCharWidth)/2` (`this+0x64`).

| position | text | source |
|---|---|---|
| (4,4) | **mission title**, CDMEMiscItem `0x44c` ("Engines ON") | `DAT_006947b0` = `0x681878+0x12f38`, copied from the mission object `DAT_00694934+0x11c`. That CString is assigned at `4b9e23` from a header struct whose layout matches misc +0x18.. (title, subtitle, start time `+0xf0`, weather). |
| (4, L+6) | `DAT_006948b0` = `+0x13038`: zero-filled every refresh and never written, so **empty** | |
| (strlen·C + 14, L+6) = **(14, L+6)** | **mission clock `HH:MM:SS`**, zero-padded | `this+0x1204`, built in `FUN_005161e0` from `DAT_006947ac` = `trunc(clock+0x38 + clock+0x18)`, the time of day in seconds. Pre-flight this is the start time `0x460` (takeoff: "08:00:00"; UNCERTAIN which double is the offset). |
| (Wc−4, 4), TA_RIGHT | `"%dx"` only when `clock->vfunc+0x20()` > 1 | probably time compression (UNCERTAIN); not seen pre-flight |

#### Buttons, checks and scrollbars

* `tsd.trx` defines these buttons:
  * left panel `pTSD`: Fly, Waypoint, Text, Grid, the 14 filters, Briefing, Arm;
  * bottom1 `pFormation`: Alpha–Delta, CheckGroup 1;
  * bottom2 `pTools`: **Zoom_In (543,429,55×23) and Zoom_Out (543,453,55×23)**, both Push.

  There is no Ruler button.
* Initial check state: the ctor copies `DAT_00836cd8..d18` into each Check (`+0x3c`). Defaults are
  all on (`FUN_004efc60`, confirmed): Waypoint, Text, Grid, 14 filters, Briefing.
  * Briefing is then forced to "file exists" (`FUN_00502ec0`).
  * Briefing is disabled if `brief/txt/<id>.rtf` is missing (`FUN_00502e40`).
* Initially disabled in SP training (takeoff):
  * Bravo, Charlie, Delta (no such flights);
  * Zoom_Out (z == 1).

  Enabled: Fly, Arm, Alpha, Zoom_In, Briefing.
* Zoom (`5019b0`):
  * Pivot: the selected unit's cached point p, or `(Wc/2)/z` if there is no selection.
  * Zoom_In: `z ×= 1.5`, capped at 32. Zoom_Out: `z ×= 2/3`, floored at 1.0.
  * Then `sx = trunc(p.x) + sx − (Wc/2)/z_new` (same for y). The pivot is **centred**.
  * Then the scrollbar ranges are reset.
* Scrollbars:
  * range `[0, z·454 − Wc]` / `[0, z·590 − Hc]`, position `s·z`;
  * **arrow step = round(5·z) px = 5 map units** (`+0x64`, `4f2800`);
  * page = client size, i.e. `Hc/z` map units (`FUN_00501170` codes 2/3);
  * thumb: `s = pos/z` (code 4).

#### Briefing rich edit (`FUN_0050be40`, `FUN_0050c160`)

* Style `0x520008c4`: child, visible, read-only, multi-line, auto-v/h-scroll.
* Setup messages:
  * `EM_SETBKGNDCOLOR` RGB(94,94,104);
  * `EM_SETTARGETDEVICE(0,0)` (wrap to window);
  * `EM_HIDESELECTION`.
* **No `EM_SETCHARFORMAT`**: fonts and colours come only from the RTF.
* Format rect (`EM_SETRECT`): 10 px inset from the left, and 10 px from the scrollbar on the right.
* Scrollbar range = line count − visible lines + 1.
* Scroll steps (`50ca40`/`50caa0`):

| input | effect |
|---|---|
| arrow buttons, VK_UP / VK_DOWN | **1 line** (Down stops once the last line is within 20 px of the bottom) |
| track click, VK_PRIOR / VK_NEXT | **one page**: exactly the number of fully visible lines, scrolled one line at a time |
| thumb | `EM_LINESCROLL(pos − first visible line)` |

* The first `<header>` is found with `EM_FINDTEXTEX` using FR_WHOLEWORD, case-insensitive. It is
  replaced by `"%s %s"` = rank + callsign.
* Rank `DAT_00836c98` is set on the pilot-record screen (`51a1fe`) from the pilot's score
  `DAT_008386f0`:

| score | rank |
|---|---|
| < 5000 | **Second Lieutenant** |
| < 15000 | Lieutenant |
| < 30000 | Captain |
| < 45000 | Major |
| < 75000 | Lt. Colonel |
| < 100000 | Colonel |
| otherwise | General |

* A new pilot has score 0, so the header becomes **"Second Lieutenant <callsign>"**. The callsign
  `DAT_00836cac` (20 chars) comes from the selected pilot record (`FUN_0051bdd0`).

#### BACK / MAIN from the TSD

Both show **msg 8, "Are you sure you want to quit the mission?"**, Yes/No (box type 4). The box posts
message `0x55c` to the frame with wParam = the target screen and lParam = the button pressed.

* **BACK** (`FUN_004eb990`): the target is MC (0x14) for mission 0x213, SpMMis (0x1c) when
  `FUN_004efe30()`, otherwise the previous screen (`frame+0x58`, i.e. the Jet or mission list).
* **MAIN** (`FUN_004eb7d0`): the target is Main (1).
* The handler `4eb920` acts only when lParam == 6 (IDYES):
  * it sends engine command 0x74, which unloads the mission (`FUN_005bc4a0`);
  * in MP it also leaves the session;
  * then it switches screen (`FUN_004e8a80`).
* NO does nothing.
* In MP, MAIN instead shows msg 11 ("quit the session?"), whose handler `0x557` → `4eb900` calls
  `FUN_004ecd90` and then goes to Main. BACK still shows msg 8.

## 9. Sounds (`menu/wav`)
* `Menu_M.WAV` is the menu music. It starts on entering any screen except TSD, Arm, FlyTSD and
  in-flight Pref, if not already playing (`FUN_004e8a80`). It fades out over 6000 ms when a mission
  loads (`FUN_004ec6a0`).
* `ButtonIn.wav` plays on button press, `ButtonOut.wav` on release (`FUN_004e11c0`, globals
  `0083644c/50`).
* `PaletteIn.wav` and `PaletteOut.wav` play with the panel slides (§2).
* `credits.wav` plays with the credits.
* `menu_mo.wav` and `menu_mo.pk` are not referenced by name in the exe (UNCERTAIN).
