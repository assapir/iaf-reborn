# Kfir pilot guide (realistic settings)

This guide covers what changes in the Kfir C7 when you switch on the realistic options: the Kfir's own HUD (head-up
display), the real jet's numbers and the real weapons. The Kfir C7 is the single-seat delta of the game's model. Each
HUD mode has its own section: when to use it, the keys, a picture whose numbered yellow callouts the list under it
explains, and a worked example. The numbers come from the game's own data and tests. Section 13 explains the
abbreviations.

---

## 1. What's different in this jet

| Area | The 1998 game | With the realistic options |
| --- | --- | --- |
| HUD | One simplified HUD for every jet: boxed speed and altitude tapes, a heading tape at the top, three text rows each side | The Kfir C7's Elbit HUD: speed and altitude as numbers, a heading scale with a steering bug, a waypoint marker on the ground, a straight ladder \[R\] |
| Gun sight | A lead-computing pipper with a range arc | Two gun modes: **LCOS** (lead-computing optical sight) with a radar range, **HOTL** (hotline) before it |
| IR missiles | A circle and a seeker cue | The seeker diamond: it spins while it searches and holds on the target once locked |
| Bombs | A pipper circle with a fall line | The Kfir's CCIP pipper (a dot in a 20 mr circle) and its fall line from the flight path marker |
| Flight data | The game's own Kfir: 20,000 lb empty, 9,600 / 16,000 lbf | Kfir C7 (J79-J1E): 16,060 lb empty, 11,870 / 17,900 lbf, 5,670 lb internal fuel (the original 8,000 lb), +7.5 / −3.5 g |
| Weapon data | The game's own values | 2 × DEFA 553 guns with 2 × 140 rounds, the EL/M-2001B ranging radar at 14.8 km, real missile weights, speeds and ranges |
| Physics | The original's quirks: still air, instant thrust | Real touchdown limits, ground effect, a flight-path hold with the stick centred, realistic spins, the tower's wind, the engine's real spool-up |

\[R\] marks a reconstruction: the Kfir's modes and the data it shows are public (Flight International 1983, the Elbit
System 82), its HUD layout is public in outline, so the game draws an early-1980s Elbit layout.

![The 1998 HUD at the start of mission 231](shots/cfir/hud_original.png)

The same moment with the Real HUD is the first picture of section 3.

**HUD warnings.** The Kfir has no Betty voice. The 1998 HUD draws a large X across its centre in the A-G gun and bomb
modes while the dive is steeper than 1° per 100 ft above the ground (20° at 2,000 ft), and in place of the missile
circle when the locked target is inside the missile's minimum range (Rmin). The Real HUD draws no X (the real Kfir's
marks are not public).

---

## 2. Settings

Set these on the Preferences screen before the flight. Every row starts at the 1998 game's setting.

| Tab | Row | Set to | What it changes |
| --- | --- | --- | --- |
| Extras | Flight data | Real aircraft | The Kfir C7 numbers (section 4) |
| Extras | Weapon data | Real weapons | Radar range, gun rounds, missile weights, speeds and ranges |
| Extras | HUD | Real | The Kfir's HUD (looking aside shows the original's helmet display) |
| Extras | Better cockpit | Better | A turning panel compass, live engine and fuel needles on their labelled dials, sharp display pages (section 11) |
| Extras | World scale | Real 1:1 | True-size models; every airbase at its real place, with its real runway numbers |
| Extras | RWR | Real | The SAM / AAA radars searching you show too, until terrain hides you (section 5) |
| Graphics → MORE | Sky, Terrain close up, Imagery Israel / outside Israel | Atmospheric, Detailed, Survey 2 m / Sentinel-2 | A physical sky, ground detail and photo imagery, if setup converted it |
| Graphics → MORE | Airbases | Detailed | Runways, taxiways and aprons with real markings near the ground |
| Graphics → MORE | Night vision (Shift+N) | Goggles | Night-vision goggles in flight: a green, brightened outside view on night missions |
| Physics | every row | on | Section 4 lists the ones that change how the Kfir flies |
| Physics | Nose dips under braking, Unbalanced stores roll the jet, Wind and turbulence, Engine spool-up per real engine | on | The brakes' pitch, the stores' roll, the tower's wind and the engine's real spool (section 4) |
| Devices | Throttle rocker | Roll trim | A stick's spring-centred 5th axis (the throttle rocker in 5-axis mode) trims roll, to hold a heavy wing up (section 4). The row shows only for a stick with a 5th axis |
| Gameplay | Easy landing, Easy aiming, No blackouts / spins / stalls, No wind | off | Real landing limits, real launch rules, g-effects, stalls and the mission's wind |

A greyed-out imagery choice needs its data: convert it with `tools/setup-cli.sh --imagery`.

---

## 3. NAV: reading the HUD

**When**: cruising, flying to a waypoint, and between attacks. **Keys**: **N** returns to NAV from any weapon mode.
**W** / **Shift+W** pick the next / previous waypoint. **H** changes the HUD colour.

![NAV at 10,000 ft, waypoint 1 ahead](shots/cfir/hud_nav.png)

1. **Airspeed**: calibrated airspeed in knots, as a number.
2. **Mach** number.
3. **Altitude** above sea level, in feet, as a number.
4. **Heading scale**: a 30° window along the top, labels in tens (`27` = 270°), read at the centre caret.
5. **Steering bug**: the triangle under the caret marks the waypoint's bearing. Turn until it sits under the caret.
   When the waypoint is more than 15° off, the bug waits at the scale's end with an arrow pointing the way to turn.
6. **Flight path marker**: where the jet is going.
7. **Pitch ladder**: the horizon line here; the bars are straight.
8. **g** (load factor).
9. **Mode**: `NAV`. The other modes: `MSL`, `LCOS`, `HOTL`, `STRF`, `CCIP`.
10. **Distance** to the waypoint in nautical miles (NM): `D4.7`.
11. **Waypoint number**: `WP1`.
12. **Waypoint marker**: a circle on a post, drawn on the ground at the waypoint. Held at the HUD's edge, it carries
    an X.

**Example**: at the start of mission 231 the bug sits under the caret: waypoint 1 is straight ahead, 4.7 NM away. Its
marker waits at the bottom edge with an X: the waypoint is below the HUD's view. Lower the nose until the marker
leaves the edge, then put the flight path marker on it.

---

## 4. Flying the Kfir with Real flight data

With Flight data = Real the Kfir C7 row comes from Jane's and other public figures, checked by the game's validation
test. The 1998 Kfir weighed 25 % more and had less thrust.

| Item | In the game | Real Kfir C7 |
| --- | --- | --- |
| Empty weight | 16,060 lb | 16,060 lb (Jane's) |
| Internal fuel | 5,670 lb | 2,572 kg = 5,670 lb (Jane's) |
| Thrust, military / full afterburner | 11,870 / 17,900 lbf | 11,870 / 17,900 lbf (J79-J1E) |
| Wing area | 375 ft² | 375 ft² |
| 1 g stall speed | 127 kt (uncertain) | approach about 160–175 kt (uncertain) |
| g limits | +7.5 / −3.5 | +7.5 / −3.5 |
| Maximum roll rate | 150°/s (the original's) | unpublished |
| Maximum speed, sea level / 40,000 ft | 771 kt / 1,139 kt (Mach 1.99) | about 750 kt / Mach 2.0 sustained |
| Climb at 350 kt, sea level | about 27,900 ft/min | 45,930 ft/min (peak, light) |
| Fuel flow, military / full afterburner | 9,970 / 35,200 lb/h | about 9,970 / 35,200 lb/h |
| Service ceiling | 58,000 ft | above 58,000 ft |

What changes in the cockpit:

- **Fuel**: about 10 minutes at full afterburner, about 34 minutes at military power. The Kfir carries the least fuel
  of the game's jets; the 2,550 lb tanks go on stations 3, 5 and 7.
- **Turns**: the delta bleeds speed fast in a hard turn, and the g limit is 7.5. Turn in short pulls and keep the
  speed up.
- **Mechanical flight controls**: the stick moves the surfaces directly. A hard pull at low speed stalls the wing, and
  with Realistic spins on the jet can spin. Recover with the stick forward and the rudder against the spin, then pull
  out of the dive.
- **Flight-path hold** (Physics): with the stick centred the jet holds its flight path.
- **Ground effect** (Physics): a longer float in the flare. **Real idle thrust on the ground**: at idle the jet taxis at
  about 35–45 kt.
- **The stick on the keyboard** gives full deflection at once, as in the original; a joystick is smoother.
- **Engine spool-up per real engine** (Physics): the thrust follows the J79-J1E's spool, slowest at first: 5 s from idle
  to military; the afterburner lights 1 s after the core reaches military and fills in 1.5 s. Out of afterburner the
  thrust drops at once. The J79-J1E is a licence-built J79-GE-17, so the game uses the -17's: 5 s at best on a test-cell
  chart[^dcsj79]; the afterburner times are open.
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
  or let the autopilot (**A**) hold it while it flies. One 2,000 lb bomb on an
  outer wing pylon, 3.1 m out, takes about 16 % stick at 290 kt and 1 g. It grows with the g in a pull, and at half the
  speed it takes four times as much.
- **The map edge**: 12 km (6.5 NM) before it the EndWorld warning sounds: turn back. Past it the game pushes the jet
  back for about 8 s (the nose rises and the jet turns).

### Take-off and landing numbers

| Item | Kfir with Real flight data |
| --- | --- |
| Rotate | 145 kt |
| Gear up below | 300 kt |
| Downwind / final | 200 kt at 2,000 ft above the ground / 165 kt |
| 1 g stall | 127 kt (uncertain) |
| Touchdown limits (Real landing limits, Easy landing off) | sink below 4 m/s (790 ft/min), pitch below 15° |
| Drag chute (**Shift+B**) | drawn, with zero drag (its size is unpublished) |
| Nose-wheel steering | rudder pedals, ±30° (uncertain) |

---

## 5. Radar and self-protection

The real Kfir C7 carries the **EL/M-2001B ranging radar**. In the game it has the same radar modes as every jet; with
Weapon data = Real its detection range is **14.8 km** (8 NM; uncertain, one database). Use it to lock and range at
close range. It sees targets from 30 m above the ground, in line of sight; the one display starts on it.

| Key | Action |
| --- | --- |
| **R** / **Q** / **S** | Radar on, A-A (air-to-air) ↔ A-G (air-to-ground) / mode (LRS → TWS → ACM; GMT ↔ MAP) / standby |
| **.** / **,** | Range scale up / down |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace** | Drop the lock |
| **\\** (hold) | Boresight: a ±12° lock cone straight ahead |

- **RWR** (radar warning receiver): the panel dial shows emitters and missiles around you; a missile launch at you
  sounds the launch warning. With Extras → *RWR: Real* it also shows the SAM and AAA radars searching you before they
  lock: a steady symbol and the new-threat tone. Drop behind a ridge and the symbol goes.
- **Chaff (Insert)** and **flares (Delete)**: 90 chaff and 60 flares. A flare fools an IR (infrared) missile with 33 %
  (50 % above 4 g) while the afterburner is off: pull hard, come out of afterburner, then flare. Self-protection is
  chaff and flares; **J** is the ECM pod's key on the jets that carry one.
- **AWACS calls**: from 60 s into the flight the airborne controller calls the enemy aircraft within 35 NM, one scan
  every 12 s. "Alpha, bearing 090, 15 miles, target, heading 270, free to engage": the contact's bearing and distance
  from you, then its heading ("targets are already engaged" in place of "free to engage").
  "Unidentified contacts, please identify": your radar has not seen it yet; find it before you engage. A contact is
  called again, in short, after 60 s or when it moved more than 5 NM. Below 50 m (165 ft) the controller is silent.
- **Flight reports**: the radio reports your side's jets airborne, landed, crashed or ejected, and each kill 5 s after
  it ("Alpha leader shot down MiG 29").

---

## 6. MSL: AIM-9D, AIM-9L, Python 3

**When**: a target inside a few miles, best from behind. **Keys**: **]** until `MSL`, **Space** to fire. With a
radar lock (**R**, then **Return**) the seeker is slaved to the locked target.

### Searching

![A Python 3 searching: the diamond spins](shots/cfir/hud_srm_search.png)

1. **Seeker diamond**, spinning: the seeker searches straight ahead.
2. **Gun cross**: shown in every weapon mode.
3. **Rounds** of the selected store: two missiles.
4. **Mode**: `MSL`.

### Locked

![A Python 3 locked on a MiG-23 1.6 NM ahead](shots/cfir/hud_srm.png)

1. **Seeker diamond**, still, on the target: the seeker tracks it. This is the Kfir's cue to fire.
2. **Radar box** on the locked target.
3. **Rounds**.
4. **Mode**.

| Missile | Real data |
| --- | --- |
| AIM-9D | 88.5 kg, Mach 2.5, 18 km, rear-aspect, 12 g |
| AIM-9L | 86 kg, Mach 2.5, 17.7 km |
| Python 3 | 120 kg, Mach 3.5, 15 km, 30° off the nose |

**Example**: a MiG-23 is 3,000 m (1.6 NM) ahead. Lock it on the radar (**Return**) and select the Python 3 (**]**).
The diamond stops spinning and sits in the radar box with a high tone: fire (**Space**). The AIM-9D's rear-aspect
seeker tracks a target flying away from you: get behind it first. Beyond half its range a seeker sees a jet with its
afterburner lit.

---

## 7. A-A gun: LCOS and HOTL

**When**: a target inside about 3,000 ft. **Keys**: **]** to the gun, **Tab** fires. The two DEFA 553 guns have
2 × 140 rounds at 2 × 1,300 rounds/min and 815 m/s: about 6.5 s of firing. The mode window shows `LCOS` once the radar
ranges the target and `HOTL` before.

### LCOS: with a radar range

![LCOS on a MiG-23 at 2,600 ft](shots/cfir/hud_gun.png)

1. **LCOS reticle**: a 50 mr (milliradian) ring with 12 ticks around a dashed inner circle.
2. **Range arc** inside the ring: 1,000 ft per tick from 12 o'clock.
3. **Pipper**: the lead-computed aim point. Put it on the target and fire.
4. **Radar box** on the target.
5. **Gun cross**.
6. **Rounds**: 280.
7. **Mode**: `LCOS`.

**Example**: the MiG is 800 m (2,600 ft) ahead. The range arc runs a little past the second tick (2,000 ft) toward the
third: inside 3,000 ft. Put the pipper on the MiG and hold **Tab** for a 1 s burst (about 43 rounds).

### HOTL: before the radar ranges

![HOTL: the gun before a radar range](shots/cfir/hud_hotline.png)

1. **Gun cross**: the hotline hangs from it, the bullets' path as you fly now.
2. **1,000 ft tick**.
3. **2,000 ft tick**.
4. **3,000 ft tick**.
5. **Mode**: `HOTL`.

**Example**: the MiG is 2,600 ft ahead, the radar off. Pull until the MiG sits on the line between the 2,000 and
3,000 ft ticks, then fire. The hotline is a reconstruction of the era's lead-computing line \[R\].

---

## 8. A-G gun: STRF

**When**: strafing a ground target. **Keys**: **[** to the gun (`STRF`), **Tab** fires.

![STRF in a 20° dive at 2,177 ft](shots/cfir/hud_strf.png)

1. **Strafe pipper** (a dot in a 20 mr circle): where the rounds hit. The target sits under it here.
2. **Flight path marker**.
3. **Mode**: `STRF`.
4. **Altitude**: 2,177 ft above sea level, about 1,970 ft above this ground.

**Example**: dive at 20° and 414 kt. With the pipper on the target, fire a short burst and pull out: at 20° and
414 kt the ground comes up at about 240 ft/s.

---

## 9. Bombs and rockets: CCIP

**When**: MK-82 / MK-83 / MK-84, the CBU-87 / CBU-97 clusters and ZUNNI rockets. **Keys**: **[** until `CCIP`; hold
**Space** to release. The stores page sets the ripple: quantity 1–14, interval 10–200 (default 2 bombs, 10 m apart).

![CCIP in a 45° dive at 2,300 ft above the ground](shots/cfir/hud_ccip.png)

1. **CCIP pipper** (continuously computed impact point): where the bomb lands now. It follows the terrain.
2. **Bomb fall line**: from the flight path marker to the pipper. Keep the target on it.
3. **Flight path marker**.
4. **Rounds**: 12 MK-82s on stations 3 and 7.
5. **Mode**: `CCIP`.
6. **Altitude**: 2,506 ft above sea level.

**Example**: 12 MK-82s, a 45° dive at 413 kt, 2,300 ft above the ground. Roll in with the target above the marker,
let the fall line carry it down, and press **Space** when it reaches the pipper. The game's training warns against
GP (general-purpose) bombs below 2,000 ft above the ground. The Kfir flies with bombs and rockets: its MK-82L / MK-83L
laser bombs fall as plain bombs on the CCIP pipper.

**Delayed release**: when the impact point lies below the HUD's lower edge, put the target under the pipper held at
the edge and hold **Space**. The bombs go at 0.9 s to go, with positive g and less than 90° of bank.

---

## 10. Landing: the gear-down HUD

**When**: on final approach, gear handle down (**G**). **Keys**: **G** gear, **F** flaps, **B** wheel brakes, **Ctrl+T**
calls the tower near an Israeli base. The approach speeds and touchdown limits are in section 4.

With the gear down the AoA (angle of attack) takes the row under the g. The ILS (instrument landing system) lines
guide you to the nearest airbase's runway.

![Final approach, 3.6 NM out at about 900 ft, 141 kt](shots/cfir/landing_final.png)

1. **Flight path marker**: on the runway here.
2. **AoA**: 3° here.
3. **ILS glide-slope line**: it crosses the localizer line at the HUD's centre when you are on the runway's centre
   line and on a 5° glide path. It drops when you are high.
4. **ILS localizer line**, held at the HUD's left edge here.
5. **Steering bug** held at the scale's right end, its arrow pointing right: the waypoint is more than 15° right.
6. **Waypoint marker** with its X, held at the edge.
7. **Airspeed**: 141 kt.
8. **Altitude**: about 900 ft.

**Example**: here the jet flies a 3° path at 3° AoA, the glide-slope line above the HUD's centre: you are under the
5° path. Fly the approach on the speed: 165 kt on final (the game's landing lesson). Above about 4° AoA the marker
sits under the HUD glass's lower edge in this cockpit.

---

## 11. Better cockpit

**When**: any flight. **Keys**: tap **V** for the whole panel (hold it to glance down and back), **PgUp** / **PgDn**
slide it.

With Better cockpit on, the compass at the bottom of the panel turns with the heading, the engine and fuel needles on
the right of the panel show the flight model's own values, and each engine needle sits on the dial its label names. The
display's pages are drawn sharp at the screen's resolution. In the 1998 game the compass is a still picture, the needles
read rough values, and the temperature needle sits on the FUEL FLOW dial while the EXH TEMP dial stays still. The
needles follow their values with a 0.3 s instrument lag.

![The Kfir panel with Better cockpit on](shots/cfir/better_panel.png)

1. **Lubber mark**: the heading reads on the card under it, here about 320°.
2. **Compass card**: it turns as the jet turns. The letters are the cardinal points (N, E, S, W), the numbers tens of
   degrees (`33` = 330°).
3. **Aircraft symbol**: fixed; it stands for your jet, its nose toward the lubber mark.
4. **RPM** (PERCENT RPM): the engine's real RPM, 60 % at idle, 100 % at military. It needs about 5 s from idle to
   military (3 s with Engine spool-up off).
5. **Exhaust temperature** (EXH TEMP, lower left of the engine dials): about 450 °C at idle and 650 °C at military, a
   little more in AB; 900 °C with an engine fire. It rises in about 2 s and falls slowly.
6. **Fuel flow** (FUEL FLOW): it follows the throttle, as on the F-4E: military at the full mark; in AB it moves on
   past military, further in AB 2.
7. **Fuel needle**: all the fuel you carry, the drop tanks too, over the most the jet holds with them. It falls from
   the first pound burnt (in the 1998 game it stays full until the tanks are empty).

The small dial right of the RPM dial, where the 1998 game draws the throttle needle, then has no needle: its label is
too small to read.

**Example**: the HUD's heading scale is a 30° window; the compass shows the whole circle. To fly 090° from 320°, find
9 on the card: it sits on the card's right half, so turn right and roll out when 9 reaches the lubber mark. Take off
with a drop tank: the fuel needle starts full and falls from the first minute. At half scale you have half of all
the fuel you took off with, the tank's included.

---

## 12. Night vision

**When**: night missions (the game's night is 20:00–05:30; mission 214 starts at 01:00), with Graphics → MORE →
Night vision = Goggles. **Keys**: **Shift+N** puts the goggles on and takes them off.

The goggles are ours: the 1998 game has none. They turn the outside view into a brightened green picture; the
cockpit and the HUD stay as you see them under the goggles. Set Graphics → MORE → Night lights = Detailed too, for
the moon, the stars and the lights on the ground.

![01:00 without goggles](shots/cfir/night.png)

![The same moment through the goggles](shots/cfir/night_nvg.png)

- The ground's relief and texture show, and the horizon is clear: fly by the outside view.
- The goggles set their own gain: the darker the scene, the more they brighten it, and the grainier it gets.
- The HUD shows in its brightest green while the goggles are on; your own level comes back when they come off.
- The Kfir's panel lighting does not suit goggles: its glow washes out the picture's lower part and lowers
  the gain.
- A view full of light (a close explosion, daylight) darkens the goggles: take them off by day.
- The goggles follow the mission's year: none before 1972, a grainy Gen II up to 1981, a Gen III from 1982, the
  sharpest from 1996 (the 1998 missions).
- A bright light (a fire, a flare, a runway light) gets a halo around it.
- The picture darkens toward its edges.

## 13. Key card

On a Mac, **Cmd** takes the place of **Ctrl** in every key below and in this guide (macOS keeps Ctrl + arrows and
Ctrl + F-keys for its desktops). The game shows Cmd there.

| Key | Action |
| --- | --- |
| 1 … 8 | Throttle: idle, 65, 70, 80, 90 %, military, AB 1, AB 2 |
| 9 / 0 | Throttle − / + 5 % |
| V / PgUp / PgDn | Whole panel ↔ none (hold V: a glance down) / slide the panel up / down |
| Arrows | Stick |
| Alt+Left / Right | Roll trim left / right (hold). Ctrl+F12 shows it (TRIM L / R %) |
| Numpad 0 / Decimal | Rudder left / right |
| G / F / B | Gear / flaps / wheel brakes |
| A | Autopilot: level → NAV → off |
| W / Shift+W | Next / previous waypoint |
| Ctrl+T | Call the tower |
| M / N | Master mode cycle / NAV |
| ] / [ | Next A-A / A-G weapon |
| Space / Tab | Fire the weapon / the gun |
| Shift+C | Jettison tanks, then bombs |
| R / Q / S | Radar on, A-A ↔ A-G / mode / standby |
| . / , | Radar range up / down |
| Return / Shift+Return | Next / previous target (locks in LRS) |
| Backspace | Drop the lock |
| \\ (hold) | Boresight |
| T / D | TSD / damage page |
| Insert / Delete | Chaff / flare |
| H | HUD colour |
| Shift+arrows, Numpad 1–9, F3 | Look around, snap views, padlock |
| Shift+N | Night-vision goggles on / off (Graphics → MORE "Night vision") |
| F1 / Ctrl+F2 | Cockpit ↔ HUD only / cockpit ↔ external |
| SysRQ | Screen capture: a PNG in the `screenshots` folder of the game's user folder |
| X | Fire extinguisher (one charge) |
| E | Eject |
| C / Ctrl+C | Time ×2 ×4 ×1 / normal time |
| Ctrl+P / Ctrl+O / Esc | Pause / in-flight menu / TSD map |
| Alt+E / W / P / T / C / B | Wingman: engage my target / other target, protect me, tactical / close formation, go home |

---

## 14. Abbreviations

| Term | Meaning |
| --- | --- |
| A-A / A-G | air-to-air / air-to-ground |
| AB | afterburner |
| ACM | air combat mode: the radar's close-range lock mode |
| AoA | angle of attack |
| CCIP | continuously computed impact point: where the bomb lands now |
| DEFA | the French 30 mm aircraft gun (DEFA 553) |
| ECM | electronic countermeasures: jamming |
| EXH TEMP | exhaust temperature |
| GMT | ground moving target |
| GP | general-purpose (bomb) |
| HOTL | hotline: the bullets' path from the gun cross |
| HUD | head-up display |
| ILS | instrument landing system |
| IR | infrared (heat-seeking) |
| kt | knots |
| lbf | pound-force (thrust) |
| LCOS | lead-computing optical sight |
| LRS | long-range search |
| mr | milliradian (1 mr spans 1 m at 1 km) |
| MSL | the missile mode |
| NAV | navigation mode |
| NM | nautical mile (1,852 m) |
| \[R\] | a reconstruction: the real layout is public in outline |
| RPM | engine speed, as % of maximum |
| RWR | radar warning receiver |
| STRF | strafe: the air-to-ground gun |
| STT | single-target track: a radar lock |
| TSD | tactical situation display: the map |
| TWS | track while scan |

[^dcsj79]: DCS World forum, "Spoolup time of J79 engines too quick": a J79-GE-17 test-cell chart, 5 s from idle to military at best (forum posts quoting the chart), https://forum.dcs.world/topic/349516-spoolup-time-of-j79-engines-too-quick/

