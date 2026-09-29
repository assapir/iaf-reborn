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
| OverGThresh | 0x168 | 6.7 | g | raw (only exposed via getter id 27 of `FUN_005a64b0`) |
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
T = max(T,0);  nose-wheel yaw rate = clamp(ru*V*DAT_00840864/74.53, ±DAT_00840864) (0 if gear up;
DAT_00840864 never written → UNCERTAIN)
```
The single "Brakes in/out" key drives ramp `S+0x360`, used as speed brake in the air and wheel brake
on the ground (UNCERTAIN mapping of events 7/8 = gear anim `S+0x320` / parachute `S+0x340`).

## 8. Controls / keys (dispatcher `FUN_0059c4f0`, event type → handler)
1 stick (`FUN_0059c740`): `S+0x2e4 = −clamp(y,−1,1)`, `S+0x2e8 = clamp(x,−1,1)`; ×0.25 when
input-mode 0x12 active, zeroed by 0x18 (UNCERTAIN meaning). 2 throttle (`FUN_0059cb60`): clamp
[0,1]; crossing into AB (≥0.75) from below sets 0.74 and schedules the AB value after
`max(0,(100−RPM%)·0.0667)` s (`FUN_0059cea0`); any throttle change turns the engine on (`S+0x1d0`).
3/4 RPM ±5 %: throttle ±0.0925 (`FUN_0059c6a0`/`c6e0`). 5 rudder (`S+0x2ec`, ramp ×0.3926).
6 flaps (`S+0x300`, ×0.33 target for aircraft type 100), 7/8/9 ramps `S+0x320/0x340/0x360`.
Throttle presets from keys.trx map naturally to RPM: idle 0, 65 % 0.0925, 70 % 0.185,
80 % 0.37, 90 % 0.555, military 0.74, AB1 [0.75,0.875), AB2 ≥0.875 (preset values themselves not
found; UNCERTAIN). Key names are loaded from `keys.trx` into `0x82eea8` (100-byte stride) by
`FUN_004e24d0`; the default key→command table was not located.

## 9. Misc
* g = 9.806 everywhere; lbf→N 4.4479; dt clamps: ramps 3.5 s, angles/axes 1.1 s.
* Stall shake/buffet: `FUN_005a7050` sets `S+0x1a8/0x1ac = 0.5` while the vibration flag is set.
* Over-G: `OverGThresh` only exported (getter id 27, `FUN_005a64b0`); comparison site not found
  (UNCERTAIN: warn when current G = L/(m·g) > OverGThresh).
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
