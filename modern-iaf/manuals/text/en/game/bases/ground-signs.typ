#import "/modern-iaf/manuals/layout/manual.typ": *

The game paints each base's runways and taxiways with the markings of a real airfield and stands signs along the taxiways. Read them, and you can taxi from any parking spot to any runway.

=== Taxiways <ground-signs-taxi>

#idx("Taxi line")A taxiway is a paved lane between the aprons and the runways. A yellow line runs along its middle. Keep the nose wheel on the yellow line: the line follows the route through every junction and turn, and it keeps the jet on the pavement.

The briefing's map shows your taxi route before the flight as a dashed line (@briefing-map).

=== The signs <ground-signs-signs>

#idx("Taxiway signs")The signs stand beside the taxiways, on your left as you taxi. There are two kinds.

#screen("ground_signs", [Ramon's two kinds of sign: a direction sign, and a holding sign.], numbered: true, width: 75%)

#screen-table(
  "ground_signs",
  (auto, 1fr, 1.3fr),
  ([No.], [Sign], [Looks like], [Tells you]),
  ("direction", [#idx("Direction sign")Direction sign], [Black letters on yellow: a runway number and an arrow, for example 07R with an arrow up.], [The way to that runway's start. It stands about 40 m before a junction where the routes to the runways part. Take the branch the arrow of your runway points to.]),
  ("holding", [#idx("Holding sign")Holding sign], [White letters on red: one runway number.], [The runway begins here. Stop. The number is the runway end you take off from when you enter at this place. Go on only with the #term("tower")'s line-up #term("clearance").]),
)

*To find your runway:*

+ Read your runway's number on the briefing or on the #term("notebook")'s #scr("nb_taxi") tab.
+ At each junction, find the yellow sign with that number.
+ Take the way its arrow points.
+ Go on until you reach a red sign with that number.
  #then[You are at the #term("holding point") of your runway.]

A jet that follows one number's signs from any parking spot reaches that runway's start.

Where a yellow sign and a red sign would stand close together, they form one row: the yellow boards first, from left to right in the order of the turns, and the red board last, nearest the taxiway.

#note[The taxiways carry no names in the game, so no sign names the taxiway you are on. At Hatzerim no sign leads to the short runway 10 / 28.]

=== The holding point <ground-signs-hold>

#idx("Holding point")#idx("Hold short")The #term("holding point") is where a taxiway meets its runway. The red holding sign marks it, 90 m from the runway's centreline. To hold short means to stop there and wait.

The briefing's map marks the holding point of your route with a pin (@briefing-map). The tower answers a line-up request when you are at the holding point or near it. From farther back it answers "hold position".

=== Lining up <ground-signs-lineup>

#idx("Line-up")After the line-up clearance:

+ Taxi onto the runway.
+ Turn onto the centreline, toward the runway's far end.
+ Stop on the centreline near the runway's start.
+ Check the heading against the runway's heading on the briefing.
+ Request the take-off.

The tower clears the take-off when you are lined up at the runway's start. From a place short of it, it answers with the line-up again.

=== Runway markings <ground-signs-markings>

#idx("Runway markings")All runway markings are white.

Where the pavement before a runway's start carries yellow chevrons, it is not part of the runway: do not land on it. The markings of the runway itself, from its start (@fig-s-runway_markings):

#screen("runway_markings", [Runway 25R at Ramon, from just above its start.], numbered: true)

#screen-table(
  "runway_markings",
  (auto, 1fr),
  ([No.], [Marking], [Meaning]),
  ("stripes", [Threshold stripes], [A row of long stripes across the runway: the runway starts here.]),
  ("number", [The runway's number], [Two large digits, and a letter L or R on a parallel runway. You read them upright when you face down the runway from this end.]),
  ("centreline", [The centreline], [A dashed line down the middle. Hold it on the take-off roll and the landing roll.]),
  ("touchdown", [Touchdown zone marks], [Pairs of bars each side of the centreline, every 150 m: three, three, two, two, one, one.]),
  ("edge", [Edge lines], [A line along each side of the runway.]),
)

#screen("runway_aiming", [Runway 25R farther along: the aiming point.], numbered: true, width: 75%)

#screen-table(
  "runway_aiming",
  (auto, 1fr),
  ([No.], [Marking], [Meaning]),
  ("aiming", [The aiming point], [Two broad blocks, 400 m past the threshold, on the long runways. Aim at them on the final approach.]),
)

Dark streaks of tyre rubber mark the part of the runway where jets touch down.

In the air the painted runways show from far away.
