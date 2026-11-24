#import "src.typ": *

=== Flameout landing <emergency-flameout-landing>
#state("part")

#idx("Flameout landing")A flameout landing is a landing with no thrust: one approach, no go-around. It is chosen when the engine will not start and a runway is within the glide; the whole pattern stays inside the seat's envelope, and a doubtful approach is ended by ejecting, not saved#fm[section III, "Flameout landing", page 3-98].

+ Turn to the runway at once, jettison the stores and hold the best-glide speed (@emergency-airstart).
+ Arrive over the runway at *high key*, 7,000 to 10,000 ft above the ground, and turn once around to *low key*, abeam the touchdown point at 3,000 to 5,000 ft#fm[section III, "Flameout landing", pages 3-99 and 3-105].
+ Lower the gear in the pattern, by the alternate way if the hydraulics need it (@emergency-alt-gear); do not let the speed fall under the gear-down glide speed to stretch the glide.
+ Aim a third of the way down the runway; when the landing is sure, move the aim short of the touchdown point. Flare and touch down at 11° to 13° angle of attack.
+ Stop with one steady braking; expect about twice the normal ground roll (8,000 ft of runway advised).

#in-sim[The glide and the landing can be flown with the engine stopped. The gear, the brakes and the flight controls keep their normal power: the hydraulics' part is #term("not modelled"). The displays stay up while the #term("EPU") runs.]

=== The gear does not come down <emergency-alt-gear>
#state("none")

*One or more of the three green lights stays dark*, or *the red light in the handle stays on*. The alternate extension lowers the gear with stored air, for a jet whose hydraulic pressure is lost#fm[section III, "Alternate LG extension", page 3-139].

+ Gear handle down (with the down-lock release if it does not move).
+ Slow, to 190 kt if practical: the system works up to 300 kt, but the nose gear may not lock above 190 kt.
+ Pull #row("alt-gear").
+ Three green: land normally and stop straight ahead; the nosewheel steering is lost. Not three green: below.

=== Landing with the gear unsafe or up <emergency-gear-unsafe>
#state("part")

Weigh the airfield, the hook's limits, the crosswind and the runway; if they are against the landing, eject under control instead (@ejection). To land: keep the empty tanks and the racks, jettison the weapons, burn the fuel down, switch the radar and the stores stations off, lock the shoulder harness#fm[section III, "Landing with LG unsafe/up", page 3-140].

#in-sim[
  - A hit, the gear down above 300 kt, or a touchdown harder than 10 ft/s damages the gear. #sym.arrow.r *The gear lights show it in transit, and it stays where it is.*
  - A touchdown with the gear up destroys the jet. If the gear is stuck up, eject.
  - #row("alt-gear") moves only.
]

=== Blown tyre <emergency-tyre>
#state("none")

Before landing with a tyre known to be blown: jettison the stores but keep empty tanks, reduce the weight, and take the pressure off the external tanks with #row("SW_AIR_REFUEL") at OPEN, since a pressurised tank that breaks on the runway can explode#fm[section III, "Landing with a blown tire", page 3-136]. With a blown nose tyre hold the stick fully back on the roll, keep off the centreline lights, stop straight ahead and do not taxi#fm[section III, "Blown tire on takeoff", page 3-38, and "Landing with a blown tire", page 3-135].

=== Cable arrestment <emergency-cable>
#state("none")

#idx("Hook")The hook under the tail catches a cable across the runway and stops the jet in a short distance. It is used whenever stopping on the runway left is in doubt: no brakes, an abort, a wet runway. Put #row("SW_HOOK") down at least 1,500 ft before the cable, slow as much as you can, and cross the cable in its middle, nosewheel on the runway, brakes off, aligned with the runway#fm[section III, "Cable arrestment", page 3-134].

#in-sim[The switch lights the HOOK caution only; the sim's jets and runways have no hook and no cable.]

=== Landing with damage <emergency-damage-landing>
#state("part")

After damage to the structure or the controls, the real pilot tries the jet at a safe height in the landing configuration, slowing only as far as it still handles well; if it cannot be controlled down to a reasonable landing speed, ejection is advised#fm[section III, "Controllability check", pages 3-133 and 3-134].

#in-sim[Do the same check. With hydraulic damage (@emergency-hydraulic) fly a long, flat, straight-in approach. With brake damage use the whole runway and aerodynamic braking (@landing-roll).]
