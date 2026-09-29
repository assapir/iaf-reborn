# Jane's IAF flight model (reverse-engineered spec)

Source: Ghidra dump `assets/ghidra/iafjets.c` + `objdump` of `install/iafjets.exe` (several key
routines, e.g. `5a15e0`, `5b4580`, `5b4840`, were not decompiled by Ghidra and were read from the
disassembly). All physics is SI: m, kg, s, N, rad. Constants were read from the `.rdata` of the exe.
`UNCERTAIN` marks guesses.

## 0. Architecture (important for a faithful port)

* Per-aircraft params `P` (struct filled by the bd.ibx loader) and a double-buffered state `S`
  (`veh+0xc34` write copy, `veh+0xc30` read copy, 0x610 bytes each, swapped by `FUN_005a5530`).
* **The model is event-driven and analytic, not a per-frame integrator.** Every state variable is
  a "channel" that stores a base time `t0` and a closed-form curve; it is sampled at any time `t`:
  * **Ramp** (type A, 0x20 bytes: `t0:f64, v0, target, rate, min, max, t_end`), set by
    `FUN_0059fe30(obj, now, v_now, target, rate)` (`rate:=±|rate|` toward target,
    `t_end=(target-v_now)/rate`), sampled by `FUN_0059feb0`: `τ=clamp(t-t0,0,3.5)`,
    `v = τ<t_end ? v0+rate·τ : target`, clamped to `[min,max]`.
  * **Accel-limited angle** (type B, 0x30 bytes: `t0, pos0, rate0, targetRate, t_end, pos_end,
    accel, startAccel, stopAccel, minRate, maxRate`), set by `FUN_005aac90(obj, now, pos, rate,
    targetRate)`: clamp rates to `[minRate,maxRate]`; `Δ=targetRate-rate`; if
    `|targetRate| > 0.02·maxRate` → `accel = startAccel·sign(Δ)` else `accel = stopAccel·sign(Δ)`;
    `t_end=Δ/accel`; `pos_end = wrap(pos + rate·t_end + ½·accel·t_end²)`. Sample (`τ≤1.1`):
    `τ≤t_end: pos0+rate0·τ+½accel·τ², rate0+accel·τ`; else `pos_end+targetRate·(τ-t_end), targetRate`.
    Angles wrapped to (-π,π] (`FUN_0056653a` = fmod).
  * **Kinematic axis** (type C, 0x20 bytes: `p0, t0:f64, v, a, min, max`), `FUN_005aab30/aab50`:
    `τ=clamp(t-t0,0,1.1)`, `p = p0 + v·τ + ½a·τ²` (clamped `[min,max]`), velocity `v + a·τ`.
    Three of them: `S+0x20` X (east), `S+0x40` Y (north), `S+0x60` Z (up, altitude).
* Updates (timers created in `FUN_005a2a10` @005a2a10, the (re)initialiser):
  * **UpdateAeroData** – every **1.0 s** (`FUN_005a15b0` → `FUN_005a42e0` @005a42e0) and also
    immediately on every control event (stick, throttle, rudder, flaps …, dispatcher
    `FUN_0059c4f0`). Recomputes thrust, drag, mass, lift *targets*, roll-rate target, fuel flow.
  * **UpdateAccelAndRates** – every **0.2 s** (`5a15e0`, disassembly only). Recomputes alpha target,
    beta, the acceleration vector from current channel values, and re-bases every channel.
  * A port can run both at a fixed dt (e.g. 60 Hz) — that is smoother but not bit-faithful; to be
    faithful keep 1 Hz/5 Hz + event updates and constant acceleration between 5 Hz ticks.

## 1. Parameters (loader `FUN_005af920` @005af920, reads `FUN_005b1a20(section,key,default)`)

Conversion constants: lb→kg ×0.45359, ft²→m² ×0.092903, ft→m ×0.3048, deg→rad ×0.0174533,
DragIndex ×1e-4. "deg→rad*" = wrapped to (-180,180] then ×π/180.

| key | P+off | default (hex) | file unit | stored |
|---|---|---|---|---|
| EmptyWeight | 0x8c | 16000 (0x467a0000) | lb | kg |
| MaxWeight | 0xd0 | 32000 (0x46fa0000) | lb | kg (only used for lift-ramp limits) |
| WingArea | 0x80 | 300 | ft² | m² |
| WingSpan | 0x7c | 32 | ft | m |
| MaxRollRate | 0xac | 100 | deg/s | rad/s |
| RollAccel | 0xb4 | 300 | deg/s² | rad/s² |
| StopAccel | 0xb0 | 300 | deg/s² | rad/s² |
| MaxBeta | 0xb8 | 10 | deg | rad* |
| BetaRate | 0xbc | 10 | deg/s | rad/s* |
| MaxG (`DAT_0066f4a4`) | 0xc8 | 9 | g | **MaxG − 1** |
| MinG (`DAT_0066f49c`) | 0xcc | −3 | g | **MinG − 1** |
| G_Rate | 0xd8 | 5 | g/s | raw |
| G_RateForAoa | 0xe0 | 1 | g/s | raw |
| DragVdmin | 0xec | 302 | ? | raw, unused in flight path found |
| DragMinFactorOfMaxThrust | 0xf0 | 0.2 | – | raw, unused found |
| FlapsDragIndex | 0xf4 | 76 | DI | ×1e-4 |
| SpeedBrakesDragIndex | 0xf8 | 320 | DI | ×1e-4 |
| LandingGearDragIndex | 0xfc | 300 | DI | ×1e-4 |
| LandingHookDragIndex | 0x100 | 100 | DI | ×1e-4 |
| ParachuteDragIndex | 0x104 | 0 | DI | ×1e-4 (no reader found) |
| PlaneDragIndex | 0x108 | 500 | DI | ×1e-4 (= CD0) |
| WheelsBrakeDragIndex | 0x10c | 5000 | DI | ×1e-4 (= friction coeff) |
| FlapsLiftCoef | 0x110 | 0.2 | – | clamped to [0,0.5] |
| FuelWeight | 0xc0 | 6000 | lb | kg |
| FuelFlowAtMaxThrust | 0xc4 | 2 | lb/s | kg/s |
| Thrust{Min,Max}Mach{Min,Max}Alt{0,1} | 0x114..0x130 | see below | lbf | raw (×4.4479 at use) |
| HasAfterBurner | 0x164 (int) | 1 | – | `value > 0` |
| StartVibsG | 0x160 | 1 | g | raw |
| UseFlightLimits | 0x88 (int) | 1 | – | ftol |
| MaxNegAlpha / MaxPosAlpha | 0x90 / 0x94 | −5 / 27.5 | deg | rad* |
| LimitAlphaVisual | 0x134 | 15 | deg | rad* |
| MaxAlphaRate, AlphaStopAccel, AlphaStartAccel, AlphaK, AlphaBeta | 0x98,0x9c,0xa0,0xa4,0xa8 | 2.5,0.1,0.5,8,0.1 | – | raw |
| StartMoveStickCenterG | 0x13c | 2 | g | raw |
| MapCenterStick | 0x138 | 0 | g | raw |
| OverGThresh | 0x168 | 6.7 | g | raw (getter id 27 of `FUN_005a64b0`; only used for the Betty "Over G" voice, §13) |
| Multiplayer{Roll,Pitch}{K,Beta} | 0x150/0x154/0x158/0x15c | 9,0,9,0 | – | network clone smoothing only |

Thrust offsets: MinMachMinAlt0/1 = 0x114/0x118, MinMachMaxAlt0/1 = 0x11c/0x120,
MaxMachMinAlt0/1 = 0x124/0x128, MaxMachMaxAlt0/1 = 0x12c/0x130 (defaults 12012.6, 19230.4, 1629.7,
2691.0, 11128.1, 30873.2, 2394.7, 8670.2 lbf). `P+0x84` (int) = vibration allowed
(pref `DAT_00694a64[0xe]==0` or multiplayer). `P+0xdc` = 10° (rad), constructor `FUN_005af4f0`.

Derived at load time (envelope `E` = `FUN_005b23c0(FlightEnvelopeFile)`, functions in §3):
```
v1 = Vmin(330 m, 1 g);  vG = Vmin(330 m, MaxG)          // FUN_005b1fa0, alt 330 m (0x43a50000)
qS1 = qS(330 m, v1);   qS2 = qS(330 m, vG)               // §2
W   = EmptyWeight_kg * 9.806
P.e4 (0xe4) = W / qS2                                     // "CL at alpha=0"
P.e8 (0xe8) = (W - qS1*e4) / (qS1 * MaxPosAlpha)          // dCL/dalpha
P.14c = Vmin(10000 m, 1 g)
P.140 = Ceiling(StartMoveStickCenterG);  P.144 = Vmin(3048 m, StartMoveStickCenterG)
P.170 = (MapCenterStick - 1)/(10 - P.144);  P.174 = MapCenterStick - P.170*10   // stick-centre line
```
Global slopes set in `FUN_005aef10` (copies P into S channel limits):
`gRateSlope(V) = G_Rate·(0.01 + 0.99·(V-20)/200)` i.e. `a=G_Rate·0.99·0.005, b=G_Rate·0.01-20a`;
same for G_RateForAoa; roll factor `k=0.00475, c=-0.045`; alpha-dynamics speed factor
`0.004995·V − 0.0989`; beta-rate `BetaRate·0.0025·V`.

## 2. Atmosphere — `FUN_005b0f00(alt, V, *mach, ΔT=0, *rho, *)` @005b0f00
```
alt = clamp(alt, -500, 20000)
H   = (1 - alt*1.5731270e-7) * alt          // geopotential
T0  = 288.15 + ΔT
if H <= 11000: T = T0 - 0.0065*H;  θ = T/T0;  p = θ^5.255876 * 10332.27
else:          T = 216.65 + ΔT;   θ = T/T0;
               p = θ^5.255876 * 10332.27 * exp((alt - 11000) * (-0.03404 / T))   // note: alt, not H
mach = V / sqrt(401.8743 * T)
rho  = 1.225 * (p / 10332.27) / θ           // p in kgf/m²
qS(V) = 0.5 * rho * V² * WingArea_m2        // FUN_005b1030
```

## 3. Flight envelope (`16.dat`) — `FUN_005b23c0`, `FUN_005b2f10`, `FUN_005b2b20`
Parsing: lines are read with `sscanf("%d %d %d", g, vel_kt, alt_ft)`; **a line with a decimal (e.g.
`0 70.3 13000`) returns 2 and is silently skipped**. vel ×0.514722 → m/s, alt ×0.3048 → m;
`AltitudeStep` ×0.3048. Rows grouped per g (consecutive equal g); first alt of each graph must be 0.
Graphs are indexed by **integer g** (index = g + idx0, idx0 = graph index of g=0; ≤14 rows each);
a sentinel row (alt 30000 m, last vel) is appended; `ceilAlt[g]` = alt of last real row;
pad graphs below min g / above max g copy the edge graph with alt−1, vel+1. `gmin/gmax` = first/last g.

* `Ceiling(g)` `FUN_005b22e0`: clamp g to [gmin,gmax], `i=trunc(g)`, linear interp of `ceilAlt`
  between graph i and i+1 (g>0) or i−1 (g≤0).
* `Vmin(alt,g)` `FUN_005b1fa0` (g≥0) / `FUN_005b2170` (g<0): clamp g; `alt=clamp(alt,0,Ceiling(g)-1)`;
  graph A=trunc(g), graph B=A+1 (A−1 for g<0). In A take segment i with `altA[i] ≤ alt < altA[i+1]`,
  in B take last row j with `altB[j] ≤ alt`; fit a plane through `(altA[i],A,vA[i])`,
  `(altA[i+1],A,vA[i+1])`, `(altB[j],B,vB[j])` (`FUN_005bbf00`) and evaluate at `(alt,g)`.
* Second pass `FUN_005b2b20` builds, for every altitude level `L_k = k·AltitudeStep`, a list of
  `(g, Vmin(L_k,g))` points (linear interp of each graph between its rows); separate lists for g≥0
  (`E+0x44`) and g≤0 (`E+0x58`), assumed sorted by velocity.
* `GLimit(alt, V, gcmd)` `FUN_005b2810` returns code + limit:
  `k=max(0,trunc(alt/step))`; if `k+1` beyond list count → code 2 (`lim=-1`).
  Look up bracketing points by velocity (`FUN_005b3330`) in levels k and k+1.
  If V is above all points of level k: `alt ≤ Ceiling(gcmd)` → code 3 (no limit), else code 4 with
  `lim = FUN_005b2770`: linear in alt, `gmax` at `Ceiling(gmax)` → 0 at the g=0 ceiling (sym. for
  negative), clamped at 0 (UNCERTAIN: second anchor). If V below all points of level k+1 → code 0
  (stall). Otherwise code 4 with `lim` = plane through `(L_k,Vlo,glo)`, `(L_k,Vhi,ghi)`,
  `(L_{k+1},V',g')` evaluated at `(alt,V)`; forced to 0 if its sign differs from gcmd.

## 4. Aero update (1 Hz + events): `FUN_005b0a20` @005b0a20 (airborne) / `FUN_005b7a20` (on ground)
Inputs: `alt=Z`, `V=|v|` (capped 1200 m/s, `5a3a90`), throttle `thr=S+0x2dc`, stick pitch
`sp=S+0x2e4` (= −joystick Y, +pull), stick roll `sr=S+0x2e8`, rudder `ru=S+0x2ec`, flaps
`fl=S+0x300 ramp`, extra mass `m_x = S+0x424 + fuel(S+0x430 ramp)`, stores DI `S+0x428+S+0x42c`,
flags (bit 2 = no fuel → set when fuel < 1e-5, bits 4/8 engine dead, 0x80&0x100 AB dead, 0x40 leak).
```
mach, rho = atmos(alt, V);  qS = qS(V)
T, rpm, ff, abStage = Thrust(alt, mach, thr, flags)          // §4.1
m  = EmptyWeight + m_x
L, Lnoflap, dragX, stall, vib = Lift(V, alt, qS, m, sp, att) // §4.2
alpha = stall ? 0 : clamp((Lnoflap - e4*qS)/(e8*qS), MaxNegAlpha, MaxPosAlpha)
D  = Drag(qS, n = L/(m*9.806), alpha, config, storesDI)     // §4.3
beta_cmd = (ru + 10*(S+0x428 - S+0x42c)) * MaxBeta           // FUN_005b1840 (asym. stores; UNCERTAIN)
rollRate_cmd = MaxRollRate * sr
```
Then (`FUN_005a42e0`): store T→S+0x1d4, D→S+0x1dc, m→S+0x1d8; set ramps
`S+0x1e0 := ramp(L)` and `S+0x200 := ramp(Lnoflap)` with rates `G_Rate·m·9.806` and
`G_RateForAoa·m·9.806` if `V ≥ 220`, else `gRateSlope(V)·m·9.806` (1 % at 20 m/s … 100 % at 220);
ramp limits `[MaxWeight·(MinG−1)·g, MaxWeight·(MaxG−1)·g]`. RPM ramp `S+0x1b0 := 100·rpm` at 15 %/s.
Fuel ramp `S+0x430` toward 0 at `ff` kg/s (limits [0,FuelWeight]). Roll channel (type B at S+0x80,
startAccel=RollAccel, stopAccel=StopAccel, rates ±MaxRollRate) gets
`targetRate = rollRate_cmd · kroll`, where
`Veff = ((-1.305e-5 + 3.1825e-9·V)·alt + 1.0017)·V − 3.122`, `kroll = Veff<220 ? 0.00475·Veff−0.045 : 1`
(no lower clamp). Alpha dynamics via `FUN_005a7590` (§5), beta via `FUN_005a78f0` (§5).

### 4.1 Thrust — `FUN_005b1050` @005b1050
```
a = clamp(alt*5e-5, 0, 1)            // alt/20000 m
M = clamp(mach/1.2, 0, 1)            // mach*0.8333
if flags&2: thr = 0
if (flags&4 && flags&8) || !engineOn(S+0x1d0) || flags&2:  T=0, stage=0, k=0, rpm=0 → fuel
if flags&0x80 && flags&0x100 && thr>=0.75: thr = 0.74
if hasAB (P+0x164 && not AI-mode):   // noAB = !HasAfterBurner || (FUN_005c58a0()∉{0,7,8})
    thr<0.75:  k = 0.05 + 0.7432432*thr, stage 0     // thr 0.74 ("military") → k≈0.60
    thr<0.875: k = 0.875, stage 1 (AB1);  else k = 1.0, stage 2 (AB2)
else:  k = (thr-0.2)*1.25; stage = thr<0.75?0 : thr<0.875?1:2
if flags&4 || flags&8: k *= 0.5
T0 = lerp(k,MinMachMinAlt0,..1); T1 = lerp(k,MinMachMaxAlt0,..1)
T2 = lerp(k,MaxMachMinAlt0,..1); T3 = lerp(k,MaxMachMaxAlt0,..1)
T  = lerp(a, lerp(M,T0,T2), lerp(M,T1,T3)) * 4.4479       // N
rpm = 0.6 + 0.4*thr*1.3513514      (engine off: 0)          // 1.0 at thr=0.74
ff  = thr * FuelFlowAtMaxThrust;  if k <= 0.6: ff *= 0.25;  if flags&0x40: ff += 0.25*FFmax
if unlimited-fuel pref (DAT_00694a64+0x44): ff = 0
```
"0"/"1" suffix = value at k=0 / k=1 (full AB2); interpolation is linear, so idle (k=0.05) ≈ 5 %.

### 4.2 Commanded G / lift — `FUN_005b13a0` @005b13a0
`bStall` (stalls enabled) = pref `+0x38 == 0` (always true in multiplayer). `latched` =
stall/limit event within the last 3.0 s (`S+0x2f8` timestamp, set/cleared by `FUN_005a7050`).
```
if latched && bStall: return L=0, dragX=1.2        (departure: no lift up to 3 s)
c = 1;  if V < P.144: c = P.170*V + P.174           // stick-centre shift (StartMoveStickCenterG/MapCenterStick)
g = sp>0 ? c + sp*(MaxG-1) : c + (-sp)*(MinG - c)   // P.c8=MaxG-1, P.cc-(-1)=MinG
if |g-1| < 1e-5 && |roll| < 10°: g = cos(pitch)/cos(roll)   // 1-g hold with neutral stick
if UseFlightLimits:
   code, lim = GLimit(alt, V, g)
   code 0 or 2 (stall/too high): dragX=1.2; bStall ? (g=0, stallFlag) : g=min(0.4,g)
   code 3: unchanged
   code 4: g<=0: g=max(g,lim)
           g>0 : if g>=lim { dragX=(g-lim)/MaxG; g=lim };  if !bStall && g<0.4: g=min(0.4, g_cmd)
   vibration flag if lim <= StartVibsG && code 4 && g_cmd>0 && P+0x84 && !AI
[AI-only oddity: if g>4.3 → g = 4 + 0.02 g²  (UNCERTAIN)]
Lnoflap = g * m * 9.806
L = Lnoflap;  if V < 125: L += |L| * FlapsLiftCoef * flaps * 3.4158838
```
`dragX` is **not** added to drag; it only feeds the stall/limit latch (`S+0x2f8`) and shake.

### 4.3 Drag — `FUN_005b1730` @005b1730 (checked in disassembly)
config ints: `sb=[6]` speed brakes deployed (`S+0x360` ramp at max), `gear=[7]` (`S+0x2cc==2`),
`hook=[8]` (always 0 in this build); `flaps=[0]` (float, `S+0x300` ramp).
```
CL = qS>0 ? cos(alpha)*m*n*9.806/qS : 0
K  = 1 / (π * WingSpan²/WingArea * 0.85)
CD = PlaneDI + sb*SpeedBrakesDI + hook*HookDI + gear*GearDI*(AImode?0:1)
     + FlapsDI*flaps*3.4158838 + storesDI + K*CL²          // all DI already ×1e-4
D  = CD * qS
```

## 5. Accel/rate update (every 0.2 s) — `5a15e0` (disasm), `FUN_005b0e20`, `FUN_005b1860`
```
t = now;  sample L = S+0x1e0(t), Laoa = S+0x200(t), att = orientation(t) (§6)
alphaTarget = clamp((Laoa - e4*qS)/(e8*qS), MaxNegAlpha, min(MaxPosAlpha, LimitAlphaVisual))  // FUN_005b1b90
Fbody (y fwd, z up, x lateral) with α=S+0x220(t), β=S+0x280(t):
  x = D*sin β + 5*V²*β
  y = T + L*sin α - D*cos α*cos β
  z = L*cos α + D*sin α*cos β
M = FUN_005b7580(pitch=att[0], roll=att[1], heading=att[2])   // cb=cos b etc.
  M = [[cH cP, -sH cP, sP],
       [sR sP cH - sH cR, -cH cR - sR sH sP, -sR cP],
       [sH sR + cR sP cH,  cH sR - cR sH sP, -cP cR]]
r = Mᵀ·(y, x, -z);  Fworld = (-r1, r0, r2)                    // FUN_005b74d0; world X east, Y north, Z up
acc = Fworld/m + (0, 0, -9.806)
for axis in X,Y,Z: p=p(t); v=v(t); set(p0=p, t0=now, v, a=acc_axis)   // exact constant-accel steps
```
On ground (`S+0x2a0`): `FUN_005b7e40` instead, and if vertical accel < 0 the Z velocity/accel are
zeroed (stays on runway). Also re-bases the lift ramps, the roll channel (pos := att roll) and alpha.

Alpha dynamics (`FUN_005a7590`, 1 Hz; type B at S+0x220, target S+0x258 = alphaTarget):
`f = V≥220 ? 1 : max(0.001, 0.004995V−0.0989)`; channel startAccel=AlphaStartAccel·f,
stopAccel=AlphaStopAccel·f, rates ±MaxAlphaRate·f, K=AlphaK·f, B=AlphaBeta·f;
`err = wrap(alphaTarget − α)`, `damp = B·rate·MaxRate` (×0.5 if |rate|>π),
`targetRate = clamp(err/π·K/MaxRate − damp, −1, 1)·MaxRate`.

Beta (`FUN_005a78f0`, airborne only): ramp `S+0x280` toward `beta_cmd` at
`V≥375 ? BetaRate : max(BetaRate·0.0025·V, 0.25·BetaRate)`, limits ±MaxBeta; a yaw-coupling term
using globals `DAT_008407c8..d0` is never written (=0) → no effect (UNCERTAIN).

## 6. Attitude (render/orientation) — mode object `veh+0xc6c`, vtable `0x60dee8`: `5b4580`/`5b4840`
Normal mode: sample v(t) (type C velocities), roll φ(t) (S+0x80), α(t), β(t); then
```
f = v/|v|;  w = S+0x08 (wing vector saved at last 5 Hz tick, together with φ_ref = S+0x18)
w = rotate(w, axis f, φ - φ_ref)            // Rodrigues (FUN_00461930/467d50/466580)
f = rotate(f, axis w, -α)                   // nose above velocity
f = rotate(f, axis f×w, β)
heading = atan2(f.x, f.y);  pitch = asin(f.z);  roll = ±acos(clamp(w·horiz,−1,1)) (sign by w.z)
```
`FUN_005a7520(pitch,roll,heading,S)` stores the Euler angles at S+0x14 and `w = Mᵀ·(−1,0,0)`
mapping at S+0x08. Other modes (`veh+0xc70` → `FUN_005a7d50`, `veh+0xc7c` → `FUN_005a96c0`) are
special departure/spin/tail-slide manoeuvres — **not covered** (UNCERTAIN).
Airborne init (`FUN_005a2a10`): `v = (V sinψ, V cosψ, vz)`, throttle 0.74, engine on.

## 7. Ground roll — `FUN_005b7a20` (replaces §4 while `S+0x2a0`≠0)
```
easy = pref+0x1c || pref+0x20   (DAT_00694a64 flags; UNCERTAIN meaning)
L = 0.5*Lift(...);  L += |L|*FlapsLiftCoef*flaps*3.4158838
if !((V > 74.53 || sp > 0.5) && (gearDown || AI || pref+0x3c || easy)): L = 0
mu = brakes[6] * WheelsBrakeDI * (AI ? 2 : 1) + DAT_0084083c(=0, never written)
if !gearDown && !AI && !easy: mu = 20                      // belly landing
D = Drag(alpha=0, n=L/(m g)) + 0.5*mu*(m*9.806 - L);  D = max(D,0);  if V > 1: D *= 0.7
T = max(T,0);  nose-wheel yaw rate = clamp(sx*V*K/74.53, ±K), K = DAT_00840864 = 20°/s = 0.3490659 rad/s
(0 if gear up; 0 if |rate| < 1e-4).  sx = stick X S+0x2e8, NOT the rudder (see "Nose-wheel steering input")
```
The single "Brakes in/out" key drives ramp `S+0x360`, used as speed brake in the air and wheel brake
on the ground (UNCERTAIN mapping of events 7/8 = gear anim `S+0x320` / parachute `S+0x340`).

### Nose-wheel steering input
**Rule: on the ground the nose wheel is steered by the stick's roll axis (`S+0x2e8`), always, with no
conversion step. The rudder input is ignored on the ground.** This matches the instructor line "The stick
controls the nose wheel steering." Nothing converts stick X into a rudder input (motion 5), either on the
ground or as an airborne auto-rudder.

Evidence (all checked in objdump):
* **Call chain, stick X → nose wheel.** `5a15e0` @5a48ec–5a4963 pushes the args of `FUN_005b0a20`
  (`ecx` = FM params). Stack arg 6 is `S+0x2a0` (ground flag, tested as `param_7`). Stack args 15/16/17 are
  `S+0x2e4` (stick Y), `S+0x2e8` (stick X) and `S+0x2ec` (rudder); arg 18 is the vehicle.
  The ground branch @5b0a3c–5b0b2e forwards 30 stack args to `FUN_005b7a20` (`ret 0x78`). b0a20 args 6/7 and 29
  are dropped, so 7a20 stack arg 14 (`param_15`) = b0a20 arg 16 = **stick X**, `param_14` = stick Y and
  `param_16` = rudder. Ghidra's display of these argument lists is shifted by one; the push order is authoritative.
  In 7a20 the yaw rate is computed @5b7da6: `fld [esp+0x5c]` (entry+0x38 = `param_15`) `fmul [esp+0x2c]` (V)
  `fmul [0x840864]` `fdiv [0x60e568]` (74.53). `param_16` (rudder) is never read in 7a20.
  The earlier notes here said "`ru`"/"rudder"; that was wrong.
* **The rudder handler ignores the ground.** Motion 5 `FUN_0059c910` @59c934 stores
  `S+0x2e0`/`S+0x2ec = clamp(in+0x10, ±1)` and starts the ×0.3926 ramp only if `S+0x2a0 == 0`. On the ground
  the command is dropped, and `S+0x2ec` keeps its last airborne value. The only other writer is the init
  @5b7119, which sets it to 0. In the air, `S+0x2ec` feeds `FUN_005b1840` (@5a1e18 in `5a15e0`), which
  returns `(ru − x·k)·P+0xb8`, the β command for the beta ramp (§5).
* **Stick handler.** Motion 1 `FUN_0059c740` writes `S+0x2e8 = clamp(in+0x14, ±1)` (X) and
  `S+0x2e4 = −clamp(in+0x10, ±1)` (Y). It has no ground test. `FUN_0044de50` type 1 sets
  `+0x14 = arg[0]·0.01` and `+0x10 = arg[1]·0.01` (`0x5fcc80` = 0.01). The controller `FUN_004493a0` case 1 (@44b153)
  posts motion 1 with the raw `(x,y)` in the range ±100. When indicator 8 is set (UNCERTAIN: autopilot) and
  |x| or |y| ≥ 51, it first clears that indicator. Case 10 posts motion 5. Cases 2/3 fall to the default
  and return (jump table `0x44c714`, index bytes `0x44c81c`).
* **K = 20°/s.** `DAT_00840864` is set by a static initialiser: CRT table `.data 0x62372c` → `0x5b7950` →
  @5b7960 `K = DAT_00840844 · 20.0` (`0x60e584`). `DAT_00840844` is set by initialiser `0x623728` →
  `0x5b7780` = 1.0° (`0x60e578`) wrapped and converted to radians = 0.01745329. So K = 0.3490659 rad/s.
  Ghidra misses both writes.

**Keyboard path (`FUN_004df3d0`, key → `WM 0x532`).** The "Roll left/right" keys send GEV 2 and
"Pitch up/down" send GEV 3. Before sending, `FUN_004df3d0` rewrites both into **GEV 1 (stick)**:
* GEV 2: x = the key's lParam, y = the last keyboard y `DAT_0082ee9c`; x is stored in `DAT_0082ee98`.
* GEV 3: the same with the axes swapped.

So a keyboard-only player steers the nose wheel with **Left/Right arrow** as a full ±1 stick X while the key
is held. The release record sends x = 0.
GEV 2/3 keys are dropped when `this+0x24 && this+0x18`. GEV 10 rudder keys are dropped when
`this+0x2c && this+0x20`. GEV 5/6/9 throttle keys are dropped when `this+0x28 && this+0x1c`.
(UNCERTAIN: these are "joystick stick/rudder/throttle axis in use" flags. The DirectInput poller `FUN_004dddb0` sends
GEV 1 from lX/lY when `+0x24`, GEV 9 from the throttle axis when `+0x28`, and GEV 10 from a 4th axis
(`param_6`, rudder pedals/twist) when `+0x2c`.) No code path turns the Rudder keys into stick X on the ground,
and none adds rudder from roll.

**Default key table.** `0x647ff8 + n·0x24`, n = keys.trx line (0-based), 117 records, copied into the
runtime table `0x836e14` (`rep movs 0x41d` @4eef80; "defaults" button @5102a5). Record layout:
* +0 press GEV, +4/+8 press arg (x, y); +0xc release GEV, +0x10/+0x14 release args;
* +0x18 key: DirectInput DIK code (ushort), modifier byte at +0x1a (0x22 = Shift, e.g. Shift+W);
* +0x1c: −1, overwritten by a file loader @4dff56 (UNCERTAIN);
* +0x20: 1 = one-shot, 0 = held with release.

The key code of record k is at `0x648010 + k·0x24`, which is where the `0x648010` in docs/mfd.md comes from.

| n | keys.trx | Default key | Press → release |
|---|---|---|---|
| 24 | Pitch up | Up arrow (DIK 0xc8) | GEV 3 (0,+100) → GEV 3 (0,0) |
| 25 | Pitch down | Down arrow (0xd0) | GEV 3 (0,−100) → GEV 3 (0,0) |
| 26 | Roll left | Left arrow (0xcb) | GEV 2 (−100) → GEV 2 (0) |
| 27 | Roll right | Right arrow (0xcd) | GEV 2 (+100) → GEV 2 (0) |
| 37 | Rudder left | Numpad 0 / Ins (DIK_NUMPAD0 0x52) | GEV 10 (−100) → GEV 10 (0) |
| 38 | Rudder right | Numpad . / Del (DIK_DECIMAL 0x53) | GEV 10 (+100) → GEV 10 (0) |

For the port: on the ground, yaw rate = `clamp(stickX·V·0.3490659/74.53, ±0.3490659)` rad/s, i.e. full
steering authority at 74.53 m/s and above. It is 0 with the gear up. Ignore the rudder while `S+0x2a0` ≠ 0.
The sign convention of the yaw rate (right stick → right turn) was not traced (UNCERTAIN).

## 8. Controls / keys (dispatcher `FUN_0059c4f0`, event type → handler)
1 stick (`FUN_0059c740`): `S+0x2e4 = −clamp(y,−1,1)`, `S+0x2e8 = clamp(x,−1,1)`; ×0.25 when
input-mode 0x12 active, zeroed by 0x18 (UNCERTAIN meaning). 2 throttle (`FUN_0059cb60`): clamp
[0,1]; crossing into AB (≥0.75) from below sets 0.74 and schedules the AB value after
`max(0,(100−RPM%)·0.0667)` s (`FUN_0059cea0`); any throttle change turns the engine on (`S+0x1d0`).
3/4 RPM ±5 %: throttle ±0.0925 (`FUN_0059c6a0`/`c6e0`). 5 rudder (`S+0x2ec`, ramp ×0.3926; ignored on the ground, see §7).
6 flaps (`S+0x300`, ×0.33 target for aircraft type 100), 7/8/9 ramps `S+0x320/0x340/0x360`.
Throttle presets from keys.trx map naturally to RPM: idle 0, 65 % 0.0925, 70 % 0.185,
80 % 0.37, 90 % 0.555, military 0.74, AB1 [0.75,0.875), AB2 ≥0.875 (preset values themselves not
found; UNCERTAIN). Key names are loaded from `keys.trx` into `0x82eea8` (100-byte stride) by
`FUN_004e24d0`; the default key→command table is at `0x647ff8` (record layout in §7 "Nose-wheel steering input").

## 9. Misc
* g = 9.806 everywhere; lbf→N 4.4479; dt clamps: ramps 3.5 s, angles/axes 1.1 s.
* Stall shake/buffet: `FUN_005a7050` sets `S+0x1a8/0x1ac = 0.5` while the vibration flag is set.
* Over-G: `OverGThresh` (getter id 27) is compared with the current G in the player controller
  (@448683). Above it, the "Over G" Betty voice plays every 4 s. No over-G damage exists. See §13.
* Ceiling/Vmin extras: `P+0x14c` (Vmin 1 g @10 km) used by AI only (UNCERTAIN).

## 10. Deviations in our port (`crates/iaf-flight`)
* **1 g hold** (§4.2): uses the flight-path angle γ instead of the nose pitch and subtracts the thrust's
  vertical share: `g = cos γ / cos φ − T·sin α /(m·g)`. With the original formula the jet slowly dives at high
  speed (α goes negative there, tilting thrust downward).
* **Envelope** (§3): linear interpolation within/between g-graphs instead of the 3-point plane fit.
* Not yet ported: AB light-up delay, departure/spin modes (§6 other modes), engine damage flags, stores drag.
* Validation against public F-16 data: `cargo test --release -p iaf-flight --test validation -- --nocapture`.

## 11. Data sets (`crates/iaf-flight/src/data_set.rs`) — chosen before the flight
* **Original**: the 1998 numbers as shipped.
* **Real** (F-16 only so far): empty 19,000 lb; thrust table ×1.5 (F110-GE-100, ~17.4k/29k lbf SL);
  1 g stall floor 118 kt (Vmin ≥ 118·√g·√(ρ0/ρ) kt → ~355 kt corner); roll 280 deg/s with 900 deg/s²
  start/stop (FLCS ~0.3 s time constant; the original's 170 deg/s² stop overshoots ~1 s); fuel flow
  16.5 lb/s at full AB (~60k lb/h, ~11k lb/h military); transonic wave drag ΔCD 0 → 0.02 over Mach 0.9–1.2.
* In-game: `--real` launch option (pre-flight menu later).

## 12. Gear lever rules (player controller `FUN_004493a0`, case GEV 0xe)
Generic for every aircraft (no per-type data involved).

**Key → event chain.** Key bindings live in a runtime table at `0x836e14` (stride 0x24: press cmd,
press lParam, release cmd/lParam, key code `ushort`+modifier at +0x18; defaults at `0x647ff8`, see §7; keys.trx
only supplies the display names). `FUN_004df3d0` sends `WM 0x532, wParam = GEV code` → handler
`0x4e1c20` (MFC map entry @`0x601918`; codes 0x7d–0x89 are UI, all others fall to `0x4e1f45`) →
`FUN_005bc4a0` (ManageUnit log) → `FUN_004ccb80` queues a `SimGameEventNode` → the player controller
`FUN_004493a0(this=ctl, gev, int *arg, int forced)`. (UNCERTAIN: the queue→`FUN_004493a0` hop was not
traced. It is inferred from the matching case codes: GEV 5/6 INC/DEC_THROTTLE → motion 3/4, 10 RUDDER → 5,
0xc FLAPS → 6, 0xe LANDING_GEAR → 7.) Motion inputs are built by `FUN_0044de50(buf,type,arg)` (+0 type,
+8 sim time, +0x18 `arg[0]`) and posted through `(*(unit+0x38))->vtbl[0]`. That lands in the FM's
slot 9 (`0x59c4f0`, vtable `0x60df00`).

**Controller state** (all offsets relative to `ctl`): the handle is `ind[9]` at `ctl+0x4e0+0xc+9*4` (1 = down, 0 = up).
The per-leg lights are `leg[i]` at `ctl+0x53c+0xc+i*4`, i=0..2 (0 = up, 1 = in transit, 2 = down and locked).
The damage flags are at `ctl+0x3d8+0xc+n*4` (n = 7 is gear, 4 is flaps).

**GEV 0xe, keyboard toggle (`forced`=0), @44c2a4:**
1. If the aircraft is simulated locally (`!netgame(0x82a9d0) || unit->local`) and `ctl+0x19c`≠0 or
   `ctl+0x1a0`≠0, the command is ignored. (UNCERTAIN: these are weapon-release and gun-burst in progress, set by `FUN_00457340`.)
2. **Ground lock:** if `ind[9]`≠0 (gear down) and FM getter 0x1a ≠ 0 → **return, silently**.
   Getter 0x1a (`0x5a64b0` case 0x1a @5a6f8a) is `(float)S+0x2a0`, the on-ground/ground-roll flag (§7).
   Nothing else is checked here: no weight-on-wheels, speed, or altitude test. No message, no sound, no
   backseat voice, and the handle stays put. Lowering the gear on the ground is never blocked by this test.
3. The three legs are tried with `FUN_0044ee10(old=ind[9], leg, forced)` @44ee10:
   * gear damaged (flag 7) → the leg does not move;
   * **up→down:** blocked if `min(|v|,1200)·1.9427955 > 300` (TAS > 300 kt; getter 5 = FM slot 0x3c).
     Otherwise, if `leg`=0, it starts extending (`FUN_0045a670`: 0→1, and →2 after 2.0 s);
   * **down→up:** no speed limit. A leg starts retracting only when `leg`=2 (`FUN_0045a640`: 2→1, →0 after 2.0 s).
   If **no** leg can move, the command is ignored silently (locally simulated aircraft).
4. The handle toggles: `ind[9]` = 0 (`FUN_0045a9b0`) or 1 (`FUN_0045a920`). Motion input 7 is sent with
   +0x18 = the new `ind[9]`, and for the player's own aircraft `SFX_LANDING_GEAR` (sound 0x1e, `FUN_0044efb0`) plays.
5. FM `FUN_0059d170`: +0x18≠0 ramps `S+0x320` to its min `S+0x334` (0 = extended). +0x18=0 ramps it to its max `S+0x338`.
   (Airborne init `FUN_005a2a10` sets 1.569 ≈ π/2 = retracted, rate `S+0x330` = 0.5/s → ~3.1 s. Ground init sets 0.)
   Ramp layout: +0 t0, +8 start, +0xc target, +0x10 rate, +0x14 min, +0x18 max, +0x1c duration.
With `forced`≠0 (explicit set, `arg[0]` = wanted state, probably network/replay; UNCERTAIN), the command is ignored
if the state is already equal, and steps 1–2 are skipped.

**Related:**
* Gear damage: `FUN_0044ca90(7)` comes from combat damage only. It shows "Gear damage" (for the player) and sets
  the leg lights to 1. No overspeed-with-gear-down damage was found (UNCERTAIN: not searched exhaustively).
* Touchdown check `FUN_005b85b0`: if the gear ramp is ≥1e-5 (not fully down), the three landing tolerances are
  multiplied by 0.2/0.2/0.25 (and ×2 in easy mode). The ground roll uses μ=20 for a belly landing (§7).
* ATC text `ACFT_GEARS_NOT_OPEN` (`FUN_0054faa0` case 10). The `BACKSEAT_GEAR_UP/DOWN` voices (category 0x36,
  ids 10/0xd) are defined in soundprop.txt, but no code that plays them was found.
* Other locks in the same controller: GEV 0x10 autopilot, when on the ground (getter 0x1a≠0), always goes to off
  (@44c548). GEV 0x11 brakes plays `SFX_SPEED_BREAKES_LOOP` (0x1c) only when airborne (@44bf1e).
  GEV 0x42 (UNCERTAIN: gun fire) is refused while `ind[9]`≠0 unless `ctl+0x970`≠0 (@44a7e4).
  GEV 0xc flaps is refused while flaps are damaged (flag 4).

## 13. Blackout / redout (G effects on the pilot)
Generic for every aircraft: the rule uses no per-aircraft data except `OverGThresh` (warning only).

**Summary.** The original **has** a blackout and a redout. It is purely visual: a full-screen overlay
plus a shrinking "tunnel" for blackout, and a flat red overlay for redout. No code was found that
removes control, changes stick input or damages the aircraft from G. There are no strings "blackout",
"redout" or "G-LOC" in the exe. The only user-visible name is the Gameplay preference **"NO BLACKOUTS"**,
which is baked into the art `resource/menu/bmp/pref/gamep_*.bmp` (column "PLAYER SKILLS").

### 13.1 G value
Getter id 0 of `FUN_005a64b0` (case @5a6567) returns
`G = L(t) / m / 9.806` with `L` = the lift ramp `S+0x1e0` (§4), `m = EmptyWeight + S+0x424 + fuel(S+0x430)`
and the factor `0.10197838` (@60dde0). This is the load factor: ≈1 in level flight and negative under a
push. `FUN_0044f050(ctl, float *G, int *enable)` reads it for the player controller (`DAT_00694948`).

### 13.2 Gating (`FUN_004da690`, called every frame from the sim render `FUN_004d7960`)
1. If `DAT_00836db0` ≠ 0, the function returns and nothing is integrated or drawn. `DAT_00836db0` is
   the menu-side copy of "No blackouts": pref object `0x836c88`+0x128, loaded from `prefs.dat` by
   `FUN_004eefb0` and copied to the pref instance `DAT_00694a64`+0x30 by `FUN_004fcb80`. The default is 0
   (blackouts on; `FUN_00450790` sets `[0xc]=0`).
2. `FUN_0044f050` sets `enable = 1` only if the controller's unit is the player object (`DAT_00694960`,
   ids at +0x30 compared) and `[unit+0x1c]+0x14 == 3` (UNCERTAIN: meaning of state 3; the same test gates
   cockpit sounds in `FUN_0044efb0`). `enable` is also cleared when pref+0x30 ≠ 0, except in
   multiplayer (`DAT_00694990 && [DAT_00694990+4]`), where the pref is ignored. Step 1 is not
   overridden in multiplayer, so a local "No blackouts" still disables the effect. (UNCERTAIN: this
   looks like an intended MP override that has no effect.)
3. `FUN_00402260(G, enable)` → TgenAPI vtable slot 0x7c (`0x405180`, real 16-bit renderer vtable
   `0x5f9908`) → `FUN_00403870` → **`FUN_0041a100(this=[0x774908], G, enable)`**. If that returns 1,
   `FUN_0041a7b0([0x7748f0])` is called, and `FUN_004da690` sets `[param+0x154]+0x300 = 1` (UNCERTAIN:
   a redraw/dirty flag).
4. `FUN_0041a100` returns immediately (no integration) when `DAT_007ccf90` = 0. That flag is set to 1 at
   @40b105 when the Direct3D device descriptor `0x7cd148` is present, and 0 otherwise. (UNCERTAIN: 1 =
   hardware D3D device. With a software device there is no blackout at all.)

### 13.3 Accumulators (`FUN_0041a100` @41a100, disassembly; constants read from .rdata)
There are two floats in the Tgen effect object: blackout `B` at +0xc0 and redout `R` at +0xc4. `dt` is
`DAT_007ccfb0`, the frame time in seconds: `(tick − lastTick)·0.001`, and if it is > 200 it is replaced
by 0.001 (@40bc40). They integrate every frame, **even when `enable` = 0** (drawing is skipped then).
```
B += G·dt·0.43        ; if B > 24  → B = 24          // 5fb468, 5fb46c
R += G·dt·0.20        ; if R > 0   → R = 0           // 5fb470
                        if R < −3  → R = −3          // 5fb474
B -= dt·2.5           ; if B < 0   → B = 0           // 5fb478
if R < 0: R += dt·0.25; if R > 0   → R = 0           // 5fb47c
b = (B − 15)·0.125                                   // 5fb480, 5fb484   (range −1.875..1.125)
r = R < 0 ? (R + 1)·0.5 : 0                          // 5fb488, 5fb48c   (range −1..0.5)
if !enable: return 0
```
The net rates are `dB/dt = 0.43·G − 2.5` and `dR/dt = 0.2·G + 0.25` (while R < 0):
* **Blackout** builds above **G > 5.81 g** (2.5/0.43). It becomes visible at B ≥ 15.08 (b ≥ 0.01) and
  fully black at B > 22.6 (b > 0.95). Starting from B = 0: at 9 g, visible after 11.0 s and black
  after 16.5 s; at 7 g, visible after 29.6 s. Recovery at 1 g is −2.07/s (from 24 to below 15.08 in
  4.3 s). Negative G drains B faster.
* **Redout** starts only below **G < −1.25 g**. It becomes visible at R < −1.008 and is at full
  strength at R = −3. At −3 g, R reaches −1 after 2.9 s and −3 after 8.6 s. Recovery at +1 g is
  +0.45/s (from −3 to −1 in 4.4 s). Positive G drains R faster.
* Blackout has priority: the redout branch runs only when b < 0.01.

### 13.4 Drawing (Direct3D, IDirect3DDevice2 `DAT_007cd518`)
Each branch first calls `SetCurrentViewport(DAT_007cd520)` (slot 0x34) and ends with
`SetCurrentViewport(DAT_007cd51c)`. (UNCERTAIN: a full-screen viewport, then the normal one.)
`FUN_00419d60(rect 0x7cd020, r, g, b, a, 0)` draws a 4-vertex TLVERTEX fan over the rect with the
colour `ARGB(a, r, g, b)` (colour built @419f7a).
* **Redout** (b < 0.01 and r ≤ 0.01): `a = trunc(−255·r)`, clamped to ≤ 255. If a < 1 nothing is
  drawn. Otherwise a flat **dark-red** overlay `ARGB(a, 0x7f, 0, 0)` is drawn. There is no tunnel.
  (@41a2c1)
* **Blackout, b > 0.95:** an opaque black overlay `ARGB(255, 0, 0, 0)` (@41a356).
* **Blackout, 0.01 ≤ b ≤ 0.95** (tunnel vision, @41a370):
  1. `a = min(trunc(275·b), 275)` (5fb49c). A full-screen black overlay with alpha `min(a, 255)` is drawn.
  2. The render states are set: TEXTUREHANDLE 0, ZENABLE 0, ZWRITEENABLE 0, FILLMODE 3.
  3. Rings: the centre is (W/2, H/2), where W, H = `DAT_007cd028/02c` are the render size in pixels.
     Ring 0 is an annulus from outer radius `W` to inner radius
     `rin = (1 − 2·(b − 0.5))·W = (2 − 2b)·W` (0.1·W at b = 0.95, ≈W at b = 0.5). Both edges are
     black with alpha `min(a, 255)`. Each next ring's outer radius is the previous inner radius, its
     inner radius is 3 px smaller (5fb4a0), and its alpha is 20 lower. There are at most 7 rings, and
     the loop stops when the next inner radius would be < 0. Each ring uses 24 points from the unit
     circle table at object +0x00..+0xbc (x, y pairs), which gives 48 TLVERTEX at +0xc8 (stride 0x20).
     It is drawn with `DrawIndexedPrimitive(TRIANGLESTRIP, TLVERTEX, …, 48, idx +0x6c8, 52, 1)`.
     (UNCERTAIN: the table and the index list are filled by a constructor that was not traced.)
     The result: the whole screen dims with `a`, and outside a circle of radius `rin` it is darker
     again, with a soft edge 18 px wide. The clear circle shrinks as B grows.
  * Quirk: the ring alpha `a − 20k` is clamped only above. For small `a`, negative values are written
    as `a<<24` and become a large wrapped alpha. A faithful port can clamp it to 0 (UNCERTAIN: whether
    this was visible in 1998).

### 13.5 Over-G warning and G sound (player controller per-frame update `FUN_00447f50`)
* @44867c: `if G > OverGThresh` (P+0x168, default 6.7 g, getter 27), then the repeat timer at `ctl+0x880`
  is polled (`FUN_004d3a00`: it fires when "now" is outside the last window and opens a new window of
  **4.0 s**; the period is `DAT_0082aa40` = 4.0, set by the load-time initialiser @446c50). When it
  fires and `ctl+0x8d8` = 0, it plays sound `0x2c009000` = `VOC_BBETTY`/`BTY_OVER_G`
  (`Cock_Bty_Over.wav`, soundprop.txt), and the handle is stored in `ctl+0x8d8`.
* @4486d2: `if G > 6.0` (hard-coded, @5fcc50), then the timer at `ctl+0x8a0` fires with period
  **17.0 s** (`DAT_0082a9e0`, initialiser @446c80) and plays `SFX_G_EFFECT` (code 0x13, `Cock_G_02.wav`).
  It is not gated by "No blackouts".
* `FUN_0044efb0` plays these only for the player's own aircraft (ctl+4 ∈ {2, 4, 5} and the same player
  object test as in §13.2).
* The G value is also written to the HUD (`FUN_00445920` → HUD `0x82aaec`+0x33c).
* **No over-G damage** was found. Getter 27 (`OverGThresh`) is used only at @44867c. The only uses
  of MaxG found are the FM's own lift limits (§4). (UNCERTAIN: other damage paths were not searched
  exhaustively.) The `BACKSEAT_HEAVY_BREATH` and
  `BACKSEAT_OH_YOU_KILLING_ME` voices (category 0x36, ids 1/2) are defined in soundprop.txt, but no code
  that plays them was found (no 0x3600x000 codes and no `FUN_00450690(0x36,…)`).

## 14. Port audit (ground roll and lift)

Source: `objdump -d -M intel` of `iafjets.exe`; stack arguments were mapped by tracking every push (the
Ghidra listing of these calls is shifted by one argument). Constants were read from `.rdata`/`.data`, and the
CRT initialiser table `0x6236f0..0x623740` was checked for load-time writes. In this section `sY` = stick Y
`S+0x2e4` (+ = pull), `sX` = stick X `S+0x2e8`, `W = m·9.806`, and `c_f = FlapsLiftCoef·flaps·3.4158838`.

### 14.1 Call graph and argument mapping
* `5a42e0` (aero update, 1 Hz + every control event) → `5b0a20(33 args)`. Arg 6 = `S+0x2a0` (ground flag)
  and arg 7 = departure latch (`S+0x2f8` ≠ −1 and `now − S+0x2f8 ≤ 3.0`).
* Ground branch: `5b0a20` → `5b7a20(30 args)`. 7a20 arg k = b0a20 arg k for k ≤ 5, arg k+2 for 6 ≤ k ≤ 26, and
  arg k+3 for k ≥ 27. The latch (b0a20 arg 7) is dropped.
  7a20 args: 1 alt, 2 V=|v|, 5 &attitude(pitch,roll,heading), 6 engine on (`S+0x1d0`), 7 &cfg, 8 extra mass
  (`S+0x424`+fuel), 9 stores DI, 13 sY, 14 sX, 15 rudder (unused), 16 vehicle.
  Outputs: 19 nose-wheel yaw, 20 roll-rate cmd, 24 L, 25 dragX, 26 stall flag, 27 Lnoflap, 28 T, 29 D, 30 m.
* `cfg` (built in 5a42e0): `[0]` flaps (float, `S+0x300` ramp) and `[6]` = 1 only when the `S+0x360` ramp has
  finished at its maximum (speed brakes in the air, wheel brakes on the ground; int). `[7]` = (`S+0x2cc`==2)
  gear down, and `[8]` = hook.
* After b0a20, 5a42e0 sets `S+0x1d4`=T, `S+0x1dc`=D, `S+0x1d8`=m, ramp `S+0x1e0`→L and ramp `S+0x200`→Lnoflap
  (rates as §4). It passes the stall flag to `5a7050` (latch). It also calls the acceleration routine
  `5b0e20` (@5a4a17) with the lift ramp value sampled *before* the new target is set, and re-bases the X/Y/Z
  axes (@5a4e56–5a4f4a). **So every aero update and every control event also changes the acceleration at
  once**, not only the 5 Hz tick.
* On the ground, 5a42e0 skips the beta update `5a78f0`. Instead it ramps `S+0x2a8` toward the nose-wheel yaw
  (arg 19) at rate `S+0x2b8` = 10000/s (init @5b70d2, `0x60e164`), so the ramp is in effect instant.

### 14.2 `FUN_005b7a20` ground aero (ret 0x78)
```
ai   = FUN_005c58a0(veh+0xc50) != 0
team = see 5b0a20 (only used by Lift for AI)
mach, rho = atmos(alt, V);  qS = 0.5*rho*V²*WingArea            // 5b0f00, 5b1030
T    = Thrust(alt, mach, V, thr=arg12, engineOn, noAB = ai, flags=arg11, &rpm,&ff,&stage)
                    // NB: airborne passes noAB = !HasAfterBurner || (ai && mode∉{7,8}); ground passes ai
m    = EmptyWeight(P+0x8c) + arg8;   *out_m = m
L    = Lift(V, alt, mach, qS, m, sY, &att, cfg, latched=0, ai, team, &dragX, &stall, &dummyVib, &Lnoflap)
easy = pref+0x20 || pref+0x1c         (both forced 0 in multiplayer)
L    = 0.5*L;   L = L + |L|*c_f                              // @5b7bdd, 0x60e594=0.5, 0x60e598=−3.4158838
      // Lift() already added |L|*c_f when V<125, so on the ground flaps count TWICE:
      // L = 0.5*g*W*(1+c_f)²   (g>0, V<125)
if !((V > 74.53 || sY > 0.5) && (cfg[7] || ai || multiplayer || pref+0x3c || easy)):
      L = 0; Lnoflap = 0; stall = 0                          // @5b7c66
mu   = cfg[6]*WheelsBrakeDI*(ai ? 2 : 1) + fric1             // fric1 = DAT_0084083c, see below
if !cfg[7] && !ai && !easy: mu = 20.0                        // belly (replaces, not adds)
D    = Drag(V, alt, n = L/W, mach, qS, alpha = 0, cfg, storesDI, dragX, stall, ai, m)
     + 0.5*mu*(W − L)
D    = D > 0 ? D : 0;   if V > 1.0: D *= 0.7
T    = max(T, 0)
yaw  = clamp(sX*V*K/74.53, −K, K);  if !cfg[7]: yaw = 0;  if |yaw| < 1e-4: yaw = 0   // K = 0.3490659
out_rollRateCmd = 0
```
**Load-time initialiser (not in Ghidra):** `DAT_0084083c` = `fric1` is **not 0**. CRT table entry `0x623720`
→ `0x5b7710` → @5b7720 calls `FUN_004d3440("TAXI", "fric1", 0.25, 0)`, which reads `IAF.ibx`.
`install/iaf.ibx` `[TAXI] fric1=0.05`, so fric1 = 0.05, a rolling friction that is always on:
`0.5·0.05·(W − L)`. `fric2` (0.30, `0x840840`) is loaded the same way but never read.
Other TAXI keys (`DistFromGround` 0x840854, `GearSize` 0x840858, keys at 0x840860 and 0x84086c) are not used here.
Constants: 74.53 `0x60e568`, 0.5 `0x60e594`, 2.0 `0x60e580` (AI brake factor), 1.0 `0x60e59c`,
20.0 `0x60e584`, 9.806 `0x60e5a0`, 0.7 `0x60e5a4`, 0 `0x60e590`, 1e-4 (double) `0x60e5a8`.

### 14.3 `FUN_005b13a0` Lift (shared, ret 0x3c)
Args: V, alt, mach, qS, m, sY, &att, cfg, latched, ai, team, &dragX, &stall, &vib, &Lnoflap.
```
bStall = !ai ? (multiplayer || pref+0x38 == 0) : !(pref+0x50 == 2 && team)
if latched && bStall: dragX=1.2; Lnoflap=0; return 0                     // ground always passes latched=0
dragX = stall = vib = 0;  lim = 0
c = V < P+0x144 ? P+0x170*V + P+0x174 : 1
g = sY > 0 ? c + sY*(P+0xc8) : c + (−sY)*((P+0xcc + 1) − c)             // P+0xc8=MaxG−1, P+0xcc=MinG−1
g_cmd = g
if |g − 1| < 1e-5 && |att.roll| < P+0xdc(10°): g_cmd = g = cos(att.pitch)/cos(att.roll)
if UseFlightLimits(P+0x88):
   code = GLimit(alt, V, g, &lim)                                       // 5b2810, jump table 0x5b171c
   0: dragX=1.2; bStall ? (g=0, stall=1) : g=min(0.4, g_cmd)
   1: g = 0          (5b2810 never returns 1)
   2: dragX=1.2; bStall ? (g=0, stall=1) : g=0.4                        // flat 0.4, not min()
   3: g unchanged
   4: if g_cmd > 0:  r = g_cmd;  if lim <= g_cmd { dragX=(g_cmd−lim)/(P+0xc8+1); r=lim }
                     if !bStall { r = max(r, 0.4); if g_cmd < 0.4: r = g_cmd }
      else:          r = max(g_cmd, lim)
      g = r
if !multiplayer && pref+0x50==0 && ai && team && g > 4.3: g = 4 + 0.02*g²
Lnoflap = g*m*9.806
if lim <= StartVibsG(P+0x160) && code==4 && g_cmd > 0 && P+0x84 && !ai: vib = 1
L = Lnoflap;  if V < 125: L += |L|*c_f
return L
```
Inputs: sY (via the stick-centre line and MaxG/MinG), the attitude (1 g hold only), V and alt (stick-centre
line and envelope), m, flaps. **The inputs do not include the AoA or the α channel.** `mach` and `qS` are
passed but not read.

`GLimit` `FUN_005b2810(alt, V, g, &lim)`: `k = max(0, ftol(alt/step))`. Use the g>0 list `E+0x44` (count
`E+0x48`) if g > 0, else the g≤0 list `E+0x58` (count `E+0x5c`).
* `k+1 > count−1` → code 2, lim = −1.
* `a = 5b3330(list[k], V)` and `b = 5b3330(list[k+1], V)` (>0 means V is above all points, <0 below all,
  0 bracketed).
* `a > 0`: if `Ceiling(g) ≥ alt` → code 3 (lim = g), else code 4 with `lim = 5b2770(g, alt)`.
* `a ≤ 0`: if `b < 0` or `a < 0` → code 0 (lim = −1). Otherwise code 4 with lim = plane fit `5b2a90`,
  forced to 0 if g > 0 and lim < 0, or if g < 0 and lim > 0.

### 14.4 `FUN_005b1730` Drag (ret 0x30) and `FUN_005b1050` Thrust (ret 0x28)
```
Drag(V, alt, n, mach, qS, alpha, cfg, storesDI, dragX, stall, ai, m):     // dragX, stall unused
  CD = PlaneDI + cfg[6]*SpeedBrakesDI + cfg[8]*HookDI + cfg[7]*GearDI*(ai ? 0 : 1)
       + FlapsDI*cfg[0]*3.4158838 + storesDI + K*CL²
  CL = qS > 0 ? cos(alpha)*m*n*9.806/qS : 0;   K = 1/(π*Span²/Area*0.85)
  return CD*qS
```
On the ground `cfg[6]` (wheel brakes) therefore also adds **SpeedBrakesDI** to the aerodynamic drag.
`Thrust` matches §4.1: a = clamp(alt·5e-5, 0, 1), M = clamp(mach·0.8333, 0, 1), `noAB` = arg 6. `noAB`:
`k=(thr−0.2)·1.25`, and the stage still follows thr (0.75/0.875). rpm = 0.6+0.4·thr·1.3513514 (0 when off).
ff = thr·FFmax, ×0.25 if k ≤ 0.6. The result ×4.4479 is not clamped here; only 7a20 clamps T ≥ 0.

### 14.5 Ground acceleration `FUN_005b7e40` (via `5b0e20` → `5b1860` when ground)
`5b0e20` forces pitch = roll = 0 on the ground, so `M = 5b7580(0, 0, heading)`.
`yaw` is `S+0x2a8` in the 5 Hz update (5b87d0 writes it into the beta slot) and arg 19 in the aero update.
```
R  = yaw == 0 ? 5.0 : V/(9.806*tan(yaw));   if |R| < 2: R = 2*sign(R)
Fc = (V > 2 && yaw != 0) ? V²*m/R : 0           // = V*m*9.806*tan(yaw)
f  = V < 25.736 ? 1.0 : |0.1 − 0.000777118*V|;  Fc *= f
Lz = L_ramp(t)                                    // S+0x1e0 sample, not the new target
if |Fc| > 0.1*Lz && V > 20.5889: Lz *= 4          // @5b7f37, 0x60e5cc=0.1, 0x60e5d4=4.0
Fx = (V < 0.01 && T < D) ? 0 : T − D − |Fc|*0.0625
F_body = (x = Fc, y = Fx, z = Lz);  Fw = 5b74d0(M, F_body)   // (-r1, r0, r2) as §5
Fw.z = max(Fw.z − m*9.806, 0);  acc = Fw/m;  acc_body = 5b7440(M, acc)
```
Constants: 5.0 (imm 0x40a00000), 2.0 `0x60e5b8`, 25.736 `0x60e5c4`, 0.000777118 `0x60e5c8`,
20.5889 `0x60e5d0`, 0.01 `0x60e5d8`, 0.0625 `0x60e5e0` (double), −9.806 `0x60e5e8`.
The heading is not integrated anywhere. The lateral force turns the velocity, and the attitude (mode object,
§6) takes its heading from the velocity.

**Stop rule** (5 Hz `5a15e0` only, @5a1a07–5a1b8e, ground only): `v_b = 5b7440(M(0,0,heading), velocity)`.
If `acc_body.y < 0` and `v_b.y + 0.2·acc_body.y < 0` (0x60dd30 = −0.2), then set `acc_body.y = 0`, recompute
the world acceleration, and re-base **all three axes with v = 0** (position kept). The 1 Hz/event path (5a42e0)
has no stop rule (UNCERTAIN: so between two 5 Hz ticks a large deceleration set by an event could briefly
reverse the velocity).

### 14.6 Air ↔ ground transitions — `FUN_005b87d0(now, &speed, &Z, &beta)`
This function is called at the start of every 5 Hz tick (`5a15e0` @5a16fd) and nowhere per frame.
`clear` = terrain(X,Y) (`402030`) + |model height| (`463310`). The Z axis limits are fixed at
[−1500, 30000] (@5b6d6a), so nothing else clamps altitude.
```
if S+0x2a0 == 0:                                     // airborne
   if Z > clear: *beta = S+0x280 ramp sample; return
   // touchdown (@5b8b14)
   S+0x2a0 = 1
   if 5b85b0(τ, vz) (landing/crash check, UNCERTAIN): event 4a8280(…,5,…)
   Z axis := (p = Z(τ), v = 0, a = unchanged a_z);  if clear in [−1500,30000]: p0 = clear, t0 = now
   *Z = clear;  5a42e0(now)                          // aero update now runs the ground branch
   non-runway / water / gear-up side effects (S+0x2c8 = 2 or 4, sounds, 441000)   (UNCERTAIN)
if *Z > clear && vz > 0.001:                          // lift-off (@5b8d6c)
   S+0x2a0 = 0;  5a42e0(now)                          // airborne branch, full lift, latch honoured
   roll channel S+0x80 := (pos = 0, rate = current rate, targetRate = S+0x90)
   *Z = Z sample, *speed = vtable+0x3c, *beta = S+0x280 sample;  S+0x2c8 = 0;  return
// still on ground
*beta = S+0x2a8 ramp sample (nose-wheel yaw); re-base S+0x2a8; crash checks for flags/speed > 25.736
```
* Touchdown: only vz is set to 0; the horizontal velocity, including any sideways part, is kept.
  Lift-off: the velocity is unchanged, and only the roll angle is reset to 0 (its rate is kept).
  There is no hysteresis: the jet lifts off as soon as the ground-mode vertical acceleration
  `max(L' − W, 0)/m` has raised Z above `clear` with vz > 0.001 at a 5 Hz tick.
* Velocity reversal: on the ground it is prevented by the stop rule, apart from the 1 Hz/event gap noted above.
  In the air nothing prevents it. The heading always follows the velocity, so a reversed velocity would show
  as a 180° heading flip.
* Stall latch on the ground: Lift can return code 0 on the ground (for example sY > 0.5 below the g=0
  Vmin). Then `stall = 1` and `5a7050` sets `S+0x2f8` even on the ground. The ground branch ignores the
  latch, but the first airborne updates within 3 s get L = 0.
* `5b1b90` (alpha target) returns 0 on the ground.

### 14.7 Worked example (the bug report: F-16, V = 65.3 m/s = 127 kt, sea level, full aft, gear down, flaps up)
Original: g_cmd ≈ 8.7 (stick-centre shift). GLimit gives code 4 with lim ≈ 1.65 (Vmin: 1 g = 86 kt,
2 g = 148 kt). So g = 1.65 and L = 0.5·1.65·W ≈ 0.83 W. n = 0.83 and CL ≈ 1.17, so D ≈ (0.072 + 0.143)·qS
≈ 15.6 kN, plus friction 0.43 kN, ×0.7 ≈ 11 kN. With T ≈ 86 kN the jet keeps accelerating and stays on the
ground. Exception: nose-wheel steering. At this speed any sX gives |Fc| > 0.1·L, which multiplies the
vertical lift by 4, and the jet lifts off.
Port: g ≈ 8.7 with no envelope, so L = 4.33 W and n = 4.33, CL ≈ 6. Induced drag ≈ 280 kN (×0.7 ≈ 200 kN)
exceeds the thrust, and az = 3.3 g. The jet decelerates hard and is thrown into the air. At 25 kt the original
would give L = 0 (code 0, below 46 kt), but the port still gives 4.5 W.

### 14.8 Mismatches, most important first (our file `crates/iaf-flight/src/aircraft.rs`)
1. **Envelope skipped on the ground** (l. 429, `&& !self.on_ground`). Original: Lift runs GLimit on the ground
   too (latched=0), so g ≤ lim(alt,V), and below Vmin(g=0) it gives g = 0 plus the stall flag. This is the
   direct cause of the report (4.3–4.5 W of lift and matching induced drag at 25–127 kt).
2. **Departure latch applied on the ground** (l. 411–413). Original: the ground call passes latched = 0. The
   original also *sets* the latch from a code-0 result on the ground; the port never does (l. 429, 446).
3. **Flaps counted once on the ground** (l. 452–460). Original: `L = 0.5·Lift(); L += |L|·c_f`, and Lift has
   already added `|L|·c_f` when V < 125. The ground lift is `0.5·g·W·(1+c_f)²`.
4. **Rolling friction fric1 = 0.05 missing** (l. 477). Original: `mu = brakeFlag·WheelsBrakeDI·(ai?2:1) + 0.05`
   (IAF.ibx `[TAXI] fric1`, load-time initialiser). The port has mu = 0 without brakes. The doc's §7 claim
   "DAT_0084083c = 0" is wrong.
5. **Ground acceleration model** (`ground_roll_update` l. 568–588, `steer` l. 278–305):
   * The port snaps the velocity to `ground_dir` and rotates `ground_dir` kinematically at the nose-wheel
     rate, every frame. Original: a lateral force `Fc = V·m·g·tan(yaw)·f` (f = 1 below 25.7 m/s, else
     |0.1 − 0.000777·V|, R ≥ 2 m) turns the velocity at 5 Hz/events, and the heading follows the velocity.
   * The port omits the scrub `Fx −= |Fc|/16` and the rule `L_vertical ×4 when |Fc| > 0.1·L && V > 20.59`.
   * The port's stop rule is `along < 0.05 && a < 0 → v=a=0` along the direction. Original:
     `Fx = 0 if V < 0.01 && T < D`, plus the 5 Hz rule `a_fwd < 0 && v_fwd + 0.2·a_fwd < 0` → all three
     velocities = 0 and a_fwd = 0.
   * The port's steering speed is `dot(v, ground_dir)`. Original: |v|.
6. **Transitions** (`ground_contact` l. 590–612, `step` l. 268–271). The port checks per frame. Original:
   once per 5 Hz tick, before the forces are computed.
   * Lift-off: the port uses `z > floor + 1.0` (an invented 1 m hysteresis). Original: `Z > clear && vz > 0.001`.
   * Touchdown: the original sets vz = 0 and keeps a_z. The port uses `vz.max(0)` and a_z = 0, and it re-clamps
     z and zeroes a_z every frame while z ≤ floor (l. 607).
   * Roll: the port resets the roll channel completely at touchdown (l. 602–603). Original: roll is untouched
     at touchdown, and at lift-off pos := 0 with the rate and target kept (the port does nothing at lift-off).
7. **Aero update does not re-base the acceleration** (l. 391–506 vs `5a42e0` @5a4a17/5a4e56). Original: every
   1 Hz update and every control event recomputes the acceleration (using the old lift-ramp sample and the
   new T/D) and re-bases the axes at once. The port waits for the next 5 Hz tick.
8. **Speed-brake drag excluded on the ground** (l. 475). Original: `cfg[6]` adds SpeedBrakesDI on the ground
   too, as well as the wheel friction. `cfg[6]` is the 0/1 "ramp finished at max" flag; the port uses the
   continuous ramp value (l. 467, 477).
9. **Ground drag uses α ≠ 0** (l. 463–465). Original: alpha = 0 in the ground Drag call, so CL = L/qS.
10. **Lnoflap not zeroed by the ground lift gate** (l. 457–458, 492). Original: the gate zeroes L,
    Lnoflap and the stall flag, so the `S+0x200` ramp also goes to 0.
11. **Alpha on the ground** (l. 520–533, 585). Original: alpha target = 0 (`5b1b90`), with normal dynamics.
    The port computes the target from lift_aoa and then snaps α to 0.
12. **Beta on the ground** (l. 503–505). Original: the beta ramp is not updated on the ground; `S+0x2a8`
    (nose-wheel yaw) is used instead.
13. **Thrust on the ground ignores HasAfterBurner** (l. 358). Original: the ground call passes `noAB = ai`,
    so a player jet without an afterburner gets the AB curve on the ground. Also for noAB the stage follows
    thr (the port gives 0). The airborne T is not clamped to ≥ 0 (l. 379 clamps both).
14. **Lift-gate conditions** (l. 457): the multiplayer, AI, pref+0x3c and "easy" bypasses of the gear test,
    and the "easy" bypass of the belly μ = 20 (l. 477), are not modelled.
15. **Lift for !bStall** (pref "stalls off"): code 2 → 0.4, code 4 → `max(r,0.4)` unless g_cmd < 0.4. Not
    modelled; the port assumes bStall.
16. **Buffet** (l. 442): the original tests `g_cmd > 0`, `P+0x84` and `!ai`. The port tests the clamped g.
17. **GLimit itself** (`envelope.rs` l. 141–174): bisection on vmin instead of the per-altitude-level point
    lists with a plane fit. The stall test (below the lowest point of level k or k+1) and code 2 (`k+1 >
    count−1`, i.e. from the list count, not ceiling + step) are approximated. This is already listed in §10.
18. **Invented terms**: `wave_drag` (l. 469–471) and the `nose_wheel` geometric steering (l. 285–291) are
    not in the original. They are active only with `DataSet::Real`.
