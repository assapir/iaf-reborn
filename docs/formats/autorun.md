# CD autorun launcher — Jauto.exe, poster.bmp, buttons.bmp, .rgn

The CD's `AUTORUN.INF` runs `JAUTO.EXE`, "Jane's Autorun": a poster with eight buttons that installs, starts or
uninstalls the game. The English and Hebrew CDs carry the same art. `iaf-extract` copies these files from the CD root
into `assets/install/autorun/` (lower case); `iaf-extract --autorun <iso> <out>` copies only them. The port shows the
launcher behind an Extras switch: docs/front-end.md §18.1.

| file | what it is |
|---|---|
| `jauto.exe` | the program (MFC, 516 KB). Its resources hold the dialog (type 5, id 102) and the startup sound (type `WAVE`, id 131) |
| `poster.bmp` | the dialog's background, 468×451, 24-bit: the gold Jane's plaque with "IAF" and eight empty bricks |
| `poster.rgn` | named rectangles in `poster.bmp`: the button slots `B1`..`B8` |
| `buttons.bmp` | the button art, 1500×456, 8-bit with a palette: 8 labels × 4 states × 3 languages |
| `buttons.rgn` | named rectangles in `buttons.bmp`: one cell per label, state and language (96) |

The disassembly comes from a Ghidra headless run on `JAUTO.EXE` with `tools/ghidra/DumpDecompiled.java` (not part of
the repo's decompile); addresses below are Jauto.exe's.

## .rgn: named rectangles
Each bitmap Jauto.exe loads has a sidecar `<name>.RGN` (format string `%s.RGN`, read in `FUN_00401d84`). It is a list
of named rectangles, not a Win32 region. All integers are little-endian.

```
count     u32
repeat count times (40 bytes each):
  name    char[4]       NUL-padded, e.g. "B1", "NE3"
  points  u32           always 4
  p[4]    (i32 x, i32 y) top-left, top-right, bottom-right, bottom-left
```

The exe keeps each entry as the rectangle left = p0.x, top = p0.y, right = p1.x, bottom = p2.y (right and bottom
exclusive) and looks cells up by name. Parser: `crates/iaf-formats/src/rgn.rs`.

`poster.rgn` (8 entries): the bricks, in rows of 3, 2 and 3. Their widths match the labels' cells.

| slot | rect (x, y, w, h) | button |
|---|---|---|
| B1 | 0, 328, 128, 38 | HELP |
| B2 | 128, 328, 212, 38 | INSTALL |
| B3 | 340, 328, 128, 38 | PLAY |
| B4 | 0, 366, 234, 38 | JANE'S ONLINE |
| B5 | 234, 366, 234, 38 | REGISTER ONLINE |
| B6 | 0, 404, 128, 38 | PREVIEWS |
| B7 | 128, 404, 212, 38 | UNINSTALL |
| B8 | 340, 404, 128, 38 | QUIT |

`buttons.rgn` (96 entries): `<state><language><n>`.

- state: `N` normal, `F` focused (the "active" row), `P` pressed, `D` disabled;
- language: `E` English, `F` French, `G` German;
- n: the button, 1..8 as in the slot table.

Columns: label n at x = 0, 128, 340, 468, 702, 936, 1064, 1276 (widths as the slots). Rows: 38 px each, English
N/F/P/D at y 0/38/76/114, French at 152.., German at 304... The French and German sets leave REGISTER ONLINE blank.

## The dialog (resource 102)
- Style `WS_POPUP | WS_VISIBLE | DS_SETFONT`, extended `WS_EX_APPWINDOW`: no caption, no border, a plain rectangle.
  On `WM_SHOWWINDOW` (`FUN_00404506`) it takes the poster's size, centred on the screen
  (`screen/2 − size/2`), and moves each button to its slot `B<n>`.
- Eight buttons, ids 0x3e8..0x3ef in slot order, style `BS_OWNERDRAW | WS_TABSTOP`. PLAY (0x3ea) and UNINSTALL (0x3ee)
  carry `WS_DISABLED`.
- `WM_PAINT` (`FUN_004043d0`) blits `poster.bmp` at (0, 0); `WM_ERASEBKGND` does nothing.
- `WM_DRAWITEM` (`FUN_00404629`) blits the cell `<state><language><n>` at the button's (0, 0). The state is `P` when
  `ODS_SELECTED`, else `F` when `ODS_FOCUS` (and it sends `DM_SETDEFID` with the button's id, so the focused
  button is the default one), else `D` when `ODS_DISABLED`, else `N`.
- So "active" is the keyboard focus: the first enabled tab stop has it at the start; Tab and the arrow keys move it;
  a mouse press moves it to the pressed button. The pointer passing over a button changes nothing.
- Esc is `IDCANCEL` and ends the dialog.

## Start-up (`FUN_00404191`)
1. If the mutex `IAFRunningMutex` exists (the game runs), it exits. If a window "Jane's Autorun" exists, it brings
   that one to the front instead.
2. It loads `POSTER.BMP` / `BUTTONS.BMP` with their `.RGN` files.
3. `PlaySoundA(131, SND_RESOURCE | SND_ASYNC)`: the `WAVE` resource 131, a RIFF WAVE of 16-bit mono PCM at 22 050 Hz,
   232 492 bytes (about 5.3 s), played while the dialog opens.
4. `FUN_00404e3e` enables PLAY when `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths` has a key named
   `IAFJets.EXE`, and UNINSTALL when `...\CurrentVersion\UnInstall` has a key named `I A F`.

## Language (`FUN_0040471e`, `FUN_004047d0`)
The value `Locale` of `HKCU\Control Panel\International` (hex LCID) picks the set: primary language 0x0c → `F`,
0x07 → `G`, 0x409 → `E`, any other → `U`, which the art lookup turns into `E`. Help files follow the same letter (`U`
finds no help file).

## Buttons (message map at 0x42f8e8)
| button | id | action |
|---|---|---|
| HELP | 0x3e8 | `WinHelpA` on `<cd>\EAHELP\EAHELP.HLP`, `Frhelp.hlp` or `GRhelp.HLP` by language (`FUN_00404806`); failure: "Could not start help" |
| INSTALL | 0x3e9 | runs `<cd>\SETUP.EXE`, then ends the dialog (`FUN_004048cc`) |
| PLAY | 0x3ea | runs the path of the `App Paths\IAFJets.EXE` key, then ends the dialog (`FUN_0040499f`) |
| JANE'S ONLINE | 0x3eb | `ShellExecuteA("open", "http://www.janes.ea.com/online")` (`0x404b24`) |
| REGISTER ONLINE | 0x3ec | runs `<cd>\EREG\ERegIP.EXE` (`FUN_00404b47`) |
| PREVIEWS | 0x3ed | `WinHelpA` on `<cd>\Previews\PREVIEWS.HLP` (`FUN_00404c20`) |
| UNINSTALL | 0x3ee | runs the `UninstallString` of the `I A F` uninstall key, then ends the dialog (`FUN_00404cad`) |
| QUIT | 0x3ef | ends the dialog (`0x404e36`) |
