#import "src.typ": *

=== The gear does not come down <emergency-alt-gear>
#state("part")

#row("ALT_GEAR"), under its guard #row("ALT_GEAR_GUARD"), lowers the gear by a second way when the handle does not (inferred from its name; the real steps and limits are open).

#in-sim[
  - A hit, the gear down above 300 kt, or a touchdown harder than 10 ft/s damages the gear. #sym.arrow.r *GEAR FAIL; the gear stays where it is.*
  - ALT GEAR, with its guard open, lowers the gear as the handle does.
  - A touchdown with the gear up destroys the jet. If the gear is stuck up, eject.
]

=== Landing with damage <emergency-damage-landing>
#state("part")

The public rules: land elsewhere if the landing roll worked out for the runway is more than 80~% of its length, and never land over a raised barrier#afi[paragraph 3.21.4]; land straight in with a flight control fault#afi[paragraph 7.4.3]. The rest is open.

#in-sim[With *FLCS DEGD* fly a long, flat, straight-in approach. With *BRAKES FAIL* use the whole runway and hold the nose up to slow down (@landing).]

=== Cable arrestment <emergency-cable>
#state("none")

#idx("Hook")The hook is lowered whenever stopping is in doubt (@emergency-abort). After the stop the engine stays running, the hook comes up on the ground crew's signal, and the jet waits to be told before it taxis#afi[paragraph 7.11].

#in-sim[The HOOK switch moves only; the sim's runways have no cable.]
