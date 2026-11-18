#import "src.typ": *

=== Landing gear

The gear has a nose leg and two main legs. #row("gear_handle") is up or down; the #row("lamp_gear_transit_0") is on while the gear moves. #row("ALT_GEAR"), under its #row("ALT_GEAR_GUARD"), lowers the gear when the normal way fails. The gear's state is also on the display. The details of the real system are not public: this is inferred from the cockpit.

=== Brakes and steering

The toes of the rudder pedals brake the main wheels, and the pedals steer the nosewheel on the ground (inferred). #row("PARK_BRAKE") holds the jet when it is parked.

=== Hook

The F-35A has an arresting hook for emergencies: it catches a cable across the runway when the jet cannot stop by itself#footnote[The Aviationist, "The F-35A has started tailhook testing at Edwards AFB", 20 May 2016, #link("https://theaviationist.com/2016/05/20/the-f-35a-has-started-tailhook-testing-at-edwards-afb/"). #checked]. #row("HOOK") lowers it.

#in-sim[
  - *Gear.* #key("Landing gear up / down") moves the handle; the gear takes about 3 seconds. ALT GEAR lowers the gear. #sym.arrow.r *Above 300 knots or Mach 0.65 with the gear down, the gear is damaged.* The real jet's limit is not public; the sim uses this one.
  - *Touchdown.* A sink rate above 10 ft a second damages the gear; above 13 ft a second, or with the gear moving, the jet is lost.
  - *Brakes.* #key("Wheel brakes") brakes both wheels on the ground; in the air the same key is the speedbrake (@flight-controls).
  - *Steering.* The rudder pedals steer the nosewheel on the ground.
  - *#term("Not modelled").* The parking brake and the hook: both switches move and do nothing. The jet has no drag chute.
]
