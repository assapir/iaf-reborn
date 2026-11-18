#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *
#let caps = (gear: [The gear panel, left of the front panel.])
#let base-speed = if sufa { 137 } else { 138 }

This section takes the #jet.name from the pattern to the end of the landing roll. The sim models it in part: the jet, its speeds and its gear are modelled; the radio calls of the pattern are not.

=== Before you begin <landing-before>

- *The clearance.* A landing needs a clearance. How to ask for it is in the #other("game", "tower").
- *The fuel.* Check it before the pattern; a second approach costs fuel.

=== The final approach speed <landing-speed>

#idx("Final approach speed")#idx("Angle of attack, on speed")The F-16 is not flown down final at a fixed speed but at a fixed angle of attack: 13°, or 11° for a faster and flatter approach#fm[section II, "Normal landing", page 2-23]. At that angle the wing gives the same lift margin at any weight; the speed that goes with it rises with the weight. A higher angle than 13° brings the tail close to the runway at touchdown; a lower one lands fast and long.

The speed is worked out before the pattern, as a cross-check of the angle: #base-speed kt, plus 4 kt for each 1,000 lb of fuel and stores on board, at 13°; 8 kt more at 11°#fm[figure 2-3 "Normal landing pattern", its notes, page 2-25: 137 kt for the two-seat jet with the Pratt & Whitney engine, 138 kt with the General Electric engine, at the basic weight with full ammunition; the real speed may differ by 5 kt with the centre of gravity. For the #jet.short's own weight and engine the figure is inferred]. With 2,000 lb of fuel left and no stores that is about #(base-speed + 8) kt.

You recognise the angle in three places:

- #row("lamp_aoa_on_speed_0"): the middle light of the indexer, alone, is 13°. #row("lamp_aoa_slow_0") means the angle is too high (the jet is slow): lower the nose or add power. #row("lamp_aoa_fast_0") means it is too low (the jet is fast).
- #row("AOA_tape").
- The bracket beside the flight path marker on the #term("HUD"), shown with the gear down (@hud).

=== Before landing <landing-card>

#steps(
  "before_landing",
  captions: caps,
  seen: (
    gear_down_ldg: [Three green lights in about 3 seconds; the handle's red light out],
  ),
  figs: ("gear",),
  notes: (
    approach_speed: [The speed is in @landing-speed.],
    gear_down_ldg: [Lower the gear below 300 kt.],
  ),
)

#idx("Landing gear, handle")#caution[In the real jet the gear handle can look down while it rests in a middle position. The gear may then come down and show three green, but the handle is not locked and the gear can retract later, in the air or on the ground. The pilot pushes the handle down by hand until it stops#fm[section II, "Normal landing", the first caution, page 2-23]. The sim's handle has two positions only.]

=== The pattern <landing-pattern>

#idx("Overhead pattern")The normal pattern is the overhead pattern: the jet flies over the runway in the landing direction, turns back in a level turn (the break), flies past the runway the other way (downwind) and turns again onto final#fm[section II, "Normal landing", page 2-23, and figure 2-3, page 2-25].

+ *Initial.* Fly along the runway at 300 kt.
+ *The break.* Turn level through 180°. Throttle back; speedbrakes as needed.
+ *Downwind.* Below 300 kt, lower the gear (the card's line).
+ *Base turn.* Check the gear down again. Slow to the final approach speed, so that the jet rolls out on final at 13° or 11°.
+ *Final.* Speedbrakes open. Hold the angle of attack with the stick and the glide path with the throttle (inferred: the manual gives the values, not the technique).

A straight-in approach is the same from step 4 on. On instruments it is flown along the ILS, whose two lines the HUD shows once the runway's frequency is set on the T-ILS page (@navigation).

#in-sim[The speedbrakes open while #key("Speedbrakes open (hold)") is held and stay where it is let go; #key("Speedbrakes close") closes them. #sym.arrow.r *The speedbrakes stop at 43° with the gear down*, so that they clear the runway. #term("Not modelled"): the calls of the pattern (initial, base, final, the go-around call).]

=== Touchdown and the landing roll <landing-roll>

+ *The flare.* Close to the ground the jet sinks a little less by itself. Ease the throttle back and the stick back to make the touchdown as soft as you can, without passing 13°#fm[section II, "Normal landing", page 2-23].
+ *Touchdown,* on the main wheels, with your feet off the brakes.
+ *Aerodynamic braking.* Keep the nose up at 13° and let the air slow the jet, down to about 100 kt#fm[section II, "Normal landing", page 2-24: two-point aerodynamic braking until about 100 kt; the most at 13°, much less under 11°].
+ *Nose down.* Fly the nosewheel onto the runway.
+ *Brakes.* Speedbrakes fully open, the stick fully back, then the wheel brakes, firmly, down to taxi speed#fm[section II, "Normal landing", page 2-26].

#idx("Aerodynamic braking")Aerodynamic braking uses the whole jet as a brake: with the nose held up the wing and the body meet the air at a high angle, and their drag slows the jet with no wear on the wheel brakes. It works best at 13° and little below 11°. Above 15° of pitch the nozzle, the speedbrakes and the fins under the tail can touch the runway#fm[section II, "Normal landing", the second caution of page 2-24].

#idx("Brakes, at touchdown")#warning[Do not touch down with the brake pedals pressed. The real jet releases the brakes at touchdown by itself, but if that protection fails the wheels are locked when they meet the runway and the main tyres burst#fm[section II, "Normal landing", the first warning of the right column, page 2-24]. The sim's tyres do not burst.]

#idx("Hot brakes")#caution[Brake firmly, once. Light braking held for long heats the brakes more than a firm stop does: the brakes stay on longer#fm[section II, "Normal landing", page 2-26: "Using less than moderate braking increases the likelihood of a hot brake"]. Hot brakes can set the wheels on fire after the jet has stopped; the real pilot recognises them by a long or heavy stop, reports them and parks away from other aircraft, without the parking brake (@emergency-landing). Not modelled.]

The real jet has a drag chute for short or wet runways, opened right after touchdown between 170 kt and 90 kt#fm[section II, "Normal landing", the cautions of page 2-24]. Not modelled: the sim's jets carry none.

#in-sim[#key("Wheel brakes") brakes the wheels on the ground; the speedbrakes stay as their keys left them. #sym.arrow.r *The jet slows; the nose drops by itself as the speed falls.* Steer with the rudder.]

=== Crosswind <landing-crosswind>

With the wind across the runway, fly final with the wings level and the nose turned into the wind (a crab), and keep it so through the touchdown#fm[section II, "Crosswind landing", page 2-26]. After touchdown hold the track with the rudder and keep the wing on the wind's side down with the stick. The lower the speed, the more rudder it takes.

=== Going around <landing-go-around>

#idx("Go-around")A go-around is an approach given up: the runway is not clear, or the jet is not at its speed and on its path. It is always a correct choice. Set #key("Throttle military power"), close the speedbrakes with #key("Speedbrakes close"), climb, and raise the gear when the jet climbs. A touch-and-go is the same from the runway: after touchdown hold the landing attitude, add power, close the speedbrakes and take off#fm[section II, "Touch-and-go landing", page 2-27].

=== If the landing goes wrong <landing-faults>

#table(
  columns: (1fr, 1fr, 1.2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([What you see], [Why], [What to do]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [No green gear lights.], [The handle is up, or the speed is too high.], [Slow below 300 kt and press #key("Landing gear up / down").],
  [The top light of the indexer.], [The jet is slow: the angle of attack is above 13°.], [Add power; lower the nose a little.],
  [The jet floats along the runway.], [Too fast on final.], [Go around.],
  [No ILS lines on the HUD.], [The runway's frequency is not set.], [Set it on the T-ILS page (#key("ICP 1 (T-ILS)")).],
)
