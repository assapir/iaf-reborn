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
