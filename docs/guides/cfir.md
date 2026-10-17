# Kfir pilot guide (realistic settings)

This guide tells you how to fly the Kfir C7 in this game with every realistic option switched on. The Kfir C7 is the
single-seat delta of the game's model. Its Reference text reads "IAI Kfir … single-seat strike, ground attack and
fighter aircraft", with most C2s "subsequently being upgraded to C7". The numbers come from the game's own data and
tests. Where the game differs from the real jet, the guide says so. Section 11 explains the abbreviations.

![The Kfir cockpit on the runway](shots/cfir/cockpit_runway.png)

---

## 1. Settings

Set these on the Preferences screen before the flight. Every row starts at the original 1998 game's setting, so switch
each one on.

### Extras tab

| Row                    | Set to                            | What it does                                                                                                     |
| ---------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Flight data            | Real aircraft                     | The Kfir C7 (J79-J1E) numbers: weight, fuel, thrust, wing area, stall, g limits, fuel flow, ceiling              |
| Weapon data            | Real weapons                      | Real missile weights, speeds and ranges, the EL/M-2001B radar range, 2 × 140 DEFA rounds at 2 × 1,300 rounds/min |
| HUD                    | Real                              | The Kfir C7's Elbit HUD: its modes from the Elbit System 82, its layout a reconstruction                         |
| HUD pitch ladder       | Conformal                         | The ladder lies on the real horizon (for the original HUD)                                                       |

### Graphics tab → MORE

Press **MORE** on the Graphics page for these rows.

| Row                    | Set to                            | What it does                                                                                                     |
| ---------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Sky                    | Atmospheric                       | A physical sky with the sun, and haze that takes its colour                                                      |
| Terrain close up       | Detailed                          | Ground detail below about 500 m                                                                                  |
| Imagery Israel         | Survey 2 m (or Survey 2 m modern) | 2 m photos of Israel, if setup converted them                                                                    |
| Imagery outside Israel | Sentinel-2 (or Sentinel-2 modern) | 10 m satellite imagery outside Israel, if setup converted it                                                     |

A greyed-out imagery choice needs its data: convert it with `tools/setup.sh --imagery`.

### Physics tab

Switch on every row:

| Row                                         | Effect                                                                                                           |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Flight-path hold (neutral stick)            | With the stick centred the jet holds its flight path at every speed                                              |
| Forces at current AoA / sideslip            | Lift and drag from the jet's actual angle of attack and sideslip                                                 |
| Air start without jolt                      | The jet starts an air start level and smoothly                                                                   |
| Air start with engine spooled up            | The engine starts an air start at the throttle's RPM                                                             |
| Air start trimmed                           | The nose holds steady through the first second of an air start                                                   |
| Real landing limits (sink, tail strike)     | Touchdown faster than 4 m/s (about 790 ft/min) or a tail strike above 15° nose-up is a crash                     |
| Realistic spins                             | More realistic spins                                                                                             |
| F-16 / Lavi deep stall                      | Acts on the fly-by-wire jets; the Kfir has mechanical controls                                                   |
| Low-speed lift rate fix                     | Fixes the lift response below about 18 m/s                                                                       |
| No reversed roll at low speed               | Fixes the roll reversal at walking speed                                                                         |
| No nose-wheel lift quirk                    | Steering on the take-off run keeps the jet on the ground                                                         |
| Ground effect                               | Less induced drag near the ground: a longer float in the flare                                                   |
| Real idle thrust on the ground (taxi speed) | At idle the jet settles near 30 kt, a taxi speed                                                                 |
| Falling jets keep their heading             | A shot-down jet falls along its own heading (the original turns every falling jet to north)                      |
| No tougher enemies on easy AI levels        | Rookie and Normal enemies take full damage (the original makes them tougher)                                     |
| Locked enemies know who locked them         | An enemy you lock with the radar knows it was you                                                                |
| Stores weight fix                           | Every store counts, in the right units                                                                           |
| Bombs burst at the ground                   | A bomb bursts where it meets the terrain, with its full blast (the original can burst it up to 70 m underground) |
| No collisions with hidden units / wrecks    | Hidden units and wrecks whose model has vanished stop being obstacles                                            |

### Gameplay tab

| Row                                                      | Set to                                  | Why                                                    |
| -------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------ |
| Easy landing                                             | off                                     | On (the default) doubles every landing limit           |
| Easy aiming                                              | off                                     | On makes any seeker target launchable at full quality  |
| No blackouts, No spins, No stalls                        | off                                     | Off keeps g-effects, spins and stalls                  |
| Invulnerable, No crashes, Unlimited ammo, Unlimited fuel | off                                     | Off keeps damage, crashes and the ammo and fuel limits |
| AI level                                                 | Expert, if you want the hardest enemies | The level sets the enemies' skill                      |

No wind and No malfunctions are placeholder switches, as in the original.

---

---

## 2. The jet in numbers

With Flight data = Real the Kfir C7 row comes from Jane's and other public figures, checked by the game's validation
test. The original 1998 Kfir weighed 25 % too much and was badly underpowered.

| Item                                   | In the game             | Real Kfir C7                                                       |
| -------------------------------------- | ----------------------- | ------------------------------------------------------------------ |
| Empty weight                           | 16,060 lb               | 16,060 lb (Jane's)                                                 |
| Internal fuel                          | 5,670 lb                | 2,572 kg = 5,670 lb (Jane's); 3,243 l in the game's Reference text |
| Thrust, military / full afterburner    | 11,870 / 17,900 lbf     | 11,870 / 17,900 lbf (J79-J1E; 18,750 "combat plus" left out)       |
| Wing area                              | 375 ft²                 | 375 ft²                                                            |
| 1 g stall speed                        | 127 kt (uncertain)      | approach about 160–175 kt (uncertain)                              |
| g limits                               | +7.5 / −3.5             | +7.5 / −3.5                                                        |
| Max roll rate                          | 150°/s (the original's) | unpublished                                                        |
| Max speed, sea level                   | 771 kt                  | about 750 kt (Mach 1.13)                                           |
| Max speed, 40,000 ft                   | 1,139 kt (Mach 1.99)    | Mach 2.0 sustained, Mach 2.3 dash                                  |
| Climb at 350 kt, sea level             | about 27,900 ft/min     | 45,930 ft/min (peak, light)                                        |
| Fuel flow, military / full afterburner | 9,970 / 35,200 lb/h     | about 9,970 / about 35,200 lb/h                                    |
| Service ceiling                        | 58,000 ft               | above 58,000 ft (17,680 m)                                         |

What that means in the cockpit:

- **Fuel.** At full afterburner the internal fuel lasts about 10 minutes, at military power about 34 minutes. The
  2,550 lb tanks ("2550LB") go on stations 3, 5 and 7. Watch the fuel: the Kfir has the least of all the jets.
- **Drag chute (Shift+B)**: visual only. The Kfir's chute size is unpublished, so the game gives it zero drag.
- **Nose-wheel steering** comes from the rudder pedals, ±30° (uncertain), wheelbase 16 ft (uncertain).

---

## 3. Start-up, take-off and landing

### On the runway

A mission that starts at an airbase puts you on the runway with the gear down, full flaps, the brakes on and the
throttle at idle. The engine is already running at the lineup point. If you start elsewhere on the base, the first
throttle key starts it, and the RPM (engine speed, in %) then climbs 15 % per second.

### Take-off

1. Check the gear is down and the flaps are out (**F**).
2. Release the brakes (**B**).
3. Throttle to full afterburner: **8**. The afterburner lights only after the engine reaches 100 %, about 2 s from
   military power.
4. Keep the runway centreline with the rudder (**Numpad 0** / **Decimal**, or the pedals).
5. At **145 kt** (knots), pull gently back until the flight path is above the horizon.
6. Gear up (**G**) and flaps up (**F**). Keep the gear speed below 300 kt.

### Landing

1. **Downwind**: 2,000 ft above the ground, **200 kt**. Gear down (**G**), flaps out (**F**).
2. **Base**: throttle 60–80 % (keys **2** to **4**), about 20° of bank, slow to **165 kt**, aim for a 4° approach.
3. **Final**: put the flight path marker on the cross of the ILS (instrument landing system) lines on the HUD (the
   localizer and a 4° glide slope).
4. Over the threshold: throttle to idle (**1**) and flare gently.
5. After touchdown: brakes (**B**).

With Real landing limits and Easy landing off, a touchdown faster than **4 m/s (about 790 ft/min)** or more than
**15° nose-up** is a crash. These speeds come from the game's own training lessons, which are the same for every jet.

![Final approach, gear down](shots/cfir/landing_final.png)

### Tower and autopilot

- **Ctrl+T** calls the tower near an Israeli base.
- **A** cycles the autopilot: off → level → NAV (follows the waypoints) → off. **W** / **Shift+W** pick the next /
  previous waypoint.

---

## 4. Handling

- **The stick on the keyboard** is all or nothing: a tap gives full deflection at once, as in the original. A joystick
  is much smoother.
- **Mechanical flight controls.** The stick moves the surfaces directly, so you own the limits: at low speed a hard pull
  stalls the wings, and with Realistic spins on you can spin. Recover with the stick forward and the rudder against the
  spin, then pull out of the dive.
- **Flight-path hold.** With the stick centred the jet holds its flight path.
- **g-effects.** With No blackouts off, a hard pull greys and blacks out the screen.

---

## 5. The Real HUD

The real Kfir C7 has an El-Op HUD driven by the Elbit System 82 weapon delivery system: airspeed, altitude, Mach, AoA
(angle of attack) and armament status, with LCOS (lead-computing optical sight) and hotline gun modes, CCIP
(continuously computed impact point), direct and toss bombing (Flight International 1983). The Real switch draws **the
Kfir's HUD as a reconstruction** in that style, from those sources:

- **Speed and altitude** as numbers: airspeed with Mach under it on the left, altitude on the right.
- **Heading** on a scale along the top, read at the centre caret.
- **Where the next waypoint is**: the **steering bug**, a small triangle under the heading scale at the waypoint's
  bearing. Turn until it sits under the caret. When the waypoint is more than 15° off, the bug waits at that end of the
  scale with an **arrow** pointing the way to turn. Over the ground, the **waypoint marker** (a circle on a post) sits
  on the waypoint itself; when it is outside the HUD it waits at the edge with an X.
- Lower left: **g**, the rounds of the selected store (or AoA with the gear down) and the **mode** (NAV, MSL, LCOS,
  HOTL, STRF, CCIP). Lower right: the waypoint's **distance** in NM (nautical miles, `D`) and its number (`WP`).
- A straight pitch ladder and the flight path marker.

![The Real HUD in NAV: the steering bug on the heading scale points to the waypoint](shots/cfir/hud_nav.png)

---

## 6. Radar (EL/M-2001B)

The real Kfir C7 has an **EL/M-2001B ranging-only radar**. The game still gives it the same radar modes as every jet.
With Weapon data = Real only its detection range changes, to **14.8 km** (uncertain, one database). So expect to find
targets late, and use the radar mainly to lock and range.

| Key                           | Action                                              |
| ----------------------------- | --------------------------------------------------- |
| **R**                         | Radar on: A-A, then toggles A-A ↔ A-G               |
| **Q**                         | Mode: A-A LRS → TWS → ACM; A-G GMT ↔ MAP            |
| **S**                         | Standby                                             |
| **.** / **,**                 | Range scale up / down                               |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| Click a blip                  | Lock that contact                                   |
| **Backspace**                 | Drop the lock                                       |
| **\\** (hold)                 | Boresight: a ±12° lock cone straight ahead          |

The radar sees targets from 30 m above the ground, in line of sight. Locking a target tells it you locked it (and its
RWR (radar warning receiver) sounds).

![The ranging radar with a locked contact](shots/cfir/mfd_radar_stt.png)

---

## 7. Displays

The Kfir has **one display**, which starts on the **radar**. The **RWR** is a separate dial on the panel, and the
attitude ball is on the panel too. **T** brings up the TSD (tactical map), **D** the damage report, **V** / **PgUp** /
**PgDn** slide the panel.

---

## 8. Self-protection

- **RWR**: the panel dial shows emitters and missiles around you; a new threat sounds a tone, a missile launch at you
  the launch warning.
- **Chaff (Insert)** and **flares (Delete)**: the Kfir carries **90 chaff and 60 flares**. Each press releases one. At
  release, every missile of the decoy's kind launched at you rolls once. Chaff fools a radar missile with 10 % (30 %
  above 4 g). A flare fools an IR (infrared) missile with 33 % (50 % above 4 g), **only with the afterburner off**.
- Self-protection is chaff and flares: **J** is the ECM (electronic countermeasures) pod's key on jets that carry one.

---

## 9. Weapons

**M** cycles the master mode NAV → A-A (air-to-air) → A-G (air-to-ground), and **N** returns to NAV. **]** selects the
next air-to-air weapon and **[** the next air-to-ground one. **Space** fires the selected weapon and **Tab** fires the
gun. The weapons are live with the gear handle up.

What the Kfir can load on the Arming screen (seven stations: 2 and 8 under the outer wings, 3 and 7 under the inner
wings, 4, 5, 6 under the fuselage):

| Store                    | Stations                      |
| ------------------------ | ----------------------------- |
| AIM-9D, AIM-9L, Python 3 | 2, 3, 7, 8                    |
| ZUNNI rockets (×25)      | 3, 4, 6, 7                    |
| MK-82                    | 2, 4, 6, 8, and ×6 on 3, 5, 7 |
| MK-82L laser bomb        | 3, 4, 5, 6, 7                 |
| MK-83                    | 5, and ×3 on 3, 7             |
| MK-83L, MK-84            | 3, 5, 7                       |
| CBU-87 / CBU-97 (×6)     | 3, 5, 7                       |
| Fuel tank ("2550LB")     | 3, 5, 7                       |

The Kfir's air-to-air missiles are all IR missiles, and its ground weapons are bombs and rockets. Its **laser bombs fall
like normal, unguided bombs (CCIP)**.

### Gun (2 × DEFA 553)

With Real data: **280 rounds** (2 × 140), 2 × 1,300 rounds/min, 815 m/s: about 6.5 s of firing. The Real HUD has the
Kfir's two gun modes:

- **LCOS** (the radar ranges the target): the lead-computing reticle with its range arc. Put the pipper on the target
  and fire.
- **HOTL**, the hotline (before the radar ranges the target): the bullet stream's path hanging from the gun cross, with
  ticks at 1,000, 2,000 and 3,000 ft. Fly the target onto the line at its range.

![The gun with a locked target: LCOS](shots/cfir/hud_gun.png)

![The gun without a radar range: the hotline](shots/cfir/hud_hotline.png)

### IR missiles: AIM-9D, AIM-9L, Python 3

| Missile  | Real data                                   |
| -------- | ------------------------------------------- |
| AIM-9D   | 88.5 kg, Mach 2.5, 18 km, rear-aspect, 12 g |
| AIM-9L   | 86 kg, Mach 2.5, 35.4 km                    |
| Python 3 | 120 kg, Mach 3.5, 15 km, 30° off-boresight  |

1. **]** until `SRM`: a growl, then a higher tone when the seeker **locks**.
2. **With a radar lock** the seeker is slaved to the locked target within its cone off the nose.
3. Beyond **half** its range the seeker sees only a jet **with its afterburner lit**.
4. On the Real HUD the seeker **diamond spins** while it searches and **holds on the target** once it locks. Fire with
   **Space** when locked: the locked diamond is the Kfir's shoot cue.

The AIM-9D's **rear-aspect** seeker (Real data) locks only on a target moving away from you: get behind it.

![Python 3 with the seeker locked](shots/cfir/hud_srm.png)

### Bombs and rockets: CCIP

MK-82 / MK-83 / MK-84, the CBU-87 / CBU-97 clusters and ZUNNI rockets.

1. **[** until `CCIP`. The pipper is where the bomb will hit, joined to the flight path marker by the fall line; a
   hill between you and the impact takes the pipper.
2. Put the pipper on the target and hold **Space**: the ripple releases one store per interval while you hold it.
3. **Delayed release**: if the impact is below the HUD's bottom edge, hold **Space** with the target under the pipper
   at the edge; the bombs go when the time-to-go reaches 0.9 s (positive g, less than 90° of bank).
4. The ripple quantity and spacing are set on the stores page (default: 2 bombs, 10 m apart).

The game's training warns against GP (general-purpose) bombs below 2,000 ft above the ground. A bomb arms at release:
dropped from any height, it bursts at the ground.

![CCIP with the pipper on a target](shots/cfir/hud_ccip.png)

### Jettison

**Shift+C**: the first press drops the fuel tanks, the second the bombs.

---

## 10. Views and key card

The views and every key are the same as in the F-16 guide: **F1** cockpit ↔ HUD only, **Shift+arrows** free look,
**F2** back view, **F3** padlock, **F4**–**F11** the outside views, **Ctrl+F2** cockpit ↔ external, **= / −** zoom.

| Key                        | Action                                                   |
| -------------------------- | -------------------------------------------------------- |
| **1** … **8**              | Throttle: idle … **6** military … **8** full afterburner |
| **G** / **F** / **B**      | Gear / flaps / brakes (speed brake in the air)           |
| **M** / **N**              | Master mode / NAV                                        |
| **]** / **[**              | Next A-A / A-G weapon                                    |
| **Space** / **Tab**        | Fire the weapon / the gun                                |
| **R** / **Q** / **S**      | Radar on, A-A ↔ A-G / mode / standby                     |
| **Return** / **Backspace** | Next contact (lock) / drop the lock                      |
| **Insert** / **Delete**    | Chaff / flare                                            |
| **Shift+C**                | Jettison                                                 |
| **A** / **W**              | Autopilot / next waypoint                                |
| **E**                      | Eject                                                    |

---

## 11. Abbreviations

| Term | Meaning                                                         |
| ---- | --------------------------------------------------------------- |
| A-A  | air-to-air                                                      |
| A-G  | air-to-ground                                                   |
| ACM  | air combat mode: the radar's close-range lock mode              |
| AoA  | angle of attack (also AOA)                                      |
| CCIP | continuously computed impact point: the bomb's predicted impact |
| ECM  | electronic countermeasures: jamming                             |
| GMT  | ground moving target                                            |
| GP   | general-purpose (bomb)                                          |
| HOTL | hotline                                                         |
| HUD  | head-up display                                                 |
| ILS  | instrument landing system                                       |
| IR   | infrared (heat-seeking)                                         |
| kt   | knots                                                           |
| lbf  | pound-force (thrust)                                            |
| LCOS | lead-computing optical sight                                    |
| LRS  | long-range search                                               |
| NAV  | navigation mode                                                 |
| NM   | nautical mile (1,852 m)                                         |
| RPM  | engine speed, as % of maximum                                   |
| RWR  | radar warning receiver                                          |
| SRM  | short-range missile: the IR missiles                            |
| STRF | strafe: the air-to-ground gun                                   |
| STT  | single-target track: a radar lock                               |
| TSD  | tactical situation display: the map                             |
| TWS  | track while scan                                                |
