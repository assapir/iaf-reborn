#import "src.typ": *

=== A start out of order <emergency-start-order>
#state("part")

The #jet.short's start is three selections in order: battery, #term("IPP"), engine (@cold-start). The IPP gives the air that turns the engine, so the engine switch has nothing to work with until the IPP is up to speed. What the real jet does with a start out of order is open; a fault of the start would show as an ICAWS message (inferred).

#in-sim[
  - #row("ENG") selected with the IPP not running, or less than 10 seconds after its start #sym.arrow.r *nothing happens.* Wait for the IPP and select it again.
  - #row("IPP") with #row("BATT") off #sym.arrow.r *nothing happens.*
  - #term("Not modelled"): a hot or hung start, and motoring the engine (the ENG switch's MOTOR position moves only).
]

=== Fire on the ground and leaving the jet <emergency-ground-fire>
#state("none")

#open-proc The cockpit has the parts such a procedure would use: the #row("lamp_eng_fire_0") light, which is also a push-button, #row("IPP_EMER_OFF") and the canopy (their use is inferred from their names).

=== Ice at the intake <emergency-ice>
#state("none")

A jet that stands for long with the engine running in icing weather has its intake watched. If ice is seen the engine is shut down at once, and the intake is inspected before the next start#afi[paragraphs 3.3.2.2 to 3.3.2.4]: ice breaking off goes through the engine.

=== Brake failure while taxiing <emergency-brakes>
#state("part")

With the brakes lost on the ground the pilot lowers the hook: it is the signal to the ground crew#afi[paragraph 3.2.6]. A jet stopped with hot brakes goes to the airfield's hot-brake area#afi[paragraph 7.3.2]. The steps in the cockpit are open.

#in-sim[Damage to the brakes #sym.arrow.r *BRAKES FAIL; #key("Wheel brakes") and the speedbrake keys do nothing.* #row("HOOK") and #row("PARK_BRAKE") move only.]
