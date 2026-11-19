#import "src.typ": *

=== Maximum speed

The F-35A's top speed is Mach 1.6 at height and 700 kt at sea level#wiki-speed. A greatest height is open.

=== System speed limits

The speed limits of the landing gear, the canopy, the weapon bay doors, the refuelling door and the tyres are open. #fsd

=== Low speed

The low-speed warning tone marks the least speed for manoeuvring#afi[paragraph 3.13.2]. The speeds on the approach are bounded from below by the flight manual's approach speeds#afi[paragraph 4.7.1], which are open.

=== Other flying limits

- Taxi at 30 kt at most, 10 kt in turns#afi[paragraph 3.4.1].
- Flight in icing conditions was prohibited when the rules were written#afi[paragraph 4.9]; whether it still is, is open.

#in-sim[
  - *Gear.* Above 300 kt or Mach 0.65 with the gear down or moving #sym.arrow.r *the gear is damaged and stays where it is.* The figure is the F-16's (inferred).
  - *Maximum speed.* Past 700 kt or Mach 1.6 the overspeed is counted. Past 770 kt or Mach 1.76 #sym.arrow.r *the structure is damaged.* Past 805 kt or Mach 1.84 #sym.arrow.r *the airframe fails from flutter, and the jet is lost.* The 700 kt and the margins are inferred. The #jet.short reaches about 750 kt (Mach 1.14) at sea level and Mach 1.6 at 40,000 ft in level flight with full afterburner.
  - *Low speed.* A tone sounds above about 52° angle of attack.
  - *Tyres.* A main tyre on the runway above 225 kt of ground speed #sym.arrow.r *bursts:* its wheel runs on the rim, does not brake and pulls the jet toward its side. The figure is the F-16's (inferred).
  - #term("Not modelled"): the bay doors' and the canopy's limits, icing, the taxi speed limit.
]
