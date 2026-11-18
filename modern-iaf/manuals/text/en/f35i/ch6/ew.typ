#import "src.typ": *

This section covers what warns you of a threat and how you release chaff and flares. It gives the displays and the switches only. Electronic attack is outside this manual.

=== The TWD format <ew-twd>

The threat warning display, TWD, is a format of the #term("PCD"). It shows the radars that the jet hears. The real format's layout is open; the sim's circle is inferred, and its symbols are those of the F-16s' threat display.

#display("twd_maw", [The TWD: one fighter radar locked on the jet, in the square, and one that has launched, in the circle and the diamond; a missile warning at the upper right with 10 seconds.])

- *Your jet* is at the centre, its nose up.
- *Each radar* shows at its bearing. Its ring tells what it does: the outer ring while it searches, the inner ring when it locks on you, close to the centre when it launches.
- *The colour:* yellow while it searches, red when it locks or launches.
- *The label* tells its kind: an aircraft by a number under a small roof, a ground site by a digit or a letter, a gun by an A in a box, a ship by an S. A radar that the jet cannot name is a U.
- *The diamond* is on the threat that matters most: a launch before a lock, a lock before a search. *A square* marks a lock. *A flashing circle* marks a launch.
- *Bottom:* the count of the threats.

A new threat flashes for 4 seconds with a tone. A launch has its own tone.

#table(
  columns: (1.5fr, 2.4fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Key], [What it does]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [#key("Threat warning: HANDOFF")], [Moves the diamond to the next threat.],
  [#key("Threat warning: priority / open mode")], [Shows the 5 first threats, or up to 16.],
  [#key("Threat warning: unknowns")], [Shows or hides the U symbols.],
  [#key("Threat warning: target separate (hold)")], [Spreads symbols that lie over each other.],
  [#key("Threat warning: system test")], [Shows a test pattern for 3 seconds.],
)

These are the functions of the F-16's threat warning panel. The #jet.short's own controls for the format are open.

=== The missile warning <ew-maw>

The real jet's cameras detect a missile in flight and warn the pilot#das-wiki. How the warning looks is not public.

#in-sim[A missile launched at you shows as a red M at its bearing, with the seconds to its arrival under it, or two dashes while it does not close:
  - on the TWD, on the outer ring (@fig-d-twd_maw);
  - in the helmet, on a ring about the nose mark (@hmd).
  The launch tone sounds. The warning does not name the missile. The DAS format, the cameras' own picture, is #nis.]

=== Chaff and flares <ew-cmds>

The jet carries chaff and flares. The function bar and the SMS format show their counts (@stores). The real jet has no dispenser panel; its controls are on the grips and on the display (inferred). In the sim the F-16's dispenser set stands in, on keys only.

- #key("Drop chaff") and #key("Drop flares") release one at a time.
- #key("CMDS mode knob") steps the dispenser's mode: OFF, STBY, MAN, SEMI, AUTO, BYP. It starts at STBY.
- #key("CMDS program (1-4)") selects one of four programs. A program is a fixed number of chaff and flares at fixed intervals.
- #key("CMS forward: run the CMDS program") runs the selected program in MAN, SEMI and AUTO. In BYP it releases one chaff and one flare.
- #key("CMS aft: stop dispensing") stops it.
- In SEMI, a launch warning makes the voice say "Counter"; #key("CMS right: consent (SEMI) / enable AUTO") then runs the program. In AUTO, after the same key once, the program runs by itself at each launch warning.

Nothing leaves the jet with the landing gear handle down.
