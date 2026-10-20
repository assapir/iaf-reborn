# Mirage pilot guide (realistic settings)

This guide covers what changes in the Mirage IIICJ Shahak when you switch on the realistic options: the real CSF 95
gyro gunsight in place of a HUD (head-up display), the real jet's numbers, the DEFA guns and the rear-aspect
missiles. The game's model is the single-seat Mirage III in IAF (Israeli Air Force) camouflage; the Real flight data
are the IIICJ as the IAF flew it, with the SEPR rocket removed. Each sight mode has its own section: when to use it,
the keys, a picture with numbered callouts, what each mark means, and a worked example. Section 11 explains the
abbreviations.

How to read the pictures: each yellow number points at one mark. The list under the picture explains it.

---

## 1. What's different in this jet

| Area | The 1998 game | With the realistic options |
| --- | --- | --- |
| Sight | The game's common HUD: speed and altitude boxes, a heading tape, text rows | The CSF 95 reflector gunsight in its lamp's orange: a fixed cross, an inverted V, and a moving pipper in a ring of 14 diamonds; flight data stays on the panel |
| Flight data | The Kfir's data: a 20,000 lb jet | Mirage IIICJ (Atar 09C): 13,000 lb empty, 4,800 lb fuel, 375 ft² delta wing, 140 kt stall |
| Approach | The common training speeds (final 165 kt) | The flapless delta's fast approach: final about 185 kt |
| Guns | The game's own gun | 2 × DEFA: 2 × 125 rounds at 2 × 1,300 rounds/min, 815 m/s |
| Missiles | The game's own values | Shafrir 2 (5 km) and AIM-9D (18 km), both rear-aspect: a tone from behind the target |
| Radar | The game's own range | Cyrano I bis, 27 km |
| Physics | The original's quirks | Real touchdown limits, ground effect, realistic spins with mechanical controls |

![The 1998 HUD at the start of mission 231](shots/mirage/hud_original.png)

The same moment with the Real sight is the first picture of section 3.

**HUD warnings.** The Mirage has no Betty voice. The 1998 HUD draws a large X across its centre in the A-G gun and
bomb modes while the dive is steeper than 1° for each 100 ft above the ground (more than 20° at 2,000 ft), and when
the locked target is closer than the selected missile's minimum range (Rmin): then it hides the missile circle. The
Real gunsight has no such mark.

---

## 2. Settings

Set these on the Preferences screen before the flight. Every row starts at the 1998 game's setting.

| Tab | Row | Set to | What it changes |
| --- | --- | --- | --- |
| Extras | Flight data | Real aircraft | The Mirage IIICJ numbers (section 9) |
| Extras | Weapon data | Real weapons | Radar range, gun rounds, missile weights, speeds and ranges |
| Extras | HUD | Real | The CSF 95 gunsight |
| Extras | Better cockpit | Better | The bearing-distance-heading dial turns with the heading and its pointers show the waypoint; the fuel needle counts the tanks, the clock and the vertical-speed dial work (section 3) |
| Graphics → MORE | Sky, Terrain close up, Imagery | Atmospheric, Detailed, Survey 2 m / Sentinel-2 | A physical sky, ground detail and photo imagery, if setup converted it |
| Graphics → MORE | Airbases | Detailed | Runways, taxiways and aprons with real markings near the ground |
| Physics | every row | on | Section 9 lists the ones that change how the Mirage flies |
| Gameplay | Easy landing, Easy aiming, No blackouts / spins / stalls | off | Real landing limits, real launch rules, g-effects and stalls |

A greyed-out imagery choice needs its data: convert it with `tools/setup-cli.sh --imagery`.

---

## 3. The gunsight in flight

**When**: always; the sight is the Mirage's only aiming display. **Keys**: **N** returns to NAV.

The CSF 95 is a reflector sight: its marks are projected on the glass, focused far ahead. The game draws them from the
Mirage IIIO flight manual's CSF 97 drawings, with the 95's aiming reticle.

![The CSF 95 gunsight in level flight](shots/mirage/sight_nav.png)

1. **Pipper**: a 2.5 mr (milliradian) dot. In NAV and with missiles it sits on the gun line; with the gun it rides
   the lead-computed aim point, with bombs the impact point.
2. **Ring of 14 diamonds**, 50 mr across, around the pipper. A fighter's wingspan (about 10 m) fills it at 200 m.
3. **Inverted V**, fixed, 40 mr above the cross.
4. **Fixed cross**, 40 mr wide.

**Example**: in level flight at 10,000 ft the moving reticle sits above the fixed cross: the pipper on the gun line.
Pull and the reticle stays on the gun line; select the gun and it swings to the lead.

### Flying by the panel

Speed, altitude and heading are on the panel: fly with its instruments.

![The instruments you fly by](shots/mirage/panel.png)

1. **Altimeter**.
2. **Airspeed** (true airspeed): the needle makes one turn per 1,000 kt, so each figure on the dial is 100 kt
   (5 = 500 kt). The vertical-speed dial at the panel's upper left stays still in the 1998 game (section 3, Better
   cockpit).
3. **Attitude indicator**: the horizon disc.
4. **Fuel**.
5. **Chaff and flare counters**: `CHF 060`, `FLR 030`.
6. **The display**: radar, RWR and the other pages (MENU).
7. **AI / ML lamps**: an air threat, a missile launch at you.
8. **The gunsight** on the glass.

### The bearing-distance-heading dial

With Extras → Better cockpit on, the dial right of the gunsight turns with the heading and its two pointers show the
route (in the 1998 game it is a still picture). **W** / **Shift+W** pick the next / previous waypoint.

![The bearing-distance-heading dial with Better cockpit on](shots/mirage/compass.png)

1. **Heading**: read on the card at the top of the dial. The numbers are tens of degrees (`33` = 330°).
2. **Bearing arrow** (the double bar): it points at the current waypoint. Turn until it points straight up, and you
   fly to the waypoint.
3. **Course needle** (the single line): the course of the route's leg, from the previous waypoint to the current one.
   On the first leg it lies on the arrow.

**Example**: here the arrow points about 90° right of the nose and the needle about 60° right: the waypoint is off
your right wing. Turn right until the arrow points up. When the arrow and the needle lie on each other you are on the
leg's line.

### Better cockpit: fuel, clock and vertical speed

With Extras → Better cockpit on, three more instruments work (in the 1998 game the clock and the vertical-speed dial
stay still). The display's pages are drawn sharp at the screen's resolution.

![Fuel, clock and vertical speed with Better cockpit on](shots/mirage/better_panel.png)

1. **Fuel needle**: all the fuel you carry, the drop tanks too, over the most the jet holds with them. It falls from
   the first pound burnt (in the 1998 game it stays full until the tanks are empty).
2. **Clock**: the time of day in the mission, hour and minute hands.
3. **Vertical speed**, upper left: level at 9 o'clock; a climb turns the needle clockwise, a descent anticlockwise.
   The marks are 500, 1,000, 2,000, 4,000 and 6,000 ft/min, 6,000 at 3 o'clock.

**Example**: the picture is level flight: the vertical-speed needle points at 9 o'clock. In a climb at 2,000 ft/min
it points at about 12 o'clock.

---

## 4. Guns: 2 × DEFA

**When**: a target inside about 600 m. **Keys**: **]** to the gun, **Tab** fires. With Real data: 2 × 125 rounds at
2 × 1,300 rounds/min, 815 m/s: about 6 s of firing.

![The gun: a MiG-23 600 m ahead](shots/mirage/sight_gun.png)

1. **Pipper**: the lead-computed aim point. Put it on the target and fire.
2. **The target**: a MiG-23.
3. **Ring of diamonds** around the pipper.
4. **Fixed cross**.

**Example**: the MiG is 600 m ahead and closing at 486 kt. It sits above the pipper: the rounds would pass under it.
Pull the nose up until the pipper covers the MiG, then fire a 1 s burst (43 rounds). The IAF fed the real sight a
fixed range (600 / 400 / 250 m) because the radar ranging was unreliable; the game's sight computes the lead.

---

## 5. IR missiles: Shafrir 2, AIM-9D

**When**: behind a target, inside the missile's range. **Keys**: **]** to the missile, **Space** fires. With a radar
lock (**R**, then **Return**) the seeker is slaved to the locked target within its 15° cone; otherwise it looks
within 6° of the nose.

| Missile | Real data |
| --- | --- |
| Shafrir 2 | 93 kg, Mach 2.1, 5 km, rear-aspect |
| AIM-9D | 88.5 kg, Mach 2.5, 18 km, rear-aspect, 12 g |

![A Shafrir 2 on a MiG-23 flying away 2,000 m ahead](shots/mirage/sight_srm.png)

1. **The target**, in the ring.
2. **Ring of diamonds**: with a missile the reticle sits on the gun line, where the seeker looks.
3. **Fixed cross**.

**Example**: the MiG flies away from you 2,000 m ahead, 50 m/s (97 kt) slower than you. Put it in the ring: a growl, then a higher tone
when the seeker locks. Fire. The sight shows the lock by the tone alone (the real jet had lock lights beside the
glass). Both missiles are rear-aspect: the seeker tracks a target flying away from you, and a head-on or a still
target stays silent. They are "limited heat" missiles too: the target has to be within 60° of your heading. Beyond
half its range the seeker sees a jet with its afterburner lit.

---

## 6. Bombs and rockets

**When**: MK-82 / MK-83 / MK-84 and ZUNNI rockets. **Keys**: **[** to the store, hold **Space** to release (the
ripple releases one store per interval; the stores page sets it).

![A 40° dive at 800 m above the ground, two MK-82s](shots/mirage/sight_bomb.png)

1. **Pipper** on the predicted impact: the tank sits under it here.
2. **Ring of diamonds**.
3. **Fixed cross**.
4. **Inverted V**.

**Example**: two MK-82s, a 40° dive at 428 kt (220 m/s), 800 m (2,600 ft) above the ground. Let the target slide up
the glass into the ring, and release when it reaches the pipper. The real sight was set by hand from bombing tables;
the game sets the reticle on the impact point by itself [R: a reconstruction].

---

## 7. Radar: Cyrano I bis

With Weapon data = Real the radar detects at **27 km** (uncertain: a nominal air-to-air lock range). Its modes are LRS
(long-range search), ACM (air combat mode) and boresight in A-A (air-to-air), MAP and GMT (ground moving target) in
A-G (air-to-ground). The single display shows it.

| Key | Action |
| --- | --- |
| **R** / **Q** / **S** | Radar on, A-A ↔ A-G / mode (LRS → ACM; GMT ↔ MAP) / standby |
| **.** / **,** | Range scale up / down |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace** | Drop the lock |
| **\\** (hold) | Boresight |

---

## 8. Self-protection

- **RWR** (radar warning receiver): on the display's RWR page (MENU) and the AI / ML lamps; a new threat sounds a
  tone, a missile launch at you the launch warning.
- **Chaff (Insert)** and **flares (Delete)**: 60 chaff and 30 flares. Chaff fools a radar missile with 10 % (30 %
  above 4 g), a flare an IR (infrared) missile with 33 % (50 % above 4 g) while the afterburner is off.
- Chaff and flares are the Mirage's whole self-protection; the **J** jammer key belongs to jets with a jammer.
- **AWACS calls** (AWACS: the airborne early-warning controller): from 60 s into the flight the controller calls the
  enemy aircraft within 35 NM, one scan every 12 s. "Alpha, bearing 090, 15 miles, target, heading 270, free to
  engage" gives the contact's bearing and distance from you, then the heading it flies; sometimes "targets are already
  engaged" takes the place of "free to engage". "Unidentified contacts, please identify" is a contact your radar has
  not seen yet: find it on the radar before you engage. A contact is called again after 60 s, or at once when it moved
  more than 5 NM; the repeat is short ("bearing 090, 15 miles, target"). The controller is silent while you fly less
  than 50 m (165 ft) above the ground.
- **Flight reports**: the radio also says when a jet of your side is airborne, has landed, crashed or ejected, and
  calls each kill 5 s after it ("Alpha leader shot down MiG 29").

---

## 9. Flying the Mirage with Real flight data

With Flight data = Real the Mirage row (docs/real-aircraft.md §7) is checked by the game's validation test.

| Item | In the game | Real Mirage IIICJ |
| --- | --- | --- |
| Empty weight | 13,000 lb | 12,350–13,450 lb |
| Internal fuel | 4,800 lb | about 4,500–5,100 lb (uncertain) |
| Thrust, military / full afterburner | 9,436 / 13,228 lbf | 9,430–9,440 / 13,240–13,670 lbf (Atar 09C) |
| Wing area | 375 ft² | 375 ft² |
| 1 g stall speed, sea level | 140 kt | approach 170–200 kt ÷ 1.3 |
| g limits | +7 / −1 | +7 / about −3 (uncertain) |
| Maximum roll rate | 150°/s | unpublished; about 150–200°/s |
| Maximum speed, sea level / 40,000 ft | 758 kt (Mach 1.15) / 1,134 kt (Mach 1.98) | about Mach 1.1–1.14 / Mach 2.1–2.2 |
| Climb at 350 kt, sea level, full afterburner | about 24,900 ft/min | 16,400 ft/min (average; understated) |
| Instantaneous turn, 420 kt at 10,000 ft | 18.4°/s at 7.0 g | unpublished |
| Fuel flow, military / full afterburner | 9,500 / 26,900 lb/h | about 9,500 / 26,900–27,700 lb/h |
| Service ceiling | 55,770 ft | 17,000 m (55,770 ft) |

What changes in the cockpit:

- **Fuel**: about 11 minutes at full afterburner, about 30 minutes at military power at sea level. The 2,300 lb tank
  on stations 4, 5 or 6 helps.
- **Mechanical flight controls**: the stick moves the surfaces directly, so you own the limits. At low speed a hard
  pull stalls the wing, and with Realistic spins on the jet can spin: recover with the stick forward and rudder
  against the spin. The F-16 / Lavi deep-stall switch acts on the fly-by-wire jets.
- **g limit +7 / −1**: the original's (the real negative limit, about −3, is uncertain, so the game keeps it).
- **Ground effect** (Physics): a longer float in the flare. **Real idle thrust on the ground**: the jet settles near
  30 kt at idle.
- **The engine gauges stay still**: on the Mirage's panel the speed and fuel needles move, and the original's own
  cockpit data switches the engine clocks off. With Better cockpit (Extras) the fuel needle counts the drop tanks
  (section 3).
- **The map edge**: about 12 km (6.5 NM) before the map's edge the EndWorld warning sounds: turn back. Past it the
  game pushes the jet back for about 8 s: the nose rises and the jet turns back toward the map.

### Take-off and landing numbers

The delta lands flapless and fast: the real jet approaches at 170–200 kt (Dassault 170, pilots about 185).

| Item | Mirage with Real flight data |
| --- | --- |
| Rotate | about 180 kt |
| Gear up below | 300 kt |
| Downwind / base / final | 220 kt at 2,000 ft above the ground / 190 kt / about 185 kt |
| 1 g stall, sea level | 140 kt |
| Touchdown | nose-high; limits (Real landing limits, Easy landing off): sink below 4 m/s (790 ft/min), pitch below 15° |
| Drag chute (**Shift+B**) | drawn, with zero drag |
| Nose-wheel steering | rudder pedals, ±30° (uncertain) |

The sight is the reticle alone, with the ILS (instrument landing system) lines left to the HUD jets: line up with the runway through the glass and fly the
airspeed needle.

---

## 10. Key card

| Key | Action |
| --- | --- |
| 1 … 8 | Throttle: idle, 65, 70, 80, 90 %, military, AB 1, AB 2 |
| 9 / 0 | Throttle − / + 5 % |
| Arrows | Stick |
| Numpad 0 / Decimal | Rudder left / right |
| G / B | Gear / wheel brakes |
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
| F1 / Ctrl+F2 | Cockpit ↔ sight only / cockpit ↔ external |
| SysRQ | Screen capture: a PNG in the `screenshots` folder of the game's user folder |
| E | Eject |
| C / Ctrl+C | Time ×2 ×4 ×1 / normal time |
| Ctrl+P / Ctrl+O / Esc | Pause / in-flight menu / TSD map |
| Alt+E / W / P / T / C / B | Wingman: engage my target / other target, protect me, tactical / close formation, go home |

---

## 11. Abbreviations

| Term | Meaning |
| --- | --- |
| A-A / A-G | air-to-air / air-to-ground |
| AB | afterburner |
| ACM | air combat mode: the radar's close-range lock mode |
| GMT | ground moving target |
| HUD | head-up display |
| IAF | Israeli Air Force |
| ILS | instrument landing system |
| IR | infrared (heat-seeking) |
| kt | knots |
| lbf | pound-force (thrust) |
| LRS | long-range search |
| mr | milliradian (1 mr spans 1 m at 1 km) |
| NAV | navigation mode |
| NM | nautical mile (1.852 km) |
| \[R\] | a reconstruction: the real setting is public in outline |
| RWR | radar warning receiver |
| STT | single-target track: a radar lock |
| TSD | tactical situation display: the map |
