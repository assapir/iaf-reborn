# Real HUD: per-aircraft reference (Extras > HUD)

The Real HUD (head-up display) is an Extras option. It replaces the original 1998 HUD with each jet's real sight / HUD
/ helmet symbology. This file is the reference the code (`crates/iaf-avionics/src/real_hud/`) is built from. For each
aircraft it says what is shown, where, in what format, and how sure we are.

Key facts:
- Researched October 2026 from public sources. The repo keeps no source images.
- Real-world documents describe the F-16, F-15, F-4E, Mirage IIICJ and F-35 displays [V].
- The Lavi, Kurnass 2000, Kfir and MiG-23 layouts and the DASH helmet's layout are public only in outline; ours are
  reconstructions [R]. The MiG-29's comes from simulator manuals (docs/mig-cockpits.md §6).
- [What ours draws (status)](#what-ours-draws-status) lists, per jet, what the code draws and what it leaves out.
- [IFF](#iff-identification-friend-or-foe) says how each real jet shows a friend, with a proposed build.

Confidence tags:
- **[V]** verified: from a real-world document or footage.
- **[S]** secondary: a book, encyclopedia or pilot account that cites real sources.
- **[SIM]** only from a simulator manual: used for detail where the real source agrees in outline.
- **[R]** our reconstruction: nothing is public, so it is inferred from the era / maker and marked as such in
  docs/deviations.md.

Units: 1 mr (milliradian) = 0.0573°. HUD positions are angles from the boresight (the gun cross).

Terms used throughout:
- A-A = air-to-air; A-G = air-to-ground; NAV = the navigation mode.
- FOV = field of view; FPM = flight path marker (the velocity vector); AoA = angle of attack.
- TD box = target designator box (the box drawn on the radar target); DLZ = dynamic launch zone (the missile's
  launch-range scale).
- SRM / MRM = short-range / medium-range missile.
- LCOS = lead-computing optical sight; CCIP = continuously computed impact point.
- MFD = multi-function display; HOTAS = hands on throttle and stick; ILS = instrument landing system; NM = nautical
  miles.

| Jet | Cockpit dir | Real display | Basis |
|---|---|---|---|
| F-16C/D (Barak) | `f16` | F-16 Block 30/40/50 HUD | dash-34 manual [V] |
| Lavi | `lavi` | Hughes wide-angle diffractive HUD, Elbit integrated display system; symbology not public | hardware [S]; layout [R] (a 1980s US / Israeli wide-angle HUD with its own layout) |
| F-15A/C (Baz) | `f15` | F-15A/C HUD (moving tapes, no digital boxes) | TO 1F-15A-1 + NADC 1976 [V] |
| F-4E (Kurnass) | `phantom` | AN/ASG-26 lead-computing optical sight (no HUD) | T.O.-derived [V/SIM] |
| F-4E 2000 (Kurnass 2000) | `f4-2000` | Kaiser / El-Op wide-angle holographic HUD, Elbit ACE-3; symbology not public | [R] its own (MIL-STD-1787 style) |
| Kfir C2/C7 | `cfir` | El-Op HUD with the Elbit System 82 / WDNS-341; layout not public | modes [S], layout [R] |
| Mirage IIICJ (Shahak) | `mirage` | CSF 95 gyro gunsight (reflector, no HUD) | CSF 97K manual drawings [V] + IAF books [S] |
| F-35I (Adir) | `extra/planes/f35i` | Gen III helmet display (no HUD) | Lockheed Martin (LM) slides + flight-test video [V] |
| MiG-23ML | `mig23` | АСП-17МЛ sight: radar / IRST data on the sight, no flight data | outline[^airwar-ml]; layout inferred |
| MiG-29 9.12 | `mig29` | ИЛС-31 HUD (СЕИ-31); Щель-3УМ helmet sight looking aside | simulator manuals built on the real jet[^ea29][^fc3] |
| F-16C/D, F-15C/D helmet (looking aside) | `f16`, `f15` | Elbit DASH III (Display And Sight Helmet) | fielding / optics [S]; symbology from the DASH-derived JHMCS [SIM]; layout [R] |

## F-16C/D (Block 30/40/50)

The Block 50 dash-34 manual documents this HUD in full [V]. The D is the two-seater with the same HUD (a repeater in
the rear cockpit). Barak-specific differences: none public.

Sources:
- T.O. GR1F-16CJ-34-1-1 (Hellenic AF Block 50 dash-34, 1997): HUD chapter pp. 1-158..1-183, A-A pp. 403-423, A-G
  pp. 441-458 (https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf).
- T.O. GR1F-16CJ-1 (dash-1).
- Lockheed MLU (Mid-Life Update) pilot's guides M1-M3 (https://falcon.blu3wolf.com/Docs/MLU_M3.pdf).
- RoKAF AFTTP 3-3 Vol 5 F-16C Basic Employment Manual
  (https://falcon.blu3wolf.com/Docs/Basic-Employment-Manual-F-16C-RoKAF.pdf).
- f-16.net pilot / test-pilot accounts.

**Scales** [V]
- Airspeed: on the left, a moving tape. One tick per 10 kt; labels every 50 kt, in tens (`50` = 500). A fixed index
  carries a boxed readout `[450]` and a caret at the tape. The mnemonic `C` / `T` / `G` sits beside it. The HUD always
  shows CAS (calibrated airspeed) with the gear down or in DGFT (the dogfight mode).
- Altitude: on the right, a moving tape. One tick per 100 ft; labels every 500 ft, in hundreds with a thousands comma
  (`20,5`). Index box `[20,000]` (last digit 0).
  - Gear down: the scale expands ×5 (20 ft ticks).
  - Below it: the radar altitude box `R 19,500` and `AL 200` (ALOW, the low-altitude warning setting).
  - Below 1,200 ft the AUTO scale applies: a 0-1,500 ft thermometer, `AR` on the index; `AL` flashes below ALOW.
  - When the A-A DLZ appears, the altitude scale moves outward.
- Heading: at the **bottom of the HUD in NAV**; gear down it sits 50 mr above the FPM. At the top in the A-G modes,
  except strafe. Ticks every 5°; labels every 10°, in tens (`06 [070] 08`, the current heading boxed).
- Vertical velocity (VV/VAH switch): a fixed scale inboard of the altitude scale with a moving triangle; ticks every
  500 fpm.
- Roll indicator: tics on a 70 mr arc centred 50 mr below the FOV centre, every 10° to ±45°. Ours raises the arc so
  its lowest tic stays inside the cockpit art's glass. That glass is shorter than the real field of view, and the HUD
  is cut at the panel's top edge.

**Ladder / markers** [V]
- Pitch ladder ("attitude bars"): a bar every 5° to ±60°, compressed beyond.
  - Climb bars are solid, dive bars dashed. Tips point toward the horizon; a centre gap leaves room for the FPM;
    numbers at both ends.
  - **Bars bend toward the horizon increasingly with pitch** (test-pilot account + figure). The exact "half the
    angle" rule is MIL-STD-1787 convention [SIM].
- Zenith / nadir: straight up a star (a circle with eight spokes), straight down the earth (a circle with a cross),
  in place of the ±90° bars [R]. This is the MIL-STD-1787 convention; no public F-16 figure shows them.
- FPM: 10 mr circle, 10 mr wings, 5 mr tail; an X over it when limited.
- Gun / boresight cross: an incomplete plus at the fuselage reference line.
- AoA bracket (gear down): the FPM at its top = 11°, centre 13°, bottom 15° (dash-1).
- Steerpoint: a **6 mr diamond drawn on the ground at the steerpoint** (conformal); an X when limited at the FOV
  edge.

**Data windows** (dash-34 fig 1-115) [V]
- Left column, under the airspeed scale: `ARM` / `SIM`; Mach `0.96`; max G `4.1`; the mode / weapon (`NAV`, `6 SRM`,
  `3 MRM`, `EEGS`, `LCOS`, `CCIP`, `DTOS`, `STRF`, ...); fuel / bingo.
- Top left, above the airspeed scale: current G `1.0`.
- Centre: `WARN`, `FUEL` (flashing at bingo). The MLU puts `SHOOT` in the same window.
- Right column, under the altitude scale:
  - `R xx,xxx`; `AL 200`;
  - slant range with a sensor letter: `B115.0` steerpoint, `F02.5` FCR (fire-control radar), `F 060` = 6,000 ft below
    1 NM;
  - time: `MMM:SS` to the steerpoint / release, or closure in the A-A gun mode;
  - steerpoint `distance>number` (`020>03`).

**A-A missiles** [V]
- TD box: 25 mr, segmented when coasting. When the target is off the HUD, a 40 mr locator line from the gun cross
  points to it, with the angle.
- AIM-9 reticle: 3° below the cross; 35 / 65 / 100 mr by seeker mode; a seeker diamond. Under 12,000 ft it shows
  range tics and a range cue at 1,000 ft per clock hour. A target-aspect triangle (6 o'clock = tail).
- AIM-120: the ASEC (allowable steering error circle), a breathing circle of at most 56 mr radius at Rpi, with an 8 mr
  steering dot (the ASC, attack steering cue).
- DLZ: on the right, beside the altitude scale.
  - Top = the radar range (80/40/20/10/5).
  - The target-range caret `>` with the closure at its left (`804>`).
  - The Rmax1 / Rmin1 bracket and the Rmax2 / Rmin2 thick maneuver bar.
  - Below: the `A37` / `T09` times.

**A-A gun** [V]
- EEGS (enhanced envelope gun sight) levels:
  - I: gun cross only.
  - II: funnel + MRGS lines (no lock).
  - III: adds the T-symbol and the TD circle (range).
  - IV: the funnel stiffens and the MRGS lines are removed (velocity).
  - V: adds the pipper (acceleration).
- Funnel: two curved lines. Each line's midpoint is the aim point at that range; the width = the set wingspan at that
  range. Top ≈ 600 ft, bottom ≈ 3,000 ft.
- TD circle: a clock analog, 1,000 ft per hour; it unwinds below 2 NM.
- LCOS (selectable): 1 mr pipper, 8 mr inner circle, 50 mr outer circle, range "L" at 1,000 ft per hour, closure
  caret, lag line.

**A-G** [V]
- CCIP: a 1 mr dot in a 12 mr circle, with a bomb fall line from the FPM. When the impact point is out of the FOV, the
  pipper is held ~14° below the cross with a time-delay cue. After designation: a steering line + a solution cue to
  the FPM.[^dash34ccip]
  - Before designation (fig. 1-283 "PRE DESIGNATE"): the fall line from the FPM to the held pipper, the time delay cue
    a short line across it between the two. The cue's presence means a delayed release; its motion is not stated
    (open).
  - Designating: the pilot holds the weapon release button with the pipper on the target; the computer stores the
    target and computes the azimuth steering error and the time to the release point.
  - After designation (fig. 1-283 "POST DESIGNATE"): a steering line through the target across the whole HUD, its
    offset from the FPM the azimuth error; the solution cue, a short line on its left, drives down toward the FPM as
    the time to go falls, and the release is automatic when it reaches the FPM's centre. The time row shows the time
    to release (`00:06`) in place of the time to the steerpoint. Not explained: the dot-in-circle drawn left of the
    data block, and the `01 0.5` row (open).
  - The pipper and the steering must be on the target at the release; the solution allows full flight-path freedom
    before it.
- DTOS (dive toss): a 10 mr TD box with a pipper; then a steering line and a solution cue; a pull-up "U".
- CCRP (continuously computed release point): TD box, azimuth steering line, solution cue; `B004.9`, the time to
  release.
- Strafe: a CCIP-style pipper; an in-range line 12 mr above it inside 4,000 ft; `STRF`.

## Lavi

The Lavi's HUD hardware is known [S]. Its symbology is not public, so ours is a reconstruction [R].

Sources: Deurenberg, *IAI Lavi* (dror-aero.com, citing Flight International / Jane's) [S]; Wikipedia "IAI Lavi" [S];
for general diffractive-HUD optics, Rochester Avionic Archives "Wide Angle Raster HUD" [S].
- **Hardware** [S]: "a Hughes Aircraft wide-angle diffractive optics head-up display (HUD) surmounting a single El-Op
  up-front control panel".
  - Elbit Computers was prime contractor for the integrated display system: the HUD, three head-down displays (two
    colour, one monochrome), the display computers and the communications controller.
  - The Elbit ACE-4 mission computer; HOTAS; a central stick (not a side-stick).
  - Some sources give Kaiser for the HUD (dokumen.pub *Lavi*).
- **Field of view** [S, general]: a diffractive HUD of that generation gives ~30° × 18°, against ~13° × 9° for a
  refractive one. Green P43 phosphor (matched to the diffractive combiner's narrow band).
- **Symbology: not public.** No photo or video through the Lavi's HUD was found, and no description of its symbology.
  The B-1 / B-2 prototypes flew 1986–87, the TD B-3 (technology demonstrator) from 1989.
- **Ours** [R]: a reconstruction of a late-1980s US / Israeli wide-angle HUD, with MIL-STD-1787 conventions and the
  F/A-18's digital boxes. Its layout is its own, distinct by design from the F-16's dash-34 layout:
  - boxed airspeed (KCAS, knots calibrated airspeed) left and barometric altitude right; under them Mach, G, AoA
    (gear down), the mode / weapon and SHOOT; the radar altitude `R` below 5,000 ft and the steerpoint block (`WP n`,
    distance in NM, time to go);
  - the heading scale on top (30°, labels every 10°) with the boxed heading under it and the **steering bug** at the
    steerpoint's bearing; outside the window the bug is held at the scale's end as an arrow pointing the way to turn,
    with the bearing beside it;
  - straight climb / dive bars every 5° (dive bars dashed, signed labels, no bending, no zenith symbol), the flight
    path marker, the steerpoint diamond on the ground (an X when held at the field's edge);
  - A-A: the SRM circle + seeker diamond; the MRM circle + steering dot + the launch-zone scale; the gun's LCOS
    reticle (no EEGS); the TD box on the target;
  - A-G: the strafe pipper with the gun cross, the CCIP pipper and fall line.

## F-15A/C

The F-15A/C HUD has **no digital speed / altitude boxes**: it shows moving tapes with fixed carets [V].

Sources:
- TO 1F-15A-1 (15 Jan 1984) "Navigation Head-Up Displays" pp. 1-65ff, figs 1-14 / 1-15
  (https://archive.org/details/f-15-manual).
- NADC-75267-40 "Head-Up Display Symbology" 1976 (DTIC ADA022655, https://archive.org/details/DTIC_ADA022655).
- Pilot account (https://www.twz.com/35765/).
- Falcon BMS F-15C -34 [SIM].

Symbology:
- Airspeed: left edge, **increasing downward**. 160 kt window, 10 kt ticks, labels every 50 kt (full value: `250`,
  `300`, `350`); a fixed caret at the midpoint. The tape moves lower with the gear down.
- Altitude: right edge, increasing upward. 1,500 ft window, 100 ft ticks, labels every 500 ft (`3500`); a fixed caret.
  Barometric only (no radar altitude on the HUD). Gear down: 300 ft window, 20 ft ticks.
- Heading: top edge between the scales. 30° window, two-digit labels (`26 27 28`), a caret below pointing up.
- Ladder: 5° rungs to 30° (compressed beyond), no signs. Climb rungs solid, tips down, the number at the tip; dive
  rungs dashed, tips up. Zenith ⊖ "90", nadir ⊗.
- Velocity vector: a circle with wings and fin; it flashes when caged / out of the FOV. The aircraft symbol `-W-`
  sits above it.
- Gun cross `+`: shown only with Master Arm on.
- AoA scale: gear down only; left, 0-45 units.
- G: lower left under the airspeed scale (`1.1G`; with the overload warning system, current and allowed G).
- Mach: under the airspeed scale, in the A-A modes only.
- NAV window: lower right, three lines `B   NAV` / `N 20.1` / `4 MIN` (destination + mode, range with a source letter,
  minutes to go).
- Steering: a bank steering bar. ILS: a flight-director cross.
- A-A [V]: the TD box; the ASE (allowable steering error) circle with a steering dot; a range scale inboard of the
  altitude scale (top = the radar range, a `320>` closure caret, two MAX ticks and one MIN tick, `IN RNG`); the
  breakaway X. SHOOT is a light on the canopy bow, outside the HUD [V].
- Gun: LCOS (no funnel): an outer ring with 12 ticks, a dashed inner circle, a centre pipper and a thick range arc
  [V]; 1,000 ft per tick [SIM].
- A-G: no CCIP. A bomb fall line runs from the velocity vector to a target square, with a pull-up bracket and a
  release cue [V].

## F-4E Kurnass: AN/ASG-26 LCOSS (no HUD)

The Kurnass aims through the AN/ASG-26 LCOSS (lead-computing optical sight system), drawn **red**. Its reticle, like
the Mirage's, is not cut to the original HUD's symbology field: only the panel's top edge cuts it.

Sources: Heatblur DCS F-4E manual (paraphrasing T.O. 1F-4E-1/-34) https://f4.manuals.heatblur.se/systems/weapon_systems/lcoss.html
and the BIT procedure; Joe Baugher; flyandwire.com.
- Reticle [V]: a 2 mr pipper dot; a 25 mr dashed inner ring; a 50 mr solid outer ring; three roll tabs on the outer
  ring (bank, or WRCS (weapon release computer system) steering).
- Range bar [V]: inside the outer ring, from 6 o'clock counter-clockwise, **with a radar lock only**.
  - Guns: 1,000 ft at 6 o'clock + 1,000 ft per hour (max 6,667 ft).
  - Missiles: 3,000 ft per hour (max 20,000 ft).
- A/A: gyro lead with the radar range (default 1,000 ft). Missiles: the reticle at the RBL (radar boresight line,
  35 mr) for a boresight lock.
- A/G: manual depression 0-245 mr (35 mr = the gun cross); no CCIP [V].
- The sight shows **no airspeed, altitude, heading or text** [V]. Missile status / IN RANGE / SHOOT are lights.

## F-4E 2000 (Kurnass 2000)

The upgrade's HUD hardware is known [S]; its symbology is not public, so ours is a reconstruction [R].

Sources: Joe Baugher, airvectors, warmachinesdrawn; GlobalSecurity "Kurnass 2000".
- **The upgrade** [S]: by IAI; the PW1120 test aircraft first flew 1986-87, in service from 1989. It brought a Kaiser /
  El-Op wide-angle (holographic) HUD, an Elbit ACE-3 mission computer, a display computer for the new MFDs, a HUD
  video camera and HOTAS.
- **The HUD** [S]: said to show speed, altitude, the direction of flight and the wind. GlobalSecurity claims a field
  of view of "60 % of the pilot's forward view, twice other systems" [S, unconfirmed]. The same El-Op wide-angle HUD
  family went into the Turkish F-4E-2020 (El-Op 976) [S].
- **No symbology figure, photo through the HUD or manual is public.** Searched: Flight International, IAF / IAI /
  Elbit material, CombatACE, War Thunder / DCS communities.

Ours (`real_hud/k2000.rs`) is therefore a reconstruction [R] in the MIL-STD-1787 manner of an Elbit-generated HUD of
the late 1980s. Its layout is its own, distinct by design from the F-16's dash-34 layout:
- Airspeed and altitude: **boxed digital readouts** on the field's edges (no tapes) [R]. The radar altitude `R…`
  under the altitude below 5,000 ft [R].
- Left column: g, Mach, the master mode (`NAV`, `SRM`, `MRM`, `GUN`, `STRF`, `CCIP`, `LGB`, `TV`, `HARM`); gear down
  `AOA…` [R]. Right column: `WP<n> <NM>`, the time to the waypoint, the target's range in A-A [R].
- Heading scale on top: a 30° window with the heading boxed under its centre, and a **filled steering caret** above
  it at the waypoint's bearing. Outside the window the caret is held at the scale's end with the angle still to turn
  [R].
- Flight path marker; a straight-rung pitch ladder (climb solid, dive dashed, signed labels at both ends, no bending,
  no zenith / nadir symbols) [R]; the waypoint's diamond on the ground (an X when limited) outside the A-A modes [R].
- A-A [R]:
  - the target box;
  - SRM: the missile circle with the seeker diamond;
  - MRM: the circle (sized by the launch zone) with the steering dot and the launch-range scale (Rmax / Rmin, range
    caret, closure) inboard of the altitude box;
  - gun: an **LCOS** ring with the pipper dot and a range arc (12,000 ft a turn).
- A-G: the CCIP pipper (a dot in a ring) with the fall line from the marker; strafe: the pipper [R].
- `SHOOT` (or `FUEL` below the bingo) at the bottom centre [R]. No wind readout (the game has no wind on the HUD).

## Kfir C2/C7

The Kfir's HUD modes and shown data are known [S]; its layout is not public, so ours is a reconstruction [R].

Sources:
- Flight International 27 Aug 1983 p. 542 (Elbit System 82 WDNS, weapon delivery and navigation system) [V].
- Jane's: the C7 from mid-1983 has a HOTAS cockpit and the WDNS-341 with the Elbit System 82 stores management /
  release computer [S].
- The System 82 document as quoted in War Thunder research threads (modes), and Colombian Air Force Kfir C7 HUD
  footage (CACOM-1 / Python 3 launch) as described there [S].
- militaryfactory / milavia [S].

What is known:
- **Modes** [S]:
  - A-A gun: **LCOS** and **HOTLINE** (also listed: SNAP / SHOOT, unconfirmed).
  - A-G: **DIR** (direct / manual), **CCIP**, **TOSS** / DTOSS.
  - Waypoint navigation and toss with the Doppler fitted.
  - TV weapons are run from the head-down CRT (cathode-ray tube display), outside the HUD [S].
- **Data shown** [S]: airspeed, altitude, Mach, AoA, armament status. The footage shows a pitch ladder (horizon).
- **Missile cue** [S]: the Python 3 launch footage shows a diamond that spins until it locks, then stays on the
  target.
- **Gun** [S]: the footage shows the gun's lead indicator (a pipper moving with the lead) and, with the EL/M-2001B
  ranging radar, the radar gun lead on the target.

**Layout not public** [R]. Ours (`real_hud/kfir.rs`) is an Elbit early-80s reconstruction:
- Airspeed and Mach as numbers on the left, altitude on the right (no tapes).
- A 30° heading scale on top with the centre caret. Under it the **steering bug** (a triangle) at the waypoint's
  bearing; outside the scale it is held at the scale's end with an arrow pointing the way.
- The waypoint marker on the ground: a circle on a post, an X when held at the field's edge.
- A straight, conformal ladder (no bent bars, no zenith symbol); the flight path marker.
- Lower left: g, AoA (gear down), the rounds of the selected store and the mode (NAV / MSL / LCOS / HOTL / STRF /
  CCIP / TV / ARM). Lower right: the `D` distance (NM) and the `WP` number.
- The gun cross when armed; the radar ranging box on the target.
- Gun: the LCOS reticle with the range arc (the F-15's) once the radar ranges. Otherwise the **hotline**: the bullet
  stream's path from the gun cross, with ticks at 1,000 / 2,000 / 3,000 ft.
- Missiles: the spinning seeker diamond, held on what it tracks.
- A-G: the strafe / CCIP pipper; the CCIP fall line from the marker.
- Not drawn (not public): a shoot cue, toss / DIR cues, the Doppler drift readout.

## Mirage IIICJ Shahak: CSF 95 gyro sight (no HUD)

The Shahak aims through a CSF 95 gyro gunsight. The CSF 97K's dimensioned drawings give the reticle [V].

Sources: RAAF Mirage IIIO/IIID Flight Manual AAP 7213.003-1 (1978) pp. 1-109..1-121 (CSF 97K, dimensioned drawings)
[V]; Aloni, *Mirage III vs MiG-21* and *Israeli Mirage III and Nesher Aces* (Osprey) via Hebrew Wikipedia [S]. The
Shahak's CSF 95 lacks the 97's gyro horizon / heading [S].
- Moving reticle: a 2.5 mr pipper dot inside a fixed 50 mr ring of 14 small diamonds. It moves up to 9° from the
  fixed cross [V].
- Fixed cross: 40 mr wide (vertical stub 10 mr up / down), with an inverted V 40 mr above it [V].
- Guns: lead-computing. The IAF fed in a pilot-selected range of 600 / 400 / 250 m, as radar ranging was unreliable
  [S].
- Missiles: lock / in-zone lights in a column right of the glass (blue = lock) [S]. The reticle has no missile
  symbols.
- Colour: drawn as a lamp reflector sight, orange-red [R, period practice].

## F-35I Adir: Gen III helmet display (no HUD)

The F-35I shows its flight data in the Gen III helmet display: green, 40° × 30°. The symbols the game adds over it
(the ILS lines, the weapon symbols, the radar's BORE cross) are green too; so are they over the DASH (`hud.gd _hc`). Looking forward, it shows an
aircraft-stabilised "virtual HUD" [V].

Sources: Lockheed Martin "The F-35 Cockpit" slides (c. 2012; https://www.f-16.net/forum/viewtopic.php?t=16223&start=180);
US Navy flight-test helmet video (https://www.twz.com/12297/); Collins datasheet; Aviation Today 2010 / 2015.

The forward virtual HUD:
- Heading tape at the top, the boxed heading `[092]`, a caret (see Navigation below).
- Airspeed: a **boxed number only**, left (`[382]`), no tape. Under it `GS 515`, `M 0.84`, `G 1.0`, `α 1.6` and a
  bare number (max G, inferred).
- Altitude: a boxed number, right (`[19 067]`, the last three digits small). Under it the vertical velocity `-1125`
  and the radar altitude `R15060`.
- The `-W-` waterline; the horizon with a centre gap; the ladder (climb solid, tips down; dive dashed, tips up; `-5`,
  `-10` numbered at the left); the FPM with an energy caret.
- Bank scale at the bottom.
- Lower left: the master mode `AA1`, the weapon `2 AIM-A`, `ARM`.
- Lower right: TACAN (tactical air navigation) `82X 11.8`; the steerpoint `001 110/22.0` (number, bearing / range);
  the time `00:02:33`.
- A-A: the target designator (an X over a circle); a steering circle with a dot; a DLZ bracket with the range `27.4`
  under it; closure `495>`. The designation cue is held at the FOV edge.
- Gun (A-A funnel and pipper, A-G strafe) and A-G cues: they exist, but the graphics are not public [R].

Off-boresight: the virtual HUD stays with the airframe. The helmet shows a reduced head-stabilised set: bare airspeed
/ altitude, heading, steerpoint, targets [V].

Navigation (researched October 2026). No public source names the helmet's navigation symbols or says how they behave.
The F-35 flight manual and the Collins symbology are not public; Collins, Elbit, Code One and the Aviation Today
articles describe the helmet only in general terms. The two LM frames are the only primary evidence. Ours reads them as
follows:
- **Steering caret** `^` on the heading tape [V, our reading]. The forward frame (heading 092°, steerpoint `001
  110/22.0`) shows a `^` just past the tape's last tic on the right, the side of the steerpoint. The "Looking Behind"
  frame shows a `^` under the head's heading tape too. Ours: the caret sits under the tics at the steerpoint's bearing
  and is held at the tape's end (±17°) when the bearing is off the tape [R, the limit].
- **Steerpoint square** on the ground [V, our reading]. The forward frame shows a small square far right, about 16°
  right and 6° below the horizon (scaled from the ladder: 5° = 210 px). The steerpoint 22 NM away at 110° from
  19,067 ft lies 18° right and 8° below, so the square is most likely the steerpoint. Ours draws it in every master
  mode, ground-stabilised at the steerpoint's projection.
- Off the field: the square is held at the field's edge on the line from the boresight, as the slide says for the
  target designator [R]. Behind the view, only the caret shows [R].
- Looking aside: the head set keeps the caret on its own heading tape [V, the "Looking Behind" frame]; it draws no
  square [R: no frame shows one].
- No steering line, no distance or time beside the square [R: none is visible in either frame]. The readouts stay in
  the steerpoint block (`001 110/22.0` and the time).

## MiG-23ML: АСП-17МЛ sight (no HUD flight data)

The research, with its sources, is docs/mig-cockpits.md §5. The ML has no radar scope: the radar's target, the IRST
data and the gun reticle show on the АСП-17МЛ sight[^airwar-ml]. No source shows a ladder, tapes or flight numbers on
it (inferred), and the reticle's drawing is not public. Ours (`real_hud/mig23.rs`) is a reconstruction:
- **Every mode but the gun:** a fixed cross at the gun cross. No numbers, no ladder, no heading.
- **NAV:** a small steering ring on the waypoint, an X when it is held at the field's edge. With the gear down, «К»
  (course) and «Г» (glide) label the ILS bars the HUD draws[^n003e].
- **A-A missiles:** the target diamond, held at the sight's designation limits (±12° in azimuth, +16 / −18°
  vertically[^airwar-ml]) and at the field's edge; «НОП» (aiming error too large) while it is held at the limits
  (inferred mapping). The range scale on the right in km: 3 / 5 / 10 / 20 / 45 km (3–20 km uncertain, 45 km
  inferred), with Rmax / Rmin and the target's caret and range. «ПР» (launch authorised) with the shoot cue. The IR
  missile's seeker as a small circle.
- **A-A gun:** a ring and pipper on the game's lead point; with a lock the range bar on the ring (a full turn =
  2,000 m, inferred).
- **A-G:** the CCIP / strafe pipper, the fall line from the fixed cross.
- **Colour:** the HUD's (the real one is open). The game's helmet display stays the original's (the ML has no helmet
  sight: inferred).
- **Not drawn:** the radar / IRST mode names (БСВ, Т-I…), the «Лазурь» datalink commands, a close-combat scan.

## MiG-29 9.12: ИЛС-31 HUD and Щель-3УМ helmet sight

The research, with its sources, is docs/mig-cockpits.md §6. The layout follows the simulator manuals built from the
real jet[^ea29][^fc3]. Ours (`real_hud/mig29.rs`):
- **Every mode:** indicated airspeed in km/h upper left; the height in m upper right: the radar height to 1 m below
  1,000 m, else the barometric height to 10 m. The heading tape on top in tens of degrees (the Kfir's tape). The
  pitch scale on the right (5° ticks, labels every 10°, a fixed caret); the horizon line; the bank scale at the
  bottom (ticks at 0, ±15, ±30, ±45°: inferred spacing); the fixed aircraft cross at the boresight.
- **Mode name, lower left:** МРШ (route), ПОС (landing: the gear down), ДВБ (long-range combat: the MRM), ТП / БВБ
  / Ф0 (the IR missile: the seeker, the radar's ACM, the radar's BORE), ОПТ ЗЕМЛЯ (A-G).
- **NAV:** the steering circle, moved sideways by the bearing to the waypoint (held inside the field); the
  waypoint's range in km at the bottom centre.
- **A-A:** the target diamond (an X when held at the field's edge); the range scale on the left in km, 10 / 25 / 50 /
  100 km (inferred from the manual's nautical-mile steps), with Rmax / Rmin and the target's caret and range;
  «ПР» with the shoot cue, «ОТВ» (break away) inside Rmin; the MRM's steering circle; the IR seeker's lock strobe.
- **Close combat:** the radar's ACM draws the vertical scan (two lines from 10° below to 50° above the boresight)
  with «РЛ»; the radar's BORE draws the 2.5° circle round the BORE cross (Ф0).
- **Gun:** with a lock, the ring and cross on the game's lead point with the range bar (a full turn = 1,200 m,
  inferred); without one, the funnel for the GSh-30-1's 860 m/s muzzle speed[^gsh30].
- **A-G:** the impact pipper and its fall line from the aircraft cross.
- **Looking aside:** the Щель-3УМ helmet sight: the DASH's aiming cross on the line of sight, «ШЛЕМ», a flashing
  «ПР» with the shoot cue, an X outside the seeker's limits (±60° in azimuth, +60 / −14°), the IR seeker's diamond.
- **Colour:** the HUD's (the real one is open).
- **Not drawn (no game value):** the commanded speed and height, the acceleration triangle, Rtr, «Г» (zoom climb),
  ВЗВ (return), ОПТ (A-A optical aiming), the A-G range scale and its «ОТВ», the toss mode, the datalink commands,
  the rounds left.

**Text:** the legends are Cyrillic. The HUD font (`Img.arial()`: Arial, else Liberation Sans) has the glyphs, and
Godot's system font fallback covers any font without them; `tests/godot/test_real_hud.gd` checks every legend's
letters.

## DASH helmet (F-16D, F-15C)

The Elbit **DASH** (Display And Sight Helmet) puts flight and weapon data on the visor and aims by the pilot's look.
No DASH symbology figure is public. The content below follows the published outline and the JHMCS (Joint
Helmet-Mounted Cueing System, its descendant), whose F-16 set is documented in simulator manuals [SIM].
- **History**:
  - An IAF requirement for the F-15 and F-16 from the mid-1980s. GEN I was in production c. 1986; **GEN III**
    (early–mid 1990s) is on the IAF F-15C/D, F-16C/D and F-15I [S, ausairpower].
  - Fielded in 1993–94 for off-axis targeting of the Rafael **Python 4** [S, Avionics Handbook ch. 5].
  - Elbit's fixed-wing HMD (helmet-mounted display) is the basis of the US **JHMCS**, built by Vision Systems
    International (VSI), Elbit's joint venture with Kaiser, later Rockwell Collins [S, Elbit / VSI releases].
- **Display**: monocular, **20° circular** field of view, 15 mm exit pupil, collimated on the visor; calligraphic
  (stroke) symbology in **green** phosphor [S]. Head tracking is electromagnetic; the line of sight goes to the
  mission computer (MIL-STD-1553B) [S].
- **Use**: aim by looking. The measured line of sight slaves the radar and the missile seeker to the target [S,
  Elbit]. A boxed target cues the Python 4's seeker, and a **diamond** shows the seeker tracking it [S, ausairpower].
  The seeker follows the pilot's line of sight off boresight [S, TWZ / GlobalSecurity]. Its limits are the missile's
  and unpublished; ours keeps the game's cones (docs/weapons.md §5.4).
- **Content** [S]: flight and weapon data on the visor (airspeed, altitude, weapons status, aiming), so the pilot
  reads them without looking at the HUD. The JHMCS adds compass heading, an artificial horizon, "look-to" and shoot
  cues [S, Avionics Handbook].
- **Layout** (the JHMCS F-16 basic / A-A set [SIM, the DCS F-16C guide], kept for the DASH [R]):
  - the **aiming cross**, fixed at the field's centre (the helmet line of sight);
  - a **line-of-sight indicator**: a circle whose gap points where the head looks relative to the nose (a gap at
    11 o'clock = looking left and up);
  - on the left, G above the **airspeed**, with the **master arm / mode** under it;
  - on the right, the **barometric altitude**, with the range / steerpoint under it;
  - the helmet's **magnetic heading** at the bottom;
  - the radar target's **TD box** where it is in the field; the IR seeker's diamond;
  - HUD and cockpit **blanking**: the symbols blank while the head looks through the HUD or down into the cockpit
    [SIM].
- Not public: the DASH's own fonts / positions, its horizon symbol, Python-specific cues and shoot cue, declutter
  levels. Ours leaves them out [R].

## IFF (identification friend or foe)

This section says how each real jet tells the pilot that an aircraft is a friend. It was researched in October 2026
from public sources. It is the reference for a future Real-mode IFF. Today the Real HUD draws no friend mark: the
original's friendly X on the target box is part of the original HUD, which Real mode hides (docs/radar.md §6).

Terms:
- **Transponder**: the set that answers interrogations (every jet here has one).
- **Interrogator** (AAI, air-to-air interrogator): the set that sends the challenge. Only some jets carry one.
- **Reply symbol**: the mark the interrogator's answers make on a display.
- FCR = fire-control radar display; VSD = vertical situation display (the F-15's radar display); HSD = horizontal
  situation display; PCD = panoramic cockpit display (the F-35's head-down screen); WSO = weapon systems officer
  (the F-4E's back seat).

Key facts:
- In every real document found, the interrogator's reply is a **symbol on the radar display**, drawn at the reply's
  own range and bearing. It is not tied to the radar track. The pilot matches the two by eye [V, F-16 MLU M3].
- No real or simulator document shows an IFF reply **on a HUD** or **on a helmet**.
- Each interrogation is **started by the aircrew** with a momentary switch. No source gives a continuous, automatic
  interrogation for the 1980s–90s jets.
- How long a reply stays on the display is in no real document. One simulator guide gives 3 s [SIM].
- The F-35 is different: its mission systems fuse every sensor into tracks, and each track carries an identity
  colour and shape on the head-down display [S].

### Per jet

| Jet (game period) | Interrogator | Control | Where the answer shows | Symbol | Time shown | Confidence |
|---|---|---|---|---|---|---|
| F-16C/D Block 30/40 (Barak, 1987–91) | none: the AN/APX-101 is a transponder only | — | — | — | — | [S] |
| F-16 with AIFF (MLU 1998, USAF CCIP 2000s; later than the game) | AN/APX-113 | TMS (target management switch) left: under 0.5 s a SCAN interrogation, 0.5 s or more a line-of-sight (LOS) one | FCR A-A page; HSD on selection | green circle = friend, yellow square = unknown, nothing = no reply | not stated ([SIM]: 3 s) | [V] |
| DASH helmet (F-16, F-15) | — | — | nothing public | nothing public | — | — |
| F-15A/C (Baz) | AN/APX-76 | IFF interrogate button on the throttle; with MSIP grips, the coolie switch left; held for contact | VSD, at the reply's range and azimuth | circle = high confidence, diamond = low confidence, nothing = no reply | not stated | control [V]; display [SIM] |
| F-4E (Kurnass) | AN/APX-81, AN/APX-80 after TO 1F-4E-587 | the WSO's interrogator push button | the WSO's radar scope | lines at the contact: one above = matching mode, one below = matching code | not stated | sets [V]; display [SIM] |
| ASG-26 sight (F-4E) | — | — | nothing: the sight has no IFF symbol | — | — | [V] (sight description) |
| Kurnass 2000 | nothing public | — | — | — | — | — |
| Kfir C2/C7 | nothing public | — | — | — | — | — |
| Lavi | nothing public | — | — | — | — | — |
| Mirage IIICJ (Shahak) | nothing public | — | — | — | — | — |
| CSF 95 sight (Mirage) | — | — | nothing: the reticle has no IFF symbol | — | — | [V] (CSF 97K drawings) |
| F-35I (Adir) | part of the communication, navigation and identification (CNI) system; fused into tracks | not public | PCD tactical display; helmet: not public | green = friend, yellow = unknown / suspect, red = hostile; green circle, yellow square, red diamond | continuous (a track property) | [S] |

### Details and sources

**F-16C/D.**
- Era [S]: the USAF chose the AN/APX-113 combined interrogator / transponder in 1999 to replace the transponder-only
  AN/APX-101 on its F-16C/D. It was fielded with the CCIP (Common Configuration Implementation Program) on Block
  50/52 in the early 2000s (Lockheed Martin releases, f-16.net). So the Block 30/40 jets of the game's period most
  likely had no air-to-air interrogator. Nothing public covers the IAF's Barak.
- The MLU M1 guide (15 Nov 1998) lists the APX-113 as **new**: it "expands the traditional IFF transponder
  capabilities to include Mode S and adds an on-board interrogation feature" [V, MLU M1 p. 1].
- Control [V, MLU M1 pp. 52–54]: "The pilot commands SCAN interrogations by depressing TMS left for less than 1/2
  second"; "Depressing TMS left for 1/2 second or more commands LOS interrogations". SCAN covers ±60° azimuth and
  elevation; LOS covers ±15° azimuth about the FCR cursor. The M3 tape moved the split to 0.6 s [V, MLU M3 p. 10].
- Display [V, MLU M1 p. 53]: "The green circles denote 'friendly' replies and yellow squares indicate responses that
  are of an 'unknown' nature." "Interrogation replies are always displayed on the FCR A-A MFD format and may be
  selected to appear on the … HSD." During a SCAN interrogation the FCR blanks its own targets and track files.
- Correlation [V, MLU M3 p. 167]: "The AIFF can interrogate a target; however, the response (or lack of response) is
  not correlated to a target track. The pilot must make his own assessment".
- HUD: the dash-34 HUD chapter (§ F-16C/D above) has no IFF symbol.
- Timing [SIM, Chuck's DCS F-16C guide pp. 643–644]: "If the contact is friendly, a green circle is drawn around the
  contact for three seconds"; "If no reply is received, no indication is displayed". DCS draws the circle on the
  track; the real guide draws it at the reply's own position.

**F-15A/C.**
- Control [V, TO 1F-15A-1 fig. 1-2 sheet 1, p. 1-5]: "IFF INTERROGATE & AIM-9L MANUAL BORESIGHT BUTTON — INITIATES
  SELECTED IFF MODE". With MSIP grips (sheet 2, p. 1-6), the multi-function (coolie) switch: "(LEFT) IFF
  INTERROGATE", momentary, "MUST BE HELD FOR CONTACT".
- The interrogator panel on the left console provides "air-to-air (AAI) target identification" [V, -1 pp. 1-80/81].
  Its display is described in TO 1F-15A/C-34-1-1, which is not public.
- Display [SIM, Falcon BMS TO 1F-15C-34-1-1 §16, p. 83]: the AAI "generates display symbols on the VSD at the correct
  target range and azimuth position". "A high confidence (HC) return is indicated by a O symbol, a low confidence
  (LC) return is indicated by a ◊." At long range a reply is hard to match to its track.
- HUD: the public HUD descriptions (the -1, NADC 1976) have no IFF symbol.

**F-4E.**
- Sets [V, TO 1F-4E-1 (1979)]: "AN/APX-81 interrogator set before TO 1F-4E-587 or … the APX-80 interrogator set
  after"; change 1F-4E-587 "Adds AN/APX-80 A/A IFF". The display is in TO 1F-4C-34-1-1-2, which is not public. The
  foldout panel legend lists an "INTERROGATOR PUSH BUTTON (SOME AIRCRAFT)" among the rear cockpit's radar controls.
- Display [SIM, Heatblur DCS F-4E manual, identification systems]: the WSO challenges with a button on the antenna
  hand control. "The radar screen presents the results of the interrogation with lines around the contacts
  position": a line above = a matching transponder mode, a line below = a matching code.
- The ASG-26 sight shows no IFF (§ F-4E Kurnass above).

**F-35.**
- [S, Code One, J. Kent, "The New Front Office", 2006]: "Symbols on the tactical display appear green if the
  aircraft's sensors or off-board assets determine these objects are friendly. If unknown to the sensors, objects
  appear yellow. If identified as potential adversaries, objects appear red."
- [S, M. Skaff (Lockheed Martin), "The Impact of Advanced Fusion in 5th Generation Fighters", 2013, as quoted on
  f-16.net]: "red diamonds, green circles, and yellow squares correspond to foe, friend, and suspect."
- Not public: whether the pilot starts an interrogation, and the track shapes on the green helmet display.

**Kurnass 2000, Kfir, Lavi, Mirage IIICJ.** No public document describes an interrogator or an IFF display for these
jets. Searched: flight-manual text, Jane's, Flight International, IAI / Elbit material, simulator communities.

### Proposed build

What a Real-mode IFF would implement, only from the findings above:
- **Every HUD, sight and helmet**: no friend mark (as today). No public source puts IFF on any of these displays.
- **F-16C/D (Block 30/40)**: no interrogator, no IFF display. The F-16 HUD and radar page stay as they are.
- **F-15C**: an interrogate key (the throttle button; a new, unused key). While the key is held, reply symbols on
  the radar page at each friendly reply's range and azimuth: a circle (high confidence). No symbol for a unit that
  does not reply. The time a reply stays after release is ours (3 s, the only figure found [SIM]) and goes in
  docs/deviations.md.
- **F-4E (Kurnass)**: the same key stands for the WSO's button. Replies on the radar page as a line above and a line
  below the friendly contact (matching mode and code). Display time as for the F-15.
- **F-35I**: no key. On the radar page, a friend's contact gets a circle and a hostile's a diamond, for as long as
  the contact is shown (fused tracks). Colours (green / red) only if the radar page can draw them without changing
  the original page.
- **Kurnass 2000, Kfir, Lavi, Mirage IIICJ**: nothing, and the pilot guides say the jet has no IFF display.
- All of it under the Real HUD switch only; the original HUD's friendly X and the original radar page stay as they
  are.

### Decisions (user, 2026-10-17; not built yet)

- **F-15C**: build as proposed above.
- **F-4E (Kurnass)**: the game has no back seat, so the WSO's interrogation is automatic. The virtual WSO
  interrogates each new radar contact once and the locked contact every few seconds; the replies show on the radar
  page as the lines above / below, for the display time above. The interrogate key also works (the pilot asking the
  WSO). The automatic timing is ours and goes in docs/deviations.md.
- **F-16**: the game's F-16D is the early-1990s Barak, which had no interrogator. Today's IAF F-16s have one, so the
  modern F-16 becomes its own switch (docs/roadmap.md "F-16I Sufa option"), with AIFF (the APX-113 class
  interrogator: TMS left, green circle / yellow square on the FCR, as in the MLU guides above) among its upgrades.
- **F-35I**: the helmet stays monochrome green with one target designator for every locked contact, as on the real
  jet. The friend / unknown / hostile colours and shapes belong on the panoramic display's radar and map formats, so
  they come with the Real MFDs (docs/roadmap.md "Real MFDs"), drawn in the real formats, not added to today's pages.
- **Kurnass 2000, Kfir, Lavi, Mirage IIICJ**: as proposed above.

## Pull-up and break marks, and the dive / height voice (per jet)

With the Real HUD each jet shows the pull-up / break mark of the real aircraft, and speaks the dive and height calls
of the real aircraft's voice system (the voice research: [real-betty.md](real-betty.md)). The original HUD keeps the
game's rule (docs/cockpit.md "break X", docs/sound.md §4).

| Jet | HUD mark | Dive / height voice |
| --- | --- | --- |
| F-16 | the break X: flashing at the GAAF advisory in every master mode; steady in the A-A missile modes inside Rmin[^dash34brk] | "PULL UP – PULL UP" at the GAAF advisory[^dash34gaaf]; "ALTITUDE – ALTITUDE" below the ALOW height[^dash34alow], 300 ft by default[^betty] |
| F-15 | the breakaway X inside Rmin (section F-15A/C above) | none: the sources list no pull-up or height call[^betty] |
| F-35I | open (none drawn) | "PULL UP" at the F-16's GAAF rule (inferred: Auto-GCAS lineage[^betty]); no height call |
| Lavi, Kurnass 2000 | open (none drawn) | the game's Betty rule (the jets' voice systems are open[^betty]) |
| Kfir | open (none drawn) | none (no voice[^betty]) |
| F-4E, Mirage | none: the optical sights have no such mark (inferred from the sight manuals above) | none (no voice[^betty]) |
| MiG-23, MiG-29 | open (none drawn) | none with the Real HUD (the jets' voice systems are open) |

F-16 ground avoidance advisory (GAAF, `crates/iaf-avionics/src/gaaf.rs`)[^dash34gaaf]:
- Active with the gear up, above 50 ft AGL and descending at 960 fpm or more.
- The advisory comes when the height above the ground is at or below the height lost in the recovery plus a buffer.
  - The recovery: the pilot's reaction (1 s; 0.45 s in the A-G modes at a low dive angle, low bank and high speed),
    the roll to wings level, then a 4.0 g wings-level pull-up.
  - The buffer: above 375 KCAS 12.5 % of that height + 50 ft; below 325 KCAS 25 % + 150 ft; linear between.
  - Inferred (the manual gives no numbers): "low dive, low bank, high speed" = under 30°, under 30°, over 400 KCAS;
    the roll rate 180°/s (the manual uses the jet's maximum for its stores); the pull-up radius V² / (g·(4 − 1)).
  - Example: a 45° dive at 413 KCAS gives the advisory at about 2,270 ft; a 20° strafing dive at 414 KCAS at about
    510 ft.
- The voice message plays to its end once per advisory; the cues reset when the dive is corrected[^dash34gaaf].
- The break X: ours is 0.6 of the field across, on the field's centre, flashing at 2 Hz (inferred from fig. 1-212).
- Not built: the pull-up anticipation cue (the U that rises to the flight path marker in the A-G modes) and the LOW
  mnemonic[^dash34brk]; the MFD break X.

CARA ALOW (`gaaf::alow`)[^dash34alow]: below the ALOW height; it stops above it, climbing faster than 1,200 fpm, with the
gear handle down, or below 15 ft. Ours repeats the call every 4 s (the game's Betty period; inferred).

## What ours draws (status)

This section lists, per jet, what the code draws and what it leaves out.

The cockpit art's glass is narrower than the real HUDs' field of view. On the F-16, F-15 and Lavi the scales and
data blocks sit 14 / 10 / 6 px in from the cockpit's HUD field (`Field::inset`), so the widest layout, the F-16's
A-A one with the altitude scale moved out for the DLZ, stays on the glass. Every block keeps its place relative to
its scale. The original HUD keeps the original layout.

- F-16: the NAV / A-A / A-G layout of figs. 1-110 / 1-111 / 1-115.
  - Drawn: the scales, boxes, the "C"; windows 3 / 4 / 5 / 7 / 8 / 10 / 13 / 14 / 25 / 26 without ALOW; the heading
    box low / high; the roll indicator; the bending ladder with the zenith star / nadir earth; FPM, AoA bracket,
    steerpoint diamond; TD box / locator line; AIM-9 reticle + seeker diamond; AIM-120 ASEC + ASC; DLZ with closure;
    CCIP / strafe pipper with the fall line; FUEL; SHOOT in its window (MLU; the AIM-9 / AIM-120 shoot cue).
  - The delayed CCIP (fig. 1-283), driven by the game's delayed release (docs/weapons.md §9.2 step 5, §9.4):
    - before designation: the pipper on the target under the original's HUD-edge pipper, kept on the glass (the real
      one is held ~14° below the cross; ours sits ~9° below it, where the game's release logic aims), the fall line to
      it, and the time delay cue across the line. Ours moves the cue from the FPM to the pipper as the time to go runs
      from 10 to 0 s, as the original HUD's cue (inferred);
    - Space held (designated): the steering line through the stored target along the rolled vertical and the solution
      cue left of it, 10 mr above the FPM's level per second to the release (inferred; the source gives no scale),
      at most 10 s, held at the glass's edge further out (inferred, like the CCRP cue frozen at its uppermost
      position[^dash34ccip]); it reaches the FPM's level at the game's release (time to
      go 0.9 s). The time row shows the time to release. The pipper is not drawn (the figure's dot in a circle is
      unexplained).
    - The other Real HUDs keep the plain pipper and fall line in the delayed case: the F-35's A-G graphics are the
      F-16's stand-ins with no public source, and the Lavi / Kurnass 2000 / Kfir layouts are reconstructions.
  - EEGS levels 2 and 5 per fig. 1-257: funnel, MRGS lines, T-symbol, 1 g / 9 g pippers, 4 mr pipper, TD circle with
    the range arc and the maximum-range dot.
  - The target-aspect triangle rides the AIM-9 reticle / ASEC.
  - The break X (GAAF and A-A inside Rmin; "Pull-up and break marks" above).
  - Not drawn: the VVI (vertical velocity indicator) scale (ours: the VAH switch position), DTOS / CCRP (the game has
    no such modes), BATR / FEDS, ALOW, the pull-up anticipation cue.
- F-15: tapes, heading, ladder with the zenith ⊖ "90" / nadir ⊗, velocity vector, -W-, gun cross when armed, G, Mach
  in A-A, NAV window, TD box, ASE circle + dot, range scale + IN RNG, breakaway X inside Rmin, LCOS reticle with the
  range arc, bomb fall line to the target square, AoA scale gear down (ours: degrees as units), NAV bank steering bar
  (ours: 2 px per degree of bearing error). Not drawn: the ILS flight-director cross, Mach outside A-A.
- Kfir: its own layout (§ Kfir C2/C7): numbers for speed / altitude, the heading scale with the steering bug, the
  waypoint marker, straight ladder, LCOS / hotline, spinning seeker diamond, CCIP pipper and fall line.
- Lavi: everything in its section above (a reconstruction). Not drawn: the bank scale, an ILS flight director, a
  VVI.
- F-4E / Mirage: the reticles as specified (ours: the reticle rides the LCOS / CCIP pipper).
- Kurnass 2000: its own reconstruction (`k2000.rs`, the section above): boxes, heading scale with the steering caret,
  ladder and marker, SRM / MRM / LCOS gun / CCIP / strafe symbols, the launch-range scale, SHOOT / FUEL.
- F-35: the forward virtual HUD and the off-boresight head set; the gun / A-G graphics are the F-16's
  (reconstruction).
- MiG-23: its own reconstruction (`mig23.rs`, the section above): the fixed cross, the steering ring, К / Г on the ILS,
  the target diamond at the designation limits with «НОП», the km range scale, «ПР», the gun ring with its metre range
  bar, the CCIP pipper. No flight data, as the real sight.
- MiG-29: its own HUD (`mig29.rs`, the section above): km/h, m, the heading tape in tens, the right-hand pitch scale,
  the horizon line, the bank scale, the steering circle, the waypoint range in km, the mode names, the km range scale
  with «ПР» / «ОТВ», the vertical scan, Ф0, the gun ring or GSh-30-1 funnel, the A-G pipper; the Щель-3УМ looking
  aside.
- DASH: in the F-16 / F-15 cockpits only (the MiG-29 has its Щель-3УМ); the Lavi, Kurnass 2000 and Kfir keep the original's helmet display.
  - When: looking aside with the Real HUD on (the original's dash condition: the panel panned ≥ 250 px aside or
    ≥ 200 px down).
  - Drawn in green, around the helmet's line of sight: the aiming cross, the line-of-sight circle with its gap, G /
    airspeed / ARM or NAV / the weapon, altitude / steerpoint, the head's heading, the TD box and the seeker diamond
    inside the 20° field.
  - The heading sits above the cross: the cockpit view's centre is low on the screen, so the JHMCS's bottom position
    would fall off it.
  - Not drawn: a horizon, shoot cue, RWR (radar warning receiver) symbols, declutter. Blanking is implied: the helmet
    set shows only while looking aside.

## References

Real-world documents (primary):
- F-16: [T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997](https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf) — HUD chapter pp. 1-158..1-183 (fig. 1-115 "HUD Window and Scale Positions"), A-A gun pp. 403-411, A-A missiles pp. 413-423, A-G pp. 441-458.
- F-16 IFF: [Lockheed Martin F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998)](https://falcon.blu3wolf.com/Docs/MLU_M1.pdf) — AN/APX-113 AIFF pp. 49–55, fig. 1-54 "AIFF Controls and Symbology".
- F-15 IFF: TO 1F-15A-1 above, fig. 1-2 sheets 1–2 pp. 1-5 / 1-6 (interrogate button / coolie), pp. 1-80/81 (interrogator set).
- F-4E IFF: [TO 1F-4E-1 flight manual (1979)](https://archive.org/details/f-4e-1-flight-manual) — AN/APX-80 / 81 interrogator sets, TO 1F-4E-587, p. 4-19, foldout FO-10.
- F-16: [T.O. GR1F-16CJ-1, Hellenic AF F-16C/D flight manual (dash-1)](https://falcon.blu3wolf.com/Docs/HAF-F16.pdf) — AoA bracket, ILS.
- F-16: Lockheed Martin F-16 MLU tape pilot's guides [M1](https://falcon.blu3wolf.com/Docs/MLU_M1.pdf), [M2](https://falcon.blu3wolf.com/Docs/MLU_M2.pdf), [M3 (16PR16226, 2004)](https://falcon.blu3wolf.com/Docs/MLU_M3.pdf).
- F-16: [RoKAF AFTTP 3-3 Vol 5, F-16C Basic Employment Manual (2005)](https://falcon.blu3wolf.com/Docs/Basic-Employment-Manual-F-16C-RoKAF.pdf) — EEGS, CCIP employment.
- F-16: [MCH 11-F16 Vol 5, Combat Aircraft Fundamentals (1996)](https://falcon.blu3wolf.com/Docs/F-16%20COMBAT%20AIRCRAFT%20FUNDAMENTALS%20-%20Multi-Command%20Handbook%2011-F16%20Vol5.pdf).
- F-15: [TO 1F-15A-1, F-15A/B/C/D flight manual (15 Jan 1984)](https://archive.org/details/f-15-manual) — "Navigation Head-Up Displays" pp. 1-65ff, figs. 1-14 (NAV HUD) and 1-15 (ILS HUD).
- F-15 and others: [NADC-75267-40 "Head-Up Display Symbology" (1976), DTIC ADA022655](https://archive.org/details/DTIC_ADA022655) — per-aircraft HUD symbology tables and figures.
- Mirage III: [RAAF AAP 7213.003-1 Mirage IIIO / IIID Flight Manual (1978)](https://aviationarchives.blogspot.com/2023/03/australia-dassault-mirage-iiio-and-iiid.html) ([Avialogs listing](https://www.avialogs.com/aircraft-d/dassault/item/2766-aap-7213003-1-flight-manual-mirage-iiio-and-iiid)) — CSF 97K sight pp. 1-109..1-121, figs. 1-60..1-73.
- Kfir: [Flight International, 27 Aug 1983, p. 542 "Smart nav/attack system for Kfir"](https://cdnc.heyzine.com/files/uploaded/v3/3c1262af2443f80fe2c7293f1cedb885c62cfe96.pdf) — Elbit System 82 WDNS.
- Kfir: [Jane's All the World's Aircraft, IAI Kfir](https://janes.migavia.com/?view=article&id=155:kfir) (C7, WDNS-341, System 82); [War Thunder research thread (System 82 modes, Colombian C7 HUD footage)](https://forum.warthunder.com/t/kfir-aircraft-c-1-c-10-blk-60-from-cub-to-lion-discussion-analysis-and-research/285880).
- F-35: Lockheed Martin "The F-35 Cockpit" slides ([SlideShare](http://www.slideshare.net/robbinlaird/the-f35-cockpit/download); images [mirrored on f-16.net](https://www.f-16.net/forum/viewtopic.php?t=16223&start=180)) — "Virtual HUD Looking Forward", "HMD Looking Behind the Aircraft".
- F-35: US Navy flight-test helmet-display videos, [The War Zone](https://www.twz.com/12297/navy-presents-new-f-35-helmet-display-videos-and-flight-test-dangers) and [HMS Queen Elizabeth landing](https://www.twz.com/29569/check-out-this-f-35-helmet-display-video-of-a-rolling-landing-on-the-hms-queen-elizabeth).
- DASH: [Helmet Mounted Sights and Displays (Air Power Australia)](https://www.ausairpower.net/hmd-technology.html) — DASH GEN I–III fielding, 20° FoV, green calligraphic symbology, boxed target / seeker diamond; [Rafael Python 4 (Air Power Australia)](https://www.ausairpower.net/TE-Gen-4-AAM-97.html).
- DASH: [The Avionics Handbook, ch. 5 "Head-Mounted Displays" (CRC 2001)](https://helitavia.com/avionics/TheAvionicsHandbook_Cap_5.pdf) — DASH for the Python 4 (1993–94); JHMCS look-to / shoot cues, altitude, airspeed, heading, horizon; 20° FoV.
- DASH: Elbit / VSI: [Elbit–Kaiser tie-up (Flight)](https://flightglobal.com/elbit/kaiser-tie-up/10418.article), [VSI JHMCS contracts (2004)](https://www.securityinfowatch.com/home/article/10553909/elbit-systems-joint-venture-with-rockwell-collins-vsi-awarded-jhmcs-contracts-valued-at-more-than-60-million), [Israeli helmets for US pilots (Israel21c)](https://archive.israel21c.org/israeli-company-to-supply-u-s-fighter-pilots-with-seeing-eye-helmets/).
- DASH: [IAF F-15 Baz cockpit / DASH (The War Zone)](https://www.twz.com/f-15a-baz-upgraded-cockpit-seen-in-rare-israeli-air-force-photo), [Python training rounds and the DASH (The War Zone)](https://www.twz.com/israeli-python-training-missiles-are-cleverly-disguised-as-u-s-sidewinders).
- DASH layout (JHMCS F-16, simulator): [DCS F-16C Viper guide, §4.3 HMD symbology / setup (Chuck's Guides)](https://assets.chucksguides.com/pdf/DCS%20F-16C%20Viper%20Guide.pdf) [SIM].
- F-35: [Collins Aerospace F-35 Gen III HMDS datasheet](https://prd-sc102-cdn.rtx.com/-/media/ca/f/f35/jsf-f35-datasheet.pdf).

Secondary (articles, books, pilot accounts):
- F-35: Aviation Today, [“Such a Capable Helmet” (2010)](https://www.aviationtoday.com/2010/07/01/such-a-capable-helmet/) and [“F-35 Gen III Helmet” (2015)](https://www.aviationtoday.com/2015/09/04/f-35-gen-iii-helmet-a-generational-leap-in-technology/); [Code One “Lightning Sight”](http://www.codeonemagazine.com/article.html?item_id=12); [SLDinfo F-35 cockpit overview](https://sldinfo.com/whitepapers/an-overview-of-the-f-35-cockpit-what-5th-generation-aircraft-are-all-about/); gun symbology (DOT&E via [The War Zone](https://www.twz.com/air/f-35as-beleaguered-25mm-cannon-is-finally-effective)); [F-35I helmet (National Interest)](https://nationalinterest.org/blog/buzz/israels-unique-f-35-variant-comes-with-unique-combat-helmet-ps-031326).
- F-35 IFF: [Code One, J. Kent, "The New Front Office" (2006)](https://www.codeonemagazine.com/u2_article.html?item_id=35) (track colours); M. Skaff, "The Impact of Advanced Fusion in 5th Generation Fighters" (2013), quoted [on f-16.net](https://www.f-16.net/forum/viewtopic.php?f=22&t=29126) (track shapes).
- F-15: [F-15C pilot account, The War Zone](https://www.twz.com/35765/confessions-of-an-f-15-eagle-driver-with-three-mig-kills) (ASE circle, steering dot, TD box).
- F-16: [f-16.net pilot / test-pilot discussions](https://www.f-16.net/forum/viewtopic.php?t=5116) (bending ladder bars, ghost horizon).
- F-4E: [Joe Baugher, F-4E](https://www.joebaugher.com/usaf_fighters/f4_11.html); Kurnass 2000: [Joe Baugher](https://www.aircraftinformation.info/JB_AIF/usaf_fighters/f4_35.html), [airvectors](http://www.airvectors.net/avf4_4.html), [warmachinesdrawn](https://warmachinesdrawn.blogspot.com/2017/06/mcdonnell-douglas-f-4e-kurnass-2000.html), [GlobalSecurity](https://www.globalsecurity.org/military/world/israel/kurnass-2000.htm); the F-4E-2020's El-Op 976: [Elbit F-16 I-HUD (same wide-angle family)](https://elbitsystems.com/media/f-16_I-HUD2_2022.pdf).
- Mirage IIICJ: Shlomo Aloni, *Mirage III vs MiG-21* (Osprey 2010) and *Israeli Mirage III and Nesher Aces* (Osprey 2004), via [Hebrew Wikipedia “מיראז' 3”](https://he.wikipedia.org/wiki/%D7%9E%D7%99%D7%A8%D7%90%D7%96%27_3); Tim Callaway, *Dassault Mirage III/5* (Aviation Classics 17, 2012).
- Kfir: [militaryfactory](https://www.militaryfactory.com/aircraft/detail.php?aircraft_id=152), [milavia](https://www.milavia.net/aircraft/kfir/kfir.htm), [Forecast International archive](https://www.forecastinternational.com/archive/disp_old_pdf.cfm?ARC_ID=1014).
- Lavi: [Ruud Deurenberg, *IAI Lavi*](https://www.dror-aero.com/pro/lavi5.pdf).

Simulator documentation (used only for detail, each fact tagged [SIM] above):
- F-4E IFF: [Heatblur DCS F-4E manual, identification systems](https://f4.manuals.heatblur.se/systems/identification_systems.html) (APX-76 / Combat Tree reply lines).
- F-15 IFF: the Falcon BMS TO 1F-15C-34-1-1 below, §16 p. 83 (VSD reply symbols). F-16 IFF timing: the DCS F-16C guide (Chuck's Guides) above, pp. 643–644.
- F-4E: [Heatblur DCS F-4E manual, LCOSS](https://f4.manuals.heatblur.se/systems/weapon_systems/lcoss.html) and [optical sight BIT](https://f4.manuals.heatblur.se/procedures/bit_tests/optical_sight.html) (paraphrasing T.O. 1F-4E-1 / -34).
- F-15: [Falcon BMS TO 1F-15C-34-1-1](https://cdn.falcon-bms.com/docs/4.37/TO%201F-15C-34-1-1%20BMS.pdf).
- F-16: [Falconpedia HUD](http://falcon4.wikidot.com/avionics:hud), [NikolaiVChr FlightGear F-16 HUD wiki](https://github.com/NikolaiVChr/f16/wiki/HUD).

[^dash34brk]: T.O. GR1F-16CJ-34-1-1 (Hellenic AF, 16 Jun 1997), p. 1-173 "Pullup Anticipation and Breakaway Cue (Break
    X)", https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf (PDF page 189).
[^dash34gaaf]: T.O. GR1F-16CJ-34-1-1, pp. 1-313..1-315 "Ground Avoidance Advisory Function (GAAF)" and fig. 1-212,
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf (PDF pages 329-331).
[^dash34alow]: T.O. GR1F-16CJ-34-1-1, p. 1-316 "CARA Altitude Low (CARA ALOW)", https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
    (PDF page 332).
[^betty]: [real-betty.md](real-betty.md) §1 and its sources.
[^dash34ccip]: T.O. GR1F-16CJ-34-1-1, pp. 1-429..1-430 "CCIP Visual Submode" and fig. 1-283 "CCIP Operation",
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf (PDF pages 445-446); the CCRP solution cue held in its uppermost
    position, p. 1-428 "No Solution Condition" (PDF page 444).
[^airwar-ml]: airwar.ru, "МиГ-23МЛ" (radar data on the sight, the designation limits, НОП): https://www.airwar.ru/enc/fighter/mig23ml.html
[^n003e]: "N003E modes", Soviet aircraft tech (the К / Г symbols in the НВГ mode): https://sites.google.com/site/sovietaircrafttech/mig-23/n003e/modes
[^ea29]: Eagle Dynamics, *DCS MiG-29A Early Access Manual* (Sept 2025), pp. 65–104 (HUD): https://www.digitalcombatsimulator.com/upload/iblock/aa2/ulzl67k42kj99ushy9m29hlvmtk0y2tg/DCS%20MiG-29A%20Early%20Access%20Manual%20EN.pdf
[^fc3]: Eagle Dynamics, *DCS MiG-29 Flight Manual* (Flaming Cliffs 3), pp. 40–59 (HUD): https://www.digitalcombatsimulator.com/upload/iblock/463/DCS%20MIG-29%20Flight%20Manual%20EN.pdf
[^gsh30]: Wikipedia, "Gryazev-Shipunov GSh-30-1" (muzzle velocity 860 m/s): https://en.wikipedia.org/wiki/Gryazev-Shipunov_GSh-30-1
