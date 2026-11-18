#import "src.typ": *

=== Landing gear

The gear has three legs: a nose leg and two main legs in the fuselage. Hydraulic system B raises and lowers it#fm[page 1-104].

#row("GEAR_LEVER") is up or down. Three green lights, #row("lamp_gear_nose_0"), #row("lamp_gear_left_0") and #row("lamp_gear_right_0"), are on when that leg is down and locked#fm[page 1-106]. The red #row("lamp_gear_transit_0") in the handle is on while any leg is not where the handle asks#fm[page 1-104]: in transit, or failed.

The gear may be down or moving up to 300 knots or Mach 0.65#fm[figure 5-6, "LG Extended or in Transit"]. Above that the air load can damage the gear (inferred).

When system B fails, the #row("alt-gear") handle lowers the gear with stored air pressure#fm[page 1-106]. The DN LOCK REL button beside the gear handle unlocks the handle mechanically#fm[page 1-104].

The #row("lamp_to_ldg_config_0") warning light and a horn warn of an approach with the gear up: below 10,000 ft and 190 knots, in a descent of more than 250 ft a minute, with a leg not down and locked#fm[page 1-106]. #row("horn_silencer") stops the horn.

=== Brakes

The main wheels are braked with the toes of the rudder pedals. The BRAKES switch chooses one of two channels, CHAN 1 in normal use. #row("SW_PARKING_BRAKE") has three positions: PARKING BRAKE, ANTI-SKID and OFF. The anti-skid keeps a braked wheel from locking (inferred)#fm[pages 1-110, 1-111 and 1-117].

=== Nosewheel steering

The pedals steer the nosewheel up to 32° to each side once the steering is engaged with a button on the stick; the green #row("lamp_ar_nws_0") light shows it#fm[page 1-110].

=== Hook and drag chute

#row("SW_HOOK") lowers an arresting hook for a cable across the runway#fm[page 1-118]. The flight manual also describes a drag chute, fitted to some air forces' jets#fm[pages 1-117 and 1-118].

#in-sim[
  - *Gear.* #key("Landing gear up / down") moves the handle; the gear takes about 3 seconds. The three green lights and the handle's red light work as above. #sym.arrow.r *Above 300 knots or Mach 0.65 with the gear down, the gear is damaged.*
  - *Touchdown.* A sink rate above 10 ft a second damages the gear; above 13 ft a second, or with the gear moving, the jet is lost. A pitch of more than 15° at touchdown strikes the tail.
  - *Brakes.* #key("Wheel brakes") brakes both wheels on the ground. The speedbrakes have their own keys (@flight-controls). Anti-skid is always on.
  - *Steering.* The rudder pedals always steer the nosewheel on the ground, up to 32°; no button is needed. #sym.arrow.r *AR/NWS is on while the jet is on the ground.*
  - *TO/LDG CONFIG* works as above; the horn is silent.
  - *#term("Not modelled").* ALT GEAR, the parking brake, the brake channels and DN LOCK REL; the HOOK switch only lights the #row("lamp_caution_hook_0") caution; the jet has no drag chute.
]
