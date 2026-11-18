#import "/modern-iaf/manuals/layout/manual.typ": *

You fly from a 3D cockpit. You turn your head in it, lean, zoom and step outside the jet. Every key in this section can be changed on the #scr("keys_screen") screen, in its #scr("group_views") group (@keys-joystick).

=== The cockpit view <views-cockpit>

#idx("Cockpit view")Every flight opens in the cockpit, with the head straight ahead and a wide view that takes in the whole front panel.

#idx("Mouse look")*To look around with the mouse:*

+ Hold the right mouse button.
  #then[The pointer hides.]
+ Move the mouse.
  #then[The head turns with it. It turns as far down as the side consoles.]
+ Let go of the button.
  #then[The head stays where you left it, and the pointer shows again.]

To look straight ahead again, double-click the right mouse button.

The left mouse button works the cockpit's controls (@clicking).

=== Zoom <views-zoom>

#idx("Zoom")The zoom narrows the view, from the wide view to a close view in which a display's small text reads from the seat.

#grid-table(
  (auto, 1fr),
  ([Control], [What it does]),
  [The mouse wheel, or a trackpad's scroll], [Zooms toward the pointer: what is under the pointer stays under it. Over a knob the wheel turns the knob instead (@clicking).],
  [#key("Zoom in (equals key)") or #key("Zoom in (numpad)")], [Zooms in one step, about the middle of the view.],
  [#key("Zoom out (minus key)") or #key("Zoom out (numpad)")], [Zooms out one step.],
)

In a view from outside the jet the same keys move the camera nearer and farther.

=== The look keys <views-look>

#idx("Look keys")A look key turns the head to a fixed direction while you hold it. Let go, and the head turns back.

#grid-table(
  (auto, auto, auto),
  ([Left], [Middle], [Right]),
  [#key("Look front-left (45 deg)")], [#key("Look up (30 deg)")], [#key("Look front-right (45 deg)")],
  [#key("Look left (90 deg)")], [#key("Look forward")], [#key("Look right (90 deg)")],
  [#key("Look back-left (135 deg)")], [#key("Look back")], [#key("Look back-right (135 deg)")],
)

A joystick's hat turns the head to the same eight directions.

=== Leaning and moving the head <views-lean>

#idx("Lean")A lean key moves the head a little way while you hold it. Let go, and the head eases back to the seat. Lean to see a switch that the stick, the throttle or a panel's edge hides.

#grid-table(
  (auto, 1fr),
  ([Key], [The head moves]),
  [#key("Lean left"), #key("Lean right")], [6 cm to the side.],
  [#key("Lean forward")], [10 cm forward. Held for about a second, it goes on to 30 cm in the Sufa and the Barak. In the Adir it moves 2 cm.],
  [#key("Lean back")], [10 cm back.],
  [#key("Raise the head")], [10 cm up.],
  [#key("Lower the head")], [15 cm down.],
)

The head stops short of the canopy and the panels. The pilot's body hides while the head is off the seat.

=== A full view of a display <views-mfd>

#idx("Full view of a display")These keys bring the eye close to one display, so that the display and the buttons round it fill the screen.

#grid-table(
  (auto, 1fr),
  ([Key], [Shows]),
  [#key("Full view of the left MFD")], [The left display of the Sufa and the Barak. In the Adir: its one wide display.],
  [#key("Full view of the right MFD")], [The right display of the Sufa and the Barak. In the Adir: its one wide display.],
)

The jet flies on, and every other key works as from the seat. Click the display's buttons with the mouse. To go back to the seat, press the same key again or #keycap("Esc"). The other display's key cuts straight to that display.

=== The pilot's body <views-body>

#idx("Pilot's body, hiding")You see the pilot's legs, arms and hands when you look down. The left glove on the throttle covers some switches of the left console. A click still reaches a switch under the body. To see the switch:

- hold #key("Hide pilot's body (hold)"): the body hides while you hold the key;
- press #key("Hide / show pilot's body"): the body hides until you press the key again.

The body shows again at the start of every flight. In a #term("lesson") that rings the switch to use, the game hides the body by itself while it covers that switch (@notebook-ring).

=== Views from outside <views-outside>

#idx("Outside views")A view key moves the camera out of the cockpit. A view of something that is not there (a radar target with nothing locked, a weapon with none in the air) does nothing.

#grid-table(
  (auto, 1fr),
  ([Key], [The view]),
  [#key("Cockpit / HUD-only view")], [From an outside view: back into the cockpit. In the cockpit: changes between the cockpit and a view of the head-up display alone, without the cockpit round it. #key("Look forward") does the same.],
  [#key("Lock-on view")], [From the cockpit, the head follows the radar's target.],
  [#key("Padlock nearest object")], [From the cockpit, the head follows the object nearest the middle of the view.],
  [#key("View of the radar target")], [The radar's target, seen from outside it.],
  [#key("Threat view")], [Your jet and the nearest threat that the radar warning receiver hears. A second press: the head follows the threat from the cockpit.],
  [#key("Wingman view")], [Your jet and your wingman. A second press: the head follows the wingman from the cockpit.],
  [#key("Player-to-target view")], [Your jet with the radar's target beyond it.],
  [#key("Target-to-player view")], [The radar's target with your jet beyond it.],
  [#key("Fly-by view")], [Your jet from outside, as it flies by.],
  [#key("Chase view")], [Your jet from behind.],
  [#key("View from the weapon")], [The last weapon you released, while it flies.],
)

You fly the jet in every view. A view from outside ends a full view of a display.
