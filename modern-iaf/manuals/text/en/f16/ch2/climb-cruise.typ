#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *

This section takes the #jet.name from the end of the card's AFTER TAKEOFF section (@cold-start-after-takeoff) to the start of the approach. The card has no section of its own for the cruise: its checks are one line of AFTER TAKEOFF, done again at intervals.

=== The climb <climb>

The real jet climbs on a schedule: an airspeed held until it meets a Mach number, then that Mach number held to the cruise height. A climb that starts above the height where the two meet holds the Mach number from the start#fm[section II, "Climb", page 2-22]. Two schedules are given: at military power for the best range, and at full afterburner for the least time#fm[section II, "Climb", page 2-22]. Their figures are tables of the performance manual, a separate book that is not public: open.

#in-sim[Climb with #key("Throttle military power"), or with the afterburner (#key("Afterburner stage 2")) when time matters more than fuel. #sym.arrow.r *The fuel flow* on #row("anim160") *about doubles or more in afterburner.* #term("Not modelled"): a climb schedule on a display; hold a steady airspeed by the pitch attitude.]

=== The checks in the climb and the cruise <cruise-checks>

#idx("Operational checks")The real jet's pilot checks five things "at frequent intervals", from the climb on#fm[section II, "Climb/in-flight/operational checks", pages 2-22 and 2-23]. The card holds them as one line, the last of its AFTER TAKEOFF section.

#table(
  columns: (auto, 1.1fr, 1.3fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Check], [In the real jet], [In the sim]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [Fuel], [The quantity, that the external tanks feed, and that the forward and aft tanks stay in balance. The pilot turns #row("FQS_sel-knob") through its positions and adds the pointers up against the total.], [#row("anim110") shows the fuel. The knob is partly modelled: NORM, EXT WING, EXT CTR and TEST show their reading; RSVR and INT WING show NORM's, as the separate tanks are not modelled (@fuel).],
  [FUEL QTY SEL], [Back to NORM. Only there the jet moves fuel forward by itself, warns of trapped fuel, and counts the bingo warning from the fuel in the fuselage#fm[section II, "Climb/in-flight/operational checks", the note under item 2, page 2-22].], [The knob's position changes only the pointers. The transfer forward, the trapped-fuel warning and a bingo from the fuselage's fuel are not modelled: the bingo counts all the fuel.],
  [Oxygen], [The regulator's flow and pressure.], [Not modelled.],
  [Cabin pressure], [#row("anim104") against the jet's height.], [The gauge works. #row("lamp_caution_cabin_press_0") works.],
  [Engine], [#term("RPM"), #term("FTIT"), nozzle, oil pressure: steady and inside their limits (@limits-engine).], [The gauges show the engine's values.],
)

#idx("Cabin pressure")#warning[The CABIN PRESS caution light comes on only when the cabin is above 27,000 ft#fm[section II, "Climb/in-flight/operational checks", the warning under item 4, page 2-23]. A cabin that loses its pressure more slowly gives no light on the way: the pilot loses oxygen without a warning (hypoxia) and thinks ever less clearly. This is why the gauge is read in every check, and why the mask stays on at height. The action is in @emergency-systems. In the sim the pilot is not affected.]

=== Fuel against bingo <cruise-bingo>

#idx("Bingo fuel")#term("Bingo fuel") is a fuel quantity that you set before the flight: what the flight home and the landing need, with a reserve. The jet compares it with the fuel left and warns when the fuel falls below it. The warning is a reminder, not a fault: the action is to end what the flight is doing and turn for home. It is set on the #term("DED")'s bingo page (@ufc).

At each fuel check, compare three numbers: the fuel left, the bingo, and the fuel the way home needs from where the jet is now. Afterburner changes the answer fast.

=== The autopilot <cruise-autopilot>

#key("Autopilot: level / nav / off") steps the sim's autopilot: it holds the jet level, then steers it along the steerpoints, then lets go. #key("Next waypoint") and #key("Previous waypoint") choose the steerpoint. In the cockpit the autopilot's two switches, #row("pitch-hold-switch") and #row("roll-hold-switch"), move only; what they do in the real jet is in @flight-controls.

=== The descent <descent>

The real jet's checklist joins the descent and the landing in one section, "Descent/before landing"#fm[section II, "Descent/before landing", page 2-23]. Before the pattern it has the pilot check the fuel, work out the final approach speed (@landing-speed), clear the canopy of mist, turn the landing light on, compare the altimeter with the #term("HUD")'s height, check the attitude instruments against each other, and stow the targeting pod. The card keeps three of these lines as its BEFORE LANDING section, which is in @landing.

#in-sim[Come down with the throttle at idle; hold #key("Speedbrakes open (hold)") to open the speedbrakes; #key("Speedbrakes close") closes them. #sym.arrow.r *The speed falls faster.* Not modelled: canopy mist, the altimeter's two modes, the pod's stow position.]
