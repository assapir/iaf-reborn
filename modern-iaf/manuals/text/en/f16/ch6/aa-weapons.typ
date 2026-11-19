#import "src.typ": *

#layout-head

This section gives the cockpit procedure for each air-to-air weapon. It gives no weapon performance.

=== Short-range missile

The missile's _seeker_ is the heat-sensing head in its nose. It starts _caged_: it looks along one line, toward the radar's locked target, else where the helmet looks, else straight ahead, and hears only a target on that line. _Uncaged_, it follows the target it heard#dcs[pages 571–574].

+ Arm (@stores).
+ Select the missile: #key("Next air-to-air weapon"), or #key("Dogfight (DGFT)"). #then[The #term("HUD") shows the missile's circle and a small diamond; the SMS format shows the missile's page with RDY.]
+ Lock the target with the radar (@radar-aa), or put it inside the circle. #then[The missile's tone rises: the seeker hears the target.]
+ Press #key("Missile seeker: UNCAGE / CAGE"). #then[The seeker follows the target: the diamond sits on it and grows.] A second press cages it again. When the target leaves the seeker's reach, the seeker cages by itself.
+ Wait for SHOOT on the HUD, then hold #key("Release selected weapon"). #then[The missile leaves and the station's count goes down.]

The SMS format's AAM page shows SPOT or SCAN by OSB 2: in SPOT the caged seeker hears a target only close to its line, in SCAN a little wider. A press on OSB 2, or #key("Missile seeker: SPOT / SCAN"), changes it.

With a radar lock the HUD also shows the box on the target and the range scale. A missile that can be aimed off the nose follows the helmet's cross: aim it by looking at the target (@hud).

=== Radar missile

+ Arm.
+ Select the missile: #key("Next air-to-air weapon"), or #key("Missile override (MSL OVRD)").
+ Bug or lock the target (@radar-aa). #then[The HUD shows the box on the target, a steering circle with a dot, and on the right a range scale with a bracket and the target's caret.]
+ Steer the dot into the circle.
+ When the caret is inside the bracket, hold #key("Release selected weapon"). #then[The missile leaves.]

=== After the launch

The HUD's right column (the sim's place) shows how long the missile still flies#dcs[pages 574 and 596–598]: _A_ and the seconds until a radar missile's own radar comes on, then _T_ and the seconds until it reaches the target. A short-range missile shows only _T_. With several missiles in the air the HUD shows the one with the longest time. The #term("FCR") shows the same time at its top right. On the FCR the target carries a short tail from the launch, which flashes once the missile's radar is on, and an X for its last 8 seconds.

Keep the lock until _A_ runs out: until then a radar missile steers on your radar's track, sent over its data link. If the lock drops, it flies on to where the target would be and turns its own radar on there; a target that turned away by then is lost. A missile whose seeker loses the target flies on unguided.

#display("hud_lock", [The HUD and the #term("FCR") with a target locked: the box on the target.], width: 90%)

=== The gun

+ Arm.
+ Select the gun: #key("Dogfight (DGFT)"), or station select on the SMS format. #then[The HUD shows the funnel; the SMS format reads EEGS.]
+ Fly the target between the funnel's two lines so that its wing tips touch them. With a radar lock #then[an aiming dot shows]: put the dot on the target.
+ Hold #key("Gun trigger"). #then[The gun fires and the rounds count goes down.]

#display("hud_gun_lock", [The gun with a target locked, the jet in a turn: the funnel, the target in it under the long bar across it, and the range arc beside the target.], width: 90%)

#in-sim[
  - With the gear handle down the gun does not fire.
  - #term("Not modelled"): the time of flight before the launch, and the target's range at those moments; the seeker's SLAVE and BORE options and its cooling.
]
