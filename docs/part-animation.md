# Jane's IAF: how aircraft model parts move (reverse-engineered spec)

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 and lists what the patch changed.

Sources: `assets/ghidra_v11/iafjets.c`, plus `objdump` of `iafjets.exe` for routines Ghidra did not
decompile. The key one is the per-part callback `0x5a09c0`. Constants come from `.rdata`.
Items marked **UNCERTAIN** are guesses. Offsets written `S+x` are in the flight state (`veh+0xc30`, see
flight-model.md), and **type** is the aircraft type `veh+0xc54`, set by `FUN_005a8980`:
100 F-16, 110 F-15, 120/200 F-4, 130 Kfir, 140 Lavi, 150 MiG-21, 160 MiG-23, 170 MiG-25, 180 MiG-29,
190 Mirage, 210 MiG-17, 220 Tu-22, 225 C-130.

## 1. Load time

**Name → id table.** Built by `FUN_005876a0`. Each `FUN_005e0297("x3ds_Name"); FUN_00587640(id)` call
puts one entry into a hash map `id → name`. Then, for every registered `id` in 1..0x27, it adds
`name+"1"` as id `id+0x3f` and `name+"2"` as id `id+0x67`. Those are the X1/X2 hinge helpers.
All names are copied into a flat table of 0x8f entries × 0x30 bytes (`global+0x74`):
`{char name[32]; Clump* clump(+0x20); float pos[3](+0x24)}`. Entry 0x3c is `"x3ds_top02"` (purpose
unknown). Other ids: Turret 0x18, Radar 0x19, Carrier 0x1a, Launcher 0x1b, Missile 0x1c,
RotorA-D 0x1d-0x20, WheelsA-F 0x21-0x26, StationA-I 0x29-0x31, StationGun 0x32, StationCha 0x33,
StationFla 0x34, Pilon 0x35, Camera 0x36, EndWingL 0x37, EndWingR 0x38, Height 0x39,
EngineL 0x3a, EngineR 0x3b.

**Frame loading.** Only `*.xfr` files use the table. `FUN_00588ea0` clears all `clump` pointers
(**not** the positions, so an entry that no longer exists keeps the position from the previous model) and calls
`FUN_0041cbb0` → `FUN_0041c880`. That loads the root frame and, for **every direct child of the root**,
calls `FUN_0041c270`:
* The frame name is looked up in the table with `_stricmp` (`FUN_0056a9f0`, case-insensitive: `x3ds_Canopy`
  and `x3ds_height` both match; the AI planes' `LdGr` is `LdgR`). The first match wins. Children that match no name are dropped.
* `pos = (-tx, -tz, ty) * scale`, where `(tx,ty,tz)` is row 3 of the child's `FrameTransformMatrix`
  (the frame origin, **not** the centroid of the helper triangle), and `scale` is the clump scale (F-16: 5.0).
  Call this frame "E". Only the frame translation is used. In all shipped models every frame rotation is identity.
* The child's mesh becomes its own clump (`entry.clump`).
* `FUN_0041c680`: `EngineR`/`EngineR1` → `clump+0x280`, `EngineL`/`EngineL1` → `clump+0x28c`.
  These are **raw** `(tx,ty,tz)*scale` with no axis swap. The first of the pair found is stored. When the second
  arrives, `clump+0x298 = |y_first - y_second|` (the flame radius) and `clump+0x27c++`. If the second one is the
  plain `EngineX`, it overwrites the stored position.
  `FUN_0041c7f0`: `StationGun` → `clump+0x29c` (raw, used for the muzzle flash).

**Graphics object.** Built by `FUN_0053da00`, called from constructor `FUN_0053d910`. `vec3 axis[0x35]` lives at `obj+0x28`:
```
for id in 1..0x27: if entry[id].clump:                 // one "Subpart" object per present part
    part = new Subpart(id, entry[id].clump); part.pos = entry[id].pos; obj.parts.append(part)
for id in 0x29..0x34: axis[id-1] = entry[id].clump ? entry[id].pos : 0   // weapon stations
if entry[0x38].clump (EndWingR): obj+0x50=1; obj+0x38=(L.x,-L.y,L.z); obj+0x44=(R.x,-R.y,R.z)
obj+0x68 = entry[0x39].clump ? entry[0x39].pos.z : 0   // Height helper (up component)
obj+0x2c = Pilon? Pilon.pos : Camera? Camera.pos : (0,0,cfg "PilonDefaultZ")  // FUN_0053e3b0 default
EngineL/EngineR also become Subparts, ids 0x3a/0x3b
for id in 1..0x27: if entry[id+0x3f].clump:              // X1 exists (X2 is NOT checked)
    P1 = entry[id+0x3f].pos; P2 = entry[id+0x67].pos
    axis[id] = |P1| <= |P2| ? normalize(P2-P1) : normalize(P1-P2)
    hide X1 and X2 clumps (FUN_00402260)
```
**The axis always points from the helper nearer the model origin toward the farther one.**
Which helper is named `1` or `2` does not matter. For left/right pairs the axes therefore point outboard, in mirrored
directions. If both helpers are the same distance from the origin, the direction is effectively arbitrary
(the F-16 `Hook1/2` differ by 0.0004). If there is no X1, `axis = 0`, and the part is drawn **unrotated**.

**Pivot = the part frame's own origin** (`part.pos`), not the helper line. On most parts the helpers sit
on the hinge (for example, the F-16 AilerL2 helper triangle centroid equals the AilerL origin). On the F-16 main gear they
do not, and the rotation is still about the part origin.

## 2. Per-frame pose (render: `FUN_004da090`, hardware path `FUN_004db180`)
Only the nearest LOD, the `_h.xfr` model, has parts (`_m.x` and `_l.x` are merged meshes). For each part,
the renderer calls the owner's `vtable[1](time*, id, &visible, &pos, &angles[3])`. For flown aircraft this is
the flight model `FUN_005a09c0` (vtable `0x611e28`). It sets `visible=1` first, and only `angles[1]` is used.
If `visible==0`, the part is not drawn.
If `axis[id]` is non-zero, `FUN_004dacd0`/`FUN_004db760` rotate the part by `angles[1]` about
`k=(-a.x,-a.y,a.z)` with Rodrigues in the swapped frame and convert the result to Euler angles.
Swapping y/z is a reflection, so **in X-file coordinates it works out to**:
```
v_world = part_origin + Rodrigues(v_local, d, -θ)      // standard right-hand formula, D3D X-file coords
   d = unit(X-file helper far - helper near)  (same rule as above, no axis swap)
// In a Z-mirrored right-handed (glTF) space: rotate by +θ about (d.x, d.y, -d.z).
```
Checked against the F-16 model: with this sign, pulling the stick raises the stabilator trailing edges, the nose gear
retracts aft, the main gears swing forward, SpdbrU opens up and SpdbrD down, and right roll gives left aileron down.
One exception: the F-16 hook swings **up**, because its degenerate helpers flip the axis.

### Ramp sampling (all animated values are flight-state "type A" ramps, in radians)
`FUN_005a2b00`/inline: `τ = clamp(now - t0, 0, 3.5)`, `v = τ < t_end ? v0 + rate·τ : target`,
clamped to `[min,max]`, then wrapped to (-π, π] (`FUN_0044f5f0`). The limits are set in the constructor
(`FUN_005ba430` calls near l.281787). The rates are set in `FUN_005a5820`: 0.5 rad/s for S+0x300..0x360 and
0.7 rad/s for S+0x380..0x400. A target is set by `FUN_005a2a80(now, v_now, target, |rate|)`.

| ramp | meaning (visual) | range (rad / deg) | rate | target set by |
|---|---|---|---|---|
| S+0x300 | flaps | [0, 0.29275] / 16.8° | 0.5 | ev 6 `FUN_0059fba0`: on → max·(type100 ? 0.33 : 1), off → 0 |
| S+0x320 | gear retraction (0 = down) | [0, 1.569] / 89.9° | 0.5 | ev 7 `FUN_0059fdc0`: flag → 0 (down), else → max (up) |
| S+0x340 | speed brakes | [0, 0.855] / 49° | 0.5 | ev 8 `FUN_0059ffc0`: flag → max, else → 0 |
| S+0x360 | arrestor hook | [0, 0.7855] / 45° | 0.5 | ev 9 `FUN_005a01c0`: flag → max, else → 0 |
| S+0x380 | rudder | ±0.3927 / 22.5° | 0.7 | airborne: pedal `FUN_0059f5a0` → `ru·0.3926`; on ground (S+0x2a0≠0): stick roll `FUN_005a03c0` → `sr·(−0.3926)` |
| S+0x3a0 / 0x3c0 | elevator L / R | ±0.5236 / 30° | 0.7 | `FUN_005a0650` (below) |
| S+0x3e0 / 0x400 | aileron (elevon) L / R | ±0.7855 / 45° | 0.7 | airborne, type≠130/190: `FUN_005a03c0` → both `= −0.7855·sr`; on ground the ailerons are not updated |

Pitch mixer `FUN_005a0650` (sp = S+0x2e4, +pull; sr = S+0x2d8 = S+0x2e8, +right):
```
A = (type in {190,130}) ? 0.7855 : 0.5236
f = type in {110,190,130} ? 0.5 : type==100 ? 0.65 : 1.0
m = type in {110,100,190,130} ? (1-f)·sr·A : 0            // differential tail / elevon roll
L = sp·f·A − m ;  R = −sp·f·A − m ; if type in {120,200}: L,R *= 0.6 (F-4)
type 190/130 (delta): S+0x3e0 := L, S+0x400 := R   else: S+0x3a0 := L, S+0x3c0 := R
```
Initial state (`FUN_005a5820`): airborne start → gear 1.569 (up), flaps 0, speed brake 0. Ground start
→ gear 0, flaps 0.29275, speed brake 0.855 (open). There is no canopy ramp.

### Callback `FUN_005a09c0`: angle θ = angles[1] and visibility per part id

| id | part | θ | visible | per-type notes |
|---|---|---|---|---|
| 1 AilerL | S+0x3e0 | 1 | F-16: θ = ail − flaps(S+0x300) (flaperon) |
| 2 AilerR | S+0x400 | 1 | F-16: θ = ail + flaps |
| 3,4 CanarL/R | 0 | **0** | no model has canards |
| 5 RuddeL, 6 Rudde | S+0x380 | 1 | same sign for both |
| 7 FlapL / 8 FlapR | −flaps / +flaps | 1 | |
| 9 SpdbrU | +sb | \|θ\|≥1e-5 | 110,140,160,190: −sb. F-16: always visible |
| 10 SpdbrD | −sb | \|θ\|≥1e-5 | 110,140,160,190: +sb. F-16: always visible |
| 0xb ElevaL | S+0x3a0 | 1 | Lavi (140): −value |
| 0xc ElevaR | S+0x3c0 | 1 | Lavi: −value |
| 0xd ElevoL / 0xe ElevoR | S+0x3e0 / S+0x400 | 1 | |
| 0xf LdgL | +g (g = S+0x320) | \|g−max\|≥1e-5 | 110: −g. 180: −g, vis g<0.8889·max. 190: +g, vis g<0.7778·max |
| 0x10 LdgR | −g | \|g−max\|≥1e-5 | 110: +g. 180: +g, vis g<0.8889·max. 190: −g, vis g<0.7778·max |
| 0x11 LdgF | −g | \|g−max\|≥1e-5 | 110,130,140,160: +g. 180: min(g, 0.87264 = 50°) |
| 0x12 LdgDr | 0 (never rotates) | \|g−max\|≥1e-5 | the doors are a static mesh, hidden only when the gear is fully up |
| 0x13 Hook | +hook (S+0x360) | \|θ\|≥1e-5 | |
| 0x27 Parach | jitter (below) | S+0x2cc==2 | |
| 0x14-0x26 (pilot, pilotB, canopy, canopyB, turret…, wheels) | 0 | **0** | the FM callback hides them, but for aircraft entities the renderer's owner is the crew object `entity+0x3c` (callback `0x53eb50`), which answers ids 0x14–0x17 and 0x1d–0x20 **before** the FM: pilot/canopy **are drawn** outside the cockpit view (see "Ejection" below). The F-16 canopy glass exists only in the `Canopy` frame (port: `crew_visible`, always true, docs/aircraft.md §2.3) |
| 0x3a/0x3b EngineL/R, other ids | 0 | 0 | |

Gear sequencing: legs and doors share one ramp, so there is no separate door ramp and no door motion. A full cycle
takes 1.569/0.5 = 3.14 s. Legs rotate while visible and vanish at full retraction (on MiG-29 and Mirage, before full retraction).
The doors are shown in their modelled (open) pose whenever the gear is not fully up.
Sign flips such as "110: −g" compensate for each model's helper order. With the §2 formula, every type gives the physically right motion.

**Drag chute** (`FUN_005a2500`, event 0x17): `S+0x2cc` goes 0 → 1 if pressed airborne, or 0 → 2 if pressed on the ground (deployed).
Pressing again at 2 → 3 (jettisoned). Only types 120,130,160,180,190,200 allocate the jitter object `S+0x2d0`
(the models with `Parach`: Kfir, F-4, MiG-23/29, Mirage). While the state is 2, the callback does
`if now − t0 > 0.1: θ = uniform(−π/36, +π/36) (±5°); t0 = now` (`FUN_005a2b80`, `rand()/32767`).

### Ejection (crew object, seat / canopy "throwing", parachuter)
Generic for every aircraft entity. Mission-side consequences (3-press rule, outcome, camera, TSD) are in
docs/mission-runtime.md §5.4. All times are **sim time** (`[0x6992d0]+0x38`, scheduler `DAT_006992ec`).

**Crew object** = `entity+0x3c`, 0x40 bytes, ctor `FUN_0053ea80` (called from the aircraft entity ctor
`FUN_0059c740` @268107), vtable `0x60c708`. The renderer (`FUN_004da090`: owner = `*(entity+0x3c)`) calls its
slot 1 `0x53eb50` for every part. Ids other than 0x14–0x17 and 0x1d–0x20 are forwarded to the vehicle's callback (`0x46478f` → FM `0x5a09c0`).

| off | meaning |
|---|---|
| +4 | entity |
| +8 | **cockpit flag**: `FUN_005400c0(v)` sets it. **0 from the ctor** (v1.1). The own jet's draw in the cockpit pass (`FUN_004d9d70`, `FUN_004db9e0`) sets it before drawing (via `FUN_004da060`) and restores it after (`FUN_004c3210`), so pilot and canopy are hidden only while the own jet is drawn from the cockpit. (v1.0 never initialised it and set it from five view changes in the event dispatcher, `FUN_004cd630` case 0x1c.) |
| +0xc | crew aboard: 1 (ctor, via `FUN_0053ee80(1)`, and `FUN_0053fe80`), 0 at ejection (`FUN_0053ee90`). `FUN_00540350` = `(+0xc == 0)` = "already ejected" |
| +0x10 | rotor angle, degrees |
| +0x14 | canopy present: 1 (ctor, `FUN_0053fe80`), 0 when a thrown canopy reaches the height limit |
| +0x18 / +0x24 | canopy / canopyB position (E frame, m). Copied from the part positions by `FUN_0053fe80` at spawn, then moved by the throw |
| +0x30/+0x34/+0x38 | vector of thrown seats (begin/end/cap). Slots 2..7 = count / add / get / remove (`0x53ff80`, `0x5400d0`, `0x53ffe0`, `0x53ff90`) |

Callback `0x53eb50` (jump table `0x53ee54`/`0x53ee6c`):

| id | output |
|---|---|
| 0x14 pilot, 0x15 pilotB | θ = 0. visible = `+0xc && !+8` |
| 0x16 canopy / 0x17 canopyB | **position** := `+0x18` / `+0x24` (θ not written = 0). visible = `+0x14 && !+8` |
| 0x1d–0x20 RotorA–D | `+0x10 += 10.0` (`0x60c6d0`), reset to 0 when > 360 (`0x60c6e4`), **per call** (frame-rate dependent). θ = that angle in radians. This is the helicopter rotor spin; it is not the canopy |
| 0x18–0x1c | forwarded to the vehicle |

So in the original, **the pilot and the canopy are drawn on every aircraft seen from outside** and hidden only in the cockpit
view. The old "hidden on the flying aircraft" note was wrong: it described only the FM callback.

**Ejection graphics** (called by `FUN_005485a0`, docs/mission-runtime.md §5.4):
1. `FUN_0053fb00`, at t0: two "Throwing subpart motion" objects (vtable `0x60c728`, 0x34 bytes: +4 dir, +0x10
   offset, +0x1c dist, +0x20 crew obj, +0x24 `&pos`, +0x28 schedule, +0x2c `&flag`, +0x30 `isSeat`). One is for canopy
   (`&+0x18`), one for canopyB (`&+0x24`). Both have `flag = &crew+0x14` and isSeat = 0. At creation dir =
   normalize(0, 0, z0) rotated by −heading, offset = (−x0, −y0, 0), dist = |z0| ((x0, y0, z0) = the part position).
   They are scheduled at **t0, period 0.05 s** (`0x3fa99999a0000000`).
2. `FUN_0053ee90(t0 + Interval)`: `+0xc = 0`, so the pilot parts vanish from the jet **at once**. It pushes a seat record
   (0x20 bytes: `{model = res 0x755b "Pilot on chair" = Pilot\ejectA\ejectA.x, pos = pilot part pos (E frame),
   rot = (0,0,0), visible = 1}`) into `+0x30`. UNCERTAIN: the drawer of the `+0x30` records was not traced. They are probably drawn in the body frame like stores, so from t0 the seat model sits where the pilot was. A second record at the pilotB position is added only if the model has a `pilotB` (0x15) part. Port: one seat per crew part, each its own parachuter (`terrain_view.gd` `_seats` / `_parachuters`); the models with `pilotB` are the F-16 (an F-16D, two-seat), the F-4 2000 / F-4E and the Lavi.
   Each seat gets a throwing object (`FUN_0053f230`: isSeat = 1, flag = `&record.visible`), scheduled at
   **t0 + Interval** (`Eject/Interval`, default **2.0 s**, `DAT_00661350`), period 0.05 s.
   The model's scale is `Cull/PilotOnChairSize`, default 2.0 (`FUN_00588ea0` @255633).
3. Tick `0x53f460` (clone `0x53f890`), every 0.05 s, in the **aircraft's body frame** (E frame: +x left, +y aft,
   +z up, metres):
   ```
   dist += Speed             // Eject/Speed, default 3.0 (DAT_0065ffdc, .data) -> 60 m/s up
   pos = (x0, y0, dist)      // straight up: no aft drift (v1.0 also did pos.y += 0.5·Speed, 30 m/s aft)
   if dist > 100.0 (0x60c6f8):
       if isSeat: world = aircraftPose(now) * pos     // +0x70 pos, +0x7c orientation of the vehicle
                  spawn parachuter at world (FUN_00548c10, below); remove the record from +0x30
       *flag = 0; unschedule                          // canopy: crew+0x14 = 0 hides BOTH canopies
   ```
   The thrown parts stay attached to the aircraft frame: they rise "up" relative to the jet, whatever its attitude.
   They are not ballistic in world space, and there is no gravity, drag or rotation. The v1.1 release note says the
   canopy and pilot no longer "spin with the plane"; this code does not fully explain that (UNCERTAIN).
   From a pilot at z ≈ 1 m the seat needs ⌈99/3⌉ = 33 ticks (1.65 s). So the parachuter appears ≈ Interval + 1.65 s = 3.65 s after t0.
4. **Parachuter** `FUN_00548c10`: it takes the next entity from a pool of `SpecialEject/ParachuterCount` (default
   **4**, `DAT_0066f2d0`) "Parachute" objects. The pool is created at mission start by `FUN_0058bf90`: object type 84 "Parachute",
   name "Parachuting pilot", ids 1000+i, model 184 = `pilot/ejectb/ejectb.gltf`. It is used round-robin (`DAT_0083fab4`). Its
   motion is class 0x1f (`FUN_00549ee0`, vtable `0x60c9b0`):
   * set-up `0x5493d0`: pos = the seat's world position, rot = (0,0,0), **v0 = (25, 30, −5) m/s** (world x, y, z;
     `FUN_00444da0(25,30,-5)` @548c52). Field +0x70 = −3.0.
   * init `0x549700(now)`: angles (·, 30°, 20°) (UNCERTAIN which axes), accel **a = (0, 0, −3.0) m/s²**, h = z − ground(x,y).
     Pure ballistic: p(t) = p0 + v0·dt + ½·a·dt² (`0x4690b0`, `0x4687d0`). There is **no drag and no terminal velocity**.
   * "landing" time `+0xc0 = now + t` with D = sqrt(4·v0z² − 8·a·h); t = (D + 4·v0z)/(2a), and if t < 0,
     t = (4·v0z − D)/(2a). The original has a factor error (4 instead of 2). From h = 1000 m: t = 29.2 s, but the real impact is at 24.2 s.
   * tick `0x54a250` every **0.2 s** ("CMParachuteUpdateEvent", vtable `0x60c9a0`, first at now+0.2): re-bases p/v,
     then swing rates `−40·sin(θa)` and `−20·sin(θb)` °/s (`0x60c974`, `0x60c978`; zeroed if the previous tick was > 0.4 s ago).
     **Stop** when `now > land − 10 s` (`0x60c988`) **or** AGL ≤ 20 m (`0x60c948`). Stop sets +0xc8 = 1 and `0x549b10` zeroes
     velocity and acceleration, so the parachuter **freezes in place** (from 1000 m it freezes at ≈ 351 m AGL). This is an original bug.
   * For the player's ejection (above 50 m, see mission-runtime.md §5.4), "Jump to tactical display event" (`0x60c918`) is scheduled at `land − 10 s`.
There is no parachute-open animation or sound (`parachute open.wav` is not referenced).

**Port (iaf-reborn, `game/terrain/terrain_view.gd` `_eject*`, `aircraft_model.gd` `ejected` / `canopy_offset`):**
the pilots are hidden, the canopies ride the 0.05 s ticks (+3 m straight up in the jet frame, v1.1) until 100 m, the seat
(`objects/pilot/ejecta`, unscaled: `Cull/PilotOnChairSize` is a cull size) starts after 2 s and turns into the
parachuter (`ejectb`) at 100 m, which follows p0 + v0·t + a·t²/2 with v0 = (25, 30, −5), a = (0, 0, −3) in world
X east / Y north / Z up and stops at 20 m AGL (the original's `land − 10 s` factor-4 freeze is not copied; in single
player the flight has ended by then; v1.1 did not change the parachuter, so this deviation stays). The crew flag
starts at 0 on every jet (`crew_visible`), as in v1.1. Not ported: the parachuter swing. The fly-by cameras on the jet and the parachuter: docs/views.md §4.3.

## 3. Other helpers
* **Stations** (A..I = index 0..8, Gun 9, Cha 10, Fla 11): the store object (`FUN_0053c1f0`) takes its
  attach point from `axis[index+0x28]` = E-frame station position ((0,0,0) if the frame is missing). Stores on
  stations 0..8 are drawn by `FUN_0053e430`. The muzzle flash `FUN_00411d90` is drawn at raw `clump+0x29c` (StationGun)
  when the render flag `+0x3e` is set.
* **EngineL/R (+L1/R1)** → afterburner `FUN_004121e0(level, x,y,z, r, scale)`, called from `FUN_0041e220` with level = render bytes +0x3c (right) / +0x3d (left), 0..100.
  The level comes from `FUN_005abdc0` / `FUN_005abc90`: `75 + 12.5·stage` while the flight model's AB stage
  (`vehicle+0x568`+0x28, written in the 1 Hz aero update) is > 0 and that side's AB-damage flag (8 / 9) is clear,
  else RPM ramp·0.74 (≤ 74). Nothing is drawn if level ≤ 74, so the flame shows exactly at AB stages 1 / 2 (k = 0.5 / 1).
  `k = (level−75)·0.04`, `j = (rand%21−10)·0.01`. 12-segment cones start at the raw nozzle position with base radius
  `r = |ΔY(EngineX, EngineX1)|`; the tip is at `z − ((3.5+j)·k·scale + 1.5·i)` (toward −Z, aft) with radius
  `base·(j+0.25)`. 3D-card path (`DAT_007d1960`): i = 2 (base 0.7·r) then i = 3 (base r); software path: only i = 3.
  Texture `afterburn.tga`, u = rand/32767 − s/12, v = 0.9999 at the base, 0 at the tip. Blend state UNCERTAIN.
  Port: `game/aircraft/afterburner.gd`, docs/aircraft.md §2.2.
* **Camera**: eye point `obj+0x2c`, E frame. A `Pilon` frame takes priority if present. The default is (0,0,`PilonDefaultZ`).
  Config `Camera/BackCockpitDistance` (default 20) goes to `global[0]`. **UNCERTAIN** which view uses which.
* **EndWingL/R**: stored as `(−x·s, z·s, y·s)` in `obj+0x38/+0x44`, with flag `obj+0x50`. The consumer was not found
  (**UNCERTAIN**: wingtip vortex or contrail emitters).
* **Height**: `obj+0x68 = y·s` of the `height` helper (F-16: −1.691·5), with getter `FUN_0053e6f0`
  (**UNCERTAIN**: ground clearance).
* The F-16 `Canopy1/2` helpers give the canopy an x-axis, which is used only by the ejection spin. The MiG-23 `WingL1/R1…`
  frames are unregistered, so there is no swing-wing animation.

## 4. Port pseudo-code
```
load(xfr):  for child in root.children: id = lookup_ci(child.name); if !id: skip
              P[id] = child.translation            // X-file coords, ignore scale if model unscaled
            for id in 1..0x27 with part & P[id+0x3f]:
              a,b = P[id+0x3f], P[id+0x67]; d[id] = |a|<=|b| ? norm(b-a) : norm(a-b)
            hide helper frames (X1, X2, Station*, Camera, EndWing*, Engine*, height)
frame(t):   for part id: (θ, vis) = table §2 (sample ramps at t); if !vis: hide
              else part.local = T(P[id]) · R(axis=d[id], angle=−θ)   // X-file (LH) space
```
Discrepancy with flight-model.md §7/§8: the visuals prove that event 8 / `S+0x340` = speed brakes,
event 9 / `S+0x360` = hook, and `S+0x2cc` = drag-chute state (not gear). Recheck the drag-code labels there.
