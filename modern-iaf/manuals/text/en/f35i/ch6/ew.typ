#import "src.typ": *

This section covers what warns you of a threat, how you release chaff and flares, and what they do to a missile.

=== The TWD format <ew-twd>

The threat warning display, TWD, is a format of the #term("PCD"). It shows the radars that the jet hears. The real format's layout is open; the sim's circle is inferred, and its symbols are those of the F-16s' threat display.

#display("twd_maw", [The TWD: one fighter radar locked on the jet, in the square, and one that has launched a radar-guided missile, in the circle and the diamond; a missile warning at the upper right, "AAM" with 7 seconds.])

- *Your jet* is at the centre, its nose up.
- *Each radar* shows at its bearing. Its ring tells what it does: the outer ring while it searches, the inner ring when it locks on you, close to the centre when it launches a radar-guided missile. A missile that homes on heat sends no radar signal, so its launch does not show here.
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

The real jet's cameras detect and track a missile in flight#das-wiki. How the pilot is warned is not public: open.

#in-sim[A missile launched at you, radar-guided or heat-seeking, shows as a red M at its bearing. Under it are its class, AAM for a missile fired from the air or SAM for one fired from the ground (inferred), and the seconds to its arrival, or two dashes while it does not close:
  - on the TWD, on the outer ring (@fig-d-twd_maw);
  - in the helmet, on a ring about the nose mark (@hmd).
  The launch tone sounds. The warning does not name the missile itself. The DAS format shows the same marks under the forward camera's picture (@pcd).]

=== Chaff and flares <ew-cmds>

The jet carries chaff and flares. The function bar and the SMS format show their counts (@stores). The real jet has no dispenser panel; its controls are on the grips and on the display (inferred). In the sim the F-16's dispenser set stands in, on keys only.

- #key("Drop chaff") and #key("Drop flares") release one at a time.
- #key("CMDS mode knob") steps the dispenser's mode: OFF, STBY, MAN, SEMI, AUTO, BYP. It starts at STBY.
- #key("CMDS program (1-4)") selects one of four programs. A program is a fixed number of chaff and flares at fixed intervals.
- #key("CMS forward: run the CMDS program") runs the selected program in MAN, SEMI and AUTO. In BYP it releases one chaff and one flare.
- #key("CMS aft: stop dispensing") stops it.
- In SEMI, a launch warning makes the voice say "Counter"; #key("CMS right: consent (SEMI) / enable AUTO") then runs the program. In AUTO, after the same key once, the program runs by itself at each launch warning.

Nothing leaves the jet with the landing gear handle down.

A flare burns hotter than the engine and draws the seeker of a heat-seeking missile. Chaff is a cloud of thin strips that gives a radar a larger echo than the jet's. A decoy acts on a missile in flight, at the moment it is released. Newer heat-seeking missiles tell a flare from a jet by the colours of its heat and by its path#footnote[Wikipedia, "Flare (countermeasure)": "More modern IR-guided missiles have sophisticated on-board electronics and secondary electro-optical sensors that help discriminate between flares and targets"; "spectral discrimination" and "trajectory discrimination", #link("https://en.wikipedia.org/wiki/Flare_(countermeasure)"). Checked 22 November 2026.]. A radar that measures speed along its line of sight tells the chaff, which slows at once, from a jet that flies toward it or away from it. A jet that turns to move across the radar's line is hard to tell from the chaff#footnote[Wikipedia, "Chaff (countermeasure)": modern radars "can thus distinguish chaff from an aircraft, which continues to move at high speed"; an aircraft moving "predominantly perpendicular to the radar source" is "more difficult to separate from the effectively stationary chaff", #link("https://en.wikipedia.org/wiki/Chaff_(countermeasure)"). Checked 22 November 2026.].

#in-sim[
  - *A decoy.* At each release every missile that flies at the jet may follow it: a flare a heat-seeking missile, chaff a radar-guided one. A missile that follows a decoy does not come back to the jet. The chance is each seeker's own (inferred). Within the missile's last 6 seconds a flare draws an R-73 about one time in three, an AIM-9M one in four, an AIM-9X or a Python 5 fewer than one in ten. Chaff draws a radar-guided missile about two times in five with the jet on the missile's beam. With the jet flying straight away from it, chaff draws an R-27R one time in five, and an AIM-120 or a surface-to-air missile one in twelve. A decoy has its full chance within the missile's last 6 seconds; one released earlier has less, and it burns out after 4 seconds. Above 4 g every decoy has one and a half times its chance; a flare beside a lit afterburner, a quarter.
  - #key("ECM jammer") lights the advisory ECM ON (@warnings). #term("Not modelled"): the jet's electronic attack.
]
