# Lavi pilot guide (realistic settings)

This guide is for flying the IAI Lavi in this game with every realistic option switched on. The game's model is the
**two-seat Lavi** (two crew under one canopy): the B-3 Technology Demonstrator of the game's Reference text, "of two-seat
configuration". Its Real flight data are the single-seat production design figures (Jane's 1987-88), because the
Lavi never entered service: the prototypes flew only to Mach 1.45 before the programme was cancelled in August 1987.
The numbers come from the game's own data and tests. Where the game differs from the real jet, the guide says so.

![The Lavi cockpit on the runway](shots/lavi/cockpit_runway.png)

---

## 1. Settings

Set these on the Preferences screen before the flight. The original 1998 game is the default everywhere, so each of
these has to be switched on.

### Extras tab

| Row                    | Set to                            | What it does                                                                                        |
| ---------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------- |
| Flight data            | Real aircraft                     | The Lavi design numbers (PW1120, Jane's 1987-88): weight, fuel, thrust, stall speed, fuel flow, ceiling |
| Weapon data            | Real weapons                      | Real missile weights, speeds and ranges, the EL/M-2035 radar range (46 km) |
| HUD                    | Real                              | The F-16's HUD on the Lavi (the Lavi's own symbology is not public: a reconstruction)                         |
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
| F-16 / Lavi deep stall                      | The Lavi can enter the F-16's deep stall (section 4)                                          |
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

## 2. The jet in numbers

With Flight data = Real the Lavi row comes from the design figures (Jane's 1987-88, docs/real-aircraft.md §6),
checked by the game's validation test.

| Item                                         | In the game                     | Real Lavi (design)                         |
| -------------------------------------------- | ------------------------------- | ------------------------------------------ |
| Empty weight                                 | 15,500 lb                       | 15,500 lb                                  |
| Internal fuel                                | 6,000 lb                        | 3,330 l ≈ 6,000 lb                         |
| Thrust, military / full afterburner          | 13,550 / 20,600 lbf             | 13,530–13,550 / 20,585–20,700 lbf (PW1120) |
| 1 g stall speed, sea level                   | 110 kt                          | 110 kt, the lowest speed flown in the tests |
| g limits                                     | +9 / −3                         | +9 (design)                                |
| Max roll rate                                | 220°/s (0 to 90° in 0.82 s)     | not public                                 |
| Max speed, sea level                         | 769 kt (Mach 1.16)              | not public; about Mach 1.1–1.2             |
| Max speed, 40,000 ft                         | 1,059 kt (Mach 1.85)            | Mach 1.85 (1,061 kt at 36,000 ft)          |
| Climb at 350 kt, sea level, full afterburner | about 37,400 ft/min             | over 50,000 ft/min                         |
| Instantaneous turn, 420 kt at 10,000 ft      | 21.7°/s at 8.1 g                | 23–24.3°/s at Mach 0.8, 15,000 ft          |
| Fuel flow, military / full afterburner       | 10,800 / 38,200 lb/h            | about 10,800 / 38,200 lb/h                 |
| Service ceiling                              | 50,000 ft                       | 50,000 ft (design)                         |

What that means in the cockpit:

- **Fuel.** Internal fuel lasts about 9 minutes at full afterburner, or about 33 minutes at military power at sea
  level.
- **Climb.** The game's Lavi climbs slower than the published figure (37,400 against over 50,000 ft/min): the thrust
  and drag are fitted to the published top speeds, which the climb figure does not match.
- **Speeds the game's own training uses** (the training lessons are the same for every jet): rotate at **145 kt**,
  downwind at **200 kt** and 2,000 ft above the ground, base and final at **165 kt**, gear down below **300 kt**. The
  Lavi's flight controls hold it down to about **110 kt**.
- **No drag chute**: the game's Lavi has none.
- **Nose-wheel steering** comes from the rudder pedals. The Lavi's steering angle is not public, so the game uses the
  F-16's ±32°, on the Lavi's 12.66 ft wheelbase.

---

## 3. Start-up, take-off and landing

### On the runway

A mission that starts at an airbase puts you on the runway with the gear down, full flaps, the brakes on and the
throttle at idle. The engine is already running at the lineup point. If you start elsewhere on the base, the first
throttle key starts it, and the RPM then climbs 15 % per second.

### Take-off

This is the procedure from the game's take-off lesson:

1. Check the gear is down and the flaps are out (**F**).
2. Release the brakes (**B**).
3. Throttle to full afterburner: **8** (AB 2). The afterburner lights only after the engine reaches 100 %, about
   2 s from military power.
4. Keep the runway centreline with the rudder (**Numpad 0** / **Decimal**, or the pedals).
5. At **145 kt**, pull gently back until the flight path marker is above the horizon.
6. Gear up (**G**) and flaps up (**F**). Keep the gear speed below 300 kt.

![Take-off roll, HUD gear down](shots/lavi/takeoff_roll.png)

### Landing

This is the circuit from the game's landing lesson:

1. **Downwind**: 2,000 ft above the ground, **200 kt**, the runway off your wing. Gear down (**G**), flaps out (**F**).
2. **Base**: throttle 60–80 % (keys **2** to **4**), about 20° of bank, slow to **165 kt**, aim for a 4° approach.
3. **Final**: **165 kt**. Put the flight path marker on the cross of the ILS lines on the HUD (the localizer and a 4°
   glide slope).
4. Over the threshold: throttle to idle (**1**) and bring the flight path marker slowly up to the horizon.
5. After touchdown: brakes (**B**).

With Real landing limits and Easy landing off, a touchdown faster than **4 m/s (about 790 ft/min)** or more than
**15° nose-up** is a crash.

![Final approach, gear down](shots/lavi/landing_final.png)

### Tower and autopilot

- **Ctrl+T** calls the tower near an Israeli base.
- **A** cycles the autopilot: off → level → NAV (follows the waypoints) → off. **W** / **Shift+W** pick the next /
  previous waypoint.

---

## 4. Handling

- **The stick on the keyboard** is all or nothing: a tap gives full deflection at once, as in the original. A joystick
  is much smoother.
- **Fly-by-wire.** Like the F-16, the Lavi is a fly-by-wire jet: a normal pull does not stall or spin it.
- **Deep stall.** With the "F-16 / Lavi deep stall" switch on, the Lavi gets the F-16's departure: zoom nose-high (30°
  or more) until the speed is gone and it hangs at about 60° angle of attack, nose rocking near the horizon, sinking
  fast. Holding the stick forward does **not** recover it. **Recovery**: rock the stick in phase with the nose (pull
  while it rises, push while it falls) until the nose falls through, then pull out of the dive. The real Lavi's
  departure behaviour is not public: the game borrows the F-16's.
- **Flight-path hold.** With the stick centred the jet holds its flight path.
- **g-effects.** With No blackouts off, a hard pull greys and blacks out the screen.

---

## 5. The Real HUD

The Lavi's real symbology is not public (it had a Hughes wide-angle HUD and Elbit displays), so the Real HUD draws
**the F-16's HUD** on the Lavi: a reconstruction. Everything in the F-16 guide's HUD section applies: the airspeed
and altitude tapes with boxed readouts, the **R** radar-altitude box, the left and right data columns, the heading
scale (bottom in NAV, top in A-G and gear down), the bank scale, the bending pitch ladder with the zenith star and
nadir earth, the `FUEL` / `SHOOT` window and the gear-down AoA bracket. **H** changes the HUD colour.

![The Real HUD in NAV (the F-16 layout)](shots/lavi/hud_nav.png)

Looking aside (**Shift+arrows**, **F3**), the Lavi's helmet sight shows the original game's helmet symbol.

---

## 6. Radar (EL/M-2035)

With Weapon data = Real the radar detects at **46 km** in LRS and STT (the EL/M-2035 tracks several targets at that
range). Without it the Lavi's radar has the game's longest search table: 90 NM in LRS. The left MFD shows it.

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

The radar does not see targets lower than 30 m above the ground or behind terrain. Locking a target tells it you
locked it (and its RWR sounds).

![The radar page with a locked contact](shots/lavi/mfd_radar_stt.png)

---

## 7. MFDs

The Lavi has three displays: the left one starts on the **radar**, the right one on the **RWR**, the middle one on the
**TSD** (tactical map). The attitude indicator is an MFD page too (the MENU page's "adi"). **T** brings up the TSD,
**D** the damage report, **I** the FLIR page (with the pod), **Z** the full-screen weapon MFD, **V** / **PgUp** /
**PgDn** slide the panel.

Picking a weapon brings up its page: the stores page for bombs and rockets, the radar for the radar missiles, the
HARM page for the HARM, the TV page for TV weapons and the FLIR page for laser bombs with the pod. They replace the
right display.

---

## 8. Self-protection

- **RWR**: the right display shows emitters and missiles around you; a new threat sounds a tone, a missile launch at
  you the launch warning.
- **Chaff (Insert)** and **flares (Delete)**: the Lavi carries **120 chaff and 60 flares**. Each press releases one.
  At release, every missile of the decoy's kind launched at you rolls once: chaff fools a radar missile with 10 %
  (30 % above 4 g), a flare an IR missile with 33 % (50 % above 4 g), and **never with the afterburner lit**.
- **ECM (J)**: the Lavi has it built in, like the F-16. Switching it on jams each radar-guided missile already flying
  at you with a 60 % chance. It has no effect on SAMs.

---

## 9. Weapons

**M** cycles the master mode NAV → A-A → A-G, and **N** returns to NAV. **]** selects the next air-to-air weapon and
**[** the next air-to-ground one. **Space** fires the selected weapon and **Tab** fires the gun. Nothing fires with the
gear handle down.

What the Lavi can load on the Arming screen (its own load list; stations 1 and 9 are the wingtips, 5 the centreline):

| Store                                    | Stations                       |
| ---------------------------------------- | ------------------------------ |
| AIM-9L, Python 4                         | 1, 2, 8, 9                     |
| AMRAAM                                   | 2, 3, 7, 8                     |
| MK-82 / MK-83 / M117 (×3), MK-84         | 3, 4, 6, 7 (MK-84 also on 5)   |
| MK-82L laser bomb                        | 2, 3, 4, 6, 7, 8               |
| MK-83L / MK-84L laser bombs              | 3, 4, 6, 7                     |
| ZUNNI rockets (×25)                      | 2, 3, 4, 6, 7, 8               |
| AGM-65 Maverick (×3)                     | 3, 4, 6, 7                     |
| AGM-62, GBU-15 (TV)                      | 3, 4, 6, 7                     |
| Popeye (TV)                              | 4, 6                           |
| AGM-88 HARM                              | 3, 4, 6, 7                     |
| FLIR pod                                 | 3                              |
| Fuel tanks: 2,700 lb / 2,100 lb          | 4, 6 / 5                       |

On the training missions flown from the Jet list the Arming screen shows the Lavi's stations but keeps the mission
jet's allowed counts, as the original does.

### Gun

The real Lavi had a 30 mm DEFA; the game gives it the 20 mm gun. Its real round count is not published, so with Real
weapon data it keeps the game's gun and count.

- **A-A gun** (**]** to the gun): the Real HUD's **EEGS** funnel, with a radar lock the T-symbol, the pipper and the
  range circle.
- **A-G gun** (**[** to the gun): **STRF**, a strafe pipper on the predicted impact.

![The gun: EEGS with a locked target](shots/lavi/hud_eegs.png)

### IR missiles: AIM-9L, Python 4

| Missile  | Real data                                  |
| -------- | ------------------------------------------ |
| AIM-9L   | 86 kg, Mach 2.5, 35.4 km                   |
| Python 4 | 120 kg, Mach 3.5, 15 km, 60° off-boresight |

1. **]** until `SRM`: a growl, then a higher tone when the seeker **locks**.
2. **With a radar lock** the seeker is slaved to the locked target within its cone off the nose.
3. **Off-boresight**: in the free-look view (**Shift+arrows**) or padlock (**F3**), the Lavi's helmet sight lets the
   seeker take the target you look at, within the missile's cone.
4. Beyond **half** its range the seeker sees only a jet **with its afterburner lit**.
5. Fire with **Space** when locked. Locked and in range, the Real HUD shows **SHOOT** in the centre window.

![AIM-9L with the seeker locked](shots/lavi/hud_srm.png)

### Radar missiles: AMRAAM

Real data: 157 kg, Mach 4, 70 km, active: it needs nothing after the launch.

1. Radar on (**R**), lock a target.
2. **]** until `MRM`. The Real HUD shows the **ASEC** circle with its steering dot and the **DLZ** on the right.
3. Inside the DLZ, steer the dot into the circle: **SHOOT** comes up. Fire (**Space**).

![AMRAAM: ASEC and the DLZ](shots/lavi/hud_mrm.png)

### Bombs and rockets: CCIP

MK-82 / MK-83 / MK-84 / M117 and ZUNNI rockets.

1. **[** until `CCIP`. The pipper is where the bomb will hit, joined to the flight path marker by the fall line. A
   hill between you and the impact takes the pipper.
2. Put the pipper on the target and hold **Space**: the ripple releases one store per interval while you hold it.
3. **Delayed release**: with the impact below the HUD, hold **Space** with the target under the pipper at the edge;
   the bombs go when the time-to-go reaches 0.9 s.
4. The ripple quantity and spacing are set on the stores page.

![CCIP with the pipper on a target](shots/lavi/hud_ccip.png)

### Laser bombs: MK-82L, MK-83L, MK-84L

These need the **FLIR pod** on station 3.

1. **[** to the laser bomb: the FLIR page comes up.
2. Slew the FLIR camera with **Ctrl+arrows**; release the keys to lock it on the point in the middle. **Numpad +/−**
   zoom.
3. **L** turns the laser on. The bomb then flies to the FLIR camera's centre point, if that point is within 60° of the
   bomb's line and on the ground. With the laser off it falls like a normal bomb (CCIP).
4. Release with **Space** as for CCIP.

![The FLIR page, laser on](shots/lavi/mfd_flir.png)

### TV weapons: AGM-65 Maverick, AGM-62, GBU-15, Popeye

1. **[** to the TV weapon: the TV page shows the weapon's camera, the HUD a diamond at its aim point.
2. Slew with **Ctrl+arrows**, zoom with **Numpad +/−**, **Z** for full screen.
3. Fire with **Space**. The **Maverick** homes by itself; the **AGM-62, GBU-15 and Popeye** fly where the centre of
   the picture points.

### HARM: AGM-88

Real data: 360 kg, Mach 2, 150 km. **[** to the AGM-88: the HARM page lists the radar sites in a ±15° cone ahead;
**Ctrl+Return** steps to the next one; fire with **Space** when its diamond is near the HUD centre.

### Jettison

**Shift+C**: the first press drops the fuel tanks, the second the bombs.

---

## 10. Views and key card

The views and every key are the F-16's (see the F-16 guide's key card): **F1** cockpit ↔ HUD only, **Shift+arrows**
free look, **F2** back view, **F3** padlock, **F4**–**F11** the outside views, **Ctrl+F2** cockpit ↔ external, **= / −**
zoom.

| Key                        | Action                                                   |
| -------------------------- | -------------------------------------------------------- |
| **1** … **8**              | Throttle: idle … **6** military … **8** full afterburner |
| **G** / **F** / **B**      | Gear / flaps / brakes                                    |
| **M** / **N**              | Master mode / NAV                                        |
| **]** / **[**              | Next A-A / A-G weapon                                    |
| **Space** / **Tab**        | Fire the weapon / the gun                                |
| **R** / **Q** / **S**      | Radar on, A-A ↔ A-G / mode / standby                     |
| **Return** / **Backspace** | Next contact (lock) / drop the lock                      |
| **Ctrl+arrows** / **L**    | Slew the TV / FLIR camera / laser                        |
| **Ctrl+Return**            | HARM: next target                                        |
| **Insert** / **Delete**    | Chaff / flare                                            |
| **J**                      | ECM                                                      |
| **Shift+C**                | Jettison                                                 |
| **A** / **W**              | Autopilot / next waypoint                                |
| **E**                      | Eject                                                    |

The **F-35I** (ours) can take the Lavi's place on the Jet list (Extras → F-35I replaces → Lavi): its own guide is
`assets/converted/guides/f35i.pdf`.
