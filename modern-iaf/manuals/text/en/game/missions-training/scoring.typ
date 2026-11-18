#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Pass and fail")#idx("Scoring")The game marks every #term("lesson") as #scr("pass") or #scr("fail"). This section gives the rules that hold in all of them. Each lesson's own goals are in @lesson-startup, @lesson-takeoff and @lesson-range.

The jets' manuals describe what a procedure does to the aircraft. This section describes what the game does about it.

=== How a mission is marked <scoring-how>

- *A pass* needs every goal of the lesson reached, within the #term("time allowed"), with nothing from @scoring-at-once on the way.
- *A fail* comes at once from any of the things in @scoring-at-once, or at the end of the flight from a goal that was not reached.

A fail at once shows a banner with #scr("fail") and the reason. Five seconds later the flight ends and the #term("debrief") opens, with that reason first.

=== What fails any mission at once <scoring-at-once>

#idx("Fail at once")#grid-table(
  (1fr, 1.3fr, 1.2fr),
  ([What you did], [What the game does], [How to avoid it]),
  [#idx("Crash")You crashed the jet.], [Fail: "The jet crashed."], [Fly within the jet's limits. On the ground, taxi slowly.],
  [#idx("Damage")The jet took any damage.], [Fail: "The jet was damaged."], [Keep clear of what you shoot at and of the ground.],
  [#idx("Off the pavement")On the ground, the middle of the jet left the paved surface: the runways, the taxiways, the aprons and the shelters' pads. The game allows a margin of 5 m past each edge.], [Fail: "The jet left the pavement."], [Keep the nose wheel on the yellow taxi line and slow down before each turn.],
  [You ejected.], [Fail: "The pilot ejected." (@time-pause-eject)], [Keep off the ejection key.],
  [You did a phase on the ground before the #term("tower") cleared it.], [The tower says so. Fail, with the phase as the reason (@scoring-clearances).], [Call, wait for the answer, then act (@tower-ground).],
  [#idx("Wrong runway")You rolled faster than 30 kt along a runway that is not the mission's.], [Fail: "The take-off was not from the assigned runway."], [Line up on the runway the tower named. Its number is on the briefing and on the #term("notebook")'s #scr("nb_taxi") tab.],
  [You did a step of the engine start out of its order, or cut the engine.], [The jet refuses the step or shuts down. Fail, with the fault as the reason (@scoring-order).], [Follow the checklist's order (@notebook-checklist).],
)

=== How the clearances are checked <scoring-clearances>

#idx("Clearance")A #term("clearance") is the tower's answer to your call. The game watches four moments on the ground. At each one it looks for the clearance you should hold by then.

#grid-table(
  (auto, 1.2fr, 1fr, 1fr),
  ([Phase], [The game sees it when], [The answer that clears it], [The reason of the fail]),
  [Engine start], [The engine turns: 5 % #term("RPM") or more.], ["cleared to start"], ["Engine start without start-up clearance."],
  [Taxi], [The jet is on the ground more than 10 m from where it first stood.], ["taxi to runway ..."], ["Taxied without clearance."],
  [Entering the runway], [The jet is on the mission's runway, lined up along it.], ["line up runway ..." or "cleared for take-off"], ["Entered the runway without clearance."],
  [The take-off roll], [The jet is on that runway and faster than 30 kt.], ["cleared for take-off"], ["Take-off roll without take-off clearance."],
)

- "hold position" clears nothing. Call again.
- A clearance, once given, stays yours for the rest of the flight.
- The tower's answer is the clearance: act on it.
- Only an act without its clearance fails the mission. A call made out of order, or made twice, costs nothing.

The Start-up lessons check the first two phases. The Take-off and Weapons range lessons check all four.

*The wrong runway.* When you line up within 30° of a runway end that is not the mission's, the tower tells you once which runway you are on and which one is assigned, and a line at the top corner of the screen says the same while you stand there. Lining up there only warns. The roll there fails the mission.

=== The engine start's order <scoring-order>

#idx("Hot start, in a lesson")The jet itself refuses a start step that comes out of order, and what the jet does about it is in its manual: the #other("f16i", "cold-start"), the #other("f16d", "cold-start") and the #other("f35i", "cold-start"). In a lesson each of these faults also fails the mission at once.

#grid-table(
  (1.1fr, 1.4fr, auto),
  ([What you did], [The reason in the debrief], [Jet]),
  [Started the starter with the main power off.], ["The starter had no power: the main power was off."], [All],
  [Moved the throttle to idle below 20 % RPM: a #term("hot start").], ["Hot start: the throttle went to idle below 20 % RPM; the engine was shut down."], [Sufa, Barak],
  [Moved the throttle to idle with the engine not turning.], ["No light-off: the throttle went to idle with the engine not turning."], [Sufa, Barak],
  [Switched the avionics on before the engine ran.], ["Avionics power on before the generators: no power for them."], [Sufa, Barak],
  [Turned the #term("INS") knob with the main power off.], ["INS alignment without main power."], [Sufa, Barak],
  [Started the engine with the IPP off.], ["Engine start without the IPP running."], [Adir],
  [Started the engine before the IPP ran up.], ["Engine start before the IPP was up to speed."], [Adir],
  [Moved the throttle to OFF with the engine running.], ["Engine shutdown: the throttle went to OFF with the engine running."], [All],
  [Used the starter while the engine wound down above 20 % RPM.], ["Starter while the engine wound down above 20 % RPM: it did not engage."], [All],
)

=== The time allowed <scoring-time>

#idx("Time allowed")Each mission has a time allowed, shown on the briefing (@briefing-card). It runs on the mission's clock from the first moment of the flight.

#grid-table(
  (auto, auto, 1fr),
  ([Lesson], [Time allowed], [What must be reached in it]),
  [Start-up], [10 min], [The engine at idle, the avionics up, the checklist done.],
  [Take-off], [15 min], [In the air with the gear up on the runway's heading.],
  [Weapons range], [45 min], [The last kill the lesson needs.],
)

Five seconds after the time allowed, a mission whose goals are still open ends as a fail. The reason names the goal that is still open. A goal reached after the time allowed gives the reason "Not done within the time budget."

=== A pass is kept <scoring-pass-kept>

#idx("Pass, kept")The moment the last goal is reached, the game stores the pass and opens the #scr("fl_complete") panel (@time-pause-done). You may fly on: go round the pattern, try a landing, visit another base. Nothing that happens afterwards takes the pass away.

=== Where the result goes <scoring-result>

When the flight ends, the game scores it from its own recording of the flight and writes the result in two places:

- the debrief, which opens at once (@debrief);
- your #term("pilot log"), which keeps every flight with its debrief (@pilots). The #scr("missions") screen shows each mission's last result from it (@mission-list).

A flight you end yourself before the goals are reached is scored as it stands (@time-pause-leave).
