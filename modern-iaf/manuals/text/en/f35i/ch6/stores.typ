#import "src.typ": *

This section covers what the jet carries, how you arm it, how you select a weapon, and how you drop stores in an emergency. The stores are chosen before the flight (#other("game", "loadout")).

=== The stations <stores-stations>

The real jet has two weapon bays with two stations each, and six stations under the wings#wiki[Armament]. The sim numbers 11 stations from the left wing tip to the right (the numbering is inferred). Stations 4, 5, 7 and 8 are inside the two weapon bays; the others are under the wings and the body. With the bays only, the jet keeps its clean shape.

#table(
  columns: (0.6fr, 1.4fr, 2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Station], [Where], [What the sim hangs there]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [1, 11], [Outer wing pylons], [The AIM-9X short-range missile.],
  [3, 9], [Inner wing pylons], [The AIM-120 missile, or a 2,000 lb or 1,000 lb bomb.],
  [4, 8], [Bays, outer side], [A GBU-31 or GBU-32 bomb, four GBU-39 bombs on one rack, or the AIM-120.],
  [5, 7], [Bays, door side], [The AIM-120.],
  [2, 10, 6], [Middle wing pylons, centre line], [Nothing.],
)

The gun is inside the jet, over the left intake, with 180 rounds.

=== The SMS format <stores-sms>

The stores management system format, SMS, of the #term("PCD") shows the jet from above:

- each station with its number and its store in green: a missile slim, a bomb fat. A number beside a store is the count on that station. An empty station is a short line;
- a white box round the selected station;
- under the jet, the selected weapon's name with its total count, or NO WPN SELECTED;
- over that line, ARM in green or SAFE in yellow: the master arm (inferred; the real format's place for it is open);
- the counts of CHAFF and FLARE, yellow at none, and GUN with its rounds.

The counts fall with each release, and a jettison empties its stations.

#display("sms", [The SMS format: the jet's outline with a missile in each bay, the selected one in a box, the weapon's name and count, the chaff and flare counts and the gun's rounds.], width: 60%)

=== Master arm <stores-arm>

#row("MASTER_ARM") holds every weapon at SAFE. The jet starts each flight at SAFE.

#picture("front", ("MASTER_ARM": "1"), width: 70%)

+ *Set* #ctl("MASTER_ARM") *to ARM*, with a click or with #key("Master arm"). #sym.arrow.r *The SMS reads ARM. The helmet shows ARM at the lower left.*

At SAFE the weapon release and the trigger do nothing.

=== Selecting a weapon <stores-select>

- #key("Next air-to-air weapon") selects the next kind of missile, and the air-to-air master mode.
- #key("Next air-to-ground weapon") selects the next kind of bomb, and the air-to-surface master mode.
- #key("Cycle master mode") steps the master modes; #key("Navigation mode") returns to navigation.

#sym.arrow.r *The portal headers read A-A, A-S or NAV. The SMS boxes the station that goes next and names the weapon. The helmet names it at the lower left.*

=== The bay doors <stores-doors>

The bay doors are closed in flight. You do not open them yourself: a release from a bay opens them, lets the store go and shuts them.

#in-sim[Hold the release until the store leaves: the doors take about half a second to open, and they shut half a second after the release. While they are open the jet has more drag.]

=== What the sim checks before a release <stores-checks>

- The master arm is at ARM.
- The landing gear handle is up.
- For a bomb: the speed is at most 600 KCAS, calibrated airspeed in knots, and the dive is at most 60°. The jet is not inverted and not under negative g.

A release outside these is refused: the store stays on its station.

=== Jettison <stores-jettison>

A jettison drops stores unarmed to make the jet lighter or cleaner. On the real jet #row("JETT_SEL") chooses what goes and #row("EMER_JETT") drops it. The real procedure is not public: open.

+ *Press* #row("EMER_JETT") or #key("Emergency jettison"). #sym.arrow.r *Every bomb and rack leaves the jet. The stores in the bays leave as soon as the doors are open. The air-to-air missiles stay. Nothing explodes.*

#in-sim[
  - The jettison is refused on the ground.
  - #row("JETT_SEL") turns and changes nothing: the button always drops the same stores.
  - A selective jettison, of one kind of store, is #nis on the #jet.short.
]
