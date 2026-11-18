#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
// The pictures' captions.
#let caps = (
  gear_panel: [The gear panel, left of the display.],
  front: [Under the display: the #term("HMD") knob, MASTER ARM and the MASTER CAUTION light.],
  start_panel: [The start panel on the left console.],
  fcs_reset: [The FCS/ENG RESET button, left console.],
)
#let ayton = [#footnote[Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, "Engine start up procedure": three switch selections (battery, IPP, engine), and "After 90 seconds, if there are no problems, the aircraft declares itself ready for flight" (checked 18 November 2026), #link("https://www.f-16.net/forum/viewtopic.php?p=317934").]<ayton>]

This procedure takes the #jet.name from a cold, dark jet on its parking spot to a climb with the gear up. It follows the jet's checklist card. The start takes about a minute and a half: the jet tests itself for 90 seconds from the moment the battery is on.

#idx("Self test")#idx("Checklist card, sources")#note[No F-35 checklist is public. The one public description of the start gives three switch selections, battery, #term("IPP") and engine, and a 90-second self test#ayton. Those four steps of the card follow it. Every other step, and the order of the sections, is inferred from the F-16's normal procedures and from this cockpit.]

The sim models this procedure in part. It ticks the steps it can check. A step marked ○ is one it does not check, in most cases because the system is #term("not modelled"): read it and go on.

=== Before you begin <cold-start-before>

- *The jet.* The jet is parked with the engine off, no electrical power and the canopy open.
- *The checklist.* #key("Checklist notebook") raises the #term("notebook"). Its CHECKLIST tab shows the same steps as this section, ticks each one the sim sees done, and marks the current step in yellow. See the #other("game", "notebook").
- *The controls.* A click moves a switch one position. Some steps also have a key, shown in the Key column. See the #other("game", "clicking").
- *Clearances.* Four points of this procedure need a clearance: the engine start, the taxi, the line-up and the take-off. How to ask for one, and what follows a move made without it, is in the #other("game", "tower").
- *In the sim.* This section says what each action does to the jet. How the sim marks the procedure is in the #other("game", "missions-training").

#idx("Clearances")The procedure has eight phases. Seven are sections of the checklist card; the take-off itself is flown, not read.

#phases(
  ("before_start", "start", "after_start", "before_taxi", "taxi", "before_takeoff", "after_takeoff"),
  ([No.], [Phase of the card], [Steps], [Ticked by the sim]),
)

=== Before engine start <cold-start-before-start>

These steps check that the cockpit is safe to power.

#steps(
  "before_start",
  captions: caps,
  figs: ("gear_panel", "front"),
)

=== Engine start <cold-start-start>

Get the start-up clearance first.

The integrated power pack (IPP) is a small turbine. It powers the jet on the ground and turns the engine. Three switches start the jet: BATT, IPP, ENG.

#idx("IPP")#caution[Wait 10 seconds after IPP – ON before you set the ENG switch to NORM. The IPP is what turns the engine: until it is up to speed it cannot crank it, and the start stops. Start again from the IPP.]

#steps(
  "start",
  captions: caps,
  seen: (
    main_power: [The lamps come alive; the 90-second self test starts],
    starter: [The IPP whines up to speed in 10 seconds; the display lights 3 seconds later],
    engine: [The engine cranks, lights and runs up to idle in about 35 seconds],
    selftest: [The helmet shows steering when the test is done],
  ),
  figs: ("start_panel",),
  notes: (
    starter: [The display runs on the IPP's power.],
    engine: [#key("Throttle idle") does the same as the switch.],
    selftest: [Nothing to do but wait. When the test is done, the navigation system is ready.],
  ),
)

=== After engine start <cold-start-after-start>

#steps(
  "after_start",
  captions: caps,
  seen: (
    icaw: [MASTER CAUTION light out],
  ),
  figs: ("front",),
  notes: (
    hmd: [The F-35 has no head-up display. With the knob at OFF the helmet shows nothing.],
    icaw: [The step is ticked while the MASTER CAUTION light is out.],
  ),
)

=== Before taxi <cold-start-before-taxi>

#steps(
  "before_taxi",
  captions: caps,
  seen: (
    canopy: [Canopy down in about 10 seconds],
  ),
  figs: ("gear_panel",),
  notes: (
    canopy: [The CANOPY switch is on the left console behind the seat's edge, out of sight from the normal head position; its key is the easy way.],
  ),
)

=== Taxi <cold-start-taxi>

Get the taxi clearance; it names the runway. Add a little throttle and follow the taxiway signs to that runway's holding point. Hold #key("Wheel brakes") to slow down.

#steps(
  "taxi",
  captions: caps,
)

At the holding point, stop and get the line-up clearance.

=== Before take-off <cold-start-before-takeoff>

Do these steps at the holding point or lined up, before the take-off clearance.

#steps(
  "before_takeoff",
  captions: caps,
  figs: ("fcs_reset", "front", "gear_panel"),
)

=== Take-off <cold-start-takeoff>

The take-off is flown from memory. It is not on the card.

+ Line up on the runway's centreline and stop.
+ Get the take-off clearance.
+ Set full power: #key("Throttle military power"), or #key("Afterburner stage 2") with a heavy load.
+ Keep the jet on the centreline with the rudder.
+ #idx("Lift-off speed")At about 165 kt (the sim's figure; the real jet's lift-off speed is open), ease the stick back and let the jet fly off.
+ When the jet climbs, go on with the next phase.

=== After take-off <cold-start-after-takeoff>

#steps(
  "after_takeoff",
  captions: caps,
  figs: ("gear_panel",),
)

=== If the start goes wrong <cold-start-faults>

#table(
  columns: (1fr, 1fr, 1.2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([What you see], [Why], [What to do]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [The IPP switch does nothing.], [No electrical power.], [Set #ctl("BATT") to ON, then the IPP.],
  [The ENG switch does not move.], [Its guard is down.], [Click once to lift the guard, then click to MOTOR and to NORM.],
  [The start stops at ENG – NORM.], [The IPP was not running, or not yet up to speed.], [Start again from the IPP and wait 10 seconds.],
  [The helmet shows no steering.], [The self test is still running, or the #ctl("HMD_MODE") is at OFF.], [Wait until 90 seconds after BATT; set the HMD knob to AUTO or DAY.],
)
