# The F-16's autopilot

The user, 18 November 2026: "yes but I guess the real autopilot will need an investigation and impl like real thing?"
and "do what ever you need". This page holds what public sources say about the F-16C/D's own autopilot (Block 40/50,
the Barak and the Sufa), and how the sim models it (`crates/iaf-flight/src/sixdof/autopilot.rs`, 2026-11-19).

The sim's other autopilot, the original game's (the A key: level, NAV, the landing circuit;
[docs/autopilot.md](../../../docs/autopilot.md)), stays as it was. While it flies, the F-16's PITCH switch stays at
A/P OFF.

## 1. What it is

The autopilot is a loop of the flight control computer (FLCC). It gives attitude hold, heading select and steering
select in roll, and attitude hold and altitude hold in pitch. Its data come from the INS and the central air data
computer over the avionics bus[^fm-135]. Its commands add to the stick's: "Since the autopilot command is additive to
stick commands, use of ALT HOLD in conjunction with high g maneuvering may result in aircraft overg"[^fm-62].

## 2. The controls

| control | where | positions and what they do |
|---|---|---|
| PITCH switch | MISC panel, the right one of the two | ALT HOLD: engages both axes; holds the altitude from the air data computer. A/P OFF: disengages both axes. ATT HOLD: engages both axes; holds the pitch attitude from the INS[^fm-134] |
| ROLL switch | MISC panel, left of PITCH | HDG SEL: turns to the heading set by the HSI's heading marker and holds it. ATT HOLD: holds the bank from the INS. STRG SEL: steers to the selected steerpoint. Works only while PITCH is out of A/P OFF[^fm-134] |
| paddle switch | the stick | interrupts the autopilot while it is held[^fm-129] |
| TRIM/AP DISC | MANUAL TRIM panel | DISC: the stick's TRIM button off, autopilot engagement prevented, the trim motors off (the trim wheels still work)[^fm-131] |
| FLCS RESET | FLCS panel | clears an A/P FAIL or A/P DEGR fault whose cause has gone[^fm-3112] |

The two switches' places come from the cockpit figure: item 30 (ROLL) is drawn left of item 29 (PITCH)[^fm-14]. The
3D cockpit's model (FlightGear's) names its two switch nodes the other way round (`roll-hold-switch` is PITCH); its
properties name them right (`f16/fcs/switch-pitch-block20` on `roll-hold-switch`)[^fg-misc].

## 3. Engagement and the solenoid

The PITCH switch is solenoid held in an engaged position. It goes to A/P OFF while any of these holds[^fm-135]:

- AIR REFUEL switch at OPEN;
- ALT FLAPS switch at EXTEND below 400 knots;
- an A/P FAIL fault;
- angle of attack above 15°;
- the digital backup (DBU) engaged;
- the gear handle down;
- the low speed warning tone sounding;
- the MPO switch at OVRD;
- a STBY GAIN fault;
- TRIM/AP DISC at DISC.

Moving PITCH out of A/P OFF engages both the pitch and roll modes selected[^fm-135]. The manual warns that engaging any
mode in other than a trimmed flight condition degrades the autopilot's performance, because its authority is
limited[^fm-136].

The low speed warning tone sounds with the gear handle up and ALT FLAPS at NORM when the airspeed falls below a line of
pitch attitude (figure 1-50), and with the gear handle down or ALT FLAPS at EXTEND at 15° angle of attack or
more[^fm-130]. FlightGear reads figure 1-50's line as 75 KIAS at 45° of pitch and 183 KIAS at 90°[^fg-misc]
(second-hand: the figure's line is not given as numbers).

## 4. The modes

- **ALT HOLD.** Holds a constant altitude, within +0.5 g to +2 g of pitch command. Engaged at a climb or dive rate
  below 2,000 feet a minute, it selects an altitude it can capture within those limits; above 2,000 feet a minute it
  does no unsafe manoeuvre, but may not capture the altitude it engaged at. Accuracy ±100 feet up to 40,000 feet in
  normal cruise. The altitude is changed by holding the paddle, flying to the new altitude and letting go. It may be
  erratic in the transonic region[^fm-136]; through Mach 1.0 a mild pitch transient may come, cleared by the
  paddle[^fm-62].
- **Pitch ATT HOLD.** Holds the pitch attitude. It does not function beyond ±60° of pitch, while the switch stays
  engaged[^fm-136].
- **HDG SEL.** Turns to the HSI's heading marker and holds it: at most 30° of bank and 20°/s of roll rate. Set the
  marker to the present heading before engaging to keep it. It does not function beyond ±60° of bank, while the switch
  stays engaged[^fm-136].
- **Roll ATT HOLD.** Holds the bank. It does not function beyond ±60° of bank[^fm-136].
- **STRG SEL.** Steers to the selected steerpoint with roll commands: at most 30° of bank and 20°/s. It does not function
  beyond ±60° of bank[^fm-136].
- **Stick steering.** Works in the pitch and roll attitude hold modes only. A force on the stick large enough makes the
  autopilot drop the selected reference and take the stick's commands[^fm-136].
- With HDG SEL and ALT HOLD the jet climbs, dives and turns within the autopilot's limits to capture the heading and
  the altitude whatever its attitude[^fm-62].

## 5. Faults

- **FLCS A/P FAIL.** The autopilot lacks data, its data are wrong, the avionics bus has failed, or the angle of attack
  is above 15°: the autopilot disconnects, the FLCS FAULT caution light comes on and the fault list shows FLCS A/P
  FAIL. Engagement attempted with a fault or above 15° fails the same way. The procedure: 1 g flight below 15°, FLCS
  RESET; if the fault stays, the autopilot cannot be engaged[^fm-3112]. Engaging it during an in-flight INS alignment
  also gives A/P FAIL, cleared by a reset once the alignment is full[^fm-3127].
- **FLCS A/P DEGR.** The autopilot is engaged but not providing its function: after 12 seconds outside the attitude
  limits with no stick input (attitude modes), after 12 seconds with the roll command at its maximum authority (roll
  ATT HOLD), after 5 seconds with the pitch command at its maximum authority, no stick input and the jet not
  correcting back to its altitude or attitude (pitch modes). The procedure: back into the autopilot's envelope, FLCS
  RESET; if it stays, disengage the autopilot[^fm-3112]. In CAT III the jet starts down from its altitude at about 8°
  to 10° of angle of attack, and A/P DEGR follows if that is not corrected within 5 seconds[^fm-62].
- The FLCS FAULT caution light comes on with a caution-level fault list item and goes out when the fault is
  acknowledged or a reset clears it[^fm-132].

The flight manual gives no autopilot lamp or HUD symbol: the PITCH switch's position shows whether it is engaged
(open: the avionics manual's HUD and DED pages were not searched; its public copy is scanned images).

## 6. The sim (2026-11-19)

`F16Autopilot` (`crates/iaf-flight/src/sixdof/autopilot.rs`) runs on the 6-DoF each frame. Its commands, a g increment
and a roll rate, are added to the stick's in the control laws (`fcs::Pilot` `ap_g`, `ap_p`), so the jet flies them
through the same α and g limiters as the stick's. The 3D cockpit's two switches and the keys move it (front-end.md §9);
the PITCH switch springs back to A/P OFF when a condition holds it off; no line over the flight says why (the user,
2026-11-25, [front-end.md](../front-end.md) §8).

What the sim models: the three pitch positions and three roll modes of §2 and §4 with their limits; the paddle (the
references taken anew where it is let go); TRIM/AP DISC (a key; the model has no MANUAL TRIM panel); every condition of
§3 the sim has (DBU and STBY GAIN have no control law of their own in the sim, and the original game's autopilot
flying holds it off too); A/P FAIL above 15° of α or without its data (no power, the INS not aligned, the autopilot
damaged, damage flag 6), its FLCS FAULT light and fault list line; A/P DEGR on §5's three timers; FLCS RESET (a key; the
model has no FLCS panel switch).

Inferred, with no public source:

| what | value | why |
|---|---|---|
| the g a level path needs at the bank | cos θ / cos φ − 1, φ within ±60° | the control laws hold 1 g with the stick centred; a banked level turn needs more |
| ALT HOLD's law | climb rate 0.1 /s × the altitude error, within ±2,000 ft/min; 0.5 /s × the climb-rate error in g | settles in about 15 s without overshoot |
| the altitude ALT HOLD selects | where a pull or push at the g limit levels the jet off (below 2,000 ft/min) | "selects an altitude within the pitch command g limits" |
| pitch ATT HOLD's law | a flight-path rate of 0.5 /s × the pitch error | |
| the roll modes' law | roll rate 1 /s × the bank error, ±20°/s; HDG SEL / STRG SEL bank 2 × the heading error, ±30° | 30° of bank at 15° of heading error |
| roll ATT HOLD's rate limit | 20°/s | as HDG SEL's |
| pitch ATT HOLD's g limits | +0.5 g to +2 g | as ALT HOLD's |
| stick steering's threshold, and "no stick input" | a tenth of the stick's travel | just past the stick's dead band |
| HDG SEL with the marker never set, STRG SEL with no steerpoint | the heading at engagement | the EHSI shows no marker until its knob is turned |

Not modelled: the stick's TRIM button (the sim trims roll with its keys, which keep working), the terrain-following
blend (ADV MODE), the transonic transient, CAT III's descent at 8° to 10°, the low speed tone's sound.

Tests: `crates/iaf-flight/src/sixdof/autopilot.rs` (each disengage rule, A/P FAIL and the reset, each mode's command,
the paddle, stick steering, A/P DEGR's three timers), `crates/iaf-flight/tests/sixdof.rs`
`f16_autopilot_flies_each_mode_through_the_control_laws` (ALT HOLD with HDG SEL on both F-16s, ATT HOLD after stick
steering, STRG SEL, A/P FAIL from a full pull), `modern-iaf/tests/test_f16_autopilot.gd` (each mode flown in the game
by its keys and the 3D switch, TRIM/AP DISC, the gear, A/P FAIL's caution and fault list, FLCS RESET).

[^fm-14]: T.O. GR1F-16CJ-1 (the HAF F-16C/D flight manual, public copy https://archive.org/details/haf-f-16), figure 1-3, sheet 4, page 1-14 (items 29 "Autopilot PITCH Switch" and 30 "Autopilot ROLL Switch").
[^fm-129]: T.O. GR1F-16CJ-1, figure 1-46, sheet 2, page 1-129 (the paddle switch: "Interrupts the autopilot while switch is depressed").
[^fm-130]: T.O. GR1F-16CJ-1, page 1-130 (the low speed warning tone's conditions).
[^fm-131]: T.O. GR1F-16CJ-1, figure 1-47, page 1-131 (TRIM/AP DISC: NORM "Permits autopilot engagement"; DISC "prevents autopilot engagement and ATF/autopilot blending").
[^fm-132]: T.O. GR1F-16CJ-1, page 1-132 (the FLCS FAULT caution light; figure 1-50, the low speed warning tone schedule).
[^fm-134]: T.O. GR1F-16CJ-1, figure 1-51, sheet 2, page 1-134 (the PITCH and ROLL switches' positions).
[^fm-135]: T.O. GR1F-16CJ-1, page 1-135 ("AUTOPILOT": the modes, TRIM/AP DISC, the paddle, the solenoid and its conditions).
[^fm-136]: T.O. GR1F-16CJ-1, page 1-136 ("AUTOPILOT OPERATION": the modes' limits, A/P FAIL and A/P DEGR, stick steering).
[^fm-3112]: T.O. GR1F-16CJ-1, section III, "Autopilot Malfunctions", pages 3-112 and 3-113.
[^fm-3127]: T.O. GR1F-16CJ-1, section III, "INS failures", page 3-127.
[^fm-62]: T.O. GR1F-16CJ-1, section VI, "AUTOPILOT", page 6-2.
[^fg-misc]: FlightGear's F-16 (https://github.com/NikolaiVChr/f16): `Models/Cockpit/Main/misc.xml` (the properties' positions: switch-pitch-block20 −1 ATT HOLD, 0 AP OFF, 1 ALT HOLD; switch-roll-block20 −1 STRG SEL, 0 ATT HOLD, 1 HDG SEL; the animation of `roll-hold-switch` by switch-pitch-block20) and `Systems/jsb-misc.xml` (the low speed warning tone's schedule, "Dash 1 1-95").
