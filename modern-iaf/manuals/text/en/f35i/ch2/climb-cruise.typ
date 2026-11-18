#import "/modern-iaf/manuals/text/en/f35i/ch2/src.typ": *

This section takes the #jet.name from the end of the card's AFTER TAKEOFF section (@cold-start-after-takeoff) to the start of the approach. The card has no section for the cruise. The F-35's own procedures are not public; the rules here are the United States Air Force's for the F-35A.

=== The climb <climb>

No climb schedule of the F-35 is public: open. Two public rules shape the first part of the climb. At night, and in weather below a 1,500 ft cloud base or 3 miles' visibility, the jet climbs straight ahead on the runway's heading to 1,000 ft above the ground before its first turn#afi[paragraphs 3.18.3 and 4.2.2]. And the pictures of the night-vision systems in the helmet stay off below 2,000 ft above the ground in the climb#afi[paragraph 3.19.2].

#in-sim[Climb with #key("Throttle military power"), or with #key("Afterburner stage 2"). #term("Not modelled"): a climb schedule on the display.]

=== The checks in the climb and the cruise <cruise-checks>

#idx("Operational checks")The pilot checks the jet in the climb or at the level-off, and again at intervals; the systems are checked above 10,000 ft when that is practical#afi[paragraphs 3.8.5 and 3.14.1]. The check has at least six items#afi[paragraph 3.14.2]:

#table(
  columns: (auto, 1.2fr, 1.2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Check], [In the real jet], [In the sim]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [Cautions], [The messages of the caution and warning system (@warnings).], [#ctl("lamp_master_caution_0") and the display's messages.],
  [Fuel], [The total fuel, read from the display's fuel page. In a formation each pilot calls it; "same" means within 500 lb of the leader's#afi[paragraph 3.14.3].], [The display shows the fuel (@pcd). One jet: nothing to call.],
  [G-suit], [The hose is connected.], [Not modelled.],
  [Oxygen], [The supply to the mask.], [Not modelled.],
  [Cabin altitude], [The cabin's pressure, against the jet's height.], [Not modelled.],
  [Largest g], [The largest g the jet has recorded so far.], [Not modelled.],
)

=== Fuel: joker, bingo and the calls <cruise-bingo>

#idx("Bingo fuel")#idx("Joker fuel")Two fuel quantities are set before a flight#afi[paragraphs 3.20.1 and 3.20.2]. #term("Bingo fuel") is what the flight home and the landing need. #term("Joker fuel") is higher: at joker the pilot ends what the flight is doing, so that the jet is on its way home when it reaches bingo. Neither is a fault; each is a decision made on the ground, when there was time to think.

Three more numbers are the United States Air Force's for the F-35A:

#table(
  columns: (auto, 1fr, 1.4fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Fuel], [What it is], [Action]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [2,500 lb], [The normal fuel at the start of the final approach, unless the base sets more#afi[paragraph 3.20.3].], [Plan the flight home to arrive with it.],
  [1,800 lb or less], [Minimum fuel: about 20 minutes of flight at 10,000 ft at the speed of longest endurance#afi[paragraph 3.20.4.1].], [Tell the controller "minimum fuel": the jet can accept no delay.],
  [1,200 lb or less], [Emergency fuel#afi[paragraph 3.20.4.2].], [Declare an emergency and land at once.],
)

#in-sim[The display shows the fuel left. Not modelled: setting joker and bingo, and their warnings (@fuel). Compare the fuel with your own numbers at each check.]

=== The flight reference and the autopilot <cruise-autopilot>

The F-35 has no head-up display on its glareshield. In cloud the pilot flies by one of two references that the United States Air Force accepts as primary: the virtual head-up display drawn in the helmet when the pilot looks ahead, or the full-colour flight instrument page of the display. The small standby display is a backup only#afi[paragraph 4.1.1]. The same virtual head-up display is the reference for recovering from an unusual attitude#afi[paragraph 4.1.2].

#in-sim[#key("Autopilot: level / nav / off") steps the sim's autopilot: it holds the jet level, then steers it along the steerpoints, then lets go. #key("Next waypoint") and #key("Previous waypoint") choose the steerpoint. With #ctl("HMD_MODE") at OFF the helmet shows nothing.]

=== The descent <descent>

No descent checklist of the F-35 is public: open. Inferred from the rules above: check the fuel against the 2,500 lb of the final approach, read the cautions, and set the lights for the landing. The night-vision pictures in the helmet go off 5 minutes before the landing#afi[paragraph 3.19.2]. The card's BEFORE LANDING section is in @landing.

#in-sim[Come down with the throttle at idle; hold #key("Speedbrakes open (hold)") to open the speedbrake surfaces; #key("Speedbrakes close") closes them. #sym.arrow.r *The speed falls faster.*]
