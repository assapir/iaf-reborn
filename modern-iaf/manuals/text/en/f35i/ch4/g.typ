#import "src.typ": *

The flight control system holds the jet inside these limits by itself (@flight-controls).

- *Load factor.* +9 g#card-a. The negative limit is open.
- *Angle of attack.* 50°#aoa50.
- *Over-g.* After an over-g the pilot lands, and the jet is inspected#afi[paragraphs 7.4.4 and 3.28]. The greatest g of the flight is shown to the pilot, who reads it at the checks in flight#afi[paragraph 3.14.2].
- *With stores, with the gear down, while rolling.* Lower limits, if any: open. The F-35 has no switch for categories of stores (inferred: its cockpit shows none); the computer knows the load.
- *Prohibited manoeuvres.* Open. Aerobatics are flown above 5,000 ft above the ground#afi[paragraph 3.13.4].

#in-sim[
  - The limiter holds +9 and −3 g (the −3 is the F-16's, inferred) and 50° angle of attack. Past 9.5 or −3.2 g the over-g is counted. Past 10.4 or −3.45 g #sym.arrow.r *the structure is damaged:* "Structural damage", the master caution and more drag; from then on it fails at 11.7 or −3.9 g. Past 13.5 or −4.5 g #sym.arrow.r *the airframe fails, and the jet is lost.* The margins are inferred.
  - The limits are the same with every load.
  - #term("Not modelled"): the maximum-g readout.
]
