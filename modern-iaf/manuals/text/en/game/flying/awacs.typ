#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("AWACS")The #term("AWACS") is the airborne controller. It watches the sky with its own radar and tells you by radio where other aircraft are. You do not call it: it calls you.

=== The contact calls <awacs-calls>

#idx("Contact call")From one minute into a flight, the AWACS reports an aircraft that is within 35 nautical miles of you. It reports again every 12 seconds while one is there. On the Weapons range (@lesson-range) the calls are about the range's drones. The Start-up and Take-off lessons have no other aircraft, so the AWACS stays silent there.

A call sounds like this:

"Alpha, bearing 090, 15 miles, target, heading 270, free to engage"

Read it part by part:

#grid-table(
  (auto, 1fr),
  ([Part], [Meaning]),
  [Alpha], [Your callsign: the call is for you.],
  [bearing 090], [The direction from you to the aircraft, as a compass heading. 090 is due east. Turn to this heading to point at it.],
  [15 miles], [Its distance from you, in nautical miles.],
  [target], [What it is: an aircraft you are to attack.],
  [heading 270], [The way the aircraft itself flies. 270 is due west: with the bearing above, it comes toward you.],
  [free to engage], [You may shoot.],
)

=== Using a call <awacs-use>

+ Turn the jet to the bearing.
+ Set the radar's range above the distance in the call.
+ Look for the contact on the radar.

How to work the radar and lock a target is in each jet's manual: the #other("f16i", "radar-aa"), the #other("f16d", "radar-aa") and the #other("f35i", "radar-aa").

The calls are spoken in the AWACS's own voice and show as lines at the top of the screen, like the #term("tower")'s (@tower-subtitles). Setting the jet's radios is in the #other("f16i", "radios"), the #other("f16d", "radios") and the #other("f35i", "radios"); the AWACS's calls reach you whatever the radios are set to.

#note[The AWACS answers no request in the sim: the list of the #key("Call the tower") key holds the tower's calls only.]
