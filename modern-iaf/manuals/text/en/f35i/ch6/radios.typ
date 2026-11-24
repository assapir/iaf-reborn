#import "src.typ": *

This section covers talking, telling friend from foe, and the picture that other aircraft send to the jet.

=== The radios <radios-radios>

The real jet has no radio panel. The radios are set on the CNI format of the #term("PCD")#codeone. The three knobs #row("COM_A"), #row("COM_B") and #row("COM_C") set the volumes only.

#in-sim[The CNI format's layout is inferred. COM1 and COM2 take a preset or a frequency from its keypad, the up-front controls' keys work it too, and the function bar shows the presets and the UHF frequency. The transponder's modes, its code and IDENT are there as well. #row("COM_A") sets the volume of the radio calls: none at its stop, the game's normal level at the position it starts at. COM B and COM C turn and change nothing: the sim's radio calls are on COM A. You speak through two lists of calls:
  - the calls to air traffic control, in #other("game", "tower");
  - the calls of the airborne controller, the AWACS, in #other("game", "awacs").]

=== Combat identification <radios-id>

The jet joins what its sensors know about another aircraft into one identity. The real display draws it in one of three colours, green for a friend, yellow for an unknown and red for a possible enemy, and in different shapes#codeone. Which shape goes with which identity is inferred:

#table(
  columns: (1fr, 1fr, 2.4fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Shape], [Identity], [The sim's rule (inferred)]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [Green circle], [Friend], [The aircraft answers the jet's interrogator as a friend.],
  [Red diamond], [Hostile], [The AWACS names it hostile over the data link, or the threat warning hears its radar.],
  [Yellow square], [Unknown], [Anything else.],
)

How the real jet decides is not public: open. In the sim the interrogator runs by itself; there is no key for it. The shapes show on SRCH and ASR (@radar-aa, @radar-ag), on the TSD (@navigation) and on the helmet's designator (@hmd).

=== The data link <radios-link>

The data link sends tracks between aircraft without a word spoken. On the real jet the jet's computers run it; no switch for it is known (inferred).

#in-sim[The data link is on from the start of the flight. The TSD shows:
  - the other jets of your flight, in green with their number in the flight;
  - the aircraft that the AWACS sees, each by its identity.
  Each track has a line along its heading. The tracks are renewed every 4 seconds.]
