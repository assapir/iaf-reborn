#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("AWACS")The #term("AWACS") is the airborne controller. It watches the sky with its own radar and tells you by radio where other aircraft are. It calls you by itself and answers your requests.

=== The contact calls <awacs-calls>

#idx("Contact call")From one minute into a flight, the AWACS reports an aircraft that is within 35 nautical miles of you. It reports again every 12 seconds while one is there.

A call sounds like this:

"Kidon 1, bearing 090, 15 miles, target, heading 270, free to engage"

Read it part by part:

#grid-table(
  (auto, 1fr),
  ([Part], [Meaning]),
  [Kidon 1], [Your callsign: the call is for you.],
  [bearing 090], [The direction from you to the aircraft, as a compass heading. 090 is due east. Turn to this heading to point at it.],
  [15 miles], [Its distance from you, in nautical miles.],
  [target], [What it is: an aircraft you are to attack.],
  [heading 270], [The way the aircraft itself flies. 270 is due west: with the bearing above, it comes toward you.],
  [free to engage], [You may shoot.],
)

=== The task call <awacs-task>

#idx("Task call")In a #scr("sec_fly_now") flight (@mission-list-scramble) the AWACS also gives your task. The first call comes a few seconds after you are in the air. It comes again every minute while the target is there, and it tells you where the part of the target nearest you is.

"Kidon 1, attack the convoy, bearing 040, 25 miles, free to engage"

#grid-table(
  (auto, 1fr),
  ([Part], [Meaning]),
  [Kidon 1], [Your callsign: the call is for you.],
  [attack the convoy], [The task. The others are "intercept the bandits" (a MiG-29 pair), "intercept the drones" and "attack the SAM battery" (the S-300).],
  [bearing 040], [The direction from you to the target, as a compass heading.],
  [25 miles], [Its distance from you, in nautical miles.],
  [free to engage], [You may shoot.],
)

=== Using a call <awacs-use>

+ Turn the jet to the bearing.
+ Set the radar's range above the distance in the call.
+ Look for the contact on the radar.

How to work the radar and lock a target is in each jet's manual: the #other("f16i", "radar-aa"), the #other("f16d", "radar-aa") and the #other("f35i", "radar-aa").

The calls are spoken in the AWACS's own voice, in the game's language, and show as lines at the top of the screen, like the #term("tower")'s (@tower-subtitles). Setting the jet's radios is in the #other("f16i", "radios"), the #other("f16d", "radios") and the #other("f35i", "radios"); the AWACS's calls reach you whatever the radios are set to.

=== Asking the AWACS <awacs-requests>

#idx("AWACS, requests")#idx("Radio menu")You can ask the AWACS where the other aircraft are, what an aircraft is and which way to fly.

+ Press #key("Call the tower").
  #then[The list shows 1 Tower, 2 Wingmen and 3 AWACS.]
+ Press 3.
  #then[The AWACS's requests show. A request you cannot make now is dimmed and does nothing; the table below says when each one is. #keycap("0") goes back.]
+ Press the number of a request.
  #then[You call the AWACS ("Eitam, Kidon 1, picture"), and it answers.]

#grid-table(
  (auto, 1fr),
  ([Request], [What the AWACS answers]),
  [Picture], [How many groups of aircraft it sees, then the three nearest you, nearest first: "Kidon 1, two groups. Group bearing 040, 30 miles, 20 thousand, hot, hostile." "Clean" when it sees none.],
  [Bogey dope], [The group nearest you, in the same words.],
  [Declare], [What the aircraft your radar has locked is: "hostile", "bogey" (unknown) or "friendly"; "clean" when the AWACS does not see it. Dimmed without a lock.],
  [Vector to target], [The heading and distance to your target: "Kidon 1, vector 040, 25 miles, target". In a #scr("sec_fly_now") flight the target is your task's; else the nearest hostile group.],
  [Vector home], [The heading and distance to your home base: "... home plate". Dimmed in a flight without a home base.],
  [Vector to #term("tanker")], [The heading and distance to the nearest tanker. With no tanker on the flight the line is dimmed (@tanker).],
  [Check in], [You join the controller's net: "Kidon 1, radar contact". Check in before the other requests; a training lesson grades it (@mission-list-training).],
  [Judy], [You have the target on your radar, the data link or in sight and take the intercept over: "Kidon 1, copy".],
)

Read a group part by part:

#grid-table(
  (auto, 1fr),
  ([Part], [Meaning]),
  [group], [One aircraft, or several within 3 nautical miles of each other.],
  [bearing 040, 30 miles], [The direction from you to it as a compass heading, and its distance in nautical miles, as in a contact call.],
  [20 thousand], [Its height, in thousands of feet.],
  [hot], [Where it points: "hot" at you, "flank" partly at you, "beam" across your line, "drag" away from you.],
  [hostile], [An enemy. "Bogey" is an aircraft not yet identified.],
)

Your wingmen hear the answers too: a wingman whose radar holds a group the AWACS named calls "contact" (@radio-flight).

=== The Eitam <awacs-eitam>

#idx("Eitam")In a #scr("sec_fly_now") flight the AWACS is the Eitam, the air force's Gulfstream G550 with its radar. It flies a long oval at 41,000 ft behind your way to the fight and to one side of it, so it is never on your route, and its radar covers the fight. In the other flights the AWACS has no aircraft in the sky.

The enemy can attack the Eitam. When enemy aircraft come close to it, it turns away at full speed and calls you for help:

"Kidon 1, threat, group bearing 040, 30 miles, 25 thousand, Eitam retrograding, commit"

The group is given from you, as in a picture: fly to it, or send your wingmen (@radio-flight). The call comes again every minute while the enemy is near the Eitam. Once it is clear, the Eitam goes back to an oval a little further back.

If the Eitam is shot down, the AWACS is gone for the rest of the flight: no more calls, every request dimmed, and the jets' data link shows no more of its aircraft.
