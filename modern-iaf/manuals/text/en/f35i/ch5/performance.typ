#import "../ch4/src.typ": *

Few of the F-35A's performance figures are public: the top speed (@limits-airspeed), a sustained turn of 4.6 g, whose speed and height are open, and no figure for the climb#specs13. The charts of the flight manual are open. This section gives what the sim's flight model does, clean, so that the pilot knows what to expect of it.

#in-sim[
  #table(
    columns: (1fr, auto),
    stroke: none,
    inset: (x: 6pt, y: 3.5pt),
    table.header([*Measure*], [*#jet.short*]),
    [Thrust at sea level, standing: military power / full afterburner], [28,000 / 43,000 lb],
    [Greatest level speed at sea level], [750 kt, Mach 1.14],
    [Greatest level speed at 40,000 ft], [Mach 1.6],
    [Least speed at 1 g, sea level], [128 kt],
    [Turn at 420 kt, 10,000 ft, full back stick], [20.0° a second at 6.7 g],
    [Fuel flow at sea level: military power / full afterburner], [22,100 / 89,500 lb an hour],
  )
  The weight is the #jet.short's with full internal fuel and no stores: 47,550 lb. Wing stores lower every figure but the thrust.
]
