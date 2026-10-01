# Jane's IAF flight model (reverse-engineered spec)

**Reference version: v1.1** (the official patch, docs/v1.1.md). Every address in this file is a **v1.1** address
(`assets/v1.1/iafjets.exe`; Ghidra dump `assets/ghidra_v11/iafjets.c`), converted from the original v1.0 analysis with
the address map of docs/v1.1.md (`assets/ghidra_v11/cited_map.tsv`); a v1.0 address is given as "(v1.0: …)" only where
it helps. The v1.0 → v1.1 flight-model changes (all ported) are summarised in §16. Several key routines (e.g. `5a4230`,
`5b9250`, `5b9530`) were read from the disassembly (`objdump -d -M intel`; Ghidra shifts stdcall argument lists by one,
the push order is authoritative). All physics is SI: m, kg, s, N, rad. Constants were read from the `.rdata` of the exe.
`UNCERTAIN` marks guesses.

## 0. Architecture (important for a faithful port)

* Per-aircraft params `P` (struct filled by the bd.ibx loader) and a double-buffered state `S`
  (`veh+0xc34` write copy, `veh+0xc30` read copy, 0x610 bytes each, swapped by `FUN_005a8300`).
* **The model is event-driven and analytic, not a per-frame integrator.** Every state variable is
  a "channel" that stores a base time `t0` and a closed-form curve; it is sampled at any time `t`:
  * **Ramp** (type A, 0x20 bytes: `t0:f64, v0, target, rate, min, max, t_end`), set by
    `FUN_005a2a80(obj, now, v_now, target, rate)` (`rate:=±|rate|` toward target,
    `t_end=(target-v_now)/rate`), sampled by `FUN_005a2b00`: `τ=clamp(t-t0,0,3.5)`,
    `v = τ<t_end ? v0+rate·τ : target`, clamped to `[min,max]`.
  * **Accel-limited angle** (type B, 0x30 bytes: `t0, pos0, rate0, targetRate, t_end, pos_end,
    accel, startAccel, stopAccel, minRate, maxRate`), set by `FUN_005adc70(obj, now, pos, rate,
    targetRate)`: clamp rates to `[minRate,maxRate]`; `Δ=targetRate-rate`; if
    `|targetRate| > 0.02·maxRate` → `accel = startAccel·sign(Δ)` else `accel = stopAccel·sign(Δ)`;
    `t_end=Δ/accel`; `pos_end = wrap(pos + rate·t_end + ½·accel·t_end²)`. Sample (`τ≤1.1`):
    `τ≤t_end: pos0+rate0·τ+½accel·τ², rate0+accel·τ`; else `pos_end+targetRate·(τ-t_end), targetRate`.
    Angles are reduced with `fmod(x, 2π)` (`FUN_0056886a` = `_CIfmod`, divisor `DAT_0084549c` = 2π), i.e. to
    (−2π, 2π), not to (−π, π] (corrected, §15). Only the angle-difference helper `5bdd50` wraps to (−π, π].
  * **Kinematic axis** (type C, 0x20 bytes: `p0, t0:f64, v, a, min, max`), `FUN_005ada80/aab50`:
    `τ=clamp(t-t0,0,1.1)`, `p = p0 + v·τ + ½a·τ²` (clamped `[min,max]`), velocity `v + a·τ`.
    Three of them: `S+0x20` X (east), `S+0x40` Y (north), `S+0x60` Z (up, altitude).
* Updates (timers created in `FUN_005a5820` @005a5820, the (re)initialiser):
  * **UpdateAeroData** – every **1.0 s** (`FUN_005a4200` → `FUN_005a70f0` @005a70f0) and also
    immediately on every control event (stick, throttle, rudder, flaps …, dispatcher
    `FUN_0059f180`). Recomputes thrust, drag, mass, lift *targets*, roll-rate target, fuel flow, the α and β
    targets, and also the acceleration (axes re-based at once, §14.1/§15.1).
  * **UpdateAccelAndRates** – every **0.2 s** (`5a4230`, disassembly only). Recomputes alpha target,
    beta (also in the spin, v1.1), the acceleration vector from current channel values, and re-bases every channel.
  * A port can run both at a fixed dt (e.g. 60 Hz) — that is smoother but not bit-faithful; to be
    faithful keep 1 Hz/5 Hz + event updates and constant acceleration between 5 Hz ticks.

## 1. Parameters (loader `FUN_005b2940` @005b2940, reads `FUN_005b4af0(section,key,default)`)

Conversion constants: lb→kg ×0.45359, ft²→m² ×0.092903, ft→m ×0.3048, deg→rad ×0.0174533,
DragIndex ×1e-4. "deg→rad*" = wrapped to (-180,180] then ×π/180.

**Parameter blocks, once per game session.** `FUN_005a8980` points the vehicle at a static block per type
(`veh+0xc4c`: 100 → `0x843e30` (also every unlisted type), 110 → `0x843fbc`, 120 / 200 → `0x844148`, **130 and 190 →
`0x8442d4`**, 140 → `0x844460`, …) and calls the loader with the type's section; the loader reads the section only
while the block's counter +0x17c is 0, then counts up. The 14 blocks (0x18c bytes) are built by a C++ static
initializer at program start (`FUN_005a2fa0`, in the `.data` initializer table) and never reset. So each block is
read on its first use in a game session, and **the Kfir and the Mirage share one**: whichever flies first in a
session (player or AI, any mission) gives both its section until the game exits. Port: `iaf_flight::load_in` with
`data_set::Blocks` (one per process in `IafFlight`), Flight data = Original only; the Real set gives each its own
section (docs/deviations.md).

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
| MaxG (`DAT_00673dfc`) | 0xc8 | 9 | g | **MaxG − 1** |
| MinG (`DAT_00673df4`) | 0xcc | −3 | g | **MinG − 1** |
| G_Rate | 0xd8 | 5 | g/s | raw |
| G_RateForAoa | 0xe0 | 1 | g/s | raw |
| DragVdmin | 0xec | 302 | ? | raw, unused in flight path found |
| DragMinFactorOfMaxThrust | 0xf0 | 0.2 | – | raw, unused found |
| FlapsDragIndex | 0xf4 | 76 | DI | ×1e-4 |
| SpeedBrakesDragIndex | 0xf8 | 320 | DI | ×1e-4 |
| LandingGearDragIndex | 0xfc | 300 | DI | ×1e-4 |
| LandingHookDragIndex | 0x100 | 100 | DI | ×1e-4 |
| ParachuteDragIndex | 0x104 | 0 | DI | ×1e-4 (no reader found: the original chute is visual only; the Real set adds its own chute drag, docs/real-aircraft.md §2.2) |
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
| **RudderK, RudderBeta, RudderStartAccel, RudderStopAccel** (v1.1) | 0x16c,0x170,0x174,0x178 | 5, 0, 0.5, 0.5 | – | raw (β channel gains, §15.2.6) |
| StartMoveStickCenterG | 0x13c | 2 | g | raw |
| MapCenterStick | 0x138 | 0 | g | raw |
| OverGThresh | 0x168 | 6.7 | g | raw (getter id 27 of `FUN_005a9280`; only used for the Betty "Over G" voice, §13) |
| Multiplayer{Roll,Pitch}{K,Beta} | 0x150/0x154/0x158/0x15c | 9,0,9,0 | – | network clone smoothing only |

The four rudder keys are new in v1.1 (read after AlphaBeta; the params stride grew `0x17c` → `0x18c`, and the derived
fields below moved up by 0x10: load counter `0x16c` → `0x17c`, stick-centre line `0x170/174/178` → `0x180/184/188`).
v1.1's `bdgen.dat` sets only **RudderK** (7.5 F-4 / Mirage / Kfir / Lavi, 5.5 F-15 / F-16 / MiG-29, 6.25 MiG-23); the
other three keys are absent everywhere, so the defaults apply. **A v1.0 `bd.ibx` has none of them: the v1.1 exe (and our
port) then runs the β channel on the defaults 5 / 0 / 0.5 / 0.5** — that is how v1.0 data plays with the v1.1 logic.

Thrust offsets: MinMachMinAlt0/1 = 0x114/0x118, MinMachMaxAlt0/1 = 0x11c/0x120,
MaxMachMinAlt0/1 = 0x124/0x128, MaxMachMaxAlt0/1 = 0x12c/0x130 (defaults 12012.6, 19230.4, 1629.7,
2691.0, 11128.1, 30873.2, 2394.7, 8670.2 lbf). `P+0x84` (int) = vibration allowed
(pref `DAT_00699424[0xe]==0` or multiplayer). `P+0xdc` = 10° (rad), constructor `FUN_005b2510`.

Derived at load time (envelope `E` = `FUN_005b5490(FlightEnvelopeFile)`, functions in §3):
```
v1 = Vmin(330 m, 1 g);  vG = Vmin(330 m, MaxG)          // FUN_005b5070, alt 330 m (0x43a50000)
qS1 = qS(330 m, v1);   qS2 = qS(330 m, vG)               // §2
W   = EmptyWeight_kg * 9.806
P.e4 (0xe4) = W / qS2                                     // "CL at alpha=0"
P.e8 (0xe8) = (W - qS1*e4) / (qS1 * MaxPosAlpha)          // dCL/dalpha
P.14c = Vmin(10000 m, 1 g)
P.140 = Ceiling(StartMoveStickCenterG);  P.144 = Vmin(3048 m, StartMoveStickCenterG)
P.180 = (MapCenterStick - 1)/(10 - P.144);  P.184 = MapCenterStick - P.180*10   // stick-centre line (v1.0 P.170/174)
```
Global slopes set in `FUN_005b1f30` (copies P into S channel limits):
`gRateSlope(V) = G_Rate·(0.01 + 0.99·(V-20)/200)` i.e. `a=G_Rate·0.99·0.005, b=G_Rate·0.01-20a`;
same for G_RateForAoa; roll factor `k=0.00475, c=-0.045`; alpha-dynamics speed factor
`0.004995·V − 0.0989`; β gain factor `k = max(BetaRate·0.0025·V, 0.25·BetaRate)/BetaRate` below 400 m/s (§15.2.6).

## 2. Atmosphere — `FUN_005b3fd0(alt, V, *mach, ΔT=0, *rho, *)` @005b3fd0
```
alt = clamp(alt, -500, 20000)
H   = (1 - alt*1.5731270e-7) * alt          // geopotential
T0  = 288.15 + ΔT
if H <= 11000: T = T0 - 0.0065*H;  θ = T/T0;  p = θ^5.255876 * 10332.27
else:          T = 216.65 + ΔT;   θ = T/T0;
               p = θ^5.255876 * 10332.27 * exp((alt - 11000) * (-0.03404 / T))   // note: alt, not H
mach = V / sqrt(401.8743 * T)
rho  = 1.225 * (p / 10332.27) / θ           // p in kgf/m²
qS(V) = 0.5 * rho * V² * WingArea_m2        // FUN_005b4100
```

## 3. Flight envelope (`16.dat`) — `FUN_005b5490`, `FUN_005b5fe0`, `FUN_005b5bf0`
Parsing: lines are read with `sscanf("%d %d %d", g, vel_kt, alt_ft)`; **a line with a decimal (e.g.
`0 70.3 13000`) returns 2 and is silently skipped**. vel ×0.514722 → m/s, alt ×0.3048 → m;
`AltitudeStep` ×0.3048. Rows grouped per g (consecutive equal g); first alt of each graph must be 0.
Graphs are indexed by **integer g** (index = g + idx0, idx0 = graph index of g=0; ≤14 rows each incl. the sentinel, not
bounds-checked; a new graph starts at every *change* of g in file order);
a sentinel row (alt 30000 **m**, last vel) is appended; `ceilAlt[g]` = alt of last real row;
pad graphs below min g / above max g copy the edge graph with max(alt−1, 0), vel+1. `gmin = min(0, all g)`, `gmax` = last g.
Exact algorithm (all functions, edge cases, F-16 check): §15.9.

* `Ceiling(g)` `FUN_005b53b0`: clamp g to [gmin,gmax], `i=trunc(g)`, linear interp of `ceilAlt`
  between graph i and i+1 (g>0) or i−1 (g≤0).
* `Vmin(alt,g)` `FUN_005b5070` (g≥0) / `FUN_005b5240` (g<0): clamp g; `alt=clamp(alt,0,Ceiling(g)-1)`;
  graph A=trunc(g), graph B=A+1 (A−1 for g<0). In A take segment i with `altA[i] ≤ alt < altA[i+1]`,
  in B take last row j with `altB[j] ≤ alt`; fit a plane through `(altA[i],A,vA[i])`,
  `(altA[i+1],A,vA[i+1])`, `(altB[j],B,vB[j])` (`FUN_005bf2a0`) and evaluate at `(alt,g)`.
* Second pass `FUN_005b5bf0` builds, for every altitude level `L_k = k·AltitudeStep`, a list of
  `(g, Vmin(L_k,g))` points (linear interp of each graph between its rows); separate lists for g≥0
  (`E+0x44`) and g≤0 (`E+0x58`), assumed sorted by velocity.
* `GLimit(alt, V, gcmd)` `FUN_005b58e0` returns code + limit:
  `k=max(0,trunc(alt/step))`; if `k+1` beyond list count → code 2 (`lim=-1`).
  Look up bracketing points by velocity (`FUN_005b6400`) in levels k and k+1.
  If V is above all points of level k: `alt ≤ Ceiling(gcmd)` → code 3 (no limit), else code 4 with
  `lim = FUN_005b5840`: linear in alt, `gmax` at `Ceiling(gmax)` → 0 at the g=0 ceiling (sym. for
  negative), clamped at 0 (confirmed, §15.9). If V below all points of level k **or** k+1 → code 0
  (stall). Otherwise code 4 with `lim` = plane through `(L_k,Vlo,glo)`, `(L_k,Vhi,ghi)`,
  `(L_{k+1},V',g')` evaluated at `(alt,V)`; forced to 0 if its sign differs from gcmd.

## 4. Aero update (1 Hz + events): `FUN_005b3af0` @005b3af0 (airborne) / `FUN_005bac40` (on ground)
Inputs: `alt=Z`, `V=|v|` (not capped in the 1 Hz path; the 5 Hz path uses the capped `5a68a0`), throttle `thr=S+0x2dc`, stick pitch
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
beta_cmd = (ru + 10*(S+0x428 - S+0x42c)) * MaxBeta           // FUN_005b4910 (asym. stores; UNCERTAIN)
rollRate_cmd = MaxRollRate * sr
```
Then (`FUN_005a70f0`): store T→S+0x1d4, D→S+0x1dc, m→S+0x1d8; set ramps
`S+0x1e0 := ramp(L)` and `S+0x200 := ramp(Lnoflap)` with rates `G_Rate·m·9.806` and
`G_RateForAoa·m·9.806` if `V ≥ 220`, else `gRateSlope(V)·m·9.806` (1 % at 20 m/s … 100 % at 220);
ramp limits `[MaxWeight·(MinG−1)·g, MaxWeight·(MaxG−1)·g]`. RPM ramp `S+0x1b0 := 100·rpm` at 15 %/s.
Fuel ramp `S+0x430` toward 0 at `ff` kg/s (limits [0,FuelWeight]). Roll channel (type B at S+0x80,
startAccel=RollAccel, stopAccel=StopAccel, rates ±MaxRollRate) gets
`targetRate = rollRate_cmd · kroll`, where
`Veff = ((-1.305e-5 + 3.1825e-9·V)·alt + 1.0017)·V − 3.122`, `kroll = Veff<220 ? 0.00475·Veff−0.045 : 1`
(no lower clamp). Before the new target is set the roll channel is re-based with `pos := attitude roll`.
Alpha dynamics via `FUN_005aa3a0` (§5), beta via `FUN_005aa700` (§5). The `cfg` flags and the exact order of all
steps are in §15.1 (the brake flag comes from ramp `S+0x340`, the gear flag from the gear ramp `S+0x320` at 0).

### 4.1 Thrust — `FUN_005b4120` @005b4120
```
a = clamp(alt*5e-5, 0, 1)            // alt/20000 m
M = clamp(mach/1.2, 0, 1)            // mach*0.8333
if flags&2: thr = 0
if (flags&4 && flags&8) || !engineOn(S+0x1d0) || flags&2:  T=0, stage=0, k=0, rpm=0 → fuel
if flags&0x80 && flags&0x100 && thr>=0.75: thr = 0.74
if hasAB (P+0x164 && not AI-mode):   // noAB = !HasAfterBurner || (FUN_005c89f0()∉{0,7,8})
    thr<0.75:  k = 0.05 + 0.7432432*thr, stage 0     // thr 0.74 ("military") → k≈0.60
    thr<0.875: k = 0.875, stage 1 (AB1);  else k = 1.0, stage 2 (AB2)
else:  k = (thr-0.2)*1.25; stage = thr<0.75?0 : thr<0.875?1:2
if flags&4 || flags&8: k *= 0.5
T0 = lerp(k,MinMachMinAlt0,..1); T1 = lerp(k,MinMachMaxAlt0,..1)
T2 = lerp(k,MaxMachMinAlt0,..1); T3 = lerp(k,MaxMachMaxAlt0,..1)
T  = lerp(a, lerp(M,T0,T2), lerp(M,T1,T3)) * 4.4479       // N
rpm = 0.6 + 0.4*thr*1.3513514      (engine off: 0)          // 1.0 at thr=0.74
ff  = thr * FuelFlowAtMaxThrust;  if k <= 0.6: ff *= 0.25;  if flags&0x40: ff += 0.25*FFmax
if unlimited-fuel pref (DAT_00699424+0x44): ff = 0
```
"0"/"1" suffix = value at k=0 / k=1 (full AB2); interpolation is linear, so idle (k=0.05) ≈ 5 %.

### 4.2 Commanded G / lift — `FUN_005b4470` @005b4470
`bStall` (stalls enabled) = pref `+0x38 == 0` (always true in multiplayer). `latched` =
stall/limit event within the last 3.0 s (`S+0x2f8` timestamp, set/cleared by `FUN_005a9e60`).
```
if latched && bStall: return L=0, dragX=1.2        (departure: no lift up to 3 s)
c = 1;  if V < P.144: c = P.180*V + P.184           // stick-centre shift (StartMoveStickCenterG/MapCenterStick)
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

### 4.3 Drag — `FUN_005b4800` @005b4800 (checked in disassembly)
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

## 5. Accel/rate update (every 0.2 s) — `5a4230` (disasm), `FUN_005b3ef0`, `FUN_005b4930`
```
t = now;  sample L = S+0x1e0(t), Laoa = S+0x200(t), att = orientation(t) (§6)
alphaTarget = clamp((Laoa - e4*qS)/(e8*qS), MaxNegAlpha, min(MaxPosAlpha, LimitAlphaVisual))  // FUN_005b4c60
Fbody (y fwd, z up, x = right wing) with α = **αT** (the target above, not the α channel) and β = fmod(β(t)) of the
channel S+0x260 in the 5 Hz path; the 1 Hz/event path uses α = S+0x220(t) and β = the commanded β_cmd (§15.2.2):
  x = D*sin β + 5*V²*β
  y = T + L*sin α - D*cos α*cos β
  z = L*cos α + D*sin α*cos β
M = FUN_005ba740(pitch=att[0], roll=att[1], heading=att[2])   // cb=cos b etc.
  M = [[cH cP, -sH cP, sP],
       [sR sP cH - sH cR, -cH cR - sR sH sP, -sR cP],
       [sH sR + cR sP cH,  cH sR - cR sH sP, -cP cR]]
r = Mᵀ·(y, x, -z);  Fworld = (-r1, r0, r2)                    // FUN_005ba690; world X east, Y north, Z up
acc = Fworld/m + (0, 0, -9.806)
for axis in X,Y,Z: p=p(t); v=v(t); set(p0=p, t0=now, v, a=acc_axis)   // exact constant-accel steps
```
On ground (`S+0x2a0`): `FUN_005bb060` instead, and if vertical accel < 0 the Z velocity/accel are
zeroed (stays on runway). Also re-bases the lift ramps, the roll channel (pos := att roll) and alpha.

Alpha dynamics (`FUN_005aa3a0`, 1 Hz; type B at S+0x220, target S+0x258 = alphaTarget):
`f = V≥220 ? 1 : max(0.001, 0.004995V−0.0989)`; channel startAccel=AlphaStartAccel·f,
stopAccel=AlphaStopAccel·f, rates ±MaxAlphaRate·f, K=AlphaK·f, B=AlphaBeta·f;
`err = wrap(alphaTarget − α)`, `damp = B·rate·MaxRate` (×0.5 if |rate|>π),
`targetRate = clamp(err/π·K/MaxRate − damp, −1, 1)·MaxRate`.

Beta (`FUN_005aa700`, v1.1): a **second-order channel of the α class** at `S+0x260` driven toward `beta_cmd` by the α law
with the gains RudderK / RudderBeta / RudderStartAccel / RudderStopAccel, all scaled by
`k = V<400 ? max(BetaRate·0.0025·V, 0.25·BetaRate)/BetaRate : 1`, no ±MaxBeta clamp (§15.2.6). It runs at 1 Hz in the
air, at every 5 Hz tick (also on the ground and, new in v1.1, in the spin); on the ground the 1 Hz update steps it with the
stored gains. (v1.0 `5a78f0`: a constant-rate ramp `S+0x280` at `k·BetaRate` clamped to ±MaxBeta, threshold 375 m/s,
plus a HUD-only ramp at `S+0x260`; both are gone.)

## 6. Attitude (render/orientation) — mode object `veh+0xc6c`, vtable `0x611db0`: `5b9250`/`5b9530`
Normal mode: sample v(t) (type C velocities), roll φ(t) (S+0x80), α(t), β(t); then
```
f = v/|v|;  w = S+0x08 (LEFT-wing vector saved at the last 1 Hz or 5 Hz update, with φ_ref = S+0x18)
w = rotate(w, axis n, φ - φ_ref)            // n = nose of the saved Euler S+0x14..0x1c (v1.1; v1.0: axis f)
f = rotate(f, axis w, -α)                   // nose above velocity
f = rotate(f, axis w×f, β)                  // (was written f×w here; the code builds w×f explicitly @5b98eb)
heading = atan2(f.x, f.y);  pitch = asin(f.z);  roll = ±acos(clamp(−w_local.x,−1,1)) (sign by w_local.z)
```
Exact version with the frames and helpers: §15.3.
`FUN_005aa330(pitch,roll,heading,S)` stores the Euler angles at S+0x14 and `w = Mᵀ·(−1,0,0)`
mapping at S+0x08. Other modes (`veh+0xc70` → `FUN_005aab90`, `veh+0xc7c` → `FUN_005ac5d0`) are
special departure/spin/tail-slide manoeuvres — see §15.5.
The Rodrigues helpers are the v1.1 optimised copies `459ac0` (add), `459b30` (cross), `459b80` (dot), `459ba0` (scale).
Airborne init (`FUN_005a5820`): `v = (V sinψ, V cosψ, vz)`, throttle 0.74, engine on; full rules (air/ground
decision, gear, flaps, brakes, RPM, lift ramps) in §15.6. The re-placement `FUN_005a4d40` uses throttle 0.7.

## 7. Ground roll — `FUN_005bac40` (replaces §4 while `S+0x2a0`≠0)
```
easy = pref+0x1c || pref+0x20   (DAT_00699424: Invulnerable || No crashes, §15.7)
L = 0.5*Lift(...);  L += |L|*FlapsLiftCoef*flaps*3.4158838
if !((V > 74.53 || sp > 0.5) && (gearDown || AI || pref+0x3c || easy)): L = 0
mu = brakes[6] * WheelsBrakeDI * (AI ? 4 : 1) + DAT_008454a8 (fric1 = 0.05, §14.2)   // AI factor v1.0: 2
if !gearDown && !AI && !easy: mu = 20                      // belly landing
D = Drag(alpha=0, n=L/(m g)) + 0.5*mu*(m*9.806 - L);  D = max(D,0);  if V > 1: D *= 0.8   // v1.0: 0.7
T = max(T,0);  nose-wheel yaw rate = clamp(sx*V*K/74.53, ±K), K = DAT_008454d4 = 20°/s = 0.3490659 rad/s
(0 if gear up; 0 if |rate| < 1e-4).  sx = stick X S+0x2e8, NOT the rudder (see "Nose-wheel steering input")
```
The single "Brakes in/out" key drives ramp `S+0x340` (motion 8, `FUN_0059ffc0`, range 0..0.855, 0.5/s), used as
speed brake in the air and wheel brake on the ground. Motion 7 = gear `S+0x320`, motion 9 = `S+0x360` (→ HookDI,
UNCERTAIN: hook). The earlier "S+0x360 = brakes" was wrong (§15.1). The nose-wheel yaw is not instant: it goes
through ramp `S+0x2a8` at rate |BetaRate| and is clamped to ±MaxBeta (§15.2.6).

### Nose-wheel steering input
**Rule: on the ground the nose wheel is steered by the stick's roll axis (`S+0x2e8`), always, with no
conversion step. The rudder input is ignored on the ground.** This matches the instructor line "The stick
controls the nose wheel steering." Nothing converts stick X into a rudder input (motion 5), either on the
ground or as an airborne auto-rudder.

Evidence (all checked in objdump):
* **Call chain, stick X → nose wheel.** `5a4230` @5a7720–5a779a pushes the args of `FUN_005b3af0`
  (`ecx` = FM params). Stack arg 6 is `S+0x2a0` (ground flag, tested as `param_7`). Stack args 15/16/17 are
  `S+0x2e4` (stick Y), `S+0x2e8` (stick X) and `S+0x2ec` (rudder); arg 18 is the vehicle.
  The ground branch @5b3b0c–5b3bfe forwards 30 stack args to `FUN_005bac40` (`ret 0x78`). b0a20 args 6/7 and 29
  are dropped, so 7a20 stack arg 14 (`param_15`) = b0a20 arg 16 = **stick X**, `param_14` = stick Y and
  `param_16` = rudder. Ghidra's display of these argument lists is shifted by one; the push order is authoritative.
  In 7a20 the yaw rate is computed @5bafc6: `fld [esp+0x5c]` (entry+0x38 = `param_15`) `fmul [esp+0x2c]` (V)
  `fmul [0x8454d4]` `fdiv [0x612440]` (74.53). `param_16` (rudder) is never read in 7a20.
  The earlier notes here said "`ru`"/"rudder"; that was wrong.
* **The rudder handler ignores the ground.** Motion 5 `FUN_0059f5a0` @59f5c6 stores
  `S+0x2e0`/`S+0x2ec = clamp(in+0x10, ±1)` and starts the ×0.3926 ramp only if `S+0x2a0 == 0`. On the ground
  the command is dropped, and `S+0x2ec` keeps its last airborne value. The only other writer is the init
  @5ba252, which sets it to 0. In the air, `S+0x2ec` feeds `FUN_005b4910` (@5a4b86 in `5a4230`), which
  returns `(ru − x·k)·P+0xb8`, the β command for the β channel (§5).
* **Stick handler.** Motion 1 `FUN_0059f3d0` writes `S+0x2e8 = clamp(in+0x14, ±1)` (X) and
  `S+0x2e4 = −clamp(in+0x10, ±1)` (Y). It has no ground test. `FUN_0044e470` type 1 sets
  `+0x14 = arg[0]·0.01` and `+0x10 = arg[1]·0.01` (`0x600b2c` = 0.01). The controller `FUN_0044a240` case 1 (@44bd01)
  posts motion 1 with the raw `(x,y)` in the range ±100. When indicator 8 (the autopilot lamp, docs/autopilot.md) is set and
  |x| or |y| ≥ 51, it first clears that indicator. Case 10 posts motion 5. Cases 2/3 fall to the default
  and return (jump table `0x44c714`, index bytes `0x44d390`).
* **K = 20°/s.** `DAT_008454d4` is set by a static initialiser: CRT table `.data 0x6277ac` → `0x5bab70` →
  @5bab80 `K = DAT_008454b0 · 20.0` (`0x61245c`). `DAT_008454b0` is set by initialiser `0x6277a8` →
  `0x5ba9a0` = 1.0° (`0x612450`) wrapped and converted to radians = 0.01745329. So K = 0.3490659 rad/s.
  Ghidra misses both writes.

**Keyboard path (`FUN_004e0b80`, key → `WM 0x532`).** The "Roll left/right" keys send GEV 2 and
"Pitch up/down" send GEV 3. Before sending, `FUN_004e0b80` rewrites both into **GEV 1 (stick)**:
* GEV 2: x = the key's lParam, y = the last keyboard y `DAT_008338f4`; x is stored in `DAT_008338f0`.
* GEV 3: the same with the axes swapped.

So a keyboard-only player steers the nose wheel with **Left/Right arrow** as a full ±1 stick X while the key
is held. The release record sends x = 0.
GEV 2/3 keys are dropped when `this+0x24 && this+0x18`. GEV 10 rudder keys are dropped when
`this+0x2c && this+0x20`. GEV 5/6/9 throttle keys are dropped when `this+0x28 && this+0x1c`.
(Resolved: `+0x18 / 0x1c / 0x20` = the joystick has a stick / throttle (lZ) / rudder (slider 0 or lRz) axis
(`FUN_004e0f90`), `+0x24 / 0x28 / 0x2c` = the Devices page's choices (`FUN_004df4e0`). The DirectInput poller
`FUN_004df560` sends GEV 1 from lX / lY when `+0x24`, GEV 9 from lZ when `+0x28` and GEV 10 from lRz when
`+0x2c`; docs/controls.md §5.) No code path turns the Rudder keys into stick X on the ground,
and none adds rudder from roll.

**Default key table.** `0x64c3c8 + n·0x24`, n = keys.trx line (0-based), 117 records, copied into the
runtime table `0x83b99c` (`rep movs 0x41d` @4f08c0; "defaults" button @511ca5). Record layout:
* +0 press GEV, +4/+8 press arg (x, y); +0xc release GEV, +0x10/+0x14 release args;
* +0x18 key: DirectInput DIK code (ushort), modifier byte at +0x1a (0x22 = Shift, e.g. Shift+W);
* +0x1c: joystick button (0-based, −1 = none; `FUN_004e0dc0`, Controls page "Button n");
* +0x20: listed on the Controls page (not one-shot / held: held keys are the ones with a release
  command). Full table and dispatch: docs/controls.md.

The key code of record k is at `0x64c3e0 + k·0x24`, which is where the `0x64c3e0` in docs/mfd.md comes from.

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

## 8. Controls / keys (dispatcher `FUN_0059f180`, event type → handler)
**Joystick axes → the flight model** (`FUN_004df560`, docs/controls.md §5): the axes reach it through the same
game events as the keys, sent when their integer value changes: stick x = `MulDiv(lX, 200, range) − 100`, y =
`MulDiv(lY, −200, range) + 100` → GEV 1 → motion 1 (`S+0x2e4 = −y·0.01`, `S+0x2e8 = x·0.01`); throttle =
`MulDiv(lZ, −100, range) + 100` → GEV 9 → motion 2 (`t·0.01`, the AB delay below); rudder = `MulDiv(lRz, 200,
range) − 100` → GEV 10 → motion 5. Linear, 1 % steps, DirectInput's 25 % dead zone on x, y and rudder, none on
the throttle; no curve, no filtering. The only smoothing stays the lift ramp (G_Rate) and the rudder ramp.

1 stick (`FUN_0059f3d0`): `S+0x2e4 = −clamp(y,−1,1)`, `S+0x2e8 = clamp(x,−1,1)`; ×0.25 when
input-mode 0x12 active, zeroed by 0x18 (UNCERTAIN meaning). 2 throttle (`FUN_0059f7d0`): clamp
[0,1]; any (player) change first cancels a pending AB request (v1.1); crossing into AB (≥0.75) from below sets 0.74
and schedules the AB value after `max(0,(100−RPM%)·0.0667)` s (`FUN_0059faf0`); any throttle change turns the engine
on (`S+0x1d0`).
3/4 RPM ±5 %: throttle ±0.0925 (`FUN_0059f330`/`c6e0`). 5 rudder (`S+0x2ec`, ramp ×0.3926; ignored on the ground, see §7).
6 flaps (`S+0x300`, ×0.33 target for aircraft type 100), 7/8/9 ramps `S+0x320/0x340/0x360`.
Throttle presets (keys 1–8, key-table records 7–14) send GEV 9 with p1 = 0, 10, 19, 38, 56, 74,
78, 100; the controller (`FUN_0044a240` case 9 → `FUN_0044e470` motion 2) makes throttle = p1 · 0.01:
idle 0, 65 % 0.10, 70 % 0.19, 80 % 0.38, 90 % 0.56, military 0.74, AB1 0.78, AB2 1.0 (docs/controls.md). Key names are loaded from `keys.trx` into `0x833900` (100-byte stride) by
`FUN_004e3c70`; the default key→command table is at `0x64c3c8` (record layout in §7 "Nose-wheel steering input").

**Keyboard stick (traced, v1.0 = v1.1).** A pitch / roll key press sends GEV 3 / 2 with ±100, its release 0
(`FUN_004e0b80`, per DirectInput key event, rewritten to GEV 1 with the other axis's last keyboard value). The
controller `FUN_0044a240` case 1 posts motion 1 at once (it only first clears indicator 8 when |x| or |y| ≥ 51);
motion 1 `FUN_0059f3d0` stores `sY = −y·0.01`, `sX = x·0.01` and the event runs UpdateAeroData (§0). So the
stick is **full at once** and centred at once: no ramp, no spring, no curve, no keyboard-specific scaling
(the joystick poller `FUN_004df560` is linear, `MulDiv` to ±100, no curve either). Commanded g jumps to
`c + sY·(MaxG−1)` (§4.2); the only smoothing is the lift ramp, `G_Rate` g/s (× `gRateSlope` below 220 m/s:
≈ 4.4 g/s for the F-16 at 350 kt). Peak g of a Down-arrow (pull) tap, 10,000 ft, 350 kt, military (port,
original / real data; push taps are the mirror down to MinG):

| tap | F-16 | F-15 | F-4 | Kfir | Lavi | Mirage | MiG-29 |
|---|---|---|---|---|---|---|---|
| 0.1 s | 1.44 / 1.46 | 1.44 / 1.46 | 1.25 / 1.27 | 1.34 / 1.36 | 1.45 / 1.46 | 1.34 / 1.36 | 1.35 / 1.38 |
| 0.3 s | 2.31 / 2.38 | 2.33 / 2.40 | 1.75 / 1.81 | 2.01 / 2.08 | 2.35 / 2.39 | 2.01 / 2.07 | 2.07 / 2.13 |
| 0.5 s | 3.18 / 3.31 | | 2.26 / 2.35 | | | | |
| 1.0 s | 5.36 / 5.61 | 5.43 / 5.68 | 3.52 / 3.71 | 4.38 / 4.59 | 5.49 / 5.64 | 4.38 / 4.58 | 4.56 / 4.76 |

So in the original an F-16 key tap longer than ≈ 0.45 s gives 3+ g. (Our former invented ramp, 2.5 /s out,
4 /s back, gave *more*: 0.3 s → 2.82 g, 0.5 s → 3.83 g, because the stick was still off centre after the
release while the lift ramp kept rising.) `tests/godot/test_keyboard_stick.gd`.

## 9. Misc
* g = 9.806 everywhere; lbf→N 4.4479; dt clamps: ramps 3.5 s, angles/axes 1.1 s.
* Stall shake/buffet: `FUN_005a9e60` sets `S+0x1a8/0x1ac = 0.5` while the vibration flag is set (only if
  `veh+0xc60 == 0`), and starts/stops the force-feedback effect "StallShake" with the stall latch (§15.2.4).
* Over-G: `OverGThresh` (getter id 27) is compared with the current G in the player controller
  (@449525). Above it, the "Over G" Betty voice plays every 4 s. No over-G damage exists. See §13.
* Ceiling/Vmin extras: `P+0x14c` (Vmin 1 g @10 km) used by AI only (UNCERTAIN).

## 10. Deviations in our port (`crates/iaf-flight`)
The airborne branch, modes, landing check, start rules, throttle rules and preferences follow §15 (checklist §15.11).
What still differs:
* **"Better physics"** (Preferences, off by default = the original). The original stays the default; each item below
  is an opt-in fix of an original quirk (§15.10 "BP") with its own switch: `Aircraft::better: BetterPhysics` (one bool
  per item, id in brackets; `BetterPhysics::OPTIONS` lists the ids with English labels; `none()` = default, `all()`).
  `set_better_physics(on)` switches all of them (the game's single setting so far); `set_better_option(id, on)` one
  (Godot: `IafFlight.set_better_option(id, on)`, `IafFlight.better_options()`). The start options act when set at t = 0.
  * **1 g hold** [`flight_path_hold`] (§4.2): the original `cos(pitch)/cos(roll)` makes the jet slowly dive/climb at high speed (α < 0 tilts
    the thrust). BP holds the flight-path angle γ and subtracts the thrust's vertical share:
    `g = cos γ / cos φ − T·sin α /(m·g)`.
  * **Force angles** [`force_angles`] (§15.2.2): the original decomposes with the α *target* at 5 Hz (free forward force `L·sin(αT − α)`
    during a pull) and the *commanded* β at 1 Hz. BP uses α(t) and β(t) in both paths.
  * **Airborne start** (§15.6.4): MaxWeight·g gives a short up-jolt (F-16: ≈ +1.9 m/s vz in the first 0.2 s); BP
    [`start_lift`] starts the lift ramps at m·g. The original also starts the RPM at 70 % while the throttle is at
    military (the engine then spools to 100 %, and the afterburner lights only after `(100 − 70)/15` = 2 s); BP
    [`start_rpm`] starts it at the start throttle's value. And it starts the α channel at 0 (the nose rises by the trim
    α during the first second); BP [`start_alpha`] starts α at its trim value.
  * **Landing check** [`landing_limits`] (§15.6.1): sink limit 4 m/s (≈ 13 ft/s, real gear) instead of 40 m/s, a tail-strike limit of 15°
    nose-up (both ×2 with Easy landing; sink ×0.25 with the gear not down), and the current attitude instead of the one
    saved at the last update. Crash reasons "sink rate" / "tail strike".
  * **Spin** [`spin_fixes`] (§15.5): "No spins" blocks entry (original: it skips the arm step so spins start *earlier*); the entry
    condition must hold for 1.2 s (original: the second consecutive qualifying update); during the spin drag bleeds the
    horizontal speed and the descent settles near 65 m/s (original: horizontal velocity frozen, `acc.z = min(0, 0.04V − g)`
    with the total speed, so a spin above 245 m/s never descends); the velocity is kept at recovery (original: snapped to
    nose·V); no yaw rotation (s1 = 0) is recoverable; the yaw-rate sign uses the channel's own τ. v1.1 changed only the
    recovery slope (π/(2.2·MaxBeta), was 1.8) and added the β update in the spin; both are the original behaviour now
    and apply in both modes. Everything this option fixes is unchanged in v1.1, so it stays as it is.
  * **Fly-by-wire departure** [`fbw_departure`] (F-16 type 100, Lavi 140; §10.1): the original never lets them depart (early return in
    the spin entry). BP gives them the FLCS deep stall instead of the spin; the other jets keep the (BP) spin.
  * **Lift-ramp rate factor** [`lift_rate_floor`] (§15.10 item 14): the original's factor `0.01 + 0.99·(V − 20)/200` has no floor, so below
    18 m/s it turns negative and its magnitude grows again (the lift changes as fast at 0 m/s as at 20 m/s). BP floors
    it at 1 %.
  * **Roll command at very low speed** [`low_speed_roll`] (§15.10 item 13a): `kroll = 0.00475·Veff − 0.045` has no lower clamp, so below
    Veff ≈ 9.5 m/s the stick rolls the jet the wrong way. BP clamps it at 0.
  * **Nose-wheel ×4 lift** [`no_nose_wheel_lift`] (§14.5): in the original data set a nose-wheel side force above 0.1·L (V > 20.6 m/s)
    multiplies the vertical lift by 4, which throws the jet into the air when steering during the take-off run. Not
    physical; BP leaves it out (the real data set already does, with its geometric steering).
  * **Ground effect** [`ground_effect`] (not in the original): the induced drag `K·CL²` is multiplied by McCormick's
    `φ = (16h/b)² / (1 + (16h/b)²)` with h = height of the aircraft origin above the terrain and b = span (F-16:
    φ = 0.5 at 0.6 m, 0.8 at 1.3 m, 0.94 at 2.5 m, ≈ 1 above ~10 m; on the wheels h = the gear clearance, 1.69 m →
    0.9). It lengthens the flare/float and shortens the take-off run slightly. Lift, α and the envelope are unchanged
    (the model commands g, not CL). Like all drag it is refreshed by the 1 Hz / event update.
* **Not changed by better physics** (original quirks that stay in both modes):
  * §15.10 item 14, the slope globals: the original's lift-ramp / β-gain slopes below 220 / 400 m/s come from the **last
    aircraft type set up** (shared globals). Our `Aircraft` keeps its own parameters, so every jet uses its own slopes in
    both modes; reproducing the leak would need a process-wide "last type" and only matters once several types fly the
    FM (only the player's jet does).
  * §15.10 item 15, the "Tornado" map-edge push-back (acceleration ramps that never decay): not ported (no map-edge
    terrain flags).
  * The 3 s zero-lift stall latch itself (§15.2.4) — the model's only stall — is kept; the F-16's deep stall starts
    from it.
* **Envelope** (§15.9, `envelope.rs`): exact algorithm, computed in f64 instead of float32/x87 (UNCERTAIN: last-digit
  rounding). Slot indices are clamped for broken files (the original does not bounds-check). Checked against a Python
  rebuild (`tools/envelope_ref.py`, run at test time on a synthetic text and on every `md/*.dat` of the local install) and the F-16 values of §15.9.
* **Real data set only** (not original): `stall_floor` (also caps the GLimit), `wave_drag`, the geometric nose-wheel
  steering (no ×4 lift quirk), §11.
* **Host (game/terrain/terrain_view.gd)**:
  * Airborne start speed 282.84 m/s along the heading, vz 0: the activation `FUN_004a9100` passes the velocity
    (200, 200, 0) (docs/ai.md §7.1).
  * Near-base and runway-start-point tests (§15.6.4): the iaf.ibx airbases (`551280`, docs/ai.md §9, `IafFlight.start_rule`);
    mission 311 (1.7 km from Ramat David's lineup point) starts with the engine off.
  * `--at` / free flight: always airborne (debug starts).
  * Terrain type flags (water, rough ground, runway, map edge) do not exist in our terrain data: water/rough are passed as
    false (UNCERTAIN), so the water/rough-ground crashes, the `S+0x2c8` surface states, the OutRunway effect and the
    "Tornado" push-back are not active. The slope for the landing check comes from `height_at` samples ±3 m.
  * No force feedback, no touchdown/screech sounds, no crash explosion. On a crash the flight model freezes and the
    mission runtime runs the player's death (destroy event, role rules, flight ends after 5 s → debrief, §5 of
    docs/mission-runtime.md); without a mission the flight ends after 5 s.
  * The cockpit gear lamps keep the controller's 2.0 s leg timer (§12) while the FM gear ramp takes 3.1 s, as in the
    original.
* **Z-axis limits in the spin**: v1.1 re-bases Z in the spin's stay branch through `5adae0`, which clamps the height to the
  Z-axis limits [−1500, 30000] m; our axes have no limits (never reached in flight).
* **Sampling**: every channel uses its own base time (the original samples all with the X-axis τ, §15.10 13d; the
  channels are re-based together, so this differs only between updates), and angles are wrapped to (−π, π] instead of
  `fmod(x, 2π)`. The spin's yaw-rate sign keeps the axis-τ quirk (off with better physics).
* Validation against public data for every flyable jet (docs/real-aircraft.md): `cargo test --release -p iaf-flight --test validation -- --nocapture`.
  The neutral-stick row starts at 350 kt in both modes and measures from 5 s after the start (the original's start
  up-jolt is not part of the 1 g hold). The "climb (Ps)" row starts at 320 kt, waits until the afterburner is lit (the
  original's light-up delay, 2 s from the airborne start's 70 % RPM) and the jet is at 350 kt, then measures over 1 s.
  Rows with "better physics" are shown under the original ones. The "rudder step" row (full pedal 4 s at 350 kt, then
  neutral) shows the v1.1 β channel: time to 90 % of MaxBeta, β at the end of the hold, the undershoot after release.
  To check v1.0 data, point `IAF_INSTALL` at an install whose `resource/md` has no `bdgen.dat` / `*gen.skp` and no
  `v1.1` directory beside it (the loader falls back to `bd.ibx` / `<n>.dat`, the rudder keys to their defaults). Only the 1 g hold row is a physics quirk that BP fixes
  (original +1,400 ft/min climb at 540 kt → level); the other OFF rows (weights, thrust, stall speed, roll rate, Ps,
  fuel flow) are the 1998 data and belong to the real data set (§11).

### 10.1 Fly-by-wire departure: the deep stall (better physics, F-16 and Lavi)
Not in the original (`5aab90` returns at once for types 100 and 140, so they cannot depart; §15.5). A plausible model,
**not extracted**: numbers are estimates from public sources, marked below.

**The real thing.** The F-16's flight control system (FLCS) limits AoA to ≈ 25° (with a g limiter), so a normal pull
cannot stall or spin it and the yaw-rate limiter makes it spin resistant. Its known departure is the **deep stall**:
the relaxed-stability airframe has a second stable pitch trim point at ≈ 60° AoA (NASA TP-1538 wind-tunnel data, the
basis of the JSBSim/FlightGear F-16 model: Cm stays ≥ 0 around 50–60° AoA even with full nose-down stabilator). It is
entered when the airspeed runs out nose-high (vertical/near-vertical zoom, low-speed high-AoA manoeuvring, aft CG or
asymmetric stores) so that the limiter can no longer hold the AoA. In it the jet "hangs" at high AoA with the nose near
the horizon, pitching back and forth, with little airspeed and a high sink rate, and holding full forward stick does not
recover it. The recovery (T.O. 1F-16-1): the manual pitch override (MPO) switch and "rocking" the stick in phase with the
pitch oscillation until the nose falls through, then the dive pull-out.

**Model** (`Mode::DeepStall`, `deep_stall_entry` / `deep_stall_hook` in `aircraft.rs`; reuses the spin's mode slot,
its pitch/roll/yaw channels and the stall latch):
* **Entry** (aero updates, airborne): the stall latch is set (the envelope's code 0/2, i.e. below the lowest speed of
  the envelope, §15.2.4), the nose is ≥ 30° up and V < Vmin(alt, 1 g). "No spins" or "No stalls" prevent it. In
  practice a zoom climb held near vertical until the speed is gone; a normal pull at any speed or a loop does not
  depart.
* **Attitude**: mean pitch → γ + 60° (the trim AoA above the flight path), clamped to [−45°, 85°], at 20°/s — so the nose
  first hangs high while the jet stops and falls, then settles near the horizon; plus pitch rocking `A·sin(2πt/4 s)`
  (A = 8° by itself), wing rock ±10° (5.3 s) and heading wander ±5° (6.7 s). The HUD α is pitch − γ (≈ 60°).
* **Forces**: a normal force `N = CN·qS` with CN = 1.5 (flat-plate-like, TP-1538 order of magnitude), split as drag
  `N·sin 60°` along −v and lift `N·cos 60°` perpendicular to v toward the jet's up axis, plus thrust along the nose and
  gravity; axes updated at both the 1 Hz and the 5 Hz update. The path settles near γ = −60° at the speed where N = W:
  F-16 at 23,000 lb at sea level ≈ 63 m/s along the path, ≈ 55 m/s (≈ 11,000 ft/min) down, faster at altitude. Power
  flattens it (military ≈ −35°, ≈ 8,000 ft/min) but does not recover it. The load factor shows N/W ≈ 1.
* **Recovery**: the stick moved in phase with the pitch rate (pull while the nose rises, push while it falls; > 50 %)
  pumps the rocking amplitude up at 5°/s (to 50°), against the phase damps it at 5°/s, otherwise it decays at 2°/s. A
  steady push or pull therefore does nothing on average. When A ≥ 20° and the nose is less than 25° above the path (the
  FLCS AoA limit), the FLCS takes over again: normal mode, the velocity kept, α continues from the nose-to-path angle,
  the stall latch cleared. From a sea-level-ish entry a few rocking cycles (≈ 8 s) and ≈ 300 m, plus the dive
  pull-out. Touchdown ends it (the landing check decides).
* **Lavi**: the same numbers (no public high-AoA data; canard-delta FBW, UNCERTAIN whether it had a deep stall at all).
* UNCERTAIN (estimates): the 60° trim AoA and CN, the entry thresholds (30° pitch, 1 g Vmin), the oscillation periods
  and amplitudes, the pumping rates; descent rates reported for real F-16 deep stalls are of the same order
  (≈ 10,000 ft/min class) but were not checked against a primary source.

## 11. Data sets (`crates/iaf-flight/src/data_set.rs`) — chosen before the flight
* **Original**: the 1998 numbers as shipped — the v1.1 files (`bdgen.dat`, `<n>gen.skp`, XOR-encoded) when the
  patch output is present, else v1.0's (`iaf_flight::read_md`; v1.1 changes: docs/real-aircraft.md §1).
* **Real**: one table row per flyable jet (F-16, F-15, F-4 / Kurnass 2000, Kfir, Lavi, Mirage) with public
  real-world values; fields left out keep the original. Per jet: weights, fuel, thrust (SL static full AB, military
  ratio via `Params::dry_thrust`), fuel flow at AB and military (`Params::dry_fuel_frac`), roll, g limits, wing
  area, 1 g stall floor (Vmin ≥ floor·√g·√(ρ0/ρ)), pedal nose-wheel steering (angle, wheelbase), and a fit of
  CD0 / transonic wave drag (ΔCD Mach 0.9–1.2) / 20 km thrust to the published max speeds. Values, sources and the
  original-vs-real verdicts: docs/real-aircraft.md. The F-16 row is the earlier F-16 set unchanged (empty 19,000 lb,
  thrust ×1.5, stall floor 118 kt, roll 280 deg/s at 900 deg/s², fuel 16.5 lb/s, wave drag 0.02, NWS ±32°).
  The AI types have rows too, per type (not per shared section): docs/real-aircraft.md §9.
* In-game: Preferences "Flight data" (Original / Real aircraft) or the `--real` launch option.

## 12. Gear lever rules (player controller `FUN_0044a240`, case GEV 0xe)
Generic for every aircraft (no per-type data involved).

**Key → event chain.** Key bindings live in a runtime table at `0x83b99c` (stride 0x24: press cmd,
press lParam, release cmd/lParam, key code `ushort`+modifier at +0x18; defaults at `0x64c3c8`, see §7; keys.trx
only supplies the display names). `FUN_004e0b80` sends `WM 0x532, wParam = GEV code` → handler
`0x4e33c0` (MFC map entry @`0x6057e0`; codes 0x7d–0x89 are UI, all others fall to `0x4e36e5`) →
`FUN_005bf840` (ManageUnit log) → `FUN_004cd3b0` queues a `SimGameEventNode` → the player controller
`FUN_0044a240(this=ctl, gev, int *arg, int forced)`. (UNCERTAIN: the queue→`FUN_0044a240` hop was not
traced. It is inferred from the matching case codes: GEV 5/6 INC/DEC_THROTTLE → motion 3/4, 10 RUDDER → 5,
0xc FLAPS → 6, 0xe LANDING_GEAR → 7.) Motion inputs are built by `FUN_0044e470(buf,type,arg)` (+0 type,
+8 sim time, +0x18 `arg[0]`) and posted through `(*(unit+0x38))->vtbl[0]`. That lands in the FM's
slot 9 (`0x59f180`, vtable `0x611dc8`).

**Controller state** (all offsets relative to `ctl`): the handle is `ind[9]` at `ctl+0x4e0+0xc+9*4` (1 = down, 0 = up).
The per-leg lights are `leg[i]` at `ctl+0x53c+0xc+i*4`, i=0..2 (0 = up, 1 = in transit, 2 = down and locked).
The damage flags are at `ctl+0x3d8+0xc+n*4` (n = 7 is gear, 4 is flaps).

**GEV 0xe, keyboard toggle (`forced`=0), @44ce35:**
1. If the aircraft is simulated locally (`!netgame(0x82f398) || unit->local`) and `ctl+0x19c`≠0 or
   `ctl+0x1a0`≠0, the command is ignored. (UNCERTAIN: these are weapon-release and gun-burst in progress, set by `FUN_004579f0`.)
2. **Ground lock:** if `ind[9]`≠0 (gear down) and FM getter 0x1a ≠ 0 → **return, silently**.
   Getter 0x1a (`0x5a9280` case 0x1a @5a9d97) is `(float)S+0x2a0`, the on-ground/ground-roll flag (§7).
   Nothing else is checked here: no weight-on-wheels, speed, or altitude test. No message, no sound, no
   backseat voice, and the handle stays put. Lowering the gear on the ground is never blocked by this test.
3. The three legs are tried with `FUN_0044f970(old=ind[9], leg, forced)` @44f970:
   * gear damaged (flag 7) → the leg does not move;
   * **up→down:** blocked if `min(|v|,1200)·1.9427955 > 300` (TAS > 300 kt; getter 5 = FM slot 0x3c).
     Otherwise, if `leg`=0, it starts extending (`FUN_0045b120`: 0→1, and →2 after 2.0 s);
   * **down→up:** no speed limit. A leg starts retracting only when `leg`=2 (`FUN_0045b0f0`: 2→1, →0 after 2.0 s).
   If **no** leg can move, the command is ignored silently (locally simulated aircraft).
4. The handle toggles: `ind[9]` = 0 (`FUN_0045b460`) or 1 (`FUN_0045b3d0`). Motion input 7 is sent with
   +0x18 = the new `ind[9]`, and for the player's own aircraft `SFX_LANDING_GEAR` (sound 0x1e, `FUN_0044fb10`) plays.
5. FM `FUN_0059fdc0`: +0x18≠0 ramps `S+0x320` to its min `S+0x334` (0 = extended). +0x18=0 ramps it to its max `S+0x338`.
   (Airborne init `FUN_005a5820` sets 1.569 ≈ π/2 = retracted, rate `S+0x330` = 0.5/s → ~3.1 s. Ground init sets 0.)
   Ramp layout: +0 t0, +8 start, +0xc target, +0x10 rate, +0x14 min, +0x18 max, +0x1c duration.
With `forced`≠0 (explicit set, `arg[0]` = wanted state, probably network/replay; UNCERTAIN), the command is ignored
if the state is already equal, and steps 1–2 are skipped.

**Related:**
* Gear damage: `FUN_0044d760(7)` comes from combat damage only. It shows "Gear damage" (for the player) and sets
  the leg lights to 1. No overspeed-with-gear-down damage was found (UNCERTAIN: not searched exhaustively).
* Touchdown check `FUN_005bb7d0`: if the gear ramp is ≥1e-5 (not fully down), the three landing tolerances are
  multiplied by 0.2/0.2/0.25 (and ×2 with the "Easy landing" preference `pref+0x3c`, default on, or in multiplayer; §15.6). The ground roll uses μ=20 for a belly landing (§7).
* ATC text `ACFT_GEARS_NOT_OPEN` (`FUN_00551c20` case 10). The `BACKSEAT_GEAR_UP/DOWN` voices (category 0x36,
  ids 10/0xd) are defined in soundprop.txt, but no code that plays them was found.
* Other locks in the same controller: GEV 0x10 autopilot, when on the ground (getter 0x1a≠0), always goes to off
  (@44d0d6). GEV 0x11 brakes plays `SFX_SPEED_BREAKES_LOOP` (0x1c) only when airborne (@44cac1).
  GEV 0x42 (UNCERTAIN: gun fire) is refused while `ind[9]`≠0 unless `ctl+0x970`≠0 (@44b328).
  GEV 0xc flaps is refused while flaps are damaged (flag 4).

## 13. Blackout / redout (G effects on the pilot)
Generic for every aircraft: the rule uses no per-aircraft data except `OverGThresh` (warning only).

**Summary.** The original **has** a blackout and a redout. It is purely visual: a full-screen overlay
plus a shrinking "tunnel" for blackout, and a flat red overlay for redout. No code was found that
removes control, changes stick input or damages the aircraft from G. There are no strings "blackout",
"redout" or "G-LOC" in the exe. The only user-visible name is the Gameplay preference **"NO BLACKOUTS"**,
which is baked into the art `resource/menu/bmp/pref/gamep_*.bmp` (column "PLAYER SKILLS").

### 13.1 G value
Getter id 0 of `FUN_005a9280` (case @5a9337) returns
`G = L(t) / m / 9.806` with `L` = the lift ramp `S+0x1e0` (§4), `m = EmptyWeight + S+0x424 + fuel(S+0x430)`
and the factor `0.10197838` (@611ca8). This is the load factor: ≈1 in level flight and negative under a
push. `FUN_0044fbb0(ctl, float *G, int *enable)` reads it for the player controller (`DAT_00699308`).

### 13.2 Gating (`FUN_004dbe40`, called every frame from the sim render `FUN_004d9080`)
1. If `DAT_0083b938` ≠ 0, the function returns and nothing is integrated or drawn. `DAT_0083b938` is
   the menu-side copy of "No blackouts": pref object `0x83b810`+0x128, loaded from `prefs.dat` by
   `FUN_004f08f0` and copied to the pref instance `DAT_00699424`+0x30 by `FUN_004fe430`. The default is 0
   (blackouts on; `FUN_00450e30` sets `[0xc]=0`).
2. `FUN_0044fbb0` sets `enable = 1` only if the controller's unit is the player object (`DAT_00699320`,
   ids at +0x30 compared) and `[unit+0x1c]+0x14 == 3` (UNCERTAIN: meaning of state 3; the same test gates
   cockpit sounds in `FUN_0044fb10`). `enable` is also cleared when pref+0x30 ≠ 0, except in
   multiplayer (`DAT_00699350 && [DAT_00699350+4]`), where the pref is ignored. Step 1 is not
   overridden in multiplayer, so a local "No blackouts" still disables the effect. (UNCERTAIN: this
   looks like an intended MP override that has no effect.)
3. `FUN_004022b0(G, enable)` → TgenAPI vtable slot 0x7c (`0x4051c0`, real 16-bit renderer vtable
   `0x5fd900`) → `FUN_004038e0` → **`FUN_0041a130(this=[0x7792d8], G, enable)`**. If that returns 1,
   `FUN_0041a7e0([0x7792c0])` is called, and `FUN_004dbe40` sets `[param+0x154]+0x300 = 1` (UNCERTAIN:
   a redraw/dirty flag).
4. `FUN_0041a130` returns immediately (no integration) when `DAT_007d1960` = 0. That flag is set to 1 at
   @40b135 when the Direct3D device descriptor `0x7d1b18` is present, and 0 otherwise. (UNCERTAIN: 1 =
   hardware D3D device. With a software device there is no blackout at all.)

### 13.3 Accumulators (`FUN_0041a130` @41a130, disassembly; constants read from .rdata)
There are two floats in the Tgen effect object: blackout `B` at +0xc0 and redout `R` at +0xc4. `dt` is
`DAT_007d1980`, the frame time in seconds: `(tick − lastTick)·0.001`, and if it is > 200 it is replaced
by 0.001 (@40bc70). They integrate every frame, **even when `enable` = 0** (drawing is skipped then).
```
B += G·dt·0.43        ; if B > 24  → B = 24          // 5ff3b8, 5ff3bc
R += G·dt·0.20        ; if R > 0   → R = 0           // 5ff3c0
                        if R < −3  → R = −3          // 5ff3c4
B -= dt·2.5           ; if B < 0   → B = 0           // 5ff3c8
if R < 0: R += dt·0.25; if R > 0   → R = 0           // 5ff3cc
b = (B − 15)·0.125                                   // 5ff3d0, 5ff3d4   (range −1.875..1.125)
r = R < 0 ? (R + 1)·0.5 : 0                          // 5ff3d8, 5ff3dc   (range −1..0.5)
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

### 13.4 Drawing (Direct3D, IDirect3DDevice2 `DAT_007d1ee8`)
Each branch first calls `SetCurrentViewport(DAT_007d1ef0)` (slot 0x34) and ends with
`SetCurrentViewport(DAT_007d1eec)`. (UNCERTAIN: a full-screen viewport, then the normal one.)
`FUN_00419d90(rect 0x7d19f0, r, g, b, a, 0)` draws a 4-vertex TLVERTEX fan over the rect with the
colour `ARGB(a, r, g, b)` (colour built @419faa).
* **Redout** (b < 0.01 and r ≤ 0.01): `a = trunc(−255·r)`, clamped to ≤ 255. If a < 1 nothing is
  drawn. Otherwise a flat **dark-red** overlay `ARGB(a, 0x7f, 0, 0)` is drawn. There is no tunnel.
  (@41a2f1)
* **Blackout, b > 0.95:** an opaque black overlay `ARGB(255, 0, 0, 0)` (@41a386).
* **Blackout, 0.01 ≤ b ≤ 0.95** (tunnel vision, @41a3a0):
  1. `a = min(trunc(275·b), 275)` (5ff3ec). A full-screen black overlay with alpha `min(a, 255)` is drawn.
  2. The render states are set: TEXTUREHANDLE 0, ZENABLE 0, ZWRITEENABLE 0, FILLMODE 3.
  3. Rings: the centre is (W/2, H/2), where W, H = `DAT_007d19f8/02c` are the render size in pixels.
     Ring 0 is an annulus from outer radius `W` to inner radius
     `rin = (1 − 2·(b − 0.5))·W = (2 − 2b)·W` (0.1·W at b = 0.95, ≈W at b = 0.5). Both edges are
     black with alpha `min(a, 255)`. Each next ring's outer radius is the previous inner radius, its
     inner radius is 3 px smaller (5ff3f0), and its alpha is 20 lower. There are at most 7 rings, and
     the loop stops when the next inner radius would be < 0. Each ring uses 24 points from the unit
     circle table at object +0x00..+0xbc (x, y pairs), which gives 48 TLVERTEX at +0xc8 (stride 0x20).
     It is drawn with `DrawIndexedPrimitive(TRIANGLESTRIP, TLVERTEX, …, 48, idx +0x6c8, 52, 1)`.
     (UNCERTAIN: the table and the index list are filled by a constructor that was not traced.)
     The result: the whole screen dims with `a`, and outside a circle of radius `rin` it is darker
     again, with a soft edge 18 px wide. The clear circle shrinks as B grows.
  * Quirk: the ring alpha `a − 20k` is clamped only above. For small `a`, negative values are written
    as `a<<24` and become a large wrapped alpha. A faithful port can clamp it to 0 (UNCERTAIN: whether
    this was visible in 1998).

### 13.5 Over-G warning and G sound (player controller per-frame update `FUN_00448b20`)
* @44951e: `if G > OverGThresh` (P+0x168, default 6.7 g, getter 27), then the repeat timer at `ctl+0x880`
  is polled (`FUN_004d4100`: it fires when "now" is outside the last window and opens a new window of
  **4.0 s**; the period is `DAT_0082f468` = 4.0, set by the load-time initialiser @446c40). When it
  fires and `ctl+0x8d8` = 0, it plays sound `0x2c009000` = `VOC_BBETTY`/`BTY_OVER_G`
  (`Cock_Bty_Over.wav`, soundprop.txt), and the handle is stored in `ctl+0x8d8`.
* @449574: `if G > 6.0` (hard-coded, @600af8), then the timer at `ctl+0x8a0` fires with period
  **17.0 s** (`DAT_0082f3d0`, initialiser @446c70) and plays `SFX_G_EFFECT` (code 0x13, `Cock_G_02.wav`).
  It is not gated by "No blackouts".
* `FUN_0044fb10` plays these only for the player's own aircraft (ctl+4 ∈ {2, 4, 5} and the same player
  object test as in §13.2).
* The G value is also written to the HUD (`FUN_00445920` → HUD `0x82f544`+0x33c).
* **No over-G damage** was found. Getter 27 (`OverGThresh`) is used only at @44951e. The only uses
  of MaxG found are the FM's own lift limits (§4). (UNCERTAIN: other damage paths were not searched
  exhaustively.) The `BACKSEAT_HEAVY_BREATH` and
  `BACKSEAT_OH_YOU_KILLING_ME` voices (category 0x36, ids 1/2) are defined in soundprop.txt, but no code
  that plays them was found (no 0x3600x000 codes and no `FUN_00450a60(0x36,…)`).

## 14. Port audit (ground roll and lift)

Source: `objdump -d -M intel` of `iafjets.exe`; stack arguments were mapped by tracking every push (the
Ghidra listing of these calls is shifted by one argument). Constants were read from `.rdata`/`.data`, and the
CRT initialiser table `0x627754..0x6277c0` was checked for load-time writes. In this section `sY` = stick Y
`S+0x2e4` (+ = pull), `sX` = stick X `S+0x2e8`, `W = m·9.806`, and `c_f = FlapsLiftCoef·flaps·3.4158838`.

### 14.1 Call graph and argument mapping
* `5a70f0` (aero update, 1 Hz + every control event) → `5b3af0(33 args)`. Arg 6 = `S+0x2a0` (ground flag)
  and arg 7 = departure latch (`S+0x2f8` ≠ −1 and `now − S+0x2f8 ≤ 3.0`).
* Ground branch: `5b3af0` → `5bac40(30 args)`. 7a20 arg k = b0a20 arg k for k ≤ 5, arg k+2 for 6 ≤ k ≤ 26, and
  arg k+3 for k ≥ 27. The latch (b0a20 arg 7) is dropped.
  7a20 args: 1 alt, 2 V=|v|, 5 &attitude(pitch,roll,heading), 6 engine on (`S+0x1d0`), 7 &cfg, 8 extra mass
  (`S+0x424`+fuel), 9 stores DI, 13 sY, 14 sX, 15 rudder (unused), 16 vehicle.
  Outputs: 19 nose-wheel yaw, 20 roll-rate cmd, 24 L, 25 dragX, 26 stall flag, 27 Lnoflap, 28 T, 29 D, 30 m.
* `cfg` (built in 5a70f0) — **corrected in §15.1**: `[0]` flaps (float, `S+0x300` ramp); `[6]` brakes from ramp
  `S+0x340` (in the air: finished at its maximum; on the ground: any sample ≥ 1e-5); `[7]` gear = gear ramp
  `S+0x320` fully extended (`|x| < 1e-5`); `[8]` = `S+0x360` finished at max (hook). (`S+0x2cc`==2 is `[9]`, unused.)
* After b0a20, 5a70f0 sets `S+0x1d4`=T, `S+0x1dc`=D, `S+0x1d8`=m, ramp `S+0x1e0`→L and ramp `S+0x200`→Lnoflap
  (rates as §4). It passes the stall flag to `5a9e60` (latch). It also calls the acceleration routine
  `5b3ef0` (@5a784b) with the lift ramp value sampled *before* the new target is set, and re-bases the X/Y/Z
  axes (@5a7eaa–5a7f9e). **So every aero update and every control event also changes the acceleration at
  once**, not only the 5 Hz tick.
* On the ground, 5a70f0 skips the beta update `5aa700`: it steps the β channel with its stored gains and command
  (`5ae4c0`/`5ae240`, v1.1; v1.0 re-based the ramp) and ramps `S+0x2a8` toward the nose-wheel yaw (arg 19) at rate
  `S+0x2b8`. **Correction:** the constructor's 10000/s (@5ba20a) is overwritten by `5b1f30` at
  SetType and by the placement inits with `|BetaRate|`, and the ramp is clamped to ±MaxBeta (F-16: 32°/s², ±15°/s,
  below K = 20°/s). The 5 Hz force uses the ramp sample; the 1 Hz/event force uses the raw target (arg 19). §15.2.6.

### 14.2 `FUN_005bac40` ground aero (ret 0x78)
```
ai   = FUN_005c89f0(veh+0xc50) != 0
team = see 5b3af0 (only used by Lift for AI)
mach, rho = atmos(alt, V);  qS = 0.5*rho*V²*WingArea            // 5b3fd0, 5b4100
T    = Thrust(alt, mach, V, thr=arg12, engineOn, noAB = ai, flags=arg11, &rpm,&ff,&stage)
                    // NB: airborne passes noAB = !HasAfterBurner || (ai && mode∉{7,8}); ground passes ai
m    = EmptyWeight(P+0x8c) + arg8;   *out_m = m
L    = Lift(V, alt, mach, qS, m, sY, &att, cfg, latched=0, ai, team, &dragX, &stall, &dummyVib, &Lnoflap)
easy = pref+0x20 || pref+0x1c         (both forced 0 in multiplayer)
L    = 0.5*L;   L = L + |L|*c_f                              // @5badfd, 0x61246c=0.5, 0x612470=−3.4158838
      // Lift() already added |L|*c_f when V<125, so on the ground flaps count TWICE:
      // L = 0.5*g*W*(1+c_f)²   (g>0, V<125)
if !((V > 74.53 || sY > 0.5) && (cfg[7] || ai || multiplayer || pref+0x3c || easy)):
      L = 0; Lnoflap = 0; stall = 0                          // @5bae86
mu   = cfg[6]*WheelsBrakeDI*(ai ? 4 : 1) + fric1             // fric1 = DAT_008454a8, see below; v1.0 ai ? 2
if !cfg[7] && !ai && !easy: mu = 20.0                        // belly (replaces, not adds)
D    = Drag(V, alt, n = L/W, mach, qS, alpha = 0, cfg, storesDI, dragX, stall, ai, m)
     + 0.5*mu*(W − L)
D    = D > 0 ? D : 0;   if V > 1.0: D *= 0.8                 // v1.0: 0.7
T    = max(T, 0)
yaw  = clamp(sX*V*K/74.53, −K, K);  if !cfg[7]: yaw = 0;  if |yaw| < 1e-4: yaw = 0   // K = 0.3490659
out_rollRateCmd = 0
```
**Load-time initialiser (not in Ghidra):** `DAT_008454a8` = `fric1` is **not 0**. CRT table entry `0x62779c`
→ `0x5ba8d0` → @5ba8e0 calls `FUN_004d3b50("TAXI", "fric1", 0.25, 0)`, which reads `IAF.ibx`.
`install/iaf.ibx` `[TAXI] fric1=0.05`, so fric1 = 0.05, a rolling friction that is always on:
`0.5·0.05·(W − L)`. `fric2` (0.30, `0x8454ac`) is loaded the same way but never read.
Other TAXI keys (`DistFromGround` 0x8454c0, `GearSize` 0x8454c4, keys at 0x8454cc and 0x8454dc) are not used here.
Constants: 74.53 `0x612440`, 0.5 `0x61246c`, 4.0 `0x612474` (AI brake factor; v1.0 2.0 at `0x60e580`), 1.0 `0x612478`,
20.0 `0x61245c`, 9.806 `0x61247c`, 0.8 `0x612480` (v1.0 0.7 at `0x60e5a4`), 0 `0x612468`, 1e-4 (double) `0x612488`.
These two constants are the only v1.1 change in `5bac40`. The taxi release-note item ("taxi with brakes can move on full
AB") comes from the data: v1.1 lowers WheelsBrakeDragIndex (F-16 15000 → 7000, F-15 15000 → 9000, F-4 10000 → 5000,
Mirage 8000 → 4500, Kfir 8000 → 4000, MiG-23 15000 → 8000, MiG-29 15000 → 7500, Lavi 15000 → 10000), so static full-AB
thrust / (μ·W) goes from 0.42–0.72 to ≈ 1.0–1.4 (MiG-23 0.79). With v1.0 data the v1.0 brake values apply (the ×0.8
still does).

### 14.3 `FUN_005b4470` Lift (shared, ret 0x3c)
Args: V, alt, mach, qS, m, sY, &att, cfg, latched, ai, team, &dragX, &stall, &vib, &Lnoflap.
```
bStall = !ai ? (multiplayer || pref+0x38 == 0) : !(pref+0x50 == 2 && team)
if latched && bStall: dragX=1.2; Lnoflap=0; return 0                     // ground always passes latched=0
dragX = stall = vib = 0;  lim = 0
c = V < P+0x144 ? P+0x180*V + P+0x184 : 1
g = sY > 0 ? c + sY*(P+0xc8) : c + (−sY)*((P+0xcc + 1) − c)             // P+0xc8=MaxG−1, P+0xcc=MinG−1
g_cmd = g
if |g − 1| < 1e-5 && |att.roll| < P+0xdc(10°): g_cmd = g = cos(att.pitch)/cos(att.roll)
if UseFlightLimits(P+0x88):
   code = GLimit(alt, V, g, &lim)                                       // 5b58e0, jump table 0x5b47ec
   0: dragX=1.2; bStall ? (g=0, stall=1) : g=min(0.4, g_cmd)
   1: g = 0          (5b58e0 never returns 1)
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

`GLimit` `FUN_005b58e0(alt, V, g, &lim)`: `k = max(0, ftol(alt/step))`. Use the g>0 list `E+0x44` (count
`E+0x48`) if g > 0, else the g≤0 list `E+0x58` (count `E+0x5c`).
* `k+1 > count−1` → code 2, lim = −1.
* `a = 5b6400(list[k], V)` and `b = 5b6400(list[k+1], V)` (>0 means V is above all points, <0 below all,
  0 bracketed).
* `a > 0`: if `Ceiling(g) ≥ alt` → code 3 (lim = g), else code 4 with `lim = 5b5840(g, alt)`.
* `a ≤ 0`: if `b < 0` or `a < 0` → code 0 (lim = −1). Otherwise code 4 with lim = plane fit `5b5b60`,
  forced to 0 if g > 0 and lim < 0, or if g < 0 and lim > 0.

### 14.4 `FUN_005b4800` Drag (ret 0x30) and `FUN_005b4120` Thrust (ret 0x28)
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

### 14.5 Ground acceleration `FUN_005bb060` (via `5b3ef0` → `5b4930` when ground)
`5b3ef0` forces pitch = roll = 0 on the ground, so `M = 5ba740(0, 0, heading)`.
`yaw` is `S+0x2a8` in the 5 Hz update (5bb9f0 writes it into the beta slot) and arg 19 in the aero update.
```
R  = yaw == 0 ? 5.0 : V/(9.806*tan(yaw));   if |R| < 2: R = 2*sign(R)
Fc = (V > 2 && yaw != 0) ? V²*m/R : 0           // = V*m*9.806*tan(yaw)
f  = V < 25.736 ? 1.0 : |0.1 − 0.000777118*V|;  Fc *= f
Lz = L_ramp(t)                                    // S+0x1e0 sample, not the new target
if |Fc| > 0.1*Lz && V > 20.5889: Lz *= 4          // @5bb157, 0x6124ac=0.1, 0x612474=4.0 (shared with the AI brake)
Fx = (V < 0.01 && T < D) ? 0 : T − D − |Fc|*0.0625
F_body = (x = Fc, y = Fx, z = Lz);  Fw = 5ba690(M, F_body)   // (-r1, r0, r2) as §5
Fw.z = max(Fw.z − m*9.806, 0);  acc = Fw/m;  acc_body = 5ba600(M, acc)
```
Constants: 5.0 (imm 0x40a00000), 2.0 `0x612498`, 25.736 `0x6124a4`, 0.000777118 `0x6124a8`,
20.5889 `0x6124b0`, 0.01 `0x6124b4`, 0.0625 `0x6124b8` (double), −9.806 `0x6124c0`.
The heading is not integrated anywhere. The lateral force turns the velocity, and the attitude (mode object,
§6) takes its heading from the velocity.

**Stop rule** (5 Hz `5a4230` only, @5a4720–5a48a7, ground only): `v_b = 5ba600(M(0,0,heading), velocity)`.
If `acc_body.y < 0` and `v_b.y + 0.2·acc_body.y < 0` (0x611bf8 = −0.2), then set `acc_body.y = 0`, recompute
the world acceleration, and re-base **all three axes with v = 0** (position kept). The 1 Hz/event path (5a70f0)
has no stop rule (UNCERTAIN: so between two 5 Hz ticks a large deceleration set by an event could briefly
reverse the velocity).

### 14.6 Air ↔ ground transitions — `FUN_005bb9f0(now, &speed, &Z, &beta)`
This function is called at the start of every 5 Hz tick (`5a4230` @5a4360) and nowhere per frame.
`clear` = terrain(X,Y) (`402080`) + |model height| (`463f20`). The Z axis limits are fixed at
[−1500, 30000] (@5b9eea), so nothing else clamps altitude.
```
if S+0x2a0 == 0:                                     // airborne
   if Z > clear: *beta = fmod(S+0x260 channel pos); return
   // touchdown (@5bbd1e)
   S+0x2a0 = 1
   if 5bb7d0(τ, vz) (landing/crash check, UNCERTAIN): event 4a8ae0(…,5,…)
   Z axis := (p = Z(τ), v = 0, a = unchanged a_z);  if clear in [−1500,30000]: p0 = clear, t0 = now
   *Z = clear;  5a70f0(now)                          // aero update now runs the ground branch
   non-runway / water / gear-up side effects (S+0x2c8 = 2 or 4, force-feedback effects + SFX, landed flag) — §15.6
if *Z > clear && vz > 0.001:                          // lift-off (@5bbf54)
   S+0x2a0 = 0;  5a70f0(now)                          // airborne branch, full lift, latch honoured
   roll channel S+0x80 := (pos = 0, rate = current rate, targetRate = S+0x90)
   *Z = Z sample, *speed = vtable+0x3c, *beta = fmod(S+0x260 pos);  S+0x2c8 = 0;  landed flag := 0 (v1.1);  return
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
  Vmin). Then `stall = 1` and `5a9e60` sets `S+0x2f8` even on the ground. The ground branch ignores the
  latch, but the first airborne updates within 3 s get L = 0.
* `5b4c60` (alpha target) returns 0 on the ground.

### 14.7 Worked example (the bug report: F-16, V = 65.3 m/s = 127 kt, sea level, full aft, gear down, flaps up)
Original: g_cmd ≈ 8.7 (stick-centre shift). GLimit gives code 4 with lim ≈ 1.65 (Vmin: 1 g = 86 kt,
2 g = 148 kt). So g = 1.65 and L = 0.5·1.65·W ≈ 0.83 W. n = 0.83 and CL ≈ 1.17, so D ≈ (0.072 + 0.143)·qS
≈ 15.6 kN, plus friction 0.43 kN, ×0.7 ≈ 11 kN (v1.0 factor; v1.1 ×0.8 ≈ 12.8 kN). With T ≈ 86 kN the jet keeps accelerating and stays on the
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
   "DAT_008454a8 = 0" is wrong.
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
7. **Aero update does not re-base the acceleration** (l. 391–506 vs `5a70f0` @5a784b/5a7eaa). Original: every
   1 Hz update and every control event recomputes the acceleration (using the old lift-ramp sample and the
   new T/D) and re-bases the axes at once. The port waits for the next 5 Hz tick.
8. **Speed-brake drag excluded on the ground** (l. 475). Original: `cfg[6]` adds SpeedBrakesDI on the ground
   too, as well as the wheel friction. `cfg[6]` is the 0/1 "ramp finished at max" flag; the port uses the
   continuous ramp value (l. 467, 477).
9. **Ground drag uses α ≠ 0** (l. 463–465). Original: alpha = 0 in the ground Drag call, so CL = L/qS.
10. **Lnoflap not zeroed by the ground lift gate** (l. 457–458, 492). Original: the gate zeroes L,
    Lnoflap and the stall flag, so the `S+0x200` ramp also goes to 0.
11. **Alpha on the ground** (l. 520–533, 585). Original: alpha target = 0 (`5b4c60`), with normal dynamics.
    The port computes the target from lift_aoa and then snaps α to 0.
12. **Beta on the ground** (l. 503–505). Original (v1.0): the beta ramp is not updated on the ground (v1.1: the β channel
    steps with its stored gains, §15.2.6); `S+0x2a8`
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
initialiser table checked for load-time writes. **The CRT table is `0x627004..0x62790c`** (v1.0 `0x623004..0x623890`, 547 entries); the FM part is
`0x62770c..0x6277c8`, larger than the `0x627754..0x6277c0` range used in §14. Notation as §14: `sY` = stick Y `S+0x2e4`
(+ = pull), `sX` = stick X `S+0x2e8`, `ru` = rudder `S+0x2ec`, `W = m·9.806`, `τ` = sample time since the channel base,
`S` = the state copy the routine works on (`veh+0xc34` write copy; the attitude sampler reads `veh+0xc30`).

Channel layouts needed below (offsets inside the channel):
* Ramp (type A, `5a2a80`/`5a2b00`, clamp `5a2b50`): `+0 t0 (f64), +8 v0, +0xc target, +0x10 rate, +0x14 min, +0x18 max,
  +0x1c t_end`. `5a2a80(&now, v_now, target, rate)` stores `rate = |rate|·sign(target − v_now)`.
* Angle (type B, `5adc70`): `+0 t0, +8 pos0, +0xc rate0, +0x10 targetRate, +0x14 t_end, +0x18 pos_end, +0x1c accel,
  +0x20 startAccel, +0x24 stopAccel, +0x28 minRate, +0x2c maxRate`. The α channel `S+0x220` has 3 more fields:
  `+0x30 B (damping), +0x34 K (gain), +0x38 target α` (`S+0x250/0x254/0x258`); so has the v1.1 β channel `S+0x260`
  (`S+0x290` B, `S+0x294` K, `S+0x298` β_cmd).
* Axis (type C, `5ada80`/`5adaa0`/`5adc00`/`5adc30`): `+0 p0, +8 t0 (f64), +0x10 v, +0x14 a, +0x18 min, +0x1c max`.
* **Angles are reduced with `fmod(x, 2π)`** (`_CIfmod` `0x56886a` with `DAT_0084549c` = 2π, set by initialiser
  `0x6277c4 → 5ba550`), i.e. to (−2π, 2π), not to (−π, π]. Only the angle-difference helper `5bdd50` and the helpers
  `44f5f0`/`43d460` (fmod, then −2π if > π) wrap further.
* All channels of a state are sampled with `τ = clamp(now − S+0x28, 0, 1.1)` where `S+0x28` is the **X-axis base time**
  (`5b9250`, `5a70f0`); the ramps use `clamp(now − own t0, 0, 3.5)`.

### 15.1 Call graph (airborne)

**1 Hz + every control event — `5a70f0(&now)`** (in this order):
1. `τ = clamp(now − S+0x28, 0, 1.1)`; `alt = Z(τ)` (`5adc00`, clamped to the Z limits); `β_s = fmod(β(τ))` (channel `S+0x260`);
   `α_s = fmod(α(τ), 2π)` (α channel `S+0x220`); `v = (vx, vy, vz)(τ)`, **`V = |v|` (not capped here)**.
2. Attitude `att = (pitch, roll, heading)`: `veh+0xc` unit → vtable `+0x54`, cached per `now` in `unit+0x88` (so the mode
   object's `5b9250`, §15.3, runs at most once per time stamp).
3. `cfg[10]` (ints, `cfg[0]` float) at `&L58` — **corrects §14.1**:
   * `cfg[0]` = flaps ramp `S+0x300` sample;
   * `cfg[6]` (brakes) = on the ground (getter `0x1a` ≠ 0): `|S+0x340(t)| ≥ 1e-5`; in the air: the `S+0x340` ramp has
     finished (`τ ≥ t_end`) **and** `|target − max| < 0.01·(max − min)`. `S+0x340` is the ramp of motion 8
     (`FUN_0059ffc0`), which the player controller posts @44c8d9/@44c949 next to the GEV 0x11 brake handler (@44cac1).
     §7 and §14.1 said `S+0x360`; that was wrong.
   * `cfg[7]` (gear) = `|S+0x320(t)| < 1e-5`, i.e. the gear ramp is exactly at its "extended" end (0). Gear drag, the
     ground lift gate and the belly rule use this, so they switch only when the gear is fully down (not while it moves).
     §14.1 said `S+0x2cc == 2`; that is `cfg[9]`, which Drag/Lift/ground aero do not read.
   * `cfg[8]` = `S+0x360` ramp finished at its max (motion 9) → `HookDragIndex` in Drag (UNCERTAIN: hook).
   * `cfg[1..5]` = 0.
4. Mass/stores: `m_x = S+0x424 + fuel(S+0x430)`, `DI_s = S+0x428 + S+0x42c`, `asym = S+0x428 − S+0x42c`.
   Flags `L90`: `|= 2` if `fuel < 1e-5` (`0x611c6c`), then `5bc350(&flags)` adds the damage bits.
5. `latched = S+0x2f8 ≠ −1.0 && now − S+0x2f8 ≤ 3.0` (`0x611bf0`, double; note `≤`).
6. `5b3af0` (33 args, below) → `L, Lnoflap, T, D, m, dragX, stall, vib, β_cmd, p_cmd, rpm, ff, abStage`.
7. `acc = 5b3ef0(L_old = S+0x1e0(t), T, D, m, alt, V, β = β_cmd, α = α_s, &att, ground)` (@5a784b) — the lift ramp sample
   **before** the new target, the new T/D/m, the **commanded** β and the **sampled** α.
8. Latch `5a9e60(now, stall, vib)` (§15.2.4), then the mode hooks `5aab90` and `5ac5d0` (§15.5).
9. Lift ramps: `S+0x1e0 → L`, `S+0x200 → Lnoflap` (first re-based with the old rate, then the rate is set as §4:
   `V ≥ 220 ? G_Rate·m·g : (0.00495·G_Rate·V + (0.01 − 0.099)·G_Rate)·m·g`, same for `G_RateForAoa`; **no lower clamp**:
   the factor is 0.01 at 20 m/s, 0 at 17.98 m/s and negative below, and `5a2a80` takes `|rate|`).
10. `S+0x1dc = D, S+0x1d4 = T, S+0x1d8 = m`.
11. α dynamics `5aa3a0(now, V, alt, Lnoflap, stall)` (§15.2.5).
12. Airborne: β `5aa700(now, V, alt, β_cmd, stall)` (§15.2.6) and re-base `S+0x2a8` (target/rate kept). On the ground:
    `S+0x2a8 → yaw_nw` (7a20 output) at its own rate, then the β channel steps with its stored gains and command:
    `r = 5ae4c0(now)`, `5ae240(now, r)` (v1.1; v1.0 re-based `S+0x280` and `S+0x260`).
13. Re-base the axes X/Y/Z with `acc` (`p = p(τ)`, `v = v0 + a0·τ`, `a = acc`).
14. `5aa330(att)`: `S+0x14..0x1c = (pitch, roll, heading)`, `S+0x08 = Mᵀ-map(−1, 0, 0)` = **left** wing in world axes
    (`5ba690`; body x is the right wing, §5).
15. Roll channel `S+0x80`: re-base with `pos = att.roll` (rate and target kept), then `5adc70(now, pos, rate, k·p_cmd)`
    with `k` as §4 (`Veff < 220 ? 0.00475·Veff − 0.045 : 1`, `0x843e10/0x843e14`, **no clamp**: `k < 0` below
    `Veff ≈ 9.47 m/s`).
16. Re-base ramps `S+0x300, 0x320, 0x340, 0x360, 0x380, 0x400` (and `0x3c0/0x3a0` unless the type is 0x82 or 0xbe);
    fuel ramp `S+0x430` rate `ff` (target kept, normally 0); `S+0x2f0 = dragX`;
    `S+0x420 = (75 < V < 150 && sY > 0.7)` (UNCERTAIN: a visual/effects flag; read only by getter `0x14` and the network
    packer); RPM ramp `S+0x1b0 → S+0x1c8·rpm` (`S+0x1c8` = 100, rate kept); sounds/AB effects; `veh+0xc3c = 1`; swap.

**5 Hz — `5a4230`** (disassembly only):
1. `now = [0x6992d0]+0x38`; `alt = Z(τ)`; `V` = FM slot `0x3c` (`5a68a0`, capped 1200 m/s); `β_s = fmod(β(τ))` (`S+0x260`).
2. `5bb9f0(now, &V, &alt, &β_s)` (air/ground transitions, §14.6; on the ground it replaces `β_s` by `S+0x2a8(t)`).
3. Attitude as step 2 above. If `S+0x00 == 0` → vtable `+0x50` and `5aebc0` (network state send; no physics).
4. **Mode dispatch:** if `S+0x04 == veh+0xc70` → `5aab90(...)`, then (v1.1) `β_cmd = 5b4910(β_s, ru, alt, V, asym = 0)` and
   `5aa700(now, V, alt, β_cmd, latched)` (so β keeps following the rudder at 5 Hz in the spin), swap, **return**; if
   `S+0x04 == veh+0xc7c` →
   `5ac5d0(...)`, swap, **return** (§15.5). Otherwise the normal tick:
5. `5aa330(att)`.
6. `Laoa = S+0x200(t)`; `αT = 5b4c60(V, alt, Laoa, latched, ground)` =
   `ground ? 0 : max(min((Laoa − e4·qS)/(e8·qS), MaxPosAlpha, LimitAlphaVisual), MaxNegAlpha)` (`latched` is not read).
7. `acc = 5b3ef0(L = S+0x1e0(t), T = S+0x1d4, D = S+0x1dc, m = S+0x1d8, alt, V, β = β_s, α = αT, &att, ground)`.
   **The 5 Hz force uses the α *target* `αT`, not the α channel.**
8. Ground stop rule (§14.5), then re-base X/Y/Z with `acc`.
9. Re-base `S+0x1e0` and `S+0x200` (same target and rate).
10. Roll: re-base `S+0x80` with `pos = att.roll`, rate and target kept (no new target at 5 Hz).
11. α: `S+0x258 = αT`, target rate `r = 5ae4c0(now)`, `5ae240(now, r)` (re-base with the new target rate; the gains
    `S+0x240..0x254` stay as set by the last 1 Hz `5aa3a0`).
12. β: `β_cmd = 5b4910(β_s, ru, alt, V, asym)` with `asym = 0` when `S+0x04 == veh+0xc70`, then
    `5aa700(now, V, alt, β_cmd, latched)` — **also on the ground**.
13. Re-base fuel `S+0x430` and RPM `S+0x1b0`. If `S+0x04 == veh+0xc78` → `5b7e60(&now)` (§15.5). `veh+0xc3c = 1`, swap.

### 15.2 Airborne aero `5b3af0` (thiscall `ecx` = P, `ret 0x84`, 33 stack args)
Args (from the pushes @5a7720–5a779a): 1 alt, 2 V, 3 α_s, 4 β_s, 5 &att, 6 ground (`S+0x2a0`), 7 latched, 8 engine on
(`S+0x1d0`), 9 &cfg, 10 m_x, 11 DI_s, 12 asym, 13 flags, 14 thr (`S+0x2dc`), 15 sY, 16 sX, 17 ru, 18 vehicle, 19/20 now,
outputs 21 &β_cmd, 22 &p_cmd, 23 &rpm, 24 &ff, 25 &abStage, 26 &L, 27 &dragX, 28 &stall, 29 &vib, 30 &Lnoflap, 31 &T,
32 &D, 33 &m. Ground → `5bac40` (§14). Airborne (@5b3c0a):
```
*vib = 0
ai   = FUN_005c89f0(veh+0xc50) != 0
team = DAT_00699320 ? 4a4cf0(...) : (side of veh ∈ {2,3})           // only used by Lift for AI
mach, rho = 5b3fd0(alt, V);  qS = 5b4100(V, rho)
noAB = !P+0x164 || (ai && mode ∉ {7, 8})
T    = 5b4120(alt, mach, V, thr, engineOn, noAB, flags, &rpm, &ff, &abStage)    // §4.1, NOT clamped ≥ 0
m    = P+0x8c + m_x
L    = 5b4470(V, alt, mach, qS, m, sY, &att, cfg, latched, ai, team, &dragX, &stall, &vib, &Lnoflap)   // §14.3
α_D  = stall ? 0 : clamp((Lnoflap − e4·qS)/(e8·qS), MaxNegAlpha, MaxPosAlpha)   // no LimitAlphaVisual here
D    = 5b4800(V, alt, n = L/(m·9.806), mach, qS, α_D, cfg, DI_s, dragX, stall||latched, ai, m)   // §14.4
β_cmd = (ru + 10·asym)·MaxBeta                                    // 5b4910; 0x612170 = −10, (A2 − A5·(−10))·P+0xb8
p_cmd = MaxRollRate·sX                                             // P+0xac
```
In Lift the airborne call passes the real `latched`: `latched && bStall` → `L = Lnoflap = 0`, `dragX = 1.2`, the stall flag
is **not** set. So during the latch `α_D = clamp(−e4/e8, …)` (irrelevant, `L = 0`), the 1 Hz α target is the zero-lift α
(§15.2.5) and the jet flies ballistic (thrust, drag with `n = 0`, gravity).

#### 15.2.1 Drag, thrust
As §14.4 with the corrected `cfg` (15.1 step 3): `CD = PlaneDI + cfg[6]·SpeedBrakesDI + cfg[8]·HookDI +
cfg[7]·GearDI·(ai ? 0 : 1) + FlapsDI·flaps·3.4158838 + DI_s + K·CL²`, `CL = cos(α_D)·L/qS` (L includes the flap
increment). Thrust as §4.1; the airborne T is not clamped.

#### 15.2.2 Acceleration `5b3ef0` → `5b4930` (airborne; `5b3ef0 ret 0x30`, `5b4930 ret 0x2c`)
`5b3ef0(L, T, D, m, alt, V, β, α, &att, ground, &acc_out, &acc_body_out)`: `M = 5ba740(ground ? 0 : pitch, ground ? 0 :
roll, heading)`, then `5b4930(&ret, ground, T, L, D, m, α, β, V, &acc_body_out, &M)`; airborne:
```
x = D·sin β + 5·V²·β           // 0x6120b0 = −5; objdump "fsubp st(1),st" = st1 − st0 (Intel semantics)
y = T + L·sin α − D·cos α·cos β
z = L·cos α + D·sin α·cos β
r = 5ba690(M, (x, y, z))        // (y, x, −z) → Mᵀ → (−r1, r0, r2), world X east, Y north, Z up
acc = (r.x/m, r.y/m, (r.z − 9.806·m)/m)
```
`acc_body_out` is not written in the air. Frames: body x = right wing, y = nose, z = up (check: `M(0,0,0) =
diag(1,−1,−1)`, body y → north, body x → east). `M` is the body attitude from the mode object (it already contains α(t)
and β(t)), while the decomposition uses the α/β passed in: 5 Hz `αT` and `β(t)` (the channel sample), 1 Hz `α(t)` and
`β_cmd`. While α lags
`αT` (a pull), the lift vector therefore leans forward by `αT − α(t)` (extra forward force `L·sin(αT − α)`); while α
overshoots it leans back. With `β_cmd ≠ β(t)` the 1 Hz side force uses the commanded sideslip at once.

How the path turns: nothing integrates a pitch or yaw rate. Lift acts along body z rotated by the bank (in `M`), so
its horizontal part turns the velocity vector; the attitude (§15.3) is rebuilt from the velocity every frame, so the
nose follows the velocity plus α/β. The side force `5·V²·β` (N, independent of mass and wing area) pulls the velocity
toward the nose (weathervane).

#### 15.2.3 Lift in the air
Exactly §14.3 with `latched` honoured. Summary of what is airborne-specific: the stick-centre line
`c = V < P+0x144 ? P+0x180·V + P+0x184 : 1` (loader @5b39a8–5b3a32: `P+0x144 = Vmin(3048 m, StartMoveStickCenterG)`,
`P+0x180 = (MapCenterStick − 1)/(10 − P+0x144)`, `P+0x184 = MapCenterStick − 10·P+0x180`, 10.0 = `0x6120c0`; skipped if
`10 − P+0x144 == 0`); the 1 g hold uses the body attitude of step 2 (pitch/roll of the nose, not of the path); the
vibration flag needs `P+0x84` and `!ai`.

#### 15.2.4 Departure / stall latch `5a9e60(now, stall, vib)` (thiscall, `ret 0x10`)
```
player = veh is DAT_00699320's unit (ids at +8/+0xc/+0x10/+0x14 equal) && [unit+0x1c]+0x14 == 3
if S+0x2f8 == −1.0 (unset) and stall:
    S+0x2f8 = now
    if player && airborne: FUN_004de6a0()     // force-feedback effect "StallShake" start
    unit log message (resource string 0x14, 4a4c50) (UNCERTAIN: text)
elif S+0x2f8 != −1.0 and now − S+0x2f8 > 3.0:
    S+0x2f8 = −1.0
    if player && airborne: FUN_004def40()     // FF effect stop
if veh+0xc60 == 0:  S+0x1a8 = S+0x1ac = vib ? 0.5 : 0      // 0x611c30 = 0.5 (double), camera/stick shake
```
* A stall result only **starts** the latch; while it is set a new stall does not extend it. It is cleared by the first
  aero update with `now − t > 3.0`, even if the jet is still stalled; the next update with `stall = 1` sets it again.
* `latched` for Lift is `now − t ≤ 3.0`. With the 1 Hz timer (updates at t+1, t+2, t+3 exactly) the lift is held at 0
  for **three** further updates, i.e. until the update at t+4; control events in between also see `L = 0`.
* The latch is also set on the ground (Lift runs GLimit there); the ground aero ignores it (§14.6).
* Stall is `code 0` (below Vmin) or `code 2` (above the envelope) with stalls enabled (`bStall`, §14.3).

#### 15.2.5 α dynamics: 1 Hz `5aa3a0(now, V, alt, Lnoflap, stall)` and 5 Hz `5ae4c0`/`5ae240`
1 Hz: `αT = 5b4c60(V, alt, Lnoflap, stall, ground)` — **uses the new `Lnoflap` target, not the ramp**. Gains:
`f = V ≥ 220 ? 1 : max(0.004995·V − 0.0989, 0.001)` (`0x8453d8/0x8453dc` set by `5b1f30`, floor `0x611cc4`);
`S+0x240 = |AlphaStartAccel·f|`, `S+0x244 = |AlphaStopAccel·f|`, `S+0x248/0x24c = ∓MaxAlphaRate·f`,
`S+0x250 = B = AlphaBeta·f`, `S+0x254 = K = AlphaK·f`, `S+0x258 = αT`. Then with `(pos, rate) = α(τ)`:
```
err  = 5bdd50(fmod(pos, 2π), αT)        // wrap(αT − pos) to (−π, π]
damp = |rate| ≤ π ? B·rate·Rmax : 0.5·B·rate·Rmax           // Rmax = S+0x24c; 0x611bd0 = 0.5
r    = clamp(err/π·K/Rmax − damp, −1, 1)·Rmax
5adc70(now, fmod(pos, 2π), rate, r)
```
5 Hz: the same `r` from `5ae4c0` with `αT` from the `S+0x200` ramp sample (§15.1) and the stored gains.
`5adc70` picks `startAccel` if `|r| > 0.02·Rmax` (`0x611bfc`), else `stopAccel`, signed toward `r − rate`.

#### 15.2.6 β `5aa700(now, V, alt, β_cmd, flag)` (thiscall, `ret 0x18`; `alt` and `flag` unused) — v1.1
The release note "rudder response increased" is this function (v1.0 `5a78f0`, rewritten). `S+0x260` is now a
second-order channel of the α class (type B plus B/K/target, layout above):

| offset | field | offset | field |
|---|---|---|---|
| `0x260` | t0 | `0x27c` | accel |
| `0x268` | pos | `0x280` | startAccel |
| `0x26c` | rate | `0x284` | stopAccel |
| `0x270` | target rate | `0x288` / `0x28c` | ∓Rmax |
| `0x274` | T (t_end) | `0x290` | B |
| `0x278` | pos(T) | `0x294` / `0x298` | K / β_cmd |

Per call (objdump @5aa700–5aaa8a):
```
k = V < 400 ? max(V·0x8453e8 + 0x8453ec, 0.25·BetaRate) / BetaRate : 1    // 0x611cc8 = 400 (v1.0 375), 0x611cc0 = 0.25
      // 0x8453e8/ec = BetaRate·0.0025, 0 (set by 5b1f30 from 0.05·BetaRate at 20 m/s and BetaRate at 400: ×−1/380, 20)
5adc70(now, fmod(pos(τ)), rate(τ), BetaRate·k)        // re-base with the OLD limits (clamps the rate to the old ±Rmax)
Rmax = BetaRate·k (S+0x28c, −Rmax at 0x288);  startAccel = |RudderStartAccel·k|;  stopAccel = |RudderStopAccel·k|
K = RudderK·k·(|β_cmd| ≤ 0.1·MaxBeta ? 1.5 : 1)       // 0x611ccc = 0.1: centring is faster
B = RudderBeta·k;  S+0x298 = β_cmd
err  = 5bdd50(wrap(pos), wrap(β_cmd))                 // wrap(β_cmd − pos)
damp = |rate| ≤ π ? B·rate·Rmax : 0.5·B·rate·Rmax      // 0x611bd0 = 0.5
r    = clamp(err/π·K/Rmax − damp, −1, 1)·Rmax           // 0x611bcc / 0x611c00 = ±1
5adc70(now, fmod(pos), rate, r)                         // startAccel if |r| > 0.02·Rmax, else stopAccel
```
i.e. exactly the α law of §15.2.5 with the rudder keys (§1: defaults 5 / 0 / 0.5 / 0.5 when a key is missing, which is
every key but RudderK in v1.1's data and all four in a v1.0 `bd.ibx`). β_cmd = `(ru + 10·asym)·MaxBeta` (`5b4910`,
unchanged). What changed with it:
* **pos is not clamped to ±MaxBeta** (the v1.0 ramp was); the HUD-only ramp (v1.0 `S+0x260` = `k·w_z − β_cmd`, the 3°
  constant `0x60de0c`) is gone and getter 8 (`5a9280`) returns the physical β.
* Called at 1 Hz in the air, at every normal 5 Hz tick (also on the ground) and, new, at every 5 Hz tick in the spin
  (§15.1). On the ground the 1 Hz update **steps** the channel with the stored gains and command (`5ae4c0` + `5ae240`)
  instead of re-basing it, so a rudder held on the ground (the command keeps its last airborne value) still shows as β
  at lift-off.
* SetType `5b1f30` sets the channel with k = 1 (±BetaRate, |RudderStart/StopAccel|, B = RudderBeta, K = RudderK); the
  placement `5a4d40` sets pos = rate = 0 (and target rate = BetaRate, a leftover of the old ramp's rate field; the
  immediate aero update re-bases it at the same time, so it has no effect); the state-set path sets pos = 0. The β
  samplers (`5ad450`, `5acfc0`, `5b9250`, `5bb9f0`) use `fmod(pos)`.
* The slope `0x8453e8/ec` is a global written by the last aircraft type set up (like the v1.0 one, §15.10 item 14).

**Behaviour (port, `validation.rs` "rudder step", full pedal at 350 kt / 10k ft, k ≈ 0.45):** β starts from rest at
startAccel (second order), reaches 90 % of MaxBeta in ≈ 3.0 s (RudderK 5.5: F-15, F-16, MiG-29) / 2.2 s (7.5: F-4, Kfir,
Lavi, Mirage) / 2.6 s (6.25: MiG-23), ≈ 3.2 s on v1.0 data (K = 5). v1.0's ramp reached full β in ≈ 1 s at that speed,
so the v1.1 β is smoother but slower below 400 m/s, and equally fast only at k = 1. **RudderBeta = 0 (no damping)
does not make it ring**: the acceleration limit and the err/π proportional rate give a well-damped response. Holding
the pedal, β approaches MaxBeta without overshoot; after release it passes zero by at most ≈ 1.2° (≈ 10 % of MaxBeta,
F-4 at 500 kt; ≤ 0.5° at 350 kt, none at 150 kt) and settles within ≈ 1 s, a single undershoot and no oscillation.
So the original is kept as is (no better-physics option).

**Ramp limits and rates set by `5b1f30` (at SetType `5a8980`, for both state copies):** roll `S+0xa0 = |RollAccel|`,
`S+0xa4 = |StopAccel|`, `S+0xa8/0xac = ∓MaxRollRate`; the β channel as above (v1.0: ramp `S+0x290 = |BetaRate|`,
`S+0x294/0x298 = ∓MaxBeta`, the same for `S+0x270..0x278`); the **nose-wheel ramp `S+0x2b8 = |BetaRate|`, `S+0x2bc/0x2c0 = ∓MaxBeta`**; lift ramps
`S+0x1f0 = |MaxWeight·G_Rate·g|`, `S+0x1f4/0x1f8 = MaxWeight·(MinG−1)·g / MaxWeight·(MaxG−1)·g` (same for `0x210..0x218`
with `G_RateForAoa`); α as above with f = 1; fuel `S+0x440 = |FuelFlow|`, limits `[0, FuelWeight]`; RPM `S+0x1c8 = 100`.
The constructor value `S+0x2b8 = 10000` (@5ba20a) quoted in §14.1 is overwritten here, and the placement init
`5a4d40` sets `S+0x2b8 = |BetaRate|` again (@5a5066). **So the nose-wheel yaw is a ramp at `BetaRate` (rad/s²) clamped to
±MaxBeta (rad/s)**: F-16 32°/s² and ±15°/s, which is below `K` = 20°/s. §14.1 ("in effect instant") was wrong.
The slopes `0x845420/24` (G_Rate), `0x845440/44` (G_RateForAoa), `0x8453e8/ec` (β gain k) are **globals** written by `5b1f30`,
i.e. by the last aircraft type set up; all aircraft use them (see mismatch list).

### 15.3 Attitude — mode object vtable `0x611db0` slot 0 `5b9250(&out, &now)` → slot 1 `5b9530`
`5b9250` (reads `S = veh+0xc30`): `τ = clamp(now − S+0x28, 0, 1.1)`; `φ = fmod(roll(τ), 2π)` (channel `S+0x80`);
`β = fmod(β(τ), 2π)` (channel `S+0x260`, not clamped; v1.0 the ramp `S+0x280`, clamped); `v = (vx, vy, vz)(τ)`;
`α = fmod(α(τ), 2π)`; then
`5b9530(&out, τ, vx, vy, vz, φ, α, β, S, &speed)` (`ret 0x28`):
```
*speed = |v|
if S+0x2a0: return 5bb300(...)                                 // ground attitude (§14)
f = v/|v|;  w = S+0x08 (left wing at the last 1 Hz/5 Hz 5aa330);  dφ = φ − S+0x18
if dφ ≠ 0: n = row 1 of Euler(S+0x14, S+0x18, wrap(S+0x1c))    // the saved attitude's body nose axis (43ecd0/43d5e0)
           w = R(n, wrap(dφ))·w                                  // v1.1; v1.0 rolled about f. Rodrigues 459ac0/459b30/459b80/459ba0
if α  ≠ 0: f = R(w, wrap(−α))·f                                  // nose above the velocity
if β  ≠ 0: n = w × f (explicit, @5b98eb);  f = R(n, wrap(β))·f     // n = "down" in body axes → β > 0 = nose right
heading = (fx == 0 && fy == 0) ? 0 : atan2(fx, fy);  pitch = asin(fz)      // both wrapped (44f5f0)
Mx = I · rot(−pitch) (44f6c0) · rot(heading) (44f880);  wl = w·Mx (43dd70)
c = clamp(−wl.x, −1, 1)  ((0x845480..88) = (−1, 0, 0), initialiser 0x6236e0 → 5b9230)
roll = acos(c);  if wl.z < 0: roll = −roll;  roll = wrap(roll)
out = (pitch, roll, heading)
```
**v1.1 change ("roll improved"):** the roll turns the wing about the body nose of the attitude saved at the last update
(`5aa330`), not about the velocity; α and β still rotate the velocity direction. With α ≈ 0 both agree; with α the v1.0
roll swung the nose on a cone around the velocity. `w` is **not** re-orthogonalised against `f`; the roll is measured
from the raw `w`. `wrap` = `fmod(x, 2π)`, then
`−2π` if `> π`. `f` is undefined for `v = 0` (UNCERTAIN: x87 NaN). The same `τ` (X-axis base) is used for all channels.

### 15.4 Mode objects (`S+0x04` = current mode)
Created in the FM constructor @5a323f–5a32e0 (8 bytes each: `+0` vtable, `+4` owner). Slot 0 = sampled attitude
`(out, &now)` → (pitch, roll, heading), slot 1 = attitude with extra outputs (`ret 0x28`), slot 2 = position, slot 3 =
velocity, slot 4 shared `5b7760`.

| field | vtable | slots 0..4 | what it is |
|---|---|---|---|
| veh+0xc6c | 0x611db0 | 5b9250, 5b9530, 5b9bb0, 5b9cc0, 5b7760 | normal flight (§15.3) |
| veh+0xc70 | 0x611d98 | 5b8b70, 5b8dc0, 5b9000, 5b9110, 5b7760 | **spin** (the only departure mode) |
| veh+0xc7c | 0x611d80 | 5b6fb0, 5b7230, 5b74a0, 5b75b0, 5b7760 | "Tornado": player map-edge push-back (`CancelTornadoEvent`) |
| veh+0xc74 | 0x611d68 | 5b7fd0, 5b83b0, 5b8950, 5b8a60, 5b7760 | scripted, motion 21 (`5b0b00`), own channels S+0x4e0..0x5e0 (UNCERTAIN) |
| veh+0xc78 | 0x611d50 | 5b7870, 5b7a70, 5b7c50, 5b7d40, 5b7e30 | scripted, motion 22 (`5a8d40`); heading ramp S+0x130, re-based by `5b7e60` at the end of each normal 5 Hz tick — a flat 3 s pivot turn about a point 30 m to the turn's side, the AI's taxi turns (docs/ai.md §8.2; ported: `Aircraft::set_pivot`) |

**There is no separate stall mode and no tail-slide mode.** "Stall" = the 3 s zero-lift latch (§15.2.4) inside normal
mode; the only departure is the spin. c74/c78 are scripted (mission/AI) manoeuvres, not triggered by the flight model.

**Where the modes run.** `5a70f0` (1 Hz/events) computes `acc` first (@5a784b), then the latch (@5a7863), then calls
`5aab90` (@5a78ba) and `5ac5d0` (@5a7913) **every time, in every mode**; afterwards it uses their in/out `L`,
`Lnoflap`, `acc`, `p_cmd`. In the 5 Hz tick, `S+4 == c70` → `5aab90` (@5a454d), swap, return; `S+4 == c7c` →
`5ac5d0(…, enter = 0, …)` (@5a45ba), swap, return. Their outputs are discarded there and the normal force/axis update
is skipped, so in both modes the axes are re-based only by the aero update or by the mode's exit.

`5aab90` args (thiscall, `ret 0x3c`, 15 stack args): A1:A2 now, A3 `τ` (X-axis), A4 dragX (fresh Lift output at 1 Hz,
`S+0x2f0` at 5 Hz), A5 V, A6 β(t) (`fmod` of the channel `S+0x260`, before this update's new target), A7..A9 pitch/roll/heading,
A10 &acc, A11 &L, A12 &Lnoflap, A13 &p_cmd, A14 &α (never read back), A15 &β_cmd (never written). `5ac5d0`
(`ret 0x40`) has an extra A10 = enter flag (0 from the updates, 1 from `5ad450`), pointers shifted to A11..A16.
π/2 = `DAT_008453f4` (initialiser `0x627724 → 5a2f40`).

### 15.5 Spin (veh+0xc70) — `5aab90`
**Channels** (limits from `5b1f30` @5b2133–5b21c3): yaw angle `S+0xb0` (type B; startAccel `|0.4·RollAccel|`,
stopAccel `|0.2·StopAccel|` (0x612060/0x61205c), rates **±0.4·MaxRollRate** (0x612064/60); `5ae450` clamps the
target rate, so the nominal π/2 is always capped: F-16 80°/s, F-15 72, F-4 32, Mirage/Kfir/MiG-23/MiG-29 60,
MiG-21 28, Lavi 88); pitch ramp `S+0xe0` (rate `|0.05·MaxRollRate|` (0x612058), limits ±π/2); roll ramp `S+0x100`
(same rate, limits ±π); arm timer `S+0x128` (double, −1 = disarmed).

**Entry** (normal mode, aero update only):
```
if veh+0xc54 ∈ {100, 140}: return                          // F-16, Lavi (type codes of 5a8980)
veh+0xc3c = 1                                               // v1.1: dirty flag, cleared again below when not entering
spinsOff = multiplayer(DAT_00699350 && [+4]) ? 0 : pref+0x34          // "No spins"
qual = |β(t)| ≥ 0.8·|MaxBeta (P+0xb8)| && dragX > 0.57 && !netgame(DAT_0082f398)   // 0x611cd8 = 0.8 (f64), 0x611ce0 = 0.57
// stage 1 @5aabfe
timer = (timer == −1 && qual && !spinsOff) ? now : −1        // also resets an armed timer
// stage 2 @5aacea
if (now ≤ timer + 1.2 || !qual) && !damage(0x18): veh+0xc3c = 0; return      // 0x611ce8 = −1.2 (f64, subtracted)
ENTER
```
Effective rule: the spin starts at the **second consecutive qualifying aero update**, whatever their spacing (the 1.2 s
never bites: stage 2 sees −1 + 1.2 < now). **With "No spins" on the timer is never armed, so the spin starts at the
first qualifying update** (a bug: the preference makes spins easier). Damage 0x18 ("Total flight control",
`FUN_0044d760`) forces entry regardless of β, dragX and preferences. β ≥ 0.8·MaxBeta needs ≈ 80 % rudder (β_cmd =
(ru + 10·asym)·MaxBeta, so heavy asymmetric stores also qualify); dragX > 0.57 means code 0/2 or latched (dragX = 1.2)
or pulling more than 0.57·MaxG over the envelope limit (dragX = (g_cmd − lim)/MaxG). "No stalls" does not prevent it
(dragX is still 1.2 on codes 0/2).

On entry (@5aad56): `S+4 = veh+0xc70`, player sound `4dece0`; `s = sign(β)` (+1/−1/0); yaw channel pos0 = heading,
rate0 = 0, target `s·π/2` (clamped), then `5adc70` re-base; pitch ramp reset to the current pitch (if within ±π/2),
target **−30°** (`0xbf060a92`); roll ramp reset to the current roll (if within ±π), target **+0.1 rad**
(`0x3dcccccd`). This update's L and acc stay normal.

**Update** (`S+4 == c70`, every aero update and 5 Hz tick):
```
acc.x = acc.y = 0
s1 = ftol(sign(yaw rate of S+0xb0 sampled with the axis τ))     // quirk: not its own τ
s2 = ftol(sign(β))
if s1 == −s2 && s1 != 0:                                        // opposite rudder slows the rotation
    yaw target = s1·π/2 + β·π/(2.2·MaxBeta)                      // 0 at β = −1.1·MaxBeta·s1 (0x611cf0 = 1.1; v1.0 0.9 →
                                                                // π/(1.8·MaxBeta)), MaxBeta = P+0xb8 (v1.0 the β ramp limit), clamped
stay = airborne && ( !(s1 > 0 && β ≤ −0.9|MaxBeta|) && !(s1 < 0 && β ≥ 0.9|MaxBeta|)  ||  dragX ≥ 0.1 )
                                                                // 0x611cf8/0x611d00 = ∓0.9 (f64), 0x611ccc = 0.1
if stay:
    L = Lnoflap = p_cmd = α_out = 0
    acc.z = min(0, 0.04·V − 9.806)                              // 0x611d08 = −0.04, 0x611d0c = −9.806
    re-base S+0x100, S+0xe0, S+0xb0 (targets kept; the yaw channel with its own τ)
    re-base the axes X, Y (5adc30) and Z (5adae0, new: also clamps the height to the axis limits), acceleration kept   // v1.1
else: EXIT
```
Consequences: in 5a70f0 both lift ramps go to 0, the α target is the zero-lift α, the roll target is 0, and the axes
get `acc = (0, 0, min(0, 0.04V − g))`. **The horizontal velocity stays frozen at its entry value**; the vertical
acceleration is 0 at |v| = 245.15 m/s (|v| includes the frozen horizontal part). β keeps following the rudder
(`5aa700` at every aero update and, v1.1, at every 5 Hz tick of the spin), and β drives the recovery. Recovery needs
**≥ 90 % opposite rudder and dragX < 0.1** (no latch, not below Vmin, not over-pulling). With the v1.1 slope the yaw
target at full opposite rudder (β = −MaxBeta) is s1·(π/2 − π/2.2) = s1·0.14 rad/s: the rotation slows to ≈ 8°/s but
keeps its sign, so s1 stays and the exit test decides (v1.0: π/2 − π/1.8 < 0, the yaw reversed). If s1 == 0 the spin
never ends in the air (only touchdown ends it). The axis re-base in the stay branch changes nothing physically (the
acceleration is kept); `veh+0xc3c` is the FM's "state changed" flag also set by the event handlers (UNCERTAIN: read by
the network update; no effect in single player, not ported).

**Spin attitude** (slot 0 `5b8b70`): one τ = clamp(now − S+0xe0 t0, 0, 3.5) for all three; pitch = ramp `S+0xe0`,
heading = yaw angle `S+0xb0` (fmod 2π), roll = ramp `S+0x100`, all wrapped to (−π, π]. The nose settles at −30° pitch
and +5.7° bank while the heading turns at up to 0.4·MaxRollRate, unrelated to the velocity.

**Exit** (@5ab6e7; same shape in `5ac5d0` and `5acfc0`): `f = 46d056(att)` = nose vector (UNCERTAIN convention,
consistent with (cos p·sin h, cos p·cos h, sin p)); `5aa330(att)`; `u = f × w`;
`f2 = R(w, α(t))·R(u, β)·f` (α from `5a91d0`; UNCERTAIN signs/order); **velocity := f2·V** (axes re-based, position and
old acceleration kept); roll channel re-based at pos = roll (rate/target kept); `S+0x128 = −1`; acc.x = acc.y = 0;
`p_cmd = s1·0.1`; `S+4 = veh+0xc6c`; player sound `4def50`.

### 15.5a "Tornado" (veh+0xc7c) — player map-edge push-back
Trigger in `5bb9f0` (@5bbb42–5bbc64, every 5 Hz tick, before the air/ground logic): `flags = 4024b0(terrain, ftol X,
ftol Y)`. `flags & 0x300`: play EndWorld.wav + Kramer18.wav once (latch `DAT_0084548c`, cleared when neither bit is
set). `flags & 0xc0`, player, not already in c7c: `5ad450(&now, pitch, roll, heading)` + Kram1.wav. (UNCERTAIN: the
cell flags mark the map border.)
`5ad450`: schedules `CancelTornadoEvent` (vtable 0x611e68) at now + 8 (`0x611d38`) → `5ae9c0` → `5acfc0` (exit as the
spin); ramps `S+0x168 = −1.5·V·sin h`, `S+0x188 = −1.5·V·cos h` (`0x611d40`, limits ±1e8) each targeting 0 at rate 10;
`5ac5d0(enter = 1)`: yaw target ±2π (clamped ±0.4·MaxRollRate, sign of roll), roll `S+0x80` target ±2π (clamped
±MaxRollRate), pitch target +50° (`0x3f5f66f3`).
Each update: `acc = (S+0x168(t), S+0x188(t), −1.0)` (ramps sampled with the axis τ ≤ 1.1, so they never decay:
UNCERTAIN, verify in game), `L = Lnoflap = p_cmd = α = 0`, channels re-based; on the ground it exits (`5ae080`).
Attitude (`5b6fb0`): pitch `S+0xe0`, roll `S+0x80`, heading `S+0xb0`.
Only needed if our world has the equivalent map-edge cell flags (low priority).

### 15.6 Touchdown, landing and crash (`5bb7d0`, `5bb9f0`), and the start rules

#### 15.6.1 Landing check `FUN_005bb7d0(τ, vz)` (thiscall, `ret 8`, returns 1 = crash)
Called only from `5bb9f0` @5bbb62, once per 5 Hz tick at touchdown. `τ` = Z-axis τ, `vz = v_z + a_z·τ`.
```
if 5abef0(&gameTime): return 0                       // crash immunity, 15.6.3
θ = S+0x14, φ = S+0x18        // Euler saved by 5aa330 at the LAST aero/5 Hz update (not re-sampled)
Lp = DAT_008454b8 = 5°   (1°·5.0,  0x612460, initialiser 0x6277b4 → 5babf0)
Lr = DAT_008454c8 = 10°  (1°·10.0, 0x612464, initialiser 0x6277bc → 5bac20)
Lv = −40.0 m/s           (0x612444)
if multiplayer || pref+0x3c ("Easy landing", default ON): Lp, Lr, Lv ×= 2
gear = S+0x320 ramp sampled with the Z-axis τ
if |gear| ≥ 1e-5 (not fully down, 0x6124e0): Lp ×= 0.2, Lr ×= 0.2 (0x6124e8), Lv ×= 0.25 (0x6124ec)
r = 4020a0(x, y, &h, &nx, &ny, &nz)                  // terrain normal (TgenAPI slot 0x4c)
OK ⇔ θ ≥ −Lp && |φ| ≤ Lr && vz ≥ Lv && (r == 0 || |nz/|n|| ≥ 0.9848077 (cos 10°, 0x6124f0))
```
| gear | Easy landing off | Easy landing on (default) |
|---|---|---|
| fully down | nose-down 5°, roll 10°, sink 40 m/s | 10° / 20° / 80 m/s |
| not fully down | 1° / 2° / 10 m/s | 2° / 4° / 20 m/s |

No nose-up (tail-strike), speed or sideslip limit. **There is no other terrain collision in the FM**: flying into the
ground is a touchdown that fails this test (nose-down, sink, roll or slope > 10°). Because it runs at 5 Hz, Z can be
up to 0.2·|vz| below the ground when it runs. UNCERTAIN: meaning of `4020a0`'s return value.

#### 15.6.2 `5bb9f0` side effects (adds to §14.6)
Terrain flags `f = 4024b0(trunc X, trunc Y)` (terraintype.dat, formats/ptt.md "Terrain types"): `f&6` water, `f&0x30` runway, `f&9` rough
ground, `f&0x300` map edge, `f&0xc0` border (Tornado, §15.5a).
* **Touchdown** @5bbd1e: `S+0x2a0 = 1`. Check failed → `4a8ae0(dmgObj, 0.0, 5, 0x832150)`: unit state 5 = destroyed
  (`4a8420`), player gets the FF "Crash" effect. Z axis as §14.6, `5a70f0(now)`. Rough ground and V > 25.736 m/s and not
  immune → destroyed. Water → `S+0x2c8 = 4`. Gear not fully down → `S+0x2c8 = 2` (belly; player, not crashed: FF Crash,
  FF OutRunway, SFX_SCREECH 0x29 on the runway). Gear down, player, not crashed: FF Landing, FF OutRunway when off the
  runway, SFX_TOUCHDOWN 0x28, then the **landed flag**: `if ctl+0xe0 == 0: 440f90()` (the mission's landed handler);
  `ctl+0xe0 = 1` (v1.0 called `441000`, which did the same). `ctl` = the player's mission object (`[[veh+0xc]+8]+0x2c`).
* **Lift-off**: as §14.6, plus `S+0x2c8 = 0` and the OutRunway FF stops, and (v1.1) `ctl+0xe0 = 0`: the flag is re-armed,
  so the landed handler fires on **every** landing (v1.0 never cleared it: only the first landing of a flight counted).
  Port: `State::landings` counts the handler calls (+1 at each gear-down touchdown that passes the check after a
  lift-off or at the first one); the host fires the mission's landed trigger when it grows (Godot state `landings`).
* **Rolling, every 5 Hz tick**: rough ground and V > 25.736 and not immune → destroyed; if `S+0x2c8 ∉ {2,4}`:
  runway && landing check OK → `S+0x2c8 = 0`, else 1 (OutRunway FF on); player and V < 5.1472 m/s (0x612500) →
  OutRunway off; `S+0x2c8 == 4` (water) and not immune → destroyed every tick (returns before clamping Z); otherwise
  Z p0 = clear, t0 = now.
* `S+0x2c8`: 0 runway, 1 off-runway ground, 2 belly, 4 water. The `0x83afc8` calls are DirectInput force-feedback
  effects (StallShake `4de6a0`/`4def40`, OutRunway `4de730`/`4def30`, Landing `4de970`, Crash `4dec00`), not sounds.

#### 15.6.3 Crash immunity `FUN_005abef0(&now)` (1 = cannot crash)
```
ai = 5c89f0() != 0;  mode = 5c89f0()
cheat  = !ai && prefsApply && (pref+0x20 "No crashes" || pref+0x1c "Invulnerable")
         // prefsApply = !multiplayer || DAT_00699428 ("Multiplayer/PreferencesApply")
aiOld  = ai && now − [veh+0xc50]+0x10 > 3.5 (0x611d20)
lowDmg = dmgObj+0x10 ≤ 0.1 (0x611ccc; Ghidra shows it inverted)
fuel   = S+0x430(t) > 0;   teamOK = !(team test && mode == 0x11)
if dmgObj+0x14 == 0: return 0
return cheat || (mode == 9 && fuel) || (aiOld && fuel && lowDmg && teamOK)
```
In practice an AI jet with fuel never crashes on landing.

#### 15.6.4 Mission start `FUN_005a5820(&now, pos[6], vel[3])` (FM vtable 0x611dc8 slot 2)
`pos` = (x, y, z, pitch, roll, heading). Reached through the vtable (e.g. the mover hand-over `4658f1` passes the
previous mover's position and velocity; UNCERTAIN which mover precedes the player's FM).
```
S+4 = veh+0xc6c (normal mode)
vz = vel.z;  if vel == 0: vz = veh+0xc40.z (constructor 0; no other writer found)
Vh = sqrt(vel.x² + vel.y²);  v = (Vh·sin ψ, Vh·cos ψ, vz), ψ = pos[5]      // heading overrides the vel direction
axes: p0 = pos, t0 = now, v, a = 0;   roll channel S+0x80: pos = pos[4], rate 0, target 0
sticks 0; S+0x128 = −1; stall latch S+0x2f8 = −1; S+0x420 = 0; S+0x1d8 = EmptyWeight
ramps S+0x360 := 0 (rate 0.5); S+0x380/3a0/3c0/3e0/400 := 0 (rate 0.7)
airborne ⇔ z > 800 (0x611c40) && !(dist_h(pos, base) < 5000 (0x611c44) && |z − base.z| < 15 (0x611c18))
           base = 551280(x, y, z) = the iaf.ibx airbase with the nearest Lineup point; the 5000 / 15 m test is
           against its Tower point, the 100 m engine test against its Lineup point (docs/ai.md §7.1, §9)
AIRBORNE: S+0x2a0 = 0; engine on; Euler = (asin(v̂z), pos[4], pos[5]) via 5aa330
          gear S+0x320 = 1.569 (up), flaps 0, brakes S+0x340 = 0, all rate 0.5
          throttle 0.74; RPM ramp 70 → 70, rate 15
          lift ramps S+0x1e0/S+0x200: value = target = MaxWeight·9.806 (5ad8a0)
GROUND:   Euler = (pos[3], 0, pos[5]); velocities 0 (a kept); Z p0 = pos.z + |model height|
          gear 0 (down); flaps S+0x300 = 0.29275 (= full: ×3.4158838 = 1.0); brakes S+0x340 = 0.855 (on)
          throttle 0; RPM 0 (rate 15); lift ramps 0
          engine ON only if dist_h(pos, runway start point) ≤ 100 m (0x611c48), else OFF
both: fuel S+0x430 = FuelWeight (full), rate 0; controller (44a240, forced): gear lever := S+0x2a0, on the ground also
      flaps (GEV 0xc) and brakes (GEV 0x11) with arg 1; swap; immediate aero update (5a4200);
      aero timer 1.0 s (veh+0xc58, 0x611e58), accel timer 0.2 s (veh+0xc5c, 5ae830); S+0x2cc = S+0x2d0 = 0
```
A start at ≤ 800 m (or near the base) is placed on the ground at its z; the next 5 Hz tick snaps Z to the terrain.
The α channel and the β channel are not reset here (UNCERTAIN).

`FUN_005a4d40(&now, pos[6], vel[3])` (re-placement; callers 5a8510, 5a91b2, 5b0b76, 5d6393, 5d6842): axes p = pos,
v = vel, a = 0; roll = pos[4]; `S+0x2a8` := 0 at rate |BetaRate|, β channel `S+0x260` pos = rate = 0 (§15.2.6); α := 0; airborne ⇔
`terrain(x,y) + |h| < z` (0x611c10 = 0.0). Airborne with |vel| > 0: pitch = asin(v̂z); with vel = 0: velocity = unit
vector of the old Euler `S+0x14` × 10 m/s (0x611c20); **throttle 0.7**, engine on, RPM 70, lift ramps = MaxWeight·g.
Ground: `S+0x2a0 = 1`, Euler (pos[3], 0, pos[5]), vz = 0, throttle 0, engine on, RPM 0, lift ramps 0. Gear, flaps and
fuel untouched; timers restarted.

**Control ramps** (constructor helper `5ba430(min, max)`: value 0, rate 10000; rates below are set by `5a5820` only):

| ramp | motion | min / max | rate | full throw |
|---|---|---|---|---|
| `S+0x300` flaps | 6 `59fba0` | 0 / 0.29275 | 0.5/s | 0.585 s |
| `S+0x320` gear | 7 `59fdc0` | 0 (extended) / 1.569 (up) | 0.5/s | 3.1 s |
| `S+0x340` brakes | 8 `59ffc0` | 0 / 0.855 | 0.5/s | 1.7 s |
| `S+0x360` hook (cfg[8]) | 9 `5a01c0` | 0 / 0.7855 | 0.5/s | 1.57 s |
| `S+0x380` | — | ±0.3926 | 0.7/s | |
| `S+0x3a0`, `S+0x3c0` | — | ±0.5236 | 0.7/s | |
| `S+0x3e0`, `S+0x400` | — | ±0.7855 | 0.7/s | |

Flaps "on" target = max × (0.33 if `veh+0xc54 == 100` else 1) (UNCERTAIN which type is 100); gear "on" → 0;
motions 8/9 "on" → max, "off" → min. After a `5a4d40` ground re-placement (or the constructor alone) the rates stay
10000, i.e. instant (UNCERTAIN in real play).

### 15.7 Preference flags (pref instance `DAT_00699424`, copied from the menu object by `FUN_004fe430`)
| pref | menu name | default (`FUN_00450e30`) | where it acts in the FM |
|---|---|---|---|
| +0x18 | Unlimited ammo | 0 | — |
| +0x1c | Invulnerable | 0 | crash immunity `5abef0`; ground aero `5bac40` "easy" (lift gate, no belly μ) |
| +0x20 | No crashes | 0 | same as +0x1c |
| +0x24 | No malfunctions | 1 | — |
| +0x28 | No wind | 1 | — |
| +0x30 | No blackouts | 0 | §13 |
| +0x34 | **No spins** | 0 | spin arming `5aab90` @5aac7e (only skips the arm step: spins start *earlier*, §15.5) |
| +0x38 | **No stalls** | 0 | Lift `bStall` @5b44e8 (§14.3); vibration allowed `P+0x84` (`5b2940`) |
| +0x3c | **Easy landing** | **1** | landing limits ×2 (`5bb7d0` @5bb84a); ground lift gate (`5bac40` @5bae6e) |
| +0x40 | Easy aiming | 1 | — |
| +0x44 | Unlimited fuel | 0 | fuel flow 0 (`5b4120` @5b443c) |
| +0x50 | AI level 0/1/2 | 2 | Lift AI branch (`5b4470` @5b44a1) |

In multiplayer: "No stalls" and "No spins" are ignored (treated as off), Easy landing is forced on, and
Invulnerable/No crashes apply only if `DAT_00699428` ("PreferencesApply") is set. Rows confirmed from the Gameplay page
draw code @516270 and its rect table `0x60a7b0`.

### 15.8 Throttle and AB light-up delay (`FUN_0059f7d0` motion 2, `FUN_0059faf0`)
```
if !ai && !engineOn: engineOn = 1, dirty = 1              // the first throttle event starts the engine
changed = !ai ? |new − thr| ≥ 0.015 (0x611b18) : new != thr   // the player's smaller moves are ignored
if changed:
    engineOn (S+0x1d0) = 1
    if !ai: cancel the c68 timer (4ce950)                    // v1.1: every change, also a new AB request
    if !ai && thr < 0.75 && new ≥ 0.75:
        thr = 0.74 (0x3f3d70a4); dirty = 1
        veh+0xc68 = timer(now + max(0, (S+0x1c8 − RPM(t))·0.0666667), copy of the event)   → 59faf0
    else: thr = clamp(new, 0, 1)
    dirty = 1
if dirty: 5a70f0(now); 5a8370()
59faf0 (ret 0x28): if veh+0xc68 ≠ 0: thr = clamp(requested, 0, 1); 5a70f0(gameTime); swap; veh+0xc68 = 0
```
The delay is the time the RPM ramp (0..100, 15 %/s, `S+0x1c0`, `0x612050`) needs to reach 100 %: 2.67 s from idle
(RPM 60), 0 from military. **v1.1:** a second AB request while one is pending cancels it and schedules a new timer from
the RPM at that moment with the new value (v1.0 left the older timer running; it applied the older value and cleared
c68, so the second request did nothing). Keys use the same handler: motion 3 (`59f330`) adds 0.0925 only if the
result stays ≤ 1.0 (so keys top out at 0.925 = AB2), motion 4 (`59f370`) = max(thr − 0.0925, 0). Motion @5a2890 writes
`S+0x1d0` (engine on/off). RPM ramp target = 100·rpm (`S+0x1c8` = 100), so full AB (rpm 1.14) shows 100.

### 15.9 Exact envelope algorithm (ported in `envelope.rs`)
All float32 with x87 intermediates; `trunc` = `_ftol` (toward 0). Constants: `0x6121b4` = 0.5147222 (kt→m/s),
`0x6121b0` = 0.3048, `0x61218c` = 0, `0x612190` = 1, `0x6121c0` = −1, `0x612198/a0/a8` = 0/−1/1 (f64), `0x6121b8` = 1e-5
(f64), sentinel altitude `0x46ea6000` = **30000.0 m**. `E` = `P+0` in the static per-type array `0x843e30`
(14 × 0x18c, BSS; v1.0 0x17c); the constructor `5b4e70` sets only `E+0x14` (idx0) = −20; `5b2940` loads a type once
(ref count `P+0x17c`, v1.0 `0x16c`). Nothing in the CRT table touches the envelope.

| field | meaning |
|---|---|
| `E[0]` | 14 row pointers; `row[r][slot] = (alt m, vel m/s)` |
| `E[3]` | per slot: index of the last real row |
| `E+0x14 / 0x18 / 0x1c` | idx0 (slot of the g=0 graph) / NumberOfG-Graphs / step (m) |
| `E+0x20 / 0x24` | gmin / gmax |
| `E+0x28/2c/30`, `E+0x34/38/3c` | positive / negative high-altitude line (a, b, 1/a) |
| `E+0x44/48`, `E+0x58/5c` | per-level point lists and counts, g ≥ 0 / g ≤ 0 |

**Loader `5b5490`.** `NumberOfG-Graphs`, `AltitudeStep` via `GetPrivateProfileIntA("Params", …)`, `step = int·0.3048`.
14 rows × (NumG+2) slots, not bounds-checked (≤ 13 real rows + sentinel; shipped files have ≤ 12). Finds
`[Min Velocity Table]`, pass 1 (`5b5fe0`), then pass 2 (`5b5bf0`) re-reads the file.

**Pass 1 `5b5fe0`** (until a line starting with `[`):
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
C0 = ceilAlt(idx0); Cmax = ceilAlt(idx0 + trunc(gmax)); Cmin = ceilAlt(idx0 + trunc(gmin))      // @5b56d6
if Cmax ≠ C0: a28 = gmax/(Cmax − C0); b2c = gmax − Cmax·a28          (else 0)
if Cmin ≠ C0: a34 = gmin/(Cmin − C0); b38 = gmin − Cmin·a34
```
**Pass 2 `5b5bf0`** (raw file rows, no sentinel/pads, same `%d %d %d` filter):
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
(vtable 0x6121f8 slot 6 = `5b64d0`) keeps each list **ascending by V**, a new point going after equal V.
F-16: 24 levels per list; level 0 positive: g0 46 kt, g1 86, …, g9 417; level 20: only g0 (290 kt).

**Ceiling `5b53b0(g)`:** `g = clamp(g, gmin, gmax); i = trunc(g); d = g > 0 ? 1 : −1; A = idx0 + i; B = A + d;
f = g > 0 ? i + 1 − g : g − i + 1; return ceilAlt(B) + (ceilAlt(A) − ceilAlt(B))·f` (= linear interpolation).

**Vmin `5b5070(alt, g, ceil)`** (`ret 0xc`; every FM caller passes `ceil = Ceiling(g)`; AI callers at 0x5cc…–0x5d1…
not checked, UNCERTAIN):
```
g = clamp(g, gmin, gmax); alt = clamp(alt, 0, ceil − 1)
if g < 0: return 5b5240(alt, g)                 // same with B = A − 1, gB = gA − 1
A = idx0 + trunc(g); B = A + 1; gA = trunc(g); gB = gA + 1
iA = last row r of slot A with alt_r ≤ alt (walk from 0, the sentinel stops it); iB = same in slot B
(a, b, c) = plane((altA[iA], gA, vA[iA]), (altA[iA+1], gA, vA[iA+1]), (altB[iB], gB, vB[iB]))
return a·alt + b·g + c
```
At integer g this is linear in altitude; at fractional g the g-slope uses graph B's row at or below `alt`, not B's
value at `alt` (not bilinear). For g in (−1, 0): A = g0 graph, B = g−1 graph.

**Plane `5bf2a0(out, P1, P2, P3)`**, z = a·x + b·y + c:
```
det = (y3−y1)·x2 + (y2−y3)·x1 + (y1−y2)·x3
if det == 0: a = b = 0
else: a = ((z3−z2)·y1 + (z2−z1)·y3 + (z1−z3)·y2)/det;  b = ((z3−z1)·x2 + (z1−z2)·x3 + (z2−z3)·x1)/det
c = z1 − a·x1 − b·y1
```
**Bracket `5b6400(list, V, &lo, &hi)`:** walk ascending; `p.V ≤ V → lo = p`, `V ≤ p.V → hi = p` (stop when both
found); lo = last point with V_p ≤ V, hi = first with V_p ≥ V (equal → lo = hi). Returns 1 if no hi (V above all
points; also for an empty list), −1 if no lo, else 0.

**GLimit `5b58e0(alt, V, g, &lim)`** (`ret 0x10`):
```
k = max(trunc(alt/step), 0)
L = g > 0 ? posList : negList                          // g == 0 uses the negative list
if k + 1 > count(L) − 1: lim = −1; return 2            // F-16: alt ≥ 23·step = 21031 m
a = bracket(L[k], V, lo, hi);  b = bracket(L[k+1], V, lo1, hi1)
if a > 0:                                              // V above every point of level k
    if Ceiling(g) ≥ alt: lim = g; return 3
    lim = 5b5840(g, alt); return 4
if a < 0 || b < 0: lim = −1; return 0                  // STALL: below the lowest (g0) point of level k OR k+1
PC = (b > 0 || (|hi1.g − lo.g| ≥ 1e-5 && |hi1.g − hi.g| ≥ 1e-5)) ? lo1 : hi1
(a, b, c) = plane((L_k, lo.V, lo.g), (L_k, hi.V, hi.g), (L_{k+1}, PC.V, PC.g))    // x = alt, y = V, z = g
lim = a·alt + b·V + c                                  // lo == hi → det = 0 → lim = lo.g
if g > 0 && lim < 0: lim = 0;   if g < 0 && lim > 0: lim = 0      // no forcing for g == 0
return 4                                               // code 1 is never returned
```
`L_k = k·step`. **`5b5840(g, alt)`** (above all points, confirmed): `g = clamp(g, gmin, gmax); g ≤ 0 ?
min(a34·alt + b38, 0) : max(a28·alt + b2c, 0)` — the line from (ceilAlt(gmax graph), gmax) to (ceilAlt(g0), 0), and the
mirror with gmin. F-16: `14 − 6.5617e-4·alt` (9 g at 7620 m, 0 at 21336 m), `−10.5 + 4.9213e-4·alt`.

**F-16 `16.dat` check** (Python reconstruction `tools/envelope_ref.py` vs the old linear `envelope.rs`; the ported
version now matches the "original" column, test `f16_file_matches_the_audit_table`):

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
"PO" = port as original. "BP" = original looks wrong → candidate for an `Aircraft::better` option (`BetterPhysics`) (the default stays
the original). Already decided and not repeated: the 1 g hold (original by default, γ-based under `flight_path_hold`).

1. **Envelope** (`envelope.rs` l. 141–174; known deliberate deviation, §10) — PO, using §15.9 exactly. The linear
   version is not just smoother: (a) the stall test must be "V below the lowest point of level k **or** k+1" (F-16 sea
   level 52 kt instead of 46 kt; at 48–50 kt the port gives lift where the original stalls and latches); (b) the
   "above all points of level k" branch must use Ceiling and then the `5b5840` line (the port allows 3–5 g too much
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
   treat as recoverable; (f) the yaw-rate sign is sampled with the axis τ. (v1.1 retuned the recovery slope to
   π/(2.2·MaxBeta) and runs β in the spin at 5 Hz, §15.5; not BP items any more.)
4. **Nose-wheel yaw is instant and unlimited** (l. 278–286, 593) — PO: ramp `S+0x2a8` toward the 7a20 yaw at
   `|BetaRate|` (rad/s²), clamped ±MaxBeta (F-16 32°/s², ±15°/s < K = 20°/s); the 5 Hz force uses the ramp sample,
   the 1 Hz/event force uses the raw target (§15.2.6, correcting §14.1).
5. **Force decomposition angles** (`apply_forces` l. 560–566) — PO: the 5 Hz tick must use `αT` (from the `S+0x200`
   ramp sample, clamped by LimitAlphaVisual, §15.1 step 6) and `β(t)` (the β channel); the 1 Hz/event path uses `α(t)` and the
   commanded `β_cmd = rudder·MaxBeta` (§15.2.2). The port uses α(t)/β(t) in both. BP: `M` already contains α(t) and
   β(t), so using αT leans the lift forward by αT − α(t) during a pull (free forward force) and β_cmd applies the side
   force before the nose has yawed; better: α(t) and β(t) in both paths.
6. **α 1 Hz update missing** (`aero_update` has none) — PO: `5aa3a0` at every aero update/event with
   `αT = 5b4c60(V, alt, Lnoflap_target, …)` (the new target, not the ramp) and recompute the gains `f(V)` only there;
   the 5 Hz tick reuses the stored gains (the port recomputes f at 5 Hz, l. 539–542). Damping ×0.5 when |rate| > π
   (never reached with MaxAlphaRate ≤ 2.5).
7. **Gear, brake, flap ramps and `cfg`** (l. 254–255, 471–478, 481) — PO: add the gear ramp `S+0x320` (0 = down,
   1.569 = up, 0.5/s, 3.1 s); gear drag, the ground lift gate and the belly μ only when the ramp is exactly at 0; brake
   flag in the air = ramp finished at max, on the ground = any value ≥ 1e-5; flaps 0..0.29275 at 0.5/s (full = 1.0
   after ×3.4158838), brakes 0..0.855 at 0.5/s, the type-100 flaps ×0.33 (§15.6.4 table). The port's 0.25/s and
   1.0/s rates and its gear-lever test are invented.
8. **Throttle/AB** (`set_controls` l. 249–257) — PO §15.8: crossing into AB sets 0.74 and applies the request after
   `(100 − RPM)/15` s (any change cancels it, v1.1: also a second AB request, which re-times it); player moves < 0.015 are ignored; the first throttle event turns
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
12. **β channel** — PO (v1.1, §15.2.6): the second-order channel with the rudder keys (defaults for v1.0 data), gains
    from V below 400 m/s, no ±MaxBeta clamp; `5aa700` at every aero update in the air and at every 5 Hz tick (also on
    the ground and in the spin); the ground 1 Hz update steps it with the stored gains, so rudder held on the ground
    shows as β at lift-off.
13. **Roll channel and attitude details** — PO: (0) v1.1 rolls the wing about the saved body nose, not the velocity
    (§15.3); (a) `kroll` has no lower clamp (port `.max(0.0)`, l. 503; negative
    below Veff ≈ 9.5 m/s); (b) the roll channel is re-based with `pos = attitude roll` and `5aa330` refreshes
    `w`/`φ_ref` at the 1 Hz update as well as at 5 Hz (port only at 5 Hz, l. 573–577); (c) `5b9530` does not
    re-orthogonalise `w` (port l. 317) and takes the roll from the raw `w` via the heading/pitch frame (port uses
    `right` recomputed after β, l. 323/331); (d) all channels are sampled with the X-axis τ (1.1 s clamp).
14. **Lift-ramp rate factor** (l. 494) — PO: no `.max(0.01)` (factor 0 at 17.98 m/s, |negative| below); guard the
    division when the rate is 0. BP: the slope globals (`0x845420/24/40/44`, β `0x8453e8/ec`) belong to the **last
    aircraft type set up**, so every jet uses that type's G_Rate/G_RateForAoa/BetaRate below 220/400 m/s; better:
    per aircraft (F-4 G_Rate 3 vs F-16 5).
15. **Terrain types and map edge** — PO when the world provides the flags: rough ground > 25.7 m/s and water destroy
    the jet, `S+0x2c8` states, OutRunway FF; the "Tornado" push-back (§15.5a) — BP: its acceleration ramps never decay
    (axis τ), reversing the velocity to ≈ 11×V₀ (UNCERTAIN, verify in game); low priority.
16. **Minor** — PO: the 1 Hz V is not capped at 1200 m/s (only the 5 Hz one); the airborne thrust is not clamped ≥ 0
    (already so, l. 392–395); `S+0x420` effects flag (75 < V < 150 && sY > 0.7); force-feedback effects and SFX 0x28/
    0x29, EndWorld/Kramer wavs (host/audio); ground roll constants ×0.8 (rolling drag) and AI brake ×4 (v1.1).
17. **Landed flag** (v1.1) — PO: the mission's landed handler fires at every gear-down touchdown that passes the check,
    re-armed at lift-off (§15.6.2).

Items still UNCERTAIN: the Euler convention of `46d056` and the Rodrigues order in the mode exits, which unit types
are 100/140, the Tornado timing, the terrain flag meanings, modes c74/c78, the mover that supplies the start velocity,
`4020a0`'s return value and the reader of `veh+0xc3c`.

### 15.11 Ported (checklist of §15.10)
"done" = ported as the original; "BP" = the better behaviour is behind an `Aircraft::better` option (`BetterPhysics`, one switch each) (the original stays the
default, §10). Rust unit tests in `aircraft.rs` / `envelope.rs`; headless Godot test `tests/godot/test_crash.gd`.

| # | item | status |
|---|---|---|
| 1 | Envelope | done: `envelope.rs` is §15.9 exactly (parser, pads, ceilings, lines, per-level lists, bracket, plane fits, codes 0/2/3/4). Tests: Python reference `tools/envelope_ref.py` run at test time (ceilings, Vmin, GLimit grid on a synthetic text and on every install `md/*.dat`) and the F-16 values of §15.9. `stall_floor` stays Real-only |
| 2 | Landing / crash check | done: `landing_check` at touchdown (saved Euler, Easy landing ×2 default on, gear-not-down ×0.2/0.2/0.25, slope > 10°, immunity = Invulnerable / No crashes); water and rough ground (> 25.7 m/s) destroy while rolling; the sim freezes (`crashed` + reason). Host: slope from `height_at`, water = false (no terrain types, UNCERTAIN), crash → mission runtime player death → flight ends after 5 s. BP: sink 4 m/s, tail strike 15°, current attitude |
| 3 | Spin mode | done: mode, three channels with their limits, two-stage entry (with the "No spins" quirk), update in both updates (5 Hz skips the forces), spin attitude, exit (velocity := rotated nose·V, `p_cmd = s1·0.1`), types 100/140 (F-16, Lavi) never spin — so the F-16 we fly cannot depart in the original. v1.1: recovery slope π/(2.2·MaxBeta), β updated at 5 Hz in the spin, axes re-based in the stay branch (test `spin_recovery_slope_v11`). BP: (a)–(f); types 100/140 get the FLCS deep stall instead (§10.1, tests `fbw_deep_stall_*`). Damage 0x18 not modelled (no damage system) |
| 4 | Nose-wheel yaw ramp | done: `S+0x2a8` at \|BetaRate\|, ±MaxBeta; 5 Hz uses the ramp, 1 Hz the raw target |
| 5 | Force angles | done: 5 Hz αT and β(t) (the β channel; ground: nose-wheel ramp), 1 Hz α(t) and β_cmd. BP: α(t)/β(t) in both |
| 6 | α 1 Hz update | done: `5aa3a0` at every aero update with αT from the new Lnoflap, gains only there, ×0.5 damping above π |
| 7 | Gear / brake / flap ramps, `cfg` | done: gear 0..1.569, flaps 0..0.29275 (F-16 lever ×0.33), brakes 0..0.855, all 0.5/s; gear flag exactly at 0, brake flag (air: finished at max; ground: ≥ 1e-5). The model's gear animation already used 0.5/s (3.1 s); the cockpit lamps keep the controller's 2 s (§12). Hook (`cfg[8]`) not wired (no hook control) |
| 8 | Throttle / AB | done: AB request after `(100 − RPM)/15` s (v1.1: any change cancels a pending request, a new AB request re-times it; test `new_throttle_request_cancels_the_pending_afterburner`), 0.015 dead band, first event starts the engine, RPM ramp 0..100 at 15 %/s; host keys step the FM throttle by 0.0925 only while ≤ 1.0 and reach the FM at once |
| 9 | Start rules | done: `Aircraft::start` / `start_is_airborne` (z > 800 m, not near a base); air: throttle 0.74, RPM 70, gear up, lift ramps MaxWeight·g; ground: gear down, full flaps, brakes, throttle 0, RPM 0, engine only near the runway start point. Host: base / runway start point from the 3 known spawn points, start speed 180 m/s (both UNCERTAIN, §10). BP: lift ramps m·g, RPM at the start throttle's value (no AB light-up delay), α at its trim value |
| 10 | Stall latch | done: `≤ 3.0`, set only when unset, cleared only by an update with `now − t > 3`, set on the ground too. FF "StallShake" skipped (no force feedback) |
| 11 | Preferences | done: No stalls (code 0/2/4 rules, no latch, no vibration), No spins (quirk; BP blocks), Easy landing (default on; landing ×2, ground lift gate), Invulnerable / No crashes (immunity, ground "easy" gate, no belly μ), Unlimited fuel. Pub fields on `Aircraft`, setters on `IafFlight`, set from `Settings` in `terrain_view.gd`. Multiplayer overrides n/a |
| 12 | β channel | done (v1.1): `beta_update` = `5aa700` (second-order, RudderK/Beta/StartAccel/StopAccel with the exe defaults for v1.0 data, 400 m/s, K ×1.5 near centre, no clamp), `beta_step` = the ground 1 Hz step, 5 Hz also in the spin; the rudder `S+0x2ec` is taken only while airborne. Tests `rudder_keys_and_v10_defaults`, `beta_channel_second_order`, `beta_steps_on_the_ground_and_in_the_spin`; validation row "rudder step" |
| 13 | Roll / attitude | done: (0) v1.1 roll about the saved body nose (test `roll_about_the_body_nose`); (a) no `kroll` clamp; (b) roll re-based on the attitude roll and `5aa330` at 1 Hz and 5 Hz; (c) no re-orthogonalisation, roll from the raw left wing in the heading/pitch frame, force matrix from the Euler angles. (d) skipped: channels use their own base time (§10). BP: `kroll ≥ 0` (no reversed roll below Veff ≈ 9.5 m/s) |
| 14 | Lift-ramp rate factor | done: no `.max(0.01)` floor; BP: floor 1 %. The per-type slope globals: not reproduced in either mode (our slopes are per aircraft, i.e. the better behaviour; identical while one type flies, §10) |
| 15 | Terrain types, map edge | partly: water / rough-ground rules are in the FM; the host passes the terraintype.dat flags (`terrain.gd surface_at`, formats/ptt.md "Terrain types"). `S+0x2c8` states, OutRunway FF and the "Tornado" push-back skipped |
| 16 | Minor | done: the 1 Hz V is not capped (5 Hz caps at 1200 m/s); airborne thrust unclamped; v1.1 rolling drag ×0.8 (test `ground_roll_drag_factor`; the AI brake ×4 waits for AI jets). Skipped: `S+0x420` effects flag, FF effects, SFX 0x28/0x29, EndWorld/Kramer wavs |
| 17 | Landed flag | done (v1.1): `State::landings` / Godot `landings` +1 at each gear-down touchdown that passes the check, re-armed at lift-off (test `landed_flag_rearmed_at_lift_off`); the mission runtime's landed trigger is the host's |
| — | Also BP (§10): the nose-wheel ×4 lift quirk off (§14.5), ground effect on the induced drag (not in the original) | done, test `better_physics_minor_fixes` |

## 16. v1.0 → v1.1 (what the patch changed in the flight model)
From docs/v1.1.md, each verified against the v1.1 decompile / disassembly and ported (the logic is v1.1 only; v1.0 data
still works, see the last column):

| change | where (v1.1, v1.0) | § | with v1.0 data |
|---|---|---|---|
| β: second-order channel (α law) with RudderK / RudderBeta / RudderStartAccel / RudderStopAccel, threshold 375 → 400 m/s, no ±MaxBeta clamp, no HUD β ramp, ground step with stored gains, 5 Hz also in the spin | `5aa700` (`5a78f0`), `5a70f0`, `5a4230`, `5b1f30`, `5a4d40`, loader `5b2940` | §1, §15.2.6 | the exe defaults 5 / 0 / 0.5 / 0.5 (what v1.1 does with a v1.0 `bd.ibx`) |
| params stride 0x17c → 0x18c; derived `P+0x16c..0x178` → `0x17c..0x188` | `5b2940`, `5b4470` | §1 | — |
| roll about the saved body nose instead of the velocity | `5b9530` (`5b4840`) | §6, §15.3 | same |
| spin recovery slope π/(1.8·MaxBeta) → π/(2.2·MaxBeta); axes re-based in the stay branch; `veh+0xc3c` | `5aab90` (`5a7d50`), `0x611cf0` | §15.5 | same |
| ground roll: rolling drag ×0.7 → ×0.8 above 1 m/s, AI wheel brake ×2 → ×4 | `5bac40` (`5b7a20`), `0x612480`, `0x612474` | §7, §14.2 | the v1.0 WheelsBrakeDragIndex / SpeedBrakesDragIndex / Lavi values apply |
| a throttle change cancels a pending AB request (a new AB request re-times it) | `59f7d0` (`59cb60`) | §8, §15.8 | same |
| landed flag re-armed at lift-off (the handler fires on every landing) | `5bb9f0` (`5b87d0`; `441000` inlined) | §15.6.2 | same |
| airbrakes ×2, taxi brakes, Lavi drag / thrust | data only (`bdgen.dat`) | — | v1.0 values |

Unchanged (layout or codegen only): lift `5b4470` (the offsets above), drag / thrust / atmosphere, getters `5a9280`,
landing check `5bb7d0`, the start state (MaxWeight·g, RPM 70 %, α = 0), the over-G logic. None of our better-physics
options became redundant (docs/v1.1.md "Our fixes made redundant"): `spin_fixes` keeps all its items, the v1.1 slope and
spin β apply underneath in both modes (§10).
