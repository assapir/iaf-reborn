#import "src.typ": *

The #jet.short has one F135-PW-100 afterburning turbofan of 40,000 lb of thrust#card-a. A digital computer controls it; the pilot's throttle only asks for thrust (inferred).

=== The integrated power pack

The #term("IPP") is a small turbine in the fuselage that does four jobs in one unit: it starts the engine, gives auxiliary power on the ground, drives the cooling of the cockpit and the avionics, and gives emergency power in flight#av[page 14]. In a start the IPP runs first, for a few minutes in the real jet, and the pilot then moves the engine switch to RUN#aib-start.

=== Controls

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("IPP")], [Starts the IPP.],
  [#row("ENG")], [Under its #row("ENG_GUARD"): starts the engine with the IPP's power.],
  [#row("throttle")], [OFF, IDLE, MIL (military power, full power without the afterburner) and MAX (full afterburner).],
  [#row("IPP_EMER_OFF")], [Under its guard: shuts the IPP down.],
  [#row("lamp_eng_fire_0")], [The red fire warning light.],
)
What the switches of this cockpit do in the real jet is inferred from their names: the F-35's flight manual is not public.

The engine's readings are on the #term("PCD"): the ENG format, and the engine's #term("RPM") in the bar at its top (@pcd).

=== Engine fire <engine-fire>

A fire in the engine bay shows as the red ENG FIRE light and an ENG FIRE warning on the display. It is acted on at once: the procedure is in @emergency-engine.

#in-sim[
  - *The start.* #row("BATT") on, then IPP, which takes 10 seconds to run up, then ENG. The engine turns to 20~% RPM in 15 seconds, lights 5 seconds later and reaches idle 15 seconds after that. From a cold jet the displays are on after about 13 seconds and the engine is at idle after about 45. #key("Starter (JFS / IPP)") is the IPP switch's key.
  - *Power.* #key("Throttle military power") is MIL; the afterburner has two steps, #key("Afterburner stage 1") and #key("Afterburner stage 2"). The engine takes about 5 seconds from idle to military power. #key("Throttle OFF (engine shutdown)") shuts it down.
  - *Fire.* A fire comes only from battle damage. #sym.arrow.r *ENG FIRE lights, the display shows ENG FIRE, the voice says "Warning", and the engine loses its thrust.* #key("Extinguish engine fire") puts it out; there is one charge. A push on the ENG FIRE light does the same.
  - *IPP EMER OFF.* The first click lifts its guard; the next press #sym.arrow.r *shuts the IPP down*, as the IPP switch at OFF does.
  - *#term("Not modelled").* Engine faults; the IPP's cooling and emergency power; #row("VS_BIT"), which moves and does nothing; the ENG switch's MOTOR position.
]
