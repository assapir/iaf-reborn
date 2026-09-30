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
  * On Arm, BACK goes back to the TSD. The frame calls content vfunc `+0xd4` (`FUN_00505ac0`), which
    validates the loadout and asks "Use weapon load?" first (§15).
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
  * 3 buttons (type 3, `4e3195`): YES at `W/2 - 2·bw = 40`, NO at `W/2 - bw/2 = 130`, CANCEL
    (`misc/MBGCan`) at `W/2 + bw = 220`.
* Types:
  * 0 OK
  * 1 OK+Cancel (loads `MBGCancel`, which is not in the install, UNCERTAIN)
  * 3 Yes/No/Cancel (`MBGYes`, `MBGNo`, `MBGCan`)
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
  (`FUN_004e11c0` around `4e1700`, removed at `4e179f`). No menu screen uses them. The Pilot Records
  Kills/Losses pages load two other font files, `fnt/key.fnt` and `fnt/hud.fnt` (§13.10).
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
  * Rows are disabled (button `_3`) for missions whose prerequisite is not passed (`FUN_004efcd0`,
    `4f5440`). The exact rule is in §13.11: only Future missions 2–7 are ever locked.
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
| Arm (0x1f) | TacticalDisplay / BACK → TSD 0x1e; Fly → flight (§15) |

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
  (case-insensitive) is replaced by `"<rank> <pilot name>"` (`DAT_00836c98`, `DAT_00836cac`; ranks are
  "Second Lieutenant"…"General"). `DAT_00836cac` is the pilot **name**, not the callsign (§13).
* **Links** (`FUN_0050c880`): text that is underlined and yellow RGB(255,255,0) is clickable. Hovering
  it shows `Cur/Point.cur`. Clicking takes the underlined run and matches it by name against
  **`<same path>.brl`** (records of 516 bytes: `name[256], int type, path[256]`; paths are relative to
  the install root). The TSD then opens a window by type (`FUN_005013b0`, W,H = TSD client):

| brl type | content | window | pos, size | TSD slot |
|---|---|---|---|---|
| 0 | another RTF (e.g. the **lesson** `\Brief\Text\311_1.rtf`, war history `67.rtf`) | brief_t frame | (W/3, H/2), 2W/3 × H/2 | +0x140 |
| 1 | UNCERTAIN (`FUN_0050cf80`), no records | frame | (W/2,H/2), W/2×H/2 | +0x148 |
| 3 | bitmap (e.g. **instructor card `\Brief\Bmp\card.BMP`**, diagrams) | `FUN_0050d310`, style close+min | (W/2, 0), W/2 × H/2 | +0x144 |
| 2 | 3D model `.x` (aircraft/SAM) | **`obj_t`** frame, 3D view (`FUN_005169f0`, §11) | (12,16) 415×260 | +0x150 |
| 5 | target: `\Brief\Tar\<id>_N.txt`, whose first line is an object name looked up in the mission (`FUN_00439bb0`) | **`targ_t`** frame, live 3D camera on the object (`FUN_005164f0`, §10) | (22,16) 406×322 | +0x14c |

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
  replaced by `"%s %s"` = rank + pilot name.
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

* A new pilot has score 0, so the header becomes **"Second Lieutenant <pilot name>"**. The pilot name
  `DAT_00836cac` (20-byte buffer, record max 10 chars) comes from the selected pilot record
  (`FUN_0051bdd0`). The callsign is `DAT_00836cc0` and is not used here (§13).

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
* `wav/pref/engines.wav`, `sfx.wav`, `speech.wav` loop while the matching Sound-page slider is dragged
  (§12.5). `iaf-convert menu` copies them to `wav/pref/`.

## 10. TSD target window (brl type 5, `targ_t`, `FUN_005164f0`)

**Summary.** This window shows no text and no separate model. It is a **live 3D camera on the named
mission object**, rendered by the flight engine, with a 15 px tab strip underneath: SATELLITE VIEW,
ZOOM VIEW and UAV VIEW.

**Opening** (`FUN_005013b0` case 5, `5016a7`–`5017d3`):
* Path = `sprintf("%s%s", <root 0x831ff8>, brlPath)`, e.g. `\Brief\Tar\113_1.txt`.
* The file is opened `"r"` and its first line is read with `fgets(buf, 255)` (`565e80`), so a
  trailing `\n` would stay in the name. None of the 128 shipped files has a newline. Only the unused
  `b4.txt` has CRLF lines.
* `FUN_00439bb0(name)` walks the engine object hash and compares `obj->desc(+0x30)->name(+0x20)` with
  an **exact, case-sensitive strcmp**. It returns the engine object.
* If the lookup fails, **nothing opens** and no message is shown.
* If the target slot `TSD+0x14c` is already open, it is retargeted (`FUN_005166b0` → `516870`).
* Otherwise the 3D-model slot `+0x150` is destroyed first (the two windows are mutually exclusive).
  A new frame is then created at TSD-client **(22,16), 406×322** (`0x16,0x10,0x196,0x142`), style
  `0xb0000`.
* Minimum size 270×146 (`FUN_0050a2e0(0x10e,0x92)`). Tab-title art `framewnd/targ_t.bmp` 78×11.
* Example data:

  | file | line |
  |---|---|
  | `113_1.txt` | `RADARsa2r1` (link "SA-2 battery" in `txt/113.brl`; the object exists in `missions/change.mis`) |
  | `215_1.txt` | `Bunker` |
  | `122_1.txt` | `RADAR1 S.A. 2` |

  Names can contain spaces and mixed case (`T55 South 4`, `Syrian Army H.Q.`).

**Layout.** The inner client is the frame minus the 5 px side borders, the 4 px top and bottom
borders and the 11 px title bar: x=5, y=15, w=cx−10, h=cy−19. For 406×322 that is **396×303**.

| child | class | rect (inner coords) | notes |
|---|---|---|---|
| 3D view | `FUN_0050db8b` (0xb30 bytes) | (0,0) w × (h−15) = 396×288 | camera mode 1 on creation |
| view strip | `FUN_0051c0b0` | (0, h−15) w × 15 | `framewnd/tvw_off.bmp` 480×15, drawn at x0 = (w−480)/2 (C integer division; −42 at w=396). The selected tab is copied from `tvw_on.bmp`. |

`WM_SIZE` (`516980`) re-lays out the same rects. The frame's own `WM_SIZE` is `50a970`.

**View strip tabs.** Source rects in the 480×15 art are at `.rdata 0x608050`. The selected tab is
`+0x44`, default 0.

| tab | art x range | camera mode | camera |
|---|---|---|---|
| 0 **SATELLITE VIEW** | 113–197 | 1 | engine camera type 0x14 (`FUN_0057ee60`): eye = object (x, y−10, z+**7000**), looking straight down (pitch −90) |
| 1 **ZOOM VIEW** | 197–281 | 2 | as tab 0, but height **2500** |
| 2 **UAV VIEW** | 282–368 | 3 | engine camera type 0x15 (`FUN_0057ed30`): offset (0,0,**300**), sub-mode 6; view pitch −45 (UNCERTAIN: exact orbit behaviour) |

* A left click (`51c520`) hit-tests the three tab rects, offset by x0 and (h−15−15)/2 = 0. On a hit:
  * play `ButtonIn.wav` (`0x83644c`);
  * set the tab;
  * `RedrawWindow(RDW_INVALIDATE|RDW_UPDATENOW)`;
  * `view->FUN_0050e6d7(mode)`.
* A right click only activates the frame (msg 0x54a).
* The distances 7000, 2500 and 300 are at `.rdata 0x605ca0/ca4/ca8`, in world units (about metres).
* Initial view values per mode (`FUN_0050e6d7`):
  * mode 1: pitch −90, dist 20;
  * mode 2: pitch −90, dist 10;
  * mode 3: pitch −45, dist 5, zoom limits 0.5..10.

**What is shown.** The flight engine renders the **live mission world**: terrain, objects and the
current mission time.
* Render path: `FUN_0050e9a8`, mode ≠ 0 branch (`FUN_004bb110`/`0050f630`/`00586610`), with the camera
  taken from the engine's camera object, then `FUN_00402140`.
* There is **no text** in the window. The object name is used only for the lookup.
* The render runs only on `WM_PAINT`. There is no timer, so the window shows a still image that is
  refreshed on repaint or when the tab changes (UNCERTAIN whether the engine keeps animating it).
* Arrow and +/− keys are ignored in modes 1 and 2 (`50f02b`). In mode 3 they change the view's own
  angles, but the engine camera does not read them (UNCERTAIN: probably no visible effect).
* The camera is set only if the target's engine body `obj+0x38 ≠ 0` (`57ee60`).
* The 3D view gets the same 3 px `mv*` bevel as §11.

## 11. TSD 3D-model window (brl type 2, `obj_t`, `FUN_005169f0`)

**Summary.** The left two-thirds is an orbit view of the brl's `_h.x` model. The right third is a
rich edit showing `<same dir>\<same name>.rtf`. `<name>.cp` sets the zoom limits. The window is
keyboard-only.

**Opening** (`FUN_005013b0` case 2, `5015d7`):
* Path = `<root>` + brlPath, e.g. `\3dObjects\NonControllablePlanes\Mig21\Mig21_h.x`.
* Across all `.brl` files there are 245 type-2 links. The most common targets are F15_h (27), F16_h
  (22), Mig21_h (20), F42000_h (15) and Zsu234_h (12).
* One path lacks the `\3dObjects\` prefix: `ControllablePlanes\mirage\mirage_h.x`. It would fail to
  load (UNCERTAIN).
* If slot `+0x150` is already open, the model is reloaded (`FUN_00516c50`).
* Otherwise the target window `+0x14c` is destroyed, and a frame is created at **(12,16), 415×260**
  (`0xc,0x10,0x19f,0x104`), style `0xb0000`.
* Minimum size 212×124 (`FUN_0050a2e0(0xd4,0x7c)`). Tab-title art `framewnd/obj_t.bmp` 74×11.

**Layout.** The inner client is 405×241 at frame (5,15). Its inner child is `FUN_00516d10`.
* **Background**: brush **RGB(94,94,104)** (`CreateSolidBrush(0x685e5e)`, the same grey as the
  briefing). Paint `517020` only `FillRect`s it.
* **3D viewport**: rect (10, 20) – (2w/3 − 4, h − 14), i.e. **(10,20) 256×207** for w=405, h=241.
  * Constants: `.rdata 0x606f90/94/98/9c` = 10, 20, 4, 14.
  * `2w/3` = trunc(w × 0.6666667) (`0x607088/0x60708c`).
  * On `WM_SIZE` (`5170d0`) it is re-placed at (10,20) with height h−34 (width UNCERTAIN, about
    (w−14)·2/3).
* **Description rich edit** (`FUN_0050be40`, the same class as the briefing, §8.1): rect
  (2w/3, 0) – (w, h) = **(270,0) 135×241**.
  * `FUN_0050c500({0,20,0,14})` sets its insets (UNCERTAIN: left/top/right/bottom margins).
  * `FUN_00516f10` splits the model path and builds `<drive><dir><fname>.rtf` (ext `"rtf"` at
    `0x656828`), e.g. `3dobjects/noncontrollableplanes/mig21/mig21_h.rtf`. 52 `_h.rtf` files exist.
  * The file is loaded with `FUN_0050c160(path,0)`. Links work as in the briefing.
* **Logo**: `framewnd/logo.bmp` 51×22 ("Jane's"), a child of the frame at **(3,4)** on top of the
  z-order (`FUN_0051c7e0(frame,3,4)`, `.rdata 0x606f88/8c`). It sits over the frame's top-left corner
  and title bar.
  * On frame `WM_SIZE` (`516c70`): if the logo is at least as wide as the frame, it is moved off-screen
    (UNCERTAIN); otherwise it goes back to (3,4).
* **Viewport bevel**: after each render (`50e9a8`), 3 px pieces are blitted over the image edges in
  this order:
  1. `mvBrdrL` 3×480 at x=0
  2. `mvBrdrT` 480×3 at y=0
  3. `mvBrdrR` at x=w−3
  4. `mvBrdrB` at y=h−3
  5. the corners `mvCrnrLT/RT/LB/RB` 3×3

  This corrects §7: the `mv*` art is this bevel, not a resize/move outline.

**Model load** (`FUN_0050e066`):
* The extension must be `.x` (`FUN_005682b0` vs `".x"`). Otherwise the load fails and the view stays
  empty.
* Engine call: `FUN_00402320(dir, file, file, 1, 0, 10.0f, 0, 1)` (engine vtable +0x94; the meaning
  of 10.0 is UNCERTAIN).
* The model instance (`this+0xbc`) is placed at **world (404912, 668510, 1410)** (`0x48c5b600`,
  `0x492335e0`, `0x44b04000`) with orientation 0. That is about (319, 208) on the TSD map, over the
  northern Golan. Whether terrain or sky shows behind the model is UNCERTAIN.
* Scene render (`FUN_00407e80`):
  * near 4, far 22000;
  * clear colour bytes `c9 e4 e4 00` (RGB(201,228,228) or its BGR swap, UNCERTAIN);
  * time argument 39600000 (11:00:00 in ms, UNCERTAIN).
* **`<fname>.cp`** (same dir, ext `"cp"`) holds two floats read with `"%f" "%f"`: `dist height`.
  Examples: `mig21_h.cp` = `170 10`, `sa13_h.cp` = `87 18`. 69 `.cp` files exist.
* Without a `.cp`, `FUN_00402230(model,&a,&b,&c)` gives `dist = sqrt(a²+b²+c²)` and
  `height = c/2` (UNCERTAIN: bounding extents).
* Then:
  * look-at = (404912, 668510, 1410 + height);
  * min distance = `dist` (`0x65407c`), max = **4·dist** (`0x605ddc`);
  * initial distance = **1.2·dist** (`0x605de0`).
* A debug log line is written: `"FileName : %s, dist = %g, height = %g"`.

**Camera (mode 0)** (`FUN_0050e6d7`, `50f02b`). Angles are in degrees and converted with ×0.0174533
(`0x605cb8`).

```
initial: pitch p = -10, yaw y = 120, roll 0, d = 1.2*dist
eye.x = X - cos(p)*sin(y)*d
eye.y = Y - cos(p)*cos(y)*d
eye.z = (1410 + height) + sin(-p)*d        (negative pitch = eye above)
engine camera = (eye, p, y, 0)             (FUN_00402180, vtable +0x60)
```

**Interaction: keyboard only**, via `WM_KEYDOWN` (`50f02b`).
* The view needs focus, which a left or right click gives it (`50efed`/`50f00c`).
* Each key press (or Windows auto-repeat) changes one value, recomputes the eye and re-renders.
* Steps: `0x605cb4` = 2°, `0x605cb0` = 2 units.

| key | effect | limit |
|---|---|---|
| VK_LEFT | yaw += 2° | none (free spin) |
| VK_RIGHT | yaw −= 2° | none |
| VK_UP | pitch −= 2° (view more from above) | only while pitch > −80 (`0x605e00`) |
| VK_DOWN | pitch += 2° | only while pitch < −10 (`0x605e04`) |
| VK_ADD (numpad +) | d −= 2 (zoom in) | only while d > dist |
| VK_SUBTRACT (numpad −) | d += 2 (zoom out) | only while d < 4·dist |
| VK_F4 | ignored | |

* **There is no mouse drag, no auto-rotation and no timer.** The message map (`.rdata 0x605ce0`)
  handles:
  * PAINT and DESTROY;
  * SETFOCUS/KILLFOCUS (title bar active/inactive via 0x54a);
  * 0x54b;
  * L/RBUTTONDOWN (focus only);
  * KEYDOWN;
  * ERASEBKGND (returns 0).
* Lighting: the render passes one object and no extra lights (`FUN_004022b0(1, &inst, +0xb0c=0, 0)`),
  so the engine defaults apply (UNCERTAIN).
* The engine draws into an off-screen surface (`FUN_004bce60`/`4eeb30`). The surface is cleared, the
  scene rendered, the bevel drawn, and the result `BitBlt` to the window.

## 12. Preferences screen (screen 3 `sGeneral`, in flight 0x21; ctor `FUN_004fc180`, vtable `0x603dd0`)

**Summary.**
* The screen has 5 tab pages drawn from bitmaps. Every control is a fixed rectangle hard-coded in
  the exe.
* A control shows "on" by copying its rectangle from `<page>_1.bmp` over `<page>_0.bmp`.
* Edits go into a working copy. The globals at `0x836c88+…` change only when the user answers Yes
  to "Save changes?". The values are then pushed into the game pref object `DAT_00694a64` and written
  to `prefs.dat`.

### 12.1 Frame and tabs
* `dat/pref.trx`: `sGeneral tPref 155 42 608 399 1`. Left panel `pPref` at (0,35). There is no bottom
  panel.
* The panel has 5 `CheckGroup 1` buttons, so exactly one is lit.

| button | screen rect (x,y,w,h) | page id | class (ctor) | art |
|---|---|---|---|---|
| Graphics | 16,65,109,39 | 1 | `FUN_005131f0` (vt `0x606820`) | `bmp/pref/graph_0/_1` |
| Sound | 16,112,109,39 | 0 | `FUN_00511790` (vt `0x606618`) | `bmp/pref/sound_0/_1` |
| Controls | 16,155,109,39 | 2 | `FUN_0050fa70` (vt `0x606148`) | `bmp/pref/cntrl_2.bmp` |
| Devices | 16,199,109,39 | 3 | `FUN_005110d0` (vt `0x606400`) | `bmp/pref/cntrl_0/_1` |
| Gameplay | 16,243,109,39 | 4 | `FUN_00514470` (vt `0x606a80`) | `bmp/pref/gamep_0/_1` |

* Title art `titles/tpref_0..2`. Content background `screens/sgeneral.bmp`.
* Each page is a 454×357 child at content (0,0) (`DAT_00603d30/34`) and covers the background.
  **Screen coordinates = page coordinates + (155,42).**
* The current page is `DAT_00836d2c`. It is zero-initialised and never reset, so the **first visit
  opens Sound**, and later visits reopen the last page used.
* Switching tabs (`FUN_004fc820`) destroys the old page (`FUN_004fce20`) and creates the new one
  (`FUN_004fcea0`). There is no prompt, and edits survive the switch.
* In flight (0x21) the ctor disables the **Gameplay** tab (`FUN_004ec0c0("Gameplay",1)` sets button
  `+0x40`). If Gameplay was the remembered page, Sound is shown instead.
* **Drawing, all pages:**
  * The backbuffer starts as `_0` (unlit).
  * Each control that is on copies its own rect from `_1` (lit LED or red bar), SRCCOPY.
  * All labels are baked into the art. Only the Controls list draws text.
* **Sliders (Graphics, Sound):**
  * Drawing:
    * erase `[x0−tw, x1+tw]` from `_0`;
    * copy the fill `(x0, y0, trunc(v·(x1−x0)), h)` from `_1`;
    * draw the thumb `pref/slider.bmp` (19×30) at `(x0 + fill − 6, y0)`, height 15: bottom half
      SRCAND (mask), then top half SRCPAINT.
  * LBUTTONDOWN inside `[x0−tw, x1+tw] × [y0,y1]` sets `v = (mx−x0)/(x1−x0)`, clamps it to [0,1] and
    captures the mouse.
  * MOUSEMOVE keeps updating the value while captured. LBUTTONUP releases the capture.
* **DEFAULT button**: `pref/defbut_0/_2` 85×23 at page (357,330) = screen **(512,372)**, on every page
  except Devices. It copies the defaults block (§12.2) into the working copy.

### 12.2 Commit, cancel, persistence
* The ctor copies the live globals into a working copy (`this+0x68..0xd4`, key table at `+0xd8`).
* **Leaving the screen** (BACK/MAIN, vtable `+0xd4/+0xd8` = `FUN_004fc900`): if anything differs
  (`FUN_004fc970`), the screen shows **msg 38 "Save changes?"** in a Yes/No/Cancel box (type 3).
  * **Yes**: `FUN_004fcb80` commits the working copy to the globals and applies it.
  * **No**: the edits are discarded, and the live-previewed SFX and music volumes are restored
    (`_DAT_00831c6c = d38`; `FUN_00542c20(music, d40)`).
  * **Cancel**: stay on the screen.
* **On destroy** (`FUN_004fc6a0`) the globals are always written to **`<exe dir>\prefs.dat`**
  (`4ef9a0`), and Mute is re-applied.
* **Load** (`FUN_004eefb0`, at startup). `prefs.dat` is:
  1. the magic `"PREFS"` (5 bytes);
  2. 28 little-endian dwords, in this order:
     * `d30 d34 d38 d3c d40`
     * `d58 d5c d60 d64 d68 d6c d70`
     * `d90 d94 d98`
     * `da8 dac db0 db4 db8 dbc dc0 dc4`
     * **`dd8`**
     * `dc8 dcc dd0 dd4`
  3. the key table (0x1074 bytes → `0x836e14`).

  If the magic does not match, the defaults are kept. The shipped `install/prefs.dat` contains only
  `"default"`, so the defaults apply. UNCERTAIN: the save order is assumed to be the same, because
  `4ef9a0` was not decompiled.
* **Apply on commit:**
  * Sound: `FUN_004c50d0(1,d34 engine)`, `(2,d38 sfx)`, `(3,d3c speech)`, then
    `FUN_004c5100(d30 mute)`.
  * Devices: `FUN_004ddd30(d90==1, d94==1, d98==1)`, only if `DAT_00836440` is set.
  * The rest is copied into the game pref object `DAT_00694a64` (via `FUN_0043b680`).
  * The score multiplier is recomputed (`FUN_004ef7e0(0)` → `0x836e10`).
* **Defaults:** set by the ctor `FUN_004eee10` (base `0x836c88`).
  * The copy that DEFAULT uses sits 0x14 further on: sound `d44..d54`, graphics `d74..d8c`, devices
    `d9c..da4`, gameplay `ddc..e0c`.
  * Hardware detection (`FUN_004024c0`, `FUN_004022e0`) then overwrites the graphics defaults in both
    the current copy and the default copy.

### 12.3 Gameplay page (paint `514730`, click `514f70`, DEFAULT `514e60`)
* A click toggles a check. The AI row is a 3-way radio.
* Rects are page `(l,t,r,b)`, from `0x6068e8`.

| control | page rect | working / global | pref `DAT_00694a64+` | default | effect in game (reader) |
|---|---|---|---|---|---|
| NO WIND | 24,45,154,78 | +0xa4 / da8 | +0x28 | 0 | no reader found (UNCERTAIN) |
| NO BLACKOUTS | 24,78,154,113 | +0xac / db0 | +0x30 | 0 | `FUN_0044f050` zeroes the G-effect output |
| NO SPINS | 24,113,154,148 | +0xb0 / db4 | +0x34 | 0 | `FUN_005a7d50` skips spin entry |
| NO STALLS | 24,148,154,183 | +0xb4 / db8 | +0x38 | 0 | `5b13a0`/`5af920`: bStall = (+0x38==0) |
| EASY LANDING | 24,183,154,218 | +0xb8 / dbc | +0x3c | **1** | `5b85b0` doubles the landing tolerances; flight-model gear check |
| EASY AIMING | 24,218,154,253 | +0xbc / dc0 | +0x40 | 0 | `FUN_00456030` sets weapon `+0xb4`=1 (effect UNCERTAIN) |
| NO MALFUNCTIONS | 24,253,154,287 | +0xc8 / dc4 | +0x24 | 0 | no reader found (UNCERTAIN) |
| ROOKIE / NORMAL / EXPERT AI | 164,45,275,78 / 164,78,275,113 / 164,113,275,148 | +0xd4 / dd8 = 0/1/2 | +0x50 | **1 (Normal)** | `440480`, `443fd0`, `463660` (damage % scaled for levels 0/1), `5b13a0` |
| INVULNERABLE | 285,45,435,78 | +0xc0 / dc8 | +0x1c | 0 | damage skipped in `43b3d0`, `4a8f40`, `447f50`, `44ca90`; crash tests `5a8fa0`, `5b7a20` |
| NO CRASHES | 285,78,435,113 | +0xc4 / dcc | +0x20 | 0 | ground collision in `5a8fa0`, `5b7a20` |
| UNLIMITED AMMO | 285,113,435,148 | +0xcc / dd0 | +0x18 | 0 | `456030`→`455e80`, `53a820` |
| UNLIMITED FUEL | 285,148,435,183 | +0xd0 / dd4 | +0x44 | 0 | `5b1050` sets fuel flow to 0 |
| (not on screen) | none | +0xa8 / dac | +0x2c | 0 | saved and loaded but never editable; no reader found |

* The flight-model "easy" flag in docs/flight-model.md is Invulnerable (+0x1c) or No Crashes (+0x20).
* **In multiplayer** (`DAT_00694990+4 ≠ 0`) the readers ignore these prefs: cheats off, AI = 1,
  stalls on, easy landing on.
* **Scoring strip**: page (290,184)-(441,218). Art `pref/score.bmp` 151×850 holds 25 frames of 34 px:
  120%, 115% … 5%, then "WARNING – NO SCORING".
  * Multiplier:

    ```
    m = 1 + (Expert ? 0.2 : 0)
          − [NoWind .05 + NoBlackouts .1 + NoSpins .05 + NoStalls .05 + EasyAiming .1
             + NoMalf .05 + Invuln 1.0 + NoCrash .5 + Ammo .5 + Fuel .25 + (Rookie ? 0.2 : 0)]
    ```

  * `m` is clamped to ≥ 0. Easy Landing costs nothing.
  * Frame = `24 − trunc(20·m + 0.5)`. The defaults give m = 1.0, frame 4 ("100%").
  * The same formula is in `FUN_004ef7e0`. The result is stored at `0x836e10` and read at `4f6207`
    (UNCERTAIN: the debrief score).

### 12.4 Graphics page (paint `5134b0`, click `513b10`, drag `5140d0`, DEFAULT `513a50`)

| control | page rect | global | default (ctor, then hardware detection) | applied |
|---|---|---|---|---|
| TERRAIN DETAIL slider | 19,62,419,77 | d68, step 0.25 (5 positions) | 0.75, then (det−1)·0.25 | renderer `FUN_004d75c0`: level = 1+4v, min 1 |
| OBJECT DETAIL slider | 19,148,419,163 | d6c, step 0.5 (3 positions) | 1.0, then (det−1)·0.5 | level = 1+2v |
| VISUAL EFFECTS slider | 19,236,419,251 | d70, step 0.5 | 1.0, then (det−1)·0.5 | level = 1+2v |
| SMOKE TRAILS | 7,306,112,326 | d58 | 1 | pref +0x48 (`4d8930`) |
| TEXTURED SKY | 112,306,217,326 | d5c | 1 / detected | renderer init +4 |
| SHADOWS | 217,306,303,326 | d60 | 1 / detected | renderer init +0x34 |
| EXTERNAL STORES | 303,306,423,326 | d64 | 1 / `FUN_004022e0()` | `FUN_00586e50(d64)` if `DAT_0083f020` |

* Slider values are quantised to `(float)ftol(x)·step` (UNCERTAIN: the rounding inside the ftol
  argument).
* The renderer levels are applied at 3D init (640×480, `4d75c0`).

### 12.5 Sound page (paint `511b10`, click `512310`, drag `512a80`, DEFAULT `512240`)

| control | page rect | global | default | live effect while dragging |
|---|---|---|---|---|
| MASTER VOLUME | 19,17,419,32 | **not stored** | n/a | sets the Windows mixer speaker volume to `v·65535` (`FUN_00512f90`) |
| MUSIC VOLUME | 19,78,419,93 | d40 | 1.0 | `FUN_00542c20(DAT_0064961c music, v)` |
| ENGINE VOLUME | 19,139,419,164 | d34 | **0.8** | loops `wav/pref/Engines.wav` |
| SOUND EFFECTS VOLUME | 19,200,419,215 | d38 | 1.0 | loops `wav/pref/Sfx.wav`; `_DAT_00831c6c = v` |
| SPEECH VOLUME | 19,261,419,276 | d3c | 1.0 | loops `wav/pref/Speech.wav` |
| MUTE | 8,307,68,327 | d30 | 0 | applied immediately (`FUN_004c5100`) |

* Sliders are continuous, clamped to [0,1].
* The preview sound (`FUN_005424c0`, looped, range 50..500) stops on LBUTTONUP (`512a40`).
* Message `0x532` with wParam 0x87 (the in-game "Mute sound toggle") re-reads d30 into the MUTE check.

### 12.6 Devices page (paint `511270`, click `511540`; no DEFAULT button)
Three two-way choices. The top option has value 1.

| group | option = 1 (rect) | option = 0 (rect) | global | default |
|---|---|---|---|---|
| FLIGHT CONTROLS | JOYSTICK 25,73,102,92 | KEYBOARD 25,108,109,127 | d90 | 1 |
| RUDDER | PEDALS 193,73,267,92 | KEYBOARD 193,108,276,127 | d98 | 0 |
| THROTTLE | JOYSTICK 317,73,394,92 | KEYBOARD 317,108,399,127 | d94 | 0 |

* Applied with `FUN_004ddd30(flight, throttle, rudder)` on commit and at startup (`4e1504`).
* `menu/joy/*.joy` is not referenced by this page (UNCERTAIN).

### 12.7 Controls page (`cntrl_2.bmp`; `FUN_0050fba0`)
The key table itself (records, modifiers, key names, dispatch, the full list) is in
**docs/controls.md**.
* **Key-binding list** (class vtable `0x606208`, base list `FUN_004f2a80`; ctor `FUN_005102f0`):
  * Created (`FUN_004f2b60`) at page (0,53) with 9 rows over a copy of the page art (0,53)-(400,323):
    row height = 270 / 9 = **30 px**, row width 400.
  * Rows = the records whose listed flag (+0x20) ≠ 0, in table order (92 of 117).
  * Row paint `FUN_00510660` is **text only** (`log/item.bmp` / `hiitem.bmp` are loaded into the
    list but only the base painter `FUN_004f35d0` would draw them, and this class overrides it):
    transparent, font Arial p11 weight 400 (`this+0x1070`), colour RGB(0,255,0) for the selected row,
    RGB(0,180,0) (`0xb400`) otherwise. Cells (row coordinates, `0x605fa8..d4`):
    * function label (keys.trx line i) (11,1)-(181,28), `DT_VCENTER|DT_SINGLELINE` (left);
    * key name (`FUN_005107c0`) (187,1)-(328,28), centred;
    * joystick button (`FUN_00511070`, "Button n") (331,1)-(409,28), centred (clipped at x 400).
  * The first row is selected on creation (`FUN_004f2df0(0)`).
* **Scrollbar** (`FUN_004f1df0`) at page (422,53)-(433,323), vertical. The first arrow child
  (`pref/slupb_0..2`, whose art points **down**) is moved to the bar's bottom (`SetWindowPos` y = bar
  height − arrow height @4f1f9e); the second (`sldownb_0..2`, pointing up) stays at (0,0), the top. Both
  15×18, clipped to the 11 px bar. Thumb `pref/sldcntrl.bmp` 10×23 between them. (The same class
  serves other scrollbars: check the TSD's `vslupb` / `vsldownb` placement against this.)
* **Key capture** (`FUN_005103c0`, the list's key-down handler):
  * VK_LEFT/UP/RIGHT/DOWN go to the list (move the selection); arrows therefore cannot be bound.
  * Otherwise the DirectInput keyboard state is scanned for the first pressed key that is not a
    modifier (skips 0x1d/0x9d, 0x2a/0x36, 0x38/0xb8, 0xdb/0xdc); the modifier is Ctrl (0x11), else
    Shift (0x22), else Alt (0x44), else Win (0x88); key = modifier << 16 | scancode.
  * If no other record has that key it is stored in the selected record (+0x18). Otherwise msg 36
    "This key is already assigned to another function. Change anyway?" (Yes/No, `FUN_004e4f00` type 4);
    Yes clears the other record's key (0) and assigns it.
  * Joystick buttons (`FUN_005105b0`) the same on +0x1c with msg 37 and −1 for the cleared record.
* **Data**: the working table `0x836e14` (see docs/controls.md; it is what `prefs.dat` stores).
* DEFAULT restores the whole table from `0x647ff8` (@5102a5) — the default table's start; there is no
  offset puzzle (`0x648018` is record 0's +0x20 field).

**linux-iaf**: the list, scrollbar (arrows, thumb drag, track click = one page, UNCERTAIN), a click on
a row selects it **and gives the list the keyboard** (UNCERTAIN: the original list takes the focus the
same way; until then keys go to the screen, so Esc still leaves), the key capture with msg 36, DEFAULT,
all in the Preferences working copy (Save changes? Yes stores `[keys]` in settings.cfg). Up/Down move
the selection. The Hebrew pack has no keys.trx: labels stay English on the pack's art.

### 12.8 Hebrew pack art
The Hebrew menu pack (docs/packs.md) replaces the page art (`pref/*_0/_1`, `cntrl_2`, `score`,
`defbut_*`) and the `pPref` tab strip; the exe and its rects are unchanged. Checked by diffing `_1`
against `_0` in both languages (pixel colour distance > 90, connected regions):
* **Gameplay, Graphics, Devices:** the lit regions (LEDs, slider fills) are at exactly the English
  positions. The Hebrew columns keep the English order (left column = Player skills, then Enemy level,
  then Cheats; Devices: Flight controls, Rudder, Throttle); only the labels are translated.
* **Sound:** the slider fills and the MUTE LED match too. The Hebrew `sound_1` also has brighter
  labels (titles, "סגור" / "מקסימום"). These are outside the copied control rects, so they never
  show, as in the original.
* `score.bmp` keeps the 25 × 34 px frame layout, and `defbut` keeps the same size.

So the Hebrew pages use the same rects as §12.3–§12.6.

### 12.9 Implementation (game/menu/front_end.gd, game/settings.gd)
* Everything above is ported: the tabs, "first visit Sound, then the last page" (`Settings.pref_page`,
  kept for the session, not saved), the `_0` art plus lit rects from `_1`, sliders with the
  `slider.bmp` thumb (image through its mask), the scoring strip, DEFAULT on every page but Devices,
  the working copy, and msg 38 Yes/No/Cancel when leaving by BACK, MAIN or Esc.
* The live previews are ported: music volume and Mute on the front-end music, and the wav/pref loops
  for engine / SFX / speech. MASTER VOLUME sets the Godot master bus and is not stored, like the
  original's mixer write.
* Stored in `user://settings.cfg` (sections sound / graphics / devices / gameplay) with the original
  defaults. The hardware detection that overrides the graphics defaults is not ported.
* In-game effect so far: only No blackouts. The other flags are stored for when their readers are
  built.
* Graphics sliders snap to `round(v/step)·step` (UNCERTAIN, see §12.4).
* **Controls page:** built (§12.7): the original key list, scrollbar, key capture with msg 36 and
  DEFAULT; rebinds are stored in `[keys]` and used in flight (docs/controls.md).
* **Extras tab (ours, not in the original).** A 6th tab, 44 px below Gameplay, the panel's button
  spacing (rect 16,287,109,39).
  * **Button art:** the `pPref` band around the Gameplay button (panel rect 12,203,116,54 from `_0`,
    the button rect from the current frame), moved down 44 px. Its label (panel 42,219,62,16) is
    filled in per row by blending the pixels on either side, then "EXTRAS" / "תוספות" is drawn in
    Arial bold.
  * **Page:** `screens/sgeneral` background, rows 35 px apart on the Gameplay page's grid, and LEDs
    copied from `gamep_0/_1`. Mirrored in Hebrew.
  * **Options:** Flight data (Original 1998 / Real F-16), Language (English / Hebrew; Hebrew only when
    the pack is installed), Better physics, Flight info (F12) show/hide, Blackbox.
  * **Behaviour:** the options go through the same working copy and "Save changes?" box. A language
    change reloads the menus on Yes.
  * The original has no language setting: the Hebrew pack simply replaces the resource files.

## 13. Login / Pilot Records screen (screen 0, `log.trx`)

**Summary.**
* Pilots live in `<exe dir>\Pilots.dat` (36-byte records). Each pilot's history is in
  `<exe dir>\Pilots\<id>.mis`. **No registry** is used.
* `DAT_00836cac` is the **pilot name** and `DAT_00836cc0` is the callsign.
* Only the Future campaign's missions 2–7 are ever locked.

### 13.1 Entry, frame and panel
* **Startup** (`4e1544..4e159c`):
  * With no command-line mission, the frame is created on **screen 0** (UNCERTAIN: `ebp`=0 at `4e157a`).
  * If `FUN_004e0720` returns −1 (the `MENU` command-line form), the frame opens on screen 0x16 (TCP).
  * Otherwise `DAT_00836c88` is set to the returned mission id and the frame opens on screen 0x27 (Jump).
* Main → `PilotRecords` returns to screen 0. On screen 0, BACK is disabled and QUIT replaces MAIN (§3.2).
* `log.trx`:
  * Header `sGeneral tLogin 155 42 608 399 1`: background `screens/sgeneral.bmp`, title `tlogin_0..2`.
  * One left panel `pLogin` at (0,35) (`palettes/plogin_0..2`, 141×414).
  * Push buttons `Login` (15,68,112×36), `New_Pilot` (15,333,112×36) and `Remove_Pilot` (15,382,112×36).
* The content window's button handler (vtable +0xcc = `FUN_005097b0`) runs first. The frame changes
  screen only if that handler returns non-zero (`4e847a`). For `Login`, the dispatcher `FUN_004eaf50`
  (case 0) then goes to **Main (1)**.

### 13.2 Content window `FUN_00509110` (vtable `0x604f48`, message map `0x604e80`)
* Font: Arial p11 weight 400 (`+0x80`), shared by the list and the pages.
* All four pages are created up front.
  * Pages are drawn at content-local **(26,55)** (`0x604e20`).
  * The tab strip (384×26 images) is drawn at **(26,29)** (`0x604e28`) by paint `FUN_00509490`.

| tab | page class | page art | strip art (current tab lit) |
|---|---|---|---|
| 0 Dossier | `FUN_00519f50` (vt `0x607cc0`) | `log/dossier.bmp` 384×273 | `log/dossierb.bmp` |
| 1 Records | `FUN_00519ba0` (vt `0x607b28`) | `log/records.bmp` 384×273 | `log/recordsb.bmp` |
| 2 Kills | `FUN_005192b0(…,1)` (vt `0x6079e0`) | `log/kills.bmp` 385×283 | `log/killsb.bmp` |
| 3 Losses | `FUN_005192b0(…,0)` | `log/losses.bmp` 385×283 | `log/lossesb.bmp` |

* **Tab hit rects** (content-local, all at y 29–55; tables at `0x604e30..0x604e6c`): Dossier x 26–142,
  Records 142–240, Kills 240–311, Losses 311–388.
* Handling (`FUN_00509660`, on left button down; the current tab is not hit-tested):
  1. Play `ButtonIn.wav` (`FUN_005424c0(DAT_0083644c)`).
  2. Call `FUN_005098a0(1)`. When leaving the Dossier, this validates the name and callsign (§13.4).
     If validation fails, the switch is cancelled.
  3. Call `FUN_00509940(tab)`.
* Message `0x549` is sent right after the screen is created (`4e8a80`, @`155173`). Its handler
  `FUN_00509860` creates the pilot list (§13.3) and shows tab 0.
* There is no Notes tab. `log/notes*.bmp` and the file `Pilots\<id>.not` (deleted when a pilot is
  removed) are otherwise unreferenced (UNCERTAIN: probably a dropped feature).

### 13.3 Pilot list box (`FUN_0051abf0` ctor, `FUN_0051ae70` create; item list `FUN_0051be80`, base `FUN_004f2a80`)
* **Its parent is the frame, not the content window.** It sits at **screen (19,123)**
  (`0x604e70/74`), size 104×200 = `log/pilotslb.bmp`. That fills the gap in the left panel between
  Login (ends at y=104) and New_Pilot (starts at y=333).
* Inside `pilotslb` (`0x607d88..a4`):
  * Item area (28,11)–(103,199), i.e. 75×188: **11 visible rows of 17 px**.
  * Scrollbar area (1,1)–(16,199) (`FUN_004f1d40`):
    * thumb `log/slider.bmp` 15×35;
    * arrows `log/slupb_0..2` / `log/sldownb_0..2` 15×18.
* Item paint (`FUN_0051c020`):
  * **Text only.** `item.bmp`/`hiitem.bmp` (75×17) are loaded, but this routine never draws them.
  * The text is record +0 (the **pilot name**), `DT_CENTER|DT_VCENTER|DT_SINGLELINE`, transparent.
  * RGB(0,255,0) when selected, RGB(0,128,0) otherwise.
* A left button down (`51bfe0` → `4f3160`) selects a pilot. A **double-click** (`51c000` →
  `FUN_0051be40`) logs in and goes to Main (`FUN_004e8a80(1)`).
* When the selection changes (notification 0x10, `FUN_0051b6b0`):
  1. Validate the dossier (`FUN_005098a0(1)`). On failure, restore the old selection and stop.
  2. Set the current index `+0x40`.
  3. Load that pilot's history (`FUN_004f4db0(id)`, §13.6).
  4. Show the Dossier.
* The initial selection is the index stored in the `Pilots.dat` header.

### 13.4 Dossier page (create `FUN_0051a050`; page-local coords, page at content (26,55))
The art `log/dossier.bmp` has these labels baked in: PILOT NAME, CALL SIGN, RANK, PILOT SCORE and
MISSIONS COMPLETED, plus a photo frame.

| item | rect / pos | content |
|---|---|---|
| Pilot name edit | (106,30) 170×18 | record +0, **max 10 chars** |
| Call sign edit | (106,64) 170×18 | record +0xb, **max 12 chars** |
| Photo | (288,32)–(357,125), StretchBlt | see below |
| Rank | (80,156) | rank string (table in §8.1); also copied to `DAT_00836c98` |
| Pilot score | (96,188) | `"%d"` of `DAT_008386f0` |
| Missions completed | (140,220) | `"%d"` of `DAT_008386d4` (missions with at least one passed attempt) |

* Text style:
  * Arial p11 weight 400, RGB(0,255,0), transparent.
  * `SetTextAlign(TA_BOTTOM|TA_LEFT)`, so each y is the text bottom.
  * The text is drawn into the page bitmap only when a pilot is selected.
* **Edit box** (`FUN_004eff00` / `FUN_004eff70`):
  * It is a child window whose background is a copy of the page bitmap under it.
  * Text is drawn at (0, h) with TA_BOTTOM, in the same green and font.
  * Caret: `misc/LoginCaret.bmp` (1×16), bottom-aligned, blinking on a 200 ms timer (`SetTimer(…,1,200)`).
  * A click places the caret at the nearest character (`FUN_004f0bd0`).
  * WM_CHAR (`4f0480`, jump table `4f0764`):
    * Only **space, `.`, `0-9`, `a-z`, `A-Z`** are accepted, inserted at the caret.
    * A character is refused if it would exceed the max length or make the text wider than the box
      (`FUN_004f0d40`).
    * Backspace deletes the character left of the caret.
  * The box notifies its parent with WM_COMMAND (high word): 0xb focus gained, 0xc focus lost,
    0xd Enter, 0xe Tab, 0xf Esc.
  * The page's handler (`FUN_0051a8b0`):
    * Enter or Tab moves focus to the other box.
    * On 0xb it validates the box that just lost focus (`+0x68`).
* **Validation** (`FUN_0051a6c0` name, `FUN_0051a710` callsign). Errors are shown in an OK box
  (`FUN_004e4f00`), and focus returns to the box.
  * Name empty → msg 0x1c "Please enter a name for the new pilot."
  * Callsign empty → msg 0x1a "Please enter a callsign for the new pilot."
  * Callsign equal to another pilot's (case-sensitive `strcmp`) → msg 0x1b "Callsign is taken. Please
    enter a different callsign."
  * Otherwise the value is written to the record.
  * Validation runs on tab switch, list selection change, New_Pilot, Login and double-click.
* **Photo** (`FUN_0051a490`). The index `+0x7c` is record +0x1c.
  * Index < 14: `log/pilots/<n>.bmp` (69×93).
  * Index ≥ 14: `<exe dir>\Pilots\<pilotId>.bmp`.
  * **Left click** on the photo (`FUN_0051a930`) cycles 0 → 1 → … → 13 → 14 → 0. Step 14 is skipped
    if no custom bitmap loads.
  * **Right button up** on the photo (`FUN_0051a9b0`) opens a Windows file dialog ("Bmp Files
    (*.bmp)", default ext BMP). The chosen file is copied to `Pilots\<id>.bmp` and the index is set
    to the pilot id.
  * The index is written back to the record (`FUN_0051b950`).

### 13.5 Buttons (`FUN_005097b0`)
* **New_Pilot** (`FUN_0051ba10`):
  1. Validate the dossier.
  2. Create a blank record (`FUN_005099d0`: empty name and callsign, id 0, photo 0).
  3. Set its id to the **lowest unused id ≥ 14** (`FUN_0051b750`).
  4. Load its (empty) history, append it to the list, select it and show the Dossier.
* **Remove_Pilot** (`FUN_0051bb20`):
  * Does nothing when there are fewer than 2 pilots, so the last pilot can never be removed.
  * If the name or callsign is filled in, it first asks msg 0x1d "You are about to delete this pilot
    record. Continue?" (Yes/No). A record with both fields blank is deleted without asking.
  * On Yes (or no question):
    * delete `Pilots\<id>.not`, `.mis` and `.bmp`;
    * remove the record (if it was last, the selection moves to the new last pilot);
    * reload that pilot's history and show the Dossier.
* **Login** (`FUN_0051bdd0`):
  * Validates the dossier; on failure the screen does not change.
  * Sets `DAT_00836c8c` = pilot id (record +0x18), `DAT_00836cac` = name (`strncpy`, 20) and
    `DAT_00836cc0` = callsign (20).
  * The dispatcher then goes to Main.
  * With no record selected it returns 1 without setting anything (UNCERTAIN; the list is never empty
    in practice).

### 13.6 Storage (no registry)
Paths are the exe's drive and dir (`GetModuleFileName`) plus a file name (`FUN_00567610`).

**`Pilots.dat`**: a `u32` selected index, then N records of 36 bytes to the end of the file
(N = (size − 4) / 36).

| offset | type | field |
|---|---|---|
| +0x00 | char[11] | pilot name (list text, `DAT_00836cac`, briefing header) |
| +0x0b | char[13] | callsign (`DAT_00836cc0`) |
| +0x18 | i32 | pilot id (≥ 14), used in `Pilots\<id>.*` file names |
| +0x1c | i32 | photo index (0–13 stock; otherwise = id, meaning the custom bmp) |
| +0x20 | i32 | unused (not initialised by `FUN_005099d0`) |

* Written when the list is destroyed (`FUN_0051b2c0`):
  * If the selected record has **both** name and callsign empty (`FUN_0051b970`), its files and record
    are deleted first.
  * The file is then rewritten: header = current index, then all records.
* If the file is missing, one default record is created: name **"Gal"**, callsign **"default"**,
  id 14, photo 0 (`FUN_0051abf0`).

**`Pilots\<id>.mis`**, the mission history. It is read by `FUN_004f65a0` and written by `FUN_004f6870`.
In memory it is the object at `0x838458`, list head at `+4`.

```
u32 nMissions
repeat nMissions:
  u32 missionId
  u32 nAttempts
  repeat nAttempts:                    // in memory 0x138 bytes each
    i32   result      (+0x00)  >0 passed, 0 failed, -1 "prerequisite not met" (not counted)
    f32   mult        (+0x04)  = DAT_00836e10 when the attempt was created (score multiplier, §12.3)
    i32   bonus       (+0x08)
    u32   nCat        (+0x0c)  = 37
    i32   kills[nCat] (+0x10)  enemy objects destroyed, per category
    i32   losses[nCat](+0xa4)  own-side objects lost, per category
```

* `FUN_004f5440(id)` = the number of attempts with result > 0 (passes).
* `FUN_004f6110` = the number of attempts with result == 0 (failures).

### 13.7 Recording a mission (`FUN_004f4fb0`)
It is called from the Debrief content ctor `FUN_004fcfb0` (@`4fd0f5`) with pilot `DAT_00836c8c` and
mission `DAT_00836c88`.
1. Reload the `.mis` file and append a new attempt (`FUN_004f6140`).
2. Fill the attempt from the results R = `mission+0x1f84` (`FUN_00598140`):
   * **result** = `R[0]`, except that it is set to −1 when all of these hold:
     * the mission is Future (id 200–299, `FUN_004efe50`);
     * it is not the first of its war (`FUN_004efe70`; the first-of-war ids are 111, 121, 131, 211,
       221, 231, 311, 321, 331, 401, 511);
     * mission id − 1 has not been passed.
   * **bonus** = `R[1]`.
   * **kills**: 1000 entries at `R+0x48`. **losses**: 1000 entries at `R+0x1f48`. Each entry is
     8 bytes. For each entry, `FUN_004f54a0(typeCode)` gives a category, and that category's counter
     is incremented.
3. Save the file, except for the MP ids 0x21d, 0x29a, 0x213 and 0x1ff–0x207.

Categories are the same indices as the TSD label table in §8.1 ("Selected-unit label"):
* 0–36 by type code;
* fallback by class: 2 → 15, 6 → 17, 9 → 25, 0xb/0xc/0xd/0x1d/0x1e → 31;
* anything else → 37, which is ignored.

### 13.8 Score and rank (`FUN_004f6230` per attempt, `FUN_004f4dd0` per pilot)
**Points per category** (`FUN_004f5c50`):

| categories | points |
|---|---|
| 0–10 | 1000, 800, 700, 600, 1200, 500, 600, 600, 700, 600, 800 |
| 11–21 | 400, 400, 2000, 2000, 200, 100, 50, 100, 50, 300, 350 |
| 22–30 | 800, 400, 400, 400, 800, 100, 100, 200, 500 |
| 31–36 | 200, 3000, 600, 100, 2000, 2000 |

**Score class** (`FUN_004f5b10`): categories 0–15 are air, 16–30 ground, 31–36 structure.

Per attempt, for each class:

```
K_class += trunc(kills · pts · mult)
L_class += losses · pts · (mult > 0 ? 1 : 0)
score    = trunc((ΣK − ΣL) + bonus · (bonus > 0 ? mult : 1.0))
```

**Best attempt** of a mission: the one with the highest score (the later one on a tie). Pilot totals
sum each mission's best attempt and skip the MP ids (§13.7).

| global | meaning |
|---|---|
| `DAT_008386f0` | **pilot score** = sum of best scores. The rank comes from it (table in §8.1: < 5000 Second Lieutenant … ≥ 100000 General). |
| `DAT_008386d4` | number of missions with at least one pass |
| `DAT_008386d8/dc/e0` | kill points: air / ground / structure |
| `DAT_008386e4/e8/ec` | loss points: air / ground / structure |
| `0x8386f4 + 8g` / `0x83874c + 8g` | kills / losses per display group: {row, count} |

**Display groups** (`FUN_004f5820`; names from `FUN_004f5fd0`; row from `FUN_004f5bf0`):

| group | categories | row |
|---|---|---|
| 0 Fighter | 2,3,5,6,7,9,10,11 | air |
| 1 Adv Fighter | 0,1,4,8 | air |
| 2 Bomber | 12 | air |
| 3 Support | 13,14 | air |
| 4 Helo | 15 | air |
| 5 Tank | 16 | ground |
| 6 Soft | 17,19 | ground |
| 7 Armored | 18 | ground |
| 8 Anti Aircraft | 20–28 | ground |
| 9 Naval | 29,30 | ground |
| 10 Structure | 31–36 | structure |

### 13.9 Records page (`FUN_00519bf0`)
* Art: `log/records.bmp`, a grid with columns 1–7 and these rows: BASIC TRAINING, COMBAT TRAINING,
  SIX DAY WAR, YOM KIPPUR WAR, LEBANON WAR, SYRIAN FRONT, IRAQI FRONT, LEBANON FRONT, SCRAMBLE.
* Each mission in the history gets a stamp:
  * `log/passed.bmp` (35×14) if it has any pass;
  * otherwise `log/failed.bmp` if it has any failure;
  * otherwise nothing (only −1 attempts).
* Stamp x = 118 + (id mod 10 − 1)·36. Stamp y by id/10:

| id/10 | 31 | 32 | 11 | 12 | 13 | 21 | 22 | 23 | 40 (scramble) |
|---|---|---|---|---|---|---|---|---|---|
| y | 64 | 79 | 96 | 111 | 126 | 143 | 158 | 173 | 190 |

  Other ids are not drawn (`0x607aa8..d4`, jump table `519e68`).

### 13.10 Kills / Losses pages (`FUN_005192b0`, paint `FUN_00519510`)
* **Icons**: `log/enemyic.bmp` (Kills) or `log/iafic.bmp` (Losses), 162×17 = six cells of 27×17.
  * Cell 0 = air, cell 1 = ground, cell 5 = structure.
  * One icon per group with count > 0, in group order, into fixed page-local slots:
    * air: (75,14), (165,14), (255,14), (120,48), (210,48)
    * ground: (75,88), (165,88), (255,88), (120,118), (210,118)
    * structure: (75,166)
* **Label** under each icon: the group name, or `"%sX%d"` when the count is ≥ 2 (e.g. "FighterX3").
  Drawn at (slotX+13, slotY+17), TA_CENTER|TA_TOP, green, font from **`fnt/key.fnt`**.
* **Class totals**: font **`fnt/hud.fnt`**, right-aligned at x=378, vertically centred on y=58 (air),
  128 (ground) and 184 (structure).
  * Kills page: `DAT_008386d8/dc/e0` in green.
  * Losses page: `−DAT_008386e4/e8/ec` in red RGB(255,0,0).
  * A total is drawn only if it is non-zero or its row has icons.
* Both `.fnt` files are loaded with `AddFontResource` + `EnumFontFamilies(<file title>)`
  (`FUN_004ed4c0`). This is a second font use besides the credits (§4).

### 13.11 Mission unlock rules
**List screens** (`FUN_00508590` @`508cc9`). `s*.trx` rows are `id f1 f2 f3 f4 Name …`. Row *i* is
disabled (button art `_3`) when all of these hold:
* `f1 ≠ 0`;
* `FUN_004f5440(id of row i−1) == 0`. The first row is compared with −1, so it is locked whenever
  f1 = 1;
* the cheat is **not** active.

| list | f1 | effect |
|---|---|---|
| straining, sbasic (311–315), scombat (321–326) | all 0 | **training is never locked** |
| scampaign, shistory, sfuture | all 0 | open |
| sh1/sh2/sh3mission (111–117, 121–127, 131–137) | all 0 | historical wars fully open |
| sf1mission 211–217, sf2mission 221–227, sf3mission 231–237 | 0 for Mission_1, **1 for Mission_2–7** | each Future-front mission needs the previous one passed |
| sspmmis 511–516 | all 0 | open |

* Multiplayer has a separate row-disable check at `508d04` (not traced).
* **Cheat** (`FUN_004efcd0(&DAT_00836c88)`): it returns 1 when the name (`0x836cac`) is **"make sim"**
  and the callsign (`0x836cc0`) is **"not war"**. With the cheat on:
  * all rows are unlocked;
  * the prerequisite for "next mission" is skipped;
  * Jump_In asks "Do you want a 40N mission?" for each N (`4eb085`).

**Debrief "next mission"** (`FUN_004fdec0`; 0 = none):

| mission | next |
|---|---|
| 111–116 | +1 |
| 117 | 121 |
| 121–126 | +1 |
| 127 | 131 |
| 131–136 | +1 |
| 137 | 211 |
| 211–216, 221–226, 231–236 | +1 only if the current mission is passed (or the cheat is on) |
| 217, 227, 237 | 0 |
| 311–314 | +1 |
| 315 | 321 |
| 321–325 | +1 |
| 401–407 | `FUN_004efd10` |

**Jump_In without the cheat** (`FUN_004efd10`):
* While 407 has no attempts: the mission after the highest attempted id in 401–406, or 401 if none
  has been attempted.
* After that: a random scramble mission not yet passed, excluding the current one.
* If all are passed: a random one of the other six.

### 13.12 Notes / UNCERTAIN
* UNCERTAIN meanings: `R[0]` (assumed to be the pass flag) and `R[1]` (the bonus).
* `FUN_004e4f00` is the message-box call used here (type 0 OK; type 4 Yes/No, returns 6 on Yes). It is
  assumed to behave like `FUN_004e2790` (§3.3).
* Page coordinates (Dossier, Records, Kills, Losses) are relative to content (26,55), so
  screen = (181 + x, 97 + y). The list box is already in screen coordinates.

## 14. Reference screen (screen 5, `ref.trx`, content class ctor `FUN_004fabb0`, vtable `0x603c50`)

**Data file.** `<ReferencePath>\refers.ref`.
* `ReferencePath` = `GetPrivateProfileString("MENU","ReferencePath",…, ini DAT_00831de8)`. In
  `tgen.ini` it is `c:\iaf\Resource\Ref`, i.e. `install/resource/ref/`.
* Loaded by `FUN_004fb9c0`: `u32 count`, then `count` × **0x234 (564) byte** records.
* Then `qsort`ed by name, case-insensitive (`FUN_00565af0`, comparator `4fbb40` → `_stricmp 5682b0`).
* `prevrefers.ref` (72 records, an older version) is **not referenced** by the exe.

| off | field |
|---|---|
| +0x000 | display name `char[32]` ("F-16") |
| +0x020 | directory `char[256]` ("F16"). Files are `ref\<dir>\<dir>_0.rtf` and `<dir>_0.bmp` (all 71 present). |
| +0x120 | model path `char[260]`, relative to `3DObjectsDir` (`\ControllablePlanes\F16\F16_h.x`) |
| +0x224 | IDF flag |
| +0x228 | Enemy flag |
| +0x22c | category: 0 Fighters, 1 Helicopters, 2 Support, 3 Tanks, 6 Other, 8 AA, 9 AG |
| +0x230 | junk pointer |

**Resulting lists.** Sorted; Prev/Next walk them in this order.

| side | Fighters | Helicopters | Support | Tanks | Other | AA | AG |
|---|---|---|---|---|---|---|---|
| IDF | A-4E, F-15, F-16, F-4 2000, F-4 E, Kfir, Lavi, Mirage | CH-53, UH-60A | Boeing 707, C-130 | M-113, Mercava | Hawk Launcher, Sa'ar 5 | AIM-120, AIM-7, AIM-9, Python 3, Python 4, Shafrir | AGM-62 TV, AGM-65 Maverick, AGM-88 HARM, CBU-87 Cluster, CBU-97 Cluster, GBU-15 TV, LAU-61 Rockets, M-117, MK-82, MK-82 LGB, MK-83, MK-83 LGB, MK-84, MK-84 LGB, Popeye TV |
| Enemy | MIG-17, MIG-21, MIG-23, MIG-25, MIG-29, SU-22, SU-24 | MI-24, MI-8 | IL-76, Tupolev | BMP-1, BRDM-2, M-1974, Scud B, T-55, T-62, T-72 | SA-13, SA-2/3/5/6 Launcher, SA-8, Syrian Military Ship, ZSU 23X4 | AA-10, AA-11, AA-2, AA-6, AA-8 | AS-14, AS-16, RBK-500 |

F-4 E uses the F42000 model.

**Left panel `pRef`** (screen coordinates, from `ref.trx`):

| button | pos, size | kind |
|---|---|---|
| IDF | (16,67) 53×22 | CheckGroup 1 |
| Enemy | (69,67) 53×22 | CheckGroup 1 |
| Aircraft | (15,99) 108×18 | CheckGroup 2 |
| Vehicles | (15,118) 108×18 | CheckGroup 2 |
| Weapons | (15,136) 108×18 | CheckGroup 2 |
| Description | (15,308) 108×18 | CheckGroup 3 |
| 3DView | (15,326) 108×18 | CheckGroup 3 |
| Pictures | (15,344) 108×18 | CheckGroup 3 |
| Prev | (16,392) 53×22 | Push |
| Next | (69,392) 53×22 | Push |

**Sub-category list.** A list widget (`FUN_0050baa0`, base `FUN_004f2a80`, create `4f2b60`), child
of the frame.
* Position **(21,184)**, size 97×114 (`ref/list.bmp`; `.rdata 0x603bd0/4`).
* **6 rows of 19 px**, each backed by `ref/item.bmp` 97×19.
* Text: Arial p11 weight 400, `DT_CENTER|DT_VCENTER|DT_SINGLELINE`, left edge +3 (`50baf0`). Colour
  RGB(0,128,0), or RGB(0,255,0) when selected.
* Rows by group:
  * Aircraft → Fighters, Helicopters, Support
  * Vehicles → Tanks, Other
  * Weapons → AA, AG
* Selecting a row (click, or `FUN_004f2df0`) sends WM_COMMAND code 0x10 to `4fb1b0`. That handler:
  1. sets the category `this+0x194` from the row string;
  2. sets the index `this+0x160` = 0;
  3. shows the first match (`FUN_004fbb60`).

**Button handler** (`FUN_004fb2e0`, vtable +0xcc):
* **IDF / Enemy**: set the side `this+0x198` (1 or 0), set the index to 0, and show the first match.
* **Aircraft / Vehicles / Weapons**: refill the list and select row 0.
* **Next / Prev**: index ±1, then scan forward or back for the next record whose category matches
  and whose side flag is set (`4fbb60`/`4fbba0`). `FUN_004fbf20` disables Next/Prev when there is no
  further match (`FUN_004ec0c0(name,1)`).
* **Description / 3DView / Pictures**:
  * If that view already exists, nothing happens.
  * Otherwise the other views are destroyed, this view is created (rect below), and the current record
    is reloaded (`FUN_004fbbd0`).
* **Video** (`ref\<dir>\<dir>_0.avi`, `FUN_0050d170`/`50d250`) is handled in code, but `ref.trx` has
  no Video button and no .avi files exist. It is unreachable.

**Initial state** (msg 0x549 → `FUN_004fb030`):
* IDF, Aircraft and Description are checked.
* The list shows Fighters/Helicopters/Support with row 0 selected.
* The first record shown is **A-4E**, with Prev disabled and Next enabled.

**Content layout.** The content area is 453×357 with `screens/sref.bmp` as background: flat grey
≈ RGB(94,94,104) with the "Jane's" logo at the top left.
* **Title strip** (`FUN_004fc020`):
  * The top **34 px** of sref.bmp are saved in the ctor (`this+0x174`) and re-blitted before each
    title is drawn.
  * The record name is drawn in **white, Arial p20 weight 400**, `DT_CENTER|DT_VCENTER|DT_SINGLELINE`,
    in rect (0,0,W,34).
* **View rect**: **(0,34)–(453,357)**, i.e. 453×323.

| view | object | file | rendering |
|---|---|---|---|
| Description | rich edit `FUN_0050be40` (same class as the briefing, §6/§8.1: background RGB(94,94,104), custom scrollbar) | `<ReferencePath>\<dir>\<dir>_0.rtf` via `FUN_0050c160` | fonts from the RTF |
| Pictures | `FUN_0050d4e0` (child, style 0x54000000) | `<ReferencePath>\<dir>\<dir>_0.bmp` (`FUN_0050d8a0`) | BLACKNESS fill, then a centred StretchBlt at zoom `z`=1.0: `x=(W−w·z)·0.5`, `y=(H−h·z)·0.5` (`50d760`). Images are up to 454×327, so a 327-high image loses 2 px at the top and bottom. See the zoom note below. |
| 3DView | `FUN_0050db8b` (the same 3D viewer class that the TSD `obj_t` frame wraps, §11) | `<3DObjectsDir>\<model path>`. `3DObjectsDir` = ini `[Render] 3DObjectsDir` (`DAT_00831ca0`, read at `4e031b`); loaded via `FUN_0050df8a`. | Plain child with no frame. Ctor arguments `DAT_00694914`, `DAT_00694974`. Camera and keys are as in §11 (keyboard orbit, `.cp` limits). |

* Pictures zoom (`50d910`/`50d980`): LBUTTON zooms in (`z≤1 ? z·2 : z+2`, while z < 16); RBUTTON zooms
  out (`z>2 ? z−2 : z·0.5`, while z > 0.2). Both act only when `+0x44` ≠ 0, and nothing sets it, so
  **there is no zoom in practice** (UNCERTAIN).
* A missing file shows a Windows message box with the path as its text and the caption "Not exists"
  (`FUN_005e5dfd`; caption role UNCERTAIN).
* LBUTTONDOWN on the content goes to the empty `4eb760`.
* BACK → Main.

## 15. Arming screen (0x1f, `arm.trx`, content ctor `FUN_005045a0`, vtable `0x6045f0`)

**Panels** (`arm.trx`, screen coordinates):
* Left panel `pArm`:
  * Fly (15,55) 111×35, Push
  * TacticalDisplay (15,98) 111×35, Push
  * AA (14,143) 35×20, AG (50,143) 35×20, Misc (85,143) 35×20, CheckGroup 1
* Bottom1 panel `pFormation`, CheckGroup 1: Alpha (153,427) 72×40, Bravo (228,427), Charlie (307,427),
  Delta (381,427).
* Header `sArming tArm`. `screens/sarming.bmp` does not exist; the jet art paints the whole content.

**Weapon database** (`CMissionWeapons`, object `0x8387b0`):
* Layout: `+0` count, `+4` array of 0x1a0-byte records, `+8` default loadouts, `+0x320` current,
  `+0x638` saved.
* Loaded by `FUN_004ed950` from the mission's bdb Weapons part.

| rec off | field (bdb Weapons) |
|---|---|
| +0 | weapon id (`0x1e`) |
| +4 | type code (`0x780`) |
| +8 | **menu tab**: 0 AA = types 540,550,570,580,600,610; 1 AG = 500,510,560,590,635,640,650; 2 Misc = 565, 660. Other types (620/630 SAMs, 0) are dropped. |
| +0xc | name (`0x708`, 80 chars) |
| +0x5c | icon file = **parent directory of the Present model path + ".BMP"**, loaded from `<DataPath>\Bmp\Arm\Weapons\` (`\WEAPONS\MK84\MK84_M.XFR` → `mk84.bmp`, 49×30 24-bit) |
| +0x160 | weight in lb (`0x758`), float |
| +0x164 | `int[9]` max count allowed per station for the current flight's aircraft |
| +0x19c | icon HBITMAP |

Misc holds fuel tanks ("2700LB" etc.) and pods (TV POD, ECM, FLIR). Guns are type 565.

**Per-station allowed counts** (`FUN_004edf60(flight)`, called on every flight change):
1. Every weapon's `+0x164[9]` is zeroed.
2. The flight leader's bdb Objects entry has a list of `CDMEWeaponLoadItem`s, each with 9 station
   flags (`raw`). For each item, for weapon `load.id(0x910)`:
   `max[i] = max(max[i], flag[i] ? load.count(0x906) : 0)`.
3. Only weapons with some `max[i] > 0` appear in the list (`FUN_004ed800`).

Example, F-16:
* AIM-9L on stations 1,2,3,7,8,9, ×1
* MK-83 on 3,4,5,6,7, ×3 (the maximum over its loads)
* 2700LB on 4,6
* 2100LB on 5

**Loadout tables.** Each table is 11 flights × 9 stations × `{id,count}` (0x48 bytes per flight):
* `0x8387b8`: mission defaults;
* `0x838ad0`: current (edited here);
* `0x838de8`: saved.

All three are filled after the mission loads (`FUN_004ee5b0` → `FUN_004ee410(flight)`). Station i
gets the leader's runtime store (`FUN_0044f110`: weapon name and count), matched to a weapon by name.
This equals the mission/bdb `CArmament` hardpoints `[id,count]×9`. F-16 default: AIM-9L, AMRAAM,
MK-83×3, MK-84, –, MK-84, MK-83×3, AMRAAM, AIM-9L (UNCERTAIN whether mission entities override the bdb
default).

**Jet art** (`FUN_00505e30`, on entry and on each flight change). The leader type code is flight
record `+0x350` (`0x689f18+n·0x370`).

| type code | 100 | 110 | 120 | 130 | 140 | 160 | 180 | 190 | 200 |
|---|---|---|---|---|---|---|---|---|---|
| art name | F-16 | F-15 | F4e | Kfir | Lavi2 | Mig23 | Mig29 | Mirage | Phantom |

* Files:
  * `bmp/arm/jets/<name>.bmp`, 454×357: a front view with baked station boxes, the jet name,
    "CURRENT LOAD" and "MAX T.O.W.".
  * `<name>.trx`, in this format:
    * line 1: base weight `%f` (`+0x64`);
    * line 2: max take-off weight `%f` (`+0x68`);
    * line 3: station count;
    * then `station x y` lines: station 1..9, (x,y) = content-local top-left of a **51×32** box
      (`.rdata 0x604478`).
* F-16 example: 27600 / 48000; stations 1 (1,210), 2 (21,261), 3 (81,261), 4 (141,261), 5 (201,282),
  6 (261,261), 7 (321,261), 8 (381,261), 9 (401,210).
* Other jets: Kfir has stations 2–8, MiG-23 has 3–7, Mirage has 3,4,5,6,7 at x 21, 81, 201, 321, 381.
* The view is from the front. Stations 1–4 (screen left) are on the aircraft's **right** wing, 5 is
  the centreline, and 6–9 are on the left wing.

**Paint** (`5048e0`, into the back buffer), in this order:
1. The jet bmp.
2. The flight name ("Alpha", flight record +0x328): `TextOut` at **(22,18)**, Arial p11 weight 500,
   RGB(0,255,0), transparent.
3. Switch the font to **`fnt/key.fnt`**: a Windows raster FNT, face "key", 6×8 fixed-pitch bold,
   loaded via AddFontResource and EnumFontFamilies (`FUN_004ed4c0`).
4. Max T.O.W. as `"%g Lb"` in rect **(377,333)–(431,352)**.
5. Current load as `"%g Lb"` in rect **(126,333)–(182,352)**.
   * Current = base + Σ count×weight (`FUN_005062b0`).
   * Drawn in **red** RGB(255,0,0) when current > max.
   * Both numbers use `DT_CENTER|DT_VCENTER|DT_SINGLELINE`.
6. Station highlights for the weapon selected in the list (`+0x5c`, set by the list's selection
   notify `517830` → `FUN_00506140`):
   * every enabled station with `max[i] > 0` gets `arm/hibox.bmp` (53×44) at (x−1,y−1);
   * the jet art is then re-blitted over (x+1,y+1, 49×40), leaving only a frame.
7. For each loaded station (count ≠ 0), all in green RGB(0,255,0), key.fnt, centred:
   * the weapon icon at (x+1,y+1), 49×30;
   * `"%dx%s"` (count, name) in (x+2,y+23)–(x+51,y+32);
   * `"%g"` = count×weight in (x+2,y+33)–(x+51,y+42).

**Weapon list** (`FUN_005171b0`; created on msg 0x549 via `FUN_00517290`):
* Frame position **(17,168)**, size 106×261 = `arm/weaponslb.bmp`.
* Inner list at local (30,4)–(102,256): **6 rows × 42 px**, 72 wide. The background is cropped from
  weaponslb.
* Scrollbar at local (2,2)–(17,261): thumb `arm/slider.bmp` 15×35, arrows `slupb_0..2`/`sldownb_0..2`
  15×18.
* Row item (`518100`):
  * a box `arm/item.bmp` 51×32 (`hiitem.bmp` when selected), centred in the cell, i.e. at local
    (40, 9+42·row);
  * the weapon icon at box+1;
  * the name in key.fnt at box (1,22)–(50,31), RGB(0,255,0) when selected, RGB(0,128,0) otherwise.
* Tab filter `FUN_00517880(tab)`: bdb order, only weapons of this tab with a non-zero allowed count.
  Row 0 is then selected.

**Mouse** (content message map `0x6044b0`). Cursors: `Cur/move.cur` on hover, `grab.cur` while
dragging, the arrow otherwise (`SETCURSOR 504e40`).
* **Drag from the list:**
  * Press on a row icon and drag across the frame. The list draws the icon and name under the cursor.
  * Release over a station (`518020` → `FUN_00506180`).
  * The drop is accepted only if that station is enabled and `max[i] > 0`. It sets
    `{id, count = max[i]}`, so the count is **always the maximum for that station**.
* **Drag from a station** (LBUTTONDOWN `504f30`):
  * Picks up the loaded weapon, switches the AA/AG/Misc tab to its tab, and selects it in the list.
  * **Clears the station.**
  * Drag feedback: the icon plus `"%dx%s"` (`505300`).
  * LBUTTONUP (`505650`) drops it by the same rule (count = station max). Dropping anywhere else
    leaves the weapon removed.
* **Right-click on a loaded station** (`5056f0`): count −1. At 0 the station is empty.
* **DEFAULT button**: `arm/defbut_0..2` 85×23 at content-local **(198,330)** (`.rdata 0x6044a0/a4`),
  bottom-bar button class `FUN_004f13b0`. On notify 0x13 (`504eb0`):
  * current = defaults, for all flights;
  * in SP, the defaults are also applied to the aircraft (`FUN_004ee7b0(0..10)`);
  * the saved table is not touched.

**Buttons** (`FUN_005057e0`):
* **AA / AG / Misc**: set the tab `+0x104`, refilter, and select row 0.
  * The initial tab is AA (checked in `505ae0`).
  * In MP, when `DAT_00838420==2` and the mission is 0x29a/0x213, AG and Misc are disabled.
* **Alpha…Foxtrot**:
  * The current loadout is validated first (see below). On failure, the old flight button is
    re-checked (`FUN_00504130`).
  * Otherwise `DAT_00836d1c` = n, and `505e30` reloads the art, stations and list.
  * Enable rules (`FUN_005064d0`) are the same as on the TSD:
    * the flight exists;
    * the leader type is flyable (`FUN_005063e0`: 100,110,120,130,140,160,180,190,200);
    * `FUN_00503cc0(n)`.
* **TacticalDisplay** → code 1. **Fly** → code 2. **BACK** → code 3. For BACK, the frame calls content
  vfunc `+0xd4` = `505ac0`, which returns 0 so that the frame's own BACK switch is skipped.
* Each of these three actions first runs validation (`FUN_00505b60`). Any failure cancels the action.
  Here w = count × weight, and 0.05 is at `0x6045ec`.
  * current > max → msg 0x32 "WARNING! Overweight." (OK box).
  * Σw(stations 1–4) > Σw(6–9) + 0.05·current → msg 0x34 "…right wing heavy."
  * Σw(6–9) > Σw(1–4) + 0.05·current → msg 0x33 "…left wing heavy."
* Then `FUN_00505ca0(code)`:
  * If current ≠ saved (memcmp of 0x318 bytes), it shows msg **0x23 "Use weapon load?"**, box type 3
    = Yes/No/Cancel. The third argument is 6 in SP and 7 in MP (meaning UNCERTAIN). The reply comes
    back as message 0x55d with wParam = code.
  * Otherwise it proceeds as if No was pressed.
* Reply handler `FUN_00505d40(code, answer)`:
  * **Cancel** (2): stay on the screen.
  * **Yes** (6): saved = current. In SP, `FUN_004ee610` → `FUN_004ee7b0` writes the loadouts to the
    aircraft of every existing flight.
  * **No** (7): current = saved (revert).
  * After Yes or No, act on the code:
    * code 1 or 3 → TSD (0x1e);
    * code 2 (Fly) in SP → `FUN_004d2ae0(flight)` (the leader becomes the player), `FUN_004d74a0`,
      frame exit code `+0x5c`=2, `FUN_004e7c40` (the menu closes and the flight starts);
    * code 2 in MP → `FUN_00506310` locks all buttons (`+0x54`=1) and waits for the session.
* **MAIN** uses the default vfunc `+0xd8` (returns 1), so it shows msg 8 as documented in §3.2. An
  unsaved loadout is neither applied nor reverted.

## 16. In-flight pause and On-The-Fly menu (flight window `CFlightWnd::OnGameEvent` 0x4daad0)

Traced from the disassembly (unless marked UNCERTAIN). **Not built yet**: the keys belong to the
key-table / in-flight input work in `game/terrain/terrain_view.gd`, so this is the spec for it.

Key commands reach several windows (`FUN_004df3d0` → WM 0x532 to CIAFWindow and, via `FUN_005df3b7`,
its children); the real handler is the flight window's map entry 0x601440 → **0x4daad0** (byte table
0x4dad38, jump table 0x4dad20): 0x7a Esc → 0x4dab65, 0x84 Ctrl+P → 0x4dac6f, 0x85 Ctrl+O → 0x4dacc9,
0x88 → screenshot `IafJets%03d.bmp` (0x4db120). The CIAFWindow default path (0x4e1f45 → `FUN_004ccb80`)
drops them. Globals: `DAT_00836454` paused (`FUN_004e0160`), 0x82edb0 menu object (+0 open,
`FUN_004ed1d0`), 0x836460 message box (`FUN_004e5100`), `DAT_0069492c+8` sim clock (0 stopped,
1 running, 2 paused). **Single player only** (both keys ignored when `[0x694990+4]` ≠ 0).

**Game events** (`FUN_004cce00`, dispatched at once): **0x75 pause**: param 0 → pause every sound
channel (`FUN_004c50b0` → 0x542eb0, buffers stopped, state 2), stop force feedback (`FUN_004dd840`),
freeze the clock (`FUN_004d0ff0`); **0x76 resume**: clock runs (`FUN_004d0f80`), channels resume where
they stopped (`FUN_004c50c0` → 0x542ef0). While the clock is not running `FUN_004ccb80` drops every
event except 0x6d, 0x73, 0x74, 0x76, 0x83: no flight commands while paused or in the menu.

### 16.1 Ctrl+P "Pause mission" (0x4dac6f)
Only with no message box and the menu closed; toggles `FUN_004da750` / `FUN_004da7e0`.
* Pause: the key manager's enable counter −1 (`FUN_004ddd50(-1)`): from the next poll **every key
  except Ctrl+P is ignored** (`FUN_004df3d0` @4df527; joystick buttons are not filtered); held keys get
  their release commands (`FUN_004df2b0(1)`, plus 0x532 id 0x16 lParam 0xfffbffff, UNCERTAIN: view-pan
  reset); if the clock runs, `this+0x40 = 1` and event 0x75(0): sim frozen, sounds paused (not muted);
  `DAT_00836454 = 1`. The mouse is not passed to the cockpit (0x4db020 / 0x4db060).
* Unpause: counter +1; event 0x76 if `this+0x40`; `DAT_00836454 = 0`.
* Drawn in the flight render `FUN_004d7960` (@4d7c31..4d7dba) over the frozen scene: **"II  PAUSE"**
  (0x6456c8, two spaces), blinking 500 ms on / 500 ms off (timeGetTime, `DAT_0082ee78/7c`), GDI on the
  back surface, Arial size 50 weight 900 (`FUN_004ed600`, created @4d7366), transparent, RGB(0,255,0),
  TA_BOTTOM|TA_LEFT at (30, 450); then a full-screen white wash alpha 0x63 (`FUN_00402280` → D3D
  `FUN_00419d60`; the software renderer draws none). UNCERTAIN: the wash is drawn after the text, so
  it also covers it.
* On the FlyTSD screen (0x20) the menu frame handles Ctrl+P itself (`FUN_004ec3a0` / `FUN_004ec610`):
  screen snapshot dithered with `misc/pat1.bmp` (SRCAND) + `pat2.bmp` (SRCPAINT), window disabled,
  same "II  PAUSE" at (30, 450) (`FUN_004e7a90`).

### 16.2 Ctrl+O "On-The-Fly menu" (0x4dacc9)
Only when not paused; toggles open (`FUN_004da840`) / close (`FUN_004da8c0`). **Esc does not open it**:
Esc (0x4dab65) unpauses if paused, else closes the menu if open, else leaves the flight for the FlyTSD
screen 0x20 (flight window +0x150 = 1, `FUN_004d7670(1)`; the "TSD and cockpit toggle"); in network
mission 0x21d Esc shows msg 8 (host) / msg 11 (client).
* Open: builds the layout (`FUN_004ecf90(hdc, 5, 10)`), releases held keys, event 0x75(0) (sim and
  sounds paused). The key counter and `DAT_00836454` are not touched. Close: frees the GDI objects,
  event 0x76, `[+0x154]+0x300 = 1` (UNCERTAIN: cockpit redraw).
* Not a dialog or bitmap: GDI drawn every frame into the 640×480 back surface (`FUN_004ed1e0`, from
  `FUN_004d7960` @4d7d4f); while a message box is up the box is drawn instead of the menu.
* **Six items** (ctor `FUN_004ecf40`, msgs lines upper-cased with `_strupr`): RESUME MISSION (18),
  END MISSION (19), RESTART MISSION (20), NEW MISSION (21), PREFERENCES (22), QUIT GAME (24).
  "Calibrate joystick" (23) is not in the menu (no other user found, UNCERTAIN).
* GDI: normal brush RGB(191,191,175), hover brush RGB(159,159,128), frame pens 2 px RGB(186,186,173)
  (PS_INSIDEFRAME) and 1 px RGB(21,21,19); font Arial size 10 weight 400 (`FUN_004ed600`; exact cell
  height UNCERTAIN).
* Layout: W = widest label, H = tallest label (GetTextExtentPoint32); item i: left 15, right
  15 + W + 16, top 20 + i·(H + 23), bottom top + H + 16 (7 px gaps). Outer frame (5, 10) to (item right
  + 10, last bottom + 10).
* Draw: each item a RoundRect 16×16 with the 1 px dark pen, filled with the hover brush when the
  cursor is inside, else the normal brush; label black, transparent, TA_CENTER|TA_TOP at
  ((l + r)/2, top + 8). Then the frame with NULL_BRUSH (scene visible between items): RoundRect 20×20
  with the 2 px light pen, then with the 1 px dark pen.
* Mouse only (no keyboard navigation): left click → hit test `FUN_004ed450` → `FUN_004da920(item)`
  (jump table 0x4daab8).

### 16.3 Item actions (`FUN_004da920`)
Boxes: `FUN_004e2790(msg, reply, group, 4 = Yes/No)`, the in-surface box (`FUN_004e2810`, which also
disables the keys). **NO closes the box; the menu stays open, paused.**
* **Resume mission**: as closing the menu.
* **End mission**: msg 8 Yes/No → reply 0x559 wParam 3 (`FUN_004e1a10`): event 0x76 + 0x7e (unload
  0x74, IAFWnd 0x7d → `FUN_004d7670(1)`), exit code 3 → **Debrief (screen 0x22)**.
* **Restart mission**: msg 9 → code 4 → screen 0x23: the debrief content with "Replay_Mission"
  (`FUN_004fcfb0`; still records the attempt, `FUN_004f4fb0`), which after 50 ms (SetTimer in
  `FUN_004fd6d0`, WM_TIMER 0x4fd850) presses Replay itself → mission reloaded (`FUN_004ec6a0`,
  `Mis\Wait.bmp`) → pre-flight TSD (0x1e); missions 400–499 go straight into the flight. (The debrief
  art may flash for ~50 ms, UNCERTAIN.)
* **New mission**: msg 10 → code 6 → screen 0x25 ("New_Mission", auto-pressed the same way) →
  `FUN_004fdd00`: missions 111–117 → 0xe, 121–127 → 0xf, 131–137 → 0x10, 211–217 → 0x11,
  221–227 → 0x12, 231–237 → 0x13, 311–315 → 7 Basic, 321–326 → 8 Combat, 0x213 / 0x29a → 0x14,
  multiplayer → 0x18, else 1 Main.
* **Preferences**: no box; flight window +0x150 = 2, `FUN_004d7670(1)` → screen 0x21 (in-flight
  Preferences, §12; Gameplay tab disabled). BACK or Esc (frame +0x5c = 5) → `CMainWindow::OnMenuDestroyed` 0x4e2030, exit 5 (@4e20d0): the
  flight window is recreated (`FUN_004d7310`), event 0x76, and the menu **reopens** (paused again).
* **Quit game**: msg 7 Yes/No → reply 0x556 (`FUN_004e1660`): unload, credits, exit (§3.2).
* Compare Ctrl+Q (0x86 → `FUN_004e1800`): msg 8 with the DEBRIEF / CONTINUE / EXIT buttons (not
  Yes/No); msg 11 for a multiplayer client.

Sounds: pause and menu pause all channels and resume them on 0x76 (docs/sound.md); the FlyTSD entry
posts 0x75 with param 1, which does not pause sounds.
