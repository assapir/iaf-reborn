#import "../ch4/src.typ": *

#block-head

=== At the limiter

With a category I load and the stick fully back the jet holds about 25° angle of attack#fm[section I, "AOA/g limiter", page 1-121]. It does not stall with a break as a jet without a limiter does, and the speed falls fast instead (inferred). Roll is reduced there, so that pitch and roll together do not throw the jet#fm[section VI, "Category I loadings", page 6-3].

=== How the limiter is defeated

A departure is the jet leaving controlled flight: it moves by itself or does not answer the controls#fm[section VI, "Out-of-control characteristics", page 6-8]. The limiters prevent most departures. They are defeated in these ways:

- *Nose high, speed falling.* Below the speed of the warning tone the tail has too little air (@limits-airspeed). Going over the top of a loop too slowly ends in an inverted departure#fm[section VI, "Pitch departure", page 6-9].
- *Abrupt stick below 200 kt.* Pitch and roll together, moved sharply, can depart the jet at any attitude. With smooth movements it is flown safely to the limiters below 200 kt#fm[section VI, "Pitch departure", page 6-9].
- *Yaw.* Near the CAT I limiter at Mach 0.80 to 0.95, above all above 25,000 ft, a full-stick roll can slice the nose sideways. A centreline store, pods under the intake and an asymmetry of more than 300 lb make it likely; left-wing-heavy loads more than right#fm[section VI, "Yaw departure", page 6-8].
- *Aft centre of gravity, open speedbrakes, stores.* Each lowers the resistance to a departure#fm[section VI, "Category I loadings", page 6-3, and "Pitch departure", page 6-9]. In the two-seat jet with external tanks the centre of gravity is furthest aft just as the tanks empty#fm[section VI, "Center-of-gravity considerations", page 6-5].

=== Recovering a nose-high, slow jet

Release the back pressure first. Roll smoothly, inverted, to the nearest horizon, and pull gently to keep the nose moving down; do not pull sharply at any time. With the nose down and the speed rising, roll upright above 150 kt, or pull through above 200 kt if the height allows. Judge the nearest horizon by the flight path, not by the nose: the two can differ by 25°#fm[section VI, "High pitch, low airspeed", page 6-6].

=== What a departure looks like

- *Yaw departure.* An abrupt slice of the nose, then uncommanded motions; a pitch departure usually follows. It ends by itself within 5 to 20 seconds, or in a #term("deep stall") or a spin#fm[section VI, "Yaw departure", pages 6-8 and 6-9].
- *Pitch departure.* The angle of attack passes the limiter. The indicator stands at the end of its scale, 32° or −5°, and the airspeed reads falsely. The computer holds the tail fully against it, and the stick does nothing without #row("SW_MPO")#fm[section VI, "Pitch departure", page 6-9].
- *Self-recovery, deep stall, spin.* What the pilot does is in @emergency-control.

=== Category III loads

With the switch at #term("CAT III") the limiter stops at 16° to 18°#fm[section I, "AOA/g limiter", page 1-121] and the limiter then resists departure with every load#fm[section VI, "Category III loadings", page 6-3]. A departure with an asymmetric category III load can end in a fast, flat spin that may not be recoverable#fm[section V, "Low airspeed operating limitations", the warning, page 5-3].

#in-sim[
  - *At the limiter.* Full back stick holds about 25° in CAT I, 15.5° to 18° in CAT III; the speed falls and the jet stays under control. A full pull at 200 kt peaks near 27°.
  - *Departure.* The jet can be driven past the limiter into a deep stall, where it stays near 59° with the hands off; the recovery works as in @emergency-deep-stall. Above 29° the computer works the ailerons and the rudder against the yaw.
  - *The stall.* In level flight at 1 g the #jet.short's least speed is about #if sufa [136] else [125] kt, clean, at sea level.
  - #term("Not modelled"): the yaw departure and the nose slice, the inverted deep stall, the spin as the real jet flies it, the effect of the centre of gravity, of the open speedbrakes and of the stores on the resistance to a departure, the false airspeed in a departure.
]
