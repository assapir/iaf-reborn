#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Lessons")#idx("Training")A #term("lesson") is a mission of the #scr("sec_training") list on the #scr("missions") screen (@mission-list). Each of the three jets has three lessons, flown from its own base. Fly them in order: each one builds on the one before.

=== The lessons of each jet <lessons-list>

#grid-table(
  (auto, 1fr, 1fr, 1fr),
  ([Lesson], [F-16I Sufa, at Ramon], [F-16D Barak, at Ramat David], [F-35I Adir, at Nevatim]),
  [1. #scr("kind_startup")], [Mission 2011], [Mission 2021], [Mission 2031],
  [2. #scr("kind_takeoff")], [Mission 2012, runway 25R], [Mission 2022, runway 27], [Mission 2032, runway 26L],
  [3. Weapons range], [Mission 2013, runway 25R], [Mission 2023, runway 27], [Mission 2033, runway 26L],
)

The mission number starts a lesson directly from the command line (@start-game). The bases are described in @airbases.

=== What each lesson teaches <lessons-teach>

#grid-table(
  (auto, 1fr, auto, auto),
  ([Lesson], [What you do], [#term("Time allowed")], [Explained in]),
  [#scr("kind_startup")], [#scr-text("desc_startup") You bring a cold jet to life by its checklist, after the #term("tower") clears the start.], [10 min], [@lesson-startup],
  [#scr("kind_takeoff")], [#scr-text("desc_takeoff") You start the jet, make the four calls, taxi to the runway, take off and climb out.], [15 min], [@lesson-takeoff],
  [Weapons range], [#scr-text("desc_range") You start and take off as before, then fly to the range.], [45 min], [@lesson-range],
)

All three lessons of a jet start at 08:00 or 09:00 in the morning, in daylight, with no wind.

=== How a lesson starts <lessons-start>

#idx("Cold start, in a lesson")Every lesson starts the same way: the jet stands on its parking spot, cold. The engine is off, there is no electrical power, every display is dark, and the canopy is up. Moving the throttle starts nothing. You start the jet step by step, by its checklist, in every lesson.

- In the Start-up lesson the #term("notebook") is raised at its checklist when the flight begins (@notebook-open). In the other two it is stowed.
- In every lesson a ring in the cockpit shows the control of the checklist item to do now (@notebook-ring).
- The clock of the #term("time allowed") runs from the first moment of the flight.

The briefing tells each lesson's story in order (@briefing-text). Read it before the flight: nothing during the flight repeats it, except the notebook's pages.

=== After the lessons <lessons-after>

#idx("Campaign")#idx("Single missions")The #scr("missions") screen also lists #scr("sec_campaign"), #scr("sec_single") and #scr("sec_fly_now"). All three read #scr("coming_later"): they come in a later version.

A lesson you passed stays open. Fly it again whenever you like; the #term("pilot log") keeps every flight (@pilots).
