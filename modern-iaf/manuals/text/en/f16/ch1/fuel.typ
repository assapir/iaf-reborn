#import "src.typ": *

The real jet's fuel is in seven internal tanks: one in each wing, three in the fuselage (F1 and F2 forward, A1 aft) and two reservoirs, forward and aft, from which the engine is fed#fm[page 1-58]. The system keeps the forward and the aft fuel in step so that the jet stays in balance (inferred). The F-16D holds about 5,800 lb of fuel inside#fm[figure 1-22, page 1-70]#if sufa [; the #jet.short's two conformal tanks add about 3,000 lb#fm[page 1-7].] else [.]

External tanks hang under the inboard wing stations, 370 or 600 US gallons each, and under the centreline, 300 US gallons#fm[figure 1-22, page 1-70, and page 2-22].

=== Controls and indicators

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("SW_MASTER_FUEL")], [Opens the main fuel shut-off valve to the engine (MASTER, OFF)#fm[page 1-72].],
  [#row("SW_KNOB_ENG_FEED")], [Chooses which pumps and reservoirs feed the engine: OFF, NORM, AFT, FWD#fm[figure 1-23, page 1-73]. AFT and FWD correct a fuel imbalance (inferred).],
  [#row("SW_TANK_INERTING")], [Fills the tanks' empty space with Halon gas, which does not burn#fm[page 1-77].],
  [#row("SW_AIR_REFUEL")], [OPEN opens the refuelling door on the spine#fm[page 1-73].],
  [#row("anim110")], [Two pointers, for the forward and the aft fuel, and a counter with the total of all tanks#fm[figure 1-24, page 1-75].],
  [#row("FQS_sel-knob")], [Chooses what the two pointers show: TEST, NORM, RSVR (the reservoirs), INT WING, EXT WING, EXT CTR#fm[figure 1-24, pages 1-75 and 1-76].],
)

=== Low fuel and bingo

The #row("lamp_caution_fwd_fuel_low_0") and #row("lamp_caution_aft_fuel_low_0") caution lights come on when a reservoir runs low; in the F-16D below 250 lb in the forward one and 400 lb in the aft one#fm[page 1-74]. The reservoirs are the last fuel the engine gets, so the lights mean: land as soon as possible (inferred).

#term("Bingo fuel") is a quantity the pilot sets before the flight: the fuel needed to fly home and land with a reserve. When the total falls below it the voice says "Bingo" and the #term("HUD") shows FUEL#fm[page 1-74]. The action is to turn for home. Bingo is a plan, not a fault: a pilot may also set it higher, as a reminder to leave a fight (inferred).

#in-sim[
  - *Quantity.* The jet starts with #if sufa [8,850 lb inside, the conformal tanks included] else [5,800 lb inside]. A 370-gallon tank adds about 2,470 lb and a 600-gallon tank about 4,000 lb; each also adds weight and drag (@handling-stores).
  - *The indicator.* Each pointer of FUEL QTY shows half of the internal fuel; the counter shows the total with the external tanks.
  - *Bingo.* It starts at 1,500 lb and is set on the #term("DED") (@ufc). #sym.arrow.r *FUEL flashes in the HUD below it.* The voice says "Bingo" below 1,000 lb and again below 500 lb, whatever bingo is set to.
  - *Low fuel.* #sym.arrow.r *FWD FUEL LOW lights below 800 lb in total, AFT FUEL LOW below 500 lb.* With no fuel left the engine gives no thrust.
  - *Fuel to the engine.* #row("SW_MASTER_FUEL") at OFF, or #row("SW_KNOB_ENG_FEED") at OFF, cuts the fuel (#key("MASTER FUEL (MASTER / OFF)"), #key("ENG FEED: next position")). #sym.arrow.r *The engine flames out and winds down; the throttle's idle step lights nothing until the fuel feeds again.* AFT and FWD feed as NORM.
  - *#row("FQS_sel-knob")* (#key("FUEL QTY SEL: next position")). NORM, RSVR and INT WING: half the internal fuel on each pointer. EXT WING: half the external fuel on each pointer. EXT CTR: both pointers at zero. TEST: 2,000 lb on each pointer and 6,000 lb on the counter (inferred). The counter shows all the fuel at every other position. The knob starts at NORM.
  - *#term("Not modelled").* Separate tanks, their order of emptying and fuel imbalance; the reservoirs and the wing tanks apart (RSVR and INT WING show NORM's reading); TANK INERTING moves and does nothing; AIR REFUEL only switches the refuelling light on. A centreline tank is not carried.
]
