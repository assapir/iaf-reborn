# Jane's IAF: how aircraft model parts move (reverse-engineered spec)

Sources: `assets/ghidra/iafjets.c`, plus `objdump` of `iafjets.exe` for routines Ghidra did not
decompile. The key one is the per-part callback `0x59dd70`. Constants come from `.rdata`.
Items marked **UNCERTAIN** are guesses. Offsets written `S+x` are in the flight state (`veh+0xc30`, see
flight-model.md), and **type** is the aircraft type `veh+0xc54`, set by `FUN_005a5bb0`:
100 F-16, 110 F-15, 120/200 F-4, 130 Kfir, 140 Lavi, 150 MiG-21, 160 MiG-23, 170 MiG-25, 180 MiG-29,
190 Mirage, 210 MiG-17, 220 Tu-22, 225 C-130.

## 1. Load time

**Name → id table.** Built by `FUN_00585040`. Each `FUN_005dd187("x3ds_Name"); FUN_00584fe0(id)` call
puts one entry into a hash map `id → name`. Then, for every registered `id` in 1..0x27, it adds
`name+"1"` as id `id+0x3f` and `name+"2"` as id `id+0x67`. Those are the X1/X2 hinge helpers.
All names are copied into a flat table of 0x8f entries × 0x30 bytes (`global+0x74`):
`{char name[32]; Clump* clump(+0x20); float pos[3](+0x24)}`. Entry 0x3c is `"x3ds_top02"` (purpose
unknown). Other ids: Turret 0x18, Radar 0x19, Carrier 0x1a, Launcher 0x1b, Missile 0x1c,
RotorA-D 0x1d-0x20, WheelsA-F 0x21-0x26, StationA-I 0x29-0x31, StationGun 0x32, StationCha 0x33,
StationFla 0x34, Pilon 0x35, Camera 0x36, EndWingL 0x37, EndWingR 0x38, Height 0x39,
EngineL 0x3a, EngineR 0x3b.

**Frame loading.** Only `*.xfr` files use the table. `FUN_00586840` clears all `clump` pointers
(**not** the positions, so an entry that no longer exists keeps the position from the previous model) and calls
`FUN_0041cb80` → `FUN_0041c850`. That loads the root frame and, for **every direct child of the root**,
calls `FUN_0041c240`:
* The frame name is looked up in the table with `_stricmp` (`FUN_005682b0`, case-insensitive: `x3ds_Canopy`
  and `x3ds_height` both match). The first match wins. Children that match no name are dropped.
* `pos = (-tx, -tz, ty) * scale`, where `(tx,ty,tz)` is row 3 of the child's `FrameTransformMatrix`
  (the frame origin, **not** the centroid of the helper triangle), and `scale` is the clump scale (F-16: 5.0).
  Call this frame "E". Only the frame translation is used. In all shipped models every frame rotation is identity.
* The child's mesh becomes its own clump (`entry.clump`).
* `FUN_0041c650`: `EngineR`/`EngineR1` → `clump+0x280`, `EngineL`/`EngineL1` → `clump+0x28c`.
  These are **raw** `(tx,ty,tz)*scale` with no axis swap. The first of the pair found is stored. When the second
  arrives, `clump+0x298 = |y_first - y_second|` (the flame radius) and `clump+0x27c++`. If the second one is the
  plain `EngineX`, it overwrites the stored position.
  `FUN_0041c7c0`: `StationGun` → `clump+0x29c` (raw, used for the muzzle flash).

**Graphics object.** Built by `FUN_0053c030`, called from constructor `FUN_0053bf40`. `vec3 axis[0x35]` lives at `obj+0x28`:
```
for id in 1..0x27: if entry[id].clump:                 // one "Subpart" object per present part
    part = new Subpart(id, entry[id].clump); part.pos = entry[id].pos; obj.parts.append(part)
for id in 0x29..0x34: axis[id-1] = entry[id].clump ? entry[id].pos : 0   // weapon stations
if entry[0x38].clump (EndWingR): obj+0x50=1; obj+0x38=(L.x,-L.y,L.z); obj+0x44=(R.x,-R.y,R.z)
obj+0x68 = entry[0x39].clump ? entry[0x39].pos.z : 0   // Height helper (up component)
obj+0x2c = Pilon? Pilon.pos : Camera? Camera.pos : (0,0,cfg "PilonDefaultZ")  // FUN_0053c9e0 default
EngineL/EngineR also become Subparts, ids 0x3a/0x3b
for id in 1..0x27: if entry[id+0x3f].clump:              // X1 exists (X2 is NOT checked)
    P1 = entry[id+0x3f].pos; P2 = entry[id+0x67].pos
    axis[id] = |P1| <= |P2| ? normalize(P2-P1) : normalize(P1-P2)
    hide X1 and X2 clumps (FUN_00402210)
```
**The axis always points from the helper nearer the model origin toward the farther one.**
Which helper is named `1` or `2` does not matter. For left/right pairs the axes therefore point outboard, in mirrored
directions. If both helpers are the same distance from the origin, the direction is effectively arbitrary
(the F-16 `Hook1/2` differ by 0.0004). If there is no X1, `axis = 0`, and the part is drawn **unrotated**.

**Pivot = the part frame's own origin** (`part.pos`), not the helper line. On most parts the helpers sit
on the hinge (for example, the F-16 AilerL2 helper triangle centroid equals the AilerL origin). On the F-16 main gear they
do not, and the rotation is still about the part origin.

## 2. Per-frame pose (render: `FUN_004d8930`, hardware path `FUN_004d9a20`)
Only the nearest LOD, the `_h.xfr` model, has parts (`_m.x` and `_l.x` are merged meshes). For each part,
the renderer calls the owner's `vtable[1](time*, id, &visible, &pos, &angles[3])`. For flown aircraft this is
the flight model `FUN_0059dd70` (vtable `0x60df60`). It sets `visible=1` first, and only `angles[1]` is used.
If `visible==0`, the part is not drawn.
If `axis[id]` is non-zero, `FUN_004d9570`/`FUN_004da000` rotate the part by `angles[1]` about
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
`FUN_0059feb0`/inline: `τ = clamp(now - t0, 0, 3.5)`, `v = τ < t_end ? v0 + rate·τ : target`,
clamped to `[min,max]`, then wrapped to (-π, π] (`FUN_0044ed30`). The limits are set in the constructor
(`FUN_005b72d0` calls near l.281787). The rates are set in `FUN_005a2a10`: 0.5 rad/s for S+0x300..0x360 and
0.7 rad/s for S+0x380..0x400. A target is set by `FUN_0059fe30(now, v_now, target, |rate|)`.

| ramp | meaning (visual) | range (rad / deg) | rate | target set by |
|---|---|---|---|---|
| S+0x300 | flaps | [0, 0.29275] / 16.8° | 0.5 | ev 6 `FUN_0059cf50`: on → max·(type100 ? 0.33 : 1), off → 0 |
| S+0x320 | gear retraction (0 = down) | [0, 1.569] / 89.9° | 0.5 | ev 7 `FUN_0059d170`: flag → 0 (down), else → max (up) |
| S+0x340 | speed brakes | [0, 0.855] / 49° | 0.5 | ev 8 `FUN_0059d370`: flag → max, else → 0 |
| S+0x360 | arrestor hook | [0, 0.7855] / 45° | 0.5 | ev 9 `FUN_0059d570`: flag → max, else → 0 |
| S+0x380 | rudder | ±0.3927 / 22.5° | 0.7 | airborne: pedal `FUN_0059c910` → `ru·0.3926`; on ground (S+0x2a0≠0): stick roll `FUN_0059d770` → `sr·(−0.3926)` |
| S+0x3a0 / 0x3c0 | elevator L / R | ±0.5236 / 30° | 0.7 | `FUN_0059da00` (below) |
| S+0x3e0 / 0x400 | aileron (elevon) L / R | ±0.7855 / 45° | 0.7 | airborne, type≠130/190: `FUN_0059d770` → both `= −0.7855·sr`; on ground the ailerons are not updated |

Pitch mixer `FUN_0059da00` (sp = S+0x2e4, +pull; sr = S+0x2d8 = S+0x2e8, +right):
```
A = (type in {190,130}) ? 0.7855 : 0.5236
f = type in {110,190,130} ? 0.5 : type==100 ? 0.65 : 1.0
m = type in {110,100,190,130} ? (1-f)·sr·A : 0            // differential tail / elevon roll
L = sp·f·A − m ;  R = −sp·f·A − m ; if type in {120,200}: L,R *= 0.6 (F-4)
type 190/130 (delta): S+0x3e0 := L, S+0x400 := R   else: S+0x3a0 := L, S+0x3c0 := R
```
Initial state (`FUN_005a2a10`): airborne start → gear 1.569 (up), flaps 0, speed brake 0. Ground start
→ gear 0, flaps 0.29275, speed brake 0.855 (open). There is no canopy ramp.

### Callback `FUN_0059dd70`: angle θ = angles[1] and visibility per part id

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
| 0x14-0x26 (pilot, pilotB, canopy, canopyB, turret…, wheels) | 0 | **0** | hidden on the flying aircraft (**UNCERTAIN** whether another path draws canopy/pilot; the F-16 canopy glass exists only in the `Canopy` frame) |
| 0x3a/0x3b EngineL/R, other ids | 0 | 0 | |

Gear sequencing: legs and doors share one ramp, so there is no separate door ramp and no door motion. A full cycle
takes 1.569/0.5 = 3.14 s. Legs rotate while visible and vanish at full retraction (on MiG-29 and Mirage, before full retraction).
The doors are shown in their modelled (open) pose whenever the gear is not fully up.
Sign flips such as "110: −g" compensate for each model's helper order. With the §2 formula, every type gives the physically right motion.

**Drag chute** (`FUN_0059f8b0`, event 0x17): `S+0x2cc` goes 0 → 1 if pressed airborne, or 0 → 2 if pressed on the ground (deployed).
Pressing again at 2 → 3 (jettisoned). Only types 120,130,160,180,190,200 allocate the jitter object `S+0x2d0`
(the models with `Parach`: Kfir, F-4, MiG-23/29, Mirage). While the state is 2, the callback does
`if now − t0 > 0.1: θ = uniform(−π/36, +π/36) (±5°); t0 = now` (`FUN_0059ff30`, `rand()/32767`).

**Ejection** (`FUN_0053d0b0` object, vtable `0x608840`, callback `0x53d180`; **UNCERTAIN** details). It reuses
the aircraft's `pilot` (0x14), `pilotB` (0x15) and `canopy` (0x16) subparts. The canopy and canopyB positions are
captured by `FUN_0053de30`. pilot and pilotB: θ=0, visible while `obj+0xc && !obj+8`. Canopy: `obj+0x10 += 10°`
**every call** (frame-rate dependent), wrapping at 360°, θ = that angle in radians about the canopy's X1/X2 axis.
canopyB (0x17) is drawn at the stored canopy position, ids 0x1d-0x20 at the canopyB position, visible while `obj+0x14 && !obj+8`.
Config `Eject/Speed`.

## 3. Other helpers
* **Stations** (A..I = index 0..8, Gun 9, Cha 10, Fla 11): the store object (`FUN_0053a820`) takes its
  attach point from `axis[index+0x28]` = E-frame station position ((0,0,0) if the frame is missing). Stores on
  stations 0..8 are drawn by `FUN_0053ca60`. The muzzle flash `FUN_00411d60` is drawn at raw `clump+0x29c` (StationGun)
  when the render flag `+0x3e` is set.
* **EngineL/R (+L1/R1)** → afterburner `FUN_004121b0(level, x,y,z, r, scale)`, called from `FUN_0041e1f0` with level = render bytes +0x3c (right) / +0x3d (left), 0..100.
  Nothing is drawn if level ≤ 74. `k = (level−75)·0.04`. Two to three nested 12-segment cones start at the raw
  nozzle position, with base radius `r = |ΔY(EngineX, EngineX1)|`. The tip is at
  `z − ((3.5+j)·k·scale + 1.5·i)` (toward −Z, aft) with radius `r·(j+0.25)`, where `j = (rand%21−10)·0.01` and
  i = 3 (2 in one render mode). Each extra cone adds `0.3·r` of radius. **UNCERTAIN** exact texture/alpha.
* **Camera**: eye point `obj+0x2c`, E frame. A `Pilon` frame takes priority if present. The default is (0,0,`PilonDefaultZ`).
  Config `Camera/BackCockpitDistance` (default 20) goes to `global[0]`. **UNCERTAIN** which view uses which.
* **EndWingL/R**: stored as `(−x·s, z·s, y·s)` in `obj+0x38/+0x44`, with flag `obj+0x50`. The consumer was not found
  (**UNCERTAIN**: wingtip vortex or contrail emitters).
* **Height**: `obj+0x68 = y·s` of the `height` helper (F-16: −1.691·5), with getter `FUN_0053cd20`
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
