# In-flight views, pause, menu and time compression

This page describes what the in-flight keys for pause, the menu, time compression, mute and the cameras do in the
original, and what the port does with them. Sections: pause and the On-The-Fly menu (§1), time compression (§2),
mute (§3), the views / cameras (§4).

Addresses are `IAFJets.exe` **v1.1**. Keys and command ids: [controls.md](controls.md). The pause / menu GDI
(Windows drawing) details are in [front-end.md](front-end.md) §16.

Terms used on this page:
* **TSD**: Tactical Situation Display, the map screen. **FlyTSD**: the TSD opened during a flight (screen 0x20).
* **HUD**: head-up display. **MFD**: multi-function display. **RWR**: radar warning receiver.
* **EO**: electro-optical (the TV weapons and the FLIR camera). **FLIR**: forward-looking infrared.
* **Sim clock**: the simulation's clock; everything that moves runs on it. **dt**: one frame's time step.
* **SP**: single player. **RMB**: right mouse button. **AI**: the computer-flown aircraft.

## 1. Pause, On-The-Fly menu, FlyTSD (Esc)

The flight window handles the key commands 0x7a (Esc, "TSD and cockpit toggle"), 0x84 (Ctrl+P) and 0x85 (Ctrl+O)
directly (`CFlightWnd::OnGameEvent` 0x4dc280). They bypass the game-event queue. Single player only.

| | Ctrl+P pause (0x4dc41f) | Ctrl+O menu (0x4dc479) | Esc (0x4dc315) |
|---|---|---|---|
| allowed | no message box, menu closed | not paused | always |
| does | toggles pause | toggles the menu | unpause if paused, else close the menu if open, else **FlyTSD** (screen 0x20) |
| held keys | release commands sent (`FUN_004e0a60(1)`) | the same | the same (flight window closed) |
| sim clock | stopped if it ran (event 0x75(0)) | stopped (0x75(0)) | stopped (0x75(**1**)) |
| sounds | every channel paused where it is | the same | **not** paused (param 1) |
| keys meanwhile | only Ctrl+P (key manager counter −1) | Esc / Ctrl+O; flight commands dropped (`FUN_004cd3b0`: clock stopped) | the menu frame's keys |
| shown | "II  PAUSE" blinking + white wash | the six-item menu | the TSD screen |

* **Esc in a paused flight**: the key manager passes only Ctrl+P. So the flight keys cannot reach the "unpause"
  branch of Esc. That branch is on the FlyTSD, whose frame handles its own Esc.
* **FlyTSD** (`flytsd.trx`: Fly, Visit, the layer checks, Alpha–Delta, Zoom):
  * Esc and BACK (frame handler `FUN_004ea090` 0x7a, BACK `FUN_004ed1b0`) return to the flight (exit 4) when
    `FUN_004bb8f9` holds (the player has a unit, UNCERTAIN).
  * MAIN (`FUN_004ecff0`) on screens 0x20 / 0x21 opens the Ctrl+Q quit-mission box (`FUN_004e2fa0(3)`).
  * The map is the live battle: the unit table is rebuilt from the spawned objects on every paint (`FUN_00517cd0` →
    `FUN_004d2900`), with the sim clock stopped. Docs/front-end.md §8.1 lists which units get a record. A downed
    formation leaves the map and its button is disabled (`FUN_00505820`). The clock is the time of day now.
  * **Fly** (`FUN_005045b0`) with a selected flight that exists calls `FUN_004d31f0`: its current leader (member 0
    while alive, else member 1, `FUN_004d35c0`) goes to `FUN_004d3250` (the TSD object's vfunc +0x14). Then the flight
    resumes (exit 4). Without such a flight: msg 25.
  * **`FUN_004d3250`**, in single player:
    1. The player's jet is kept as the old jet when it is alive, is not the target, and its control status
       (state +0x14) is neither 0 nor 1.
    2. If the target is brain controlled (status 1), it becomes player controlled (`FUN_004a8e70(3)`: the player
       object, its controller attached, the input devices' current stick and throttle passed to its flight model). The
       old jet becomes brain controlled (`FUN_004a8e70(1)`).
    3. The camera goes to the cockpit view on the player's jet (`FUN_0057f2a0(…, 1, player)`).

    Fly on the player's own flight therefore only returns the cockpit view.
  * **Visit** (`FUN_005046b0`, in flight with a selected unit) calls `FUN_004d3450` with that unit, then the flight
    resumes. `FUN_004d3450` sets the main camera to the radar-target view on the unit (`FUN_00580f50`, type 9:
    aircraft {300, 700, 300, 10°, ·, 2°} ×1, others {500, 900, 500, 30°, ·, 120°} ×3, no randomness). It also sets
    `+8 = 1` in the visual record (`obj+4`) of the unit and of the living player's jet, and clears `+8` of the record's
    cockpit part when there is one (UNCERTAIN: "drawn from outside"). The player keeps flying the own jet. Esc gives the
    FlyTSD again (EN 3.1).
  * **Double-click** on the map (`FUN_00501ef0`): a flight leader of class 0x1c with a flyable type, on the side rule,
    flies (`FUN_004d3250`). Any other unit is visited in flight; before the flight nothing happens.
  * **Ctrl+P** (frame handler `FUN_004ea090`, event 0x84; screen 0x20, single player, no message box) pauses the FlyTSD
    (`FUN_004edbc0`) or resumes it (`FUN_004ede30`). The pause:
    * snapshots the window and dithers it: AND with `menu/bmp/misc/pat1.bmp`, then OR with `pat2.bmp`. Both are
      640×480 checkerboards, so every other pixel turns grey 215;
    * releases the held keys (`FUN_004e0a60(1)`) and drops the key manager's counter (`FUN_004df500(-1)`), so every
      key but Ctrl+P is ignored, Esc too;
    * disables the frame window (no mouse);
    * stops the sim clock only if it runs (it is already stopped on the FlyTSD, so the sounds play on).

    The paint (`FUN_004e92b0`) blits the snapshot and, 500 ms on / 500 ms off, "II  PAUSE" in Arial 50 weight 900,
    RGB(0,255,0), TA_BOTTOM at (30, 450).
  * While the time rate is > 1, the TSD overlay shows `"%dx"` (0x654b74) at (Wc − 4, 4), TA_RIGHT (@5013f0).
* **Menu items** (`FUN_004dc0d0`):
  * Resume.
  * End mission: msg 8 → debrief.
  * Restart: msg 9 → debrief screen 0x23, which presses Replay itself after 50 ms.
  * New mission: msg 10 → screen 0x25, which presses New Mission.
  * Preferences: screen 0x21, Gameplay tab disabled. BACK / Esc recreates the flight window and reopens the menu,
    still paused.
  * Quit game: msg 7.

  In each message box, NO closes the box and the menu stays.

### iaf-reborn
* **Code**: `game/terrain/flight_overlay.gd` draws the pause text / wash and the menu with the GDI rules of
  `game/util/gdi.gd` (front-end.md §16.2); `game/mission/render_box.gd` is the in-flight message box (§16.4). In
  `terrain_view.gd`: `window_key`, `_pause_key`, `_menu_key`, `_esc_key`, `menu_choice`.
* **Sim clock stop** = the **scene tree's pause**: every sim node stops. The overlay, message boxes and the front
  end over the flight keep running while paused.
* **Sound pause**: the port sets `stream_paused` on every playing player of the flight and clears it on resume.
* **FlyTSD and in-flight Preferences**: both are the front end (`front_end.gd` with `flight` set) on a layer over
  the frozen flight. Leaving them calls `close_front_end()`. Changed preferences apply on return (sound, shadows,
  the textured sky and the Extras render options, blackouts).
* **Restart / New mission** end the flight with the debrief. `Settings.debrief.auto` = the button the debrief
  presses after 50 ms (`replaymission` / `newmission`).
* **FlyTSD live map**: `game/menu/tsd.gd` `_load_units` builds the tables from the flight's runtime entities when the
  TSD opens. The sim is frozen while it is up, so one build equals the original's rebuild on every paint.
* **Fly** (`terrain_view.gd` `fly_unit` / `_take_over`): the target's IafFlight becomes the player's flight model. The
  player's jet is then rebuilt for the target's type: cockpit, sounds, systems damage, model and `_bc` model,
  weapons with the stores the AI jet had left (`player_weapons.gd` `rearm`), route and autopilot. The brain's
  autopilot mode ends (flight model mode 0, so its AI rules stop) and the player's autopilot starts as the jet's
  controller did at spawn (on in level mode after an airborne start, @4483d7). The levers (gear,
  flaps, brakes) follow the new jet; the stick and throttle stay the player's. The old jet keeps its IafFlight
  under a new AI pilot with its brain, its systems damage and the stores it had left (`ai_flights.gd` `adopt`,
  `combat.gd` `adopt`). Weapons already in the air fly on.
* **Visit** (`terrain_view.gd` `visit_unit`): the radar-target view (`_follow_radar_target`) on the unit's node, the
  own jet's rig for the player's own unit. The visual-record flags have no equivalent here: every model is drawn.
* **Ctrl+P on the FlyTSD**: `front_end.gd` `tsd_pause_key`, drawn by `game/menu/tsd_pause.gd` (the dither as a
  shader on the viewport's snapshot).
* **Open**:
  * Fly while the own jet is down (destroyed, falling or ejected): ours changes nothing. The exe hands over the new
    jet; rule 1 still ends the flight 5 s after the death (docs/mission-runtime.md §5.1).
  * The multiplayer boxes (msgs 11 / 12).

## 2. Time compression (C 0x77, Ctrl+C 0x78)

Key facts:
* C steps the rate x1 → x2 → x4 → x1. Ctrl+C sets x1.
* Any situation allows it, and only these keys change it.
* The cockpit shows the rate at (630, 10) while it is > 1.0.

The clock: the single-player sim clock (`DAT_006992d0`, ctor `FUN_004cf910`, vtable 0x604c50) has a rate `+0x48`
(start 1.0) and a cap `+0x58` = 16.0 (0x604bf0). Sim time = real time × rate + offset (`FUN_004cfa50`).
`FUN_004cfa10` re-bases the offset so the time does not jump.
* **C** (`FUN_004cd630` case 0x77 @4cebc0):
  1. `r = ftol(rate)` (vfunc +0x20 `FUN_004cf990`).
  2. If `r < 4.0` (0x604ba8): vfunc 0 `FUN_004cf9c0(r)` sets rate + r (only if < 16): 1 → 2 → 4.
  3. Else: vfunc +4 `FUN_004cf9f0` sets 1.0.

  So x1 → x2 → x4 → x1.
* **Ctrl+C** (case 0x78 @4cec01): vfunc +4 → 1.0.
* **No other rule**: nothing refuses it (on the ground, near enemies, under attack) and nothing resets it.
  * The rate functions have no other callers. All vcalls on `DAT_006992d0` were checked: @4497b0 HUD copy,
    @5013f0 FlyTSD text.
  * The events go through the queue (`FUN_004cd3b0`), so they act only while the clock runs (not paused / in the
    menu).
* **Indicator**: the cockpit copies the rate into HUD +0x10f4 every frame (`FUN_00446840` @4497cd). While the rate
  is > 1.0, the console drawer `FUN_005201b0` (@520414) prints `"%1dX"` (0x65c6c4) with TA_RIGHT at **(630, 10)**
  in the console font and HUD colour. The FlyTSD shows `"%dx"` (§1).
* **Stepping**: the original runs one frame with dt = rate × the real frame time. Everything on the sim clock
  (flight model, AI, scripts, timers) runs faster. These stay in real time:
  * the blackout / redout integration uses the frame's real time (`DAT_007d1980`, flight-model.md §13.3);
  * the pause blink uses timeGetTime.

### iaf-reborn
* `Engine.time_scale` = rate. Godot scales every sim `_process` delta and sim timer, as the original's clock does.
* The player's flight model is stepped `rate` times per frame with the uncompressed frame time.
  * Its 1 Hz / 5 Hz updates are scheduled at fixed sim times (`Aircraft::step`). So this equals one step of
    rate × dt and stays deterministic.
  * It also keeps each call under the 0.25 s clamp.
* `g_effects.gd` divides by the time scale (real time).
* The `"%1dX"` text: `cockpit.gd` `_draw_console` (shown with the cockpit, like the subtitles). FlyTSD: `tsd.gd`.
* Leaving the flight resets the scale to 1.

## 3. Mute (Ctrl+M, 0x87)
`0x4e3442` flips the Sound page's MUTE (`DAT_0083b8b8`) and applies it (`FUN_004c5930`). Port: `sound_buses.gd`
`toggle_mute()`. The port does not save it (UNCERTAIN whether the original saves it).

## 4. Views (cameras)

Traced in v1.1:
* view manager `DAT_00699304`;
* setters `FUN_0057f2a0` / `FUN_005808c0` / `FUN_005811b0` / `FUN_00581640` / `FUN_00581390`;
* per-frame pose `FUN_00582880`;
* keys in `FUN_004cd630` cases 0x14–0x1c.

Port: `game/terrain/views.gd`, `terrain_view.gd` `_view_command` / `_snap_command` / `_apply_view`.

### 4.1 Architecture
* **Camera slots**: three slots of 0x490 bytes at `mgr + 8 + k·0x490` (`mgr+0` = the active slot):
  * 0: the main camera (every view key);
  * 1: the EO weapon camera (MFD);
  * 2: the **snap view**, while a Numpad snap key is held.
* **View types** (the camera's `+8`): 1 cockpit, 5 HUD only, 6 chase / two-object, 9 fly-by / radar target /
  weapon, 0x10 circle (player killed), 0x12 cockpit free look, 0x15 wreck circle, 0x16 padlock.
* **Terrain clamp**: every pose ends with one.
  * cockpit eye ≥ ground + 1 m (0x610e14);
  * orbit ≥ ground + max(15, 0.2·distance) (0x610e18, 0x610f14);
  * two-object ≥ ground + 2 m (0x610f30);
  * circle ≥ ground + 15 m.
* **Roll**: external views look at their object with **roll 0**. The cockpit types keep the jet's roll.
* **Drawn per type** (`FUN_0051f8e0`): 1 / 0x12 / 0x16 (and snaps) draw the cockpit; 5 draws the HUD only (no
  panel); every other view draws only the message lines.
* **Field of view**: the projection is 50° across 640 px for every view. The camera's zoom `+0xc` (0.75 cockpit,
  0.5 external) only sets the object-culling angle (`FUN_00588ca0`, 50°/z). The external "zoom" keys change the
  distance.

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
`DAT_00833704` = the last id (padlock excluded). F5 / F6 use it for their "again" rule. In the external views the
Numpad snap keys turn the orbit: 8 / 2 pitch, 6 / 4 heading. F2 and 1 / 3 / 7 / 9 do nothing there.

### 4.3 The cameras
* **Cockpit** (1, HUD only 5): the eye is at the jet, with the jet's attitude, then head yaw and pitch with
  `FUN_00585270`: pitch = max(head pitch − 5.5°, 0.1·(|yaw| − 90°)).
  * F1 from a turned head returns it to (0, 0) linearly at 45°/s on the larger axis (`FUN_0057fa10`).
  * The panel art pans with the head (docs/cockpit.md "Pans"): 1920 / AzimutAngleDeg px per rad of yaw,
    (PanelHeight + HUD CenterY) / ElevationAngleDeg per rad of pitch.
* **Own jet in the cockpit views** (1, 0x12, 0x16; `FUN_004d9d70` with the view test `FUN_0045e290`): the player's
  jet is drawn with its cockpit-view model, model slot [8] = `<plane>_bc.x` (wings, fuselage aft of the eye, tail and
  seat back; docs/damage.md §2). The canopy structure follows each jet: a hoop behind the seat on the F-16 and Lavi,
  a heavy rear frame on the Kurnass 2000, a rear hood on the Kfir, a rear fairing on the Mirage, sill rails only on
  the frameless-canopy F-15, through `FUN_004da060` (display slot 4, the crew's cockpit flag
  set so the pilot and canopy stay hidden) and back to slot 1 after the draw (`FUN_004c3210`). The model is moved
  by the eye offset (`FUN_00444da0`) so the eye sits at the camera. The HUD-only view (5) draws no own jet. The
  F-4E draws only its cockpit. Ours: the F-35I's is `f35i_bc.gltf` (`tools/f35i/bc.py`, docs/f35i.md §4.4).
* **Free look** (0x12, `FUN_00582370`):
  * Press: angle = start + rate · 2·t·(1 − 0.9^t). The rate is 45°/s, so the pan speeds up toward 90°/s.
  * Limits: pitch −12°…+85°, yaw unlimited.
  * Release: the head stays where it is.
  * Panning breaks a padlock.
* **Padlock** (0x16): the head points at the target's direction in the jet's body frame, pitch ≥ −12°, and at
  (0, 0) within 5° of the nose. The head closes 0.9^(10·dt) of the error per frame step (τ ≈ 0.95 s).
* **Helmet** (free look 0x12 / padlock 0x16):
  * The IR seeker looks along the camera axis within its generation cone.
  * `Dash 1` cockpits draw the HUD as a helmet display at (320, 220) once the head is turned (docs/weapons.md
    §5.4, docs/cockpit.md "HUD dash repeater").
  * The 3D viewport follows the pan (docs/cockpit.md "3D view").
* **Orbit / path-follow** (6 chase, 9):
  * The trail keeps the target's last 100 frame positions.
  * The camera sits L back along that path. L is a rope: min dmin = min(1500, scale·size), start 3·dmin, max
    20·dmin. A short path goes on along −forward.
  * Then the camera is rotated about the target by the orbit heading (chase 2°) and pitch (chase 10°).
  * F9 / F4 / F11 add the **swoop**: the camera starts at the offset point (in the target's body axes; x / z get a
    random sign and ×0.5–1.5 when random). The offset decays as 0.3^t into the chase position.
* **Two-object** (6): W = unit(A − B), N = (−W.y, W.x, 0), U = W × N (world axes, z up). Eye = A + 150·W + 30·N +
  30·U, looking at B. The pan / zoom keys have no visible effect there.
* **Circle**:
  * 0x10 (player killed): r 600 m, +600 m, 18°/s from the view's start.
  * 0x15 (an object the external view followed was destroyed, event 0x4d): r 600 m, +600 m around the wreck with a
    wall-clock angle; back to the cockpit 6 s later (`FUN_005862a0`). With the attacker within 1000 m it circles the
    attacker at +300 m.
* **Ejection**: fly-by on the jet {1500, 900, −200, −10°, ·, 120°} ×2 random. At t0 + 5 s it switches to the
  parachuter {1000, 600, 200, 230°, ·, 160°} ×2 (docs/mission-runtime.md §5.4).

### 4.4 iaf-reborn
* **Built**: all of the above, with these differences:
  * **F5 threat** follows the RWR (`terrain_view.threat()`; the AI's locks `ai/combat.gd` `_pick` and launches
    fill it). Without a threat it does nothing, as the original.
  * **F4 / F7 / F8 / F3** use the radar's A-A lock / TWS selection (`radar.locked()`; A-A: air-to-air, TWS: track
    while scan).
  * **F6** uses the AI formation (`ai_flights.gd` `_formation_of`).
  * **F11** (`terrain_view.gd` `last_weapon`) follows the homing missiles (IR and radar, any launcher's) and falling
    bombs / jettisoned tanks. The TV weapons and rockets, like chaff / flares / gun rounds, are never it.
  * The wreck circle has no attacker field, so it always circles the wreck.
  * The own jet's `_bc` model (`terrain_view.gd` `own_bc`) is a sibling of the jet model on the rig, at the jet's
    Present scale, shifted by −eye; it shows in the views where the cockpit art is drawn. Snap views count as the
    cockpit's (UNCERTAIN: the type of the slot-2 camera).
* **UNCERTAIN, chosen here**:
  * the fly-by offset axes (x right, y forward, z up);
  * the orbit signs (+heading swings the camera right, +pitch raises it);
  * object size = the largest dimension of the scaled model box;
  * the visual-lock screen point = the screen centre;
  * the two-object side N as written.

  The trail takes one sample per rendered frame (as the original, frame dependent).
* **Ours (kept)**:
  * RMB drag turns the orbit, and the wheel steps its distance (within [dmin, 20·dmin]).
  * `=` / `−` zoom the cockpit art in the cockpit views.
  * Ctrl+F2 toggles cockpit ↔ chase.
  * `--external`, `--orbit yaw pitch dist` (180 = behind) set test poses.
* **HUD only** (type 5): the HUD symbology and the message lines, with no panel / MFDs. The projection stays the
  cockpit's, so the HUD stays registered. (The original's viewport grows to 480 rows, which moves the projection
  centre: not ported.)
* **EO camera** (slot 1, type 0xb): built for the FLIR pod and the TV weapons, riding a launched one (docs/mfd.md
  "FLIR (6), TV (5)"; a SubViewport camera, terrain_view.gd `_update_eo_view`). The full-screen weapon MFD (Z) is
  built (`_update_full_screen`, `cockpit/fs_mfd.gd`).
