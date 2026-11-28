#import "src.typ": *

This chapter gives the #jet.name's emergencies in the order of a flight: on the ground, on take-off, in the air, on landing, and last the ejection. The F-35's flight manual and its emergency checklist are not public. What a public source states is given with its place; where none exists the manual says "open" and gives no steps. A line under each heading says whether the sim can produce the emergency.

=== What is public <emergency-rules>

The one public source is a United States Air Force flying instruction from the jet's development years#afi[chapter 7, "Abnormal operating procedures"]. It gives rules of airmanship, not steps:

- A jet with a fault that touches the safety of flight is not flown, and is not taxied with a steering or brake fault. In the air, fault-finding stops when the checklist's steps are done and the jet can be brought home safely#afi[paragraph 7.1].
- Land from a straight-in approach with a cooling caution, after a bird strike, with a flight control fault, with an engine caution that does not clear, or with a fault of the oxygen system#afi[paragraph 7.4.3]. After too much g: land, have the jet checked, and write it up#afi[paragraph 7.4.4].
- At the time of the instruction the F-35A had no memory items: no steps the pilot must know by heart#afi[attachment 4, its paragraph 1].

=== How the jet tells you <emergency-signs>

Every fault is a message of the ICAWS on the #term("PCD"), with a tone or the voice and #row("lamp_master_caution_0") (@warnings). A fire has its own red light, #row("lamp_eng_fire_0").

#in-sim[
  - A fault comes from three causes: damage (a hit, the gear down at too high a speed, a hard touchdown), a wrong action in the start, and a set failure: an engine fire, a flameout, a generator failure, the control system's degraded mode or a gear fault started on purpose, at a set time or on the take-off roll. Systems do not fail by chance.
  - A set failure #sym.arrow.r *MASTER CAUTION, and the voice says "Warning" or "Caution"; the ICAWS shows its line.* The #term("notebook")'s emergency tab (the #other("game", "notebook")) holds the steps the sim answers to; they are inferred from the F-16's, as the jet's own are not public.
  - Every piece of damage #sym.arrow.r *lights MASTER CAUTION and speaks "Caution" (with "Warning" for a fire or a dead engine).* A missile's hit also shakes the jet.
  - #key("Damage page") shows the ICAWS format. Its lines: *ENG FIRE, ENGINE FAIL, AB FAIL, FUEL LEAK, ELEC FAIL, FCS DEGD, FCS FAIL, FLAPS FAIL, GEAR FAIL, BRAKES FAIL, AP FAIL, #term("INS") FAIL, RADAR FAIL, RWR FAIL, ECM FAIL, #term("HMD") FAIL, WPN FAIL* and *GUN FAIL*.
  - A crash destroys the jet: a touchdown that sinks faster than about 13 ft/s (4 m/s), with the gear up, banked more than 10°, with the tail lower than 15° or the nose lower than 5°; water; or rough ground at speed.
]
