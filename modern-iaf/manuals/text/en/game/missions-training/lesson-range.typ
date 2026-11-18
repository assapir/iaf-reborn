#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Weapons range")#idx("Range lesson")The third #term("lesson") of each jet: missions 2013 (Sufa, Ramon, runway 25R), 2023 (Barak, Ramat David, runway 27) and 2033 (Adir, Nevatim, runway 26L).

=== Its purpose <lesson-range-purpose>

You find aircraft on the radar and shoot them down, then bomb targets on the ground. The targets are the range's own: drones in the air and retired jets on the ground. None of them shoots back.

The weapons' procedures are in each jet's manual:

- the radar: the #other("f16i", "radar-aa"), the #other("f16d", "radar-aa") and the #other("f35i", "radar-aa");
- the master arm and the stores: the #other("f16i", "stores"), the #other("f16d", "stores") and the #other("f35i", "stores");
- missiles and the gun: the #other("f16i", "aa-weapons"), the #other("f16d", "aa-weapons") and the #other("f35i", "aa-weapons");
- bombs: the #other("f16i", "ag-weapons"), the #other("f16d", "ag-weapons") and the #other("f35i", "ag-weapons").

=== Before you fly: the loadout <lesson-range-loadout>

#idx("Range lesson, loadout")The mission's own #term("loadout") carries what the range asks for: the Sufa and the Barak four AIM-9M, six Mk 82 bombs and two drop tanks, the Adir four AIM-120 and two GBU-31 bombs.

#caution[A loadout you made for the jet takes the place of the mission's. If it has no bombs, the ground targets cannot be destroyed: select the mission's loadout on the Loadout screen, or hang bombs, before you select #scr("fly") (@loadout-hang).]

A bomb that needs a targeting pod needs the pod on the jet too (@loadout-rules). The game keeps your last loadout for each jet, so check the #scr("tab_arming") line of the briefing before every flight to the range.

=== The range <lesson-range-where>

The route has two points. The first is the air range, the second the ground targets.

#grid-table(
  (auto, 1fr, 1fr),
  ([Jet], [Air range], [Ground targets]),
  [Sufa, from Ramon], [Over the open Negev between Ramon and Revivim.], [In the Halutza sands, 28 km north of Ramon.],
  [Adir, from Nevatim], [The same air range.], [The same targets, 50 km south-west of Nevatim.],
  [Barak, from Ramat David], [Over the sea west of Haifa.], [On the Golan plateau, 65 km north-east of Ramat David.],
)

*In the air* five drones fly, marked as hostile for the exercise:

- one at 15,000 ft, round a long racetrack;
- one low, about 500 m above the ground or the sea;
- one at 20,000 ft that weaves, and breaks away when you come within 9 km;
- a pair at 25,000 ft with their radars on: your radar warning receiver hears them.

The #term("AWACS") calls out the drones' positions (@awacs-calls).

*On the ground* four retired jets stand parked in the open. A fifth is towed round a loop beside them: a moving target for the radar. A target barge moves slowly at sea: the radar's sea target. All six count as ground targets.

=== What the game checks <lesson-range-objectives>

The briefing lists the objectives: shoot down 2 of the range's drones; destroy 2 of its ground targets; within 45 minutes of the start; and #scr-text("obj_safe").

The lesson passes when all of these are true:

#grid-table(
  (auto, 1fr),
  ([Check], [Exactly]),
  [Each phase had its #term("clearance")], [The start, the taxi, the runway entry and the take-off roll each came after the #term("tower")'s answer, as in the Take-off lesson (@scoring-clearances).],
  [Two drones down], [You destroyed at least two of the five drones. Any weapon counts: the gun or a missile.],
  [Two ground targets destroyed], [You destroyed at least two of the six ground targets. The towed one and the barge count too.],
  [In time], [The last of these four kills came within 45 minutes of the start of the flight.],
  [Nothing failed], [None of the things that fail any mission at once happened (@scoring-at-once).],
)

The order is free: the game counts the kills, whichever come first. It checks the count every 3 seconds once you are in the air. When the fourth kill it needs is in, the #scr("fl_complete") panel opens (@time-pause-done). The #term("debrief") then reads: #scr-text("done_range")

=== The goals in the debrief <lesson-range-debrief>

#grid-table(
  (auto, 1fr),
  ([Goal], [Target]),
  [Shoot down 2 drones], [The drones you shot down, against 2.],
  [Destroy 2 ground targets], [The ground targets you destroyed, against 2.],
  [Within 45 min of the start], [The time of the last kill the lesson needs.],
)

=== What fails it <lesson-range-fails>

#grid-table(
  (1fr, 1.2fr, 1.2fr),
  ([What you did], [What the game does], [How to avoid it]),
  [You started a phase on the ground before its clearance, left the pavement, or rolled on the wrong runway.], [The mission fails at once, as in the Take-off lesson (@lesson-takeoff-fails).], [Fly the departure exactly as you learned it.],
  [Your jet was damaged or crashed.], [The mission fails at once.], [Pull out of a bombing dive in good time. Keep clear of the drone you shoot and of its wreck.],
  [45 minutes passed with a kill still missing.], [Five seconds later the mission ends as a fail, with the missing kills as the reason (the next two rows).], [Fly to the range right after the take-off. Use the faster clock on the way (@time-pause-speed).],
  [You ended the flight with fewer than two drones down.], [The mission is a fail: "Fewer drones shot down than the range asks."], [Find a drone on the radar and lock it. Close to the gun's range, or launch a missile when the jet shows the drone in range.],
  [You ended the flight with fewer than two ground targets destroyed.], [The mission is a fail: "Fewer ground targets destroyed than the range asks."], [Select the bombs, set the master arm, and release with the aiming mark on the target.],
)

=== The usual reasons for a fail <lesson-range-usual>

- *No bombs on the jet.* Your own loadout for the jet has none. See @lesson-range-loadout.
- *Nothing releases.* Every flight starts with the master arm safe, and nothing releases with the gear handle down. The #term("notebook")'s #scr("nb_weapons") tab lists the arming steps with their keys (@notebook-tabs).
- *Out of weapons.* Count before you shoot: two drones and two ground targets need at least four good shots. Take more than you need.
- *Time.* The range is far from the base and 45 minutes include the cold start. Do not linger over the checklist.
