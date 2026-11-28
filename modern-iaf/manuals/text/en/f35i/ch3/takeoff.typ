#import "src.typ": *

=== Aborted take-off <emergency-abort>
#state("part")

#idx("Abort")An abort is a take-off given up on the runway. The public rules: lower the hook on an abort whenever stopping is in doubt, and call "Cable, cable, cable" (or "Barrier, barrier, barrier") so that the airfield knows the jet will take the cable#afi[paragraphs 7.3.1 and 7.3.3]. After the cable has stopped the jet, keep the engine running, raise the hook on the ground crew's signal, and do not taxi until told#afi[paragraph 7.11]. The abort's speeds and steps are open.

#in-sim[#key("Throttle idle"), then hold #key("Wheel brakes (hold)") and #key("Speedbrakes open (hold)") #sym.arrow.r *the wheels brake and the speedbrakes open.* #term("Not modelled"): the hook and the cable.]

=== Engine failure, fire or a tyre failure on take-off <emergency-takeoff-engine>
#state("none")

#open-proc

=== The gear does not come up <emergency-gear-up>
#state("part")

In the crash of an F-35A at Eielson Air Force Base on 28 January 2025, water in the gear struts' hydraulic fluid froze, and the gear did not retract after take-off. The weight-on-wheels sensors then put the flight controls into their mode for the ground while the jet flew, and the pilot ejected. The board found that such a jet is best kept in the air for a planned full-stop landing#footnote[The Aviationist, "Hydraulic Fluid Contamination and Ice Buildup Led to January F-35A Crash in Alaska", 26 August 2025, on the accident investigation board's report, #link("https://theaviationist.com/2025/08/26/eielson-january-2025-f-35-crash-aib-report/"). Checked 28 November 2026.]. The checklist itself is open.

#in-sim[A set gear fault #sym.arrow.r *GEAR FAIL on the ICAWS; the gear stays where it is, whatever the handle does.* Stay below 300 kt with the gear down (faster damages it), hold, then land straight in to a full stop. #term("Not modelled"): the flight controls' ground mode in the air.]
