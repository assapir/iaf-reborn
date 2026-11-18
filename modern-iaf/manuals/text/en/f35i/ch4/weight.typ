#import "src.typ": *

=== Weight

The F-35A's maximum take-off weight is 65,918 lb#wiki[Specifications (F-35A)]. The #jet.short's own figure, a landing weight and the centre-of-gravity limits are open.

=== Stores and asymmetric loads

What each bay and wing station may carry is in @aircraft-stations. The stores' limits of speed, g and release, the limits with the bay doors open and the limit of an asymmetric load are open.

=== Landing and the runway

- *Runway.* Do not take off or land when the computed ground roll is more than 80~% of the runway#afi[paragraphs 3.6.2 and 3.21.4]. Touch down 500 to 1,000 ft past the threshold#afi[paragraph 3.21.1].
- *Crosswind, sink rate, brakes.* Open. #fsd
- *Hook.* The hook is lowered on an aborted take-off when the stop is in doubt (@emergency-abort)#afi[paragraph 7.3.3]. Its engagement speeds are open.

#in-sim[
  - *Weight.* The maximum take-off weight is 70,000 lb (31,751 kg). A load that passes it is refused when the jet is loaded.
  - *Asymmetry.* No limit, and no warning.
  - *Touchdown.* Sinking faster than 10 ft/s #sym.arrow.r *the gear is damaged.* Sinking faster than 13 ft/s, more than 10° of bank or the nose below −5° #sym.arrow.r *the jet is lost.* Above 15° of pitch #sym.arrow.r *a tail strike, and the jet is lost.* The figures are the F-16's (inferred).
  - *Crosswind.* No limit.
  - #term("Not modelled"): the centre of gravity, the brakes' energy, the hook, the runway-length rule.
]
