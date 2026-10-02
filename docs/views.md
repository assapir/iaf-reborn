# In-flight views, pause, menu and time compression

Addresses are `IAFJets.exe` **v1.1**. Keys and command ids: [controls.md](controls.md). The pause / menu GDI details are
in [front-end.md](front-end.md) §16; this page says what the port does with them.

## 1. Pause, On-The-Fly menu, FlyTSD (Esc)

The key commands 0x7a (Esc, "TSD and cockpit toggle"), 0x84 (Ctrl+P) and 0x85 (Ctrl+O) are handled by the flight window
(`CFlightWnd::OnGameEvent` 0x4dc280), not by the game-event queue. Single player only.

| | Ctrl+P pause (0x4dc41f) | Ctrl+O menu (0x4dc479) | Esc (0x4dc315) |
|---|---|---|---|
| allowed | no message box, menu closed | not paused | always |
| does | toggles pause | toggles the menu | unpause if paused, else close the menu if open, else **FlyTSD** (screen 0x20) |
| held keys | release commands sent (`FUN_004e0a60(1)`) | the same | the same (flight window closed) |
| sim clock | stopped if it ran (event 0x75(0)) | stopped (0x75(0)) | stopped (0x75(**1**)) |
| sounds | every channel paused where it is | the same | **not** paused (param 1) |
| keys meanwhile | only Ctrl+P (key manager counter −1) | Esc / Ctrl+O; flight commands dropped (`FUN_004cd3b0`: clock stopped) | the menu frame's keys |
| shown | "II  PAUSE" blinking + white wash | the six-item menu | the TSD screen |

* **Esc in a paused flight**: the key manager passes only Ctrl+P, so the "unpause" branch of Esc is not reachable from
  the flight keys (it is on the FlyTSD, whose frame handles its own Esc).
* **FlyTSD** (`flytsd.trx`: Fly, Visit, the layer checks, Alpha–Delta, Zoom): Esc and BACK (frame handler `FUN_004ea090`
  0x7a, BACK `FUN_004ed1b0`) return to the flight (exit 4) when `FUN_004bb8f9` holds (the player has a unit,
  UNCERTAIN); MAIN (`FUN_004ecff0`) on screens 0x20 / 0x21 opens the Ctrl+Q quit-mission box (`FUN_004e2fa0(3)`). Fly (`FUN_005045b0`) takes the selected formation
  (`FUN_004d31f0`: fly another flight's aircraft) and returns; Visit (`FUN_005046b0`) returns with the selected unit
  (`FUN_004d3450`, UNCERTAIN: a view on it). Ctrl+P on the FlyTSD pauses with a dithered snapshot (`FUN_004edbc0`).
  The TSD overlay shows `"%dx"` (0x654b74) at (Wc − 4, 4), TA_RIGHT, while the time rate is > 1 (@5013f0).
* **Menu items** (`FUN_004dc0d0`): Resume; End mission (msg 8 → debrief); Restart (msg 9 → debrief screen 0x23, which
  presses Replay itself after 50 ms); New mission (msg 10 → screen 0x25, presses New Mission); Preferences (screen 0x21,
  Gameplay tab disabled; BACK / Esc → the flight window is recreated and the menu reopens, still paused); Quit game
  (msg 7). NO closes the box and the menu stays.

### iaf-reborn
* `game/terrain/flight_overlay.gd` draws the pause text / wash and the menu; `terrain_view.gd` `window_key`, `_pause_key`,
  `_menu_key`, `_esc_key`, `menu_choice`. The sim clock stop is the **scene tree's pause** (every sim node stops; the
  overlay, message boxes and the front end over the flight run while paused); the sound pause sets `stream_paused` on
  every playing player of the flight and clears it on resume.
* The FlyTSD and the in-flight Preferences are the front end (`front_end.gd` with `flight` set) on a layer over the
  frozen flight; leaving them calls `close_front_end()`. Changed preferences apply on return (sound, shadows, blackouts).
* Restart / New mission end the flight with the debrief and `Settings.debrief.auto` = the button the debrief presses
  after 50 ms (`replaymission` / `newmission`).
* Not ported: FlyTSD Fly into another formation's aircraft (Fly returns to your own jet), Visit (does nothing),
  Ctrl+P on the FlyTSD, live unit positions on the FlyTSD (it draws the mission's start positions, as before the flight;
  UNCERTAIN what the original draws there), the multiplayer boxes (msgs 11 / 12).

## 2. Time compression (C 0x77, Ctrl+C 0x78)

The single-player sim clock (`DAT_006992d0`, ctor `FUN_004cf910`, vtable 0x604c50) has a rate `+0x48` (start 1.0) and
a cap `+0x58` = 16.0 (0x604bf0). Sim time = real time × rate + offset (`FUN_004cfa50`; `FUN_004cfa10` re-bases the
offset so the time does not jump).
* **C** (`FUN_004cd630` case 0x77 @4cebc0): `r = ftol(rate)` (vfunc +0x20 `FUN_004cf990`); if `r < 4.0` (0x604ba8):
  vfunc 0 `FUN_004cf9c0(r)` = rate + r (only if < 16) → 1 → 2 → 4; else vfunc +4 `FUN_004cf9f0` → 1.0. So x1 → x2 → x4 → x1.
* **Ctrl+C** (case 0x78 @4cec01): vfunc +4 → 1.0.
* **No other rule**: nothing refuses it (on the ground, near enemies, under attack) and nothing resets it. The rate
  functions have no other callers (all vcalls on `DAT_006992d0` checked: @4497b0 HUD copy, @5013f0 FlyTSD text). The
  events go through the queue (`FUN_004cd3b0`), so they only act while the clock runs (not paused / in the menu).
* **Indicator**: the cockpit copies the rate into HUD +0x10f4 every frame (`FUN_00446840` @4497cd); the console drawer
  `FUN_005201b0` (@520414) prints `"%1dX"` (0x65c6c4) with TA_RIGHT at **(630, 10)** in the console font and HUD colour
  while it is > 1.0. The FlyTSD shows `"%dx"` (§1).
* **Stepping**: the original runs one frame with dt = rate × the real frame time; everything on the sim clock (flight
  model, AI, scripts, timers) runs faster. Real-time things stay: the blackout / redout integration uses the frame's
  real time (`DAT_007d1980`, flight-model.md §13.3), the pause blink uses timeGetTime.

### iaf-reborn
* `Engine.time_scale` = rate: every sim `_process` delta and sim timer is scaled, as the original's clock. The player's
  flight model is stepped `rate` times per frame with the uncompressed frame time: its 1 Hz / 5 Hz updates are scheduled
  at fixed sim times (`Aircraft::step`), so this equals one step of rate × dt and stays deterministic; it also keeps each
  call under the 0.25 s clamp. `g_effects.gd` divides by the time scale (real time).
* The `"%1dX"` text: `cockpit.gd` `_draw_console` (shown with the cockpit, like the subtitles). FlyTSD: `tsd.gd`.
* Leaving the flight resets the scale to 1.

## 3. Mute (Ctrl+M, 0x87)
`0x4e3442` flips the Sound page's MUTE (`DAT_0083b8b8`) and applies it (`FUN_004c5930`): `sound_buses.gd`
`toggle_mute()` (not saved; UNCERTAIN whether the original saves it).

## 4. Views (cameras)

Traced in v1.1 (view manager `DAT_00699304`, setters `FUN_0057f2a0` / `FUN_005808c0` / `FUN_005811b0` / `FUN_00581640` /
`FUN_00581390`, per-frame pose `FUN_00582880`, keys in `FUN_004cd630` cases 0x14–0x1c). Port: `game/terrain/views.gd`,
`terrain_view.gd` `_view_command` / `_snap_command` / `_apply_view`.

### 4.1 Architecture
* Three camera slots of 0x490 bytes at `mgr + 8 + k·0x490`: 0 the main camera (every view key), 1 the EO weapon camera
  (MFD), 2 the **snap view** while a Numpad snap key is held (`mgr+0` = active slot). The camera's `+8` is the view type:
  1 cockpit, 5 HUD only, 6 chase / two-object, 9 fly-by / radar target / weapon, 0x10 circle (player killed), 0x12 cockpit
  free look, 0x15 wreck circle, 0x16 padlock.
* Every pose ends with a terrain clamp: cockpit eye ≥ ground + 1 m (0x610e14); orbit ≥ ground + max(15, 0.2·distance)
  (0x610e18, 0x610f14); two-object ≥ ground + 2 m (0x610f30); circle ≥ ground + 15 m.
* External views look at their object with **roll 0**; the cockpit types keep the jet's roll.
* Drawn per type (`FUN_0051f8e0`): 1 / 0x12 / 0x16 (and snaps) the cockpit; 5 the HUD only (no panel); every other view
  only the message lines.
* Field of view: the projection is 50° across 640 px for every view; the camera's zoom `+0xc` (0.75 cockpit, 0.5
  external) only sets the object-culling angle (`FUN_00588ca0`, 50°/z). The external "zoom" keys change the distance.

### 4.2 The keys (event 0x1c, p1 = view id; gate: the player flies the jet, no snap held)
| key | id | view | object missing |
|---|---|---|---|
| F1 / Numpad 5 | 1 | cockpit ↔ HUD only (type 1 → 5 → 1; from an external view the last of the two, `DAT_0083370c`) | — |
| F3 | 0x16 | padlock: the radar target (stored in `ctl+0x804`) or the stored one | nothing |
| Shift+F3 | event 0x67 | padlock the on-screen object nearest the screen centre inside a 4635 m sphere 4635 m ahead (`FUN_0045de60`; cockpit / HUD views only) | nothing |
| F4 | 9 | radar target: path-follow with the swoop (aircraft {300, 700, 300, 10°, ·, 2°} ×1, others {500, 900, 500, 30°, ·, 120°} ×3) | nothing |
| F5 | 0x17 | two-object player → threat (the RWR's nearest listed emitter ≤ 370.8 km after a refresh, `FUN_00451f70`, docs/rwr.md §5); again: padlock it; again: back | nothing |
| F6 | 0x18 | two-object player → wingman (next formation member, else the leader; alive); again: padlock; again: back | nothing |
| F7 / F8 | 0x19 / 0x1a | two-object player → radar target / target → player | nothing |
| F9 | 0x13 | fly-by: random offset point → glides into the chase (type 9) | — |
| F10 | 6 | chase | — |
| F11 | 0x1b | the last released weapon still flying (not chaff, flares, gun rounds): fly-by {300, 700, 300, 10°, ·, 10°} ×6, random | nothing |
| F2, Numpad 1–4, 6–9 (held) | event 22 | snap view in slot 2 (cockpit-like views): head yaw 0, ±36° (0.2π), ±90°, ±144° (0.8π), 180° (F2 / Numpad 2, pitch 12°), Numpad 8 pitch 15°; release → slot 0 | — |
| Shift+Numpad / Shift+arrows | 23, 24, 26, 27 | cockpit: free look; external orbit: ±45°/s heading / pitch | — |
| Numpad + / − , = / − | 20, 21 | external orbit: distance ∓60 m/s | — |
DAT_00833704 = the last id (not for padlock): F5 / F6's "again" rule. In the external views the Numpad snap keys turn the
orbit instead (8 / 2 pitch, 6 / 4 heading; F2 and 1 / 3 / 7 / 9 do nothing there).

### 4.3 The cameras
* **Cockpit** (1, HUD only 5): eye at the jet, the jet's attitude, then head yaw and pitch with `FUN_00585270`:
  pitch = max(head pitch − 5.5°, 0.1·(|yaw| − 90°)). F1 from a turned head returns it to (0, 0) linearly at 45°/s on
  the larger axis (`FUN_0057fa10`). The panel art pans with the head (docs/cockpit.md "Pans": 1920 / AzimutAngleDeg px
  per rad of yaw, (PanelHeight + HUD CenterY) / ElevationAngleDeg per rad of pitch).
* **Free look** (0x12, `FUN_00582370`): press = angle start + rate · 2·t·(1 − 0.9^t) (rate 45°/s, so it speeds up toward
  90°/s), pitch −12°…+85°, yaw unlimited; release: the head stays. Panning breaks a padlock.
* **Padlock** (0x16): the target's direction in the jet's body frame, pitch ≥ −12°, (0, 0) within 5° of the nose; the
  head closes 0.9^(10·dt) of the error per frame step (τ ≈ 0.95 s).
* **Helmet** (free look 0x12 / padlock 0x16): the IR seeker looks along the camera axis within its generation cone,
  and `Dash 1` cockpits draw the HUD as a helmet display at (320, 220) once the head is turned (docs/weapons.md §5.4,
  docs/cockpit.md "HUD dash repeater"). The 3D viewport follows the pan (docs/cockpit.md "3D view").
* **Orbit / path-follow** (6 chase, 9): the trail keeps the target's last 100 frame positions; the camera sits L back
  along that path (L = rope: min dmin = min(1500, scale·size), start 3·dmin, max 20·dmin; a short path goes on along
  −forward), then rotated about the target by the orbit heading (chase 2°) and pitch (chase 10°). F9 / F4 / F11 add the
  **swoop**: the camera starts at the offset point (in the target's body axes, x / z random sign and ×0.5–1.5 when random)
  and the offset decays as 0.3^t into the chase position.
* **Two-object** (6): W = unit(A − B), N = (−W.y, W.x, 0), U = W × N (world axes, z up); eye = A + 150·W + 30·N + 30·U,
  looking at B. The pan / zoom keys have no visible effect there.
* **Circle**: 0x10 (player killed) r 600 m, +600 m, 18°/s from the view's start; 0x15 (an object the external view
  followed was destroyed, event 0x4d): r 600 m, +600 m around the wreck with a wall-clock angle, back to the cockpit 6 s
  later (`FUN_005862a0`); with the attacker within 1000 m it circles the attacker at +300 m instead.
* **Ejection**: fly-by on the jet {1500, 900, −200, −10°, ·, 120°} ×2 random; at t0 + 5 s on the parachuter
  {1000, 600, 200, 230°, ·, 160°} ×2 (docs/mission-runtime.md §5.4).

### 4.4 iaf-reborn
* All of the above, with these gaps: **F5 threat** follows the RWR (`terrain_view.threat()`), but nothing locks the
  player yet (AI combat / enemy weapons), so in flight it finds none and does nothing, as the original with no threat;
  **F4 / F7 / F8 / F3** use the radar's A-A lock / TWS selection (`radar.locked()`); **F6** the AI
  formation (`ai_flights.gd` `_formation_of`); **F11** our IR missiles (the only released weapons; bombs etc. are not
  built); the wreck circle never knows an attacker (no attacker field), so it is always the wreck.
* UNCERTAIN, chosen here: the fly-by offset axes (x right, y forward, z up), the orbit signs (+heading swings the camera
  right, +pitch raises it), object size = the largest dimension of the scaled model box, the visual-lock screen point = the
  screen centre, the two-object side N as written. The trail takes one sample per rendered frame (as the original, frame
  dependent).
* Ours (kept): RMB drag turns the orbit and the wheel steps its distance (within [dmin, 20·dmin]); `=` / `−` zoom the cockpit
  art in the cockpit views; Ctrl+F2 toggles cockpit ↔ chase; `--external`, `--orbit yaw pitch dist` (180 = behind) for
  test poses.
* HUD only (type 5): the HUD symbology and the message lines, no panel / MFDs; the projection stays the cockpit's (the
  original's viewport grows to 480 rows, which moves the projection centre: not ported, so the HUD stays registered).
* EO camera (slot 1, type 0xb): built for the FLIR pod and the TV weapons before launch (docs/mfd.md "FLIR (6), TV (5)";
  a SubViewport camera, terrain_view.gd `_update_eo_view`); the full-screen weapon MFD (Z) is not built.
