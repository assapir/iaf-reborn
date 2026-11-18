#import "src.typ": *

The real jet's fuel is in seven internal tanks: one in each wing, three in the fuselage (F1 and F2 forward, A1 aft) and two reservoirs, forward and aft, from which the engine is fed#fm[page 1-58]. The tanks form two systems: the forward one (the right wing tank, F1, F2 and the forward reservoir) and the aft one (the left wing tank, A1 and the aft reservoir); each external wing tank empties into its own wing tank, the wing tanks into the fuselage tanks and these into the reservoirs#fm[page 1-61]. The fuel flow proportioner takes the same amount from each reservoir, which keeps the jet in balance#fm[page 1-61]. The F-16D holds about 5,800 lb of fuel inside#fm[figure 1-22, page 1-70]#if sufa [; the #jet.short's two conformal tanks add about 3,000 lb#fm[page 1-7].] else [.]

External tanks hang under the inboard wing stations, 370 or 600 US gallons each, and under the centreline, 300 US gallons#fm[figure 1-22, page 1-70, and page 2-22].

=== Controls and indicators

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("SW_MASTER_FUEL")], [Opens the main fuel shut-off valve to the engine (MASTER, OFF)#fm[page 1-72].],
  [#row("SW_KNOB_ENG_FEED")], [Chooses which pumps feed the engine: OFF, NORM, AFT, FWD#fm[figure 1-23, page 1-73]. NORM: all of them. AFT or FWD: that system's pumps, which feed the engine and pump fuel into the other system, to correct an imbalance#fm[section III, "Fuel imbalance", pages 3-119 and 3-120]. OFF: no electric pump; the proportioner still feeds the engine#fm[figure 1-23, page 1-73].],
  [#row("SW_TANK_INERTING")], [Fills the tanks' empty space with Halon gas, which does not burn#fm[page 1-77].],
  [#row("SW_AIR_REFUEL")], [OPEN opens the refuelling door on the spine#fm[page 1-73].],
  [#row("anim110")], [Two pointers, for the forward and the aft fuel, and a counter with the total of all tanks#fm[figure 1-24, page 1-75].],
  [#row("FQS_sel-knob")], [Chooses what the two pointers show: TEST, NORM (the aft and the forward fuselage fuel), RSVR (the reservoirs), INT WING, EXT WING, EXT CTR (the centreline tank)#fm[figure 1-24, pages 1-75 and 1-76]. Out of NORM the automatic forward fuel transfer stops#fm[page 1-61].],
)

=== Low fuel and bingo

The #row("lamp_caution_fwd_fuel_low_0") and #row("lamp_caution_aft_fuel_low_0") caution lights come on when a reservoir runs low; in the F-16D below 250 lb in the forward one and 400 lb in the aft one#fm[page 1-74]. The reservoirs are the last fuel the engine gets, so the lights mean: land as soon as possible (inferred).

#term("Bingo fuel") is a quantity the pilot sets before the flight: the fuel needed to fly home and land with a reserve. When the total falls below it the voice says "Bingo" and the #term("HUD") shows FUEL#fm[page 1-74]. The action is to turn for home. Bingo is a plan, not a fault: a pilot may also set it higher, as a reminder to leave a fight (inferred).

#in-sim[
  - *Quantity.* The jet starts with #if sufa [8,850 lb inside, the conformal tanks included] else [5,800 lb inside]. A 370-gallon tank adds about 2,470 lb and a 600-gallon tank about 4,000 lb; each also adds weight and drag (@handling-stores).
  - *The tanks.* Each system's tanks empty from the far end: the external tank, the wing tank, the fuselage tanks, the reservoir last. A full #jet.short holds 2,810 lb in the aft fuselage tanks, 1,890 lb in the forward ones (480 lb in each reservoir) and #if sufa [2,075] else [550] lb in each wing tank#if sufa [ with its conformal tank]. Each external tank holds half of the external fuel. With the selector at NORM the automatic forward transfer keeps the aft fuselage fuel no more than 900 lb above the forward.
  - *Bingo.* It starts at 1,500 lb and is set on the #term("DED") (@ufc). The real jet compares it with the fuselage fuel at NORM; the sim compares it with the total, which is the same here: the fuselage tanks empty last. #sym.arrow.r *FUEL flashes in the HUD below it.* The voice says "Bingo" below 1,000 lb and again below 500 lb, whatever bingo is set to.
  - *Low fuel.* #sym.arrow.r *FWD FUEL LOW lights below 250 lb in the forward reservoir, AFT FUEL LOW below 400 lb in the aft one.* With no fuel left the engine gives no thrust.
  - *Fuel to the engine.* #row("SW_MASTER_FUEL") at OFF cuts the fuel (#key("MASTER FUEL (MASTER / OFF)")). #sym.arrow.r *The engine flames out and winds down; the throttle's idle step lights nothing until the fuel feeds again.*
  - *#row("SW_KNOB_ENG_FEED")* (#key("ENG FEED: next position")). #sym.arrow.r *AFT or FWD: the engine is fed from that system, and about 4,300 lb an hour moves into the other system's fuselage tanks (inferred from the timings of page 3-136); the pointers at NORM show it. OFF and NORM: both systems feed alike.*
  - *#row("FQS_sel-knob")* (#key("FUEL QTY SEL: next position")). #sym.arrow.r *NORM: the aft fuselage fuel on AL, the forward on FR. RSVR: the reservoirs. INT WING: the wing tanks. EXT WING: the external tanks. EXT CTR: both pointers at zero. TEST: 2,000 lb on each pointer, 6,000 lb on the counter and both FUEL LOW lights on.* The counter shows all the fuel at every other position. The knob starts at NORM.
  - *#term("Not modelled").* The centre of gravity's move with the fuel; the AL pointer's red imbalance mark; external fuel that fails to transfer, with its TRP FUEL warning; TANK INERTING moves and does nothing; AIR REFUEL only switches the refuelling light on; EXT FUEL TRANS moves only (no centreline tank is carried, so its order changes nothing).
]
