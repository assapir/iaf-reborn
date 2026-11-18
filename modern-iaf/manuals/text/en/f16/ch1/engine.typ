#import "src.typ": *

#if sufa [
  The #jet.short has one F100-PW-229 afterburning turbofan of about 29,000 lb of thrust#fm[page 1-31].
] else [
  The #jet.short has one F110-GE-100 afterburning turbofan#f16net. The engine controls below are those of the public flight manual, which describes the F100-PW-229; that the #jet.short's cockpit works the same way is inferred.
]

=== Engine control

A digital computer on the engine, the DEEC, has full authority over fuel flow and the nozzle. When it fails, a hydromechanical control, the SEC, takes over; the pilot can also select it with the guarded ENG CONT switch (PRI, SEC). In SEC the afterburner is inhibited and the SEC caution light is on#fm[pages 1-33 to 1-37].

=== The throttle

The #row("THROTTLE") has four marked positions: OFF, IDLE, MIL and MAX AB. Between OFF and IDLE is the idle cut-off: a release at the base of the throttle must be lifted to pass it, so that pulling the throttle back does not shut the engine down (the purpose is inferred)#fm[page 1-40]. MIL is military power, full power without the afterburner. Past MIL the afterburner lights and adds fuel through 11 segments up to MAX AB#fm[page 1-40].

=== The jet fuel starter

The #term("JFS") is a small gas turbine that cranks the engine for a start. Two hydraulic accumulators, shared with the brakes, spin it up: #row("JFS") at START 1 uses one accumulator, START 2 both. The switch goes back to OFF by itself, and the JFS stops, when the engine reaches 50~% #term("RPM"). The #row("lamp_jfs_run_0") light shows that the JFS runs#fm[pages 1-36 and 1-37].

A #term("hot start") is a start in which fuel reaches an engine that turns too slowly. It is explained with the start procedure, in @cold-start-start.

=== Engine instruments

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("anim169")], [Engine speed, 0 to 100~%. On the ground at idle the real engine turns at 65 to 77~%.],
  [#row("anim166")], [The #term("FTIT"), 200 to 1,200~°C.],
  [#row("anim167")], [How far the exhaust nozzle is open, 0 to 100~%. At idle on the ground it is above 80~%; it closes towards MIL and opens again in afterburner.],
  [#row("anim168")], [Oil pressure, 0 to 100 psi.],
  [#row("anim160")], [Fuel flow to the engine, 0 to 80,000 lb an hour.],
)
The ranges are the flight manual's#fm[pages 1-39 and 1-40].

The red #row("lamp_engine_0") warning light comes on when the RPM falls below 55~% or the FTIT passes 1,100~°C: the engine has flamed out or runs too hot#fm[page 1-40].

=== Engine fire <engine-fire>

A fire in the engine bay shows as the red #row("lamp_eng_fire_0") warning light; an overheat in the engine bay, the wheel wells or the equipment bays shows as the #row("lamp_caution_overheat_0") caution light. Both come from the fire and overheat detection system, tested with #row("FIRE_OHEAT_DETECT")#fm[page 1-58]. A fire in the bay can spread to the fuel and the flight controls around the engine (inferred), so it is acted on at once: the first action is to pull the throttle back to the least power that keeps the jet flying#fm[page 3-61, "Engine fire"]. The whole procedure is in @emergency-engine.

#in-sim[
  - *The start.* The JFS turns the engine to 20~% RPM in 15 seconds and holds it there. With the throttle moved to idle (#key("Throttle idle")), the engine lights 5 seconds later and reaches its idle, 60~%, 15 seconds after that. #sym.arrow.r *At 52~% the generator comes on line and the JFS switch goes back to OFF.* #key("Throttle OFF (engine shutdown)") shuts the engine down.
  - *Power.* Military power is #key("Throttle military power")\; the afterburner has two steps, #key("Afterburner stage 1") and #key("Afterburner stage 2"). The engine takes about 3 seconds from idle to military power.
  - *Instruments.* All five are driven. The FTIT shows 450~°C at idle and 650~°C at military power, more in afterburner.
  - *Fire.* A fire comes only from battle damage. #sym.arrow.r *ENG FIRE and OVERHEAT light, the voice says "Warning", and the engine loses its thrust.* #key("Extinguish engine fire") puts it out; there is one charge.
  - *#term("Not modelled").* The SEC and the ENG CONT switch, which the cockpit does not have; the engine anti-ice (#row("anti-ice-switch") moves and does nothing); #row("SW_MAX_POWER") and #row("SW_STARTING_FUEL"), which move and do nothing; temperature and oil-pressure limits; START 1 and START 2 act alike.
]
