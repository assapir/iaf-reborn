#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Tower")#idx("Radio calls")On the ground every phase of a cold start waits for the #term("tower"): the engine start, the taxi, entering the runway and the take-off. You ask, the tower answers, and its answer is your #term("clearance"). This section gives the calls in order.

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
  [], [5], [Radio check],
  [In the air], [1], [Contact tower (landing)],
)

The tower that answers is the base nearest to you, within about 18 km.

=== The calls on the ground, in order <tower-ground>

#idx("Start-up clearance")#idx("Taxi clearance")#idx("Line-up clearance")#idx("Take-off clearance")Your callsign is Kidon 1 (kidon style: the first flight is Kidon 1, the next Kidon 2, and a flight's jets are Kidon 1-1, 1-2 and so on). The runway in the tower's answers is the runway in use: your mission's runway, or its other end when the wind blows from behind it (@tower-wind).

+ With the engine off, on your parking spot, press #key("Call the tower"), then #keycap("1").
  #then[The tower answers "Kidon 1, cleared to start", and your pilot reads it back: "Cleared to start, Kidon 1". You may start the engine.]
+ Start the jet by its checklist (@notebook-checklist). Wait for the engine at idle and the avionics up.
+ Press #key("Call the tower"), then #keycap("2").
  #then[The tower answers with a greeting and "taxi to runway" with your runway's number, and your pilot reads it back. You may leave the parking spot.]
+ Taxi to the runway and stop at the #term("holding point"), short of the runway (@ground-signs-hold).
+ Press #key("Call the tower"), then #keycap("3").
  #then[The tower answers "line up runway" with the runway's number and the wind ("wind 270 degrees, 10 knots", or "wind calm"), and your pilot reads it back. You may enter the runway.]
+ Taxi onto the runway and stop on its centreline, facing down the runway.
+ Press #key("Call the tower"), then #keycap("4").
  #then[The tower answers with the wind, the runway and "cleared for take-off" ("Kidon 1, wind calm, runway 25 right, cleared for take-off"), and your pilot reads it back. You may start the take-off roll.]

#idx("Readback")Your pilot reads back every clearance in your pilot's voice: the clearance and its runway, then your callsign ("Taxi to runway 25 right, Kidon 1"). To "hold position" your pilot answers "Holding, Kidon 1", to a go-around "Going around, Kidon 1", and to the gear warning "Roger".

Once you have a clearance, you keep it, also when you shut the engine down and start it again.

=== The runway in use and the wind <tower-wind>

#idx("Runway in use")#idx("Wind")The tower names the runway end that faces the wind. When the mission's wind is 10 knots or more and blows from more than 90° off your mission's runway, the tower turns the base round and names the other end of the same runway: at Ramon 07L in place of 25R. The briefing, the Missions screen and the #term("notebook") name that end too.

+ Taxi to the runway's usual #term("holding point") and ask for line-up there.
  #then[The tower answers "line up runway" with the far end's number.]
+ Enter the runway and taxi down its centreline to its far end (a backtrack).
+ Turn round on the centreline at the far end, facing down the runway, and ask for take-off.

In a four-ship flight each wingman waits at the holding point until the jet ahead of it is in the air, then backtracks in its turn. A wind of exactly 90° off, or under 5 knots, keeps the mission's runway. The missions of this version are flown with the wind calm, so the tower names the mission's runway.

=== The tower's other answers <tower-answers>

#idx("Hold position")#grid-table(
  (1fr, 1.3fr),
  ([The tower says], [Meaning, and what to do]),
  ["hold position"], [The tower cannot clear the call now. You have no clearance. Typical causes: a taxi request with the engine not running; a line-up request far from the runway or with the runway in use. Mend the cause and call again.],
  ["negative, hold position, request ... first"], [You skipped a call: take-off before line-up, line-up before taxi, or taxi before start-up. Make the call the tower names, then this one.],
  ["line up runway ..." in answer to a take-off request], [You asked for take-off before you were lined up. This clears the line-up only. Line up, then request take-off again.],
  ["you are on runway ..., the assigned runway is ..."], [You lined up on a runway end that is not the one the tower named. Taxi off it and go to the assigned runway.],
  ["engine start without clearance", "taxi without clearance", "runway entry without clearance", "take-off without clearance"], [You did the thing before its clearance.],
)

#idx("Radio check")The radio check (#keycap("5") on the ground) tests the radio at any moment on the ground: the tower answers "Kidon 1, read you five". Its answer is a reply, and your clearances stay as they were.

A wrong or repeated call costs nothing. A repeated call gets its answer again.

=== The landing call <tower-landing>

#idx("Landing call")In the air the list holds one call.

+ Press #key("Call the tower"), then #keycap("1").
  #then[Your pilot asks the nearest base for a landing. The tower answers "proceed to runway" with the runway to land on.]

The tower has no calls for you yet for joining the pattern, the final approach or a go-around.

#idx("Wingmen, landing calls")In a four-ship flight you also hear the tower talk to your wingmen as each comes home: "Kidon 1-2, cleared to land runway ..." as it turns onto its final approach and "Kidon 1-2, welcome back, taxi to parking" after its landing roll. Each answers with its callsign. These calls need nothing from you.

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

#idx("Subtitles")Every call and answer is spoken, and shows as a line of text at the top middle of the screen as its voice starts. The strip holds the three newest lines, each for 8 seconds. Your own call comes first, then, after a short pause, the tower's answer, then your pilot's readback of it. Each call ends with about a second of quiet on the radio before the next one starts.

The lines and the voices are in the game's language (@language).

#screen("flight_band", [A tower call: the radio's lines at the top of the screen.])

=== Commands to your wingmen <radio-flight>

#idx("Wingmen")#idx("Radio menu")In a four-ship flight you fly as Kidon 1-1 and lead Kidon 1-2, 1-3 and 1-4. Kidon 1-2 flies on you; Kidon 1-4 flies on Kidon 1-3, who leads the second pair. You command them from the same menu; four commands also have a key of their own (below the table).

+ Press #key("Call the tower").
  #then[The list shows 1 Tower, 2 Wingmen and 3 #term("AWACS"). The tower's calls are under 1, the AWACS's requests under 3 (@awacs-requests). With a #term("tanker") on the flight, 4 Tanker follows (@tanker).]
+ Press 2.
  #then[The list shows "Kidon 1" (the flight), "Kidon 1, element 3–4", "Kidon 1-2", "Kidon 1-3" and "Kidon 1-4".]
+ Press the number of whom you call.
  #then[The list shows the commands for them. #keycap("0") goes back. A list longer than nine shows its first eight and 9 More, which shows the rest.]
+ Press the number of a command.
  #then[The list closes. Your pilot makes the call ("Kidon 1-2, rejoin"). Each wingman answers with its callsign ("Kidon 1-2.") or "unable".]

You can also click a line of the list.

#grid-table(
  (auto, auto, 1fr),
  ([Command], [To], [What the wingmen do]),
  [Formation], [the flight], [A page of shapes: fingertip, line abreast, trail, echelon right, echelon left, diamond, vic, delta. Each calls "in position" in its new slot. Its last line, Spacing, opens Close up and Spread out.],
  [Close up], [the flight], [The close shapes one step tighter: from the standard 60 m between the slots to 30 m, then to 12 m, wingtips 2 m apart. Each calls "in position" at the new spacing. At 12 m, in line abreast or in trail they answer "unable". A new shape keeps the spacing. At 12 m, fly smoothly: when you bank past 35°, roll fast or pull more than 1.5 g, the wingmen move out to 30 m on their own, and close back up 5 seconds after you fly smoothly again.],
  [Spread out], [the flight], [One step back toward the standard 60 m. At the standard they answer "unable".],
  [Rejoin], [anyone], [Back to the slot from any task, also after an RTB. To the element 3–4 it ends a split.],
  [Split], [the element 3–4], [The second pair flies to your sensor's point (the radar's designated point, else your steerpoint) and circles it. It must be within 40 km of you, or they answer "unable"; with no sensor's point they answer "unable" too.],
  [Engage my target], [anyone], [They fight the aircraft your radar has locked: a collision course, a missile inside its envelope, a turn away while it flies, then the dogfight and the gun. With nothing left to shoot they answer "unable". When it is destroyed they rejoin. Number 4 stays with number 3. To give each its own aircraft, lock one and give it to Kidon 1-2, then lock another and give it to the element 3–4. With no aircraft locked they attack your ground target instead: the enemy ground unit your radar has locked, else the one nearest your sensor's point (within 500 m), else that point itself. With no sensor's point (nothing designated, no steerpoint and the targeting pod not looking at the ground) they answer "unable". Each wingman with bombs attacks in turn, one after the other: a dive for plain bombs, a level run for guided ones. Without bombs it answers "unable". Against a moving target, such as a vehicle in a convoy, each aims where it will be when the bombs land.],
  [Sort], [the flight], [They share out the enemy aircraft any of you sees. Aircraft within 3 NM of each other are one group. Two groups side by side: the pair on the left takes the left group. Two groups one behind the other: your pair takes the near one, the second pair the far one. Each pair shares its group out the same way, jet by jet. Number 3 answers "targeted" and attacks. Numbers 2 and 4 answer, stay with their pair's leader and hold their fire until that leader fires or a threat is on them. With nothing seen they answer "unable".],
  [Weapons free], [anyone], [They hunt any enemy aircraft within 20 NM of your sensor's point (the radar's designated point, else your steerpoint), each an aircraft nobody else has; with none there they circle the point. Number 4 stays with number 3 and fights the other aircraft of its group. The point must be within 40 km of you, or they answer "unable"; with no sensor's point they hunt round you. Joker fuel or Rejoin ends the hunt.],
  [Low level], [the flight], [When they fly on their own (a split, a rejoin, a turn away from a threat, a ground attack) they fly 300 ft above the ground ahead. In an air fight they fly at the fight's own heights. In their slot they keep your height, so you fly low too. A bomb run comes in low, climbs 4 NM from the target into a dive on it and leaves low.],
  [Back to altitude], [the flight], [They fly on their own at their normal heights again.],
  [Cover me], [anyone], [They keep their slot and fight an enemy aircraft that attacks you: its radar locked on you, or behind you and pointing at you. Rejoin or RTB ends the cover.],
  [Refuel], [anyone], [Offered only with a tanker on the flight. They fly to the tanker, refuel one after the other and rejoin you (@tanker-wingmen).],
  [RTB], [anyone], [They return to base and land.],
  [Check in], [anyone], [Each answers with its number.],
  [Ops check], [anyone], [Each answers with its fuel, in thousands of pounds ("Two, six point two").],
)

The keys: #key("Wingman: attack my target") gives Kidon 1-2 engage my target, #key("Flight: sort") gives Sort to the flight, #key("Flight: weapons free") gives Weapons free to the flight, #key("Flight: low level / back to altitude") gives Low level to the flight, or Back to altitude when it flies low, and #key("Wingman: cover me") tells Kidon 1-2 to cover you.

The wingmen also call by themselves: "joker" and "bingo" for their fuel, "spike" or "mud" when a radar locks on them, "defending" when a missile flies at them, "break left" or "break right" when they see a missile fired at their pair's other jet, "contact" when their radar first finds an enemy aircraft or holds one the AWACS called, and "Three has the lead" when the lead changes. A wingman under a lock or a missile turns away from the threat, and a Sufa wingman turns its jammer on. Against a missile it also drops chaff, or flares against a heat-seeking one: once at the launch and again in the missile's last seconds. Then it rejoins. With no command they keep their slot and fight only an aircraft that attacks them. In a fight they call "engaged" when they take on an aircraft by themselves (one attacking them, one attacking you while they cover you, or one they hunt), "Fox one", "Fox two" or "Fox three" for a missile, "guns" for a burst, "splash" for a kill and "winchester" when nothing is left to shoot; a lock in a fight is called and the attack goes on. In a ground attack each calls "in" as it starts its run, "bombs away" as its bombs leave, "shack" when the target is destroyed (the wingman that released last) and "done" once it is clear of the target; then it rejoins. A new command ends the attack at once and the wingman follows it: rejoin, RTB, split, cover me, sort, weapons free, or engage my target again, which starts its run over. A formation change does not end it.
