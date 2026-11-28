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
  [#scr("end_flight")], [Ends the flight now (@time-pause-leave).],
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

The jet and the mission's clock run faster.

#caution[At a faster clock the jet answers the controls as fast as the clock runs. Near the ground or another aircraft a small move becomes a large one. Go back to normal speed with #key("Real-time speed") before a take-off, a landing or a fight.]

=== The sound <time-pause-mute>

#idx("Mute")#key("Mute / unmute sound") silences every sound of the game, and a second press brings the sound back. It is the #scr("mute") setting of the #scr("sound") settings (@settings).

=== Leaving a flight <time-pause-leave>

To leave a flight at any moment:

+ Press #keycap("Esc").
+ Select #scr("end_flight").
  #then[The flight ends, and the #term("Hangar") opens.]

=== Ejecting <time-pause-eject>

#idx("Ejection, in the game")#warning[An ejection ends the flight. The key works at any moment, on the ground too, as long as the jet is in one piece: once it has blown up in the air, the key does nothing and the flight ends 5 seconds later. It needs three presses so that one stray press does nothing.]

+ Press #key("Eject (press 3 times)") three times.
  #then[The seat leaves the jet. Every sound and the radio stop. The view stays outside, on the seat and the jet.]

The flight is over, and the Hangar opens. When to eject from the jet is in its manual: the #other("f16i", "ejection"), the #other("f16d", "ejection") and the #other("f35i", "ejection").
