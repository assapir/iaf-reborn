#import "src.typ": *

The #jet.short carries all its fuel inside: 18,250 lb#card-a. It refuels in the air through a receptacle on its back, from a tanker's boom#wiki[F-35A]. The layout of the tanks is not public.

The fuel quantity is on the #term("PCD"): the FUEL format, and the total in the bar at its top (@pcd).

=== Joker and bingo

Two quantities are set for a flight:

- #term("Joker fuel") is the higher one: the fuel at which the pilot ends what the flight is doing and starts for home.
- #term("Bingo fuel") is the lower one: the fuel needed to fly home and land with a reserve. At bingo the jet goes straight home.

Neither is a fault. A pilot may set them higher for a short flight or a far alternate (inferred: the two words are general fighter practice, not taken from an F-35 source).

#in-sim[
  - *Quantity.* The jet starts with 18,250 lb. It carries no external tanks.
  - *Joker and bingo* are fixed: 5,500 lb and 3,600 lb. The FUEL format marks them, and the bar at the top of the display shows the joker quantity (JKR), in yellow below joker. The voice says "Bingo" below 1,000 lb and again below 500 lb.
  - With no fuel left the engine gives no thrust.
  - *#term("Not modelled").* Separate tanks and their order of emptying, fuel dump, air refuelling, and setting joker and bingo.
]
