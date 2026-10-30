# Real HUD: per-aircraft reference (Extras > HUD)

The Real HUD (head-up display) is an Extras option. It replaces the original 1998 HUD with each jet's real sight / HUD
/ helmet symbology (docs/deviations.md §2). This file is the reference the code (`crates/iaf-avionics/src/real_hud/`)
is built from: per aircraft, what is shown, where, in what format, and how sure we are. How the game draws it:
[cockpit.md "Real HUD"](cockpit.md#real-hud-ours-extras--hud).

Key facts:
- Researched October 2026 from public sources. The repo keeps no source images.
- Real-world documents describe the F-16, F-15, F-4E, Mirage IIICJ and F-35
  displays[^dash34][^f15-1][^f4e-1][^raaf][^lm-slides].
- The Lavi, Kurnass 2000, Kfir and MiG-23 layouts and the DASH helmet's layout are public only in outline; ours are
  reconstructions (inferred). The MiG-29's comes from simulator manuals (docs/mig-cockpits.md §6).
- [What ours draws (status)](#what-ours-draws-status) lists, per jet, what the code draws and what it leaves out.
- [IFF](#iff-identification-friend-or-foe) says how each real jet shows a friend, with a proposed build.

Sources are footnotes; a simulator source says so in its footnote. "Inferred" marks our own reconstruction (from
the era and the maker, recorded in docs/deviations.md); "open" marks what no source gives.

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
| F-16C/D (Barak) | `f16` | F-16 Block 30/40/50 HUD | dash-34 manual[^dash34] |
| Lavi | `lavi` | Hughes wide-angle diffractive HUD, Elbit integrated display system; symbology not public | hardware[^deurenberg]; layout inferred (a 1980s US / Israeli wide-angle HUD with its own layout) |
| F-15A/C (Baz) | `f15` | F-15A/C HUD (moving tapes, no digital boxes) | TO 1F-15A-1[^f15-1] + NADC 1976[^nadc] |
| F-4E (Kurnass) | `phantom` | AN/ASG-26 lead-computing optical sight (no HUD) | a simulator manual paraphrasing the T.O.[^heatblur-lcoss] |
| F-4E 2000 (Kurnass 2000) | `f4-2000` | Kaiser / El-Op wide-angle holographic HUD, Elbit ACE-3; symbology not public | inferred: its own (MIL-STD-1787 style) |
| Kfir C2/C7 | `cfir` | El-Op HUD with the Elbit System 82 / WDNS-341; layout not public | modes[^flight1983][^wt-kfir], layout inferred |
| Mirage IIICJ (Shahak) | `mirage` | CSF 95 gyro gunsight (reflector, no HUD) | CSF 97K manual drawings[^raaf] + IAF books[^aloni] |
| F-35I (Adir) | `extra/planes/f35i` | Gen III helmet display (no HUD) | Lockheed Martin (LM) slides[^lm-slides] + flight-test video[^twz-f35] |
| MiG-23ML | `mig23` | АСП-17МЛ sight: radar / IRST data on the sight, no flight data | outline[^airwar-ml]; layout inferred |
| MiG-29 9.12 | `mig29` | ИЛС-31 HUD (СЕИ-31); Щель-3УМ helmet sight looking aside | simulator manuals built on the real jet[^ea29][^fc3] |
| F-16C/D, F-15C/D helmet (looking aside) | `f16`, `f15` | Elbit DASH III (Display And Sight Helmet) | fielding / optics[^ausairpower-hmd][^avhandbook]; symbology from the DASH-derived JHMCS in a simulator guide[^chucks]; layout inferred |

## F-16C/D (Block 30/40/50)

The Block 50 dash-34 manual documents this HUD in full[^dash34]. The D is the two-seater with the same HUD (a repeater
in the rear cockpit). Barak-specific differences: none public.

Sources: the dash-34[^dash34] and dash-1[^dash1]; the Lockheed MLU (Mid-Life Update) pilot's guides
M1-M3[^mlu1][^mlu2][^mlu3]; the RoKAF Basic Employment Manual[^rokaf]; the MCH 11-F16 handbook[^mch]; f-16.net pilot /
test-pilot accounts[^f16net].

**Scales**[^dash34]
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
- Roll indicator: tics on a 70 mr arc centred 50 mr below the FOV centre, every 10° to ±45°. With "Real HUD view"
  (see "Real view") it sits at that place. With the original view the glass is shorter than the real field, so ours
  raises the arc until its lowest tic stays inside the glass.

**Ladder / markers**[^dash34]
- Pitch ladder ("attitude bars"): a bar every 5° to ±60°, compressed beyond.
  - Climb bars are solid, dive bars dashed. Tips point toward the horizon; a centre gap leaves room for the FPM;
    numbers at both ends.
  - **Bars bend toward the horizon increasingly with pitch** (test-pilot account[^f16net] + figure). The exact "half
    the angle" rule is MIL-STD-1787 convention, as the simulator references give it[^falconpedia][^fg-hud].
- Zenith / nadir: straight up a star (a circle with eight spokes), straight down the earth (a circle with a cross),
  in place of the ±90° bars (inferred). This is the MIL-STD-1787 convention; no public F-16 figure shows them.
- FPM: 10 mr circle, 10 mr wings, 5 mr tail; an X over it when limited.
- Gun / boresight cross: an incomplete plus at the fuselage reference line.
- AoA bracket (gear down): the FPM at its top = 11°, centre 13°, bottom 15° (dash-1[^dash1]).
- Steerpoint: a **6 mr diamond drawn on the ground at the steerpoint** (conformal); an X when limited at the FOV
  edge.

**Data windows** (dash-34 fig 1-115[^dash34])
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

**A-A missiles**[^dash34]
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

**A-A gun**[^dash34][^rokaf]
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

**A-G**[^dash34]
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

The Lavi's HUD hardware is known[^deurenberg][^wiki-lavi]. Its symbology is not public, so ours is a reconstruction
(inferred).

Sources: Deurenberg, *IAI Lavi* (citing Flight International / Jane's)[^deurenberg]; Wikipedia "IAI Lavi"[^wiki-lavi];
for general diffractive-HUD optics, Rochester Avionic Archives[^rochester].
- **Hardware**[^deurenberg]: "a Hughes Aircraft wide-angle diffractive optics head-up display (HUD) surmounting a single
  El-Op up-front control panel".
  - Elbit Computers was prime contractor for the integrated display system: the HUD, three head-down displays (two
    colour, one monochrome), the display computers and the communications controller.
  - The Elbit ACE-4 mission computer; HOTAS; a central stick (not a side-stick).
  - Some sources give Kaiser for the HUD[^dokumen-lavi].
- **Field of view** (diffractive HUDs in general[^rochester]): a diffractive HUD of that generation gives ~30° × 18°,
  against ~13° × 9° for a refractive one. Green P43 phosphor (matched to the diffractive combiner's narrow band).
- **Symbology: not public.** No photo or video through the Lavi's HUD was found, and no description of its symbology.
  The B-1 / B-2 prototypes flew 1986–87, the TD B-3 (technology demonstrator) from 1989.
- **Ours** (inferred): a reconstruction of a late-1980s US / Israeli wide-angle HUD, with MIL-STD-1787 conventions and
  the F/A-18's digital boxes. Its layout is its own, distinct by design from the F-16's dash-34 layout:
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
  - A-G: the strafe pipper with the gun cross, the CCIP pipper and fall line;
  - NAV: the bank scale at the bottom, MIL-STD-1787 style: ticks at 0, ±10, ±20, ±30, ±45 and ±60° on a 60 mr arc,
    the pointer at the bank angle (held at ±60°);
  - ILS (NAV, gear down): localizer and glide-slope needles referenced to the flight path marker, as on the F/A-18:
    fly the marker to where they cross. They move with the game's ILS deviations (12 px per degree, the original HUD's
    scale), stop at full scale 4° from the marker (inferred), and replace the original's ILS lines.

## F-15A/C

The F-15A/C HUD has **no digital speed / altitude boxes**: it shows moving tapes with fixed carets[^f15-1][^nadc].

Sources: TO 1F-15A-1[^f15-1]; NADC-75267-40[^nadc]; a pilot account[^twz-f15]; the Falcon BMS F-15C -34, a
simulator manual[^bms-f15].

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
- Steering: a bank steering bar.
- ILS (ILS/NAV or ILS/TCN steering mode, fig. 1-15 and p. 1-70)[^f15-1]: the steering mode reads `ILS-N` / `ILS-T` in
  the NAV window and `CSET` flashes 10 s. The integrated flight director: the bank steering bar (to the localizer) and
  the pitch steering bar, which joins it as a cross once the glide slope's centre is captured. Before that, within
  about 0.6° of the glide slope, `GSUP` or `GSDN` shows (the jet below / above it). `MKR` flashes over a marker
  beacon. The manual's figure shows the cross near the aircraft symbol; it gives no bar scale.
- A-A[^f15-1][^twz-f15]: the TD box; the ASE (allowable steering error) circle with a steering dot; a range scale
  inboard of the altitude scale (top = the radar range, a `320>` closure caret, two MAX ticks and one MIN tick, `IN
  RNG`); the breakaway X. SHOOT is a light on the canopy bow, outside the HUD[^f15-1].
- Gun: LCOS (no funnel): an outer ring with 12 ticks, a dashed inner circle, a centre pipper and a thick range
  arc[^f15-1]; 1,000 ft per tick (simulator manual only[^bms-f15]).
- A-G: no CCIP. A bomb fall line runs from the velocity vector to a target square, with a pull-up bracket and a
  release cue[^f15-1].

## F-4E Kurnass: AN/ASG-26 LCOSS (no HUD)

The Kurnass aims through the AN/ASG-26 LCOSS (lead-computing optical sight system), drawn **red**. Its reticle, like
the Mirage's, is not cut to the original HUD's symbology field: only the panel's top edge cuts it.

Sources: the Heatblur DCS F-4E manual, a simulator manual paraphrasing T.O. 1F-4E-1 / -34[^heatblur-lcoss], and its
BIT procedure[^heatblur-bit]; Joe Baugher[^baugher-f4e]; flyandwire.com[^flyandwire].
- Reticle[^heatblur-lcoss]: a 2 mr pipper dot; a 25 mr dashed inner ring; a 50 mr solid outer ring; three roll tabs on
  the outer ring (bank, or WRCS (weapon release computer system) steering).
- Range bar[^heatblur-lcoss]: inside the outer ring, from 6 o'clock counter-clockwise, **with a radar lock only**.
  - Guns: 1,000 ft at 6 o'clock + 1,000 ft per hour (max 6,667 ft).
  - Missiles: 3,000 ft per hour (max 20,000 ft).
- A/A: gyro lead with the radar range (default 1,000 ft). Missiles: the reticle at the RBL (radar boresight line,
  35 mr) for a boresight lock.
- A/G: manual depression 0-245 mr (35 mr = the gun cross); no CCIP[^heatblur-lcoss].
- The sight shows **no airspeed, altitude, heading or text**[^heatblur-lcoss]. Missile status / IN RANGE / SHOOT are
  lights.

## F-4E 2000 (Kurnass 2000)

The upgrade's HUD hardware is known[^baugher-k2000][^globalsecurity-k2000]; its symbology is not public, so ours is a
reconstruction (inferred).

Sources: Joe Baugher[^baugher-k2000], airvectors[^airvectors], warmachinesdrawn[^warmachines]; GlobalSecurity
"Kurnass 2000"[^globalsecurity-k2000].
- **The upgrade**[^baugher-k2000][^airvectors][^warmachines]: by IAI; the PW1120 test aircraft first flew 1986-87, in
  service from 1989. It brought a Kaiser / El-Op wide-angle (holographic) HUD, an Elbit ACE-3 mission computer, a
  display computer for the new MFDs, a HUD video camera and HOTAS.
- **The HUD**[^globalsecurity-k2000]: said to show speed, altitude, the direction of flight and the wind. GlobalSecurity
  claims a field of view of "60 % of the pilot's forward view, twice other systems" (unconfirmed). The same El-Op
  wide-angle HUD family went into the Turkish F-4E-2020 (El-Op 976)[^elbit-ihud].
- **No symbology figure, photo through the HUD or manual is public.** Searched: Flight International, IAF / IAI /
  Elbit material, CombatACE, War Thunder / DCS communities.

Ours (`real_hud/k2000.rs`) is therefore a reconstruction in the MIL-STD-1787 manner of an Elbit-generated HUD of the
late 1980s; all of the list below is inferred. Its layout is its own, distinct by design from the F-16's dash-34
layout:
- Airspeed and altitude: **boxed digital readouts** on the field's edges (no tapes). The radar altitude `R…`
  under the altitude below 5,000 ft.
- Left column: g, Mach, the master mode (`NAV`, `SRM`, `MRM`, `GUN`, `STRF`, `CCIP`, `LGB`, `TV`, `HARM`); gear down
  `AOA…`. Right column: `WP<n> <NM>`, the time to the waypoint, the target's range in A-A.
- Heading scale on top: a 30° window with the heading boxed under its centre, and a **filled steering caret** above
  it at the waypoint's bearing. Outside the window the caret is held at the scale's end with the angle still to turn.
- Flight path marker; a straight-rung pitch ladder (climb solid, dive dashed, signed labels at both ends, no bending,
  no zenith / nadir symbols); the waypoint's diamond on the ground (an X when limited) outside the A-A modes.
- A-A:
  - the target box;
  - SRM: the missile circle with the seeker diamond;
  - MRM: the circle (sized by the launch zone) with the steering dot and the launch-range scale (Rmax / Rmin, range
    caret, closure) inboard of the altitude box;
  - gun: an **LCOS** ring with the pipper dot and a range arc (12,000 ft a turn).
- A-G: the CCIP pipper (a dot in a ring) with the fall line from the marker; strafe: the pipper.
- `SHOOT` (or `FUEL` below the bingo) at the bottom centre. No wind readout.

## Kfir C2/C7

The Kfir's HUD modes and shown data are known[^flight1983][^janes-kfir][^wt-kfir]; its layout is not public, so ours
is a reconstruction (inferred).

Sources:
- Flight International 27 Aug 1983 p. 542 (Elbit System 82 WDNS, weapon delivery and navigation system)[^flight1983].
- Jane's: the C7 from mid-1983 has a HOTAS cockpit and the WDNS-341 with the Elbit System 82 stores management /
  release computer[^janes-kfir].
- The System 82 document as quoted in War Thunder research threads (modes), and Colombian Air Force Kfir C7 HUD
  footage (CACOM-1 / Python 3 launch) as described there[^wt-kfir].
- militaryfactory[^militaryfactory] / milavia[^milavia]; Forecast International[^forecast].

What is known:
- **Modes**[^flight1983][^wt-kfir]:
  - A-A gun: **LCOS** and **HOTLINE** (also listed: SNAP / SHOOT, unconfirmed).
  - A-G: **DIR** (direct / manual), **CCIP**, **TOSS** / DTOSS.
  - Waypoint navigation and toss with the Doppler fitted.
  - TV weapons are run from the head-down CRT (cathode-ray tube display), outside the HUD[^wt-kfir].
- **Data shown**[^wt-kfir]: airspeed, altitude, Mach, AoA, armament status. The footage shows a pitch ladder (horizon).
- **Missile cue**[^wt-kfir]: the Python 3 launch footage shows a diamond that spins until it locks, then stays on the
  target.
- **Gun**[^wt-kfir]: the footage shows the gun's lead indicator (a pipper moving with the lead) and, with the EL/M-2001B
  ranging radar, the radar gun lead on the target.

**Layout not public.** Ours (`real_hud/kfir.rs`) is an Elbit early-80s reconstruction (inferred):
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

The Shahak aims through a CSF 95 gyro gunsight. The CSF 97K's dimensioned drawings give the reticle[^raaf].

Sources: the RAAF Mirage IIIO/IIID Flight Manual (CSF 97K, dimensioned drawings)[^raaf]; Aloni's Osprey books via
Hebrew Wikipedia[^aloni]; Callaway, *Dassault Mirage III/5*[^callaway]. The Shahak's CSF 95 lacks the 97's gyro
horizon / heading[^aloni].
- Moving reticle: a 2.5 mr pipper dot inside a fixed 50 mr ring of 14 small diamonds. It moves up to 9° from the
  fixed cross[^raaf].
- Fixed cross: 40 mr wide (vertical stub 10 mr up / down), with an inverted V 40 mr above it[^raaf].
- Guns: lead-computing. The IAF fed in a pilot-selected range of 600 / 400 / 250 m, as radar ranging was
  unreliable[^aloni].
- Missiles: lock / in-zone lights in a column right of the glass (blue = lock)[^aloni]. The reticle has no missile
  symbols.
- Colour: drawn as a lamp reflector sight, a deep orange (inferred from period practice). 2026-10-26: the first
  build's light orange (RGB 1.0 / 0.62 / 0.2) all but vanished against a pale sky; now 1.0 / 0.45 / 0.05, drawn with
  the thicker reticle pen ("What ours draws").

## F-35I Adir: Gen III helmet display (no HUD)

The F-35I shows its flight data in the Gen III helmet display: green, 40° × 30°. Looking forward, it shows an
aircraft-stabilised "virtual HUD"[^lm-slides][^twz-f35]. The symbols the game adds over it (the ILS lines, the weapon
symbols, the radar's BORE cross) are green too, as over the DASH (`hud.gd` `_hc`).

Sources: Lockheed Martin "The F-35 Cockpit" slides[^lm-slides]; US Navy flight-test helmet video[^twz-f35]; the Collins
datasheet[^collins]; Aviation Today 2010 / 2015[^avtoday]; Code One[^codeone-sight]; SLDinfo[^sldinfo]; National
Interest on the F-35I helmet[^natint].

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
- Gun (A-A funnel and pipper, A-G strafe) and A-G cues: they exist[^dote-gun], but the graphics are not public (ours:
  inferred).

Off-boresight: the virtual HUD stays with the airframe. The helmet shows a reduced head-stabilised set: bare airspeed
/ altitude, heading, steerpoint, targets[^lm-slides]. With the AIM-9X selected ours adds the DASH's seeker diamond,
seeker limit, SHOOT and LOAL cues ("DASH helmet"; inferred).

Navigation. No public source names the helmet's navigation symbols or says how they behave.
The F-35 flight manual and the Collins symbology are not public; Collins, Elbit, Code One and the Aviation Today
articles describe the helmet only in general terms. The two LM frames are the only primary evidence. Ours reads them as
follows:
- **Steering caret** `^` on the heading tape (our reading of the LM frames[^lm-slides]). The forward frame (heading
  092°, steerpoint `001 110/22.0`) shows a `^` just past the tape's last tic on the right, the side of the steerpoint.
  The "Looking Behind" frame shows a `^` under the head's heading tape too. Ours: the caret sits under the tics at the
  steerpoint's bearing and is held at the tape's end (±17°) when the bearing is off the tape (the limit: inferred).
- **Steerpoint square** on the ground (our reading of the forward frame[^lm-slides]). The forward frame shows a small
  square far right, about 16° right and 6° below the horizon (scaled from the ladder: 5° = 210 px). The steerpoint 22 NM
  away at 110° from 19,067 ft lies 18° right and 8° below, so the square is most likely the steerpoint. Ours draws it in
  every master mode, ground-stabilised at the steerpoint's projection.
- Off the field: the square is held at the field's edge on the line from the boresight, as the slide says for the
  target designator (inferred). Behind the view, only the caret shows (inferred).
- Looking aside: the head set keeps the caret on its own heading tape (the "Looking Behind" frame[^lm-slides]); it draws
  no square (inferred: no frame shows one).
- No steering line, no distance or time beside the square (inferred: none is visible in either
  frame). The readouts stay in
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
- **Colour:** the HUD's (the real one is open), with the thicker reticle pen ("What ours draws").
- **Looking aside:** nothing (the ML has no helmet sight: inferred). Until 2026-10-26 the original's helmet display
  showed there, floating in the side view.
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
Helmet-Mounted Cueing System, its descendant), whose F-16 set is documented in a simulator guide[^chucks].
- **History**:
  - An IAF requirement for the F-15 and F-16 from the mid-1980s. GEN I was in production c. 1986; **GEN III**
    (early–mid 1990s) is on the IAF F-15C/D, F-16C/D and F-15I[^ausairpower-hmd].
  - Fielded in 1993–94 for off-axis targeting of the Rafael **Python 4**[^avhandbook].
  - Elbit's fixed-wing HMD (helmet-mounted display) is the basis of the US **JHMCS**, built by Vision Systems
    International (VSI), Elbit's joint venture with Kaiser, later Rockwell Collins[^elbit-vsi].
- **Display**: monocular, **20° circular** field of view, 15 mm exit pupil, collimated on the visor; calligraphic
  (stroke) symbology in **green** phosphor[^ausairpower-hmd]. Head tracking is electromagnetic; the line of sight goes
  to the mission computer (MIL-STD-1553B)[^ausairpower-hmd][^avhandbook].
- **Use**: aim by looking. The measured line of sight slaves the radar and the missile seeker to the target[^elbit-vsi].
  A boxed target cues the Python 4's seeker, and a **diamond** shows the seeker tracking
  it[^ausairpower-hmd][^ausairpower-python4]. The seeker follows the pilot's line of sight off
  boresight[^twz-dash][^globalsecurity-dash]. Its limits are the missile's and unpublished; ours keeps the game's cones
  (docs/weapons.md §5.4).
- **Content**[^ausairpower-hmd][^avhandbook]: flight and weapon data on the visor (airspeed, altitude, weapons status,
  aiming), so the pilot reads them without looking at the HUD. The JHMCS adds compass heading, an artificial horizon,
  "look-to" and shoot cues[^avhandbook].
- **Layout** (the JHMCS F-16 basic / A-A set from a simulator guide[^chucks], kept for the DASH: inferred):
  - the **aiming cross**, fixed at the field's centre (the helmet line of sight);
  - a **line-of-sight indicator**: a circle whose gap points where the head looks relative to the nose (a gap at
    11 o'clock = looking left and up);
  - on the left, G above the **airspeed**, with the **master arm / mode** under it;
  - on the right, the **barometric altitude**, with the range / steerpoint under it;
  - the helmet's **magnetic heading** at the bottom;
  - the radar target's **TD box** where it is in the field; the IR seeker's diamond;
  - HUD and cockpit **blanking**: the symbols blank while the head looks through the HUD or down into the
    cockpit[^chucks].
- **High off-boresight missiles** (the AIM-9X and Python 5, docs/weapons.md §13.1; `dash.rs` `hobs_cues`). The
  helmet points the seeker and the missile can lock after launch: the AIM-9X's seeker follows the helmet's line of
  sight[^raytheon-9x-hobs][^jhmcs-hobs]; the Python 5 locks before or after launch, all round, far off
  boresight[^gs-python5][^aft-python5]. No figure of these cues on the DASH or the JHMCS is public. Ours draws them in
  the DASH's style (inferred; the diamond as the seeker's line of sight, after the F-16 HMCS in a simulator
  guide[^chucks]):
  - the **seeker diamond** on the seeker's target while it tracks one, held on the field's edge toward it when the
    target is outside the 20° field;
  - without a target, the diamond on the **aiming cross**: the seeker is slaved to the helmet while the head looks
    within the missile's cone of the nose (90° / 100°);
  - the **seeker limit**: with the head beyond the cone the diamond stops on the field's edge toward the nose, an X
    over it;
  - **SHOOT** under the cross with the mode-1 shoot cue (the seeker's lock in range);
  - **LOAL** flashing under it (1 Hz) while a missile launched without a lock still searches.

  The F-35I's head-stabilised set draws the same cues for its AIM-9X, around its line-of-sight cross.
- Not public: the DASH's own fonts / positions, its horizon symbol, the Python-specific symbols, declutter levels.
  Ours leaves them out.

## IFF (identification friend or foe)

This section says how each real jet tells the pilot that an aircraft is a friend. It is the reference for a future
Real-mode IFF (not built). Today the Real HUD draws no friend mark: the original's friendly X on the target box is
part of the original HUD, which Real mode hides (docs/radar.md §6).

Terms:
- **Transponder**: the set that answers interrogations (every jet here has one).
- **Interrogator** (AAI, air-to-air interrogator): the set that sends the challenge. Only some jets carry one.
- **Reply symbol**: the mark the interrogator's answers make on a display.
- FCR = fire-control radar display; VSD = vertical situation display (the F-15's radar display); HSD = horizontal
  situation display; PCD = panoramic cockpit display (the F-35's head-down screen); WSO = weapon systems officer
  (the F-4E's back seat).

Key facts:
- In every real document found, the interrogator's reply is a **symbol on the radar display**, drawn at the reply's
  own range and bearing. It is not tied to the radar track. The pilot matches the two by eye[^mlu3].
- No real or simulator document shows an IFF reply **on a HUD** or **on a helmet**.
- Each interrogation is **started by the aircrew** with a momentary switch. No source gives a continuous, automatic
  interrogation for the 1980s–90s jets.
- How long a reply stays on the display is in no real document. One simulator guide gives 3 s[^chucks].
- The F-35 is different: its mission systems fuse every sensor into tracks, and each track carries an identity
  colour and shape on the head-down display[^codeone-kent][^skaff].

### Per jet

| Jet (game period) | Interrogator | Control | Where the answer shows | Symbol | Time shown | Sources |
|---|---|---|---|---|---|---|
| F-16C/D Block 30/40 (Barak, 1987–91) | none: the AN/APX-101 is a transponder only | — | — | — | — | [^apx113] |
| F-16 with AIFF (MLU 1998, USAF CCIP 2000s; later than the game) | AN/APX-113 | TMS (target management switch) left: under 0.5 s a SCAN interrogation, 0.5 s or more a line-of-sight (LOS) one | FCR A-A page; HSD on selection | green circle = friend, yellow square = unknown, nothing = no reply | not stated (a simulator guide: 3 s[^chucks]) | [^mlu1][^mlu3] |
| DASH helmet (F-16, F-15) | — | — | nothing public | nothing public | — | — |
| F-15A/C (Baz) | AN/APX-76 | IFF interrogate button on the throttle; with MSIP grips, the coolie switch left; held for contact | VSD, at the reply's range and azimuth | circle = high confidence, diamond = low confidence, nothing = no reply | not stated | control[^f15-1]; display: a simulator manual[^bms-f15] |
| F-4E (Kurnass) | AN/APX-81, AN/APX-80 after TO 1F-4E-587 | the WSO's interrogator push button | the WSO's radar scope | lines at the contact: one above = matching mode, one below = matching code | not stated | sets[^f4e-1]; display: a simulator manual[^heatblur-iff] |
| ASG-26 sight (F-4E) | — | — | nothing: the sight has no IFF symbol | — | — | sight description[^heatblur-lcoss] |
| Kurnass 2000 | nothing public | — | — | — | — | — |
| Kfir C2/C7 | nothing public | — | — | — | — | — |
| Lavi | nothing public | — | — | — | — | — |
| Mirage IIICJ (Shahak) | nothing public | — | — | — | — | — |
| CSF 95 sight (Mirage) | — | — | nothing: the reticle has no IFF symbol | — | — | CSF 97K drawings[^raaf] |
| F-35I (Adir) | part of the communication, navigation and identification (CNI) system; fused into tracks | not public | PCD tactical display; helmet: not public | green = friend, yellow = unknown / suspect, red = hostile; green circle, yellow square, red diamond | continuous (a track property) | [^codeone-kent][^skaff] |

### Details and sources

**F-16C/D.**
- Era[^apx113]: the USAF chose the AN/APX-113 combined interrogator / transponder in 1999 to replace the
  transponder-only AN/APX-101 on its F-16C/D. It was fielded with the CCIP (Common Configuration Implementation Program)
  on Block 50/52 in the early 2000s (Lockheed Martin releases, f-16.net). So the Block 30/40 jets of the game's period
  most likely had no air-to-air interrogator. Nothing public covers the IAF's Barak.
- The MLU M1 guide (15 Nov 1998) lists the APX-113 as **new**: it "expands the traditional IFF transponder
  capabilities to include Mode S and adds an on-board interrogation feature" (MLU M1 p. 1[^mlu1]).
- Control (MLU M1 pp. 52–54[^mlu1]): "The pilot commands SCAN interrogations by depressing TMS left for less than 1/2
  second"; "Depressing TMS left for 1/2 second or more commands LOS interrogations". SCAN covers ±60° azimuth and
  elevation; LOS covers ±15° azimuth about the FCR cursor. The M3 tape moved the split to 0.6 s (MLU M3 p. 10[^mlu3]).
- Display (MLU M1 p. 53[^mlu1]): "The green circles denote 'friendly' replies and yellow squares indicate responses that
  are of an 'unknown' nature." "Interrogation replies are always displayed on the FCR A-A MFD format and may be
  selected to appear on the … HSD." During a SCAN interrogation the FCR blanks its own targets and track files.
- Correlation (MLU M3 p. 167[^mlu3]): "The AIFF can interrogate a target; however, the response (or lack of response) is
  not correlated to a target track. The pilot must make his own assessment".
- HUD: the dash-34 HUD chapter (§ F-16C/D above) has no IFF symbol.
- Timing (simulator: Chuck's DCS F-16C guide pp. 643–644[^chucks]): "If the contact is friendly, a green circle is drawn
  around the contact for three seconds"; "If no reply is received, no indication is displayed". DCS draws the circle on
  the track; the real guide draws it at the reply's own position.

**F-15A/C.**
- Control (TO 1F-15A-1 fig. 1-2 sheet 1, p. 1-5[^f15-1]): "IFF INTERROGATE & AIM-9L MANUAL BORESIGHT BUTTON — INITIATES
  SELECTED IFF MODE". With MSIP grips (sheet 2, p. 1-6), the multi-function (coolie) switch: "(LEFT) IFF
  INTERROGATE", momentary, "MUST BE HELD FOR CONTACT".
- The interrogator panel on the left console provides "air-to-air (AAI) target identification" (-1 pp. 1-80/81[^f15-1]).
  Its display is described in TO 1F-15A/C-34-1-1, which is not public.
- Display (simulator: Falcon BMS TO 1F-15C-34-1-1 §16, p. 83[^bms-f15]): the AAI "generates display symbols on the VSD
  at the correct target range and azimuth position". "A high confidence (HC) return is indicated by a O symbol, a low
  confidence (LC) return is indicated by a ◊." At long range a reply is hard to match to its track.
- HUD: the public HUD descriptions (the -1, NADC 1976) have no IFF symbol.

**F-4E.**
- Sets (TO 1F-4E-1, 1979[^f4e-1]): "AN/APX-81 interrogator set before TO 1F-4E-587 or … the APX-80 interrogator set
  after"; change 1F-4E-587 "Adds AN/APX-80 A/A IFF". The display is in TO 1F-4C-34-1-1-2, which is not public. The
  foldout panel legend lists an "INTERROGATOR PUSH BUTTON (SOME AIRCRAFT)" among the rear cockpit's radar controls.
- Display (simulator: Heatblur DCS F-4E manual, identification systems[^heatblur-iff]): the WSO challenges with a button
  on the antenna hand control. "The radar screen presents the results of the interrogation with lines around the
  contacts position": a line above = a matching transponder mode, a line below = a matching code.
- The ASG-26 sight shows no IFF (§ F-4E Kurnass above).

**F-35.**
- Code One, J. Kent, "The New Front Office", 2006[^codeone-kent]: "Symbols on the tactical display appear green if the
  aircraft's sensors or off-board assets determine these objects are friendly. If unknown to the sensors, objects
  appear yellow. If identified as potential adversaries, objects appear red."
- M. Skaff (Lockheed Martin), "The Impact of Advanced Fusion in 5th Generation Fighters", 2013, as quoted on
  f-16.net[^skaff]: "red diamonds, green circles, and yellow squares correspond to foe, friend, and suspect."
- Not public: whether the pilot starts an interrogation, and the track shapes on the green helmet display.

**Kurnass 2000, Kfir, Lavi, Mirage IIICJ.** No public document describes an interrogator or an IFF display for these
jets. Searched: flight-manual text, Jane's, Flight International, IAI / Elbit material, simulator communities.

### Build plan (user decisions 2026-10-17; not built yet)

Only from the findings above, under the Real HUD switch only; the original HUD's friendly X and the original radar
page stay as they are.
- **Every HUD, sight and helmet**: no friend mark (as today). No public source puts IFF on any of these displays.
- **F-15C**: an interrogate key (the throttle button; a new, unused key). While the key is held, reply symbols on the
  radar page at each friendly reply's range and azimuth: a circle (high confidence). No symbol for a unit that does not
  reply. A reply stays 3 s after release (ours; the only figure found is a simulator guide's[^chucks]; goes in
  docs/deviations.md).
- **F-4E (Kurnass)**: the game has no back seat, so the WSO's interrogation is automatic. The virtual WSO
  interrogates each new radar contact once and the locked contact every few seconds; the replies show on the radar
  page as a line above and a line below the friendly contact (matching mode and code), for the F-15's display time.
  The interrogate key also works (the pilot asking the WSO). The automatic timing is ours and goes in
  docs/deviations.md.
- **F-16**: the game's F-16D is the early-1990s Barak, which had no interrogator: its HUD and radar page stay as they
  are. Today's IAF F-16s have one, so AIFF (the APX-113 class: TMS left, green circle / yellow square on the FCR, as
  in the MLU guides above) comes with the modern F-16's own switch ([f16i.md](f16i.md) §3).
- **F-35I**: the helmet stays monochrome green with one target designator for every locked contact, as on the real
  jet. The friend / unknown / hostile colours and shapes belong on the panoramic display's radar and map formats, so
  they come with the Real MFDs (docs/roadmap.md "Real MFDs"), drawn in the real formats, not added to today's pages.
- **Kurnass 2000, Kfir, Lavi, Mirage IIICJ**: nothing, and the pilot guides say the jet has no IFF display.

## Pull-up and break marks, and the dive / height voice (per jet)

With the Real HUD each jet shows the pull-up / break mark of the real aircraft, and speaks the dive and height calls
of the real aircraft's voice system (the voice research: [real-betty.md](real-betty.md)). The original HUD keeps the
game's rule (docs/cockpit.md "break X", docs/sound.md §4).

| Jet | HUD mark | Dive / height voice |
| --- | --- | --- |
| F-16 | the break X: flashing at the GAAF advisory in every master mode; steady in the A-A missile modes inside Rmin[^dash34brk]; the pull-up anticipation U rising to the flight path marker in the A-G modes[^dash34brk]; `AL` flashing below ALOW[^dash34alow] | "PULL UP – PULL UP" at the GAAF advisory[^dash34gaaf]; "ALTITUDE – ALTITUDE" below the ALOW height[^dash34alow], 300 ft by default[^betty] |
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
- The pull-up anticipation cue[^dash34brk] (`f16.rs` `pullup_cue`): a U under the flight path marker in the A-G
  modes. It rises toward the marker as the jet dives and cups it at the GAAF advisory, with the break X (fig. 1-212).
  The real cue also rises for the weapon release's minimum (fuze arming) height, with `LOW` beside the marker; the
  game has no fuze arming height, so ours follows the GAAF advisory only. Inferred (the manual gives no scale): 10 mr
  below the marker's circle per second to the advisory, shown over the last 10 s (the delayed CCIP solution cue's
  scale); 24 mr wide with 3 mr ends, about the marker's span in fig. 1-212; level on the HUD.
- Not built: the LOW mnemonic; the MFD break X.

CARA ALOW (`gaaf::alow`)[^dash34alow]: below the ALOW height; it stops above it, climbing faster than 1,200 fpm, with
the gear handle down, or below 15 ft. Ours repeats the call every 4 s (the game's Betty period; inferred).
On the HUD (`gaaf::alow_hud`)[^dash34alow]: the `AL` mnemonic and its readout (`AL 300`, one row under the radar
altitude, fig. 1-115) flash below the ALOW height; they stop above it, climbing faster than 1,200 fpm or below 70 kt
(the gear does not stop them). Ours flashes at 2 Hz, as the break X; the ALOW height stays 300 ft (no DED to set it).

## Real view (the real field of view)
Extras → "Real HUD view": Original (1998) / Real field of view. It acts with HUD Real only.
- **Original view:** 50° across the 640 px screen (about 12 px per degree; cockpit.md "3D view"). At that scale each
  cockpit's HUD glass spans about 11° × 11°, less than the real HUDs' fields.
- **Real field of view:** the cockpit view widens so that the jet's real instantaneous field of view (IFOV, what the
  pilot sees through the glass from the design eye) fits the glass, centred on the HUD centre (inferred: no source
  gives each FOV centre's place against the glass). The symbols stay on the world, and the F-16's bank scale sits at
  its real place. The panel art keeps its size; only the 3D view and the symbols' scale change.
  - Code: `Jet::fov_deg` / `Jet::real_view_px_per_deg` (`real_hud/mod.rs`) → `IafRealHud.real_view_px_per_deg` →
    `cockpit.gd` `focal_length()`. The HUD layout's boresight and gun cross move with it (`cockpit.gd` `view_y`), so
    they keep pointing where they did.
- **Looking around:** the Real view holds with the head forward only. As the head turns (snap views, free look,
  padlock), the view blends back to the original 50°, reached at 20° of head yaw or pitch (`cockpit.gd`
  `REAL_VIEW_HEAD_DEG`), where the HUD glass has left the screen (the panel pans 1920 px per 90°). The look-around
  views then show the cockpit model (`*_bc`) from the original eye at the original scale.

| Jet | IFOV across × up | Basis |
|---|---|---|
| F-16C/D | 20° × 13.5° (25° total, cut 10.5° below its centre) | the wide-angle conventional HUD of the Block 25 / 30 F-16C/D[^roch-f16cd]; dash-34[^dash34fov] |
| Lavi, Kurnass 2000 | 30° × 18° | inferred: a wide-angle diffractive HUD of the time (the F-16 LANTIRN HUD's 30° × 18°[^roch-lantirn][^fisher85]) |
| MiG-29 9.12 | 13° × 18° | ИЛС-31 at 600 mm from the eye, a simulator manual[^ea29] |
| F-15A/C, Kfir, MiG-23ML, F-4E, Mirage IIICJ | 17.8° × 12° | open: inferred from a typical single-combiner refractive HUD[^avhandbook-hud] |
| F-35I | — (the helmet's 40° × 30°: the original view stays) | Collins datasheet[^collins-hmds] |

Until 2026-10-26 the F-35I took the F-16's Real view by mistake: `cockpit.gd` `focal_length()` passed only the cockpit
folder's last part, and the F-35I's (`res://extra/planes/f35i/cockpit`) ends in `cockpit`, which `Jet::of_cockpit`
reads as the F-16. The view widened and the eye seemed to move between Real view off and on. It now passes the whole
path (`test_hud.gd` checks it).

Until 2026-10-28 the Real view held in every cockpit view. Looking back over the canopy of an F-16, the wider view
drew the seat and canopy frame smaller, as if further back, and showed the dark cut-off floor under the seat, below
the part of the `f16_bc` model the original view shows. `test_hud.gd` and `test_views.gd` check the back view's
focal length and eye.

With Real view the view is wider (the F-16's about 78° across, the Lavi's about 88°), so the GPU draws more of the
world. Measured on the Intel Iris Xe (2026-10-26, `_flight_bench.gd`, mission 311's F-16 at 1485×1041, default
graphics, warm runs): +0.06 ms a frame at 150 m, +0.67 ms (5 %) at 1,500 m, +1.37 ms (8 %) at 6,000 m; about 20 % more
primitives and 12 % more draw calls.

## GPS bombs (JDAM, GBU-39; ours)

A GPS bomb flies to coordinates, PRE (pre-planned on the briefing TSD) or VIS (designated in flight), and may be
released anywhere inside its launch acceptability region (LAR; docs/weapons.md §13.2–§13.3). The F-16's JDAM
symbology comes from the simulators' manuals and their users (secondary sources[^dcs-jdam][^bms-jdam]); the layout
details are inferred. The F-15 and the F-35I's helmet draw the same set (their own JDAM symbology is not public;
inferred). Built in `real_hud/mod.rs` `gps_cues`, drawn while a GPS bomb has an aim (HUD modes 5 / 6):

| symbol | what it shows | F-16 | F-15 | F-35I helmet |
|---|---|---|---|---|
| TD box (4 mr half) | the aim, held at the field's edge with an X over it when outside | yes | yes | yes, also looking aside |
| azimuth steering line | through the aim along the rolled vertical; the pilot puts the flight path marker on it | yes | yes | yes |
| LAR staple | a bracket from Rmin to Rmax opening left, 0 at the bottom, the scale's NM (5 / 10 / 20 / 40 / 80) above it | where the DLZ goes, the altitude scale moved out | where the range scale goes | right of centre, as its DLZ |
| range caret | the ground distance to the aim, left of the staple | yes | yes | yes |
| `TMR m:ss` / `IN RNG` | under the staple: the time to Rmax while closing, then in range | yes | yes | yes |
| PRE / VIS | the mode | the weapon window (instead of CCIP) | under the G | the weapon line (`1 PRE`) |
| `TTI m:ss` | after the release, the last released bomb's time to impact until it bursts, in every HUD mode (docs/weapons.md §13.3) | the right column's time row, in place of the steerpoint's time | the time row under the steerpoint (instead of `N MIN`) | the time row under the steerpoint, also looking aside |

The real F-16 shows the released weapon's time to impact in a HUD window (secondary[^dcs-tti]); its row here is
inferred.

The CCIP pipper and the fall line are not drawn while the bomb has an aim. Open: the impact-angle in-zone bar and the
GBU-39's attack-azimuth LAR2 (no setting built).

## What ours draws (status)

This section lists, per jet, what the code draws and what it leaves out.

The cockpit art's glass is narrower than the real HUDs' field of view. On the F-16, F-15 and Lavi the scales and
data blocks sit 14 / 10 / 6 px in from the cockpit's HUD field (`Field::inset`), so the widest layout, the F-16's
A-A one with the altitude scale moved out for the DLZ, stays on the glass. Every block keeps its place relative to
its scale. The original HUD keeps the original layout.

- F-16: the NAV / A-A / A-G layout of figs. 1-110 / 1-111 / 1-115.
  - Drawn: the scales, boxes, the "C"; windows 3 / 4 / 5 / 7 / 8 / 10 / 13 / 14 / 25 / 26; `AL 300` (ALOW, below)
    under the radar altitude; the heading
    box low / high; the roll indicator; the bending ladder with the zenith star / nadir earth; FPM, AoA bracket,
    steerpoint diamond; TD box / locator line; AIM-9 reticle + seeker diamond; AIM-120 ASEC + ASC; DLZ with closure;
    CCIP / strafe pipper with the fall line; FUEL below the player's bingo (Extras "Real HUD bingo", 1,500 lb by
    default); SHOOT in its window (MLU; the AIM-9 / AIM-120 shoot cue).
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
  - The break X (GAAF and A-A inside Rmin), the pull-up anticipation cue and the ALOW readout ("Pull-up and break
    marks" above).
  - Not drawn: the VVI (vertical velocity indicator) scale (ours: the VAH switch position), DTOS / CCRP (the game has
    no such modes), BATR / FEDS, the AUTO altitude scale below 1,200 ft, the LOW mnemonic (the game has no fuze
    arming height).
- F-15: tapes, heading, ladder with the zenith ⊖ "90" / nadir ⊗, velocity vector, -W-, gun cross when armed, G, Mach
  in A-A, NAV window, TD box, ASE circle + dot, range scale + IN RNG, breakaway X inside Rmin, LCOS reticle with the
  range arc, bomb fall line to the target square, AoA scale gear down (ours: degrees as units), NAV bank steering bar
  (ours: 2 px per degree of bearing error), the ILS flight director (below). Not drawn: Mach outside A-A, `CSET`,
  `MKR` (the game has no marker beacons).
  - ILS, NAV with the gear down (the game's ILS is always on there): `ILS-N` in the NAV window; the bank steering bar
    follows the localizer; `GSUP` / `GSDN` under the window within 0.6° of the glide slope; at its centre (within
    1 px, 1/12°; inferred) the glide slope is captured and the pitch steering bar joins the cross until the jet leaves
    the 0.6° band or the ILS display (inferred: the manual gives no release). The bars sit off the aircraft symbol by
    the game's ILS deviations, 12 px per degree (inferred: the manual gives no scale). The original's ILS lines are
    not drawn on this HUD.
- Kfir (`kfir.rs`), Kurnass 2000 (`k2000.rs`), MiG-23 (`mig23.rs`), MiG-29 (`mig29.rs`): everything in "Ours" of
  their sections above; what those sections mark "not drawn" stays out.
- Lavi (`lavi.rs`): everything in its section above, with the bank scale and the ILS needles (the original's ILS
  lines are not drawn on this HUD). Not drawn: a VVI.
- The other Real HUDs (F-16, Kfir, Kurnass 2000, MiGs, F-35) keep the original's ILS lines over them.
- F-4E / Mirage (`sights.rs`): the reticles as specified (ours: the reticle rides the LCOS / CCIP pipper).
- Reticle pen (F-4E, Mirage, MiG-23; `hud.gd` `real_reticle`, 2026-10-26): these sights are a few thin lines at their
  real angular size (the F-4E's outer ring 50 mr, about 2.9°), drawn at the HUD's 0.6 px pen they all but vanished
  against a bright sky. They draw at 1.8 times that pen (about 2.4 px at 1080 rows), near a reflector reticle's 1 mr
  line (inferred). Considered and dropped: a dark outline (a combiner only adds light, it cannot darken the sky) and
  larger reticles (the sizes are the real ones).
- F-35 (`f35.rs`): the forward virtual HUD and the off-boresight head set; the gun / A-G graphics are the F-16's
  (reconstruction).
- DASH (`dash.rs`): in the F-16 / F-15 cockpits only (the MiG-29 has its Щель-3УМ); the Lavi and Kurnass 2000 keep
  the original's helmet display, the MiG-23 draws none (no helmet sight); the Kfir, F-4E and Mirage cockpits have no
  helmet display (`[HUD] Dash` 0), so their sight pans away with the glass.
  - When: looking aside with the Real HUD on (the original's dash condition: the panel panned ≥ 250 px aside or
    ≥ 200 px down).
  - Drawn in green, around the helmet's line of sight: the aiming cross, the line-of-sight circle with its gap, G /
    airspeed / ARM or NAV / the weapon, altitude / steerpoint, the head's heading, the TD box and the seeker diamond
    inside the 20° field.
  - The heading sits above the cross: the cockpit view's centre is low on the screen, so the JHMCS's bottom position
    would fall off it.
  - Not drawn: a horizon, shoot cue, RWR (radar warning receiver) symbols, declutter. Blanking is implied: the helmet
    set shows only while looking aside.

[^dash34]: T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997: HUD
    chapter pp. 1-158..1-183 (fig. 1-115 "HUD Window and Scale Positions"), A-A gun pp. 403-411, A-A missiles
    pp. 413-423, A-G pp. 441-458: https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^dash1]: T.O. GR1F-16CJ-1, Hellenic AF F-16C/D flight manual (dash-1): AoA bracket, ILS:
    https://falcon.blu3wolf.com/Docs/HAF-F16.pdf
[^mlu1]: Lockheed Martin F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998): AN/APX-113 AIFF
    pp. 49–55, fig. 1-54 "AIFF Controls and Symbology": https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^mlu2]: Lockheed Martin F-16 MLU tape M2 pilot's guide: https://falcon.blu3wolf.com/Docs/MLU_M2.pdf
[^mlu3]: Lockheed Martin F-16 MLU tape M3 pilot's guide (16PR16226, 2004): https://falcon.blu3wolf.com/Docs/MLU_M3.pdf
[^rokaf]: RoKAF AFTTP 3-3 Vol 5, F-16C Basic Employment Manual (2005): EEGS, CCIP employment:
    https://falcon.blu3wolf.com/Docs/Basic-Employment-Manual-F-16C-RoKAF.pdf
[^mch]: MCH 11-F16 Vol 5, Combat Aircraft Fundamentals (1996):
    https://falcon.blu3wolf.com/Docs/F-16%20COMBAT%20AIRCRAFT%20FUNDAMENTALS%20-%20Multi-Command%20Handbook%2011-F16%20Vol5.pdf
[^f16net]: f-16.net pilot / test-pilot discussions (bending ladder bars, ghost horizon):
    https://www.f-16.net/forum/viewtopic.php?t=5116
[^falconpedia]: Falconpedia, "HUD", simulator documentation (Falcon 4): http://falcon4.wikidot.com/avionics:hud
[^fg-hud]: NikolaiVChr, FlightGear F-16 HUD wiki, simulator documentation: https://github.com/NikolaiVChr/f16/wiki/HUD
[^f15-1]: TO 1F-15A-1, F-15A/B/C/D flight manual (15 Jan 1984): "Navigation Head-Up Displays" pp. 1-65ff, figs. 1-14
    (NAV HUD) and 1-15 (ILS HUD); fig. 1-2 sheets 1–2 pp. 1-5 / 1-6 (interrogate button / coolie), pp. 1-80/81
    (interrogator set): https://archive.org/details/f-15-manual
[^nadc]: NADC-75267-40, "Head-Up Display Symbology" (1976), DTIC ADA022655: per-aircraft HUD symbology tables and
    figures: https://archive.org/details/DTIC_ADA022655
[^twz-f15]: The War Zone, F-15C pilot account (ASE circle, steering dot, TD box):
    https://www.twz.com/35765/confessions-of-an-f-15-eagle-driver-with-three-mig-kills
[^bms-f15]: Falcon BMS TO 1F-15C-34-1-1, a simulator manual (§16 p. 83: the VSD reply symbols):
    https://cdn.falcon-bms.com/docs/4.37/TO%201F-15C-34-1-1%20BMS.pdf
[^heatblur-lcoss]: Heatblur DCS F-4E manual, "LCOSS", a simulator manual paraphrasing T.O. 1F-4E-1 / -34:
    https://f4.manuals.heatblur.se/systems/weapon_systems/lcoss.html
[^heatblur-bit]: Heatblur DCS F-4E manual, optical sight BIT procedure, a simulator manual:
    https://f4.manuals.heatblur.se/procedures/bit_tests/optical_sight.html
[^heatblur-iff]: Heatblur DCS F-4E manual, identification systems, a simulator manual (APX-76 / Combat Tree reply
    lines): https://f4.manuals.heatblur.se/systems/identification_systems.html
[^f4e-1]: TO 1F-4E-1 flight manual (1979): AN/APX-80 / 81 interrogator sets, TO 1F-4E-587, p. 4-19, foldout FO-10:
    https://archive.org/details/f-4e-1-flight-manual
[^baugher-f4e]: Joe Baugher, F-4E: https://www.joebaugher.com/usaf_fighters/f4_11.html
[^flyandwire]: flyandwire.com (F-4E).
[^baugher-k2000]: Joe Baugher, Kurnass 2000: https://www.aircraftinformation.info/JB_AIF/usaf_fighters/f4_35.html
[^airvectors]: airvectors, F-4 Phantom: http://www.airvectors.net/avf4_4.html
[^warmachines]: warmachinesdrawn, "McDonnell Douglas F-4E Kurnass 2000":
    https://warmachinesdrawn.blogspot.com/2017/06/mcdonnell-douglas-f-4e-kurnass-2000.html
[^globalsecurity-k2000]: GlobalSecurity, "Kurnass 2000": https://www.globalsecurity.org/military/world/israel/kurnass-2000.htm
[^elbit-ihud]: Elbit Systems, F-16 I-HUD (the wide-angle family of the F-4E-2020's El-Op 976):
    https://elbitsystems.com/media/f-16_I-HUD2_2022.pdf
[^flight1983]: Flight International, 27 Aug 1983, p. 542, "Smart nav/attack system for Kfir" (Elbit System 82 WDNS):
    https://cdnc.heyzine.com/files/uploaded/v3/3c1262af2443f80fe2c7293f1cedb885c62cfe96.pdf
[^janes-kfir]: Jane's All the World's Aircraft, IAI Kfir (C7, WDNS-341, System 82):
    https://janes.migavia.com/?view=article&id=155:kfir
[^wt-kfir]: War Thunder forum research thread on the Kfir (System 82 modes, Colombian C7 HUD footage):
    https://forum.warthunder.com/t/kfir-aircraft-c-1-c-10-blk-60-from-cub-to-lion-discussion-analysis-and-research/285880
[^militaryfactory]: militaryfactory, IAI Kfir: https://www.militaryfactory.com/aircraft/detail.php?aircraft_id=152
[^milavia]: milavia, IAI Kfir: https://www.milavia.net/aircraft/kfir/kfir.htm
[^forecast]: Forecast International archive, Kfir: https://www.forecastinternational.com/archive/disp_old_pdf.cfm?ARC_ID=1014
[^raaf]: RAAF AAP 7213.003-1, Mirage IIIO / IIID Flight Manual (1978): CSF 97K sight pp. 1-109..1-121, figs.
    1-60..1-73: https://aviationarchives.blogspot.com/2023/03/australia-dassault-mirage-iiio-and-iiid.html (Avialogs
    listing: https://www.avialogs.com/aircraft-d/dassault/item/2766-aap-7213003-1-flight-manual-mirage-iiio-and-iiid)
[^aloni]: Shlomo Aloni, *Mirage III vs MiG-21* (Osprey 2010) and *Israeli Mirage III and Nesher Aces* (Osprey 2004),
    via Hebrew Wikipedia "מיראז' 3": https://he.wikipedia.org/wiki/%D7%9E%D7%99%D7%A8%D7%90%D7%96%27_3
[^callaway]: Tim Callaway, *Dassault Mirage III/5* (Aviation Classics 17, 2012).
[^lm-slides]: Lockheed Martin, "The F-35 Cockpit" slides (c. 2012): "Virtual HUD Looking Forward", "HMD Looking Behind
    the Aircraft": http://www.slideshare.net/robbinlaird/the-f35-cockpit/download (images mirrored on f-16.net:
    https://www.f-16.net/forum/viewtopic.php?t=16223&start=180)
[^twz-f35]: The War Zone, US Navy flight-test helmet-display videos:
    https://www.twz.com/12297/navy-presents-new-f-35-helmet-display-videos-and-flight-test-dangers and the HMS Queen
    Elizabeth landing: https://www.twz.com/29569/check-out-this-f-35-helmet-display-video-of-a-rolling-landing-on-the-hms-queen-elizabeth
[^collins]: Collins Aerospace, F-35 Gen III HMDS datasheet: https://prd-sc102-cdn.rtx.com/-/media/ca/f/f35/jsf-f35-datasheet.pdf
[^avtoday]: Aviation Today, "Such a Capable Helmet" (2010): https://www.aviationtoday.com/2010/07/01/such-a-capable-helmet/
    and "F-35 Gen III Helmet" (2015):
    https://www.aviationtoday.com/2015/09/04/f-35-gen-iii-helmet-a-generational-leap-in-technology/
[^codeone-sight]: Code One, "Lightning Sight": http://www.codeonemagazine.com/article.html?item_id=12
[^sldinfo]: SLDinfo, F-35 cockpit overview:
    https://sldinfo.com/whitepapers/an-overview-of-the-f-35-cockpit-what-5th-generation-aircraft-are-all-about/
[^dote-gun]: DOT&E on the F-35 gun symbology, via The War Zone:
    https://www.twz.com/air/f-35as-beleaguered-25mm-cannon-is-finally-effective
[^natint]: National Interest, the F-35I helmet:
    https://nationalinterest.org/blog/buzz/israels-unique-f-35-variant-comes-with-unique-combat-helmet-ps-031326
[^codeone-kent]: Code One, J. Kent, "The New Front Office" (2006), track colours:
    https://www.codeonemagazine.com/u2_article.html?item_id=35
[^skaff]: M. Skaff (Lockheed Martin), "The Impact of Advanced Fusion in 5th Generation Fighters" (2013), track shapes,
    quoted on f-16.net: https://www.f-16.net/forum/viewtopic.php?f=22&t=29126
[^apx113]: Lockheed Martin releases and f-16.net on the AN/APX-113 for the USAF F-16C/D (no link recorded).
[^deurenberg]: Ruud Deurenberg, *IAI Lavi* (citing Flight International / Jane's): https://www.dror-aero.com/pro/lavi5.pdf
[^wiki-lavi]: Wikipedia, "IAI Lavi".
[^dokumen-lavi]: dokumen.pub, *Lavi*.
[^rochester]: Rochester Avionic Archives, "Wide Angle Raster HUD".
[^roch-f16cd]: Rochester Avionic Archives, "F-16C/D HUD Pilot's Display Unit" ("a 25 degree Total Field of View and a
    20 degree by 13.5 degree Instantaneous Field of View"; the wide-angle conventional optic, an interim design while
    the LANTIRN HUD was late): https://rochesteravionicarchives.co.uk/items/f-16-c-d-hud-pilot-s-display-unit-1
[^dash34fov]: T.O. GR1F-16CJ-34-1-1 (1997), p. 1-156: "a total field of view of 25 degrees in diameter and is limited
    at the bottom along a line of 10.5 degrees below the center of the total field of view":
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^roch-lantirn]: Rochester Avionic Archives, "F-16 LANTIRN Diffractive HUD Pilot's Display Unit" (18° vertically,
    30° horizontally): https://rochesteravionicarchives.co.uk/items/f-16-lantirn-diffractive-hud-pilot-s-display-unit
[^fisher85]: J. F. Fisher, "Wide Angle Raster Head Up Display", GEC Avionics, 1985 (refractive limit about 20° × 15°;
    diffractive 30° × 18°): https://rochesteravionicarchives.co.uk/items/wide-angle-raster-head-up-display
[^avhandbook-hud]: R. B. Wood, P. J. Howells, The Avionics Handbook, ch. 4 "Head-Up Displays", table 4.1 (CRC 2001):
    typical single-combiner refractive HUD 17.8° × 12° IFOV, 20–25° total:
    http://helitavia.com/avionics/TheAvionicsHandbook_Cap_4.pdf
[^collins-hmds]: Collins Aerospace, F-35 Gen III HMDS datasheet ("Field of view: 40H x 30V degree"):
    https://prd-sc102-cdn.rtx.com/-/media/ca/f/f35/jsf-f35-datasheet.pdf
[^ausairpower-hmd]: Air Power Australia, "Helmet Mounted Sights and Displays" (DASH GEN I–III fielding, 20° FoV, green
    calligraphic symbology, boxed target / seeker diamond): https://www.ausairpower.net/hmd-technology.html
[^ausairpower-python4]: Air Power Australia, Rafael Python 4: https://www.ausairpower.net/TE-Gen-4-AAM-97.html
[^avhandbook]: The Avionics Handbook, ch. 5 "Head-Mounted Displays" (CRC 2001): DASH for the Python 4 (1993–94); JHMCS
    look-to / shoot cues, altitude, airspeed, heading, horizon; 20° FoV:
    https://helitavia.com/avionics/TheAvionicsHandbook_Cap_5.pdf
[^elbit-vsi]: Elbit / VSI: the Elbit–Kaiser tie-up (Flight): https://flightglobal.com/elbit/kaiser-tie-up/10418.article;
    VSI JHMCS contracts (2004):
    https://www.securityinfowatch.com/home/article/10553909/elbit-systems-joint-venture-with-rockwell-collins-vsi-awarded-jhmcs-contracts-valued-at-more-than-60-million;
    Israeli helmets for US pilots (Israel21c):
    https://archive.israel21c.org/israeli-company-to-supply-u-s-fighter-pilots-with-seeing-eye-helmets/
[^twz-dash]: The War Zone, IAF F-15 Baz cockpit / DASH:
    https://www.twz.com/f-15a-baz-upgraded-cockpit-seen-in-rare-israeli-air-force-photo and Python training rounds and
    the DASH: https://www.twz.com/israeli-python-training-missiles-are-cleverly-disguised-as-u-s-sidewinders
[^globalsecurity-dash]: GlobalSecurity, on the DASH (no link recorded).
[^raytheon-9x-hobs]: Flight International, "Raytheon test-fires fourth AIM-9X" (the helmet sight directs the seeker,
    which acquires the target at high off-boresight angles):
    https://www.flightglobal.com/raytheon-test-fires-fourth-aim-9x/31692.article
[^jhmcs-hobs]: Military & Aerospace Electronics, JHMCS production (the JHMCS cues the AIM-9X's high off-boresight
    shots):
    https://www.militaryaerospace.com/communications/article/16719516/boeing-scores-another-air-force-production-contract-for-joint-helmet-mounted-cueing-system
[^gs-python5]: GlobalSecurity, Python 5 (lock-on before and after launch, full sphere, very high off-boresight seeker):
    https://www.globalsecurity.org/military/world/israel/python5.htm
[^aft-python5]: Airforce Technology, Python 5 (LOAL: the launcher passes the target data, the seeker then scans and
    locks): https://www.airforce-technology.com/?p=4169
[^chucks]: Chuck's Guides, DCS F-16C Viper guide, a simulator guide: §4.3 HMD symbology / setup (the JHMCS F-16 set);
    pp. 643–644 (IFF reply timing): https://assets.chucksguides.com/pdf/DCS%20F-16C%20Viper%20Guide.pdf
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
[^dcs-jdam]: DCS forum, "JDAM help" (2022), secondary: the time to max range then `IN RNG` on the right, release while
    the caret is inside the LAR's long bar: <https://forum.dcs.world/topic/291870-jadam-help/>
[^bms-jdam]: Falcon BMS forum, secondary: the range cue "on the right side of the HUD"
    (<https://forum.falcon-bms.com/topic/25722/disappearing-and-appearing-bombing-range-cue>); LAR2 with an attack
    azimuth (<https://forum.falcon-bms.com/post/390232>)
[^dcs-tti]: DCS forum, "CBU-105 HUD symbology question" (2022), secondary: the F-16's HUD window for the JDAM, JSOW,
    WCMD and Paveway III shows the time to impact after the release
    (<https://forum.dcs.world/topic/304597-cbu-105-hud-symbology-question>)
