#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Tower")#idx("Radio calls")On the ground every phase of a #term("lesson") waits for the #term("tower"): the engine start, the taxi, entering the runway and the take-off. You ask, the tower answers, and its answer is your #term("clearance"). This section gives the calls in order. What the game does when you move without a clearance is in @scoring-clearances.

Each jet's manual gives the procedure between the calls: the #other("f16i", "cold-start"), the #other("f16d", "cold-start") and the #other("f35i", "cold-start") for the start and the take-off; the #other("f16i", "landing"), the #other("f16d", "landing") and the #other("f35i", "landing") for the landing.

=== The Call the tower key and its menu <tower-menu>

#idx("Call the tower")
+ Press #key("Call the tower").
  #then[A short numbered list opens at the top corner of the screen, under the name of the tower you talk to.]
+ Press the number of a call.
  #then[The list closes. Your pilot makes the call. The tower answers.]

Any other key closes the list without a call. The list also closes by itself after 6 seconds.

The list holds the calls of the moment:

#grid-table(
  (auto, auto, 1fr),
  ([Where you are], [Number], [Call]),
  [On the ground], [1], [Request start-up],
  [], [2], [Request taxi],
  [], [3], [Request line-up],
  [], [4], [Request take-off],
  [In the air], [1], [Contact tower (landing)],
)

The tower that answers is the base nearest to you, within about 18 km.

=== The calls on the ground, in order <tower-ground>

#idx("Start-up clearance")#idx("Taxi clearance")#idx("Line-up clearance")#idx("Take-off clearance")Your callsign is Alpha. The runway in the tower's answers is your mission's runway.

#caution[A phase started before the tower's clearance fails a Training mission at once. Make each call, and wait for the answer in the right-hand column, before you do what it clears (@scoring-clearances).]

+ With the engine off, on your parking spot, press #key("Call the tower"), then #keycap("1").
  #then[The tower answers "Alpha, cleared to start". You may start the engine.]
+ Start the jet by its checklist (@notebook-checklist). Wait for the engine at idle and the avionics up.
+ Press #key("Call the tower"), then #keycap("2").
  #then[The tower answers with a greeting and "taxi to runway" with your runway's number. You may leave the parking spot.]
+ Taxi to the runway and stop at the #term("holding point"), short of the runway (@ground-signs-hold).
+ Press #key("Call the tower"), then #keycap("3").
  #then[The tower answers "line up runway" with the runway's number and the wind. You may enter the runway.]
+ Taxi onto the runway and stop on its centreline, facing down the runway.
+ Press #key("Call the tower"), then #keycap("4").
  #then[The tower answers "cleared for take-off". You may start the take-off roll.]

Once you have a clearance, you keep it, also when you shut the engine down and start it again.

=== The tower's other answers <tower-answers>

#idx("Hold position")#grid-table(
  (1fr, 1.3fr),
  ([The tower says], [Meaning, and what to do]),
  ["hold position"], [The tower cannot clear the call now. You have no clearance. Typical causes: a taxi request with the engine not running; a line-up request far from the runway or with the runway in use. Mend the cause and call again.],
  ["negative, hold position, request ... first"], [You skipped a call: take-off before line-up, line-up before taxi, or taxi before start-up. Make the call the tower names, then this one.],
  ["line up runway ..." in answer to a take-off request], [You asked for take-off before you were lined up. This clears the line-up only. Line up, then request take-off again.],
  ["you are on runway ..., the assigned runway is ..."], [You lined up on a runway that is not your mission's. Taxi off it and go to the assigned runway. A take-off roll on the wrong runway fails the mission.],
  ["engine start without clearance", "taxi without clearance", "runway entry without clearance", "take-off without clearance"], [You did the thing before its clearance. In a Training mission the mission has failed.],
)

A wrong or repeated call costs nothing. A repeated call gets its answer again.

=== The landing call <tower-landing>

#idx("Landing call")In the air the list holds one call.

+ Press #key("Call the tower"), then #keycap("1").
  #then[Your pilot asks the nearest base for a landing. The tower answers "proceed to runway" with the runway to land on.]

The tower has no calls yet for joining the pattern, the final approach or a go-around.

=== The frequencies: the RADIO tab <tower-radio>

#idx("Frequencies")#idx("GND")#idx("TWR")The #term("notebook")'s #scr("nb_radio") tab (@notebook-tabs) lists, for your base:

- #scr("nb_callsign"): your callsign;
- the base's frequencies in MHz: GND (ground control), TWR (the tower) and APP (approach);
- each call under #scr("nb_you_call"), the frequency it is made #scr("nb_on"), and the #scr("nb_answer") to wait for.

#grid-table(
  (auto, auto, auto, auto),
  ([Base], [GND], [TWR], [APP]),
  [Ramon], [275.8], [251.15], [120.9],
  [Ramat David], [285.25], [118.6], [125.8],
  [Nevatim], [264.35], [240.25], [120.9],
  [Hatzerim], [268.7], [256.9], [122.15],
)

The page puts the start-up and taxi calls on GND and the line-up, take-off and landing calls on TWR. Ramon's and Nevatim's APP and Ramat David's TWR and APP are the published frequencies. The others are the sim's own.

#note[In the sim the #key("Call the tower") key reaches the tower whatever frequency the jet's radio is set to, and one controller's voice answers all the calls. Setting the radios is a procedure of the jet: the #other("f16i", "radios"), the #other("f16d", "radios") and the #other("f35i", "radios").]

#screen("notebook_radio", [The RADIO tab at Ramon.])

=== The radio's lines on the screen <tower-subtitles>

#idx("Subtitles")Every call and answer is spoken, and shows as a line of text at the top middle of the screen as its voice starts. The strip holds the three newest lines, each for 8 seconds. Your own call comes first, then, after a short pause, the tower's answer, then your pilot's "Roger".

The lines and the voices are in the game's language (@language).

#screen("flight_band", [A tower call: the radio's lines at the top of the screen.])

=== Commands to your wingmen <radio-flight>

#idx("Wingmen")#idx("Radio menu")In a four-ship lesson you fly as Alpha 1 and lead Alpha 2, 3 and 4. Alpha 2 flies on you; Alpha 4 flies on Alpha 3, who leads the second pair. You command them from the same menu: there is no other key.

+ Press #key("Call the tower").
  #then[The list shows 1 Tower, 2 Wingmen and 3 #term("AWACS"). The tower's calls are under 1. AWACS has no call to make: it reports by itself, so its line is dimmed.]
+ Press 2.
  #then[The list shows Alpha (flight), Alpha 3–4 (element), Alpha 2, Alpha 3 and Alpha 4.]
+ Press the number of whom you call.
  #then[The list shows the commands for them. #keycap("0") goes back.]
+ Press the number of a command.
  #then[The list closes. Your pilot makes the call ("Alpha Two, rejoin"). Each wingman answers by its number ("Two.") or "unable".]

You can also click a line of the list.

#grid-table(
  (auto, auto, 1fr),
  ([Command], [To], [What the wingmen do]),
  [Formation], [the flight], [A page of shapes: fingertip, line abreast, trail, echelon right, echelon left, diamond, vic, delta. Each calls "in position" in its new slot.],
  [Rejoin], [anyone], [Back to the slot from any task, also after an RTB. To Alpha 3–4 it ends a split.],
  [Split], [Alpha 3–4], [The second pair flies to your sensor's point (the radar's designated point, else your steerpoint) and circles it. It must be within 40 km of you, or they answer "unable".],
  [Engage my target], [anyone], [They fly at the aircraft your radar has locked and fire their air-to-air missiles. With no enemy aircraft locked they answer "unable". When it is destroyed they rejoin.],
  [RTB], [anyone], [They return to base and land.],
  [Check in], [anyone], [Each answers with its number.],
  [Ops check], [anyone], [Each answers with its fuel, in thousands of pounds ("Two, six point two").],
)

The wingmen also call by themselves: "joker" and "bingo" for their fuel, "spike" or "mud" when a radar locks on them, "defending" when a missile flies at them, "break left" or "break right" when they see a missile fired at their pair's other jet, "contact" when their radar holds an aircraft the AWACS called, and "Three has the lead" when the lead changes. A wingman under a lock turns away from the threat and drops chaff or flares, then rejoins.
