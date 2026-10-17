# Lavi pilot guide (realistic settings)

This guide covers what changes in the IAI Lavi when you switch on the realistic options: its own wide-angle HUD
(head-up display), the design figures of the real jet and the real weapons. The game's model is the **two-seat
Lavi**, the B-3 Technology Demonstrator of the game's Reference text. The Lavi stayed a prototype (cancelled in August
1987), so its Real flight data are the single-seat production design figures (Jane's 1987-88). Each HUD mode has its
own section: when to use it, the keys, a picture with numbered callouts, what each symbol means, and a worked example.
Section 13 explains the abbreviations.

How to read the pictures: each yellow number points at one symbol. The list under the picture explains it.

---

## 1. What's different in this jet

The real Lavi had a Hughes wide-angle diffractive HUD driven by Elbit's display system. Its symbology stays
unpublished, so the Real HUD draws a reconstruction [R] of a late-1980s US / Israeli wide-angle HUD: digital boxes, a
heading scale with a steering bug, straight ladder bars, an LCOS gun sight and CCIP.

| Area | The 1998 game | With the realistic options |
| --- | --- | --- |
| HUD | One simplified HUD for every jet: boxed speed and altitude, a heading tape, three text rows each side | The Lavi's own layout [R]: boxed airspeed and altitude, a data column under each, a 30° heading scale on top with a steering bug |
| Navigation | A heading caret and a waypoint row | The steering bug over the steerpoint's bearing, or an arrow with the bearing when the steerpoint lies outside the scale; the steerpoint block `WP n`, distance, time |
| Gun sight | A lead-computing pipper with a range arc | The LCOS (lead-computing optical sight) reticle: a ring with clock tics, a dashed inner circle, a pipper and a range arc |
| IR missiles | A circle and a seeker cue | The missile circle, the seeker diamond, the launch-zone scale and SHOOT under the mode |
| Radar missiles | A circle and a predicted point | A launch circle that grows inside the zone, the steering dot and the launch-zone scale with its max / min ticks |
| Bombs | A pipper circle with a fall line | The CCIP pipper with the fall line from the flight path marker |
| Flight data | The game's own Lavi | The design figures (PW1120): 6,000 lb internal fuel, +9 / −3 g, 110 kt stall, Mach 1.85 at altitude |
| Weapon data | The game's own values | EL/M-2035 radar out to 46 km, real missile weights, speeds and ranges |
| Physics | The original's quirks | The F-16's deep stall (a stand-in), real touchdown limits, ground effect, a flight-path hold with the stick centred |

![The 1998 HUD at the start of mission 231](shots/lavi/hud_original.png)

The same moment with the Real HUD is the first picture of section 3. Looking aside, the Lavi keeps the original
game's helmet display.

---

## 2. Settings

Set these on the Preferences screen before the flight. Every row starts at the 1998 game's setting.

| Tab | Row | Set to | What it changes |
| --- | --- | --- | --- |
| Extras | Flight data | Real aircraft | The Lavi design numbers (section 10) |
| Extras | Weapon data | Real weapons | Radar range, missile weights, speeds and ranges |
| Extras | HUD | Real | The Lavi's HUD reconstruction |
| Graphics → MORE | Sky, Terrain close up, Imagery | Atmospheric, Detailed, Survey 2 m / Sentinel-2 | A physical sky, ground detail and photo imagery, if setup converted it |
| Graphics → MORE | Airbases | Detailed | Runways, taxiways and aprons with real markings near the ground |
| Physics | every row | on | Section 10 lists the ones that change how the Lavi flies |
| Gameplay | Easy landing, Easy aiming, No blackouts / spins / stalls | off | Real landing limits, real launch rules, g-effects and stalls |

A greyed-out imagery choice needs its data: convert it with `tools/setup.sh --imagery`.

---

## 3. NAV: reading the HUD

**When**: cruising, navigating to a steerpoint, and between attacks. **Keys**: **N** returns to NAV from any weapon
mode. **W** / **Shift+W** pick the next / previous steerpoint. **H** changes the HUD colour.

![NAV at 10,000 ft and 427 kt, steerpoint 1 ahead](shots/lavi/hud_nav.png)

1. **Airspeed**: calibrated airspeed in knots (KCAS), boxed.
2. **Mach** number.
3. **g** (load factor).
4. **Mode**: `NAV`. With a weapon: `SRM 2`, `MRM 2`, `GUN`, `STRF`, `CCIP`, `TV`, `ARM` (the HARM).
5. **Altitude** above sea level, in feet, boxed.
6. **Steerpoint number**: `WP 1`.
7. **Distance** to the steerpoint in nautical miles (NM).
8. **Time to the steerpoint**, minutes:seconds.
9. **Heading**, boxed under the scale. The scale spans 30°, with labels every 10° (`27` = 270°).
10. **Steering bug** (a V): the steerpoint's bearing. Turn to put it over the centre. When the steerpoint lies outside
    the scale, an arrow at the scale's end points the way to turn, with the bearing beside it.
11. **Flight path marker**: where the jet is going.
12. **Horizon line** of the ladder. The bars every 5° are straight: solid above the horizon, dashed below, with signed
    labels.
13. **Dive bar** label: `-5` = 5° nose-down.
14. **Steerpoint diamond** on the ground, here held at the HUD's edge with an X: it lies ahead and below.

**Example**: the start of mission 231. `WP 1`, `4.7 NM`, `00:35`: steerpoint 1 is 35 s ahead. The bug sits over the
centre of the heading scale, so the steerpoint is straight ahead; its diamond waits at the bottom edge. Lower the
nose until the diamond leaves the edge and fly the marker onto it.

---

## 4. Landing: the gear-down HUD

**When**: on final approach, gear handle down (**G**). **Keys**: **G** gear, **F** flaps, **B** wheel brakes,
**Ctrl+T** calls the tower near an Israeli base.

With the gear down the left column adds the AoA (angle of attack), and the radar altitude `R` shows below 5,000 ft.
The ILS (instrument landing system) lines are the original game's, for every jet.

![Final approach, 3.6 NM out at 687 ft, 141 kt, 5° AoA](shots/lavi/landing_final.png)

1. **Flight path marker**: on the runway threshold here.
2. **ILS glide-slope line**: it crosses the localizer line at the HUD's centre when you are on the runway's centre
   line and on a 5° glide path. It drops when you are high.
3. **ILS localizer line**: held at the HUD's left edge here: the runway's extended centre line lies well to the
   left.
4. **Steering arrow**: steerpoint 1 lies at 254°, outside the scale: turn right.
5. **AoA** in degrees: `AOA 5.0`.
6. **Radar altitude**: 687 ft above the ground.
7. **Steerpoint diamond** held at the edge, with its X.
8. **Airspeed**: 141 kt.
9. **Heading**: 150°.

**Example**: on a 3° path the glide-slope line sits above the HUD's centre: you are under the 5° path the lines
measure. Read the AoA directly: fly the final at the game's landing-lesson 165 kt and watch `AOA` rise as you slow.

### Take-off and landing numbers

| Item | Lavi with Real flight data |
| --- | --- |
| Rotate | 145 kt |
| Gear up below | 300 kt |
| Downwind / final | 200 kt at 2,000 ft above the ground / 165 kt |
| 1 g stall, sea level | 110 kt, the lowest speed flown in the tests |
| Touchdown limits (Real landing limits, Easy landing off) | sink below 4 m/s (790 ft/min), pitch below 15° |
| Nose-wheel steering | rudder pedals, ±32° (the F-16's figure, as a stand-in), 12.66 ft wheelbase |

---

## 5. SRM: AIM-9L, Python 4

**When**: a target inside the missile's launch zone, best from behind. **Keys**: **]** until `SRM`, **Space** to fire.
With a radar lock (**R**, then **Return**) the seeker is slaved to the locked target. In free look (**Shift+arrows**)
or padlock (**F3**) the seeker takes the target you look at, inside the missile's cone.

![A Python 4 locked on a MiG-23 1,500 m ahead](shots/lavi/hud_srm.png)

1. **Missile circle**: 50 mr (milliradian) in radius, round the HUD's centre.
2. **Target box** on the radar target.
3. **Seeker diamond**: on the target while the seeker tracks it.
4. **SHOOT**: the seeker is locked and the range is inside the launch zone.
5. **Mode**: two SRMs left.
6. **Range caret** with the closure in knots (`490>`) on the launch-zone scale; the scale's two ticks are the
   missile's maximum and minimum range.
7. **Scale top**: 10 NM here.

| Missile | Real data |
| --- | --- |
| AIM-9L | 86 kg, Mach 2.5, 35.4 km |
| Python 4 | 120 kg, Mach 3.5, 15 km, 60° off the nose |

**Example**: the MiG is 1,500 m ahead and holds still, so the closure is your own 486 kt (`490>`). Against it the
Python 4's zone runs from 1.08 km to 12.9 km: the caret sits just above the lower tick at the bottom of the 10 NM
scale, the upper tick at 7 NM, and **SHOOT** shows under the mode. Closer than 1.08 km SHOOT goes off. Beyond half
its range the seeker sees a jet with its afterburner lit.

---

## 6. MRM: AMRAAM

**When**: a target beyond the IR missiles' reach. **Keys**: radar on (**R**), lock (**Return** in LRS (long-range
search), or click its blip), **]** until `MRM`, **Space** to fire.

![An AMRAAM locked on a MiG-23 8 NM ahead](shots/lavi/hud_mrm.png)

1. **Target box** on the locked target.
2. **Steering dot**: steer it into the circle.
3. **Launch circle**: it grows as you close from the maximum toward the minimum range.
4. **SHOOT**: the dot is inside the circle and the range is inside the zone.
5. **Mode**: two MRMs left.
6. **Scale top**: 40 NM here.
7. **Maximum range** tick against this target.
8. **Minimum range** tick.
9. **Range caret** with the closure (`490>`).

Real data: the AMRAAM (AIM-120A/B) weighs 157 kg, flies at Mach 4 out to 70 km, and is **active**: it guides itself
after the launch.

**Example**: lock the MiG-23 at 8 NM (14.8 km). Against this still target the zone runs from 2.2 km (1.2 NM, the
lower tick) to 67.3 km (36 NM, the upper tick, near the top of the 40 NM scale). The caret at 8 NM sits low, a little above
the minimum: well inside, so the circle is near its largest. The dot is in the circle and **SHOOT** shows: fire.

---

## 7. A-A gun: LCOS

**When**: a target inside about 3,000 ft. **Keys**: **]** to the gun (`GUN`), **Tab** fires. The real Lavi had a 30 mm
DEFA; the game gives it the 20 mm gun with the game's own round count (its real count is unpublished).

![The gun's LCOS reticle on a MiG-23 at 2,600 ft](shots/lavi/hud_gun.png)

1. **Outer ring** (50 mr across) with tics at each clock hour.
2. **Range arc**: 1,000 ft per clock hour, from 12 o'clock; it shows with a radar lock.
3. **Dashed inner circle**.
4. **Pipper**: the lead-computed aim point. Put it on the target and fire.
5. **Target box** on the radar target.
6. **Mode**: `GUN`.

**Example**: the MiG is 800 m (2,600 ft) ahead with the radar locked. The range arc runs from 12 o'clock to just past
2:30. Hold the pipper on the MiG and fire a 1 s burst.

---

## 8. A-G gun: STRF

**When**: strafing a ground target. **Keys**: **[** to the gun (`STRF`), **Tab** fires.

![STRF in a 20° dive](shots/lavi/hud_strf.png)

1. **Strafe pipper** (a dot in a 12 mr circle): where the rounds hit.
2. **Gun cross**: the gun line, the reference while strafing.
3. **Mode**: `STRF`.
4. **Radar altitude**: 1,969 ft.

**Example**: dive at 20° and 414 kt. With the pipper on the target at 1,969 ft above the ground, fire a short burst
and pull out: the ground comes up at about 240 ft/s.

---

## 9. Bombs, laser and TV weapons, HARM

### Bombs and rockets: CCIP

**When**: MK-82 / MK-83 / MK-84 / M117 and ZUNNI rockets. **Keys**: **[** until `CCIP`; hold **Space** to release.
The stores page sets the ripple quantity and spacing.

![CCIP in a 45° dive at 2,300 ft above the ground](shots/lavi/hud_ccip.png)

1. **CCIP pipper** (continuously computed impact point): a dot in a 16 mr circle where the bomb lands now. A hill
   between you and the impact takes the pipper.
2. **Bomb fall line**: from the flight path marker to the pipper. Keep the target on it.
3. **Flight path marker**.
4. **Mode**: `CCIP`.
5. **Radar altitude**: 2,297 ft.

**Example**: two MK-82s, a 45° dive at 413 kt, 2,297 ft above the ground. Let the fall line carry the target down to
the pipper and press **Space**. **Delayed release**: with the impact below the HUD, hold **Space** with the target
under the pipper at the edge; the bombs go at 0.9 s to go.

### Laser bombs: MK-82L, MK-83L, MK-84L

**Keys**: the FLIR (forward-looking infrared) pod on station 3; **[** to the laser bomb brings up the FLIR page.
**Ctrl+arrows** slew the camera, **Numpad +/−** zoom, **L** the laser, **Space** releases.

![The FLIR page, laser on](shots/lavi/mfd_flir.png)

1. **LASER ON**: the bomb flies to the camera's centre point.
2. **WIDE / SPOT** field of view.
3. **Zoom** (×1 here).
4. **Centre cross**: the laser spot. Release the slew keys and the camera holds this point.
5. **Range** to the point: 3.1 NM.

**Example**: slew the cross onto the target, release the keys, press **L** and release. The bomb steers to the spot
when the spot is on the ground within 60° of its path; with the laser off it falls as a plain bomb (CCIP).

### TV weapons and HARM

- **AGM-65 Maverick, AGM-62, GBU-15, Popeye** (`TV`): **[** to the weapon brings up its TV page and a HUD diamond at
  its aim point. The Maverick homes by itself after **Space**; the others fly where the picture's centre points.
- **AGM-88 HARM** (`ARM`, 360 kg, Mach 2, 150 km): the HARM page lists the radar sites within ±15° of the nose;
  **Ctrl+Return** steps through them; fire with the HUD diamond near the centre.

---

## 10. Flying the Lavi with Real flight data

With Flight data = Real the Lavi row comes from the design figures (Jane's 1987-88), checked by the game's validation
test.

| Item | In the game | Real Lavi (design) |
| --- | --- | --- |
| Empty weight | 15,500 lb | 15,500 lb |
| Internal fuel | 6,000 lb | 3,330 l ≈ 6,000 lb |
| Thrust, military / full afterburner | 13,550 / 20,600 lbf | 13,530–13,550 / 20,585–20,700 lbf (PW1120) |
| 1 g stall speed, sea level | 110 kt | 110 kt |
| g limits | +9 / −3 | +9 (design) |
| Maximum roll rate | 220°/s (0 to 90° in 0.82 s) | unpublished |
| Maximum speed, sea level / 40,000 ft | 769 kt (Mach 1.16) / 1,059 kt (Mach 1.85) | about Mach 1.1–1.2 / Mach 1.85 |
| Climb at 350 kt, sea level, full afterburner | about 37,400 ft/min | over 50,000 ft/min |
| Instantaneous turn, 420 kt at 10,000 ft | 21.7°/s at 8.1 g | 23–24.3°/s at Mach 0.8, 15,000 ft |
| Fuel flow, military / full afterburner | 10,800 / 38,200 lb/h | about 10,800 / 38,200 lb/h |
| Service ceiling | 50,000 ft | 50,000 ft (design) |

What changes in the cockpit:

- **Fuel**: about 9 minutes at full afterburner, about 33 minutes at military power at sea level: longer legs than the
  F-16 on less thrust.
- **Climb**: 37,400 ft/min against the published 50,000+: the thrust and drag fit the published top speeds first.
- **Roll**: 220°/s, slower than the F-16's 280°/s: start rolls a little earlier.
- **Flight-path hold** (Physics): with the stick centred the fly-by-wire jet holds its flight path.
- **Deep stall** (Physics: Realistic spins, F-16 / Lavi deep stall): the Lavi takes the F-16's departure, a stand-in
  from the closest public data. Zoom 30° or more nose-high until the speed is gone and it hangs at about 60° AoA, the
  nose rocking near the horizon. Holding the stick forward keeps it there. **Recovery**: rock the stick in phase
  with the nose (pull while it rises, push while it falls) until the nose falls through, then pull out of the dive.
- **Ground effect** (Physics): a longer float in the flare.

---

## 11. Radar, displays and self-protection

With Weapon data = Real the EL/M-2035 detects at **46 km** in LRS and STT (single-target track); it tracks several
targets at that range. (With the original weapon data the Lavi has the game's longest search table: 90 NM.) The left
display shows it, the right one the RWR (radar warning receiver), the middle one the TSD (tactical map). A selected
weapon's page replaces the right display.

| Key | Action |
| --- | --- |
| **R** / **Q** / **S** | Radar on, A-A (air-to-air) ↔ A-G (air-to-ground) / mode (LRS → TWS → ACM; GMT ↔ MAP) / standby |
| **.** / **,** | Range scale up / down |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace** | Drop the lock |
| **\\** (hold) | Boresight: a ±12° lock cone straight ahead |

- **Chaff (Insert)** and **flares (Delete)**: 120 chaff and 60 flares. A flare fools an IR missile with 33 % (50 %
  above 4 g) while the afterburner is off.
- **ECM (J)** (electronic countermeasures), built in: each radar-guided missile already flying at you is jammed with a
  60 % chance. SAMs (surface-to-air missiles) keep guiding.

---

## 12. Key card

| Key | Action |
| --- | --- |
| 1 … 8 | Throttle: idle, 65, 70, 80, 90 %, military, AB 1, AB 2 |
| Arrows / Numpad 0, Decimal | Stick / rudder |
| G / F / B | Gear / flaps / wheel brakes |
| A / W | Autopilot / next steerpoint |
| M / N | Master mode cycle / NAV |
| ] / [ | Next A-A / A-G weapon |
| Space / Tab | Fire the weapon / the gun |
| Shift+C | Jettison tanks, then bombs |
| R / Q / S | Radar on, A-A ↔ A-G / mode / standby |
| Return / Backspace | Next contact (locks in LRS) / drop the lock |
| Ctrl+arrows / Numpad + − / L | Slew / zoom the TV or FLIR camera / laser |
| Ctrl+Return | HARM: next target |
| T / D / I / Z | TSD / damage / FLIR page / full-screen weapon MFD |
| Insert / Delete / J | Chaff / flare / ECM |
| H | HUD colour |
| Shift+arrows, F3 | Free look, padlock |
| E | Eject |

The **F-35I** (ours) can take the Lavi's place on the Jet list (Extras → F-35I replaces → Lavi): its own guide is
`assets/converted/guides/f35i.pdf`.

---

## 13. Abbreviations

| Term | Meaning |
| --- | --- |
| A-A / A-G | air-to-air / air-to-ground |
| AB | afterburner |
| ACM | air combat mode: the radar's close-range lock mode |
| AMRAAM | advanced medium-range air-to-air missile (AIM-120) |
| AoA | angle of attack (also AOA) |
| CCIP | continuously computed impact point: where the bomb lands now |
| ECM | electronic countermeasures: jamming |
| FLIR | forward-looking infrared: an infrared camera |
| GMT | ground moving target |
| HARM | high-speed anti-radiation missile: it homes on radar emitters |
| HUD | head-up display |
| ILS | instrument landing system |
| IR | infrared (heat-seeking) |
| KCAS | knots calibrated airspeed |
| kt | knots |
| lbf | pound-force (thrust) |
| LCOS | lead-computing optical sight |
| LRS | long-range search |
| MFD | multi-function display |
| mr | milliradian (1 mr spans 1 m at 1 km) |
| MRM / SRM | medium-range (radar) / short-range (IR) missile |
| NAV | navigation mode |
| NM | nautical mile (1,852 m) |
| \[R\] | a reconstruction: the real layout is unpublished |
| RWR | radar warning receiver |
| SAM | surface-to-air missile |
| STRF | strafe: the air-to-ground gun |
| STT | single-target track: a radar lock |
| TSD | tactical situation display: the map |
| TWS | track while scan |
