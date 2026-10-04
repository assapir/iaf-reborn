# Real HUD: per-aircraft reference (Extras > HUD)

The Real HUD replaces the original 1998 HUD with each jet's real sight / HUD / helmet symbology. This file is the
reference the code (`crates/iaf-avionics/src/real_hud.rs`) is built from: per aircraft, what is shown, where, in what
format, and how sure we are. Researched October 2026 from public sources; no source images are kept in the repo.

Confidence tags: **[V]** verified from a real-world document or footage; **[S]** secondary (book / encyclopedia /
pilot account citing real sources); **[SIM]** only from a simulator manual (used for detail where the real source
agrees in outline); **[R]** our reconstruction (nothing public; inferred from the era / maker, marked as such in
docs/deviations.md).

Units: 1 mr (milliradian) = 0.0573°; HUD positions as angles from the boresight (gun cross).

| Jet | Cockpit dir | Real display | Basis |
|---|---|---|---|
| F-16C/D (Barak) | `f16` | F-16 Block 30/40/50 HUD | dash-34 manual [V] |
| Lavi | `lavi` | the F-16's (Lavi symbology not public; Hughes wide-angle HUD, Elbit displays) | [R] = F-16 |
| F-15A/C (Baz) | `f15` | F-15A/C HUD (no digital boxes) | TO 1F-15A-1 + NADC 1976 [V] |
| F-4E (Kurnass) | `phantom` | AN/ASG-26 lead-computing optical sight (no HUD) | T.O.-derived [V/SIM] |
| F-4E 2000 (Kurnass 2000) | `f4-2000` | Kaiser wide-angle HUD; symbology not public | [R] F-16-style |
| Kfir C2/C7 | `cfir` | El-Op HUD with Elbit WDNS; symbology not public | [R] |
| Mirage IIICJ (Shahak) | `mirage` | CSF 95 gyro gunsight (reflector, no HUD) | CSF 97K manual drawings [V] + IAF books [S] |
| F-35I (Adir) | `extra/planes/f35i` | Gen III helmet display (no HUD) | LM slides + flight-test video [V] |

## F-16C/D (Block 30/40/50)

Sources: T.O. GR1F-16CJ-34-1-1 (Hellenic AF Block 50 dash-34, 1997) HUD chapter pp. 1-158..1-183, A-A pp. 403-423,
A-G pp. 441-458 (https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf); T.O. GR1F-16CJ-1 (dash-1); Lockheed MLU pilot's
guides M1-M3 (https://falcon.blu3wolf.com/Docs/MLU_M3.pdf); RoKAF AFTTP 3-3 Vol 5 F-16C Basic Employment Manual
(https://falcon.blu3wolf.com/Docs/Basic-Employment-Manual-F-16C-RoKAF.pdf); f-16.net pilot / test-pilot accounts.
The D is the two-seater with the same HUD (rear cockpit repeater). Barak-specific differences: none public.

**Scales** [V]
- Airspeed: left, moving tape, tick per 10 kt, labels every 50 kt in tens (`50` = 500). Fixed index with a boxed
  readout `[450]` and a caret at the tape; mnemonic `C` / `T` / `G` beside it (CAS always gear down / DGFT).
- Altitude: right, moving tape, tick per 100 ft, labels every 500 ft in hundreds with a thousands comma (`20,5`);
  index box `[20,000]` (last digit 0). Gear down ×5 expanded (20 ft ticks). Radar altitude box `R 19,500` and
  `AL 200` (ALOW) below it; AUTO scale below 1,200 ft: 0-1,500 ft thermometer, `AR` on the index, `AL` flashes below
  ALOW. When the A-A DLZ appears the altitude scale moves outward.
- Heading: **bottom of the HUD in NAV**, top in A-G modes (but strafe); 50 mr above the FPM gear down. Ticks 5°,
  labels every 10° in tens (`06 [070] 08`, boxed current heading).
- Vertical velocity (VV/VAH switch): fixed scale inboard of the altitude scale, moving triangle, ticks 500 fpm.
- Roll indicator: tics on a 70 mr arc centred 50 mr below the FOV centre, every 10° to ±45°.
**Ladder / markers** [V]
- Pitch ladder ("attitude bars") every 5° (±60°, compressed beyond); climb bars solid, dive bars dashed, tips toward
  the horizon, centre gap for the FPM, numbers at both ends; **bars bend toward the horizon increasingly with pitch**
  (test-pilot account + figure; the exact "half the angle" rule is MIL-STD-1787 convention [SIM]).
- FPM: 10 mr circle, 10 mr wings, 5 mr tail; X over it when limited.
- Gun / boresight cross: an incomplete plus at the fuselage reference line.
- AoA bracket gear down: FPM at its top = 11°, centre 13°, bottom 15° (dash-1).
- Steerpoint: a **6 mr diamond drawn on the ground at the steerpoint** (conformal); X when limited at the FOV edge.
**Data windows** (dash-34 fig 1-115) [V]
- Left column under the airspeed scale: `ARM` / `SIM`; Mach `0.96`; max G `4.1`; mode / weapon (`NAV`, `6 SRM`,
  `3 MRM`, `EEGS`, `LCOS`, `CCIP`, `DTOS`, `STRF`, ...); fuel / bingo.
- Top left above the airspeed scale: current G `1.0`.
- Centre: `WARN`, `FUEL` (flashing at bingo; MLU puts `SHOOT` in the same window).
- Right column under the altitude scale: `R xx,xxx`; `AL 200`; slant range with sensor letter (`B115.0` steerpoint,
  `F02.5` FCR, `F 060` = 6,000 ft below 1 NM); time (`MMM:SS` to steerpoint / release, closure in A-A gun);
  steerpoint `distance>number` (`020>03`).
**A-A missiles** [V]
- TD box 25 mr (segmented when coasting); off the HUD a 40 mr locator line from the gun cross with the angle.
- AIM-9 reticle 3° below the cross, 35 / 65 / 100 mr by seeker mode; seeker diamond; range tics and a range cue at
  1,000 ft per clock hour under 12,000 ft; target-aspect triangle (6 o'clock = tail).
- AIM-120: ASEC (breathing circle, max 56 mr radius at Rpi) with an 8 mr steering dot (ASC).
- DLZ: right, beside the altitude scale; top = radar range (80/40/20/10/5); target-range caret `>` with closure at its
  left (`804>`); Rmax1 / Rmin1 bracket, Rmax2 / Rmin2 thick maneuver bar; below: `A37` / `T09` times.
**A-A gun** [V]
- EEGS levels: I gun cross only; II funnel + MRGS lines (no lock); III + T-symbol and TD circle (range); IV funnel
  stiffens, MRGS removed (velocity); V + pipper (acceleration).
- Funnel: two curved lines, each midpoint the aim point at that range, width = the set wingspan at that range;
  top ≈ 600 ft, bottom ≈ 3,000 ft. TD circle: clock analog, 1,000 ft per hour, unwinds below 2 NM.
- LCOS (selectable): 1 mr pipper, 8 mr inner circle, 50 mr outer circle, range "L" at 1,000 ft per hour, closure
  caret, lag line.
**A-G** [V]
- CCIP: 1 mr dot in a 12 mr circle, bomb fall line from the FPM; out of the FOV: held ~14° below the cross with a
  time-delay cue; post-designate: steering line + solution cue to the FPM.
- DTOS: 10 mr TD box with a pipper; then steering line and solution cue; pull-up "U".
- CCRP: TD box, azimuth steering line, solution cue; `B004.9`, time to release.
- Strafe: CCIP-style pipper; in-range line 12 mr above it inside 4,000 ft; `STRF`.

## F-15A/C

Sources: TO 1F-15A-1 (15 Jan 1984) "Navigation Head-Up Displays" pp. 1-65ff, figs 1-14 / 1-15
(https://archive.org/details/f-15-manual); NADC-75267-40 "Head-Up Display Symbology" 1976 (DTIC ADA022655,
https://archive.org/details/DTIC_ADA022655); pilot account (https://www.twz.com/35765/); Falcon BMS F-15C -34 [SIM].
**No digital speed / altitude boxes**: moving tapes with fixed carets [V].
- Airspeed: left edge, **increasing downward**, 160 kt window, 10 kt ticks, labels every 50 kt (full value: `250`,
  `300`, `350`); fixed caret at the midpoint. Moves lower gear down.
- Altitude: right edge, increasing upward, 1,500 ft window, 100 ft ticks, labels every 500 ft (`3500`); fixed caret;
  barometric only (no radar altitude on the HUD). Gear down 300 ft window, 20 ft ticks.
- Heading: top edge between the scales, 30° window, two-digit labels (`26 27 28`), caret below pointing up.
- Ladder: 5° rungs to 30° (compressed beyond), no signs; climb solid with tips down and the number at the tip,
  dive dashed tips up; zenith ⊖ "90", nadir ⊗.
- Velocity vector: circle with wings and fin, flashes when caged / out of the FOV. Aircraft symbol `-W-` above it.
- Gun cross `+` only with Master Arm on.
- AoA scale gear down only: left, 0-45 units.
- G: lower left under the airspeed scale (`1.1G`; after the overload warning system: current and allowed G).
- Mach: under the airspeed scale, A-A modes only.
- NAV window lower right, three lines: `B   NAV` / `N 20.1` / `4 MIN` (destination + mode, range with source
  letter, minutes to go).
- Steering: a bank steering bar; ILS: a flight-director cross.
- A-A: TD box, ASE circle with a steering dot, a range scale inboard of the altitude scale (top = radar range,
  `320>` closure caret, two MAX and one MIN tick, `IN RNG`), breakaway X [V]. SHOOT is a light on the canopy bow,
  not HUD text [V].
- Gun: LCOS (no funnel) — outer ring with 12 ticks, dashed inner circle, centre pipper, thick range arc [V];
  1,000 ft per tick [SIM].
- A-G: no CCIP; bomb fall line from the velocity vector to a target square, pull-up bracket, release cue [V].

## F-4E Kurnass: AN/ASG-26 LCOSS (no HUD)

Sources: Heatblur DCS F-4E manual (paraphrasing T.O. 1F-4E-1/-34) https://f4.manuals.heatblur.se/systems/weapon_systems/lcoss.html
and the BIT procedure; Joe Baugher; flyandwire.com. Drawn **red**.
- Pipper 2 mr dot; inner ring 25 mr dashed; outer ring 50 mr solid; three roll tabs on the outer ring (bank, or WRCS
  steering) [V]; range bar inside the outer ring from 6 o'clock counter-clockwise **with a radar lock only**: guns
  1,000 ft at 6 o'clock + 1,000 ft per hour (max 6,667 ft); missiles 3,000 ft per hour (max 20,000 ft) [V].
- A/A: gyro lead with radar range (default 1,000 ft); missiles: reticle at the RBL (35 mr) for boresight lock.
- A/G: manual depression 0-245 mr (35 mr = gun cross), no CCIP [V].
- **No airspeed, altitude, heading or text** in the sight [V]. Missile status / IN RANGE / SHOOT are lights.

## F-4E 2000 (Kurnass 2000)

Sources: Joe Baugher, airvectors, warmachinesdrawn. Kaiser (El-Op) wide-angle HUD, said to show speed, altitude,
direction of flight and wind [S]; Elbit ACE-3 mission computer, HOTAS, HUD camera. **No symbology layout is public**:
ours is an F-16-style reconstruction [R], with a wind readout.

## Kfir C2/C7

Sources: Flight International 27 Aug 1983 p. 542 (Elbit System 82 WDNS) [V]; militaryfactory / milavia [S]. El-Op
HUD driven by the Elbit symbol generator; modes include LCOS and hotline (A-A gun), CCIP and direct / manual
(A-G), toss; airspeed, altitude, Mach, AoA and armament status shown [S]. **Layout not public**: ours is an
Elbit / F-16-era reconstruction [R].

## Mirage IIICJ Shahak: CSF 95 gyro sight (no HUD)

Sources: RAAF Mirage IIIO/IIID Flight Manual AAP 7213.003-1 (1978) pp. 1-109..1-121 (CSF 97K, dimensioned drawings)
[V]; Aloni, *Mirage III vs MiG-21* and *Israeli Mirage III and Nesher Aces* (Osprey) via Hebrew Wikipedia [S]. The
Shahak's CSF 95 lacks the 97's gyro horizon / heading [S].
- Moving reticle: 2.5 mr pipper dot inside a fixed 50 mr ring of 14 small diamonds; field of movement 9° from the
  fixed cross [V].
- Fixed cross 40 mr wide (vertical stub 10 mr up / down), an inverted V 40 mr above it [V].
- Guns: lead-computing; the IAF fed a pilot-selected range of 600 / 400 / 250 m (radar ranging unreliable) [S].
- Missiles: lock / in-zone lights in a column right of the glass (blue = lock) [S], not reticle symbols.
- Drawn as a lamp reflector sight: orange-red [R, period practice].

## F-35I Adir: Gen III helmet display (no HUD)

Sources: Lockheed Martin "The F-35 Cockpit" slides (c. 2012; https://www.f-16.net/forum/viewtopic.php?t=16223&start=180);
US Navy flight-test helmet video (https://www.twz.com/12297/); Collins datasheet; Aviation Today 2010 / 2015. Green,
40° × 30°. Forward: an aircraft-stabilised "virtual HUD" [V]:
- Heading tape at the top, boxed heading `[092]`, caret.
- Airspeed: **boxed number only**, left (`[382]`), no tape; under it `GS 515`, `M 0.84`, `G 1.0`, `α 1.6`, a bare
  number (max G, inferred).
- Altitude: boxed number right (`[19 067]`, small last three digits); under it vertical velocity `-1125` and radar
  altitude `R15060`.
- `-W-` waterline, horizon with a centre gap, ladder (climb solid tips down, dive dashed tips up, `-5`, `-10`
  numbered at the left), FPM with an energy caret.
- Bank scale at the bottom.
- Lower left: master mode `AA1`, weapon `2 AIM-A`, `ARM`.
- Lower right: TACAN `82X 11.8`, steerpoint `001 110/22.0` (number, bearing / range), time `00:02:33`.
- A-A: target designator (X over a circle), steering circle with a dot, a DLZ bracket with the range `27.4` under it,
  closure `495>`; designation cue held at the FOV edge.
- Gun (A-A funnel and pipper, A-G strafe) and A-G cues: exist, graphics not public [R].
- Off-boresight: the virtual HUD stays with the airframe; a reduced head-stabilised set (bare airspeed / altitude,
  heading, steerpoint, targets) [V].
