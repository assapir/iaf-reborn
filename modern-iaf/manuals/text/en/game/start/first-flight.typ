#import "/modern-iaf/manuals/layout/manual.typ": *

This task takes you from the #term("Hangar") to the #term("debrief") of the first Training #term("lesson"), #scr("kind_startup"): #scr-text("desc_startup") The jet stands cold on its base and stays on the ground, so nothing can be lost by trying.

=== Before you begin <first-flight-before>

- Setup is finished (@setup) and you have a pilot (@start-game-first).
- Read your jet's cold start once. It is in the jet's own manual: #other("f16i", "cold-start"); #other("f16d", "cold-start"); #other("f35i", "cold-start").

=== From the Hangar to the cockpit <first-flight-go>

+ On the Hangar, select a jet under #scr("aircraft").
  #then[The jet stands in the middle of the screen and its card shows its squadron and base (@hangar).]
+ Select #scr("fly").
  #then[The #scr("missions") screen opens (@mission-list).]
+ Select #scr("sec_training").
  #then[The jet's lessons are listed in order. The first one is marked #scr("next_up").]
+ Select the first lesson, #scr("kind_startup").
  #then[Its briefing opens: the map of the base and the mission's card (@briefing).]
+ Read #scr("objectives") and #scr("learn") on the briefing.
+ Select #scr("fly").
  #then[The loading screen shows the steps of the start (@loading). Then you sit in the cockpit, the engine off.]

=== In the cockpit <first-flight-cockpit>

The #term("Notebook") is up in front of you, open on its #scr("nb_startup") tab: the jet's own checklist, one line a step. #key("Checklist notebook") stows it and brings it back (@notebook).

+ Do the checklist's first open step. Click the switch that the line names with the pointer (@clicking).
  #then[The notebook ticks the step and marks the next one.]
+ Go on, step by step, to the end of the checklist.
  #then[The engine runs at idle and the avionics are up. The flight pauses under the panel #scr("fl_complete").]
+ Select #scr("debrief").
  #then[The debrief opens: the result, the goals and the remarks (@debrief).]

When a step waits for the jet (the engine's speed, the alignment), the notebook says what it waits for. Why each step is done is in the jet's manual. What passes and what fails the lesson is in @lesson-startup and @scoring.

To stop early, press #keycap("Esc") and select #scr("end_flight") (@time-pause).

=== After the debrief <first-flight-after>

- #scr("next_mission") opens the briefing of the next lesson, #scr("kind_takeoff"). In it every move on the ground waits for a #term("clearance") from the #term("Tower"); how to ask is in @tower.
- #scr("fly_again") opens the same briefing again.
- #scr("back_missions") opens the list of lessons. The lessons in order are in @lessons.
