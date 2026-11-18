#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *
#let caps = (
  test: [The TEST panel, left console.],
  gear: [The gear panel, left of the front panel.],
  master_arm: [The MASTER ARM switch on the MISC panel.],
  avionic_power: [The #term("AVIONIC POWER") panel, right console.],
  snsr_pwr: [The #term("SNSR PWR") panel, right console.],
  elec: [The ELEC and FUEL panels, left console.],
)

This section takes the #jet.name from the end of the landing roll to a cold, dark jet. It follows the last three sections of the checklist card, which keep the order of the real checklist#fm[section II, "After landing", "Prior to engine shutdown" and "Engine shutdown", pages 2-27 to 2-30].

#phases(
  ("after_landing", "before_shutdown", "shutdown"),
  ([No.], [Phase of the card], [Steps], [Ticked by the sim]),
)

=== After landing <shutdown-after-landing>

Do these steps once the jet is off the runway and slow.

#steps(
  "after_landing",
  captions: caps,
  figs: ("test", "gear", "master_arm"),
  notes: (
    probe_heat_off: [On the ground no air cools the probes: their heaters fail if left on for long, and a probe can burn a hand#fm[section II, "After landing", the warning and the caution at item 2, pages 2-27 and 2-28].],
    speedbrakes_closed: [In the sim #key("Speedbrakes close") closes them.],
    seat_safe: [With the lever up the seat cannot fire. It is made safe before anyone comes near the cockpit.],
  ),
)

#idx("Parking brake, after landing")#caution[After a landing the real jet is held with the pedals or with chocks, not with the parking brake. The brakes are hot from the stop; the parking brake clamps them, the heat stays in, the brakes are damaged and a brake fire becomes more likely#fm[section II, "After landing", the caution of page 2-27]. Before a flight, with cold brakes, the parking brake is the normal way to hold the jet. In the sim #row("SW_PARKING_BRAKE") moves only.]

Taxi back as you taxied out: a little throttle, #key("Wheel brakes") to slow down.

=== Prior to engine shutdown <shutdown-before>

Stop on the parking spot. Turn off what the generator feeds while it still runs, the #term("INS") first.

#steps(
  "before_shutdown",
  captions: caps,
  seen: (
    avionics_off: [The displays, the #term("HUD") and the #term("DED") go dark],
  ),
  figs: ("avionic_power", "snsr_pwr"),
  notes: (
    ins_off: [The real unit needs power for a time after OFF to close down in order: at least 10 seconds, and 20 seconds for the newer unit with satellite navigation#fm[section II, "Prior to engine shutdown", the note at item 6, page 2-29]. The sim sets no such time.],
  ),
)

=== Engine shutdown <shutdown-engine>

#steps(
  "shutdown",
  captions: caps,
  seen: (
    throttle_off: [#term("RPM") falls: under 20~% after about 16 seconds, stopped after about a minute; the generator lets go at about 52~%],
    main_power_off: [Every lamp and gauge dark],
  ),
  figs: ("elec",),
  notes: (
    throttle_off: [The throttle stops at idle; OFF takes its own key, as the real lever's stop at idle takes a deliberate lift.],
    main_power_off: [With the General Electric engine the real pilot waits until the RPM is under 20~%: the nozzle then stays open, which makes the inspection after the flight easier#fm[section II, "Engine shutdown", the note at item 4, page 2-29]. The card keeps the wait for both jets.],
    canopy_open: [#key("Canopy") opens it.],
  ),
)

#idx("Throttle OFF")#caution[The throttle at OFF cuts the engine's fuel at once, wherever the jet is. On the ground after a flight that is the shutdown. In the air it stops the engine: the jet glides, and the generator lets go as the RPM falls. The only use of OFF in the air is as a step of an engine restart (@emergency-engine, #term("not modelled")). The key is apart from the other throttle keys for this reason.]

#idx("Tailpipe fire")#note[After the shutdown, fuel left in the hot engine can light: a mild bang, then smoke or a small fire at the tailpipe. It does no damage to the engine. The real pilot turns the engine with the #term("JFS") for about a minute to blow it out; without the JFS it goes out by itself in a few minutes. The ground crew keeps clear of the intake and the tailpipe for some minutes after every shutdown#fm[section II, "Engine shutdown", the warning before item 1, page 2-29]. Not modelled.]

#in-sim[A jet shut down can be started again with the card from its first section, once the RPM is under 20~%. #sym.arrow.r *The JFS switch does nothing above 20~% RPM.*]
