# Mirage pilot guide (realistic settings)

This guide is for flying the Mirage IIICJ Shahak in this game with every realistic option switched on. The game's
model is the **single-seat Mirage III** (the Reference text: "Dassault Mirage III, single-seat fighter-bomber"), in
IAF camouflage. The Real flight data are the **IIICJ without the SEPR rocket**, as the IAF flew them; most "Mirage
III" tables are the longer, heavier IIIE. The numbers come from the game's own data and tests. Where the game differs
from the real jet, the guide says so.

![The Mirage cockpit on the runway](shots/mirage/cockpit_runway.png)

---

## 1. Settings

Set these on the Preferences screen before the flight. The original 1998 game is the default everywhere, so each of
these has to be switched on.

### Extras tab

| Row                    | Set to                            | What it does                                                                                        |
| ---------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------- |
| Flight data            | Real aircraft                     | The Mirage IIICJ numbers (Atar 09C): weight, fuel, thrust, wing area, stall speed, fuel flow, ceiling |
| Weapon data            | Real weapons                      | Real missile weights, speeds and ranges, the Cyrano radar range (27 km), 2 × 125 DEFA rounds |
| HUD                    | Real                              | The Mirage's CSF 95 gyro gunsight                                                                 |
| HUD pitch ladder       | Conformal                         | The ladder lies on the real horizon (only matters with the original HUD)                            |
| Sky                    | Atmospheric                       | A physical sky with the sun, and haze that takes its colour                                         |
| Terrain close up       | Detailed                          | Ground detail below about 500 m                                                                     |
| Imagery Israel         | Survey 2 m (or Survey 2 m modern) | 2 m photos of Israel, if setup converted them                                                       |
| Imagery outside Israel | Sentinel-2 (or Sentinel-2 modern) | 10 m satellite imagery outside Israel, if setup converted it                                        |

A greyed-out imagery choice means its data was not converted (`tools/setup.sh --imagery`).

### Physics tab

Switch on every row:

| Row                                         | Effect                                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Flight-path hold (neutral stick)            | With the stick centred the jet holds its flight path at every speed                           |
| Forces at current AoA / sideslip            | Lift and drag from the jet's actual angle of attack and sideslip                               |
| Air start without jolt                      | The jet starts an air start level, without a jump                                              |
| Air start with engine spooled up            | The engine starts an air start at the throttle's RPM                                           |
| Air start trimmed                           | The nose holds steady through the first second of an air start                                 |
| Real landing limits (sink, tail strike)     | Touchdown faster than 4 m/s (about 790 ft/min) or a tail strike above 15° nose-up is a crash   |
| Realistic spins                             | More realistic spins                                                                           |
| F-16 / Lavi deep stall                      | No effect on the Mirage (no fly-by-wire)                                          |
| Low-speed lift rate fix                     | Fixes the lift response below about 18 m/s                                                     |
| No reversed roll at low speed               | Fixes the roll reversal at walking speed                                                       |
| No nose-wheel lift quirk                    | Steering on the take-off run keeps the jet on the ground                                       |
| Ground effect                               | Less induced drag near the ground: a longer float in the flare                                 |
| Real idle thrust on the ground (taxi speed) | At idle the jet settles near 30 kt, a taxi speed                                               |
| Falling jets keep their heading             |                                                                                                |
| No tougher enemies on easy AI levels        |                                                                                                |
| Locked enemies know who locked them         | An enemy you lock with the radar knows it was you                                              |
| Stores weight fix                           | Every store counts, in the right units                                                         |
| Bombs burst at the ground                   |                                                                                                |
| No collisions with hidden units / wrecks    |                                                                                                |

### Gameplay tab

| Row                                                      | Set to                                  | Why                                                   |
| -------------------------------------------------------- | --------------------------------------- | ----------------------------------------------------- |
| Easy landing                                             | off                                     | On (the default) doubles every landing limit          |
| Easy aiming                                              | off                                     | On makes any seeker target launchable at full quality |
| No blackouts, No spins, No stalls                        | off                                     |                                                       |
| Invulnerable, No crashes, Unlimited ammo, Unlimited fuel | off                                     |                                                       |
| AI level                                                 | Expert, if you want the hardest enemies |                                                       |

No wind and No malfunctions have no effect: nothing in the original reads them either.

---

## 2. The jet in numbers

With Flight data = Real the Mirage row (docs/real-aircraft.md §7) is checked by the game's validation test. The
original game flew the Mirage with the Kfir's data, a 20,000 lb jet: its weight was the largest single error in the
1998 data.

| Item                                         | In the game                  | Real Mirage IIICJ                          |
| -------------------------------------------- | ---------------------------- | ------------------------------------------ |
| Empty weight                                 | 13,000 lb                    | 12,350–13,450 lb                           |
| Internal fuel                                | 4,800 lb                     | about 4,500–5,100 lb (uncertain)           |
| Thrust, military / full afterburner          | 9,436 / 13,228 lbf           | 9,430–9,440 / 13,240–13,670 lbf (Atar 09C) |
| Wing area                                    | 375 ft²                      | 375 ft²                                    |
| 1 g stall speed, sea level                   | 140 kt                       | approach 170–200 kt ÷ 1.3                  |
| g limits                                     | +7 / −1                      | +7 / about −3 (uncertain)                  |
| Max roll rate                                | 150°/s                       | unpublished; about 150–200°/s               |
| Max speed, sea level                         | 758 kt (Mach 1.15)           | about Mach 1.1–1.14                        |
| Max speed, 40,000 ft                         | 1,134 kt (Mach 1.98)         | Mach 2.1–2.2 at 39,000 ft                  |
| Climb at 350 kt, sea level, full afterburner | about 24,900 ft/min          | 16,400 ft/min (average; understated)       |
| Instantaneous turn, 420 kt at 10,000 ft      | 18.4°/s at 7.0 g             | unpublished                               |
| Fuel flow, military / full afterburner       | 9,500 / 26,900 lb/h          | about 9,500 / 26,900–27,700 lb/h           |
| Service ceiling                              | 55,770 ft                    | 17,000 m (55,770 ft)                       |

What that means in the cockpit:

- **Fuel.** Internal fuel lasts about 11 minutes at full afterburner, or about 30 minutes at military power at sea
  level. The 2,300 lb tank on stations 4, 5 or 6 helps.
- **Fast approach.** The delta wing has no landing flaps: the real jet approaches at **170–200 kt** (Dassault 170,
  pilots about 185). The game's training speeds (rotate **145 kt**, final **165 kt**, the same for every jet) are too
  slow for the Mirage: rotate at about **180 kt** and fly the final at about **185 kt**.
- **Drag chute** (Shift+B): the Mirage has one, but it is visual only (no drag) in the game.
- **Nose-wheel steering** comes from the rudder pedals, ±30° (uncertain), wheelbase 15.96 ft.
- **The engine gauges stay still**: the Mirage's panel has only the speed and fuel needles working; its engine clocks
  are switched off in the original's own cockpit data.

---

## 3. Start-up, take-off and landing

### On the runway

A mission that starts at an airbase puts you on the runway with the gear down, the brakes on and the throttle at idle.
The engine is already running at the lineup point. If you start elsewhere on the base, the first throttle key starts
it, and the RPM then climbs 15 % per second.

### Take-off

1. Release the brakes (**B**).
2. Throttle to full afterburner: **8**. The afterburner lights only after the engine reaches 100 %, about 2 s from
   military power.
3. Keep the runway centreline with the rudder (**Numpad 0** / **Decimal**, or the pedals).
4. At about **180 kt**, pull gently back until the velocity marker is above the horizon.
5. Gear up (**G**). Keep the gear speed below 300 kt.

![Take-off roll](shots/mirage/takeoff_roll.png)

### Landing

1. **Downwind**: 2,000 ft above the ground, **220 kt**, the runway off your wing. Gear down (**G**).
2. **Base**: throttle back, about 20° of bank, slow to about **190 kt**, aim for a 4° approach.
3. **Final**: about **185 kt**. Line up with the runway through the gunsight and watch the airspeed needle on the
   panel.
4. Over the threshold: throttle to idle (**1**) and raise the nose gently. The delta lands nose-high: watch the 15°
   tail-strike limit.
5. After touchdown: brakes (**B**), drag chute (**Shift+B**) if you like the look.

With Real landing limits and Easy landing off, a touchdown faster than **4 m/s (about 790 ft/min)** or more than
**15° nose-up** is a crash.

![Final approach, gear down](shots/mirage/landing_final.png)

### Tower and autopilot

- **Ctrl+T** calls the tower near an Israeli base.
- **A** cycles the autopilot: off → level → NAV (follows the waypoints) → off. **W** / **Shift+W** pick the next /
  previous waypoint.

---

## 4. Handling

- **No fly-by-wire.** Nothing stops you from pulling into a stall: at low speed a hard pull stalls the wing, and with
  Realistic spins on you can spin. Recover with the stick forward and the rudder against the spin.
- **g limit +7 / −1** (the original's; the real negative limit is about −3, uncertain, so it is kept).
- **The stick on the keyboard** is all or nothing; a joystick is much smoother.
- **Flight-path hold.** With the stick centred the jet holds its flight path.
- **g-effects.** With No blackouts off, a hard pull greys and blacks out the screen.

---

## 5. The gunsight (the Real "HUD")

The Shahak's sight is the **CSF 95 gyro gunsight**, a reflector sight. With Real HUD on, the game draws that sight in
its lamp's **orange-red**, from the Mirage IIIO flight manual's CSF 97 drawings, with the 95's aiming reticle (flight
data is on the panel's instruments):

- a **fixed cross** 40 mr wide with an inverted V above it;
- a **moving reticle**: a 2.5 mr pipper dot inside a 50 mr ring of 14 small diamonds, riding the lead-computing (gun)
  or impact (bombs) point.

No airspeed, altitude, heading or text: fly with the panel instruments. Missile lock and in-zone were lights beside
the glass in the real jet, not reticle symbols.

![The CSF 95 gunsight](shots/mirage/sight_nav.png)

---

## 6. Radar (Cyrano I bis)

With Weapon data = Real the radar detects at **27 km** (uncertain: a nominal air-to-air lock range). It has **no
TWS**: LRS, ACM and boresight in A-A, MAP and GMT in A-G. The single display (left) shows it.

| Key                           | Action                                              |
| ----------------------------- | --------------------------------------------------- |
| **R**                         | Radar on: A-A, then toggles A-A ↔ A-G               |
| **Q**                         | Mode: A-A LRS → ACM; A-G GMT ↔ MAP                  |
| **S**                         | Standby                                             |
| **.** / **,**                 | Range scale up / down                               |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| **Backspace**                 | Drop the lock                                       |
| **\\** (hold)                 | Boresight                                           |

![The radar display with a locked contact](shots/mirage/mfd_radar_stt.png)

---

## 7. Display and self-protection

The Mirage has **one display**: it starts on the radar; the RWR and the other pages are reached through its MENU
button. The attitude indicator is the panel's horizon disc. **T** brings up the TSD, **D** the damage report.

- **RWR**: on the display's RWR page (MENU); a new threat sounds a tone, a missile launch at you the launch warning.
- **Chaff (Insert)** and **flares (Delete)**: the Mirage carries **60 chaff and 30 flares**. The decoy rules are every
  jet's: chaff 10 % (30 % above 4 g) against a radar missile, a flare 33 % (50 % above 4 g) against an IR missile,
  never with the afterburner lit.
- **No ECM.**

---

## 8. Weapons

**M** cycles the master mode NAV → A-A → A-G, and **N** returns to NAV. **]** selects the next air-to-air weapon and
**[** the next air-to-ground one. **Space** fires the selected weapon and **Tab** fires the gun.

What the Mirage can load on the Arming screen:

| Store               | Stations      |
| ------------------- | ------------- |
| Shafrir 2, AIM-9D   | 3, 4, 6, 7    |
| MK-82, MK-83        | 3, 4, 5, 6, 7 |
| MK-84               | 4, 6          |
| ZUNNI rockets (×25) | 3, 4, 6, 7    |
| Fuel tank, 2,300 lb | 4, 5, 6       |

### Guns (2 × DEFA)

With Real data: **2 × 125 rounds**, 2 × 1,300 rounds/min, 815 m/s: about 6 s of firing. The IAF fed the sight a fixed
range (600 / 400 / 250 m) because the radar ranging was unreliable; the game's sight is lead-computing.

![The gun: the reticle on the lead](shots/mirage/sight_gun.png)

### IR missiles: Shafrir 2, AIM-9D

| Missile   | Real data                                   |
| --------- | ------------------------------------------- |
| Shafrir 2 | 93 kg, Mach 2.1, 5 km, rear-aspect          |
| AIM-9D    | 88.5 kg, Mach 2.5, 18 km, rear-aspect, 12 g |

1. **]** to the missile: a growl, then a higher tone when the seeker **locks**.
2. These are "limited heat" missiles: the seeker only takes a target within **60° of your heading**. Get behind it.
3. **With a radar lock** the seeker is slaved to the locked target within its 15° cone; without one it looks within
   6° of the nose. The Mirage has no helmet sight: looking aside does not cue the seeker.
4. Beyond **half** its range the seeker sees only a jet **with its afterburner lit**.
5. Fire with **Space** when locked.

![Shafrir 2 with the seeker locked](shots/mirage/sight_srm.png)

### Bombs and rockets

MK-82 / MK-83 / MK-84 and ZUNNI rockets. With the Real sight the moving reticle sits on the predicted impact: dive,
put it on the target and hold **Space** (the ripple releases one store per interval). The ripple is set on the stores
page.

![Bombing: the reticle on the impact](shots/mirage/sight_bomb.png)

### Jettison

**Shift+C**: the first press drops the fuel tanks, the second the bombs.

---

## 9. Views and key card

The views and keys are every jet's (see the F-16 guide's key card): **F1** cockpit ↔ sight only, **Shift+arrows** free
look, **F2** back view, **F3** padlock, **F4**–**F11** the outside views, **Ctrl+F2** cockpit ↔ external.

| Key                        | Action                                                   |
| -------------------------- | -------------------------------------------------------- |
| **1** … **8**              | Throttle: idle … **6** military … **8** full afterburner |
| **G** / **B**              | Gear / brakes                                            |
| **Shift+B**                | Drag chute (visual)                                      |
| **M** / **N**              | Master mode / NAV                                        |
| **]** / **[**              | Next A-A / A-G weapon                                    |
| **Space** / **Tab**        | Fire the weapon / the guns                               |
| **R** / **Q** / **S**      | Radar on, A-A ↔ A-G / mode / standby                     |
| **Return** / **Backspace** | Next contact (lock) / drop the lock                      |
| **Insert** / **Delete**    | Chaff / flare                                            |
| **Shift+C**                | Jettison                                                 |
| **A** / **W**              | Autopilot / next waypoint                                |
| **E**                      | Eject                                                    |
