#import "src.typ": *

=== Canopy

One canopy covers both seats. It is hinged at its aft end; #row("CANOPY_SWITCH") opens and closes it and the yellow #row("CANOPY_SPIDER") locks it. The red #row("lamp_canopy_0") warning light is on while the canopy is not locked#fm[pages 1-157 and 1-160]. The light must be out before the take-off roll: the air can tear an unlocked canopy off (inferred). A T-handle jettisons the canopy#fm[page 1-161].

=== Ejection seat

Each seat is an ACES II ejection seat. Pulling the ejection handle jettisons the canopy and fires the seat. The ejection safety lever locks the handle; the #row("lamp_caution_seat_not_armed_0") caution light is on while it is locked#fm[page 1-161]. When to eject is in @ejection.

=== Oxygen

The pilot breathes through a mask from a regulator. This cockpit has the #row("anim120") quantity indicator of the jets that carry liquid oxygen#fm[page 1-177 and figure 1-71, pages 1-177 to 1-179]. The regulator has three levers#fm[figure 1-71, page 1-178]: #row("PBG"), the supply lever (PBG, pressure breathing during high g; ON; OFF), #row("O2") (NORM mixes cabin air with oxygen, 100~% gives pure oxygen) and #row("EM-NO-TE") (EMER gives pure oxygen under pressure, also for the pilot's leak check of the mask; TEST MASK does the same for the ground crew's test). The #row("lamp_caution_oxy_low_0") caution light comes on with less than half a litre of oxygen left or a low pressure in the system#fm[figure 1-71, page 1-179].

=== Cabin air

Air bled from the engine pressurises and cools the cockpit and cools the avionics. #row("AirSource_knob") has four positions#fm[page 1-81]\; what DUMP and RAM are used for is inferred:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [OFF], [No bleed air: no pressure and no cooling.],
  [NORM], [Pressure and cooling. The position for flight.],
  [DUMP], [The cabin's pressure is let out; cooling goes on. For smoke or fumes.],
  [RAM], [Outside air through a scoop, with no bleed air: no pressure. For a fault of the bleed air.],
)

#row("anim104") shows the cabin's own altitude. The #row("lamp_caution_cabin_press_0") caution light comes on when it passes 27,000 ft#fm[page 1-82]: descend, and check the oxygen. The #row("lamp_caution_equip_hot_0") caution light means that the avionics get too little cooling air; without cooling they overheat (inferred).

#in-sim[
  - *Canopy.* Hold #row("CANOPY_SWITCH") at CLOSE until the canopy is down (10 seconds for the whole travel), then put #row("CANOPY_SPIDER") down. #sym.arrow.r *CANOPY goes out.* To open, lift the handle and hold the switch at OPEN. #key("Canopy") does the whole sequence either way.
  - *Ejection.* #key("Eject (press 3 times)"), pressed three times within a second, ejects.
  - *Cabin.* CABIN PRESS ALT follows the jet up to 8,000 ft, stays there up to about 23,000 ft and rises above that. With AIR SOURCE at OFF, DUMP or RAM it follows the jet all the way. #sym.arrow.r *CABIN PRESS lights above a cabin altitude of 27,000 ft.* *EQUIP HOT lights* with AIR SOURCE at OFF, or at RAM below 70 knots, once the avionics have power.
  - *#term("Not modelled").* The seat's safety lever, which the cockpit does not have, and SEAT NOT ARMED; the canopy's seal; the canopy's jettison and its loss in flight; the oxygen system (the levers move, LIQUID OXYGEN shows a fixed value); the cabin's pressure and temperature have no effect on the pilot; the avionics do not fail from heat.
]
