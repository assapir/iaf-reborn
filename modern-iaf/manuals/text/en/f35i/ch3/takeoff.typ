#import "src.typ": *

=== Aborted take-off <emergency-abort>
#state("part")

#idx("Abort")An abort is a take-off given up on the runway. The public rules: lower the hook on an abort whenever stopping is in doubt, and call "Cable, cable, cable" (or "Barrier, barrier, barrier") so that the airfield knows the jet will take the cable#afi[paragraphs 7.3.1 and 7.3.3]. After the cable has stopped the jet, keep the engine running, raise the hook on the ground crew's signal, and do not taxi until told#afi[paragraph 7.11]. The abort's speeds and steps are open.

#in-sim[#key("Throttle idle"), then hold #key("Wheel brakes") #sym.arrow.r *the speedbrakes open and the wheels brake.* #term("Not modelled"): the hook and the cable.]

=== Engine failure, fire or a tyre failure on take-off <emergency-takeoff-engine>
#state("none")

#open-proc
