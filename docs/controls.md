# Controls — the original key table

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 and lists what the patch changed.

Jane's IAF drives every keyboard / joystick command through one table of **117 records** in
`iafjets.exe`. iaf-reborn converts it (`iaf-convert keys` → `assets/converted/keys.json`), shows it on
the Preferences Controls page (docs/front-end.md §12.7) and looks every in-flight key up in it
(`game/controls/key_table.gd`, `game/terrain/terrain_view.gd`).

## 1. The table

* **Default table** `0x64c3c8` (`.data`), 117 × 36 bytes, copied (`rep movs 0x41d` dwords) into the
  working table `0x83b99c` (prefs object `0x83b810 + 0x18c`) by the prefs constructor `FUN_004f0750`
  and by the prefs loader `FUN_004f08f0` before it reads `prefs.dat`. DEFAULT on the Controls page
  copies it again (@511ca5).
* Record layout (9 dwords):

  | offset | field |
  |---|---|
  | +0x00 | press command id |
  | +0x04, +0x08 | press p1, p2 |
  | +0x0c | release command id (0 = none) |
  | +0x10, +0x14 | release p1, p2 |
  | +0x18 | key: DirectInput scancode (ushort) \| modifier << 16 (0 = none) |
  | +0x1c | joystick button, 0-based (−1 = none) |
  | +0x20 | listed on the Controls page (≠ 0) |

* **Record i ↔ `txt/keys.trx` line i (0-based).** Resolved: `FUN_004e3c70` loads the 117 lines of
  keys.trx into `0x833900 + 100·i` (loop to `0x8366b4` = 117 × 100), and the dispatcher
  `FUN_004e0b80` traces `"pressed %s"` / `"released %s"` with `0x833900 + 100·i` for the record i it
  just matched; the Controls row painter `FUN_00512080` also draws label i next to record i's key. So
  line 0 "TSD and cockpit toggle" is record 0 (Esc, command 122), and the earlier "116 records at
  0x64c3e8" reading was off by one: `0x64c3e8` is record 0's +0x20 (the listed flag), which is the
  field `FUN_00511cf0` walks (`0x64c3e8 .. 0x64d45c`, stride 36) to fill the list.
* **Modifiers** (one per key): 0x11 Ctrl, 0x22 Shift, 0x44 Alt, 0x88 Win (`FUN_004e08c0`: L/R Ctrl
  0x1d/0x9d, Shift 0x2a/0x36, Alt 0x38/0xb8, Win 0xdb/0xdc). A key matches only with exactly its
  modifier (`FUN_004e0b80` compares the scancode and the modifier byte), so W and Shift+W are
  different keys.
* **Key names** (`FUN_005121e0` → `FUN_005122b0`): "Ctrl + " / "Shift + " / "Alt + " / "Win + "
  (the first bit set, in that order) + the scancode's name from a switch of 121 names ("Esc", "1",
  "Backspace", "Numpad 7", "Up", "SysRQ", …; codes without a case have no name). The converter reads
  the strings from the exe at the addresses of that switch (`keys.json` `key_names`).
* **Joystick button names** (`FUN_00512a90`): `"Button %d"` with button + 1; none = empty.

## 2. Dispatch (in flight)

* Keyboard (`FUN_004e0b80`, called per DirectInput key event by `FUN_004e0a60`): the **first**
  record whose key equals scancode | modifier; a press sends its press command, a release its release
  command (id 0 = nothing), as `WM 0x532` (wParam = id, lParam = p2 << 16 | p1 & 0xffff).
  Joystick buttons (`FUN_004e0dc0`) do the same through +0x1c.
* Rewrites before sending: ids 2 (roll) and 3 (pitch) become id 1 (stick) with the other axis taken
  from the last keyboard value (`DAT_008338f0` x, `DAT_008338f4` y); ids 0x8b / 0x8c (EO pan) become
  0x8a the same way.
* Dropped: ids 2 / 3 while a joystick stick axis is used, 5 / 6 / 9 while a throttle axis is used,
  10 while a rudder axis is used (`this+0x18..0x2c`, UNCERTAIN flag names; docs/flight-model.md §7);
  every id except 0x84 while `this+0x10 < 1` (UNCERTAIN: not in flight).
* Held commands are the records with a release command: pitch / roll / rudder, EO pan, view pan,
  zoom. Everything else is one-shot.
* v1.1: the key table (all 117 records byte-identical, `0x64c3c8`; v1.0 `0x647ff8`), this dispatch and the mute key
  are unchanged. One handler changed: **Z "Full screen weapon MFD"** (event 0x1f in `FUN_004cd630`) now forwards to
  the cockpit and sets view 1 / 5 (v1.0 did nothing). Not ported (no full-screen MFD yet).

### iaf-reborn

* The Godot key is turned into the scancode by its **physical** position (`physical_keycode`, the
  US layout, like DirectInput; the tests send plain keycodes, which are used when there is no
  physical code) and one modifier (Ctrl, then Shift, Alt, Meta = Win).
* One-shot commands run on the key press. The held commands (ids 2, 3, 10) are polled every frame:
  while a record's key and exactly its modifier are down, its press value is the stick / rudder
  target; our sprung keyboard stick then moves toward it (2.5 /s, back at 4 /s — ours, the original
  sets the value at once). Original y +100 (Up arrow, "Pitch up") is our stick **forward** (nose
  down), as before (docs/flight-model.md §7: `S+0x2e4 = −y`); the keys.trx wording is the original's.
* **Own keys** (not in the table, or on an original key whose command we do not implement yet) run
  only when the table gives no implemented command for that key:

  | key | ours | the original's command on that key |
  |---|---|---|
  | Esc | quit-mission box (msg 8) / menus | TSD and cockpit toggle (122, not built) |
  | C | cockpit ↔ external | Time compress (119, not built) |
  | F1 | cockpit | Cockpit / HUD view (28,1) — the same, runs through the table |
  | F2 | external view | Back view (22,180, not built) |
  | F12 | flight-info line on / off | I-mode (124, not built) |
  | V | panel up / down | — |
  | PgUp / PgDn | slide the panel | — |
  | = / − / Numpad + / − | cockpit zoom | Zoom in / out (20 / 21) — runs through the table, one step per press (the original zooms while held) |

  If the player binds one of these keys to a command we implement, the command wins.
* Joystick buttons are not handled in flight yet (no joystick support); the Controls page shows and
  edits the button column only as data.
* Rebinds: `Settings.key_bindings` = {record: [key, button]} for the records that differ from the
  default, saved in the `[keys]` section of `user://settings.cfg` as `r<index> = [key, button]`.
  Configs without that section load the defaults.

## 3. Full original key list

"Listed" = shown on the Controls page (92 of 117). Our Extras option **"All keys on the Keyboard page"**
(`show_all_keys`, off = the original list) also lists every unlisted record with a label (115 of 117: stick,
rudder, RPM ± 5, view / EO pans, the cheats, screen capture; not the two unlabelled records 115 / 116), in table
order, so they can be rebound (e.g. the numpad rudder on keyboards without a numpad); they are stored in `[keys]`
like the others and the flight looks every key up through the table. Rebinding a cheat only stores its key (the
cheats are not built). "iaf-reborn" = what the command does here (— = not
implemented yet: the key is ignored unless one of our own keys above is on it). Command ids are the
original's `WM 0x532` wParam; p1 / p2 as stored.

| # | Function (keys.trx) | Default key | Joy | Press (id, p1, p2) | Release | Listed | iaf-reborn |
|---|---|---|---|---|---|---|---|
| 0 | TSD and cockpit toggle | Esc |  | (122, 0, 0) |  | yes | — |
| 1 | Quit mission | Ctrl + Q |  | (134, 3, 0) |  | yes | quit-mission box (msg 8) |
| 2 | Pause mission | Ctrl + P |  | (132, 0, 0) |  | yes | — |
| 3 | On-The-Fly menu | Ctrl + O |  | (133, 0, 0) |  | yes | — |
| 4 | Mute sound toggle | Ctrl + M |  | (135, 0, 0) |  | yes | — |
| 5 | Time compress toggle x2 x4 x1 | C |  | (119, 0, 0) |  | yes | — |
| 6 | Normal time | Ctrl + C |  | (120, 0, 0) |  | yes | — |
| 7 | Idle thrust | 1 |  | (9, 0, 0) |  | yes | throttle = p1 · 0.01 |
| 8 | 65% thrust | 2 |  | (9, 10, 0) |  | yes | throttle = p1 · 0.01 |
| 9 | 70% thrust | 3 |  | (9, 19, 0) |  | yes | throttle = p1 · 0.01 |
| 10 | 80% thrust | 4 |  | (9, 38, 0) |  | yes | throttle = p1 · 0.01 |
| 11 | 90% thrust | 5 |  | (9, 56, 0) |  | yes | throttle = p1 · 0.01 |
| 12 | Military thrust | 6 |  | (9, 74, 0) |  | yes | throttle = p1 · 0.01 |
| 13 | 100 + AB1 | 7 |  | (9, 78, 0) |  | yes | throttle = p1 · 0.01 |
| 14 | 100 + AB2 | 8 |  | (9, 100, 0) |  | yes | throttle = p1 · 0.01 |
| 15 | RPM - 5 | 9 |  | (6, 0, 0) |  | no | throttle −0.0925 |
| 16 | RPM + 5 | 0 |  | (5, 0, 0) |  | no | throttle +0.0925 |
| 17 | Eject (x3) | E |  | (18, 0, 0) |  | yes | eject |
| 18 | Autopilot level/navigation/off | A |  | (16, 0, 0) |  | yes | — |
| 19 | Flaps up/down | F |  | (12, 0, 0) |  | yes | flaps |
| 20 | Landing gear up/down | G |  | (14, 0, 0) |  | yes | gear |
| 21 | Fire extinguisher | X |  | (73, 0, 0) |  | yes | — |
| 22 | Brakes in/out | B |  | (17, 0, 0) |  | yes | brakes |
| 23 | Landing parachute | Shift + B |  | (19, 0, 0) |  | yes | — |
| 24 | Pitch up | Up |  | (3, 0, 100) | (3, 0, 0) | no | stick pitch (held) |
| 25 | Pitch down | Down |  | (3, 0, -100) | (3, 0, 0) | no | stick pitch (held) |
| 26 | Roll left | Left |  | (2, -100, 0) | (2, 0, 0) | no | stick roll (held) |
| 27 | Roll right | Right |  | (2, 100, 0) | (2, 0, 0) | no | stick roll (held) |
| 28 | Snap view 135 left | Numpad 1 |  | (22, 225, 1) | (22, -1, -1) | yes | — |
| 29 | Snap view back | Numpad 2 |  | (22, 180, 2) | (22, -1, -2) | yes | — |
| 30 | Snap view 135 right | Numpad 3 |  | (22, 135, 3) | (22, -1, -3) | yes | — |
| 31 | Snap view 90 left | Numpad 4 |  | (22, 270, 4) | (22, -1, -4) | yes | — |
| 32 | Straight ahead view | Numpad 5 |  | (28, 1, 0) |  | yes | cockpit view |
| 33 | Snap view 90 right | Numpad 6 |  | (22, 90, 6) | (22, -1, -6) | yes | — |
| 34 | Snap view 45 left | Numpad 7 |  | (22, 315, 7) | (22, -1, -7) | yes | — |
| 35 | Snap view up 30 | Numpad 8 |  | (22, 0, 8) | (22, -1, -8) | yes | — |
| 36 | Snap view 45 right | Numpad 9 |  | (22, 45, 9) | (22, -1, -9) | yes | — |
| 37 | Rudder left | Numpad 0 |  | (10, -100, 0) | (10, 0, 0) | no | rudder (held) |
| 38 | Rudder right | Decimal |  | (10, 100, 0) | (10, 0, 0) | no | rudder (held) |
| 39 | Next waypoint | W |  | (101, 0, 0) |  | yes | next waypoint |
| 40 | Previous waypoint | Shift + W |  | (102, 0, 0) |  | yes | previous waypoint |
| 41 | FLIR on/off | I |  | (90, 6, 0) |  | yes | — |
| 42 | Damage report | D |  | (90, 4, 0) |  | yes | MFD: damage |
| 43 | ECM Jammer on/off | J |  | (70, 0, 0) |  | yes | — |
| 44 | Laser on/off | L |  | (106, 0, 0) |  | yes | — |
| 45 | NAV mode on | N |  | (98, 0, 0) |  | yes | — |
| 46 | Change HUD color | H |  | (123, 0, 0) |  | yes | HUD colour |
| 47 | Contact tower | Ctrl + T |  | (107, 0, 0) |  | yes | — |
| 48 | Pan EO weapon/FLIR up | Ctrl + Up |  | (140, 0, 100) | (140, 0, 0) | no | — |
| 49 | Pan EO weapon/FLIR left | Ctrl + Left |  | (139, -100, 0) | (139, 0, 0) | no | — |
| 50 | Pan EO weapon/FLIR right | Ctrl + Right |  | (139, 100, 0) | (139, 0, 0) | no | — |
| 51 | Pan EO weapon/FLIR down | Ctrl + Down |  | (140, 0, -100) | (140, 0, 0) | no | — |
| 52 | Full screen weapon MFD | Z |  | (31, 0, 0) |  | yes | — |
| 53 | Activate TSD on MFD | T |  | (90, 3, 0) |  | yes | MFD: TSD |
| 54 | Master modes | M |  | (99, 0, 0) |  | yes | — |
| 55 | Deselect target | Backspace |  | (49, 0, 0) |  | yes | — |
| 56 | Radar modes | Q |  | (36, 0, 0) |  | yes | radar mode cycle |
| 57 | Radar on/AA/AG | R |  | (43, 0, 0) |  | yes | radar A-A / A-G |
| 58 | Select next target | Return | Button 3 | (38, 0, 0) |  | yes | — |
| 59 | Select previous target | Shift + Return |  | (39, 0, 0) |  | yes | — |
| 60 | Radar standby | S |  | (44, 0, 0) |  | yes | radar standby |
| 61 | Boresight mode on | \ |  | (45, 0, 0) | (46, 0, 0) | yes | — |
| 62 | Increase radar range | . |  | (33, 0, 0) |  | yes | radar range + |
| 63 | Decrease radar range | , |  | (34, 0, 0) |  | yes | radar range − |
| 64 | Fire gun | Tab | Button 1 | (66, 0, 0) | (67, 0, 0) | yes | — |
| 65 | Select next AG weapon | [ |  | (60, 0, 0) |  | yes | — |
| 66 | Select next AA weapon | ] |  | (62, 0, 0) |  | yes | — |
| 67 | Back toggle AG weapons | Shift + [ |  | (60, 0, 0) |  | yes | — |
| 68 | Back toggle AA weapons | Shift + ] |  | (62, 0, 0) |  | yes | — |
| 69 | Fire selected weapon | Space | Button 2 | (64, 0, 0) | (65, 0, 0) | yes | — |
| 70 | Chaff | Insert |  | (68, 0, 0) |  | yes | — |
| 71 | Flare | Delete | Button 4 | (69, 0, 0) |  | yes | — |
| 72 | Jettison fuel tanks/bombs | Shift + C |  | (72, 0, 0) |  | yes | — |
| 73 | Cockpit/HUD view | F1 |  | (28, 1, 0) |  | yes | cockpit view |
| 74 | Back view | F2 |  | (22, 180, 0) | (22, -1, 0) | yes | — |
| 75 | Padlock view | F3 |  | (28, 22, 0) |  | yes | — |
| 76 | Visual lock on target close | Shift + F3 |  | (103, 0, 0) |  | yes | — |
| 77 | Radar target view | F4 |  | (28, 9, 0) |  | yes | — |
| 78 | Threat view | F5 |  | (28, 23, 0) |  | yes | — |
| 79 | Player-wingman view | F6 |  | (28, 24, 0) |  | yes | — |
| 80 | Player to target view | F7 |  | (28, 25, 0) |  | yes | — |
| 81 | Target-player view | F8 |  | (28, 26, 0) |  | yes | — |
| 82 | Fly-by view | F9 |  | (28, 19, 0) |  | yes | — |
| 83 | Chase view | F10 |  | (28, 6, 0) |  | yes | external view |
| 84 | Weapon view | F11 |  | (28, 27, 0) |  | yes | — |
| 85 | I-mode | F12 |  | (124, 0, 0) |  | yes | — |
| 86 | Pan up | Shift + Numpad 8 |  | (26, 1, 0) | (26, 0, 0) | yes | — |
| 87 | Pan down | Shift + Numpad 2 |  | (27, -1, 0) | (27, 0, 0) | yes | — |
| 88 | Pan left | Shift + Numpad 4 |  | (24, -1, 0) | (24, 0, 0) | yes | — |
| 89 | Pan right | Shift + Numpad 6 |  | (23, 1, 0) | (23, 0, 0) | yes | — |
| 90 | Pan up | Shift + Up |  | (26, 1, 0) | (26, 0, 0) | no | — |
| 91 | Pan down | Shift + Down |  | (27, -1, 0) | (27, 0, 0) | no | — |
| 92 | Pan left | Shift + Right |  | (23, 1, 0) | (23, 0, 0) | no | — |
| 93 | Pan right | Shift + Left |  | (24, -1, 0) | (24, 0, 0) | no | — |
| 94 | Zoom out | Numpad - |  | (21, -1, 0) | (21, 0, 0) | yes | cockpit zoom out (one step) |
| 95 | Zoom in | Numpad + |  | (20, -1, 0) | (20, 0, 0) | yes | cockpit zoom in (one step) |
| 96 | Zoom out | - |  | (21, -1, 0) | (21, 0, 0) | yes | cockpit zoom out (one step) |
| 97 | Zoom in | = |  | (20, -1, 0) | (20, 0, 0) | yes | cockpit zoom in (one step) |
| 98 | Engage other target | Alt + W |  | (108, 4, 0) |  | yes | — |
| 99 | Engage my target | Alt + E |  | (108, 3, 0) |  | yes | — |
| 100 | Tactical formation | Alt + T |  | (108, 5, 0) |  | yes | — |
| 101 | Protect me | Alt + P |  | (108, 1, 0) |  | yes | — |
| 102 | Close formation | Alt + C |  | (108, 6, 0) |  | yes | — |
| 103 | Go home | Alt + B |  | (108, 2, 0) |  | yes | — |
| 104 | Chat: Compose message to all players | ~ |  | (137, 0, 0) |  | yes | — |
| 105 | Chat: Compose message to friends | Alt + ~ |  | (137, 1, 0) |  | yes | — |
| 106 | Chat: Compose message to foes | Shift + ~ |  | (137, 2, 0) |  | yes | — |
| 107 | Chat: Compose message to last target | Ctrl + ~ |  | (137, 3, 0) |  | yes | — |
| 108 | Cheat: reload weapons | Ctrl + W |  | (110, 26, 0) |  | no | — |
| 109 | Cheat: dump flight model data | Shift + D |  | (110, 28, 0) |  | no | — |
| 110 | Cheat: stop dump flight model data | Ctrl + Return |  | (51, 0, 0) |  | no | — |
| 111 | Cheat: explosion effect | Shift + S |  | (110, 27, 0) |  | no | — |
| 112 | Cheat: flight model hover | Shift + R |  | (110, 4, 0) |  | no | — |
| 113 | Cheat: toggle target cheat view | U |  | (90, 7, 0) |  | no | — |
| 114 | Capture screen image | Shift + T |  | (110, 25, 0) |  | no | — |
| 115 |  | Shift + F |  | (110, 12, 0) |  | no | — |
| 116 |  | SysRQ |  | (136, 0, 0) |  | no | — |

Notes on the list:
* Throttle presets (records 7–14) send command 9 with p1 = 0, 10, 19, 38, 56, 74, 78, 100; the
  player controller (`FUN_0044a240` case 9 → `FUN_0044e470` motion 2) sets throttle = p1 · 0.01.
  (Earlier ports guessed 0.0925 steps; these are the exe's numbers.)
* Snap views (28–36): command 22 with (angle, n) and release (22, −1, −n); padlock / external views
  (73–84) are command 28 with the view id.
* 86–93: view pan with Shift + Numpad 8/2/4/6 (listed) and Shift + arrows (not listed).
* Wingman commands (98–103) use Alt; the chat keys (104–107) use `~` with modifiers.
* Cheats (108–115) and screen capture (116, SysRQ) are not listed.

## 4. Unlabelled and cheat commands

Traced in v1.1 (objdump; v1.0 has the same handlers). **The keys.trx labels of 108–114 do not match
what the exe does**: the strings the handlers print are the reliable names. Records 115 / 116 are hidden
and unlabelled, but work.

**Common path.** The dispatcher (`FUN_004e0b80`) does not look at the "shown" flag: a hidden record fires
like any other (first matching key; in flight only, `this+0x10 ≥ 1`). There is **no debug flag or build
switch**: every handler below is live in the retail exe. Commands 0x6e (110), 0x33 (51) and 0x5a (90) go
through `FUN_004cd3b0` (queued while the sim clock runs, dropped while paused / in the menu) to
`FUN_004cd630`. Case 0x6e → `FUN_004d19d0`, a switch on p1 (jump table 0x4d1a8c / bytes 0x4d1ab4):

| p1 | handler |
|---|---|
| 4, 12, 25, 27, 28 | `FUN_00450780(p)` on the player controller `DAT_00699308` |
| 26 | `FUN_0055fa00` (this = 0x8415a8) |
| 13 | `FUN_004d1ad0`; 19 → `FUN_004081a0` (empty); 20 / 21 → FM `+0xca8` = 1 / 0 (no key uses 13, 19–21) |

`FUN_00450780` (jump table 0x450a20 / bytes 0x450a38) does nothing unless `DAT_00699320` ≠ 0, the
controller's unit is that unit (the four id words at `+0x30` +8..+0x14 match), and the control mode
(status `+0x14`) is 3 (the player flies). "Local" below = `!netgame(DAT_0082f398) || unit local`.
Messages go to the console line (`FUN_0044a060`).

| # | key | keys.trx label | what it really does | gate in retail v1.1 |
|---|---|---|---|---|
| 108 | Ctrl+W | Cheat: reload weapons | Re-reads the weapon-motion table: clears the `0x8415a8` map (`FUN_0055fba0`) and re-parses `<[Weapons] weaponsPath of iaf.ibx = WeaponsMotion>\Weapons.ibx` (`FUN_0055f420`, `WEAPON_%03d` sections). A developer hot-reload; with the shipped file it changes nothing. No message. | **Live**, SP and MP. |
| 109 | Shift+D | Cheat: dump flight model data | Toggles `DAT_0062f064` (starts 1): "Cheat: Text messages on" / "Cheat: Text messages off". Off = mission subtitles skipped (docs/mission-runtime.md). | **Live**; only when local. |
| 110 | Ctrl+Return | Cheat: stop dump flight model data | Controller case 0x33: only in HUD mode 8 (`ctl+0x5c`, set by `FUN_00449810` for master mode 4 with the HARM, weapon 0x24e): if the object from `ctl+0x44c` vfunc +0x20 has `+0x348` > 1, calls `ctl+0x44c` vfunc +0x2c(1). UNCERTAIN: probably steps the HARM target list. Command 0x34 (no key) calls +0x2c(0). | **Live**. |
| 111 | Shift+S | Cheat: explosion effect | Toggles `ctl+0x970`, the weapons-safety override: "Safety Off" / "Safety On" (v1.1 texts from `[DamageLocalization] SafetyOff / SafetyOn`, defaults as shown). While `ind[9]` ≠ 0 (gear handle down) "Fire gun" (0x42) and "Fire selected weapon" (0x40) are refused unless it is set. | **Live**; the toggle always, the message only when local. |
| 112 | Shift+R | Cheat: flight model hover | Prints "Cheat: Reload Weapons" after `FUN_00456ce0` on the stores (`ctl+0xf0`): resets them (`FUN_0053bed0`, `FUN_00454010`, state 5) unless busy (`+0xb8` / `+0xbc`). UNCERTAIN: the exact refill. | **Single player only** (`[DAT_00699350+4]` = 0), and only if `ind[9]` = 0, `ind[5]` ≠ 0, `ctl+0xb4` = 1 and HUD mode `ctl+0x5c` = 4 (meanings UNCERTAIN). |
| 113 | U | Cheat: toggle target cheat view | Command 0x5a(7) = SET_MFD_SCREEN(7): puts the RWR page on an MFD (the same event as T / I / D; ignored if it already shows). Not a cheat. | **Live**. |
| 114 | Shift+T | Capture screen image | p1 25 → `FUN_004081a0`, which is a bare `ret` (v1.0 `FUN_004d5560` is empty too): **does nothing**. | Dead (the handler was compiled out). |
| 115 | Shift+F | (none) | **"Cheat: Refuel internal tank"** (`FUN_0044e250`): if the unit's FM vfunc +0x6c = 0x1e (controlled aircraft) and `FUN_0045ee10(unit, now)` = 0 (UNCERTAIN meaning), and fuel (`veh+0x568`+0x1c) < internal capacity (FM `+0xc4c`→`+0xc0`) × 2.2046 (kg→lb, 0x600b28), sends the unit motion input 0x18 with value = capacity (refill). The message shows even when already full. | **Live**, SP and MP (no local test). |
| 116 | SysRQ | (none) | **The real screen capture**: command 0x88, handled by the flight window (`FUN_004dc280` → `FUN_004dc8d0`). GetDC on the primary / back surface, DIB of its bitmap + palette, written with `OpenFile(OF_CREATE)` to **`IafJets%03d.bmp`** in the working directory; the counter `DAT_008338d8` starts at 0 each run, so old captures are overwritten. | **Live**, SP and MP. |

So the retail cheats are: refuel (Shift+F), stores reload (Shift+R, SP only), weapons safety off
(Shift+S), text messages on/off (Shift+D), and the SysRQ screenshot; Ctrl+W re-reads weapons.ibx,
Ctrl+Return is a HARM-mode function and U the RWR page. The "flight model dump / hover", "explosion
effect" and "target cheat view" of the labels do not exist in the retail exe.
