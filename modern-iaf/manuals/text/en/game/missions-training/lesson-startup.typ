#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Start-up lesson")The first #term("lesson") of each jet: missions 2011 (Sufa, Ramon), 2021 (Barak, Ramat David) and 2031 (Adir, Nevatim).

=== Its purpose <lesson-startup-purpose>

You learn to bring a cold jet to life in the real order, by the jet's own checklist card, and to ask the #term("tower") before you start. The lesson ends on the parking spot: you do not taxi.

The procedure itself, switch by switch, is in each jet's manual: the #other("f16i", "cold-start"), the #other("f16d", "cold-start") and the #other("f35i", "cold-start"). This section says what the game checks.

=== What the game checks <lesson-startup-objectives>

The briefing lists three objectives:

- #scr("obj_idle")
- #scr("obj_avionics")
- #scr("obj_safe")

all within 10 minutes of the start.

The lesson passes when all of these are true:

#grid-table(
  (auto, 1fr),
  ([Check], [Exactly]),
  [The tower cleared the start], [You requested start-up and heard "cleared to start" before the engine turned (@tower-ground).],
  [The checklist is done], [Every item of the card from its top to the end of its section before taxi is ticked in the #term("notebook"), except the items you only read and acknowledge (@notebook-checklist). The Sufa and the Barak have 36 such items. The Adir has 15.],
  [The engine idles], [The engine runs at 60 % #term("RPM") or more.],
  [The avionics are up], [The displays and the avionics have power. In the Adir the avionics report ready 90 seconds after the battery went on.],
  [In time], [All of the above within 10 minutes of the start of the flight.],
  [Nothing failed], [None of the things that fail any mission at once happened (@scoring-at-once).],
)

When the last check comes true, the #scr("fl_complete") panel opens (@time-pause-done). The #term("debrief") then reads: #scr-text("done_startup")

In the Sufa and the Barak the last thing to come true is usually the #term("INS"): its alignment takes 90 seconds from the moment its knob goes to STOR HDG, and its item is done only when the knob then goes on to NAV. Start the alignment as soon as the avionics have power, and do the other items while it runs.

=== The goals in the debrief <lesson-startup-debrief>

#grid-table(
  (auto, 1fr),
  ([Goal], [Target]),
  [Idle with the avionics up within 10 min], [The time it took you, against 10 minutes.],
  [Checklist steps done], [The items done, against the items the lesson asks for.],
)

=== What fails it <lesson-startup-fails>

#grid-table(
  (1fr, 1.2fr, 1.2fr),
  ([What you did], [What the game does], [How to avoid it]),
  [You turned the engine before the tower cleared the start.], [The tower says "engine start without clearance". The mission fails at once.], [Request start-up first and wait for "cleared to start".],
  [You moved the jet more than 10 m off its spot.], [The tower says "taxi without clearance". The mission fails at once.], [Leave the brakes alone and the throttle at idle. This lesson has no taxi.],
  [You did a start step out of its order.], [The jet refuses the step. The #term("notebook") shows the fault in red. The mission fails at once, with the fault as its reason (@scoring-order).], [Follow the yellow band from the top of the card. Read the hint line before each click (@notebook-hints).],
  [You moved the throttle to OFF with the engine running.], [The engine shuts down. The mission fails at once.], [Once the engine runs, leave the Throttle OFF key alone.],
  [10 minutes passed before the checks came true.], [Five seconds later the mission ends as a fail. The reason names what is missing: "The engine never started.", "The engine never reached idle with the avionics up.", or the first start step you skipped.], [Start the INS alignment early. Go on to the next item as soon as one is done.],
  [You ended the flight with items open.], [The mission is a fail. The reason names the first start step you skipped, or says that a checklist item was skipped.], [Stay until the #scr("fl_complete") panel opens.],
)

A crash, damage, an ejection or a jet off the pavement fails this lesson as it fails every mission (@scoring-at-once).

=== The usual reasons for a fail <lesson-startup-usual>

- *The engine start came before the call.* The first line of the checklist page is the tower call. Make it first.
- *The throttle came up too early.* In the Sufa and the Barak, wait until the RPM gauge reads 20 % before you move the throttle from OFF to idle. The ring round the gauge shows the value to watch for.
- *The main power stands at BATT.* The switch has three positions. One click from OFF gives BATT, and the next gives MAIN PWR (@clicking-three).
- *The avionics went on too early.* Wait for the engine at idle. The generators come on line just before idle, and the avionics get their power from them.
- *The lesson seems finished and nothing happens.* An item higher on the card is still open. Page back in the notebook to the yellow band.
