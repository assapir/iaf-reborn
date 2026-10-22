# MiG-23 pilot guide (realistic settings)

This guide covers what changes in the MiG-23ML when you switch on the realistic options: the real jet's АСП-17МЛ sight
in place of the game's HUD (head-up display), the real jet's numbers, the metric dials and the SPO-15 warning lamps.
The game's MiG-23 is an enemy jet that the player flies only in a Mission Creator mission (section 2). Each sight mode
has its own section: when to use it, the keys, a picture whose numbered yellow callouts the list under it explains,
and a worked example. Section 12 explains the abbreviations.

---

## 1. What's different in this jet

| Area | The 1998 game | With the realistic options |
| --- | --- | --- |
| Sight | The game's common HUD: speed and altitude boxes, a heading tape, text rows | The АСП-17МЛ sight, a reconstruction: a fixed cross, the radar's target and range scale, Cyrillic legends, no flight data |
| Flight data | The original's MiG-23: 13,200 / 22,000 lbf, 12,500 lb fuel | MiG-23ML (R-35-300): 18,850 / 28,660 lbf, 7,496 lb fuel, 757 kt at sea level |
| Panel | The needles of the Western jets on the wrong Russian dials: airspeed on the Mach meter, RPM on the fuel gauge, fuel on the exhaust-temperature dial | Better cockpit: each needle on its own dial, metric units, the SPO-15 lamps, the range counter, the HSI bars (section 10) |
| Radar | 25 NM search, no track-while-scan | the same (Weapon data = Real keeps the MiGs' radar table) |
| Gun | The game's DEFA record, 175 rounds | Weapon data = Real: 2 × 1,300 rounds/min at 815 m/s, the same 175 rounds |
| Physics | The original's quirks: still air, instant thrust | Real touchdown limits, ground effect, realistic spins with mechanical controls, the tower's wind, the engine's real spool-up |

![The 1998 HUD in a Mission Creator MiG-23](shots/mig23/hud_original.png)

The same flight with the Real sight is the first picture of section 3.

**HUD warnings.** The MiG-23 has no Betty voice. The 1998 HUD draws a large X across its centre in the A-G gun and
bomb modes while the dive is steeper than 1° per 100 ft above the ground (20° at 2,000 ft), and in place of the missile
circle when the locked target is inside the missile's minimum range (Rmin). The Real sight draws no such mark.

---

## 2. Settings

**Getting into the MiG-23.** The Jet list has no MiG. Open **Mission Creator** on the main menu, set Alpha's **No** to
1 or 2 and its **TYPE** to **MiG-23**, pick the base, the time, the starting altitude, a target and the enemy (Charlie,
Delta), then press **FLY**. The TSD (tactical situation display) opens on the built mission: **Arm** loads the
stores (unless WEAPONS is Guns Only), **Fly** starts the flight. SAVE keeps the setup for next time. The 1998 Creator's
mission always has a 10 kt wind from 270°; with Extras → Mission Creator = Better, its WIND and FROM boxes set it.

Set these on the Preferences screen before the flight. Every row starts at the 1998 game's setting.

| Tab | Row | Set to | What it changes |
| --- | --- | --- | --- |
| Extras | Flight data | Real aircraft | The MiG-23ML numbers (section 4) |
| Extras | Weapon data | Real weapons | The gun's rate and muzzle speed; the radar and the AA missiles keep the game's values |
| Extras | HUD | Real | The АСП-17МЛ sight |
| Extras | Better cockpit | Better | Each needle on its own dial, metric units, the SPO-15 lamps, the range counter, the HSI bars (section 10) |
| Extras | Mission Creator | Better | WIND and FROM boxes on the Mission Creator screen: the mission's wind |
| Extras | World scale | Real 1:1 | True-size models; every airbase at its real place, with its real runway numbers |
| Extras | RWR | Real | The SAM / AAA radars searching you show too, until terrain hides you (section 5) |
| Graphics → MORE | Sky, Terrain close up, Imagery Israel / outside Israel | Atmospheric, Detailed, Survey 2 m / Sentinel-2 | A physical sky, ground detail and photo imagery, if setup converted it |
| Graphics → MORE | Airbases | Detailed | Runways, taxiways and aprons with real markings near the ground |
| Graphics → MORE | Night vision (Shift+N) | Goggles | Night-vision goggles in flight: a green, brightened outside view on night missions |
| Physics | every row | on | Section 4 lists the ones that change how the MiG-23 flies |
| Physics | Nose dips under braking, Unbalanced stores roll the jet, Wind and turbulence, Engine spool-up per real engine | on | The brakes' pitch, the stores' roll, the tower's wind and the engine's real spool (section 4) |
| Gameplay | Easy landing, Easy aiming, No blackouts / spins / stalls, No wind | off | Real landing limits, real launch rules, g-effects, spins, stalls and the mission's wind |

A greyed-out imagery choice needs its data: convert it with `tools/setup-cli.sh --imagery`.

---

## 3. The sight in flight

**When**: always; the sight is the MiG-23's only head-up display. **Keys**: **N** returns to NAV.

The real MiG-23ML has no radar scope: the radar's picture, the infrared search data and the gun reticle all show on
its sight[^airwar-ml]. No public source shows a pitch ladder or speed and altitude numbers on it, and its drawing is
not public, so the game's sight is a reconstruction: a fixed cross and the symbols of the selected weapon. Read speed,
height and heading on the panel.

![The sight in NAV: the fixed cross and the steering ring](shots/mig23/sight_nav.png)

1. **Fixed cross**: the gun line.
2. **Steering ring**: a small ring on the current waypoint. While the waypoint is outside the sight's field the ring
   is held at the field's edge and drawn as an X.

**Example**: just after the start the waypoint lies below the sight's field, so the X sits at the field's lower left.
Turn and lower the nose toward it until the ring comes inside the field, then put it on the fixed cross. **W** /
**Shift+W** pick the next / previous waypoint.

---

## 4. Flying the MiG-23 with Real flight data

With Flight data = Real the MiG-23 row (docs/real-aircraft.md §9.2) is checked by the game's validation test. The game
flies one fixed wing: the real jet's wing sweep (16°, 45°, 72°) is not modelled.

| Item | In the game | Real MiG-23ML |
| --- | --- | --- |
| Empty weight | 22,500 lb | 22,487–22,553 lb |
| Internal fuel | 7,496 lb | 4,250 l = 7,496 lb (8,157 lb in one source) |
| Thrust, military / full afterburner | 18,850 / 28,660 lbf | 18,850 / 28,660 lbf (R-35-300) |
| 1 g stall speed, sea level | 157 kt (the original's envelope) | landing 140–151 kt, so about 132 kt |
| g limits | +8.5 / −3 | +8.5 below Mach 0.85, +7.5 above |
| Maximum speed, sea level / 40,000 ft | 757 kt (Mach 1.14) / 1,349 kt | Mach 1.14 / Mach 2.35 (wings at 72°) |
| Instantaneous turn | 15.4°/s | 16.7°/s at 486 kt, 3,300 ft |
| Climb at sea level | 30,500 ft/min | 42,300–47,250 ft/min |
| Fuel flow, military / full afterburner | 17,340 / 55,600 lb/h | about 17,340 / 55,600 lb/h |

What changes in the cockpit:

- **Fuel**: about 8 minutes at full afterburner, about 26 minutes at military power at sea level. The 2,800 lb
  centreline tank helps.
- **Mechanical flight controls**: the stick moves the surfaces directly, so you own the limits. At low speed a hard
  pull stalls the wing, and with Realistic spins on the jet can spin: recover with the stick forward and rudder
  against the spin.
- **Ground effect** (Physics): a longer float in the flare. **Real idle thrust on the ground**: at idle the jet taxis at
  about 35–45 kt.
- **Engine spool-up per real engine** (Physics): the thrust follows the R-35's spool, slowest at first: 5 s from idle to
  military; the afterburner lights 1 s after the core reaches military and fills in 1.5 s. Out of afterburner the thrust
  drops at once. No R-35 figure is public; 5 s is the limit the Soviet engine norms set (open)[^bigenc].
- **Wind and turbulence** (Physics): the air moves with the tower's wind. The jet crabs into a crosswind and drifts
  downwind, a headwind shortens the take-off run, and light gusts shake it, strongest below 300 m (1,000 ft). The AI
  jets fly in the same air, bombs drift downwind (the bombing computer allows for it: the impact pipper moves downwind),
  and smoke, fire and trails drift with it. With a wind of 5 kt or more from behind the main runway the tower turns the
  base to the runway's other end: the starts, the tower's calls, the taxi signs, the autopilot, the AI and the ILS use
  that end; training missions keep their runway. Gameplay → No wind calms the air.
- **Nose dips under braking** (Physics): the nose dips up to 2° under the wheel brakes and squats up to 1° at full
  thrust on the brakes; it levels within about a second once the jet stops.
- **Unbalanced stores roll the jet** (Physics): stores left on one wing roll the jet toward it: hold that wing up with
  the stick (the game has no roll trim), or let the autopilot (**A**) hold it while it flies. Its pylons sit close to
  the fuselage: one MK-84 (2,020 lb) left on station 3, 1.4 m out, takes about 4 % stick at 290 kt and 1 g. It grows
  with the g in a pull, and at half the speed it takes four times as much.
- **The map edge**: 12 km (6.5 NM) before it the EndWorld warning sounds: turn back. Past it the game pushes the jet
  back for about 8 s (the nose rises and the jet turns).

### Take-off and landing numbers

| Item | MiG-23 with Real flight data |
| --- | --- |
| 1 g stall, sea level | 157 kt |
| Final approach | about 190 kt: 1.2 × the game's stall speed (inferred) |
| Touchdown limits (Real landing limits, Easy landing off) | sink below 4 m/s (790 ft/min), pitch below 15° |
| Drag chute (**Shift+B**) | drawn, with zero drag (the chute's drag is open) |

---

## 5. Radar and self-protection

The radar detects at **46 km** (25 NM) in LRS (long-range search), 10 NM in ACM (air combat mode) and boresight; MAP
40 NM, GMT (ground moving target) 25 NM. The MiG-23 has no TWS (track while scan). Weapon data = Real keeps these
numbers. The MFD (multi-function display) under the sight shows the radar; the real ML had none there.

| Key | Action |
| --- | --- |
| **R** / **Q** / **S** | Radar on, A-A ↔ A-G / mode (LRS → ACM; GMT ↔ MAP) / standby |
| **.** / **,** | Range scale up / down |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace** | Drop the lock |
| **\\** (hold) | Boresight |

- **SPO-15 and the lamps**: the panel's AI / ML boxes light for an air threat and a missile launch at you. With Better
  cockpit on, the SPO-15's lamps work too (section 10). The display's RWR page (MENU) lists the threats.
- **RWR: Real** (Extras): the RWR page also shows the SAM and AAA radars searching you before they lock: a steady symbol
  and the new-threat tone; the SPO-15 lights their direction and type lamps, not the lock lamp. Drop behind a ridge and
  they go.
- **Chaff (Insert)** and **flares (Delete)**: 40 chaff and 20 flares. Chaff fools a radar missile with 10 % (30 %
  above 4 g), a flare an IR (infrared) missile with 33 % (50 % above 4 g) while the afterburner is off.
- Chaff and flares are the MiG-23's whole self-protection; the **J** jammer key belongs to jets with a jammer.
- **AWACS calls**: from 60 s into the flight the airborne controller calls the enemy aircraft within 35 NM, one scan
  every 12 s. "Alpha, bearing 090, 15 miles, target, heading 270, free to engage": the contact's bearing and distance
  from you, then its heading ("targets are already engaged" in place of "free to engage").
  "Unidentified contacts, please identify": your radar has not seen it yet; find it before you engage. A contact is
  called again, in short, after 60 s or when it moved more than 5 NM. Below 50 m (165 ft) the controller is silent.
- **Flight reports**: the radio reports your side's jets airborne, landed, crashed or ejected, and each kill 5 s after
  it.

What the MiG-23 can load on the Arming screen (stations 3 and 7 the outer pylons, 4 and 6 the inner ones, 5 the
centreline):

| Store | Stations |
| --- | --- |
| AA-8, AA-2 | 3, 4, 6, 7 |
| AA-6 | 4, 6 |
| MK-83, CBU-87, Shrike | 3, 4, 5 (MK-83), 6, 7 |
| MK-84 | 3, 5, 7 |
| AS-14 laser bomb, AS16 bomb | 4, 6 |
| 2,800 lb tank | 3, 5, 7 |

The default load is two AA-8s, two AA-6s and the centreline tank.

---

## 6. IR missiles: AA-8, AA-6, AA-2

**When**: a target inside the missile's range. **Keys**: **]** to the missile, **Space** fires. With a radar lock
(**R**, then **Return**) the seeker is slaved to the locked target within its cone; otherwise it looks within 6° of
the nose. All three are the game's "limited heat" missiles: the target has to be within 60° of your heading. Weapon
data = Real keeps their game values.

| Missile | Game data |
| --- | --- |
| AA-8 | 143 lb; seeker cone 21°, range 8 NM |
| AA-6 | 1,015 lb; seeker cone 15°, range 6 NM |
| AA-2 | 165 lb; seeker cone 15°, range 6 NM |

![An R-60 (AA-8) on a MiG-21 flying away 2,000 m ahead](shots/mig23/sight_srm.png)

1. **Target diamond** on the locked target. At the sight's designation limits (±12° in azimuth, +16 / −18°
   vertically[^airwar-ml]) it stays at the limit and «НОП» (aiming error too large) shows.
2. **«ПР»** (launch authorised): the target is inside the missile's range.
3. **Range scale** in km: its top reads the scale (3, 5, 10, 20 or 45 km).
4. **Target caret** with the range in km; the scale's ticks mark Rmax and Rmin.
5. **Fixed cross**.

**Example**: the MiG-21 flies away 2,000 m ahead, 50 m/s (97 kt) slower than you. The scale reads 10 km, the caret
2.0 km, and the AA-8's zone runs from about 1.8 km to 6.7 km. «ПР» is lit: fire. Beyond half the missile's range the
seeker sees only a jet with its afterburner lit.

---

## 7. Gun

**When**: a target inside about 600 m. **Keys**: **]** to the gun, **Tab** fires. With Real data the game's DEFA
record fires 2 × 1,300 rounds/min at 815 m/s: the 175 rounds last about 4 s.

![The gun: a MiG-21 600 m ahead](shots/mig23/sight_gun.png)

1. **Pipper**: the lead-computed aim point.
2. **Ring with the range bar**: with a radar lock the bar runs round the ring, a full turn for 2,000 m (inferred).
3. **The target**: a MiG-21.

**Example**: the MiG-21 is 600 m ahead and closing at 486 kt; the range bar covers about a third of the ring. The MiG
sits below the pipper: lower the nose until the pipper covers it, then fire a 1 s burst (43 rounds).

---

## 8. Bombs and rockets

**When**: MK-83 / MK-84 / CBU-87 bombs. **Keys**: **[** to the store, hold **Space** to release (the ripple releases one
store per interval; the stores page sets it).

![A 45° dive at 500 m above the ground, two MK-83s](shots/mig23/sight_bomb.png)

1. **Pipper** on the predicted impact.
2. **Fixed cross**: the fall line runs from it to the pipper.

**Example**: two MK-83s, a 45° dive at 428 kt (220 m/s), 500 m (1,640 ft) above the ground. Steer so that the target
slides down the fall line, and release when it reaches the pipper. Higher up, the impact falls below the sight's
small field: the pipper then waits at the field's lower edge.

The AS-14 laser bomb, the AS16 and the Shrike load too (section 5); they aim as on the Western jets (the F-16 guide
describes the laser and anti-radar modes).

---

## 9. Landing

**When**: on final approach, gear handle down (**G**). **Keys**: **G** gear, **F** flaps, **B** wheel brakes, **Ctrl+T**
call the tower.

![Final approach: the К and Г bars](shots/mig23/landing.png)

1. **«К»** (course): the vertical ILS (instrument landing system) bar, the runway's centreline.
2. **«Г»** (glide): the horizontal bar, the glide path[^n003e].
3. **Fixed cross**.

**Example**: 4 km short of the runway at about 700 ft the К bar lies on the runway's centreline. Steer toward the К
bar and climb or descend toward the Г bar until they cross in the sight's middle, hold about 190 kt, and flare over
the threshold.

---

## 10. Better cockpit

**When**: any flight. **Keys**: tap **V** for the whole panel (hold it to glance down and back), **PgUp** / **PgDn**
slide it.

The 1998 game drives the MiG-23's panel with the Western jets' needles: the airspeed lands on the Mach meter, the RPM
on the fuel gauge, the fuel on the exhaust-temperature dial. With Better cockpit on, each needle reads the dial it sits
on, in its own units, and the needles follow their values with a 0.3 s instrument lag.

![The panel with Better cockpit on, on final](shots/mig23/better_panel.png)

1. **Altimeter**, in metres: one turn of the long needle per 1,000 m.
2. **Mach meter**: the Mach number (0.6 … 3).
3. **КПП** (attitude director indicator).
4. **ПНП** (horizontal situation indicator): the heading card turns; with the gear down the К / Г bars follow the ILS.
5. **Range counter**: the distance to the current waypoint in km (the real counter shows the range to the RSBN radio
   beacon; the game has no beacons).
6. **Hydraulic pressure**: two needles, one per system, at 210 kgf/cm² (inferred); they fall to 0 with the
   hydraulics damaged.
7. **Vertical speed**, × 10 m/s (unit inferred): level at 9 o'clock.
8. **Exhaust temperature**, × 100 °C (the art's FUEL plate is the game artist's).
9. **Fuel**, in thousands of litres, the drop tanks included.
10. **SPO-15**: the sector lamps light toward each radar locking you, about 10° apart within ±50°; the ring of dashes
    shows the nearest one's strength; the red centre lamp is steady with a lock and flashes with a launch; the type
    lamps П, З, Х, Н tell an aircraft from a long-, medium- or short-range SAM radar.

**Example**: on final the range counter reads 003 (3 km to the waypoint), the Mach meter about 0.2 and the vertical
speed a small descent. The panel has no airspeed dial and no tachometer: hold the speed with the Mach meter.

---

## 11. Night vision

**When**: night missions (the game's night is 20:00–05:30; mission 214 starts at 01:00), with Graphics → MORE →
Night vision = Goggles. **Keys**: **Shift+N** puts the goggles on and takes them off.

The goggles are ours: the 1998 game has none. They turn the outside view into a brightened green picture; the
cockpit and the HUD stay as you see them under the goggles. Set Graphics → MORE → Night lights = Detailed too, for
the moon, the stars and the lights on the ground.

![01:00 without goggles](shots/mig23/night.png)

![The same moment through the goggles](shots/mig23/night_nvg.png)

- The ground's relief and texture show, and the horizon is clear: fly by the outside view.
- The goggles set their own gain: the darker the scene, the more they brighten it, and the grainier it gets.
- The HUD shows in its brightest green while the goggles are on; your own level comes back when they come off.
- The goggles follow the mission's year: none before 1972, a grainy Gen II up to 1981, a Gen III from 1982, the
  sharpest from 1996 (the 1998 missions).
- In a MiG the goggles are the older, grainier Gen II at best (the Soviet ONV-1).
- A bright light (a fire, a flare, a runway light) gets a halo around it.
- The picture darkens toward its edges.

## 12. Key card

| Key | Action |
| --- | --- |
| 1 … 8 | Throttle: idle, 65, 70, 80, 90 %, military, AB 1, AB 2 |
| 9 / 0 | Throttle − / + 5 % |
| V / PgUp / PgDn | Whole panel ↔ none (hold V: a glance down) / slide the panel up / down |
| Arrows | Stick |
| Numpad 0 / Decimal | Rudder left / right |
| G / F / B | Gear / flaps / wheel brakes |
| Shift+B | Drag chute |
| A | Autopilot: level → NAV → off |
| W / Shift+W | Next / previous waypoint |
| Ctrl+T | Call the tower |
| M / N | Master mode cycle / NAV |
| ] / [ | Next A-A / A-G weapon |
| Space / Tab | Fire the weapon / the guns |
| Shift+C | Jettison tanks, then bombs |
| R / Q / S | Radar on, A-A ↔ A-G / mode / standby |
| . / , | Radar range up / down |
| Return / Shift+Return | Next / previous target (locks in LRS) |
| Backspace | Drop the lock |
| \\ (hold) | Boresight |
| T / D | TSD / damage page |
| Insert / Delete | Chaff / flare |
| Shift+arrows, Numpad 1–9, F3 | Look around, snap views, padlock |
| Shift+N | Night-vision goggles on / off (Graphics → MORE "Night vision") |
| F1 / Ctrl+F2 | Cockpit ↔ sight only / cockpit ↔ external |
| SysRQ | Screen capture: a PNG in the `screenshots` folder of the game's user folder |
| X | Fire extinguisher (one charge) |
| E | Eject |
| C / Ctrl+C | Time ×2 ×4 ×1 / normal time |
| Ctrl+P / Ctrl+O / Esc | Pause / in-flight menu / TSD map |
| Alt+E / W / P / T / C / B | Wingman: engage my target / other target, protect me, tactical / close formation, go home |

---

## 13. Abbreviations

| Term | Meaning |
| --- | --- |
| A-A / A-G | air-to-air / air-to-ground |
| AB | afterburner |
| ACM | air combat mode: the radar's close-range lock mode |
| GMT | ground moving target |
| HUD | head-up display |
| ILS | instrument landing system |
| IR | infrared (heat-seeking) |
| kt | knots |
| lbf | pound-force (thrust) |
| LRS | long-range search |
| NAV | navigation mode |
| NM | nautical mile (1.852 km) |
| RWR | radar warning receiver |
| SAM | surface-to-air missile |
| STT | single-target track: a radar lock |
| TSD | tactical situation display: the map |
| «Г» | глиссада: the glide path bar |
| «К» | курс: the course bar |
| «НОП» | недопустимая ошибка прицеливания: aiming error too large |
| «ПР» | пуск разрешён: launch authorised |
| КПП / ПНП | the attitude director indicator / the horizontal situation indicator |
| SPO-15 (СПО-15) | the radar warning receiver of the real MiG-23MLD |

[^airwar-ml]: airwar.ru, "МиГ-23МЛ" (the sight shows the radar data; designation limits; НОП), https://www.airwar.ru/enc/fighter/mig23ml.html

[^n003e]: "N003E modes", Soviet aircraft tech (the К and Г symbols), https://sites.google.com/site/sovietaircrafttech/mig-23/n003e/modes

[^bigenc]: Большая российская энциклопедия, «Приёмистость авиационного двигателя»: the norms limit idle to maximum at sea level to 5 s, https://bigenc.ru/c/priiomistost-aviatsionnogo-dvigatelia-481568

