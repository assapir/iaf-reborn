#import "src.typ": *

The #jet.name is Israel's F-35A: a single-seat, single-engine stealth fighter that takes off and lands on a runway#wiki[Specifications (F-35A)]. The first two arrived in Israel in 2016#footnote[Lockheed Martin, "Israel" (the F-35's global enterprise), the timeline, #link("https://sustainability.lockheedmartin.com/f35/global-enterprise/israel.html"). #checked]. Israel fits systems of its own to the jet; they are not public, and this manual describes the F-35A.

#table(
  columns: (auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [Span], [35 ft (10.7 m)],
  [Length], [51.4 ft (15.7 m)],
  [Height], [14.4 ft (4.4 m)],
  [Engine], [One F135-PW-100, 40,000 lb of thrust],
  [Internal fuel], [18,250 lb],
  [Empty weight], [29,300 lb],
  [Maximum take-off weight], [70,000 lb class],
  [Load factor], [9 g],
)
The span, the length, the engine, the fuel and the load factor are the maker's#card-a\; the height and the weights are an encyclopedia's#wiki[Specifications (F-35A)].

The jet's shape and skin are made to return little radar energy. For the same reason it carries its weapons and all its fuel inside, and its sensors sit behind flush windows (inferred).

=== Weapon bays and stations <aircraft-stations>

Two weapon bays under the fuselage, each with two stations, hold the weapons of a stealthy flight. Stations under the wings carry more when stealth matters less#wiki[Armament].

#in-sim[
  Stations 4, 5, 7 and 8 are in the bays: a store there adds no drag. Stations 1, 3, 9 and 11 are under the wings; stations 2 and 10 carry nothing. What each station carries is in @stores.
]

=== In the sim <aircraft-sim>

#table(
  columns: (auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [Engine], [28,000 lb of thrust at military power, 43,000 lb with full afterburner],
  [Empty weight], [29,300 lb],
  [Internal fuel], [18,250 lb],
  [Maximum take-off weight], [70,000 lb (31,751 kg)],
)

Israel's own systems are #term("not modelled").
