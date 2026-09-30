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
    Angles are reduced with `fmod(x, 2π)` (`FUN_0056653a` = `_CIfmod`, divisor `DAT_00840880` = 2π), i.e. to
    (−2π, 2π), not to (−π, π] (corrected, §15). Only the angle-difference helper `5ba9b0` wraps to (−π, π].
  * **Kinematic axis** (type C, 0x20 bytes: `p0, t0:f64, v, a, min, max`), `FUN_005aab30/aab50`:
    `τ=clamp(t-t0,0,1.1)`, `p = p0 + v·τ + ½a·τ²` (clamped `[min,max]`), velocity `v + a·τ`.
    Three of them: `S+0x20` X (east), `S+0x40` Y (north), `S+0x60` Z (up, altitude).
* Updates (timers created in `FUN_005a2a10` @005a2a10, the (re)initialiser):
  * **UpdateAeroData** – every **1.0 s** (`FUN_005a15b0` → `FUN_005a42e0` @005a42e0) and also
    immediately on every control event (stick, throttle, rudder, flaps …, dispatcher
    `FUN_0059c4f0`). Recomputes thrust, drag, mass, lift *targets*, roll-rate target, fuel flow, the α and β
    targets, and also the acceleration (axes re-based at once, §14.1/§15.1).
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
Graphs are indexed by **integer g** (index = g + idx0, idx0 = graph index of g=0; ≤14 rows each incl. the sentinel, not
bounds-checked; a new graph starts at every *change* of g in file order);
a sentinel row (alt 30000 **m**, last vel) is appended; `ceilAlt[g]` = alt of last real row;
pad graphs below min g / above max g copy the edge graph with max(alt−1, 0), vel+1. `gmin = min(0, all g)`, `gmax` = last g.
Exact algorithm (all functions, edge cases, F-16 check): §15.9.

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
  negative), clamped at 0 (confirmed, §15.9). If V below all points of level k **or** k+1 → code 0
  (stall). Otherwise code 4 with `lim` = plane through `(L_k,Vlo,glo)`, `(L_k,Vhi,ghi)`,
  `(L_{k+1},V',g')` evaluated at `(alt,V)`; forced to 0 if its sign differs from gcmd.

## 4. Aero update (1 Hz + events): `FUN_005b0a20` @005b0a20 (airborne) / `FUN_005b7a20` (on ground)
Inputs: `alt=Z`, `V=|v|` (not capped in the 1 Hz path; the 5 Hz path uses the capped `5a3a90`), throttle `thr=S+0x2dc`, stick pitch
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
(no lower clamp). Before the new target is set the roll channel is re-based with `pos := attitude roll`.
Alpha dynamics via `FUN_005a7590` (§5), beta via `FUN_005a78f0` (§5). The `cfg` flags and the exact order of all
steps are in §15.1 (the brake flag comes from ramp `S+0x340`, the gear flag from the gear ramp `S+0x320` at 0).

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
config ints (corrected in §15.1): `sb=[6]` brakes (`S+0x340` ramp: in the air finished at max, on the ground any
value ≥ 1e-5), `gear=[7]` (gear ramp `S+0x320` fully extended, `|x| < 1e-5`), `hook=[8]` (`S+0x360` ramp finished at
max); `flaps=[0]` (float, `S+0x300` ramp). `[9]` = (`S+0x2cc==2`) is not read by Drag.
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
Fbody (y fwd, z up, x = right wing) with α = **αT** (the target above, not the α channel) and β = S+0x280(t)
in the 5 Hz path; the 1 Hz/event path uses α = S+0x220(t) and β = the commanded β_cmd (§15.2.2):
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
`V≥375 ? BetaRate : max(BetaRate·0.0025·V, 0.25·BetaRate)`, limits ±MaxBeta. The "yaw-coupling" globals
`DAT_008407c8..d0` are (0,0,1), written by the CRT initialiser `0x6236a8 → 5a02c0` (the old note "never written"
was wrong), but the term only feeds the ramp `S+0x260`, which is a HUD value (getter 8) with no effect on the flight
path (§15.2.6). `5a78f0` also runs at 5 Hz, on the ground too.

## 6. Attitude (render/orientation) — mode object `veh+0xc6c`, vtable `0x60dee8`: `5b4580`/`5b4840`
Normal mode: sample v(t) (type C velocities), roll φ(t) (S+0x80), α(t), β(t); then
```
f = v/|v|;  w = S+0x08 (LEFT-wing vector saved at the last 1 Hz or 5 Hz update, with φ_ref = S+0x18)
w = rotate(w, axis f, φ - φ_ref)            // Rodrigues (FUN_00461930/467d50/466580)
f = rotate(f, axis w, -α)                   // nose above velocity
f = rotate(f, axis w×f, β)                  // (was written f×w here; the code builds w×f explicitly @5b4b8c)
heading = atan2(f.x, f.y);  pitch = asin(f.z);  roll = ±acos(clamp(−w_local.x,−1,1)) (sign by w_local.z)
```
Exact version with the frames and helpers: §15.3.
`FUN_005a7520(pitch,roll,heading,S)` stores the Euler angles at S+0x14 and `w = Mᵀ·(−1,0,0)`
mapping at S+0x08. Other modes (`veh+0xc70` → `FUN_005a7d50`, `veh+0xc7c` → `FUN_005a96c0`) are
special departure/spin/tail-slide manoeuvres — see §15.5.
Airborne init (`FUN_005a2a10`): `v = (V sinψ, V cosψ, vz)`, throttle 0.74, engine on; full rules (air/ground
decision, gear, flaps, brakes, RPM, lift ramps) in §15.6. The re-placement `FUN_005a2000` uses throttle 0.7.

## 7. Ground roll — `FUN_005b7a20` (replaces §4 while `S+0x2a0`≠0)
```
easy = pref+0x1c || pref+0x20   (DAT_00694a64: Invulnerable || No crashes, §15.7)
L = 0.5*Lift(...);  L += |L|*FlapsLiftCoef*flaps*3.4158838
if !((V > 74.53 || sp > 0.5) && (gearDown || AI || pref+0x3c || easy)): L = 0
mu = brakes[6] * WheelsBrakeDI * (AI ? 2 : 1) + DAT_0084083c(=0, never written)
if !gearDown && !AI && !easy: mu = 20                      // belly landing
D = Drag(alpha=0, n=L/(m g)) + 0.5*mu*(m*9.806 - L);  D = max(D,0);  if V > 1: D *= 0.7
T = max(T,0);  nose-wheel yaw rate = clamp(sx*V*K/74.53, ±K), K = DAT_00840864 = 20°/s = 0.3490659 rad/s
(0 if gear up; 0 if |rate| < 1e-4).  sx = stick X S+0x2e8, NOT the rudder (see "Nose-wheel steering input")
```
The single "Brakes in/out" key drives ramp `S+0x340` (motion 8, `FUN_0059d370`, range 0..0.855, 0.5/s), used as
speed brake in the air and wheel brake on the ground. Motion 7 = gear `S+0x320`, motion 9 = `S+0x360` (→ HookDI,
UNCERTAIN: hook). The earlier "S+0x360 = brakes" was wrong (§15.1). The nose-wheel yaw is not instant: it goes
through ramp `S+0x2a8` at rate |BetaRate| and is clamped to ±MaxBeta (§15.2.6).

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
* Stall shake/buffet: `FUN_005a7050` sets `S+0x1a8/0x1ac = 0.5` while the vibration flag is set (only if
  `veh+0xc60 == 0`), and starts/stops the force-feedback effect "StallShake" with the stall latch (§15.2.4).
* Over-G: `OverGThresh` (getter id 27) is compared with the current G in the player controller
  (@448683). Above it, the "Over G" Betty voice plays every 4 s. No over-G damage exists. See §13.
* Ceiling/Vmin extras: `P+0x14c` (Vmin 1 g @10 km) used by AI only (UNCERTAIN).

## 10. Deviations in our port (`crates/iaf-flight`)
* **1 g hold** (§4.2): original formula `cos(pitch)/cos(roll)` by default. With it the jet slowly dives at high
  speed (α goes negative there, tilting thrust downward). The **"Better physics"** option (Preferences, user
  decision) holds the flight-path angle γ instead and subtracts the thrust's vertical share:
  `g = cos γ / cos φ − T·sin α /(m·g)`.
* **Envelope** (§3): linear interpolation within/between g-graphs instead of the 3-point plane fit.
* Not yet ported: AB light-up delay, departure/spin modes, landing/crash check, preference gates, engine damage
  flags, stores drag. Full list with fixes: §15.10; exact envelope algorithm: §15.9.
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
  multiplied by 0.2/0.2/0.25 (and ×2 with the "Easy landing" preference `pref+0x3c`, default on, or in multiplayer; §15.6). The ground roll uses μ=20 for a belly landing (§7).
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
* `cfg` (built in 5a42e0) — **corrected in §15.1**: `[0]` flaps (float, `S+0x300` ramp); `[6]` brakes from ramp
  `S+0x340` (in the air: finished at its maximum; on the ground: any sample ≥ 1e-5); `[7]` gear = gear ramp
  `S+0x320` fully extended (`|x| < 1e-5`); `[8]` = `S+0x360` finished at max (hook). (`S+0x2cc`==2 is `[9]`, unused.)
* After b0a20, 5a42e0 sets `S+0x1d4`=T, `S+0x1dc`=D, `S+0x1d8`=m, ramp `S+0x1e0`→L and ramp `S+0x200`→Lnoflap
  (rates as §4). It passes the stall flag to `5a7050` (latch). It also calls the acceleration routine
  `5b0e20` (@5a4a17) with the lift ramp value sampled *before* the new target is set, and re-bases the X/Y/Z
  axes (@5a4e56–5a4f4a). **So every aero update and every control event also changes the acceleration at
  once**, not only the 5 Hz tick.
* On the ground, 5a42e0 skips the beta update `5a78f0`. Instead it ramps `S+0x2a8` toward the nose-wheel yaw
  (arg 19) at rate `S+0x2b8`. **Correction:** the constructor's 10000/s (@5b70d2) is overwritten by `5aef10` at
  SetType and by the placement inits with `|BetaRate|`, and the ramp is clamped to ±MaxBeta (F-16: 32°/s², ±15°/s,
  below K = 20°/s). The 5 Hz force uses the ramp sample; the 1 Hz/event force uses the raw target (arg 19). §15.2.6.

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
   non-runway / water / gear-up side effects (S+0x2c8 = 2 or 4, force-feedback effects + SFX, 441000) — §15.6
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

## 15. Port audit (airborne branch and modes)

Source and method as in §14: `objdump -d -M intel` of `iafjets.exe`, stack arguments mapped by tracking the pushes
(Ghidra's argument lists of these calls are shifted by one), constants read from `.rdata`/`.data`, and the whole CRT
initialiser table checked for load-time writes. **The CRT table is `0x623004..0x623890`** (547 entries); the FM part is
`0x623694..0x62374c`, larger than the `0x6236f0..0x623740` range used in §14. Notation as §14: `sY` = stick Y `S+0x2e4`
(+ = pull), `sX` = stick X `S+0x2e8`, `ru` = rudder `S+0x2ec`, `W = m·9.806`, `τ` = sample time since the channel base,
`S` = the state copy the routine works on (`veh+0xc34` write copy; the attitude sampler reads `veh+0xc30`).

Channel layouts needed below (offsets inside the channel):
* Ramp (type A, `59fe30`/`59feb0`, clamp `59ff00`): `+0 t0 (f64), +8 v0, +0xc target, +0x10 rate, +0x14 min, +0x18 max,
  +0x1c t_end`. `59fe30(&now, v_now, target, rate)` stores `rate = |rate|·sign(target − v_now)`.
* Angle (type B, `5aac90`): `+0 t0, +8 pos0, +0xc rate0, +0x10 targetRate, +0x14 t_end, +0x18 pos_end, +0x1c accel,
  +0x20 startAccel, +0x24 stopAccel, +0x28 minRate, +0x2c maxRate`. The α channel `S+0x220` has 3 more fields:
  `+0x30 B (damping), +0x34 K (gain), +0x38 target α` (`S+0x250/0x254/0x258`).
* Axis (type C, `5aab30`/`5aab50`/`5aac20`/`5aac50`): `+0 p0, +8 t0 (f64), +0x10 v, +0x14 a, +0x18 min, +0x1c max`.
* **Angles are reduced with `fmod(x, 2π)`** (`_CIfmod` `0x56653a` with `DAT_00840880` = 2π, set by initialiser
  `0x623744 → 5b9320`), i.e. to (−2π, 2π), not to (−π, π]. Only the angle-difference helper `5ba9b0` and the helpers
  `44ed30`/`43d490` (fmod, then −2π if > π) wrap further.
* All channels of a state are sampled with `τ = clamp(now − S+0x28, 0, 1.1)` where `S+0x28` is the **X-axis base time**
  (`5b4580`, `5a42e0`); the ramps use `clamp(now − own t0, 0, 3.5)`.

### 15.1 Call graph (airborne)

**1 Hz + every control event — `5a42e0(&now)`** (in this order):
1. `τ = clamp(now − S+0x28, 0, 1.1)`; `alt = Z(τ)` (`5aac20`, clamped to the Z limits); `β_s = S+0x280(t)` (ramp sample);
   `α_s = fmod(α(τ), 2π)` (α channel `S+0x220`); `v = (vx, vy, vz)(τ)`, **`V = |v|` (not capped here)**.
2. Attitude `att = (pitch, roll, heading)`: `veh+0xc` unit → vtable `+0x54`, cached per `now` in `unit+0x88` (so the mode
   object's `5b4580`, §15.3, runs at most once per time stamp).
3. `cfg[10]` (ints, `cfg[0]` float) at `&L58` — **corrects §14.1**:
   * `cfg[0]` = flaps ramp `S+0x300` sample;
   * `cfg[6]` (brakes) = on the ground (getter `0x1a` ≠ 0): `|S+0x340(t)| ≥ 1e-5`; in the air: the `S+0x340` ramp has
     finished (`τ ≥ t_end`) **and** `|target − max| < 0.01·(max − min)`. `S+0x340` is the ramp of motion 8
     (`FUN_0059d370`), which the player controller posts @44bcf7/@44bd97 next to the GEV 0x11 brake handler (@44bf1e).
     §7 and §14.1 said `S+0x360`; that was wrong.
   * `cfg[7]` (gear) = `|S+0x320(t)| < 1e-5`, i.e. the gear ramp is exactly at its "extended" end (0). Gear drag, the
     ground lift gate and the belly rule use this, so they switch only when the gear is fully down (not while it moves).
     §14.1 said `S+0x2cc == 2`; that is `cfg[9]`, which Drag/Lift/ground aero do not read.
   * `cfg[8]` = `S+0x360` ramp finished at its max (motion 9) → `HookDragIndex` in Drag (UNCERTAIN: hook).
   * `cfg[1..5]` = 0.
4. Mass/stores: `m_x = S+0x424 + fuel(S+0x430)`, `DI_s = S+0x428 + S+0x42c`, `asym = S+0x428 − S+0x42c`.
   Flags `L90`: `|= 2` if `fuel < 1e-5` (`0x60dda4`), then `5b9140(&flags)` adds the damage bits.
5. `latched = S+0x2f8 ≠ −1.0 && now − S+0x2f8 ≤ 3.0` (`0x60dd28`, double; note `≤`).
6. `5b0a20` (33 args, below) → `L, Lnoflap, T, D, m, dragX, stall, vib, β_cmd, p_cmd, rpm, ff, abStage`.
7. `acc = 5b0e20(L_old = S+0x1e0(t), T, D, m, alt, V, β = β_cmd, α = α_s, &att, ground)` (@5a4a17) — the lift ramp sample
   **before** the new target, the new T/D/m, the **commanded** β and the **sampled** α.
8. Latch `5a7050(now, stall, vib)` (§15.2.4), then the mode hooks `5a7d50` and `5a96c0` (§15.5).
9. Lift ramps: `S+0x1e0 → L`, `S+0x200 → Lnoflap` (first re-based with the old rate, then the rate is set as §4:
   `V ≥ 220 ? G_Rate·m·g : (0.00495·G_Rate·V + (0.01 − 0.099)·G_Rate)·m·g`, same for `G_RateForAoa`; **no lower clamp**:
   the factor is 0.01 at 20 m/s, 0 at 17.98 m/s and negative below, and `59fe30` takes `|rate|`).
10. `S+0x1dc = D, S+0x1d4 = T, S+0x1d8 = m`.
11. α dynamics `5a7590(now, V, alt, Lnoflap, stall)` (§15.2.5).
12. Airborne: β `5a78f0(now, V, alt, β_cmd, stall)` (§15.2.6) and re-base `S+0x2a8` (target/rate kept). On the ground:
    `S+0x2a8 → yaw_nw` (7a20 output) at its own rate, re-base `S+0x280` and `S+0x260`.
13. Re-base the axes X/Y/Z with `acc` (`p = p(τ)`, `v = v0 + a0·τ`, `a = acc`).
14. `5a7520(att)`: `S+0x14..0x1c = (pitch, roll, heading)`, `S+0x08 = Mᵀ-map(−1, 0, 0)` = **left** wing in world axes
    (`5b74d0`; body x is the right wing, §5).
15. Roll channel `S+0x80`: re-base with `pos = att.roll` (rate and target kept), then `5aac90(now, pos, rate, k·p_cmd)`
    with `k` as §4 (`Veff < 220 ? 0.00475·Veff − 0.045 : 1`, `0x83f288/0x83f28c`, **no clamp**: `k < 0` below
    `Veff ≈ 9.47 m/s`).
16. Re-base ramps `S+0x300, 0x320, 0x340, 0x360, 0x380, 0x400` (and `0x3c0/0x3a0` unless the type is 0x82 or 0xbe);
    fuel ramp `S+0x430` rate `ff` (target kept, normally 0); `S+0x2f0 = dragX`;
    `S+0x420 = (75 < V < 150 && sY > 0.7)` (UNCERTAIN: a visual/effects flag; read only by getter `0x14` and the network
    packer); RPM ramp `S+0x1b0 → S+0x1c8·rpm` (`S+0x1c8` = 100, rate kept); sounds/AB effects; `veh+0xc3c = 1`; swap.

**5 Hz — `5a15e0`** (disassembly only):
1. `now = [0x694910]+0x38`; `alt = Z(τ)`; `V` = FM slot `0x3c` (`5a3a90`, capped 1200 m/s); `β_s = S+0x280(t)`.
2. `5b87d0(now, &V, &alt, &β_s)` (air/ground transitions, §14.6; on the ground it replaces `β_s` by `S+0x2a8(t)`).
3. Attitude as step 2 above. If `S+0x00 == 0` → vtable `+0x50` and `5abba0` (network state send; no physics).
4. **Mode dispatch:** if `S+0x04 == veh+0xc70` → `5a7d50(...)`, swap, **return**; if `S+0x04 == veh+0xc7c` →
   `5a96c0(...)`, swap, **return** (§15.5). Otherwise the normal tick:
5. `5a7520(att)`.
6. `Laoa = S+0x200(t)`; `αT = 5b1b90(V, alt, Laoa, latched, ground)` =
   `ground ? 0 : max(min((Laoa − e4·qS)/(e8·qS), MaxPosAlpha, LimitAlphaVisual), MaxNegAlpha)` (`latched` is not read).
7. `acc = 5b0e20(L = S+0x1e0(t), T = S+0x1d4, D = S+0x1dc, m = S+0x1d8, alt, V, β = β_s, α = αT, &att, ground)`.
   **The 5 Hz force uses the α *target* `αT`, not the α channel.**
8. Ground stop rule (§14.5), then re-base X/Y/Z with `acc`.
9. Re-base `S+0x1e0` and `S+0x200` (same target and rate).
10. Roll: re-base `S+0x80` with `pos = att.roll`, rate and target kept (no new target at 5 Hz).
11. α: `S+0x258 = αT`, target rate `r = 5ab4e0(now)`, `5ab260(now, r)` (re-base with the new target rate; the gains
    `S+0x240..0x254` stay as set by the last 1 Hz `5a7590`).
12. β: `β_cmd = 5b1840(β_s, ru, alt, V, asym)` with `asym = 0` when `S+0x04 == veh+0xc70`, then
    `5a78f0(now, V, alt, β_cmd, latched)` — **also on the ground**.
13. Re-base fuel `S+0x430` and RPM `S+0x1b0`. If `S+0x04 == veh+0xc78` → `5b5eb0(&now)` (§15.5). `veh+0xc3c = 1`, swap.

### 15.2 Airborne aero `5b0a20` (thiscall `ecx` = P, `ret 0x84`, 33 stack args)
Args (from the pushes @5a48ec–5a4963): 1 alt, 2 V, 3 α_s, 4 β_s, 5 &att, 6 ground (`S+0x2a0`), 7 latched, 8 engine on
(`S+0x1d0`), 9 &cfg, 10 m_x, 11 DI_s, 12 asym, 13 flags, 14 thr (`S+0x2dc`), 15 sY, 16 sX, 17 ru, 18 vehicle, 19/20 now,
outputs 21 &β_cmd, 22 &p_cmd, 23 &rpm, 24 &ff, 25 &abStage, 26 &L, 27 &dragX, 28 &stall, 29 &vib, 30 &Lnoflap, 31 &T,
32 &D, 33 &m. Ground → `5b7a20` (§14). Airborne (@5b0b3a):
```
*vib = 0
ai   = FUN_005c58a0(veh+0xc50) != 0
team = DAT_00694960 ? 4a41e0(...) : (side of veh ∈ {2,3})           // only used by Lift for AI
mach, rho = 5b0f00(alt, V);  qS = 5b1030(V, rho)
noAB = !P+0x164 || (ai && mode ∉ {7, 8})
T    = 5b1050(alt, mach, V, thr, engineOn, noAB, flags, &rpm, &ff, &abStage)    // §4.1, NOT clamped ≥ 0
m    = P+0x8c + m_x
L    = 5b13a0(V, alt, mach, qS, m, sY, &att, cfg, latched, ai, team, &dragX, &stall, &vib, &Lnoflap)   // §14.3
α_D  = stall ? 0 : clamp((Lnoflap − e4·qS)/(e8·qS), MaxNegAlpha, MaxPosAlpha)   // no LimitAlphaVisual here
D    = 5b1730(V, alt, n = L/(m·9.806), mach, qS, α_D, cfg, DI_s, dragX, stall||latched, ai, m)   // §14.4
β_cmd = (ru + 10·asym)·MaxBeta                                    // 5b1840; 0x60e2a8 = −10, (A2 − A5·(−10))·P+0xb8
p_cmd = MaxRollRate·sX                                             // P+0xac
```
In Lift the airborne call passes the real `latched`: `latched && bStall` → `L = Lnoflap = 0`, `dragX = 1.2`, the stall flag
is **not** set. So during the latch `α_D = clamp(−e4/e8, …)` (irrelevant, `L = 0`), the 1 Hz α target is the zero-lift α
(§15.2.5) and the jet flies ballistic (thrust, drag with `n = 0`, gravity).

#### 15.2.1 Drag, thrust
As §14.4 with the corrected `cfg` (15.1 step 3): `CD = PlaneDI + cfg[6]·SpeedBrakesDI + cfg[8]·HookDI +
cfg[7]·GearDI·(ai ? 0 : 1) + FlapsDI·flaps·3.4158838 + DI_s + K·CL²`, `CL = cos(α_D)·L/qS` (L includes the flap
increment). Thrust as §4.1; the airborne T is not clamped.

#### 15.2.2 Acceleration `5b0e20` → `5b1860` (airborne; `5b0e20 ret 0x30`, `5b1860 ret 0x2c`)
`5b0e20(L, T, D, m, alt, V, β, α, &att, ground, &acc_out, &acc_body_out)`: `M = 5b7580(ground ? 0 : pitch, ground ? 0 :
roll, heading)`, then `5b1860(&ret, ground, T, L, D, m, α, β, V, &acc_body_out, &M)`; airborne:
```
x = D·sin β + 5·V²·β           // 0x60e1e8 = −5; objdump "fsubp st(1),st" = st1 − st0 (Intel semantics)
y = T + L·sin α − D·cos α·cos β
z = L·cos α + D·sin α·cos β
r = 5b74d0(M, (x, y, z))        // (y, x, −z) → Mᵀ → (−r1, r0, r2), world X east, Y north, Z up
acc = (r.x/m, r.y/m, (r.z − 9.806·m)/m)
```
`acc_body_out` is not written in the air. Frames: body x = right wing, y = nose, z = up (check: `M(0,0,0) =
diag(1,−1,−1)`, body y → north, body x → east). `M` is the body attitude from the mode object (it already contains α(t)
and β(t)), while the decomposition uses the α/β passed in: 5 Hz `αT` and `β(t)`, 1 Hz `α(t)` and `β_cmd`. While α lags
`αT` (a pull), the lift vector therefore leans forward by `αT − α(t)` (extra forward force `L·sin(αT − α)`); while α
overshoots it leans back. With `β_cmd ≠ β(t)` the 1 Hz side force uses the commanded sideslip at once.

How the path turns: nothing integrates a pitch or yaw rate. Lift acts along body z rotated by the bank (in `M`), so
its horizontal part turns the velocity vector; the attitude (§15.3) is rebuilt from the velocity every frame, so the
nose follows the velocity plus α/β. The side force `5·V²·β` (N, independent of mass and wing area) pulls the velocity
toward the nose (weathervane).

#### 15.2.3 Lift in the air
Exactly §14.3 with `latched` honoured. Summary of what is airborne-specific: the stick-centre line
`c = V < P+0x144 ? P+0x170·V + P+0x174 : 1` (loader @5b08cc–5b0956: `P+0x144 = Vmin(3048 m, StartMoveStickCenterG)`,
`P+0x170 = (MapCenterStick − 1)/(10 − P+0x144)`, `P+0x174 = MapCenterStick − 10·P+0x170`, 10.0 = `0x60e1f8`; skipped if
`10 − P+0x144 == 0`); the 1 g hold uses the body attitude of step 2 (pitch/roll of the nose, not of the path); the
vibration flag needs `P+0x84` and `!ai`.

#### 15.2.4 Departure / stall latch `5a7050(now, stall, vib)` (thiscall, `ret 0x10`)
```
player = veh is DAT_00694960's unit (ids at +8/+0xc/+0x10/+0x14 equal) && [unit+0x1c]+0x14 == 3
if S+0x2f8 == −1.0 (unset) and stall:
    S+0x2f8 = now
    if player && airborne: FUN_004dcef0()     // force-feedback effect "StallShake" start
    unit log message (resource string 0x14, 4a4140) (UNCERTAIN: text)
elif S+0x2f8 != −1.0 and now − S+0x2f8 > 3.0:
    S+0x2f8 = −1.0
    if player && airborne: FUN_004dd790()     // FF effect stop
if veh+0xc60 == 0:  S+0x1a8 = S+0x1ac = vib ? 0.5 : 0      // 0x60dd68 = 0.5 (double), camera/stick shake
```
* A stall result only **starts** the latch; while it is set a new stall does not extend it. It is cleared by the first
  aero update with `now − t > 3.0`, even if the jet is still stalled; the next update with `stall = 1` sets it again.
* `latched` for Lift is `now − t ≤ 3.0`. With the 1 Hz timer (updates at t+1, t+2, t+3 exactly) the lift is held at 0
  for **three** further updates, i.e. until the update at t+4; control events in between also see `L = 0`.
* The latch is also set on the ground (Lift runs GLimit there); the ground aero ignores it (§14.6).
* Stall is `code 0` (below Vmin) or `code 2` (above the envelope) with stalls enabled (`bStall`, §14.3).

#### 15.2.5 α dynamics: 1 Hz `5a7590(now, V, alt, Lnoflap, stall)` and 5 Hz `5ab4e0`/`5ab260`
1 Hz: `αT = 5b1b90(V, alt, Lnoflap, stall, ground)` — **uses the new `Lnoflap` target, not the ramp**. Gains:
`f = V ≥ 220 ? 1 : max(0.004995·V − 0.0989, 0.001)` (`0x840770/0x840774` set by `5aef10`, floor `0x60ddfc`);
`S+0x240 = |AlphaStartAccel·f|`, `S+0x244 = |AlphaStopAccel·f|`, `S+0x248/0x24c = ∓MaxAlphaRate·f`,
`S+0x250 = B = AlphaBeta·f`, `S+0x254 = K = AlphaK·f`, `S+0x258 = αT`. Then with `(pos, rate) = α(τ)`:
```
err  = 5ba9b0(fmod(pos, 2π), αT)        // wrap(αT − pos) to (−π, π]
damp = |rate| ≤ π ? B·rate·Rmax : 0.5·B·rate·Rmax           // Rmax = S+0x24c; 0x60dd08 = 0.5
r    = clamp(err/π·K/Rmax − damp, −1, 1)·Rmax
5aac90(now, fmod(pos, 2π), rate, r)
```
5 Hz: the same `r` from `5ab4e0` with `αT` from the `S+0x200` ramp sample (§15.1) and the stored gains.
`5aac90` picks `startAccel` if `|r| > 0.02·Rmax` (`0x60dd34`), else `stopAccel`, signed toward `r − rate`.

#### 15.2.6 β `5a78f0(now, V, alt, β_cmd, flag)` (thiscall, `ret 0x18`; `alt` and `flag` unused)
```
rate = V < 375 ? max(V·0.0025·BetaRate, 0.25·BetaRate) : BetaRate    // 0x840780 = BetaRate·0.95/380, 0x840784 = 0
S+0x280 (β ramp, limits ±MaxBeta):  set(now, β(t), β_cmd, rate)
S+0x260 (limits ±MaxBeta):           set(now, v(t), k·w_z − β_cmd, rate)
    k = V < 400 ? min(0.0573452 − 9.97308e-5·V, 3°) : 1°            // 0x83f29c, 0x83f298, 0x60de0c, 0x3c8ef95c
    w_z = S+0x10 (left-wing vector z); (0x8407c8, 0x8407cc, 0x8407d0) = (0, 0, 1)
```
The vector `(0,0,1)` is written by the CRT initialiser `0x6236a8 → 5a02c0`; the doc (§5) said it was never written.
`S+0x260` is read only by getter 8 (`5a64b0`), which feeds the HUD (`44831e`/`44834a` → `445950`/`445940`); it has no
effect on the flight path. So the physical β is just the ramp `S+0x280 → β_cmd`. `5a78f0` runs at 1 Hz (airborne only)
and at 5 Hz (always, also on the ground), so a rudder held on the ground builds up β that shows at lift-off.

**Ramp limits and rates set by `5aef10` (at SetType `5a5bb0`, for both state copies):** roll `S+0xa0 = |RollAccel|`,
`S+0xa4 = |StopAccel|`, `S+0xa8/0xac = ∓MaxRollRate`; β `S+0x290 = |BetaRate|`, `S+0x294/0x298 = ∓MaxBeta`; the same for
`S+0x270..0x278` and for the **nose-wheel ramp `S+0x2b8 = |BetaRate|`, `S+0x2bc/0x2c0 = ∓MaxBeta`**; lift ramps
`S+0x1f0 = |MaxWeight·G_Rate·g|`, `S+0x1f4/0x1f8 = MaxWeight·(MinG−1)·g / MaxWeight·(MaxG−1)·g` (same for `0x210..0x218`
with `G_RateForAoa`); α as above with f = 1; fuel `S+0x440 = |FuelFlow|`, limits `[0, FuelWeight]`; RPM `S+0x1c8 = 100`.
The constructor value `S+0x2b8 = 10000` (@5b70d2) quoted in §14.1 is overwritten here, and the placement init
`5a2000` sets `S+0x2b8 = |BetaRate|` again (@5a2244). **So the nose-wheel yaw is a ramp at `BetaRate` (rad/s²) clamped to
±MaxBeta (rad/s)**: F-16 32°/s² and ±15°/s, which is below `K` = 20°/s. §14.1 ("in effect instant") was wrong.
The slopes `0x8407b8/bc` (G_Rate), `0x8407d8/dc` (G_RateForAoa), `0x840780/84` (β) are **globals** written by `5aef10`,
i.e. by the last aircraft type set up; all aircraft use them (see mismatch list).

### 15.3 Attitude — mode object vtable `0x60dee8` slot 0 `5b4580(&out, &now)` → slot 1 `5b4840`
`5b4580` (reads `S = veh+0xc30`): `τ = clamp(now − S+0x28, 0, 1.1)`; `φ = fmod(roll(τ), 2π)` (channel `S+0x80`);
`β = S+0x280(t)` (clamped); `v = (vx, vy, vz)(τ)`; `α = fmod(α(τ), 2π)`; then
`5b4840(&out, τ, vx, vy, vz, φ, α, β, S, &speed)` (`ret 0x28`):
```
*speed = |v|
if S+0x2a0: return 5b80e0(...)                                 // ground attitude (§14)
f = v/|v|;  w = S+0x08 (left wing at the last 1 Hz/5 Hz 5a7520);  dφ = φ − S+0x18
if dφ ≠ 0: w = R(f, wrap(dφ))·w                                  // Rodrigues, right-hand, 461970/467d50/46cac0/461930/466580
if α  ≠ 0: f = R(w, wrap(−α))·f                                  // nose above the velocity
if β  ≠ 0: n = w × f (explicit, @5b4b8c);  f = R(n, wrap(β))·f     // n = "down" in body axes → β > 0 = nose right
heading = (fx == 0 && fy == 0) ? 0 : atan2(fx, fy);  pitch = asin(fz)      // both wrapped (44ed30)
Mx = I · rot(−pitch) (44f700) · rot(heading) (44f8c0);  wl = w·Mx (43dda0)
c = clamp(−wl.x, −1, 1)  ((0x840800..08) = (−1, 0, 0), initialiser 0x6236e0 → 5b4560)
roll = acos(c);  if wl.z < 0: roll = −roll;  roll = wrap(roll)
out = (pitch, roll, heading)
```
`w` is **not** re-orthogonalised against `f`; the roll is measured from the raw `w`. `wrap` = `fmod(x, 2π)`, then
`−2π` if `> π`. `f` is undefined for `v = 0` (UNCERTAIN: x87 NaN). The same `τ` (X-axis base) is used for all channels.

### 15.4 Mode objects (`S+0x04` = current mode)
Created in the FM constructor @5a05ef–5a0690 (8 bytes each: `+0` vtable, `+4` owner). Slot 0 = sampled attitude
`(out, &now)` → (pitch, roll, heading), slot 1 = attitude with extra outputs (`ret 0x28`), slot 2 = position, slot 3 =
velocity, slot 4 shared `5b6b40`.

| field | vtable | slots 0..4 | what it is |
|---|---|---|---|
| veh+0xc6c | 0x60dee8 | 5b4580, 5b4840, 5b4e70, 5b4f80, 5b6b40 | normal flight (§15.3) |
| veh+0xc70 | 0x60ded0 | 5b3ea0, 5b40f0, 5b4330, 5b4440, 5b6b40 | **spin** (the only departure mode) |
| veh+0xc7c | 0x60deb8 | 5b5090, 5b5310, 5b5580, 5b5690, 5b6b40 | "Tornado": player map-edge push-back (`CancelTornadoEvent`) |
| veh+0xc74 | 0x60dea0 | 5b6020, 5b6400, 5b69a0, 5b6ab0, 5b6b40 | scripted, motion 21 (`5adae0`), own channels S+0x4e0..0x5e0 (UNCERTAIN) |
| veh+0xc78 | 0x60de88 | 5b58c0, 5b5ac0, 5b5ca0, 5b5d90, 5b5e80 | scripted, motion 22 (`5a5f70`); heading ramp S+0x130, re-based by `5b5eb0` at the end of each normal 5 Hz tick (UNCERTAIN: constant-bank turn) |

**There is no separate stall mode and no tail-slide mode.** "Stall" = the 3 s zero-lift latch (§15.2.4) inside normal
mode; the only departure is the spin. c74/c78 are scripted (mission/AI) manoeuvres, not triggered by the flight model.

**Where the modes run.** `5a42e0` (1 Hz/events) computes `acc` first (@5a4a17), then the latch (@5a4a2f), then calls
`5a7d50` (@5a4a86) and `5a96c0` (@5a4adf) **every time, in every mode**; afterwards it uses their in/out `L`,
`Lnoflap`, `acc`, `p_cmd`. In the 5 Hz tick, `S+4 == c70` → `5a7d50` (@5a1834), swap, return; `S+4 == c7c` →
`5a96c0(…, enter = 0, …)` (@5a18a1), swap, return. Their outputs are discarded there and the normal force/axis update
is skipped, so in both modes the axes are re-based only by the aero update or by the mode's exit.

`5a7d50` args (thiscall, `ret 0x3c`, 15 stack args): A1:A2 now, A3 `τ` (X-axis), A4 dragX (fresh Lift output at 1 Hz,
`S+0x2f0` at 5 Hz), A5 V, A6 β(t) (ramp `S+0x280`, before this update's new target), A7..A9 pitch/roll/heading,
A10 &acc, A11 &L, A12 &Lnoflap, A13 &p_cmd, A14 &α (never read back), A15 &β_cmd (never written). `5a96c0`
(`ret 0x40`) has an extra A10 = enter flag (0 from the updates, 1 from `5aa520`), pointers shifted to A11..A16.
π/2 = `DAT_0084078c` (initialiser `0x6236ac → 5a02f0`).

### 15.5 Spin (veh+0xc70) — `5a7d50`
**Channels** (limits from `5aef10` @5af10d–5af19d): yaw angle `S+0xb0` (type B; startAccel `|0.4·RollAccel|`,
stopAccel `|0.2·StopAccel|` (0x60e198/0x60e194), rates **±0.4·MaxRollRate** (0x60e19c/98); `5ab470` clamps the
target rate, so the nominal π/2 is always capped: F-16 80°/s, F-15 72, F-4 32, Mirage/Kfir/MiG-23/MiG-29 60,
MiG-21 28, Lavi 88); pitch ramp `S+0xe0` (rate `|0.05·MaxRollRate|` (0x60e190), limits ±π/2); roll ramp `S+0x100`
(same rate, limits ±π); arm timer `S+0x128` (double, −1 = disarmed).

**Entry** (normal mode, aero update only):
```
if veh+0xc54 ∈ {100, 140}: return                          // unit types without spins (UNCERTAIN which)
spinsOff = multiplayer(DAT_00694990 && [+4]) ? 0 : pref+0x34          // "No spins"
qual = |β(t)| ≥ 0.8·|MaxBeta| && dragX > 0.57 && !netgame(DAT_0082a9d0)   // 0x60de10 = 0.8 (f64), 0x60de18 = 0.57
// stage 1 @5a7dcf
timer = (timer == −1 && qual && !spinsOff) ? now : −1        // also resets an armed timer
// stage 2 @5a7e9f
if (now ≤ timer + 1.2 || !qual) && !damage(0x18): return      // 0x60de20 = −1.2 (f64, subtracted)
ENTER
```
Effective rule: the spin starts at the **second consecutive qualifying aero update**, whatever their spacing (the 1.2 s
never bites: stage 2 sees −1 + 1.2 < now). **With "No spins" on the timer is never armed, so the spin starts at the
first qualifying update** (a bug: the preference makes spins easier). Damage 0x18 ("Total flight control",
`FUN_0044ca90`) forces entry regardless of β, dragX and preferences. β ≥ 0.8·MaxBeta needs ≈ 80 % rudder (β_cmd =
(ru + 10·asym)·MaxBeta, so heavy asymmetric stores also qualify); dragX > 0.57 means code 0/2 or latched (dragX = 1.2)
or pulling more than 0.57·MaxG over the envelope limit (dragX = (g_cmd − lim)/MaxG). "No stalls" does not prevent it
(dragX is still 1.2 on codes 0/2).

On entry (@5a7f05): `S+4 = veh+0xc70`, player sound `4dd530`; `s = sign(β)` (+1/−1/0); yaw channel pos0 = heading,
rate0 = 0, target `s·π/2` (clamped), then `5aac90` re-base; pitch ramp reset to the current pitch (if within ±π/2),
target **−30°** (`0xbf060a92`); roll ramp reset to the current roll (if within ±π), target **+0.1 rad**
(`0x3dcccccd`). This update's L and acc stay normal.

**Update** (`S+4 == c70`, every aero update and 5 Hz tick):
```
acc.x = acc.y = 0
s1 = ftol(sign(yaw rate of S+0xb0 sampled with the axis τ))     // quirk: not its own τ
s2 = ftol(sign(β))
if s1 == −s2 && s1 != 0:                                        // opposite rudder slows the rotation
    yaw target = s1·π/2 + β·π/(1.8·MaxBeta)                      // 0 at β = −0.9·MaxBeta·s1 (0x60de28 = 0.9), clamped
stay = airborne && ( !(s1 > 0 && β ≤ −0.9|MaxBeta|) && !(s1 < 0 && β ≥ 0.9|MaxBeta|)  ||  dragX ≥ 0.1 )
                                                                // 0x60de30/38 = ∓0.9 (f64), 0x60de40 = 0.1
if stay:
    L = Lnoflap = p_cmd = α_out = 0
    acc.z = min(0, 0.04·V − 9.806)                              // 0x60de44 = −0.04, 0x60de48 = −9.806
    re-base S+0x100, S+0xe0, S+0xb0 (targets kept)
else: EXIT
```
Consequences: in 5a42e0 both lift ramps go to 0, the α target is the zero-lift α, the roll target is 0, and the axes
get `acc = (0, 0, min(0, 0.04V − g))`. **The horizontal velocity stays frozen at its entry value**; the vertical
acceleration is 0 at |v| = 245.15 m/s (|v| includes the frozen horizontal part). The β ramp keeps following the
rudder (`5a78f0`), and β drives the recovery. Recovery needs **≥ 90 % opposite rudder and dragX < 0.1** (no latch, not
below Vmin, not over-pulling). If s1 == 0 the spin never ends in the air (only touchdown ends it).

**Spin attitude** (slot 0 `5b3ea0`): one τ = clamp(now − S+0xe0 t0, 0, 3.5) for all three; pitch = ramp `S+0xe0`,
heading = yaw angle `S+0xb0` (fmod 2π), roll = ramp `S+0x100`, all wrapped to (−π, π]. The nose settles at −30° pitch
and +5.7° bank while the heading turns at up to 0.4·MaxRollRate, unrelated to the velocity.

**Exit** (@5a8791; same shape in `5a96c0` and `5aa0b0`): `f = 46c556(att)` = nose vector (UNCERTAIN convention,
consistent with (cos p·sin h, cos p·cos h, sin p)); `5a7520(att)`; `u = f × w`;
`f2 = R(w, α(t))·R(u, β)·f` (α from `5a6400`; UNCERTAIN signs/order); **velocity := f2·V** (axes re-based, position and
old acceleration kept); roll channel re-based at pos = roll (rate/target kept); `S+0x128 = −1`; acc.x = acc.y = 0;
`p_cmd = s1·0.1`; `S+4 = veh+0xc6c`; player sound `4dd7a0`.

### 15.5a "Tornado" (veh+0xc7c) — player map-edge push-back
Trigger in `5b87d0` (@5b8938–5b8a78, every 5 Hz tick, before the air/ground logic): `flags = 402460(terrain, ftol X,
ftol Y)`. `flags & 0x300`: play EndWorld.wav + Kramer18.wav once (latch `DAT_00840870`, cleared when neither bit is
set). `flags & 0xc0`, player, not already in c7c: `5aa520(&now, pitch, roll, heading)` + Kram1.wav. (UNCERTAIN: the
cell flags mark the map border.)
`5aa520`: schedules `CancelTornadoEvent` (vtable 0x60dfa0) at now + 8 (`0x60de70`) → `5ab9c0` → `5aa0b0` (exit as the
spin); ramps `S+0x168 = −1.5·V·sin h`, `S+0x188 = −1.5·V·cos h` (`0x60de78`, limits ±1e8) each targeting 0 at rate 10;
`5a96c0(enter = 1)`: yaw target ±2π (clamped ±0.4·MaxRollRate, sign of roll), roll `S+0x80` target ±2π (clamped
±MaxRollRate), pitch target +50° (`0x3f5f66f3`).
Each update: `acc = (S+0x168(t), S+0x188(t), −1.0)` (ramps sampled with the axis τ ≤ 1.1, so they never decay:
UNCERTAIN, verify in game), `L = Lnoflap = p_cmd = α = 0`, channels re-based; on the ground it exits (`5ab0a0`).
Attitude (`5b5090`): pitch `S+0xe0`, roll `S+0x80`, heading `S+0xb0`.
Only needed if our world has the equivalent map-edge cell flags (low priority).

### 15.6 Touchdown, landing and crash (`5b85b0`, `5b87d0`), and the start rules

#### 15.6.1 Landing check `FUN_005b85b0(τ, vz)` (thiscall, `ret 8`, returns 1 = crash)
Called only from `5b87d0` @5b8958, once per 5 Hz tick at touchdown. `τ` = Z-axis τ, `vz = v_z + a_z·τ`.
```
if 5a8fa0(&gameTime): return 0                       // crash immunity, 15.6.3
θ = S+0x14, φ = S+0x18        // Euler saved by 5a7520 at the LAST aero/5 Hz update (not re-sampled)
Lp = DAT_0084084c = 5°   (1°·5.0,  0x60e588, initialiser 0x623734 → 5b79d0)
Lr = DAT_0084085c = 10°  (1°·10.0, 0x60e58c, initialiser 0x62373c → 5b7a00)
Lv = −40.0 m/s           (0x60e56c)
if multiplayer || pref+0x3c ("Easy landing", default ON): Lp, Lr, Lv ×= 2
gear = S+0x320 ramp sampled with the Z-axis τ
if |gear| ≥ 1e-5 (not fully down, 0x60e608): Lp ×= 0.2, Lr ×= 0.2 (0x60e610), Lv ×= 0.25 (0x60e614)
r = 402050(x, y, &h, &nx, &ny, &nz)                  // terrain normal (TgenAPI slot 0x4c)
OK ⇔ θ ≥ −Lp && |φ| ≤ Lr && vz ≥ Lv && (r == 0 || |nz/|n|| ≥ 0.9848077 (cos 10°, 0x60e618))
```
| gear | Easy landing off | Easy landing on (default) |
|---|---|---|
| fully down | nose-down 5°, roll 10°, sink 40 m/s | 10° / 20° / 80 m/s |
| not fully down | 1° / 2° / 10 m/s | 2° / 4° / 20 m/s |

No nose-up (tail-strike), speed or sideslip limit. **There is no other terrain collision in the FM**: flying into the
ground is a touchdown that fails this test (nose-down, sink, roll or slope > 10°). Because it runs at 5 Hz, Z can be
up to 0.2·|vz| below the ground when it runs. UNCERTAIN: meaning of `402050`'s return value.

#### 15.6.2 `5b87d0` side effects (adds to §14.6)
Terrain flags `f = 402460(round X, round Y)` (names inferred, UNCERTAIN): `f&6` water, `f&0x30` runway, `f&9` rough
ground, `f&0x300` map edge, `f&0xc0` border (Tornado, §15.5a).
* **Touchdown** @5b8b14: `S+0x2a0 = 1`. Check failed → `4a8280(dmgObj, 0.0, 5, 0x82d6f8)`: unit state 5 = destroyed
  (`4a7ba0`), player gets the FF "Crash" effect. Z axis as §14.6, `5a42e0(now)`. Rough ground and V > 25.736 m/s and not
  immune → destroyed. Water → `S+0x2c8 = 4`. Gear not fully down → `S+0x2c8 = 2` (belly; player, not crashed: FF Crash,
  FF OutRunway, SFX_SCREECH 0x29 on the runway). Gear down, player, not crashed: FF Landing, FF OutRunway when off the
  runway, SFX_TOUCHDOWN 0x28, `441000()` (UNCERTAIN: "landed" flag at ctl+0xe0).
* **Lift-off**: as §14.6, plus `S+0x2c8 = 0` and the OutRunway FF stops.
* **Rolling, every 5 Hz tick**: rough ground and V > 25.736 and not immune → destroyed; if `S+0x2c8 ∉ {2,4}`:
  runway && landing check OK → `S+0x2c8 = 0`, else 1 (OutRunway FF on); player and V < 5.1472 m/s (0x60e628) →
  OutRunway off; `S+0x2c8 == 4` (water) and not immune → destroyed every tick (returns before clamping Z); otherwise
  Z p0 = clear, t0 = now.
* `S+0x2c8`: 0 runway, 1 off-runway ground, 2 belly, 4 water. The `0x836440` calls are DirectInput force-feedback
  effects (StallShake `4dcef0`/`4dd790`, OutRunway `4dcf80`/`4dd780`, Landing `4dd1c0`, Crash `4dd450`), not sounds.

#### 15.6.3 Crash immunity `FUN_005a8fa0(&now)` (1 = cannot crash)
```
ai = 5c58a0() != 0;  mode = 5c58a0()
cheat  = !ai && prefsApply && (pref+0x20 "No crashes" || pref+0x1c "Invulnerable")
         // prefsApply = !multiplayer || DAT_00694a68 ("Multiplayer/PreferencesApply")
aiOld  = ai && now − [veh+0xc50]+0x10 > 3.5 (0x60de58)
lowDmg = dmgObj+0x10 ≤ 0.1 (0x60de40; Ghidra shows it inverted)
fuel   = S+0x430(t) > 0;   teamOK = !(team test && mode == 0x11)
if dmgObj+0x14 == 0: return 0
return cheat || (mode == 9 && fuel) || (aiOld && fuel && lowDmg && teamOK)
```
In practice an AI jet with fuel never crashes on landing.

#### 15.6.4 Mission start `FUN_005a2a10(&now, pos[6], vel[3])` (FM vtable 0x60df00 slot 2)
`pos` = (x, y, z, pitch, roll, heading). Reached through the vtable (e.g. the mover hand-over `464c61` passes the
previous mover's position and velocity; UNCERTAIN which mover precedes the player's FM).
```
S+4 = veh+0xc6c (normal mode)
vz = vel.z;  if vel == 0: vz = veh+0xc40.z (constructor 0; no other writer found)
Vh = sqrt(vel.x² + vel.y²);  v = (Vh·sin ψ, Vh·cos ψ, vz), ψ = pos[5]      // heading overrides the vel direction
axes: p0 = pos, t0 = now, v, a = 0;   roll channel S+0x80: pos = pos[4], rate 0, target 0
sticks 0; S+0x128 = −1; stall latch S+0x2f8 = −1; S+0x420 = 0; S+0x1d8 = EmptyWeight
ramps S+0x360 := 0 (rate 0.5); S+0x380/3a0/3c0/3e0/400 := 0 (rate 0.7)
airborne ⇔ z > 800 (0x60dd78) && !(dist_h(pos, base) < 5000 (0x60dd7c) && |z − base.z| < 15 (0x60dd50))
           base = 54f100(x, y, z) (UNCERTAIN: nearest airbase; [3..4] = runway start point)
AIRBORNE: S+0x2a0 = 0; engine on; Euler = (asin(v̂z), pos[4], pos[5]) via 5a7520
          gear S+0x320 = 1.569 (up), flaps 0, brakes S+0x340 = 0, all rate 0.5
          throttle 0.74; RPM ramp 70 → 70, rate 15
          lift ramps S+0x1e0/S+0x200: value = target = MaxWeight·9.806 (5aa950)
GROUND:   Euler = (pos[3], 0, pos[5]); velocities 0 (a kept); Z p0 = pos.z + |model height|
          gear 0 (down); flaps S+0x300 = 0.29275 (= full: ×3.4158838 = 1.0); brakes S+0x340 = 0.855 (on)
          throttle 0; RPM 0 (rate 15); lift ramps 0
          engine ON only if dist_h(pos, runway start point) ≤ 100 m (0x60dd80), else OFF
both: fuel S+0x430 = FuelWeight (full), rate 0; controller (4493a0, forced): gear lever := S+0x2a0, on the ground also
      flaps (GEV 0xc) and brakes (GEV 0x11) with arg 1; swap; immediate aero update (5a15b0);
      aero timer 1.0 s (veh+0xc58, 0x60df90), accel timer 0.2 s (veh+0xc5c, 5ab830); S+0x2cc = S+0x2d0 = 0
```
A start at ≤ 800 m (or near the base) is placed on the ground at its z; the next 5 Hz tick snaps Z to the terrain.
The α channel and the β ramp are not reset here (UNCERTAIN).

`FUN_005a2000(&now, pos[6], vel[3])` (re-placement; callers 5a5740, 5a63e2, 5adb56, 5d3293, 5d3742): axes p = pos,
v = vel, a = 0; roll = pos[4]; β, `S+0x2a8`, `S+0x260` ramps := 0 at rate |BetaRate|; α := 0; airborne ⇔
`terrain(x,y) + |h| < z` (0x60dd48 = 0.0). Airborne with |vel| > 0: pitch = asin(v̂z); with vel = 0: velocity = unit
vector of the old Euler `S+0x14` × 10 m/s (0x60dd58); **throttle 0.7**, engine on, RPM 70, lift ramps = MaxWeight·g.
Ground: `S+0x2a0 = 1`, Euler (pos[3], 0, pos[5]), vz = 0, throttle 0, engine on, RPM 0, lift ramps 0. Gear, flaps and
fuel untouched; timers restarted.

**Control ramps** (constructor helper `5b72d0(min, max)`: value 0, rate 10000; rates below are set by `5a2a10` only):

| ramp | motion | min / max | rate | full throw |
|---|---|---|---|---|
| `S+0x300` flaps | 6 `59cf50` | 0 / 0.29275 | 0.5/s | 0.585 s |
| `S+0x320` gear | 7 `59d170` | 0 (extended) / 1.569 (up) | 0.5/s | 3.1 s |
| `S+0x340` brakes | 8 `59d370` | 0 / 0.855 | 0.5/s | 1.7 s |
| `S+0x360` hook (cfg[8]) | 9 `59d570` | 0 / 0.7855 | 0.5/s | 1.57 s |
| `S+0x380` | — | ±0.3926 | 0.7/s | |
| `S+0x3a0`, `S+0x3c0` | — | ±0.5236 | 0.7/s | |
| `S+0x3e0`, `S+0x400` | — | ±0.7855 | 0.7/s | |

Flaps "on" target = max × (0.33 if `veh+0xc54 == 100` else 1) (UNCERTAIN which type is 100); gear "on" → 0;
motions 8/9 "on" → max, "off" → min. After a `5a2000` ground re-placement (or the constructor alone) the rates stay
10000, i.e. instant (UNCERTAIN in real play).

### 15.7 Preference flags (pref instance `DAT_00694a64`, copied from the menu object by `FUN_004fcb80`)
| pref | menu name | default (`FUN_00450790`) | where it acts in the FM |
|---|---|---|---|
| +0x18 | Unlimited ammo | 0 | — |
| +0x1c | Invulnerable | 0 | crash immunity `5a8fa0`; ground aero `5b7a20` "easy" (lift gate, no belly μ) |
| +0x20 | No crashes | 0 | same as +0x1c |
| +0x24 | No malfunctions | 1 | — |
| +0x28 | No wind | 1 | — |
| +0x30 | No blackouts | 0 | §13 |
| +0x34 | **No spins** | 0 | spin arming `5a7d50` @5a7e33 (only skips the arm step: spins start *earlier*, §15.5) |
| +0x38 | **No stalls** | 0 | Lift `bStall` @5b1418 (§14.3); vibration allowed `P+0x84` (`5af920`) |
| +0x3c | **Easy landing** | **1** | landing limits ×2 (`5b85b0` @5b862a); ground lift gate (`5b7a20` @5b7c4e) |
| +0x40 | Easy aiming | 1 | — |
| +0x44 | Unlimited fuel | 0 | fuel flow 0 (`5b1050` @5b136c) |
| +0x50 | AI level 0/1/2 | 2 | Lift AI branch (`5b13a0` @5b13d1) |

In multiplayer: "No stalls" and "No spins" are ignored (treated as off), Easy landing is forced on, and
Invulnerable/No crashes apply only if `DAT_00694a68` ("PreferencesApply") is set. Rows confirmed from the Gameplay page
draw code @514780 and its rect table `0x6068e8`.

### 15.8 Throttle and AB light-up delay (`FUN_0059cb60` motion 2, `FUN_0059cea0`)
```
if !ai && !engineOn: engineOn = 1, dirty = 1              // the first throttle event starts the engine
changed = !ai ? |new − thr| ≥ 0.015 (0x60dc48) : new != thr   // the player's smaller moves are ignored
if changed:
    engineOn (S+0x1d0) = 1
    if !ai && thr < 0.75 && new ≥ 0.75:
        thr = 0.74 (0x3f3d70a4); dirty = 1
        veh+0xc68 = timer(now + max(0, (S+0x1c8 − RPM(t))·0.0666667), copy of the event)   → 59cea0
        // an older c68 timer is not cancelled
    elif !ai: cancel the c68 timer; thr = clamp(new, 0, 1)
    else:     thr = clamp(new, 0, 1)
    dirty = 1
if dirty: 5a42e0(now); 5a55a0()
59cea0 (ret 0x28): if veh+0xc68 ≠ 0: thr = clamp(requested, 0, 1); 5a42e0(gameTime); swap; veh+0xc68 = 0
```
The delay is the time the RPM ramp (0..100, 15 %/s, `S+0x1c0`, `0x60e188`) needs to reach 100 %: 2.67 s from idle
(RPM 60), 0 from military. A second AB request while one is pending adds a second timer; the first applies the older
value and clears c68, so the second does nothing. Keys use the same handler: motion 3 (`59c6a0`) adds 0.0925 only if the
result stays ≤ 1.0 (so keys top out at 0.925 = AB2), motion 4 (`59c6e0`) = max(thr − 0.0925, 0). Motion @59fc40 writes
`S+0x1d0` (engine on/off). RPM ramp target = 100·rpm (`S+0x1c8` = 100), so full AB (rpm 1.14) shows 100.

### 15.9 Exact envelope algorithm (for porting; the port currently interpolates linearly, §10)
All float32 with x87 intermediates; `trunc` = `_ftol` (toward 0). Constants: `0x60e2ec` = 0.5147222 (kt→m/s),
`0x60e2e8` = 0.3048, `0x60e2c4` = 0, `0x60e2c8` = 1, `0x60e2f8` = −1, `0x60e2d0/d8/e0` = 0/−1/1 (f64), `0x60e2f0` = 1e-5
(f64), sentinel altitude `0x46ea6000` = **30000.0 m**. `E` = `P+0` in the static per-type array `0x83f2a8`
(14 × 0x17c, BSS); the constructor `5b1da0` sets only `E+0x14` (idx0) = −20; `5af920` loads a type once (ref count
`P+0x16c`). Nothing in the CRT table touches the envelope.

| field | meaning |
|---|---|
| `E[0]` | 14 row pointers; `row[r][slot] = (alt m, vel m/s)` |
| `E[3]` | per slot: index of the last real row |
| `E+0x14 / 0x18 / 0x1c` | idx0 (slot of the g=0 graph) / NumberOfG-Graphs / step (m) |
| `E+0x20 / 0x24` | gmin / gmax |
| `E+0x28/2c/30`, `E+0x34/38/3c` | positive / negative high-altitude line (a, b, 1/a) |
| `E+0x44/48`, `E+0x58/5c` | per-level point lists and counts, g ≥ 0 / g ≤ 0 |

**Loader `5b23c0`.** `NumberOfG-Graphs`, `AltitudeStep` via `GetPrivateProfileIntA("Params", …)`, `step = int·0.3048`.
14 rows × (NumG+2) slots, not bounds-checked (≤ 13 real rows + sentinel; shipped files have ≤ 12). Finds
`[Min Velocity Table]`, pass 1 (`5b2f10`), then pass 2 (`5b2b20`) re-reads the file.

**Pass 1 `5b2f10`** (until a line starting with `[`):
```
sscanf("%d %d %d", g, v_kt, alt_ft) == 3 else skip          // "0 70.3 13000" → 2 → skipped; trailing text ignored
if g != previous g:                                         // new graph on every CHANGE of g, file order, no sort
    gmin = min(gmin, g)                                     // gmin starts at 0 (BSS) → min(0, all g)
    if slot > 0: row[n][slot] = (30000, row[n−1][slot].vel); E3[slot] = n−1     // close previous graph
    slot += 1                                               // real graphs are slots 1..N, slot 0 is a pad
    if g == 0: idx0 = slot
row[n][slot] = (alt_ft·0.3048, v_kt·0.5147222); n += 1
end: close the last slot; gmax = (float) last g
pads, r = 0..13: slot 0 = (max(slot1.alt − 1, 0), slot1.vel + 1), E3[0] = E3[1]
                 slot N+1 = (max(slotN.alt − 1, 0), slotN.vel + 1), E3[N+1] = E3[N]
ceilAlt(slot) = row[E3[slot]][slot].alt
C0 = ceilAlt(idx0); Cmax = ceilAlt(idx0 + trunc(gmax)); Cmin = ceilAlt(idx0 + trunc(gmin))      // @5b2606
if Cmax ≠ C0: a28 = gmax/(Cmax − C0); b2c = gmax − Cmax·a28          (else 0)
if Cmin ≠ C0: a34 = gmin/(Cmin − C0); b38 = gmin − Cmin·a34
```
**Pass 2 `5b2b20`** (raw file rows, no sentinel/pads, same `%d %d %d` filter):
```
first row of a graph: prev = row; k = 0
next rows of the same g: (Vp, Ap) = prev, (Vc, Ac) = cur (SI)
    dV = Vp − Vc
    if dV ≠ 0: s = (Ap − Ac)/dV; if s ≠ 0: inv = 1/s; icpt = Ap − s·Vp
    // dV == 0 or s == 0: previous inv/icpt reused (stale; uninitialised on a first segment — no shipped file hits it)
    while k·step ≤ Ac:
        V = (k·step − icpt)·inv
        if g ≥ 0: insert (g, V) into posList[k];  if g ≤ 0: insert into negList[k]     // g = 0 in both
        k += 1
    prev = cur
```
A graph contributes to levels 0..floor(lastAlt/step) only (high-g graphs drop out at high levels). The insert
(vtable 0x60e330 slot 6 = `5b33c0`) keeps each list **ascending by V**, a new point going after equal V.
F-16: 24 levels per list; level 0 positive: g0 46 kt, g1 86, …, g9 417; level 20: only g0 (290 kt).

**Ceiling `5b22e0(g)`:** `g = clamp(g, gmin, gmax); i = trunc(g); d = g > 0 ? 1 : −1; A = idx0 + i; B = A + d;
f = g > 0 ? i + 1 − g : g − i + 1; return ceilAlt(B) + (ceilAlt(A) − ceilAlt(B))·f` (= linear interpolation).

**Vmin `5b1fa0(alt, g, ceil)`** (`ret 0xc`; every FM caller passes `ceil = Ceiling(g)`; AI callers at 0x5cc…–0x5d1…
not checked, UNCERTAIN):
```
g = clamp(g, gmin, gmax); alt = clamp(alt, 0, ceil − 1)
if g < 0: return 5b2170(alt, g)                 // same with B = A − 1, gB = gA − 1
A = idx0 + trunc(g); B = A + 1; gA = trunc(g); gB = gA + 1
iA = last row r of slot A with alt_r ≤ alt (walk from 0, the sentinel stops it); iB = same in slot B
(a, b, c) = plane((altA[iA], gA, vA[iA]), (altA[iA+1], gA, vA[iA+1]), (altB[iB], gB, vB[iB]))
return a·alt + b·g + c
```
At integer g this is linear in altitude; at fractional g the g-slope uses graph B's row at or below `alt`, not B's
value at `alt` (not bilinear). For g in (−1, 0): A = g0 graph, B = g−1 graph.

**Plane `5bbf00(out, P1, P2, P3)`**, z = a·x + b·y + c:
```
det = (y3−y1)·x2 + (y2−y3)·x1 + (y1−y2)·x3
if det == 0: a = b = 0
else: a = ((z3−z2)·y1 + (z2−z1)·y3 + (z1−z3)·y2)/det;  b = ((z3−z1)·x2 + (z1−z2)·x3 + (z2−z3)·x1)/det
c = z1 − a·x1 − b·y1
```
**Bracket `5b3330(list, V, &lo, &hi)`:** walk ascending; `p.V ≤ V → lo = p`, `V ≤ p.V → hi = p` (stop when both
found); lo = last point with V_p ≤ V, hi = first with V_p ≥ V (equal → lo = hi). Returns 1 if no hi (V above all
points; also for an empty list), −1 if no lo, else 0.

**GLimit `5b2810(alt, V, g, &lim)`** (`ret 0x10`):
```
k = max(trunc(alt/step), 0)
L = g > 0 ? posList : negList                          // g == 0 uses the negative list
if k + 1 > count(L) − 1: lim = −1; return 2            // F-16: alt ≥ 23·step = 21031 m
a = bracket(L[k], V, lo, hi);  b = bracket(L[k+1], V, lo1, hi1)
if a > 0:                                              // V above every point of level k
    if Ceiling(g) ≥ alt: lim = g; return 3
    lim = 5b2770(g, alt); return 4
if a < 0 || b < 0: lim = −1; return 0                  // STALL: below the lowest (g0) point of level k OR k+1
PC = (b > 0 || (|hi1.g − lo.g| ≥ 1e-5 && |hi1.g − hi.g| ≥ 1e-5)) ? lo1 : hi1
(a, b, c) = plane((L_k, lo.V, lo.g), (L_k, hi.V, hi.g), (L_{k+1}, PC.V, PC.g))    // x = alt, y = V, z = g
lim = a·alt + b·V + c                                  // lo == hi → det = 0 → lim = lo.g
if g > 0 && lim < 0: lim = 0;   if g < 0 && lim > 0: lim = 0      // no forcing for g == 0
return 4                                               // code 1 is never returned
```
`L_k = k·step`. **`5b2770(g, alt)`** (above all points, confirmed): `g = clamp(g, gmin, gmax); g ≤ 0 ?
min(a34·alt + b38, 0) : max(a28·alt + b2c, 0)` — the line from (ceilAlt(gmax graph), gmax) to (ceilAlt(g0), 0), and the
mirror with gmin. F-16: `14 − 6.5617e-4·alt` (9 g at 7620 m, 0 at 21336 m), `−10.5 + 4.9213e-4·alt`.

**F-16 `16.dat` check** (Python reconstruction `scratchpad/env/orig.py` vs the current `envelope.rs`):

| quantity | original | port |
|---|---|---|
| Vmin(330 m, 1 g) / (330 m, 9 g) | 87.95 / 422.41 kt | same (e4/e8 identical) |
| P+0x144 = Vmin(3048 m, 2.2 g) | 191.60 kt | 192.20 kt |
| Vmin(3048 m, ±1.5 g) | 138.0 kt | 143.0 kt |
| GLimit(0 m, 65.3 m/s, 8.7) | 4, 1.659 | 4, 1.659 |
| GLimit(0 m, 48 / 50 kt, 1) | **0 (stall)** | 4, 0.05 / 0.10 |
| GLimit(915 m, 53 kt, 1) | **0** | 4, 0.023 |
| GLimit(3000 m, 200 m/s, 9) | 4, 7.245 | 4, 7.256 |
| GLimit(10000 m, 250 m/s, 9) | 4, 5.115 | 4, 5.244 |
| GLimit(17000 m, 300 m/s, 1) | **4, 2.845** (line) | 4, 5.433 |
| GLimit(20000 m, 250 m/s, 1) | **4, 0.877** | 4, 3.647 |
| GLimit(22000 m, 300 m/s, 1) | **2** | 4, 5.433 |
| GLimit(1000 m, 120 kt, −1) | 4, −1.422 | 4, −1.426 |

The effective stall speed is the g0 speed of the **next** level up (F-16 sea level: 52.1 kt, port 46 kt); code 2 comes
≈ 1.2 km lower than in the port; above ≈ 12 km the port allows 3–5 g too much. UNCERTAIN: float32/x87 rounding (the
check used doubles).

### 15.10 Mismatches, most important first (`crates/iaf-flight/src/aircraft.rs`, `envelope.rs`)
"PO" = port as original. "BP" = original looks wrong → candidate for `Aircraft::better_physics` (the default stays
the original). Already decided and not repeated: the 1 g hold (original by default, γ-based under better_physics).

1. **Envelope** (`envelope.rs` l. 141–174; known deliberate deviation, §10) — PO, using §15.9 exactly. The linear
   version is not just smoother: (a) the stall test must be "V below the lowest point of level k **or** k+1" (F-16 sea
   level 52 kt instead of 46 kt; at 48–50 kt the port gives lift where the original stalls and latches); (b) the
   "above all points of level k" branch must use Ceiling and then the `5b2770` line (the port allows 3–5 g too much
   above ≈ 12 km); (c) code 2 from the level count (`trunc(alt/step) + 1 > levels − 1`, ≈ 1.2 km lower); (d) Vmin and
   the limit by the 3-point plane fits (≤ 0.13 g, ≤ 5 kt; `P+0x144` changes by 0.6 kt); (e) the parser: graphs by change
   of g in file order, trailing text after the 3rd integer accepted, pass-2 lists from the raw rows, g = 0 in both lists.
   `stall_floor` stays `DataSet::Real` only.
2. **No landing/crash check** (`transitions` l. 643–654) — PO: §15.6.1 at touchdown (and the rolling re-checks of
   §15.6.2) with the Easy-landing ×2 (default on), the gear-not-down ×0.2/0.2/0.25, the slope test, immunity §15.6.3;
   failure = destroyed. There is no other ground collision, so this is also "crash into terrain". BP: 40 m/s sink
   (80 m/s by default) is absurdly lenient (real gear ≈ 3–5 m/s), there is no nose-up/tail-strike limit, and the
   attitude used is up to 1 s old; better: ≈ 3–5 m/s, current attitude, a tail-strike limit.
3. **Spin mode missing** — PO: §15.4/§15.5 (mode state, three spin channels with their limits, the two-stage entry in
   `aero_update` after the latch, the update in both updates with `accel_update` skipping `apply_forces`, attitude
   from the spin channels, the exit that sets velocity := rotated nose·V, `p_cmd = s1·0.1`). BP: (a) "No spins"
   removes the arm step so spins start *earlier* — better: block entry; (b) the arm timer resets itself so the 1.2 s
   never applies — better: require the condition for 1.2 s; (c) the horizontal velocity is frozen during the spin and
   `acc.z = min(0, 0.04V − g)` uses the total speed, so a spin entered above 245 m/s never descends — better: bleed
   the horizontal speed with drag toward a 50–80 m/s descent; (d) velocity snaps to nose·V at recovery — better: keep
   the velocity and let the aero forces turn it; (e) s1 == 0 (or damage 0x18 with β = 0) never recovers — better:
   treat as recoverable; (f) the yaw-rate sign is sampled with the axis τ.
4. **Nose-wheel yaw is instant and unlimited** (l. 278–286, 593) — PO: ramp `S+0x2a8` toward the 7a20 yaw at
   `|BetaRate|` (rad/s²), clamped ±MaxBeta (F-16 32°/s², ±15°/s < K = 20°/s); the 5 Hz force uses the ramp sample,
   the 1 Hz/event force uses the raw target (§15.2.6, correcting §14.1).
5. **Force decomposition angles** (`apply_forces` l. 560–566) — PO: the 5 Hz tick must use `αT` (from the `S+0x200`
   ramp sample, clamped by LimitAlphaVisual, §15.1 step 6) and `β(t)`; the 1 Hz/event path uses `α(t)` and the
   commanded `β_cmd = rudder·MaxBeta` (§15.2.2). The port uses α(t)/β(t) in both. BP: `M` already contains α(t) and
   β(t), so using αT leans the lift forward by αT − α(t) during a pull (free forward force) and β_cmd applies the side
   force before the nose has yawed; better: α(t) and β(t) in both paths.
6. **α 1 Hz update missing** (`aero_update` has none) — PO: `5a7590` at every aero update/event with
   `αT = 5b1b90(V, alt, Lnoflap_target, …)` (the new target, not the ramp) and recompute the gains `f(V)` only there;
   the 5 Hz tick reuses the stored gains (the port recomputes f at 5 Hz, l. 539–542). Damping ×0.5 when |rate| > π
   (never reached with MaxAlphaRate ≤ 2.5).
7. **Gear, brake, flap ramps and `cfg`** (l. 254–255, 471–478, 481) — PO: add the gear ramp `S+0x320` (0 = down,
   1.569 = up, 0.5/s, 3.1 s); gear drag, the ground lift gate and the belly μ only when the ramp is exactly at 0; brake
   flag in the air = ramp finished at max, on the ground = any value ≥ 1e-5; flaps 0..0.29275 at 0.5/s (full = 1.0
   after ×3.4158838), brakes 0..0.855 at 0.5/s, the type-100 flaps ×0.33 (§15.6.4 table). The port's 0.25/s and
   1.0/s rates and its gear-lever test are invented.
8. **Throttle/AB** (`set_controls` l. 249–257) — PO §15.8: crossing into AB sets 0.74 and applies the request after
   `(100 − RPM)/15` s (a non-AB change cancels it); player moves < 0.015 are ignored; the first throttle event turns
   the engine on; key steps ±0.0925 up to 0.925. RPM ramp max 100 (port 110, l. 174), rate 15 %/s.
9. **Start rules** (`Aircraft::new` l. 155–208; host) — PO §15.6.4: airborne ⇔ z > 800 m and not near the base; roll
   = mission roll, vz from the start velocity, speed along the heading; throttle 0.74; RPM 70; gear up; ground start:
   gear down, full flaps, brakes on, throttle 0, RPM 0, engine on only within 100 m of the runway start point.
   Lift ramps start at MaxWeight·g (port: m·g, l. 172–173) — BP: this gives a short up-jolt until the first update;
   better: m·g.
10. **Stall latch** (l. 405, 462–464) — PO: latched while `now − t ≤ 3.0` (port `<`), started only when unset, cleared
    only at an aero update with `now − t > 3.0` (so with 1 Hz updates L = 0 for three further updates); the ground
    lift may set it. FF "StallShake" start/stop for the player.
11. **Preferences** (§15.7) — PO: "No stalls" (`!bStall`: code 0 → `min(0.4, g_cmd)`, code 2 → 0.4, code 4 →
    `max(r, 0.4)` unless g_cmd < 0.4, no latch), "No spins" (quirk above), "Easy landing" (default on), "Invulnerable"
    / "No crashes" (immunity and the ground "easy" gate), "Unlimited fuel" (ff = 0), all ignored/forced in
    multiplayer as listed. The vibration flag also needs `P+0x84` (pref +0x0e/multiplayer) and `!ai`.
12. **β also at 5 Hz and on the ground** (l. 507–512) — PO: `5a78f0` runs at every 5 Hz tick too (rate from the
    current V), also on the ground, so rudder held on the ground shows as β at lift-off. The `S+0x260` HUD value can
    be ignored.
13. **Roll channel and attitude details** — PO: (a) `kroll` has no lower clamp (port `.max(0.0)`, l. 503; negative
    below Veff ≈ 9.5 m/s); (b) the roll channel is re-based with `pos = attitude roll` and `5a7520` refreshes
    `w`/`φ_ref` at the 1 Hz update as well as at 5 Hz (port only at 5 Hz, l. 573–577); (c) `5b4840` does not
    re-orthogonalise `w` (port l. 317) and takes the roll from the raw `w` via the heading/pitch frame (port uses
    `right` recomputed after β, l. 323/331); (d) all channels are sampled with the X-axis τ (1.1 s clamp).
14. **Lift-ramp rate factor** (l. 494) — PO: no `.max(0.01)` (factor 0 at 17.98 m/s, |negative| below); guard the
    division when the rate is 0. BP: the slope globals (`0x8407b8/bc/d8/dc`, β `0x840780/84`) belong to the **last
    aircraft type set up**, so every jet uses that type's G_Rate/G_RateForAoa/BetaRate below 220/375 m/s; better:
    per aircraft (F-4 G_Rate 3 vs F-16 5).
15. **Terrain types and map edge** — PO when the world provides the flags: rough ground > 25.7 m/s and water destroy
    the jet, `S+0x2c8` states, OutRunway FF; the "Tornado" push-back (§15.5a) — BP: its acceleration ramps never decay
    (axis τ), reversing the velocity to ≈ 11×V₀ (UNCERTAIN, verify in game); low priority.
16. **Minor** — PO: the 1 Hz V is not capped at 1200 m/s (only the 5 Hz one); the airborne thrust is not clamped ≥ 0
    (already so, l. 392–395); `S+0x420` effects flag (75 < V < 150 && sY > 0.7); force-feedback effects and SFX 0x28/
    0x29, EndWorld/Kramer wavs (host/audio).

Items still UNCERTAIN: the Euler convention of `46c556` and the Rodrigues order in the mode exits, which unit types
are 100/140, the Tornado timing, the terrain flag meanings, modes c74/c78, the mover that supplies the start velocity,
`402050`'s return value and `441000`.
