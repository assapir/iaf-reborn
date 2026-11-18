#import "src.typ": *

=== Aborted take-off <emergency-abort>
#state("part")

#idx("Abort")An abort is a take-off given up on the runway. Whether to abort depends on the runway left and its surface, the jet's weight, the fault and the speed; an early decision is the best one, and above 100 kt an abort needs the procedure flown exactly#fm[section III, "Abort", pages 3-33 and 3-34].

+ Throttle to idle. From full afterburner the thrust takes 2 to 4 seconds to fall.
+ Before rotation: keep the nose down and brake as hard as the stop needs. After rotation: hold the nose up, brake fully, and let the nose fall by itself; then the stick fully back, the speedbrakes fully open and full braking.
+ Hook down if there is any doubt about stopping, at least 1,500 ft before the cable.
+ On fire: throttle to OFF and #row("SW_MASTER_FUEL") to OFF once stopped.

#caution[Braking with the engine above idle heats the brakes far more and can start a wheel fire (@emergency-hot-brakes). A late rotation is no reason to abort: heavy stores and a nose strut serviced wrongly can delay it by up to 25 kt#fm[section III, "Delayed rotation", page 3-33].]

#in-sim[#key("Throttle idle"), then hold #key("Wheel brakes (hold)") and #key("Speedbrakes open (hold)") #sym.arrow.r *the wheels brake and the speedbrakes open.* #term("Not modelled"): the hook, the cable and hot brakes. The sim's jets carry no drag chute.]

=== Engine failure on take-off <emergency-takeoff-engine>
#state("none")

An engine that fails just after lift-off leaves no time to analyse. Before lift-off, abort. After it#fm[section III, "Engine failure on takeoff", page 3-34]:

+ Zoom: trade the speed above the glide for height.
+ Jettison the stores, if there is time.
+ Eject before the jet starts to sink.

With low thrust that still flies the jet, select the afterburner; if that does not light, the engine's secondary control (ENG CONT at SEC), which gives #if sufa [70 to 80~%] else [70 to 95~%] of military thrust and no afterburner#fm[section III, "Low thrust on takeoff or at low altitude", #if sufa [page 3-35] else [page 3-36: the figure of the manual's General Electric engine, the F110-GE-129; for the #jet.short's F110-GE-100 it is inferred]].

=== Engine fire on take-off <emergency-takeoff-fire>
#state("none")

It shows as in the air: *#row("lamp_eng_fire_0")*, *#row("lamp_caution_overheat_0")*, high #term("FTIT"), smoke#fm[section III, "Engine fire on takeoff", page 3-36]. Abort if the runway allows. If not, climb at take-off thrust to the lowest safe height for an ejection and go on with @emergency-fire.

=== The gear does not come up <emergency-gear-up>
#state("none")

*The red light in the gear handle stays on* after the handle is raised: the gear or its doors are not locked up#fm[section III, "LG fails to retract", page 3-36].

+ Stay below 300 kt.
+ Gear handle down, once. Do not cycle it: that can damage the gear and the doors.
+ With three green lights: burn fuel down to a landing weight and land. Without them: @emergency-alt-gear.

=== Blown tyre on take-off <emergency-takeoff-tyre>
#state("none")

A tyre that fails on the take-off roll is hard to notice from the cockpit#fm[section III, "Blown tire on takeoff", page 3-37]. At high speed an abort with a blown tyre can be more dangerous than taking off, most of all at a heavy weight, because braking and steering are both impaired#fm[section III, "Abort", page 3-33]. The landing that follows is in @emergency-tyre.
