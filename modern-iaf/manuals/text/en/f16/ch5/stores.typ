#import "../ch4/src.typ": *

#block-head

Stores add weight, inertia and drag. The jet answers more slowly and damps its motions less, so the pilot starts and stops each manoeuvre earlier. Stores generally lower the stability in pitch and in yaw#fm[section VI, "Flight with stores", page 6-6].

=== Category III loads

Large stores add much drag and take performance, and the jet otherwise answers like a clean one. A light buffet near Mach 0.92 in level flight is normal#fm[section VI, "Category III loadings", page 6-3]. Stop a roll before 360° of bank; letting go of the stick is not always enough, and opposite stick may be needed#fm[section VI, "Flight with stores", page 6-6].

#if sufa [
=== Conformal tanks

The conformal tanks change the handling little. The jet is looser in yaw: it shows more sideslip in rolling and turning, felt in tracking and behind the tanker. Use the rudder only as needed, without abrupt or large movements#fm[section VI, "Conformal fuel tanks", page 6-3].
]

=== Oscillations

- *With 600-gallon tanks.* Above Mach 0.80 the jet is sensitive in pitch; small uncommanded changes of pitch and bank can come above Mach 0.85. Fly smoothly, and slow down if it disturbs#fm[section VI, "Factors affecting flying characteristics", pages 6-4 and 6-5].
- *Limit cycle oscillation.* With some loads the wing and its stores shake at a steady 5 to 10 cycles a second, felt as a sideways or vertical buffet that grows with speed and g. Inside the stores' limits it does not harm the jet. Reduce the speed or the g#fm[section VI, "Limit cycle oscillation and aeroservoelastic oscillation", page 6-7].

=== Asymmetric loads

- The jet rolls toward the heavy wing; stick or roll trim away from it holds the wings level, and more g needs more of it#fm[section VI, "Asymmetric loadings", page 6-7].
- Roll trim brings rudder with it, so the jet yaws a little away from the heavy wing#fm[section VI, "Asymmetric loadings", page 6-7].
- An asymmetric load departs and spins more easily, a left-heavy one more than a right-heavy one. With 2,000 lb or more on one middle wing station and stores inboard, an abrupt pull can slice the nose#fm[section VI, "Asymmetric loadings", the warnings and the note, page 6-7].
- The limit of the asymmetry is in @limits-weight.

=== Release

Stores released in pairs, and missiles fired from the wing tips, do not disturb the jet. A 300-gallon centreline tank pushes the jet to negative g as it leaves, up to −1.5 g when full and supersonic. One 370-gallon wing tank dropped alone gives up to +1 g and 15° of bank away from it#fm[section VI, "Store separation", page 6-8].

#in-sim[
  - *Weight and drag.* Each store, rack, pod and tank has its weight and its drag. The jet accelerates, climbs and turns worse with them, and burns more fuel.
  - *Asymmetry.* A heavy wing rolls the jet toward it, more under g; the roll trim holds it. The side with more drag yaws the jet toward it. A store released from one wing leaves the jet rolling toward the other.
  - *#term("CAT III").* The switch changes the limits (@limits-g). A category III load lowers the directional stability above the CAT III line: at CAT I the jet yaws off near 25°.
  - #term("Not modelled"): the lower stability with category I stores, the looseness in yaw with the conformal tanks, every oscillation and buffet, the yaw from the roll trim, the push of a tank as it leaves.
]
