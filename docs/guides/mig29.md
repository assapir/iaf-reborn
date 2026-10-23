# MiG-29 pilot guide (realistic settings)

This guide covers what changes in the MiG-29 9.12 when you switch on the realistic options: the real jet's ИЛС-31 HUD
(head-up display) in kilometres per hour and metres, the Щель-3УМ helmet sight, the real jet's numbers and the
Russian dials. The game's MiG-29 is an enemy jet that the player flies only in a Mission Creator mission (section 2).
Each HUD mode has its own section: when to use it, the keys, a picture whose numbered yellow callouts the list under
it explains, and a worked example. Section 14 explains the abbreviations.

---

## 1. What's different in this jet

| Area | The 1998 game | With the realistic options |
| --- | --- | --- |
| HUD | The game's common HUD: speed and altitude boxes in knots and feet, a heading tape, English text rows | The ИЛС-31 HUD laid out from the simulator manuals built from the real jet[^ea][^fc3]: speed in km/h, height in metres, a pitch scale on the right, Cyrillic mode names |
| Looking aside | The original's helmet repeater | The Щель-3УМ helmet sight: aim an R-73 by turning your head |
| Flight data | The original's MiG-29: 20,000 lb, 15,000 / 25,000 lbf | MiG-29 9.12 (2 × RD-33): 24,030 lb empty, 22,220 / 36,600 lbf, 7,720 lb fuel |
| Panel | The airspeed needle on the radar altimeter, the vertical speed on the AoA / g meter | Better cockpit: the radar altimeter with its 70 m warning, the AoA / g meter with a max-g needle, metric units (section 12) |
| Radar | 45 NM search, track-while-scan | the same (Weapon data = Real keeps the MiGs' radar table) |
| Gun | The game's 20 MM record, 140 rounds | Weapon data = Real: 6,000 rounds/min at 1,030 m/s, the same 140 rounds |
| Physics | The original's quirks: still air, instant thrust | Real touchdown limits, ground effect, realistic spins with mechanical controls, the tower's wind, the engines' real spool-up |

![The 1998 HUD in a Mission Creator MiG-29](shots/mig29/hud_original.png)

The same flight with the Real HUD is the first picture of section 3.

**Voice and HUD warnings.** With the 1998 HUD the MiG-29 has the Betty voice: "Altitude" below 100 ft with the gear
up, "Pull up" in a steep A-G dive, the damage calls; the HUD draws a large X across its centre in that dive and in
place of the missile circle inside the missile's minimum range (Rmin). With the Real HUD these dive and height calls
and the X stay off: the real jet's voice system is open. Better cockpit's radar altimeter brings back an "Altitude"
call below its 70 m danger height (section 12).

---

## 2. Settings

**Getting into the MiG-29.** The Jet list has no MiG. Open **Mission Creator** on the main menu, set Alpha's **No** to
1 or 2 and its **TYPE** to **MiG-29**, pick the base, the time, the starting altitude, a target and the enemy (Charlie,
Delta), then press **FLY**. The TSD (tactical situation display) opens on the built mission: **Arm** loads the
stores (unless WEAPONS is Guns Only), **Fly** starts the flight. SAVE keeps the setup for next time. The 1998 Creator's
mission always has a 10 kt wind from 270°; with Extras → Mission Creator = Better, its WIND and FROM boxes set it.

Set these on the Preferences screen before the flight. Every row starts at the 1998 game's setting.

| Tab | Row | Set to | What it changes |
| --- | --- | --- | --- |
| Extras | Flight data | Real aircraft | The MiG-29 9.12 numbers (section 4) |
| Extras | Weapon data | Real weapons | The gun's rate and muzzle speed; the radar and the AA missiles keep the game's values |
| Extras | HUD | Real | The ИЛС-31 HUD and the Щель-3УМ helmet sight |
| Extras | Better cockpit | Better | The radar altimeter, the AoA / g meter, the tachometers, metric units (section 12) |
| Extras | Mission Creator | Better | WIND and FROM boxes on the Mission Creator screen: the mission's wind |
| Extras | World scale | Real 1:1 | True-size models; every airbase at its real place, with its real runway numbers |
| Extras | RWR | Real | The SAM / AAA radars searching you show too, until terrain hides you (section 5) |
| Graphics → MORE | Sky, Terrain close up, Imagery Israel / outside Israel | Atmospheric, Detailed, Survey 2 m / Sentinel-2 | A physical sky, ground detail and photo imagery, if setup converted it |
| Graphics → MORE | Airbases | Detailed | Runways, taxiways and aprons with real markings near the ground |
| Graphics → MORE | Night vision (Shift+N) | Goggles | Night-vision goggles in flight: a green, brightened outside view on night missions |
| Physics | every row | on | Section 4 lists the ones that change how the MiG-29 flies |
| Physics | Nose dips under braking, Unbalanced stores roll the jet, Wind and turbulence, Engine spool-up per real engine | on | The brakes' pitch, the stores' roll, the tower's wind and the engine's real spool (section 4) |
| Devices | Throttle rocker | Roll trim | A stick's spring-centred 5th axis (the throttle rocker in 5-axis mode) trims roll, to hold a heavy wing up (section 4). The row shows only for a stick with a 5th axis |
| Gameplay | Easy landing, Easy aiming, No blackouts / spins / stalls, No wind | off | Real landing limits, real launch rules, g-effects, spins, stalls and the mission's wind |

A greyed-out imagery choice needs its data: convert it with `tools/setup-cli.sh --imagery`.

---

## 3. The HUD in flight (МРШ)

**When**: cruising to the next waypoint. **Keys**: **N** returns to NAV; **W** / **Shift+W** pick the next / previous
waypoint.

![The ИЛС-31 HUD in NAV (МРШ)](shots/mig29/hud_nav.png)

1. **Indicated airspeed** in km/h.
2. **Height** in metres: the radar height to 1 m below 1,000 m, else the barometric height to 10 m.
3. **Heading tape** in tens of degrees (`25` = 250°), read at the caret under it.
4. **Pitch scale**, on the right: a tick every 5°, a label every 10°, the caret at the jet's pitch.
5. **Mode name**: МРШ (route). ПОС with the gear down, ДВБ / ТП / БВБ / Ф0 with the A-A missiles, ОПТ ЗЕМЛЯ in A-G.
6. **Range to the waypoint** in km.
7. **Steering circle**: it moves sideways with the bearing to the waypoint.
8. **Aircraft cross**, fixed on the boresight. The bank scale arcs under the HUD's centre.

**Example**: 790 km/h (427 kt) at 3,100 m (10,200 ft), heading about 255°, level. The steering circle sits left of the
cross: the waypoint is 7.3 km away to the left. Turn left until the circle is over the cross.

---

## 4. Flying the MiG-29 with Real flight data

With Flight data = Real the MiG-29 row (docs/real-aircraft.md §9.4) is checked by the game's validation test.

| Item | In the game | Real MiG-29 9.12 |
| --- | --- | --- |
| Empty weight | 24,030 lb | 24,030 lb |
| Internal fuel | 7,720 lb | 4,200–4,365 l = 7,500–8,000 lb |
| Thrust, military / full afterburner | 22,220 / 36,600 lbf | 2 × 11,110 / 2 × 18,300 lbf (RD-33) |
| Wing area | 410 ft² | 410 ft² |
| 1 g stall speed, sea level | 132 kt (the original's envelope) | landing 127 kt, so about 115 kt |
| g limits | +9 / −3 | +9 below Mach 0.85, +7 above |
| Maximum speed, sea level / 40,000 ft | 781 kt / 1,322 kt | 700–810 kt / Mach 2.3 at 11 km |
| Climb at sea level | 42,600 ft/min | 49,600–65,000 ft/min |
| Fuel flow, military / full afterburner | 17,100 / 75,000 lb/h | about 17,100 / 75,000 lb/h |

What changes in the cockpit:

- **Fuel**: about 6 minutes at full afterburner, about 27 minutes at military power at sea level. The 3,500 lb
  centreline tank helps.
- **Mechanical flight controls**: the stick moves the surfaces directly, so you own the limits. At low speed a hard
  pull stalls the wing, and with Realistic spins on the jet can spin: recover with the stick forward and rudder
  against the spin.
- **Two engines**: the throttle keys move both; the damage page shows each engine.
- **Ground effect** (Physics): a longer float in the flare. **Real idle thrust on the ground**: at idle the jet taxis at
  about 35–45 kt.
- **Engine spool-up per real engine** (Physics): the thrust follows the RD-33's spool, slowest at first: 3 s from idle
  to military; the afterburner lights 0.8 s after the core reaches military and fills in 1.2 s. Out of afterburner the
  thrust drops at once. Published for the RD-33: idle to maximum 3–4 s, maximum to full afterburner 2–3 s, idle to full
  afterburner 4–5 s[^rd33].
- **Wind and turbulence** (Physics): the air moves with the tower's wind. The jet crabs into a crosswind and drifts
  downwind, a headwind shortens the take-off run, and light gusts shake it, strongest below 300 m (1,000 ft). The AI
  jets fly in the same air, bombs drift downwind (the bombing computer allows for it: the impact pipper moves downwind),
  and smoke, fire and trails drift with it. With a wind of 5 kt or more from behind the main runway the tower turns the
  base to the runway's other end: the starts, the tower's calls, the taxi signs, the autopilot, the AI and the ILS use
  that end; training missions keep their runway. Gameplay → No wind calms the air.
- **Nose dips under braking** (Physics): the nose dips up to 2° under the wheel brakes and squats up to 1° at full
  thrust on the brakes; it levels within about a second once the jet stops.
- **Unbalanced stores roll the jet** (Physics): stores left on one wing roll the jet toward it: hold that wing up with
  the stick, trim it out (**Alt+Left / Right**, or the throttle rocker with Devices → Throttle rocker = Roll trim),
  or let the autopilot (**A**) hold it while it flies. One MK-84 (2,020 lb) left
  on station 3, 3.5 m out, takes about 12 % stick at 290 kt and 1 g. It grows with the g in a pull, and at half the
  speed it takes four times as much.
- **The map edge**: 12 km (6.5 NM) before it the EndWorld warning sounds: turn back. Past it the game pushes the jet
  back for about 8 s (the nose rises and the jet turns).

### Take-off and landing numbers

| Item | MiG-29 with Real flight data |
| --- | --- |
| 1 g stall, sea level | 132 kt |
| Final approach | about 160 kt: 1.2 × the game's stall speed (inferred) |
| Touchdown limits (Real landing limits, Easy landing off) | sink below 4 m/s (790 ft/min), pitch below 15° |
| Drag chute (**Shift+B**) | drawn, with zero drag (the chute's drag is open) |

---

## 5. Radar and self-protection

The radar detects at **83 km** (45 NM) in LRS (long-range search), 35 NM in TWS (track while scan), 10 NM in ACM (air
combat mode) and boresight; MAP and GMT (ground moving target) 10 NM. Weapon data = Real keeps these numbers. The
left display shows the radar, the right one the RWR (radar warning receiver).

| Key | Action |
| --- | --- |
| **R** / **Q** / **S** | Radar on, A-A ↔ A-G / mode (LRS → TWS → ACM; GMT ↔ MAP) / standby |
| **.** / **,** | Range scale up / down |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace** | Drop the lock |
| **\\** (hold) | Boresight |

- **RWR**: the right display's RWR page and the AI / ML lamps at the panel's upper left; a new threat sounds a tone, a
  missile launch at you the launch warning. With Extras → *RWR: Real* it also shows the SAM and AAA radars searching you
  before they lock: a steady symbol and the new-threat tone. Drop behind a ridge and the symbol goes.
- **Chaff (Insert)** and **flares (Delete)**: 60 chaff and 30 flares. Chaff fools a radar missile with 10 % (30 %
  above 4 g), a flare an IR (infrared) missile with 33 % (50 % above 4 g) while the afterburner is off.
- Chaff and flares are the MiG-29's whole self-protection; the **J** jammer key belongs to jets with a jammer.
- **AWACS calls**: from 60 s into the flight the airborne controller calls the enemy aircraft within 35 NM, one scan
  every 12 s. "Alpha, bearing 090, 15 miles, target, heading 270, free to engage": the contact's bearing and distance
  from you, then its heading ("targets are already engaged" in place of "free to engage").
  "Unidentified contacts, please identify": your radar has not seen it yet; find it before you engage. A contact is
  called again, in short, after 60 s or when it moved more than 5 NM. Below 50 m (165 ft) the controller is silent.
- **Flight reports**: the radio reports your side's jets airborne, landed, crashed or ejected, and each kill 5 s after
  it.

What the MiG-29 can load on the Arming screen (stations 1, 2, 8, 9 the outer pylons, 3, 4, 6, 7 the inner ones, 5 the
centreline):

| Store | Stations |
| --- | --- |
| AA-11, AA-8, AA-2 | 1, 2, 3, 4, 6, 7, 8, 9 |
| AA-10, AA-6 | 3, 4, 6, 7 |
| MK-83 | 4, 6 (×3 each) |
| MK-84 | 3, 4, 5, 6, 7 |
| 3,500 lb tank | 5 |

The default load is four AA-11s on stations 1, 2, 8, 9 and four AA-10s on 3, 4, 6, 7.

---

## 6. The Щель-3УМ helmet sight

**When**: a target off the nose, within the R-73's seeker limits. **Keys**: **]** to the IR missile, then look at the
target: **Shift+arrows** (free look) or **F3** (padlock); **Space** fires.

![The Щель-3УМ helmet sight on a MiG-21 45° left](shots/mig29/helmet.png)

1. **«ШЛЕМ»** (helmet): the helmet sight is aiming.
2. **Seeker diamond** on the target the seeker tracks.
3. **Aiming cross** on your line of sight. «ПР» flashes above it when the missile can fire; an X shows when the
   target is outside the seeker's limits (±60° in azimuth, +60 / −14°).

**Example**: the MiG-21 flies away 2,000 m off, 45° left of the nose. Look at it: the seeker diamond settles on the
MiG and «ПР» flashes. Fire without turning the jet.

---

## 7. IR missiles: AA-11, AA-8, AA-2

**When**: a target inside the missile's range. **Keys**: **]** to the missile, **Space** fires. With a radar lock
(**R**, then **Return**) the seeker is slaved to the locked target within its cone; otherwise it looks within 6° of
the nose. Weapon data = Real keeps their game values.

| Missile | Game data |
| --- | --- |
| AA-11 | 260 lb; seeker cone 70°, range 15 NM, any aspect |
| AA-8 | 143 lb; seeker cone 21°, range 8 NM, target within 60° of your heading |
| AA-2 | 165 lb; seeker cone 15°, range 6 NM, target within 60° of your heading |

![An R-73 (AA-11) on a MiG-21 flying away 2,000 m ahead](shots/mig29/hud_srm.png)

1. **Target mark with the seeker's lock strobe**: the circle round it shows the seeker tracking.
2. **Mode name**: ТП (the seeker); БВБ with the radar's ACM, Ф0 with its boresight.
3. **«ПР»** (launch authorised).
4. **Range scale** in km, on the left: its top reads the scale (10, 25, 50 or 100 km).
5. **Target caret** with the range in km; the scale's ticks mark Rmax and Rmin.

**Example**: the MiG-21 flies away 2,000 m ahead, 50 m/s (97 kt) slower than you. The AA-11's zone runs from about
1.2 km to 20 km, «ПР» is lit: fire. Beyond half the missile's range the seeker sees only a jet with its afterburner
lit.

**Close combat.** In the radar's ACM the HUD draws the vertical scan, two lines from 10° below to 50° above the
boresight, with «РЛ»; in boresight (**\\** held) a 2.5° circle round the cross (Ф0).

---

## 8. Radar missiles: AA-10

**When**: a target beyond the IR missiles' range. **Keys**: **R** radar on, **Return** locks a contact, **]** to the
AA-10, **Space** fires. It is semi-active: keep the lock until it hits.

![An R-27 (AA-10) on a MiG-21 15 km ahead (ДВБ)](shots/mig29/hud_mrm.png)

1. **Target diamond** on the locked target.
2. **Steering circle**: keep the target diamond inside it.
3. **Mode name**: ДВБ (long-range combat).
4. **Range scale** in km: 100 here.
5. **Target caret** with the range: 15 km.
6. **«ПР»** (launch authorised); inside Rmin «ОТВ» (break away) takes its place.

**Example**: the MiG-21 is 15 km ahead, closing at 250 m/s (486 kt). The AA-10's zone runs from about 1.5 km to
51 km, so «ПР» is lit: fire, and hold the lock while the missile flies.

---

## 9. Gun

**When**: a target inside about 600 m. **Keys**: **]** to the gun, **Tab** fires. With Real data the game's 20 MM
record fires 6,000 rounds/min at 1,030 m/s: the 140 rounds last about 1.4 s.

![The gun: a MiG-21 600 m ahead](shots/mig29/hud_gun.png)

1. **Pipper**: the cross on the lead-computed aim point.
2. **Ring with the range bar**: with a radar lock the bar runs round the ring, a full turn for 1,200 m (inferred).
3. **Target diamond** on the locked MiG-21.

**Example**: the MiG-21 is 600 m ahead and closing at 486 kt: the range bar covers half the ring. Put the cross on
the MiG and fire a short burst: 0.5 s is 50 rounds. Without a lock the HUD draws a funnel for the real gun, the
GSh-30-1, whose rounds leave at 860 m/s[^gsh30]. With Weapon data Real the game fires the GSh-30-1's rounds (860 m/s,
150 of them), so the funnel lies on their path; with Original data the rounds are the 20 MM record's.

---

## 10. Bombs (ОПТ ЗЕМЛЯ)

**When**: MK-83 / MK-84 bombs. **Keys**: **[** to the store, hold **Space** to release (the ripple releases one store
per interval; the stores page sets it).

![A 45° dive at 800 m above the ground, two MK-83s (ОПТ ЗЕМЛЯ)](shots/mig29/hud_bomb.png)

1. **Pipper** on the predicted impact.
2. **Mode name**: ОПТ ЗЕМЛЯ (optical, ground).
3. **Aircraft cross**: the fall line runs from it to the pipper.

**Example**: two MK-83s, a 45° dive at 428 kt (220 m/s), 800 m (2,600 ft) above the ground. Steer so that the target
slides down the fall line, and release when it reaches the pipper.

---

## 11. Landing (ПОС)

**When**: on final approach, gear handle down (**G**). **Keys**: **G** gear, **F** flaps, **B** wheel brakes, **Ctrl+T**
call the tower.

![Final approach (ПОС)](shots/mig29/landing.png)

1. **Mode name**: ПОС (landing), with the gear down.
2. **Range** to the waypoint in km.
3. **Steering circle**.
4. **Radar height** in metres.

**Example**: 261 km/h (141 kt), about 200 m (650 ft) above the ground, 4 km short of the runway. The ILS (instrument
landing system) bars cross near the aircraft cross: steer toward the vertical bar, climb or descend toward the
horizontal one, and bring the speed up to about 160 kt.

---

## 12. Better cockpit

**When**: any flight. **Keys**: tap **V** for the whole panel (hold it to glance down and back), **PgUp** / **PgDn**
slide it.

The 1998 game drives the MiG-29's panel with the Western jets' needles: the airspeed lands on the radar altimeter, the
vertical speed on the AoA / g meter. With Better cockpit on, each needle reads the dial it sits on, in its own units,
the displays are drawn sharp, and the needles follow their values with a 0.3 s instrument lag.

![The panel with Better cockpit on, on final](shots/mig29/better_panel.png)

1. **Radar altimeter**, in metres on a non-linear face (0–1,500 m). The red flag shows above 1,500 m or beyond 60° of
   bank. Below the yellow index, 70 m, an amber lamp lights and, with the gear handle up, Betty calls "Altitude" every
   4 s.
2. **Barometric altimeter**, in metres: one turn per 1,000 m.
3. **КПП** (attitude director indicator).
4. **Left engine's RPM**, in %.
5. **Right engine's RPM**, in %.
6. **AoA / g meter**: the AoA on the left scale (0–30°), the g on the right (0–10); a third, shorter needle holds the
   highest g since the start and resets on the ground.
7. **Fuel**: all the fuel, the drop tank included, on the lb face.
8. **The RWR page** on the right display.

**Example**: on final the radar altimeter reads about 200 m, as the HUD does, and both tachometers show the
approach power. Below 70 m with the gear still up the amber lamp and Betty would warn you.

---

## 13. Night vision

**When**: night missions (the game's night is 20:00–05:30; mission 214 starts at 01:00), with Graphics → MORE →
Night vision = Goggles. **Keys**: **Shift+N** puts the goggles on and takes them off.

The goggles are ours: the 1998 game has none. They turn the outside view into a brightened green picture; the
cockpit and the HUD stay as you see them under the goggles. Set Graphics → MORE → Night lights = Detailed too, for
the moon, the stars and the lights on the ground.

![01:00 without goggles](shots/mig29/night.png)

![The same moment through the goggles](shots/mig29/night_nvg.png)

- The ground's relief and texture show, and the horizon is clear: fly by the outside view.
- The goggles set their own gain: the darker the scene, the more they brighten it, and the grainier it gets.
- The HUD shows in its brightest green while the goggles are on; your own level comes back when they come off.
- The MiG-29's panel lighting does not suit goggles: its glow washes out the picture's lower part and lowers
  the gain.
- A view full of light (a close explosion, daylight) darkens the goggles: take them off by day.
- The goggles follow the mission's year: none before 1972, a grainy Gen II up to 1981, a Gen III from 1982, the
  sharpest from 1996 (the 1998 missions).
- In a MiG the goggles are the older, grainier Gen II at best (the Soviet ONV-1).
- A bright light (a fire, a flare, a runway light) gets a halo around it.
- The picture darkens toward its edges.

## 14. Key card

| Key | Action |
| --- | --- |
| 1 … 8 | Throttle: idle, 65, 70, 80, 90 %, military, AB 1, AB 2 |
| 9 / 0 | Throttle − / + 5 % |
| V / PgUp / PgDn | Whole panel ↔ none (hold V: a glance down) / slide the panel up / down |
| Arrows | Stick |
| Alt+Left / Right | Roll trim left / right (hold). Ctrl+F12 shows it (TRIM L / R %) |
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
| Shift+arrows, Numpad 1–9, F3 | Look around (the helmet sight), snap views, padlock |
| Shift+N | Night-vision goggles on / off (Graphics → MORE "Night vision") |
| F1 / Ctrl+F2 | Cockpit ↔ HUD only / cockpit ↔ external |
| SysRQ | Screen capture: a PNG in the `screenshots` folder of the game's user folder |
| X | Fire extinguisher (one charge) |
| E | Eject |
| C / Ctrl+C | Time ×2 ×4 ×1 / normal time |
| Ctrl+P / Ctrl+O / Esc | Pause / in-flight menu / TSD map |
| Alt+E / W / P / T / C / B | Wingman: engage my target / other target, protect me, tactical / close formation, go home |

---

## 15. Abbreviations

| Term | Meaning |
| --- | --- |
| A-A / A-G | air-to-air / air-to-ground |
| AB | afterburner |
| ACM | air combat mode: the radar's close-range lock mode |
| AoA | angle of attack |
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
| STT | single-target track: a radar lock |
| TSD | tactical situation display: the map |
| TWS | track while scan |
| БВБ | ближний воздушный бой: close combat (the radar's ACM) |
| ДВБ | дальний воздушный бой: long-range combat |
| МРШ | маршрут: the route |
| ОПТ ЗЕМЛЯ | optical sight, ground target |
| ОТВ | отворот: break away |
| ПОС | посадка: landing |
| ПР | пуск разрешён: launch authorised |
| РЛ | the radar |
| ТП | the IR seeker (теплопеленгатор) |
| Ф0 | the boresight |
| ШЛЕМ | шлем: the helmet sight |

[^ea]: Eagle Dynamics, *DCS MiG-29A Early Access Manual* (Sept 2025), pp. 65–104 (the HUD), https://www.digitalcombatsimulator.com/upload/iblock/aa2/ulzl67k42kj99ushy9m29hlvmtk0y2tg/DCS%20MiG-29A%20Early%20Access%20Manual%20EN.pdf

[^fc3]: Eagle Dynamics, *DCS MiG-29 Flight Manual* (Flaming Cliffs 3), pp. 40–59 (the HUD), https://www.digitalcombatsimulator.com/upload/iblock/463/DCS%20MIG-29%20Flight%20Manual%20EN.pdf

[^gsh30]: Wikipedia, "Gryazev-Shipunov GSh-30-1" (muzzle velocity 860 m/s), https://en.wikipedia.org/wiki/Gryazev-Shipunov_GSh-30-1

[^rd33]: propulsionplant.ru, RD-33: idle to maximum 3–4 s, maximum to full afterburner 2–3 s, idle to full afterburner 4–5 s (secondary, no source given), http://www.propulsionplant.ru/dvigateli/aviacionnye-raketnye-morskie-promyshlennye/82178217zavod-imeni-v-ja-klimova82178217-gunpp/rd-33.html

