#import "/modern-iaf/manuals/text/en/f35i/ch2/src.typ": *
#let caps = (gear_panel: [The gear panel, left of the display.])

This section takes the #jet.name from the pattern to the end of the landing roll. The sim models it in part: the jet and its gear are modelled; the radio calls of the pattern are not. The F-35's approach speeds and landing technique are in its flight manual, which is not public: open. The rules here are the United States Air Force's for the F-35A; the technique is inferred.

=== Before you begin <landing-before>

- *The clearance.* A landing needs a clearance. How to ask for it is in the #other("game", "tower").
- *The fuel.* 2,500 lb at the start of the final approach is the normal figure (@cruise-bingo).

=== Before landing <landing-card>

#steps(
  "before_landing",
  captions: caps,
  seen: (
    gear_down_ldg: [Three green lights in about 3 seconds],
  ),
  figs: ("gear_panel",),
  notes: (landing_light_on: [At night, with the gear down and the generator on line, TAXI lights the taxi light and LAND the landing light: each lights the ground ahead. #key("Lights Master: navigation lights and strobe on / off (F-35I)") turns the navigation lights and the strobe on or off, on the generator.]),
)

The real pilot reports "gear down" to the controller before the jet crosses the runway's threshold#afi[paragraph 3.15.4.2]: the call makes the pilot look at the lights once more. #term("Not modelled").

=== The pattern <landing-pattern>

#idx("Overhead pattern")The overhead pattern: the jet flies over the runway in the landing direction, turns back in a level turn of 180° (the break) that starts over the touchdown point, flies past the runway the other way and turns onto final. It rolls its wings level on final about 1 mile out and 300 ft above the ground#afi[paragraphs 3.22.2 to 3.22.4]. In a closed pattern, flown after a go-around, the jet is below 250 kt on the downwind leg#afi[paragraph 3.26].

#in-sim[#idx("Overhead pattern, in the sim")The pattern the sim flies (inferred where the manual gives no figure): to the left; the initial 5 miles out on the runway heading, 1,500 ft above the field, 300 kt; the break over the touchdown zone, a level turn of 180° at 4 to 5 g; downwind 1 mile abeam, the gear down below 300 kt; the perch 800 ft above the field abeam the touchdown point; the final turn rolls out on final 1 mile out at 300 ft; the final at 13°, touching down within the first 1,000 ft. The training course teaches it: the #other("game", "course-pattern").]

At night the normal landing is a straight-in approach on instruments#afi[paragraph 3.18.7]. For instrument approaches the F-35A counts as a category E aircraft, the fastest group; a missed approach is flown at 250 kt#afi[paragraph 4.7.2].

#in-sim[The helmet shows the ILS lines of the runway (@navigation). #sym.arrow.r *Keep the flight path marker where the two lines cross.* Not modelled: the calls of the pattern.]

=== Touchdown and the landing roll <landing-roll>

+ *Aim* to touch down 500 to 1,000 ft past the runway's threshold, on its centre#afi[paragraphs 3.21.1 and 3.21.3].
+ *Touch down* on the main wheels with your feet off the brakes (inferred).
+ *Lower the nose* and hold #key("Wheel brakes (hold)") down to taxi speed. Steer with the rudder.

#idx("Landing distance")The real pilot works out the landing roll before the flight. If it is more than 80~% of the runway, the jet lands elsewhere#afi[paragraph 3.21.4]. The sim gives no such figure.

=== Going around <landing-go-around>

#idx("Go-around")A go-around is an approach given up: the runway is not clear, or the jet is not at its speed and on its path. It is always a correct choice. Set #key("Throttle military power"), climb, and raise the gear when the jet climbs. The real jet stays 500 ft below the pattern's height until it has passed the far end of the runway, so that it stays under the jets that fly the break#afi[paragraph 3.25.2].

=== If the landing goes wrong <landing-faults>

#table(
  columns: (1fr, 1fr, 1.2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([What you see], [Why], [What to do]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [No green gear lights.], [The handle is up.], [Press #key("Landing gear up / down").],
  [The jet floats along the runway.], [Too fast on final.], [Go around.],
  [The helmet shows nothing.], [The #ctl("HMD_MODE") is at OFF.], [Set it to AUTO or DAY.],
)
