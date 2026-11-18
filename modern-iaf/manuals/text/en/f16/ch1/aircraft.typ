#import "src.typ": *

#if sufa [
  The #jet.name is the two-seat F-16 built for Israel. It carries the F100-PW-229 engine, two conformal fuel tanks on the upper fuselage that hold 450 US gallons between them, and a dorsal compartment behind the canopy for avionics#aft. It is based on the Block 52+ aircraft#footnote[Wikipedia, "General Dynamics F-16 Fighting Falcon variants", section "F-16C/D Block 50/52 Plus", #link("https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon_variants"). Checked 18 November 2026.]. The first two were delivered on 19 February 2004#f16net.
] else [
  The #jet.name is Israel's two-seat F-16D. Israel received F-16Ds of Block 30 and of Block 40, with the F110-GE-100 engine and a dorsal spine behind the canopy for avionics#f16net.
]

The F-16D is the two-seat version of the F-16: the seats stand one behind the other under one canopy. It has one engine, fed by an intake under the fuselage, a thin, moderately swept wing and one fin#fm-full[page 1-6].

#table(
  columns: (auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [Span], [32 ft 10 in (10.0 m)],
  [Length, with the nose probe], [49 ft 5.2 in (15.1 m)],
  [Height], [16 ft 10 in (5.1 m)],
)
The sizes are the Block 50/52's#fm[page 1-7, "Aircraft Dimensions"]#if sufa [.] else [; that they hold for the #jet.short's blocks is inferred.]

This manual describes the systems from the public flight manual of the Block 50/52+ aircraft. An Israeli jet's own equipment is not public; where the cockpit of this manual differs from that flight manual, the text follows the cockpit.

=== Stores stations <aircraft-stations>

The real jet numbers its stores stations 1 to 9, with 3A and 7A beside stations 3 and 7#fm[page 1-93, the stores stations' power table]. Stations 1 and 9 are the wing tips, 2 and 8 the outboard wing, 3 and 7 the middle of the wing, 4 and 6 the inboard wing, which can carry fuel tanks, and 5 the centreline (the places are inferred from the numbering). Two chin stations under the intake carry pods (#term("HDPT"))#fm[page 1-83, the left and right inlet stations].

#in-sim[The stations are 1 to 9 as above. The right chin station is 5R; the left one is station 10 (5L)#if sufa [ and carries the navigation pod]. What each station carries is in @stores.]

=== In the sim <aircraft-sim>

#table(
  columns: (auto, auto),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [Engine], if sufa [F100-PW-229: 17,800 lb of thrust at military power, 29,160 lb with full afterburner] else [F110-GE-100: 17,110 lb of thrust at military power, 29,000 lb with full afterburner],
  [Empty weight], if sufa [20,500 lb] else [19,100 lb],
  [Internal fuel], if sufa [8,850 lb, the conformal tanks included] else [5,800 lb],
  [Maximum take-off weight], if sufa [52,000 lb (23,582 kg)] else [42,300 lb (19,187 kg)],
)

The rear seat is #term("not modelled"): you fly from the front seat and do the rear seat's work from there.
