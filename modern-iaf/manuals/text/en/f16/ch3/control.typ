#import "src.typ": *

=== Departure and deep stall <emergency-deep-stall>
#state("part")

#idx("Deep stall, recovery")A departure is the jet leaving controlled flight: the nose goes where the stick did not send it. Most departures end by themselves when the controls are let go. One that does not ends in a #term("deep stall") (@flight-controls) or, rarely, a spin. It matters because the jet loses height for as long as it lasts (inferred).

*You recognise a deep stall by* the *angle of attack fixed at the end of its scale* (32° upright with positive g, −5° inverted with negative g), *low airspeed* and a nose that swings up and down without answering the stick#fm[section III, "Out-of-control recovery", page 3-130]. A spin shows as a steady turn of the nose around the horizon; the flight controls work against it by themselves, and it must be left to slow, which can take 20 to 30 seconds, before anything else works#fm[section III, "Out-of-control recovery", page 3-129].

+ *Controls: release.* Hands and feet off. #if sufa [In afterburner, throttle back to military power; otherwise leave the throttle. ] else [Throttle to idle (the step of the manual's General Electric engine, the F110-GE-129; inferred for the #jet.short's F110-GE-100). ]If the jet recovers, fly out of the dive.
+ *Still out of control:* #row("SW_MPO") to OVRD, and hold it there to the end. In normal flight this switch is never touched; here it gives the stick the tail directly.
+ *Rock the nose, in step with it.* When the nose rises, pull fully back and hold; when it stops and starts down, push fully forward. Upright with no nose movement: pull first, and push after 3 to 4 seconds. Inverted with no movement: push first. Move the stick sharply and fully; small or fast, out-of-step movements do nothing.
+ *When the nose stays down* and the angle of attack reads normally, the jet is flying. Above 200 kt release the switch, keep the roll and the rudder neutral, and pull out of the dive with military power or afterburner#fm[section III, "Out-of-control recovery", pages 3-129 and 3-130].

#warning[Holding the switch at OVRD without moving the stick streamlines the tail and prevents the recovery; releasing it in the middle cancels the swing you have built#fm[section III, "Out-of-control recovery", page 3-129]. If the jet is not recovering by 6,000 ft above the ground, eject (@ejection): the dive after a recovery can need more than 6,000 ft#fm[section III, "Out-of-control recovery", the warnings, page 3-130].]

#in-sim[The deep stall and its recovery are modelled: the jet stays at about 59° angle of attack with the hands off, and comes out when the nose is rocked in step with MANUAL PITCH held at OVRD. *A tone sounds above about 27° angle of attack.* #term("Not modelled"): the inverted deep stall and the spin as the real jet flies them, and the engine's stall in a departure.]
