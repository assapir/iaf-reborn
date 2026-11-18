#import "src.typ": *

#block-head

=== Weight

#if sufa [
  The #jet.short's maximum take-off weight is 23,582 kg, about 52,000 lb#aft. The public flight manual's jet, without the #jet.short's changes, is limited to 48,000 lb for ground handling, taxi, take-off, flight and landing#fm[section V, "Gross weight limitations", page 5-3]. A separate landing weight for the #jet.short is open.
] else [
  The maximum take-off weight of the F-16D of Block 40 is 42,300 lb#b40. The public flight manual's jet, of Blocks 50 and 52, is limited to 48,000 lb for ground handling, taxi, take-off, flight and landing#fm[section V, "Gross weight limitations", page 5-3]. A separate landing weight for the #jet.short is open.
]

=== Centre of gravity

The fuel's distribution between the forward and aft tanks sets the centre of gravity. The jet is generally inside its limits while the red part of the aft-left pointer of the fuel quantity indicator is hidden, with FUEL QTY SEL at NORM#fm[section V, "Center-of-gravity limitations", page 5-3]. The limits themselves are in a supplement that is not public: open.

=== Asymmetric loads

An asymmetric load is one that needs roll or yaw trim. The greatest rolling moment allowed, on the ground and in flight, is 25,020 ft-lb. Take-off is prohibited when the load needs more roll trim than the jet has#fm[section V, "Asymmetric stores loading", page 5-4].#block-note

=== Stores

What each station may carry, and each store's limits of speed, g and release, are in the stores supplement of the flight manual: open. Only the two categories and what they do to the jet's limits are public (@limits-g).

=== Landing and the runway

- *Sink rate.* The flight manual gives no figure for the touchdown: open.
- *Pitch.* Above 15° of pitch on the runway the nozzle, the speedbrakes and the ventral fins can touch it (@landing-roll)#fm[section II, "Normal landing", the caution, page 2-24].
- *Brakes.* Each brake can take up a fixed amount of energy; a stop from too high a speed loses the brakes before the jet stands. The speeds are in the performance supplement: open#fm[section V, "Brake energy limits", page 5-2].
- *Crosswind.* The limits for take-off and landing are in the performance supplement: open#fm[section V, "Crosswind limits", page 5-5]. The technique is in @handling-takeoff-landing.
- *Arresting gear.* The hook takes the cable systems and the nets take the jet as the manual lists them#fm[section V, "Net arrestment limitations", page 5-5]; the engagement speeds are in a figure this copy shows as a picture: open.

#in-sim[
  - *Weight.* The #jet.short's maximum take-off weight is #if sufa [52,000 lb (23,582 kg)] else [42,300 lb (19,187 kg)]. A load that passes it is refused when the jet is loaded.
  - *Asymmetry.* A load whose rolling moment passes 25,020 ft-lb is shown with a warning when the jet is loaded; it can be flown.
  - *Touchdown.* Sinking faster than 10 ft/s #sym.arrow.r *the gear is damaged.* Sinking faster than 13 ft/s, more than 10° of bank or the nose below −5° #sym.arrow.r *the jet is lost.* Above 15° of pitch #sym.arrow.r *a tail strike, and the jet is lost.*
  - *Crosswind.* No limit. The jet keeps to the runway in a 25 kt crosswind.
  - #term("Not modelled"): the centre of gravity (the fuel and the stores sit at it), the brakes' energy, the hook and the arresting gear, the stores' own limits.
]
