#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Clicking the cockpit")#idx("Mouse, in the cockpit")The switches, knobs and buttons of the 3D cockpit answer the mouse. The left button works a control. The right button turns the head (@views-cockpit). Each control also shows what its key did: press a control's key, and its switch moves in the cockpit.

=== The rule every control follows <clicking-rule>

#grid-table(
  (auto, 1fr),
  ([The control], [What the mouse does]),
  [A switch, or a knob with fixed positions], [*A click* moves it one position on. After the last position it goes round to the first. \ *A drag* moves it one position on or back, and stops at the ends: drag up or down on a switch, round on a knob. \ *The wheel* turns a knob of four positions or more. Over a switch the wheel stays the view's zoom.],
  [A knob that turns smoothly (a light's or a display's brightness, a volume)], [*The wheel* or *a drag* turns it in small steps.],
  [A push button], [It is down while you hold the mouse button, and comes up when you let go.],
  [A spring-loaded switch (a TEST position, for example)], [It stays where you put it while you hold the mouse button, and goes back to rest when you let go.],
  [A switch under a guard], [*The first click* lifts the guard. The next clicks move the switch. Closing the guard puts the switch back to its normal position.],
  [A button round a display], [A click presses it. A full view of the display brings every one of them within reach (@views-mfd).],
)

=== A switch of three positions <clicking-three>

A click moves one position, so a switch of three positions needs two clicks to go from one end to the other. The main power switch of the Sufa and the Barak goes from OFF through BATT to MAIN PWR: two clicks. Its key sets it to MAIN PWR at once.

In a #term("lesson") the #term("notebook") tells you when a switch stands one click short (@notebook-hints).

=== What takes no mouse <clicking-not>

- *The throttle and the stick.* Use the keyboard, a joystick or a throttle lever (@keys-joystick).
- *The pilot's body.* A click goes through it to the control under it (@views-body).
- *The ejection.* It takes three presses of its key within a second each, so that a stray press never fires the seat (@time-pause-eject). In the Adir three clicks on the ejection handle the same way fire the seat too, with the seat's lever at ARMED: the #other("f35i", "canopy-seat").

=== Controls with no system behind them <clicking-moves>

Every control of the cockpit moves and keeps its position. Many of them work a system the sim has. The others move with no effect. Each jet's manual says of every control which it is, in its chapter "The aircraft": the #other("f16i", "cockpit"), the #other("f16d", "cockpit") and the #other("f35i", "cockpit").
