#import "/modern-iaf/manuals/layout/manual.typ": *

This section covers the keys that act on the game itself during a flight: the pause menu, the pause key, the speed of time, the sound, and the ways a flight ends.

=== The pause menu <time-pause-menu>

#idx("Pause menu")
+ Press #keycap("Esc") during a flight.
  #then[The flight freezes and the pause menu opens over it: #scr("paused"), with the mission and the jet you fly.]

#screen("flight_pause", [The pause menu.])

#grid-table(
  (auto, 1fr),
  ([Entry], [What it does]),
  [#scr("resume")], [Closes the menu. The flight goes on from where it froze. #keycap("Esc") does the same.],
  [#scr("preferences")], [Opens the settings over the frozen flight (@settings), with the #scr("keys_screen") and #scr("joystick_screen") screens (@keys-joystick). #keycap("Esc") goes back to the pause menu. Your changes apply when you go back: graphics, sound, keys and language.],
  [#scr("end_flight")], [Ends the flight now and opens its #term("debrief") (@debrief). A Training mission is scored as it stands at that moment (@time-pause-leave).],
  [#scr("quit_desktop")], [Asks #scr("quit_q") and, when you confirm, closes the game.],
)

=== The pause key <time-pause-key>

#idx("Pause")#key("Pause") freezes the flight and its sounds without a menu. A blinking pause mark shows on the screen. Press the key again, or #keycap("Esc"), to go on.

=== The speed of time <time-pause-speed>

#idx("Time speed")A long leg takes less of your time at a faster clock.

#grid-table(
  (auto, 1fr),
  ([Key], [What it does]),
  [#key("Cycle time speed x1 / x2 / x4")], [Each press steps the clock: twice as fast, four times as fast, then normal again.],
  [#key("Real-time speed")], [Sets the clock to normal at once.],
)

The jet and the mission's clock run faster. The #term("time allowed") is counted on the mission's clock, so it runs out faster too.

#caution[At a faster clock the jet answers the controls as fast as the clock runs. Near the ground or another aircraft a small move becomes a large one. Go back to normal speed with #key("Real-time speed") before a take-off, a landing or a fight.]

=== The sound <time-pause-mute>

#idx("Mute")#key("Mute / unmute sound") silences every sound of the game, and a second press brings the sound back. It is the #scr("mute") setting of the #scr("sound") settings (@settings).

=== The Mission accomplished panel <time-pause-done>

#idx("Mission accomplished")When you reach a Training mission's objectives, the flight freezes under a panel titled #scr("fl_complete"). It reads:

#scr-text("fl_kept")

#screen("flight_accomplished", [The panel at the end of a passed #term("lesson").])

- #scr("resume") closes the panel, and you fly on. The panel does not come back in this flight. #keycap("Esc") does the same.
- #scr("debrief") ends the flight and opens the debrief.

The pass is yours from this moment (@scoring-pass-kept).

While a goal is still open after the take-off, a line at the top corner of the screen names what is missing, for example "To complete: raise the gear."

=== A failed mission <time-pause-fail>

#idx("Fail banner")When a Training mission fails, a banner shows #scr("fail") and the reason. Five seconds later the flight ends and the debrief opens. The reasons are in @scoring.

=== Leaving a flight <time-pause-leave>

To leave a flight at any moment:

+ Press #keycap("Esc").
+ Select #scr("end_flight").
  #then[The debrief opens.]

A Training mission you leave before its objectives are reached counts as it stands: it is a #scr("fail") with the first objective you did not reach as the reason. A mission you already passed stays a #scr("pass").

To fly the mission again, select #scr("fly_again") in the debrief.

=== Ejecting <time-pause-eject>

#idx("Ejection, in the game")#warning[An ejection ends the flight and fails a Training mission. The key works at any moment, on the ground too. It needs three presses so that one stray press does nothing.]

+ Press #key("Eject (press 3 times)") three times.
  #then[The seat leaves the jet. Every sound and the radio stop. The view stays outside, on the seat and the jet.]

The flight is over: the mission ends as a #scr("fail"), with "The pilot ejected." as its reason, and the debrief opens. When to eject from the jet is in its manual: the #other("f16i", "ejection"), the #other("f16d", "ejection") and the #other("f35i", "ejection").
