#import "../ch4/src.typ": *

#block-head

=== Take-off

- *Steering.* The nose-wheel steering holds the jet straight until the rudder works, at about 70 kt#fm[section II, the take-off figure, page 2-21].
- *Rotation.* Start the pull about 10 kt below the computed take-off speed without afterburner, 15 kt with it, and set 8° to 12° of pitch. An earlier pull can over-rotate the jet, make it skip or wallow, and lengthens the roll#fm[section II, "Takeoff", page 2-21].
- *Speeds.* The take-off speed depends on the weight; the charts are in the performance supplement, which is not public: open.
- *After lift-off.* The gear and the trailing-edge flaps come up together when the handle is raised, and the computer changes to its cruise gains (@handling-general). Until the wheels stop spinning the computer adds no rudder to a roll; a jet held with roll trim against a heavy wing yaws a little at that moment#fm[section VI, "Asymmetric loadings", page 6-7].

=== Approach and landing

The approach is flown on angle of attack, not on a speed (@landing-speed). The manual gives two ways#fm[section VI, "Landing configuration", page 6-4]:

- *11°.* The stick holds the glide path and the throttle the speed. The nose is lower, the view and the pitch control are better, and the jet floats 800 to 1,200 ft from the flare to the touchdown.
- *13°.* The throttle holds the glide path and the stick the angle of attack. The touchdown point is more exact and the jet floats 500 to 700 ft, but the flare is harder: there is little left to pull, and the speedbrakes can scrape.

In both:

- Open the speedbrakes. Closed, the light wing floats in the ground effect#fm[section VI, "Landing configuration", page 6-4].
- Near the ground, stop a sink with thrust, not with the stick: more back stick there can strike the tail. Do not cut the thrust early or by much#fm[section VI, "Landing configuration", page 6-4].
- Keep the stick movements small; the jet answers the same at low speed as at high#fm[section VI, "Landing configuration", page 6-4].
- Wake turbulence is a hazard to a light wing near the ground. A large roll input there lifts a flaperon, loses lift and can bring a tail surface to the runway; go around early instead#fm[section VI, "Landing configuration", page 6-4].

After touchdown the nose is held up at 13° to brake on the air, and flown down at about 100 kt (@landing-roll)#fm[section II, "Normal landing", page 2-24].

=== Crosswind

Fly a crab with the wings level through the touchdown. At touchdown the computer stops adding rudder, so the pilot holds the track with the rudder and keeps the upwind wing down with the stick. Too much stick into the wind weakens the directional control. Braking on the air with the nose up is harder in a crosswind#fm[section II, "Crosswind landing", pages 2-26 and 2-27]. The crosswind limits are open (@limits-weight).

=== Flight with the gear down

With the handle down the flaps stay down too, and the fuel flow is much higher. When the gear must stay down for a long flight and the handle can be raised, the flaps come up, and the best speed is 230 to 250 kt#fm[section VI, "Flight with LG down", pages 6-3 and 6-4].

#in-sim[
  - *Take-off.* The pedals steer the nose wheel. At the weight of an air-to-air load the jet lifts off near 180 kt, 6 to 12 kt after the pull starts.
  - *Ground effect.* Modelled: near the runway the lift grows by a few per cent and the jet floats.
  - *Approach.* The angle-of-attack approach works as above: at 13° the speed follows the weight (@landing-speed). The speedbrakes open to 43° with the gear down.
  - *Crosswind and gusts.* The wind moves the jet and a light turbulence comes with it. The pilot adds the rudder in a roll on the runway, as in the real jet.
  - #term("Not modelled"): wake turbulence, the yaw when the wheels stop spinning after lift-off, a tail surface touching the runway.
]
