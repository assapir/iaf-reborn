#import "../ch4/src.typ": *

The #jet.short's performance charts (take-off and landing distances, climb, range, endurance, turn) are in the performance supplement of the flight manual, which is not public: open. This section gives what the sim's flight model does, clean, so that the pilot knows what to expect of it.

#in-sim[
  #table(
    columns: (1fr, auto),
    stroke: none,
    inset: (x: 6pt, y: 3.5pt),
    table.header([*Measure*], [*#jet.short*]),
    [Thrust at sea level, standing: military power / full afterburner], if sufa [17,800 / 29,160 lb] else [17,110 / 29,000 lb],
    [Greatest level speed at sea level], if sufa [Mach 1.19] else [785 kt, Mach 1.19],
    [Greatest level speed at 40,000 ft], [Mach 1.99],
    [Least speed at 1 g, sea level], if sufa [136 kt] else [125 kt],
    [Turn at 420 kt, 10,000 ft, full back stick], if sufa [20.3° a second at 7.0 g] else [21.4° a second at 7.7 g],
    [Fuel flow at sea level: military power / full afterburner], if sufa [13,500 / 59,900 lb an hour] else [10,900 / 63,600 lb an hour],
  )
  The weights are the #jet.short's with full internal fuel and no stores: #if sufa [29,350 lb] else [24,900 lb]. Stores lower every figure but the thrust.
]
