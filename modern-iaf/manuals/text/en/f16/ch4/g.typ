#import "src.typ": *

#block-head

The #term("FLCS") holds the jet inside most of these limits by itself (@flight-controls). The limits it does not hold are the pilot's: the rolling limits, the stores' limits and the limits with the gear down.

=== Load factor

- *Positive.* +9 g below 15° angle of attack, and less as the angle of attack rises#fm[section I, "AOA/g limiter", page 1-121].
- *Negative.* −3 g above about 250 kt; below it between −3 g and zero, by speed, height and angle of attack#fm[section I, "AOA/g limiter", page 1-121].
- *Over-g.* A pull on the limiter that reads 9.5 g or more, or −3.2 g or less, is reported for an inspection of the jet#fm[section V, "Acceleration limitations", page 5-3].
- *Rolling.* The FLCS does not protect the lower g limits that hold while the jet rolls#fm[section VI, "Normal flight characteristics", the warning, page 6-3]. A manoeuvre counts as rolling when the roll rate passes 20° a second or the stick is moved sideways abruptly#fm[section V, "Acceleration limitations", the note, page 5-4]. The figures are in the stores supplement: open.
- *With the gear.* Take-off and landing: +4 to 0 g in symmetric flight, +2 to 0 g while rolling. Gear moving: +2 to 0 g#fm[section V, figure 5-7, page 5-15].

=== Angle of attack and the stores categories

A load is of category I or category III. Category I loads leave the jet its full manoeuvring; category III loads are heavy or large stores with which the jet departs more easily (@handling-stores). Which category a load has is listed in the stores supplement: open. #row("SW_STORES_CONFIG") is set to match the load.

#table(
  columns: (auto, 1fr, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  table.header([], [*CAT I*], [*#term("CAT III")*]),
  [Greatest angle of attack], [About 25°: the g allowed falls to 1 g at 25°], [About 16° to 18°, by weight and g],
  [Roll], [Full], [Reduced],
  [Greatest change of bank in one roll at full stick], [360°], [360°],
)
The limits are the flight manual's#fm[section I, "AOA/g limiter", page 1-121, and section V, figure 5-8, page 5-15].#block-note

#warning[Do not fly a category III load with the switch at CAT I, except in an emergency. The limiter then gives no protection against a departure, and rolling can damage the wing's structure#fm[section V, "AOA and rolling limitations" and its warnings, page 5-4].]

=== Prohibited manoeuvres

- Intentional departures and spins with a category III load, an asymmetric load, stores on the middle or inboard wing stations, the centre of gravity behind its aft limit, a fuel imbalance of more than 200 lb between the sides, or below 30,000 ft above the ground.
- Repeated full rudder reversals, and several full-stick 360° rolls one after another.
- Full-stick rolls above Mach 1.8 when above 3 g or below 35,000 ft.
- Rolls made or helped with the rudder through more than 90° of bank, with any store on the middle or inboard wing stations.
- With the gear or the flaps down: more than 15° angle of attack with stores on the middle or inboard wing stations, and full-stick rolls through more than 90° of bank.
- Abrupt roll reversals above 550 kt below 20,000 ft with the switch at CAT I#if sufa [; with the conformal tanks, above 500 kt].
- A rapid release or reversal of the rudder above 300 kt or Mach 0.6. The manual marks this for some builds of the jet only; whether it holds for the #jet.short is open.
#if sufa [- Flight with the conformal tanks and a category III load. The manual marks this for some builds only; whether it holds for the #jet.short is open.]

The list is from the flight manual's#fm[section V, "Prohibited maneuvers", page 5-3].#block-note

#in-sim[
  - *Load factor.* The limiter holds +9 and −3 g; a full pull at high speed peaks near 9.3 g. Nothing breaks from g, and no inspection follows.
  - *Angle of attack.* CAT I: 25°. CAT III: 15.5° to 18°, by weight, with the roll reduced to about 60~% and the pedals faded out by 15°. #row("SW_STORES_CONFIG") is read; it starts at CAT I.
  - A category III load flown at CAT I has the CAT I limits: the sim does not make it depart more easily.
  - #term("Not modelled"): the rolling g limits, the g limits with the gear down, the bank-change limit, the stores' categories as a list, the STORES CONFIG caution, damage from any prohibited manoeuvre.
]
