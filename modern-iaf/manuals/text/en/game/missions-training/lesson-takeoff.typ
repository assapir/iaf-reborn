#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Take-off lesson")The second #term("lesson") of each jet: missions 2012 (Sufa, Ramon, runway 25R), 2022 (Barak, Ramat David, runway 27) and 2032 (Adir, Nevatim, runway 26L).

=== Its purpose <lesson-takeoff-purpose>

You fly a full departure with the #term("tower"): the start, the four calls, the taxi to the runway, the line-up, the take-off and the climb-out on the runway's heading with the gear up.

The procedures of the jet are in its manual: the start and the take-off in the #other("f16i", "cold-start"), the #other("f16d", "cold-start") and the #other("f35i", "cold-start"); how the jet behaves on the roll in the #other("f16i", "handling-takeoff-landing"), the #other("f16d", "handling-takeoff-landing") and the #other("f35i", "handling-takeoff-landing"). The calls are in @tower-ground. This section says what the game checks.

=== What the game checks <lesson-takeoff-objectives>

The briefing lists four objectives: take off from the mission's runway; climb out with the gear up on the runway heading, within 10° either side; do it within 15 minutes of the start; and #scr-text("obj_safe").

The lesson passes when all of these are true:

#grid-table(
  (auto, 1fr),
  ([Check], [Exactly]),
  [Each phase had its #term("clearance")], [Start-up, taxi, runway entry and take-off roll each came after the tower's answer (@scoring-clearances).],
  [The right runway], [The take-off roll started on the mission's runway and ran toward its far end.],
  [The roll stayed on the runway], [From the start of the roll to the lift-off, the middle of the jet stayed within half the runway's width of the centreline.],
  [A lift-off], [The jet left the ground and stayed off it.],
  [The climb-out], [At some moment after the lift-off the jet is in the air with the gear up and its heading within 10° of the runway's heading.],
  [In time], [That moment comes within 15 minutes of the start of the flight.],
  [Nothing failed], [None of the things that fail any mission at once happened (@scoring-at-once).],
)

The game checks the flight every 3 seconds once you are in the air. While a goal is still open, a line at the top corner of the screen names it: "To complete: raise the gear." or "To complete: climb out on the runway heading with the gear up." When the last goal is met, the #scr("fl_complete") panel opens (@time-pause-done). The #term("debrief") then reads: #scr-text("done_takeoff")

The runway headings are 246° for Ramon's 25R, 265° for Ramat David's 27 and 256° for Nevatim's 26L.

=== The goals in the debrief <lesson-takeoff-debrief>

#grid-table(
  (1.3fr, 1.3fr, 1fr),
  ([Goal], [Target], [Off the target]),
  [Take off from the runway], [The mission's runway.], [Fail],
  [Within 15 min of the start], [15 minutes, to the moment of the climb-out check.], [Fail],
  [Gear up on the runway heading], [The runway's heading, ±10°.], [Fail],
  [Offset from the centreline during the roll], [At most half the runway's width.], [Fail],
  [Lift-off speed against the reference at this weight], [The reference take-off speed for the jet's weight at the lift-off. It rises with the weight.], [A "!" mark beyond 10 kt; the mission still passes],
  [Tower calls], [Four calls.], [A "!" mark with fewer; the mission still passes],
)

The reference speed is a number to learn from: no lift-off speed fails the lesson.

=== What fails it <lesson-takeoff-fails>

#grid-table(
  (1fr, 1.2fr, 1.2fr),
  ([What you did], [What the game does], [How to avoid it]),
  [You started a phase before its clearance.], [The tower names it. The mission fails at once (@scoring-clearances).], [Make the call and wait for the answer before each phase.],
  [The jet left the pavement on the taxi.], [The mission fails at once: "The jet left the pavement."], [Keep the nose wheel on the yellow taxi line. Slow down before each turn.],
  [You started the roll on another runway.], [On the line-up the tower warns you once. Faster than 30 kt there, the mission fails at once: "The take-off was not from the assigned runway."], [Follow the signs to your runway's number (@ground-signs-signs). On the tower's warning, stop and taxi off.],
  [The jet left the runway during the roll.], [The mission fails: "The jet left the runway during the take-off roll."], [Hold the centreline with the rudder through the whole roll.],
  [You climbed out with the gear down, or turned off the heading before the gear was up.], [The "To complete" line stays. When 15 minutes have passed, the mission fails.], [Raise the gear right after the lift-off, on the runway's heading, before any turn.],
  [15 minutes passed.], [Five seconds later the mission ends as a fail. The reason names the open goal: "The jet never left the ground.", "The gear was never raised." or "Not on the runway heading with the gear up."], [Ask the tower for the next step as soon as the last one is done.],
  [You never left the ground.], [When you end the flight, or the time runs out, the mission fails: "The jet never left the ground."], [Use full power on the runway and raise the nose as the speed nears the reference.],
)

A crash, damage, an ejection or a start step out of order fails this lesson as it fails every mission (@scoring-at-once).

=== The usual reasons for a fail <lesson-takeoff-usual>

- *A move without its call.* The four calls are four separate clearances. "Taxi to runway" does not clear you onto the runway. "Line up" does not clear the take-off.
- *A corner cut on the taxi.* The game checks the middle of the jet against the paved shapes, with a margin of 5 m. A wide swing over the sand at a junction is enough to fail.
- *A fast taxi.* Slow to a few knots for each turn. Brake before the turn.
- *The line-up on the first runway you meet.* At Ramon and Nevatim parallel runways lie side by side, and at Ramat David the runways cross. Read the red sign before you enter (@ground-signs-signs).
- *The gear forgotten.* The lesson is not passed at the lift-off. It is passed with the gear up on the heading.
