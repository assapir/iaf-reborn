#import "src.typ": *

#block-head

The engine's limits are read on four gauges: #term("RPM"), #term("FTIT"), oil pressure and the nozzle position (@engine). Past a limit the engine can be damaged at once or lose life, so the pilot reduces power and lands (@emergency-engine).

=== Engine limits <limits-engine-table>

#table(
  columns: (auto, auto, auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  table.header([*Condition*], [*FTIT, °C*], [*RPM, %*], [*Oil pressure, psi*]),
  ..if sufa {
    ([Start on the ground], [800], [], [],
     [Idle on the ground], [625], [], [15 at least],
     [Military power and afterburner], [1,070], [97], [30 to 95],
     [Transient], [1,090, above 1,070 for 10 seconds at most], [98], [30 to 95],
     [Air start], [870], [], [])
  } else {
    ([Start on the ground], [935], [], [],
     [Idle on the ground], [650], [], [15 at least],
     [Military power and afterburner], [980], [108], [25 to 65],
     [Transient], [980], [109], [25 to 65],
     [Air start], [935], [], [])
  }
)
The limits are the flight manual's#fm[section V, figure 5-2, #if sufa [sheet 1, page 5-8] else [sheet 2, page 5-9]].#ge-note

- *Fluctuation.* The gauges may swing by ±10~°C, ±1~% RPM and #if sufa [±5~psi of oil pressure at idle, ±10~psi above idle,] else [±5~psi] inside the limits. #if sufa [Several gauges swinging together, or swings with surges of thrust, mean a fault of the engine control#fm[figure 5-2, sheet 1, the remarks, page 5-8].] else [The nozzle may swing by ±2~%#fm[figure 5-2, sheet 2, the remarks, page 5-9].]
- *Oil pressure.* It must rise with the RPM. Zero oil pressure is allowed for up to one minute in flight at less than +1 g#fm[figure 5-2, the in-flight remarks, pages 5-8 and 5-9].
- *Secondary engine control.* In SEC do not pull the throttle below military power while supersonic#fm[section V, figure 5-3, pages 5-10 and 5-11].

=== Jet fuel starter limits

- The #term("JFS") may turn the engine without fuel for 4 minutes at most; a normal start may follow after 5 minutes of cooling. Wait one minute after each start attempt, so that fuel drains from the JFS.
- After a #term("hot start") (@emergency-hot-start) the JFS turns the engine until the FTIT is below 200~°C.
- In flight the JFS is used only below 20,000 ft and below 400 kt (@emergency-airstart)#fm[section V, figure 5-4, page 5-12].#block-note

=== Fuel limits

- *Fuels.* JP-4, JP-5 and JP-8, their NATO grades and commercial Jet A, Jet A-1 and Jet B are approved, and may be mixed#fm[section V, "Fuels", page 5-1].
- *Negative g.* With both reservoir tanks full, flight at negative g is limited to 10 seconds in afterburner and 30 seconds at military power or below. Avoid it with a reservoir not full#fm[section V, "Negative G flight", page 5-2]. The reason is inferred: the reservoirs feed the engine while the fuel is thrown away from the tanks' outlets.
- *One reservoir empty.* The fuel flow is limited to 25,000 lb an hour#fm[section V, "Fuel system limitations", page 5-2].#block-note

#in-sim[
  - The start has one limit: the throttle leaves OFF at 20~% RPM or more. Below it the start is a hot start (@emergency-hot-start).
  - The gauges show the engine's state. No temperature, RPM or oil pressure limit can be passed, and none has a consequence.
  - #term("Not modelled"): the JFS's time limits, the negative-g time limits, the reservoirs and the fuel-flow limit, the kinds of fuel, SEC.
]
