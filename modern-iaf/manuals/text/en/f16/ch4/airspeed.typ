#import "src.typ": *

#block-head

=== Maximum speed

The jet is limited to 800 kt from sea level to 30,000 ft, and to Mach 2.05 above 30,000 ft. Stores and systems lower the limit (below). The engine's thrust is enough to pass the limit in level flight, so the pilot watches the airspeed#fm[section V, "Maximum airspeed operating limitations" and the caution before it, page 5-2].#block-note

A greatest height is not among the manual's limits; the #jet.short's service ceiling is open.

=== System speed limits

#table(
  columns: (1fr, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  table.header([*System or condition*], [*Limit*]),
  [Canopy open or moving], [70 kt, the wind on the ground included],
  [Landing gear down or moving], [300 kt or Mach 0.65, the lower],
  [Air refuelling door opening or closing], [400 kt or Mach 0.85, the lower],
  [Air refuelling door open], [400 kt or Mach 0.95, the lower],
  [Severe turbulence], [500 kt],
  [Main tyres on the runway], [225 kt of ground speed],
)
The limits are the flight manual's#fm[section V, figure 5-6, page 5-15, and "Tire speed limit", page 5-2].#block-note The nose tyre's limit is 217 or 235 kt by the jet's build#fm[section V, "Tire speed limit", page 5-2]; which holds for the #jet.short is open.

The trailing-edge flaps have no speed limit of their own: they follow the gear handle and come up by themselves as the speed rises above 240 kt (@flight-controls).

=== Low speed

A steady tone in the headset warns of a low speed with the nose high. Start the recovery no later than the tone. With a category I load of high drag (a drag index above 120), waiting for the tone can be too late: the speed falls so fast that the controls lose their grip on the air#fm[section V, "Low airspeed operating limitations" and its warning, page 5-3]. With a #term("CAT III") load do not fly below 200 kt except for take-off and landing#fm[section V, "Low airspeed operating limitations", page 5-3].

=== Stores

Each store has its own carriage and release speeds. They are in the stores supplement of the flight manual, which is not public: open.

#in-sim[
  - *Gear.* Above 300 kt or Mach 0.65 with the gear down or moving #sym.arrow.r *the gear is damaged and stays where it is.*
  - *Maximum speed.* Past 800 kt or Mach 2.05 the overspeed is counted. Past 880 kt or Mach 2.25 #sym.arrow.r *the structure is damaged* (@limits-g). Past 920 kt or Mach 2.36 #sym.arrow.r *the airframe fails from flutter, and the jet is lost.* The margins are inferred. The #jet.short reaches about #if sufa [Mach 1.19] else [785 kt (Mach 1.19)] at sea level and Mach 1.99 at 40,000 ft in level flight, clean, with full afterburner.
  - *Low speed.* A tone sounds above about 27° angle of attack.
  - *Tyres.* A main tyre on the runway above 225 kt of ground speed #sym.arrow.r *bursts:* its wheel runs on the rim, does not brake and pulls the jet toward its side.
  - #term("Not modelled"): the canopy's, the refuelling door's and the turbulence limits; the nose tyre's limit; the stores' speed limits.
]
