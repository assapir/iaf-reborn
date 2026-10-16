# Kfir pilot guide (realistic settings)

This guide is for flying the Kfir C7 (the single-seat delta: the game's model, and its Reference text "IAI Kfir …
single-seat strike, ground attack and fighter aircraft", most C2s "subsequently being upgraded to C7") in this game
with every realistic option switched on. The numbers come from the game's own data and tests. Where the game differs
from the real jet, the guide says so.

![The Kfir cockpit on the runway](shots/cfir/cockpit_runway.png)

---

## 1. Settings

Set these on the Preferences screen before the flight. The original 1998 game is the default everywhere, so each of
these has to be switched on.

### Extras tab

| Row                    | Set to                            | What it does                                                                                        |
| ---------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------- |
| Flight data            | Real aircraft                     | The Kfir C7 (J79-J1E) numbers: weight, fuel, thrust, wing area, stall, g limits, fuel flow, ceiling |
| Weapon data            | Real weapons                      | Real missile weights, speeds and ranges, the EL/M-2001B radar range, 2 × 140 DEFA rounds at 2 × 1,300 rounds/min |
| HUD                    | Real                              | An Elbit HUD; its layout is not public, so ours is an F-16-era reconstruction |
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
| Flight-path hold (neutral stick)            | With the stick centred the jet holds its flight path, instead of slowly climbing at high speed |
| Forces at current AoA / sideslip            | Lift and drag from the real angle of attack, not the commanded one                             |
| Air start without jolt                      | No upward jump at an air start                                                                 |
| Air start with engine spooled up            | The engine starts an air start at the throttle's RPM                                           |
| Air start trimmed                           | The nose does not rise during the first second of an air start                                 |
| Real landing limits (sink, tail strike)     | Touchdown faster than 4 m/s (about 790 ft/min) or a tail strike above 15° nose-up is a crash   |
| Realistic spins                             | More realistic spins                                                                           |
| F-16 / Lavi deep stall                      | No effect on the Kfir (it has no fly-by-wire limiter) |
| Low-speed lift rate fix                     | Fixes the lift response below about 18 m/s                                                     |
| No reversed roll at low speed               | Fixes the roll reversal at walking speed                                                       |
| No nose-wheel lift quirk                    | Steering on the take-off run no longer throws the jet into the air                             |
| Ground effect                               | Less induced drag near the ground: a longer float in the flare                                 |
| Real idle thrust on the ground (taxi speed) | At idle the jet settles near 30 kt instead of accelerating                                     |
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

---

## 2. The jet in numbers

With Flight data = Real the Kfir C7 row comes from Jane's and other public figures, checked by the game's validation
test. The original 1998 Kfir weighed 25 % too much and was badly underpowered.

| Item                                   | In the game                  | Real Kfir C7                                           |
| -------------------------------------- | ---------------------------- | ------------------------------------------------------ |
| Empty weight                           | 16,060 lb                    | 16,060 lb (Jane's)                                     |
| Internal fuel                          | 5,670 lb                     | 2,572 kg = 5,670 lb (Jane's); 3,243 l in the game's Reference text |
| Thrust, military / full afterburner    | 11,870 / 17,900 lbf          | 11,870 / 17,900 lbf (J79-J1E; 18,750 "combat plus" not modelled) |
| Wing area                              | 375 ft²                      | 375 ft²                                                |
| 1 g stall speed                        | 127 kt (uncertain)           | approach about 160–175 kt (uncertain)                  |
| g limits                               | +7.5 / −3.5                  | +7.5 / −3.5                                            |
| Max roll rate                          | 150°/s (the original's)      | not public                                             |
| Max speed, sea level                   | 771 kt                       | about 750 kt (Mach 1.13)                               |
| Max speed, 40,000 ft                   | 1,139 kt (Mach 1.99)         | Mach 2.0 sustained, Mach 2.3 dash                      |
| Climb at 350 kt, sea level             | about 27,900 ft/min          | 45,930 ft/min (peak, light)                            |
| Fuel flow, military / full afterburner | 9,970 / 35,200 lb/h          | about 9,970 / about 35,200 lb/h                        |
| Service ceiling                        | 58,000 ft                    | above 58,000 ft (17,680 m)                             |

What that means in the cockpit:

- **Fuel.** At full afterburner the internal fuel lasts about 10 minutes, at military power about 34 minutes. The
  2,550 lb tanks ("2550LB") go on stations 3, 5 and 7. Watch the fuel: the Kfir has the least of all the jets.
- **Drag chute (Shift+B)**: visual only (no Kfir chute size was found, so it adds no drag).
- **Nose-wheel steering** comes from the rudder pedals, ±30° (uncertain), wheelbase 16 ft (uncertain).

---

## 3. Start-up, take-off and landing

### On the runway

A mission that starts at an airbase puts you on the runway with the gear down, full flaps, the brakes on and the
throttle at idle. The engine is already running at the lineup point. If you start elsewhere on the base, the first
throttle key starts it, and the RPM then climbs 15 % per second.

### Take-off

1. Check the gear is down and the flaps are out (**F**).
2. Release the brakes (**B**).
3. Throttle to full afterburner: **8**. The afterburner lights only after the engine reaches 100 %, about 2 s from
   military power.
4. Keep the runway centreline with the rudder (**Numpad 0** / **Decimal**, or the pedals).
5. At **145 kt**, pull gently back until the flight path is above the horizon.
6. Gear up (**G**) and flaps up (**F**). Keep the gear speed below 300 kt.

### Landing

1. **Downwind**: 2,000 ft above the ground, **200 kt**. Gear down (**G**), flaps out (**F**).
2. **Base**: throttle 60–80 % (keys **2** to **4**), about 20° of bank, slow to **165 kt**, aim for a 4° approach.
3. **Final**: line up with the runway on a 4° glide slope: put the flight path marker on the cross of the ILS lines on the HUD (the localizer and a 4° glide slope).
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
- **No fly-by-wire limiter.** Nothing stops you from pulling into a stall: at low speed a hard pull stalls the wings,
  and with Realistic spins on you can spin. Recover with the stick forward and the rudder against the spin, then pull
  out of the dive.
- **Flight-path hold.** With the stick centred the jet holds its flight path.
- **g-effects.** With No blackouts off, a hard pull greys and blacks out the screen.

---

## 5. The Real HUD

The real Kfir C7 has an El-Op HUD driven by the Elbit System 82 weapon delivery system: airspeed, altitude, Mach, AoA
and armament status, with LCOS and hotline gun modes, CCIP and toss (Flight International 1983). **Its layout is not
public**: the Real switch draws an Elbit / F-16-era reconstruction, the **F-16's HUD**, so everything in the F-16
guide's Real HUD section applies (radar altitude box `R`, bank scale, zenith star and nadir earth, SHOOT in the centre
window, EEGS for the gun, CCIP).

![The Real HUD in NAV (an Elbit / F-16-era reconstruction)](shots/cfir/hud_nav.png)

---

## 6. Radar (EL/M-2001B)

The real Kfir C7 has an **EL/M-2001B ranging radar with no search mode**. The game still gives it the same radar modes
as every jet; with Weapon data = Real only its detection range changes, to **14.8 km** (uncertain, one database). So
expect to find targets late, and use the radar mainly to lock and range.

| Key                           | Action                                              |
| ----------------------------- | --------------------------------------------------- |
| **R**                         | Radar on: A-A, then toggles A-A ↔ A-G               |
| **Q**                         | Mode: A-A LRS → TWS → ACM; A-G GMT ↔ MAP            |
| **S**                         | Standby                                             |
| **.** / **,**                 | Range scale up / down                               |
| **Return** / **Shift+Return** | Next / previous contact (in LRS this locks it: STT) |
| Click a blip                  | Lock that contact                                   |
| **Backspace**                 | Drop the lock                                       |
| **\\** (hold)                | Boresight: a ±12° lock cone straight ahead          |

The radar does not see targets lower than 30 m above the ground or behind terrain. Locking a target tells it you
locked it (and its RWR sounds).

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
- **Chaff (Insert)** and **flares (Delete)**: the Kfir carries **90 chaff and 60 flares**. Each press releases one.
  At release, every missile of the decoy's kind launched at you rolls once: chaff fools a radar missile with 10 %
  (30 % above 4 g), a flare an IR missile with 33 % (50 % above 4 g), and **never with the afterburner lit**.
- **No ECM pod**: the Kfir's store list has none, so **J** does nothing.

---

## 9. Weapons

**M** cycles the master mode NAV → A-A → A-G, and **N** returns to NAV. **]** selects the next air-to-air weapon and
**[** the next air-to-ground one. **Space** fires the selected weapon and **Tab** fires the gun. Nothing fires with the
gear handle down.

What the Kfir can load on the Arming screen (seven stations: 2 and 8 under the outer wings, 3 and 7 under the inner
wings, 4, 5, 6 under the fuselage):

| Store                                | Stations                                   |
| ------------------------------------ | ------------------------------------------ |
| AIM-9D, AIM-9L, Python 3             | 2, 3, 7, 8                                 |
| ZUNNI rockets (×25)                  | 3, 4, 6, 7                                 |
| MK-82                                | 2, 4, 6, 8, and ×6 on 3, 5, 7              |
| MK-82L laser bomb                    | 3, 4, 5, 6, 7                              |
| MK-83                                | 5, and ×3 on 3, 7                          |
| MK-83L, MK-84                        | 3, 5, 7                                    |
| CBU-87 / CBU-97 (×6)                 | 3, 5, 7                                    |
| Fuel tank ("2550LB")                 | 3, 5, 7                                    |

The Kfir has no radar missiles, no FLIR pod and no TV or HARM weapons. Its **laser bombs have no designator**: with
nothing to lase they fall like normal bombs (CCIP).

### Gun (2 × DEFA 553)

With Real data: **280 rounds** (2 × 140), 2 × 1,300 rounds/min, 815 m/s: about 6.5 s of firing. The Real HUD draws the
F-16's **EEGS** for it (the reconstruction; the real Kfir had LCOS and hotline modes).

![The gun with a locked target](shots/cfir/hud_gun.png)

### IR missiles: AIM-9D, AIM-9L, Python 3

| Missile  | Real data                                      |
| -------- | ---------------------------------------------- |
| AIM-9D   | 88.5 kg, Mach 2.5, 18 km, rear-aspect, 12 g    |
| AIM-9L   | 86 kg, Mach 2.5, 35.4 km                       |
| Python 3 | 120 kg, Mach 3.5, 15 km, 30° off-boresight     |

1. **]** until `SRM`: a growl, then a higher tone when the seeker **locks**.
2. **With a radar lock** the seeker is slaved to the locked target within its cone off the nose.
3. Beyond **half** its range the seeker sees only a jet **with its afterburner lit**.
4. Fire with **Space** when locked; locked and in range the Real HUD shows **SHOOT**.

The AIM-9D's **rear-aspect** seeker (Real data) gives no tone on a target coming at you or standing still: get behind it.

![Python 3 with the seeker locked](shots/cfir/hud_srm.png)

### Bombs and rockets: CCIP

MK-82 / MK-83 / MK-84, the CBU-87 / CBU-97 clusters and ZUNNI rockets.

1. **[** until `CCIP`. The pipper is where the bomb will hit, joined to the flight path marker by the fall line; a
   hill between you and the impact takes the pipper.
2. Put the pipper on the target and hold **Space**: the ripple releases one store per interval while you hold it.
3. **Delayed release**: if the impact is below the HUD's bottom edge, hold **Space** with the target under the pipper
   at the edge; the bombs go when the time-to-go reaches 0.9 s (positive g, less than 90° of bank).
4. The ripple quantity and spacing are set on the stores page (default: 2 bombs, 10 m apart).

The game's training warns against GP bombs below 2,000 ft above the ground. There is no fuse or arming time: a bomb
dropped from any height bursts at the ground.

![CCIP with the pipper on a target](shots/cfir/hud_ccip.png)

### Jettison

**Shift+C**: the first press drops the fuel tanks, the second the bombs.

---

## 10. Views and key card

The views and every key are the same as in the F-16 guide: **F1** cockpit ↔ HUD only, **Shift+arrows** free look,
**F2** back view, **F3** padlock, **F4**–**F11** the outside views, **Ctrl+F2** cockpit ↔ external, **= / −** zoom.

| Key                       | Action                                    |
| ------------------------- | ----------------------------------------- |
| **1** … **8**             | Throttle: idle … **6** military … **8** full afterburner |
| **G** / **F** / **B**     | Gear / flaps / brakes (speed brake in the air) |
| **M** / **N**             | Master mode / NAV                         |
| **]** / **[**             | Next A-A / A-G weapon                     |
| **Space** / **Tab**       | Fire the weapon / the gun                 |
| **R** / **Q** / **S**     | Radar on, A-A ↔ A-G / mode / standby      |
| **Return** / **Backspace**| Next contact (lock) / drop the lock       |
| **Insert** / **Delete**   | Chaff / flare                             |
| **Shift+C**               | Jettison                                  |
| **A** / **W**             | Autopilot / next waypoint                 |
| **E**                     | Eject                                     |
