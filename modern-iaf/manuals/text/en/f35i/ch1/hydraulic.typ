#import "src.typ": *

The #jet.short has no central hydraulic system for its flight controls. Each control surface is moved by an electro-hydrostatic actuator: a sealed unit with its own electric motor, pump and fluid, fed by the 270 V electrical system (@electrical). These actuators power the primary and the secondary flight control surfaces#av[page 13].

A fault of an actuator or of its electrical supply shows as a message on the display (@warnings); the procedures are in @emergency-systems.

#in-sim[
  The actuators and their power are #term("not modelled"): the surfaces move while the jet has electrical power, and battle damage to the flight controls weakens the stick's authority.
]
