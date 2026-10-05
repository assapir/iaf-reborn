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
* One-shot commands run on the key press. The held commands (ids 2, 3, 10) are polled every frame for
  press / release edges (a record's key and exactly its modifier down): a press sets its axis **at once**
  to the press value (±1), a release to the release value (0), the last event wins — as the original
  (no ramp, curve or spring anywhere between the key and `S+0x2e4/0x2e8`: `FUN_004e0b80` → controller
  `FUN_0044a240` case 1 → motion 1 `FUN_0059f3d0`, v1.0 identical; the joystick poller `FUN_004df560` is
  linear too, ±100 by `MulDiv`). So Up held + Down pressed = full pull, releasing either centres. The only
  smoothing is the flight model's lift ramp (G_Rate, docs/flight-model.md §8 "Keyboard stick"). Original
  y +100 (Up arrow, "Pitch up") is our stick **forward** (nose down), as before (docs/flight-model.md §7:
  `S+0x2e4 = −y`); the keys.trx wording is the original's.
* **Own keys** (not in the table, or on an original key whose command we do not implement yet) run
  only when the table gives no implemented command for that key:

  | key | ours | the original's command on that key |
  |---|---|---|
  | Ctrl+F1 | quit-mission box (msg 8) | — (was on Esc, now the TSD toggle 122) |
  | Ctrl+F2 | cockpit ↔ external | — (was on C, now time compression 119, and F2, now the back view) |
  | Ctrl+F12 | flight-info line on / off | — (was on F12, I-mode 124, which is not built) |
  | F1 | cockpit | Cockpit / HUD view (28,1) — the same, runs through the table |
  | V | panel up / down | — |
  | PgUp / PgDn | slide the panel | — |
  | = / − / Numpad + / − | cockpit art zoom (cockpit views) | Zoom in / out (20 / 21): the orbit distance in the external views (views.md §4) |

  If the player binds one of these keys to a command we implement, the command wins. Moving our functions to
  Ctrl + F-keys when the original commands on their keys were built is a user decision; no table record uses
  Ctrl + F-keys.
* Joystick buttons, axes and the hat: §5.
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
| 0 | TSD and cockpit toggle | Esc |  | (122, 0, 0) |  | yes | unpause / close the menu / FlyTSD and back (views.md §1) |
| 1 | Quit mission | Ctrl + Q |  | (134, 3, 0) |  | yes | quit-mission box (msg 8) |
| 2 | Pause mission | Ctrl + P |  | (132, 0, 0) |  | yes | pause (views.md §1) |
| 3 | On-The-Fly menu | Ctrl + O |  | (133, 0, 0) |  | yes | On-The-Fly menu (views.md §1) |
| 4 | Mute sound toggle | Ctrl + M |  | (135, 0, 0) |  | yes | Mute on / off |
| 5 | Time compress toggle x2 x4 x1 | C |  | (119, 0, 0) |  | yes | time rate 1 → 2 → 4 → 1 (views.md §2) |
| 6 | Normal time | Ctrl + C |  | (120, 0, 0) |  | yes | time rate 1 |
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
| 18 | Autopilot level/navigation/off | A |  | (16, 0, 0) |  | yes | autopilot off → level → NAV → off (docs/autopilot.md); in NAV the throttle keys are dropped |
| 19 | Flaps up/down | F |  | (12, 0, 0) |  | yes | flaps |
| 20 | Landing gear up/down | G |  | (14, 0, 0) |  | yes | gear |
| 21 | Fire extinguisher | X |  | (73, 0, 0) |  | yes | fire extinguisher: one charge, puts out an engine fire (damage.md §5.3) |
| 22 | Brakes in/out | B |  | (17, 0, 0) |  | yes | brakes |
| 23 | Landing parachute | Shift + B |  | (19, 0, 0) |  | yes | drag chute: armed in the air, deployed on the ground / at touchdown, again = jettison (visual only in the original; with Flight data = Real it brakes, docs/real-aircraft.md §2.2) |
| 24 | Pitch up | Up |  | (3, 0, 100) | (3, 0, 0) | no | stick pitch (held) |
| 25 | Pitch down | Down |  | (3, 0, -100) | (3, 0, 0) | no | stick pitch (held) |
| 26 | Roll left | Left |  | (2, -100, 0) | (2, 0, 0) | no | stick roll (held) |
| 27 | Roll right | Right |  | (2, 100, 0) | (2, 0, 0) | no | stick roll (held) |
| 28 | Snap view 135 left | Numpad 1 |  | (22, 225, 1) | (22, -1, -1) | yes | snap view while held (views.md §4) |
| 29 | Snap view back | Numpad 2 |  | (22, 180, 2) | (22, -1, -2) | yes | snap view while held (views.md §4) |
| 30 | Snap view 135 right | Numpad 3 |  | (22, 135, 3) | (22, -1, -3) | yes | snap view while held (views.md §4) |
| 31 | Snap view 90 left | Numpad 4 |  | (22, 270, 4) | (22, -1, -4) | yes | snap view while held (views.md §4) |
| 32 | Straight ahead view | Numpad 5 |  | (28, 1, 0) |  | yes | cockpit ↔ HUD only |
| 33 | Snap view 90 right | Numpad 6 |  | (22, 90, 6) | (22, -1, -6) | yes | snap view while held (views.md §4) |
| 34 | Snap view 45 left | Numpad 7 |  | (22, 315, 7) | (22, -1, -7) | yes | snap view while held (views.md §4) |
| 35 | Snap view up 30 | Numpad 8 |  | (22, 0, 8) | (22, -1, -8) | yes | snap view while held (views.md §4) |
| 36 | Snap view 45 right | Numpad 9 |  | (22, 45, 9) | (22, -1, -9) | yes | snap view while held (views.md §4) |
| 37 | Rudder left | Numpad 0 |  | (10, -100, 0) | (10, 0, 0) | no | rudder (held) |
| 38 | Rudder right | Decimal |  | (10, 100, 0) | (10, 0, 0) | no | rudder (held) |
| 39 | Next waypoint | W |  | (101, 0, 0) |  | yes | next waypoint (NAV re-targets it) |
| 40 | Previous waypoint | Shift + W |  | (102, 0, 0) |  | yes | previous waypoint (NAV re-targets it) |
| 41 | FLIR on/off | I |  | (90, 6, 0) |  | yes | MFD: FLIR page + FLIR on, with a FLIR pod (not a toggle; mfd.md) |
| 42 | Damage report | D |  | (90, 4, 0) |  | yes | MFD: damage |
| 43 | ECM Jammer on/off | J |  | (70, 0, 0) |  | yes | ECM on / off, light 6 (weapons.md §10) |
| 44 | Laser on/off | L |  | (106, 0, 0) |  | yes | laser flag (FLIR pod only; the designation is not built: laser bombs fall free, weapons.md §9.8) |
| 45 | NAV mode on | N |  | (98, 0, 0) |  | yes | master mode NAV (weapons.md §4) |
| 46 | Change HUD color | H |  | (123, 0, 0) |  | yes | HUD colour |
| 47 | Contact tower | Ctrl + T |  | (107, 0, 0) |  | yes | the tower: in the air near an Israeli base "proceed to runway" and the landing calls; near no tower / an Arab base a radio click; on the ground nothing (the tower talks by itself; docs/radio.md §2) |
| 48 | Pan EO weapon/FLIR up | Ctrl + Up |  | (140, 0, 100) | (140, 0, 0) | no | EO camera slew / lock on release (mfd.md) |
| 49 | Pan EO weapon/FLIR left | Ctrl + Left |  | (139, -100, 0) | (139, 0, 0) | no | EO camera slew / lock on release (mfd.md) |
| 50 | Pan EO weapon/FLIR right | Ctrl + Right |  | (139, 100, 0) | (139, 0, 0) | no | EO camera slew / lock on release (mfd.md) |
| 51 | Pan EO weapon/FLIR down | Ctrl + Down |  | (140, 0, -100) | (140, 0, 0) | no | EO camera slew / lock on release (mfd.md) |
| 52 | Full screen weapon MFD | Z |  | (31, 0, 0) |  | yes | — |
| 53 | Activate TSD on MFD | T |  | (90, 3, 0) |  | yes | MFD: TSD |
| 54 | Master modes | M |  | (99, 0, 0) |  | yes | master mode cycle NAV / AA / AG + button click |
| 55 | Deselect target | Backspace |  | (49, 0, 0) |  | yes | radar: drop the lock (radar.md) |
| 56 | Radar modes | Q |  | (36, 0, 0) |  | yes | radar mode cycle |
| 57 | Radar on/AA/AG | R |  | (43, 0, 0) |  | yes | radar A-A / A-G |
| 58 | Select next target | Return | Button 3 | (38, 0, 0) |  | yes | radar: next target (radar.md) |
| 59 | Select previous target | Shift + Return |  | (39, 0, 0) |  | yes | radar: previous target (radar.md) |
| 60 | Radar standby | S |  | (44, 0, 0) |  | yes | radar standby |
| 61 | Boresight mode on | \ |  | (45, 0, 0) | (46, 0, 0) | yes | radar boresight while held (radar.md) |
| 62 | Increase radar range | . |  | (33, 0, 0) |  | yes | radar range + |
| 63 | Decrease radar range | , |  | (34, 0, 0) |  | yes | radar range − |
| 64 | Fire gun | Tab | Button 1 | (66, 0, 0) | (67, 0, 0) | yes | gun: fire while held (gear down only with Safety off) |
| 65 | Select next AG weapon | [ |  | (60, 0, 0) |  | yes | next AG store |
| 66 | Select next AA weapon | ] |  | (62, 0, 0) |  | yes | next AA store |
| 67 | Back toggle AG weapons | Shift + [ |  | (60, 0, 0) |  | yes | next AG store (the same event: forward, as the original) |
| 68 | Back toggle AA weapons | Shift + ] |  | (62, 0, 0) |  | yes | next AA store (the same event) |
| 69 | Fire selected weapon | Space | Button 2 | (64, 0, 0) | (65, 0, 0) | yes | release the selected store (gun, IR missiles, bombs, rockets; HUD mode 1..8; weapons.md) |
| 70 | Chaff | Insert |  | (68, 0, 0) |  | yes | chaff (weapons.md §10) |
| 71 | Flare | Delete | Button 4 | (69, 0, 0) |  | yes | flare (weapons.md §10) |
| 72 | Jettison fuel tanks/bombs | Shift + C |  | (72, 0, 0) |  | yes | jettison the tanks (1st press), then the bombs (2nd) |
| 73 | Cockpit/HUD view | F1 |  | (28, 1, 0) |  | yes | cockpit ↔ HUD only (views.md §4) |
| 74 | Back view | F2 |  | (22, 180, 0) | (22, -1, 0) | yes | back view while held |
| 75 | Padlock view | F3 |  | (28, 22, 0) |  | yes | padlock (radar target) |
| 76 | Visual lock on target close | Shift + F3 |  | (103, 0, 0) |  | yes | padlock the object nearest the screen centre |
| 77 | Radar target view | F4 |  | (28, 9, 0) |  | yes | radar-target view |
| 78 | Threat view | F5 |  | (28, 23, 0) |  | yes | threat view (the RWR's nearest emitter; views.md §4) |
| 79 | Player-wingman view | F6 |  | (28, 24, 0) |  | yes | player-wingman view |
| 80 | Player to target view | F7 |  | (28, 25, 0) |  | yes | player-to-target view |
| 81 | Target-player view | F8 |  | (28, 26, 0) |  | yes | target-player view |
| 82 | Fly-by view | F9 |  | (28, 19, 0) |  | yes | fly-by view |
| 83 | Chase view | F10 |  | (28, 6, 0) |  | yes | chase view |
| 84 | Weapon view | F11 |  | (28, 27, 0) |  | yes | weapon view (IR missiles, falling bombs) |
| 85 | I-mode | F12 |  | (124, 0, 0) |  | yes | — |
| 86 | Pan up | Shift + Numpad 8 |  | (26, 1, 0) | (26, 0, 0) | yes | cockpit free look / orbit turn |
| 87 | Pan down | Shift + Numpad 2 |  | (27, -1, 0) | (27, 0, 0) | yes | cockpit free look / orbit turn |
| 88 | Pan left | Shift + Numpad 4 |  | (24, -1, 0) | (24, 0, 0) | yes | cockpit free look / orbit turn |
| 89 | Pan right | Shift + Numpad 6 |  | (23, 1, 0) | (23, 0, 0) | yes | cockpit free look / orbit turn |
| 90 | Pan up | Shift + Up |  | (26, 1, 0) | (26, 0, 0) | no | cockpit free look / orbit turn |
| 91 | Pan down | Shift + Down |  | (27, -1, 0) | (27, 0, 0) | no | cockpit free look / orbit turn |
| 92 | Pan left | Shift + Right |  | (23, 1, 0) | (23, 0, 0) | no | cockpit free look / orbit turn |
| 93 | Pan right | Shift + Left |  | (24, -1, 0) | (24, 0, 0) | no | cockpit free look / orbit turn |
| 94 | Zoom out | Numpad - |  | (21, -1, 0) | (21, 0, 0) | yes | orbit distance (external); cockpit art zoom, one step (ours); the release zooms the EO camera |
| 95 | Zoom in | Numpad + |  | (20, -1, 0) | (20, 0, 0) | yes | orbit distance (external); cockpit art zoom, one step (ours); the release zooms the EO camera |
| 96 | Zoom out | - |  | (21, -1, 0) | (21, 0, 0) | yes | orbit distance (external); cockpit art zoom, one step (ours); the release zooms the EO camera |
| 97 | Zoom in | = |  | (20, -1, 0) | (20, 0, 0) | yes | orbit distance (external); cockpit art zoom, one step (ours); the release zooms the EO camera |
| 98 | Engage other target | Alt + W |  | (108, 4, 0) |  | yes | wingman command 4 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
| 99 | Engage my target | Alt + E |  | (108, 3, 0) |  | yes | wingman command 3 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
| 100 | Tactical formation | Alt + T |  | (108, 5, 0) |  | yes | wingman command 5 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
| 101 | Protect me | Alt + P |  | (108, 1, 0) |  | yes | wingman command 1 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
| 102 | Close formation | Alt + C |  | (108, 6, 0) |  | yes | wingman command 6 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
| 103 | Go home | Alt + B |  | (108, 2, 0) |  | yes | wingman command 2 → the wingman's brain, negative reply if it cannot (docs/radio.md §3) |
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
* Wingman commands (98–103) use Alt (command 108, p1 = the command; docs/radio.md §3); the chat keys (104–107) use `~`
  with modifiers.
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

## 5. Joystick (DirectInput)

One DirectInput joystick, polled every idle frame (in the menus too) by `FUN_004df560` from the app's idle
handler `FUN_004e1df0`; there is no joystick code anywhere else. Addresses v1.1 (v1.0 has the same code).

### 5.1 The original

* **Setup** (`FUN_004df3c0`, at startup only): `DirectInputCreateA` (version 0x500), keyboard, then
  `EnumDevices(DIDEVTYPE_JOYSTICK, FUN_004e0f90, attached only)` (`FUN_004e01b0`). The callback keeps the
  **first joystick it can open** (returns DIENUM_STOP after it, CONTINUE on a failure): `c_dfDIJoystick2`
  (`0x57c690`, `DIJOYSTATE2`), cooperative level 5 (exclusive | foreground), buffer size 1024; then
  `this+0x18 = 1` (a stick). No hot-plug: a device plugged in later is not seen; a lost one only logs errors.
* **Axes** (`FUN_004e0f90` @4e10fb..4e1352, DIPROP_RANGE read with GetProperty, DIPROP_DEADZONE set):

  | role | DirectInput axis | range kept at | dead zone | "has the axis" flag |
  |---|---|---|---|---|
  | stick x | lX (ofs 0) | +0x154 / +0x164 | 2500 | (+0x18) |
  | stick y | lY (ofs 4) | +0x158 / +0x168 | 2500 | (+0x18) |
  | throttle | lZ (ofs 8) | +0x15c / +0x16c | none | +0x1c when lZ has a range |
  | rudder | **range and dead zone of slider 0 (ofs 0x18), else lRz (0x14)** | +0x160 / +0x170 | 2500 | +0x20 when either exists |

  The poller always **reads lRz** for the rudder: a stick with a slider but no Rz reads 0 there (full left
  rudder with the PEDALS choice). Original quirk, kept in spirit (§5.2: Godot cannot tell axes apart anyway).
  DIPROP_DEADZONE 2500 = DirectInput reports the centre within 25 % of the half range and scales the rest over
  the full range (DirectInput's behaviour, not the exe's; UNCERTAIN detail of the scaling).
* **No calibration, curves or centring of its own.** The ranges are DirectInput's (Windows' joystick
  calibration); "Calibrate joystick" (msg 23) is in msgs.trx but nothing shows it (docs/front-end.md §16).
  The formulas ignore the range minimum (`MulDiv(v, ±scale, max − min)`), i.e. they assume DirectInput's
  default 0..65535.
* **The poller** (`FUN_004df560`, only while acquired, `this+0xc`): keyboard state and buffered keys, then
  `Poll` + `GetDeviceState` of the joystick (0x110 bytes), then, **each sent only when its integer value
  changed** (`WM 0x532`, the key table's message):

  | when | value | event |
  |---|---|---|
  | `+0x24` (FLIGHT CONTROLS joystick) | x = `MulDiv(lX, 200, range) − 100` (log "X_AXIS : movement") | GEV 1 (x, last y) |
  | `+0x24` | y = `MulDiv(lY, −200, range) + 100` (pushed = +100) | GEV 1 (last x, y) |
  | `+0x28` (THROTTLE joystick) | t = `MulDiv(lZ, −100, range) + 100` (lever forward = 100) | GEV 9 (t, ·) |
  | `+0x2c` (RUDDER pedals) | r = `MulDiv(lRz, 200, range) − 100` ("Z_AXIS : rotation") | GEV 10 (r, ·) |
  | `+0x24` and POV 0 changed | see below | GEV 22 |

  GEV 1 / 9 / 10 are the same events as the stick, throttle-preset and rudder keys (docs/flight-model.md §8),
  so the axis drives `S+0x2e4 / 0x2e8` (stick, `−y·0.01`, `x·0.01`), the throttle (`t·0.01`, with the AB
  delay of motion 2) and the rudder (`r·0.01`) exactly like the keys, linear, no curve. The keyboard's
  pitch / roll rewrite is not involved (the joystick sends GEV 1 itself); the autopilot's ±51 rule (case 1 /
  0xa) and the NAV throttle drop (case 9) apply as to the keys. The stored values (+0x144 x, +0x148 y,
  +0x14c throttle, +0x150 rudder) live as long as the program, so a lever that did not move since the last
  flight sends nothing at the next start.
* **POV hat** (rgdwPOV[0], `DAT_0064ace0`, compared with the last `DAT_0064acdc`, both 0xffff at start):
  0 → (0, 8), 4500 → (45, 9), 9000 → (90, 6), 13500 → (135, 3), 18000 → (180, 2), 22500 → (225, 1),
  27000 → (270, 4), 31500 → (315, 7), 0xffff → (−1, 5); other values send nothing. Before each new one the
  previous one's release (−1, −digit) is sent (`DAT_008338e0 / e4`, `DAT_008338ec` = something was sent).
  These are the numpad snap-view keys' own (p1, p2) (records 28–36), so the hat **is** the snap views (and
  turns the orbit in the external views, docs/views.md §4.2).
* **Buttons** (buffered data, offsets 0x30..0xaf = buttons 0..127, merged with the key events by sequence
  number): a press (data & 0x80) is queued in the held list and `FUN_004e0dc0(data, button)` runs; a release
  runs it only if that button is in the held list (and removes it); an event equal to a held one is skipped.
  `FUN_004e0dc0` posts msg 0x555 (the Keyboard page's capture, `FUN_00511fb0`, docs/front-end.md §12.7) and
  sends the press / release command of the **first record whose +0x1c is that button** — as stored: no
  drops, no "not in flight" gate, no roll / pitch rewrite (so a button on Roll / Pitch sends GEV 2 / 3, which
  the controller `FUN_0044a240` has no case for: nothing; a button on Rudder sends GEV 10: works).
* **Key drops** (`FUN_004e0b80`, keys only): ids 2 / 3 while `+0x24 && +0x18`, 5 / 6 / 9 while
  `+0x28 && +0x1c`, 10 while `+0x2c && +0x20` — the Devices choice **and** a device with that axis. Without a
  joystick the flags +0x18..0x20 are 0 (`FUN_004e0230`), so the Devices page changes nothing.
* **Flush** (`FUN_004e0a60(1)`: pause, On-The-Fly menu, losing focus): every held key and button sends its
  release, then GEV 22 (−1, −5) and the last POV becomes 0xffff (a held hat direction is sent again).
* **Getters**: `FUN_004e0f00 / 0f20` = stick x / y while used (else 0), `FUN_004e0f40` = throttle (0..100)
  while used (else −1). `FUN_005a29d0` (autopilot leaving NAV) posts motion 2 with `throttle · 0.01`, 0.74
  without an axis (docs/autopilot.md); `FUN_005a28c0` (taking over a jet, from `4a8e70` / `4a9100`) also
  posts the stick at (x · −0.01, y · 0.01) (not ported: no jet switch yet).
* **menu/joy/*.joy** (`FUN_004e1590`, called by the callback with the device's product name,
  `DIDEVICEINSTANCE.tszProductName`): for each `<install>\Joy\*.JOY` in directory order, line 1 is a name;
  if it is **contained in** the product name (`strstr`), the **default** table's button column (`0x64c3e4`,
  stride 36) is set to −1 for all 117 records, then line k (k = 0 for the line after the name) = n puts
  button k on record n − 1 (n in 1..117; 0 or junk = no record); the first matching file wins. Shipped:
  CH F-16 Combat Stick, CH ForceFx, SideWinder Force Feedback Pro, SideWinder Precision Pro, Logitech WingMan
  Extreme. The working table comes from prefs.dat when it exists, so a .joy changes the buttons only on a
  first run and through DEFAULT on the Keyboard page.
* **Force feedback** (`+0x30`, `iaforce.ifr`, the SideWinder FF check): not ported (no hardware; docs/status.md).

### 5.2 iaf-reborn

* `game/controls/joystick.gd` (autoload `Joystick`) = the poller, on **Godot's joypad API** (SDL3 since
  Godot 4.5) instead of DirectInput. Device: the **first connected joypad** (lowest id); one device only.
  Hot-plug works (Godot reports it; the next poll uses the new device; the last values are kept). The log
  prints the device's name, GUID and the axis numbers when one is connected.
* **Axis mapping** (Godot axis numbers in `Settings.joy_axes`, settings.cfg `[devices] joy_axes`, default
  `[0, 1, 2, 3]`): 0 → lX (stick x), 1 → lY (stick y), 2 → lZ (throttle), 3 → lRz (rudder). Godot gives
  −1..1; the port maps it to DirectInput's 0..65535 and runs the original formulas (MulDiv rounding), with
  the 25 % dead zone on x, y and the rudder, none on the throttle. Godot / SDL do not name the axes: a stick
  SDL knows as a gamepad uses the gamepad layout (2 = right stick x, 3 = right stick y), others the device's
  own axis order, so if the throttle or the rudder sit on other numbers, edit `joy_axes`.
* "Has the axis" (+0x1c / +0x20) cannot be read from Godot: a connected device counts as having all four.
* Hat: Godot reports it as the D-pad buttons 11–14 (up, down, left, right); two at once = a diagonal. On a
  stick SDL does not know as a gamepad, raw buttons 12–15 share those numbers (seen on the T.Flight Hotas X:
  button 12 and POV up were the same event, each firing the other's binding). So an **unknown stick gets a
  mapping** at connect (`Joystick._connected`, `Input.add_joy_mapping`): buttons 1–11 keep their numbers,
  12–17 move to Godot 15–20 (misc1, paddles 1–4, touchpad), the hat stays on 11–14, axes 0–3 unchanged, 4 / 5
  become triggers (Godot 0..1, read back as −1..1, `Joystick.axis`). Buttons from the 18th on are lost (Godot
  has 21 gamepad buttons). `Joystick.physical_button` turns an event back into the stick's own number and
  drops the hat (D-pad 11–14 are the POV, not buttons, as in DirectInput), for the flight and the Keyboard page.
  `tools/joyprobe/probe.gd` prints what Godot reports for a stick (name, GUID, known gamepad, each button index
  pressed, each axis' range; `REMAP=1` with our mapping): `godot --path tools/joyprobe -s probe.gd`.
* Buttons: `InputEventJoypadButton` from the device → the flight scene (`terrain_view.gd _joy_button`): the
  first record with that button, its press / release command as the original (no drops, Roll / Pitch do
  nothing, Rudder moves the rudder), a release only after its press; pause / menu release held buttons.
  Godot button n = DirectInput button n ("Button n+1" on the Keyboard page).
* Keyboard page: with the list focused, a joystick button binds the selected function; a taken one asks msg
  37, Yes clears it from the other (−1). Stored with the keys (`[keys] r<i> = [key, button]`).
* `menu/joy/*.joy`: read when a device connects, matched against Godot's device name (SDL's name, which
  may differ from the DirectInput product name), files sorted by name. It changes the **defaults**; our
  rebinds are stored as differences from the defaults, so un-rebound records follow the file.
* Without a device nothing changes: no event, no key dropped, the Devices page stores its choices.
* Not ported: force feedback; the stick re-sync when taking over another jet.


* **Ours: Devices page "Detent = MIL"** (under THROTTLE) (off = the original's linear lever): with the lever in its detent, "Set at lever"
  stores that raw value d; then lever t ≤ d → 74·t/d, t > d → 74 + 26·(t − d)/(100 − d) (`Joystick.detent_map`).
