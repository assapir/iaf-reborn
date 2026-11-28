#import "src.typ": *

This chapter gives the #jet.name's emergency procedures in the order of a flight: on the ground, on take-off, in the air, on landing, and last the ejection. Each emergency says what it is, why it matters, how you recognise it, what to do in order, and what follows. A line under each heading says whether the sim can produce it; the real procedure is given in both cases.

=== The three rules <emergency-rules>

The flight manual puts three rules before every procedure#fm[section III, "Introduction", page 3-3]:

+ *Keep the jet under control.* Fly first; a switch can wait a few seconds.
+ *Analyse the situation and take the proper action.* Read the lights before acting.
+ *Land as the situation dictates.* "As soon as possible" means the nearest suitable runway, with an emergency declared; "as soon as practical" leaves the choice of airfield to the pilot.

=== How the jet tells you <emergency-signs>

A fault shows on the red warning lights at eye level, on the amber caution lights with #row("master_reset"), and by the voice (@warnings). The red lights that matter most in this chapter are #row("lamp_eng_fire_0"), #row("lamp_engine_0"), #row("lamp_hyd_oil_press_0") and #row("lamp_flcs_0").

#in-sim[
  - A fault comes from three causes: damage (a hit, the gear down at too high a speed, a hard touchdown), a wrong action in the start, and a set failure: one of this chapter's emergencies started on purpose, at a set time or on the take-off roll. Systems do not fail by chance.
  - A set failure #sym.arrow.r *MASTER CAUTION, and the voice says "Warning" (a red warning light) or "Caution" (the generators).* Its lights and fault list lines are the real jet's, and the steps of this chapter recover it. The #term("notebook")'s emergency tab holds the same steps (the #other("game", "notebook")).
  - Every piece of damage #sym.arrow.r *lights MASTER CAUTION and speaks "Caution" (with "Warning" for a fire or a dead engine).* A missile's hit also shakes the jet.
  - #key("Damage page") shows the TEST format of the #term("MFD") with each damaged system; the #term("DED") lists the faults.
  - Damage can take: the engine, the afterburner, the fuel (a leak), the hydraulics, the flight controls, the generators, the flaps, the speedbrakes and wheel brakes, the gear, the autopilot, the instruments, the #term("HUD"), the radar, the warning receiver, the jammer, the gun and the weapons.
  - A crash destroys the jet: a touchdown that sinks faster than about 13 ft/s (4 m/s), with the gear up, banked more than 10°, with the tail lower than 15° or the nose lower than 5°; water; or rough ground at speed.
]
