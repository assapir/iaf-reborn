# The RWR (radar warning receiver)

The RWR of a controller (`ctl+0x5b0`, ctor `FUN_004515d0`, v1.1 addresses) and how ours follows it
(`game/weapons/rwr.gd`, owned by `player_weapons.gd`; drawn by `cockpit/cockpit.gd` `draw_rwr_symbols` on the MFD
page 7 (`cockpit/mfd.gd`) and the panel dial). World frame X east, Y north, Z up, metres, sim seconds.

Only a **controller** has an RWR: in single player that is the player's jet. AI aircraft and ground units have none
(their brain gets the lock instead, §2).

## 1. The list
10 slots × 0x24 from `+0xc`: +0 the emitter unit, +4 its bdb type code, +8 its position, +0x14 the launch flag,
+0x18 missiles in flight (short), +0x1c drop pending, +0x20 active. `+0x174` the count, `+0x178` the missile list
(`{distance from the jet at the launch, missile}`, used by the decoys, docs/weapons.md §10).

- **Add** (`FUN_004518d0`): refused when count > 9 or the unit is listed; the first slot whose type is 0; position,
  type, active = the emitter test; count + 1.
- **Remove** (`FUN_004519e0`): with missiles still in flight only the drop is marked; else the slot is cleared and
  count − 1. Slots are **not compacted**.
- **Emitter test** (`FUN_004521c0`): 3-D distance ≤ 37080 m (`0x600d14`); classes 8, 9, 10, 5, 0x10 (ground) always
  pass; any other class only when its relative bearing off the own nose (`FUN_0044e770`) is more than 120°
  (`0x600d18`, 2.0944 rad), i.e. an aircraft in the rear sector.
- **Refresh** (`FUN_00451a70`) on the controller's 2.0 s timer (`DAT_0082f4a8`, object 0x600b60 → `FUN_0044a1a0`, the
  same timer as the radar scan; first at the flight start, `FUN_00448120` @44859e): positions; active = the emitter
  test or the launch flag; an emitter in state 5 is removed. (docs/ai.md §14 said 0.25 s: that is the other timer,
  `0x82f3f8`, which drives `FUN_0044a180`.)
- **Clear** (`FUN_00451b90`): every slot and the missile list; damage 14 (RWR), 19 and 21 (generators) call it
  (`FUN_0044d760` @44d8b6 / @44da17 / @44da83).
- Every RWR entry point first checks damage flag 14 (`FUN_0045cc90(0xe)`): a damaged RWR hears nothing.

## 2. Who feeds it
- **Locks** (`FUN_0044deb0` / `FUN_0044e030`, ECX = the target's controller, args (emitter, from-network)): called by
  the radar manager's on-lock / on-unlock `FUN_004b0510` / `FUN_004b04d0` when the target has a controller
  (`unit+0x34`). The radar manager is shared by the player's radar and the AI target sensors (brain+0x40; their
  override `FUN_004aca60` / `FUN_004aca80` notifies only class 0x1c targets). Types 220, 250, 270 are ignored. A new
  entry that is active lights its lamp (§3) and plays WRN_NEW_GUY (gated). An unlock removes the entry; with the list
  then empty its lamp goes off. In multiplayer both also send a network message (`0x600bf0`); the remote side calls
  them with from-network = 1 (`0x5c29b0`).
- A target **without a controller** (an AI unit): its brain+0x7c is set on the lock when it is 0 and cleared on the
  unlock when it matches. Original bug: the value written is the locked unit itself, not the radar's owner. Brain
  condition 38 (`FUN_005c1410`) and action 430 (`FUN_00444a60`) use brain+0x7c as the threat of a unit without a
  controller; condition 39 (`FUN_005c1490`) is 0 and condition 19 (`FUN_005c14e0`) invalid without one.
- **Launches** (`FUN_0044e160` ← the missile's guidance start `@4d814b`, ECX = the missile's target's controller,
  args (the launcher `missile+0xfc`, the missile)) → `FUN_00451be0`: the emitter's entry (added if new; original
  quirk: when that add fills the list, the function returns before marking it) gets the launch flag, one more missile
  and active; the missile joins the missile list unless it chases a decoy (`FUN_004d83f0`: target type 0x21c / 0x226)
  or is listed. Then the WRN_MISSILE_LAUNCH loop starts if not running (handle `ctl+0x8c8`) and, with Betty
  (`ctl+0x964`), Betty "Missile" (`0x2c002000`) plays on every launch.
- **Missile ends** (`FUN_0044e1d0` ← `@4d81ff`) → `FUN_00451e30`: one missile less; at 0 the launch flag drops and a
  pending drop removes the entry; the missile leaves the list. With no launch flag left (`FUN_004520f0`) the loop
  stops.

## 3. Lamps and sounds (`FUN_00450bc0`, every frame)
Panel lights 3 'ai' and 4 'sam' (docs/cockpit.md). Every frame, with an empty list (`ctl+0x724` = RWR+0x174) both go
off. Else: an active entry of a ground class (8, 9, 10, 5, 0x10, `FUN_00452380`) lights 4, of another class
(`FUN_004523c0`) lights 3; a light that comes on plays SFX_WARNING WRN_NEW_GUY (`0x18002000`, `WrnSfxNewGuy.wav`)
when the gate `ctl+0x860` passes (at most once per 1.0 s, `FUN_004d3fa0(0, 1.0, 0)` @4479fd); a light without such
an entry goes off. There is no separate lock tone; the launch tone is the WRN_MISSILE_LAUNCH loop (`WrnSfxMissile.wav`).

## 4. The displays
- Cockpit copy (`FUN_00446200` via `FUN_00451b50` when dirty): **the first `count` slots** (≤ 15) → state+0xe80..
  (stride 0x18: type, position, launch, active), count → state+0xfe8. Original bug kept: after a removal the slots are
  not compacted, so an entry past the count is not shown while a freed slot is (it is never drawn: inactive).
- Symbols (`FUN_00531470(cx, cy, radius)`): the 10×10 rwrsymb.bmp glyph of the type (docs/mfd.md §3 "RWR") centred
  at cx + ⌊(C·dx + S·dy)/k⌋, cy + ⌊(C·dy − S·dx)/k⌋ with dx = X − own X, dy = own Y − Y (the horizontal offset clamped
  to 37060 m), k = 37060 / radius m/px, S / C = sin / cos of the heading: heading-up. Active entries only; types
  without a glyph are skipped; launch-flag entries blink (300 ms, the phase starts visible, `DAT_0065d560`).
- MFD page 7 (`FUN_00531290`): tile (132,0); centre (66,66), radius 56; with RWR damage (state+0x590 = damage flag 14)
  the text "Mal" at (101,3) instead.
- Panel dial (`FUN_00531330`, `[PANELRWR] Active`): centre `CenterX / CenterY` in panel pixels, `Radius`; nothing
  with RWR damage. Per cockpit: F-16 (805,84) r 28, Kfir (1094,74) r 32, F-4E (1218,69) r 28; every other cockpit has
  no dial and shows the RWR as MFD page 7 (default Right page on F-15, Lavi, F-4-2000, MiG-29; MENU "rwr" elsewhere),
  docs/mfd.md §7.

## 5. The threat (`FUN_00451f70`)
A refresh, then the nearest listed emitter (active or not) within 370800 m (3-D). Used by the F5 threat view
(`@4ce003`), AI action 430 and condition 38 (for a unit with a controller).

## 6. Ours
- `rwr.gd` ports §1–§3 and §5; `cockpit.gd` §4 (the 4× glyph art; blink from the wall clock).
- Feeds today: the player's radar lock hook (`player_weapons._radar_lock`: the AI's brain+0x7c, §2). Nothing locks
  the player yet: the AI target sensors (actions 400 / 410 / 420, docs/ai.md §13–14) and the ground units' brains are
  the AI combat job, and enemy missiles are not built. `rwr.lock(key)` / `unlock(key)` / `launch(key, missile)` /
  `missile_end(key, missile)` are the entry points for them; `tests/godot/test_rwr.gd` drives them with synthetic
  emitters.
- Not ported: the network messages; the restart path of the launch loop in `FUN_00448120` (@4482ee, a flight
  restored with launch flags).
