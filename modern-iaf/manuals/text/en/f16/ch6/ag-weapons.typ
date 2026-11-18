#import "src.typ": *

#layout-head

This section gives the cockpit procedure for each air-to-ground weapon. The sim releases a bomb only at 600 kt of calibrated airspeed or less and in a dive of 60° or less; outside them the release waits.

=== Unguided bombs: CCIP

CCIP, the continuously computed impact point, shows on the #term("HUD") where a bomb released now would hit#d34[section I, "CCIP pipper and inrange cue", page 1-173].

+ Arm (@stores).
+ Select the bomb: #key("Next air-to-ground weapon"). #then[The HUD shows the impact point, a dot in a circle, at the end of the bomb fall line, and CCIP in the mode window; the radar goes to AGR (@radar-ag).]
+ On the SMS format set SGL or PAIR, the spacing and the number of releases (@stores).
+ Dive at the target and fly the impact point onto it.
+ Hold #key("Release selected weapon") as the point reaches the target. #then[The bombs leave; the count goes down.]

*Delayed release.* When the impact point is below the HUD's view, the point stays at the HUD's lower edge. Put it on the target and hold the release button #then[a steering line and a cue show.] Keep holding and fly the flight path marker along the line #then[the bombs leave when the cue reaches the marker.]

#display("hud_ccip_delayed", [A delayed release with the button held: the steering line down the HUD through the point, and the cue, the short bar above the flight path marker, coming down onto it.], width: 90%)

=== Laser-guided bombs

+ Before the flight, load the targeting pod with the bombs (@stores).
+ Arm. Select the bomb.
+ Find the target with the pod and track it (@tgp).
+ #row("laser-arm-switch") to ARM.
+ Release as in CCIP. #then[The TGP format counts the time to impact.]
+ Hold the pod on the target until the impact. The laser fires by itself for the last seconds, or fire it with #key("Laser designator").

=== GPS-guided bombs

A GPS-guided bomb flies to coordinates. It takes them in one of two modes: PRE, a target planned before the flight, and VIS, a point designated in flight#dcs["JDAM SMS format", page 639]. #key("GPS bomb PRE / VIS") changes the mode, and #osb(2) on the SMS format opens the list of modes (@stores); #key("GPS bomb next PRE target") steps the planned targets.

+ Arm. Select the bomb. #then[The HUD's mode window shows PRE or VIS.]
+ In VIS, designate the point with the ground map (@radar-ag).
+ #then[The HUD shows a box on the target, a steering line through it, and on the right a range scale with a bracket and a caret.] Fly the flight path marker onto the steering line.
+ Under the scale a time counts down, then *IN RNG* shows. Hold #key("Release selected weapon"). #then[The bomb leaves; the HUD shows its time to impact.]

#display("hud_gps", [A GPS-guided bomb in PRE with a point designated: the box on the line, the range scale on the right with its bracket and caret, and the time under it (TMR).], width: 90%)
#display("hud_gps_inrng", [The same bomb inside its range: the bracket round the caret and IN RNG under the scale.], width: 90%)

The WPN format (@mfd) shows the selected GPS-guided bomb's status, and #osb(1) there also changes PRE and VIS.

=== The gun: strafing

+ Arm. Select the gun in air-to-ground. #then[The HUD shows the strafing dot with the slant range; the SMS format reads STRF.]
+ Dive, put the dot on the target, hold #key("Gun trigger").

#in-sim[
  - A bomb in PRE takes the route's target steerpoint, if it has one.
  - The layout of the GPS-guided bomb's HUD symbols is inferred from simulators' manuals.
  - #term("Not modelled"): a PRE target set before the flight; the release modes CCRP, DTOS, LADD and MAN; fuze and arming settings and the LOW cue; a laser from another aircraft or from the ground.
]
