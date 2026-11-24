#import "src.typ": *

No public source gives the #jet.short's procedures for electrical or flight control failures: open. The rule that is public is to land from a straight-in approach with any flight control fault#afi[paragraph 7.4.3]. The jet's controls are moved by electrically powered actuators (@flight-controls, @hydraulic), so the two kinds of failure are closely tied (inferred).

=== Loss of the displays or of orientation <emergency-displays>
#state("none")

A pilot who loses the sense of attitude looks at the instruments more often, calls up the full flight instrument format, flies straight and level for about a minute, and considers the autopilot#afi[paragraph 7.9]. If the helmet's night picture fails, the first move is to the instruments#afi[paragraph 3.19.8.2].

=== Radio failure <emergency-radio>
#state("none")

Without a radio the pilot joins another jet, sets the transponder to 7600 (7700 with an emergency as well), lowers the hook to ask for a cable, and flashes the landing light on final#afi[paragraphs 7.6.2.2, 7.6.6.3 and 7.8.5].

=== Jettison <emergency-jettison>
#state("full")

#idx("Emergency jettison")#row("EMER_JETT") drops the stores in one press (inferred from its name; the real sequence is open).

#in-sim[#key("Emergency jettison") or the button #sym.arrow.r *the stores #row("JETT_SEL") selects fall, unarmed: ALL every station, EXT the external stations only, SEL the selected store's stations; the bay doors open for a bay store; the air-to-air missiles stay.* On the ground nothing is dropped.]

#in-sim[What damage does: *ELEC FAIL* takes the radar and the warning receiver, and when total the weapons and the displays' flight data too; *FCS DEGD* leaves the stick a quarter of its authority: fly gently and land straight in; *FCS FAIL* stops the surfaces: eject. #row("FCS_RESET") moves only.]
