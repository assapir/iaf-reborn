#import "src.typ": *

#layout-head

This section gives the cockpit procedure for each air-to-air weapon. It gives no weapon performance.

=== Short-range missile

+ Arm (@stores).
+ Select the missile: #key("Next air-to-air weapon"), or #key("Dogfight (DGFT)"). #then[The #term("HUD") shows the missile's circle; the SMS format shows the missile's page with RDY.]
+ Put the target inside the circle. #then[The missile's tone rises and a diamond shows on the target.] The sim asks for no uncage press.
+ Hold #key("Release selected weapon"). #then[The missile leaves and the station's count goes down.]

With a radar lock (@radar-aa) the HUD also shows the box on the target and the range scale. A missile that can be aimed off the nose follows the helmet's cross: look at the target instead of pointing the nose (@hud).

=== Radar missile

+ Arm.
+ Select the missile: #key("Next air-to-air weapon"), or #key("Missile override (MSL OVRD)").
+ Bug or lock the target (@radar-aa). #then[The HUD shows the box on the target, a steering circle with a dot, and on the right a range scale with a bracket and the target's caret.]
+ Steer the dot into the circle.
+ When the caret is inside the bracket, hold #key("Release selected weapon"). #then[The missile leaves.]

#display("hud_lock", [The HUD and the #term("FCR") with a target locked: the box on the target.], width: 90%)

=== The gun

+ Arm.
+ Select the gun: #key("Dogfight (DGFT)"), or station select on the SMS format. #then[The HUD shows the funnel; the SMS format reads EEGS.]
+ Fly the target between the funnel's two lines so that its wing tips touch them. With a radar lock #then[an aiming dot shows]: put the dot on the target.
+ Hold #key("Gun trigger"). #then[The gun fires and the rounds count goes down.]

#in-sim[
  - With the gear handle down the gun does not fire.
  - #term("Not modelled"): the missile's cage and uncage and its seeker's scan options; every cue after a missile's launch.
]
