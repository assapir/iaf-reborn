#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
// The pictures' captions.
#let caps = (
  elec: [The ELEC and FUEL panels, left console.],
  test: [The TEST panel, left console.],
  flt_control: [The FLT CONTROL panel, left console.],
  master_arm: [The MASTER ARM switch on the MISC panel.],
  gear: [The gear panel, left of the front panel.],
  air_source: [The AIR SOURCE knob, right console.],
  jfs: [The #term("JFS") switch on the ENG & JET START panel, left console.],
  avionic_power: [The #term("AVIONIC POWER") panel, right console.],
  snsr_pwr: [The #term("SNSR PWR") panel, right console.],
  sym: [The SYM wheel on the #term("ICP"), under the #term("HUD").],
  mpo: [The MANUAL PITCH switch, left console.],
  master_caution: [The MASTER CAUTION light, on the glareshield.],
  ext_lights: [The EXT LIGHTING panel, left console.],
  cmds: [The #term("CMDS") panel, left console.],
)
// The sources, each a footnote at its first use.
#let haf = [#footnote[Flight manual of the Hellenic Air Force's F-16C/D Blocks 50 and 52+, T.O. GR1F-16CJ-1, 15 October 2002 with Change 1 of 15 June 2003, section II "Normal procedures", pages 2-2 to 2-30. A public copy: #link("https://archive.org/details/haf-f-16"). Checked 18 November 2026.]<haf>]
#let fmp(place) = footnote[The same flight manual, #place.]
#let ins = [#footnote[F-16.net forum, "INS alignment time and time to takeoff from cold start", posts of 16 and 18 February 2004 and 25 April 2005: "a minimum of 8 minutes is the normal spin-up time"; a stored-heading alignment "takes approx 90sec" (a forum: a weak source; other posts give 4 minutes for newer units), #link("https://www.f-16.net/forum/viewtopic.php?p=7943").]<ins>]
#let gen = fmp[section II, "Starting engine", page 2-10: the JFS shuts down by itself at about 55~% RPM and the standby generator comes on line at about 60~% (the text for the General Electric engine)]
#let hot = fmp[section III, "Hot start (ground)", page 3-26: a hot start is an FTIT over 800~°C with the Pratt & Whitney engine and over 935~°C with the General Electric engine; throttle OFF, watch the FTIT, and above 500~°C turn the engine with the JFS until 200~°C or for four minutes. Why the start runs hot is inferred]
#let rot = [#footnote[Falcon BMS forum, "Rotation speed": "70 knots plus 3x GW in thousands of pounds", a member's fit to the take-off charts, within a couple of knots (a forum: a weak source), #link("https://forum.falcon-bms.com/post/314659").]<rot>]

This procedure takes the #jet.name from a cold, dark jet on its parking spot to a climb with the gear up. It follows the jet's checklist card, which keeps the sections and the order of the real F-16C/D normal procedures#haf. The start takes about four minutes; most of that is the #term("INS") alignment.

The sim models this procedure in part. It ticks the steps it can check. A step marked ○ is one it does not check, in most cases because the system is #term("not modelled"): read it and go on.

=== Before you begin <cold-start-before>

- *The jet.* The jet is parked with the engine off, no electrical power and the canopy open.
- *The checklist.* #key("Checklist notebook") raises the #term("notebook"). Its CHECKLIST tab shows the same steps as this section, ticks each one the sim sees done, and marks the current step in yellow. See the #other("game", "notebook").
- *The controls.* A click moves a switch one position; a held click holds a test switch. Many steps also have a key, shown in the Key column. See the #other("game", "clicking").
- *Clearances.* Four points of this procedure need a clearance: the engine start, the taxi, the line-up and the take-off. How to ask for one, and what follows a move made without it, is in the #other("game", "tower").
- *In the sim.* This section says what each action does to the jet. How the sim marks the procedure is in the #other("game", "missions-training").

#idx("Clearances")The procedure has eight phases. Seven are sections of the checklist card; the take-off itself is flown, not read.

#phases(
  ("before_start", "start", "after_start", "before_taxi", "taxi", "before_takeoff", "after_takeoff"),
  ([No.], [Phase of the card], [Steps], [Ticked by the sim]),
)

=== Before starting engine <cold-start-before-start>

These steps check that the cockpit is safe to power, then bring the battery and main power on.

#steps(
  "before_start",
  captions: caps,
  seen: (
    batt: [#term("FLCS") RLY light on; the warning lamps and the engine gauges come alive],
    flcs_pwr_test: [FLCS PWR lights on while the switch is held],
  ),
  figs: ("elec", "test", "flt_control", "master_arm", "gear", "air_source"),
  notes: (
    batt: [The displays stay dark until the engine drives the generator.],
    flcs_pwr_test: [Hold the switch for a moment. The sim ticks the step once the switch has been at TEST.],
    fuel_master: [The cockpit model has this switch, but the sim has no fuel shut-off behind it.],
  ),
)

=== Starting engine <cold-start-start>

Get the start-up clearance first.

The jet fuel starter (JFS) turns the engine. At 20~% #term("RPM") you move the throttle from OFF to idle, which lets fuel in. The engine lights about 5 seconds later and reaches idle about 15 seconds after that.

#idx("Hot start")#caution[Keep the throttle at OFF until the RPM reaches 20~%. Below that the engine turns too slowly to move enough air through itself; fuel let in then burns too hot, and the turbine's temperature passes its limit. This is a #term("hot start"), and it can damage the turbine#hot. In the real jet you see it on the #term("FTIT") indicator, which climbs fast towards its limit; you put the throttle back to OFF and watch the FTIT, and if it stays above 500~°C the JFS turns the engine again to cool it. In the sim: #sym.arrow.r *the engine shuts down* by itself; the FTIT's limit and the damage are not modelled. No procedure on the ground uses an early throttle; an engine start in the air is a different procedure with its own conditions (@emergency-engine, not modelled). The ground case is in @emergency-ground.]

#steps(
  "start",
  captions: caps,
  seen: (
    starter: [The JFS whines; RPM climbs to 20~% in about 15 seconds and holds there until the throttle moves],
    engine: [The engine lights; RPM climbs to idle],
    jfs_off: [JFS switch back at OFF at about 52~% RPM; displays and HUD on 3 seconds later],
    engine_lights: [ENGINE and HYD/OIL PRESS lights out],
  ),
  figs: ("jfs",),
  notes: (
    engine: [Use the throttle lever, or #key("Throttle idle"). With the throttle at OFF, the key takes the step.],
    jfs_off: [The real JFS shuts down by itself at about 55~% RPM, and the generators come on line a little above that#gen. The sim does both at 52~%.],
    engine_gauges: [The gauges show the engine's values. The sim sets no limits on them, so there is nothing to tick.],
  ),
)

=== After engine start <cold-start-after-start>

With the generator on line, test the warning systems, power the avionics and start the INS alignment. Then check the flight controls.

#steps(
  "after_start",
  captions: caps,
  seen: (
    probe_heat_test: [The caution light flashes at TEST],
    fire_test: [ENG FIRE and OVERHEAT lights on],
    mal_ind_test: [Every lamp lights while the button is held],
    avionics: [Each system is up 3 seconds after its switch],
    ins_align: [ALIGN steady on the HUD],
    hdpt: [NOT TIMED OUT while the targeting pod cools],
    master_caution: [MASTER CAUTION light out],
    flcs_bit: [RUN lights at BIT],
    dbu: [DBU ON lights],
  ),
  figs: ("test", "avionic_power", "snsr_pwr", "sym", "master_caution", "flt_control", "mpo", "elec"),
  notes: (
    avionics: [The key turns on all four, and the #term("FCR") and RDR ALT switches of the SNSR PWR panel with them.],
    ins_align: [Go on with the next steps; the INS needs 90 seconds.],
    hdpt: [The targeting pod has power only with RIGHT #term("HDPT") on.],
    master_caution: [The step is ticked while the MASTER CAUTION light is out.],
    flight_controls: [Move the stick and the pedals and watch the surfaces from an outside view if you wish. The sim does not check it.],
  ),
)

#idx("INS alignment")#idx("Checklist card, differences from the real one")#note[The sim's card differs from the real checklist#footnote(<haf>) in three places. The real card aligns the INS at NORM, which takes about 8 minutes#ins, while the sim's card uses #term("STOR HDG"), the alignment of the real jet's quick-response start#fmp[section II, "Scramble", item 8, page 2-30], which takes 90 seconds. The real card has the left hardpoint off unless its pod is needed and the right one "as required"#fmp[section II, "After engine start", item 5, page 2-12]; the sim's card always turns both on, for the pods these jets carry. The real #term("EPU") check runs the unit with the engine a little above idle#fmp[section II, the EPU check, page 2-19]; the sim has no EPU, so its card only moves the switch to OFF and back to NORM.]

=== Before taxi <cold-start-before-taxi>

Close the canopy, set the lights and the countermeasures panel, and put the INS to NAV once it is aligned.

#steps(
  "before_taxi",
  captions: caps,
  seen: (
    canopy: [Canopy down in about 10 seconds; CANOPY light out when it is locked],
    ins: [ALIGN flashes on the HUD when the alignment is done; at NAV, ALIGN goes out and the HUD shows steering],
  ),
  figs: ("ext_lights", "cmds", "avionic_power", "gear"),
)

#idx("INS alignment")#caution[The INS knob turned to NAV before ALIGN flashes leaves the INS without an alignment: the HUD gives no steering. Wait for the flashing ALIGN.]

=== Taxi <cold-start-taxi>

Get the taxi clearance; it names the runway. Release the brakes, add a little throttle and follow the taxiway signs to that runway's holding point. Hold #key("Wheel brakes") to slow down.

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
  figs: ("flt_control", "test", "master_caution", "gear"),
)

=== Take-off <cold-start-takeoff>

The take-off is flown from memory. It is not on the card.

+ Line up on the runway's centreline and stop.
+ Get the take-off clearance.
+ Set full power: #key("Throttle military power"), or #key("Afterburner stage 2") with a heavy load.
+ Keep the jet on the centreline with the rudder. The real jet is steered with the nosewheel until the rudder takes hold, at about 70 kt#fmp[figure 2-2 "Normal takeoff", page 2-21].
+ #idx("Rotation speed")At the rotation speed, ease the stick back and hold the nose 8° to 12° up#fmp[section II, "Normal takeoff", page 2-21: the rotation starts 10 kt below the take-off speed, 15 kt with afterburner; an earlier pull lengthens the take-off run]. The rotation speed is 70 kt plus 3 kt for each 1,000 lb of the jet's weight#rot: about 145 kt at 25,000 lb, about 175 kt at 35,000 lb.
+ When the jet climbs, go on with the next phase.

=== After take-off <cold-start-after-takeoff>

#steps(
  "after_takeoff",
  captions: caps,
  figs: ("gear",),
)

=== If the start goes wrong <cold-start-faults>

#table(
  columns: (1fr, 1fr, 1.2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([What you see], [Why], [What to do]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [The JFS switch does nothing.], [No electrical power.], [Set #ctl("MAIN_PWR") to MAIN PWR, then JFS to START 2.],
  [The RPM stays at 20~%.], [The JFS is waiting for the throttle.], [Move the throttle from OFF to idle.],
  [The engine shuts down during the start.], [A hot start: the throttle left OFF below 20~% RPM.], [Throttle to OFF with #key("Throttle OFF (engine shutdown)"). Start again from the JFS and wait for 20~%.],
  [The displays stay dark with the engine at idle.], [The AVIONIC POWER switches are off, or were set before the generator came on line.], [Set #term("MMC"), ST STA, #term("MFD") and UFC to ON with the engine at idle.],
  [ALIGN stays steady on the HUD.], [The INS is still aligning.], [Wait 90 seconds from STOR HDG. The #term("DED")'s INS page (LIST, then 6) counts the time.],
  [The HUD is dark with the avionics on.], [The #ctl("SYM") is at its lowest.], [Roll the wheel up.],
)
