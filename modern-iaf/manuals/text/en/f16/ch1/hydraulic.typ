#import "src.typ": *

The real jet has two hydraulic systems, A and B, each at 3,000 psi from its own engine-driven pump. Both move the flight control surfaces, so the jet flies on either one. System A also drives the speedbrakes and the fuel flow proportioner. System B also drives the landing gear, the wheel brakes, the nosewheel steering, the gun and the refuelling door, and recharges the accumulators of the #term("JFS")#fm[pages 1-36 and 1-98].

#row("anim118") and #row("anim119") show each system's pressure. The red #row("lamp_hyd_oil_press_0") warning light comes on when a system falls below 1,000 psi, or when the engine's oil pressure stays under 10 psi for 30 seconds#fm[pages 1-39 and 1-98]. It is on before the start and goes out as the engine speeds up (inferred). In flight it means a lost system or failing oil pressure; the procedures are in @emergency-systems.

=== The emergency power unit

The #term("EPU") is a small turbine that starts by itself when both generators or both hydraulic systems are lost. It gives hydraulic pressure to system A and electrical power for the essential systems. It runs on engine bleed air, and on hydrazine, a fuel of its own, when the engine gives too little air#fm[pages 1-98 and 1-99].

#row("SW_EPU") has three positions under its guard: OFF, NORM (it starts when needed) and ON (it runs now). The #row("lamp_epu_run_0") is on while the EPU gives pressure#fm[page 1-99]\; #row("lamp_epu_hydrazine_0") and #row("lamp_epu_air_0") show what it runs on, and #row("anim108") how much hydrazine is left.

#in-sim[
  The hydraulic system is #term("not modelled") as a system: pressure is there while the engine runs.
  - HYD PRESS A and B rise with the #term("RPM") to 3,000 psi.
  - #sym.arrow.r *HYD/OIL PRESS is on while the engine is stopped or turns slowly*, and after battle damage to the hydraulics; that damage also weakens the stick's authority.
  - The EPU switch moves and does nothing; the EPU's lights come on in the lamp test only, and EPU FUEL shows a fixed value.
]
