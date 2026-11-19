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

=== The release modes

A bomb has five release modes; #osb(2) on the SMS format's air-to-ground page opens their list, and a press on one picks it#mlu["Air-to-Ground Page", figures 1-38 and 1-39]. #key("A-G release submode: next (CCIP, DTOS, CCRP)") steps CCIP, DTOS and CCRP, as the stick's missile step switch does in the real jet. The HUD's mode window names the mode. Each bomb keeps its mode in each of its two profiles (@stores).

- *CCIP:* you put the impact point on the target and release (above).
- *CCRP*, the continuously computed release point: you pick the target before the attack; the jet works out where to release and releases the bomb by itself.
- *DTOS*, dive toss: you mark the target in a dive; then the release goes by itself, as in CCRP.
- *LADD*, low-altitude drogue delivery: CCRP from a low run-in with a pull-up into a climb; the bomb is thrown up and forward.
- *MAN*, manual: a fixed sight on the HUD; nothing is worked out.

=== CCRP

+ Arm. Select the bomb. Pick CCRP.
+ Give the jet the target, one of: designate it with the ground map (@radar-ag); track it with the targeting pod (@tgp); or make the target steerpoint the current steerpoint. #then[A box on the target, the TD box, and a vertical steering line through it; the timer row counts down to the release.]
+ Fly the flight path marker onto the steering line, wings level#mlu["Continuously Computed Release Point", pages 175-177].
+ Hold #key("Release selected weapon"). #then[About 10 seconds before the release a short line, the solution cue, comes down the steering line. The bomb leaves by itself when the cue reaches the marker.]
+ Keep holding until the bomb is gone. Release the key early and nothing leaves.

To throw the bomb from farther out, pull up when the pull-up cues meet the marker, as in LADD below; the release still waits for the cue.

=== DTOS

+ Arm. Select the bomb. Pick DTOS. #then[The TD box sits on the flight path marker; the HUD is the sensor of interest.]
+ Dive so that the box is on the target.
+ Press and hold #key("Release selected weapon"), or press #key("Radar: bug / lock (TMS up)"). #then[The box stays on that ground point#mlu["Dive Toss", page 173]; the steering line and the time to release show.]
+ Keep the release key held. Keep diving, or pull out: the bomb leaves by itself when the cue reaches the marker, often during the pull-out.
+ To mark another point, press #key("Radar: drop bug / lock (TMS down)") #then[the box goes back to the marker.]

=== LADD

+ Arm. Select the bomb. Pick LADD. Give the jet the target as in CCRP.
+ Fly low and fast toward the target on the steering line. The guide plans the run-in at 200 ft above the target and 550 knots#mlu["Low Altitude Drogue Delivery", pages 178-180]. #then[The timer row counts down to the pull-up.]
+ Hold #key("Release selected weapon").
+ 10 seconds before the pull-up a short line shows above the marker and a bar below it; both move toward the marker.
+ When they meet the marker, pull up at about 4 g. #then[A bar shows where a 45° climb puts the marker; the solution cue comes down the steering line.]
+ Hold the marker on the bar. The bomb leaves by itself in the climb. Then turn away.

=== MAN

The manual mode gives a fixed sight, the reticle: a dot in a dashed ring inside a larger ring, lowered below the gun cross by the RET DEPR wheel#mlu["Manual Weapon Delivery", page 191]. The HUD shows how far it is lowered, in milliradians.

+ Arm. Select the bomb. Pick MAN.
+ Set #row("depr_ret") with #key("RET DEPR wheel: reticle down") and #key("RET DEPR wheel: reticle up"), and #row("depr-ret-switch") to PRI with #key("HUD DEPR RET (STBY / PRI / OFF)"). #then[The reticle shows.]
+ Fly the planned dive, speed and height. Release with #key("Release selected weapon") when the reticle's dot is on the target. #then[The bomb leaves at once.]

To find the setting, fly the same pass in CCIP with DEPR RET at STBY and turn the wheel until the reticle's dot sits on the impact point; the setting is then the one for that dive, speed and height.

=== Fuzes and the arming delay

A bomb's fuze arms some seconds after the release, the arming delay. A bomb that hits sooner does not go off#dcs["Unguided bombs CCIP attack", page 625].

- #osb(18) on the SMS format, or #key("Bomb fuze: next (NSTL / NOSE / TAIL)"), steps the fuze: NSTL (nose and tail), NOSE, TAIL. On the sim's bombs all three act the same.
- #osb(17), or #key("Bomb arming delay: next"), steps the arming delay; the page shows it as AD 4.80SEC, the delay at the start#mlu["Air-to-Ground Page", figure 1-38].
- *LOW* beside the flight path marker means a bomb released now would hit before it arms. Climb, or release higher. The pull-up cue under the marker also rises for this height#d34[section I, "Pullup anticipation and breakaway cue", page 1-173].

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

*PRE targets.* Each station, and each bomb of a two-bomb GBU-38 rack, takes its own PRE target before the flight (#other("game", "briefing")). A bomb with no target of its own takes its station's; a station with none takes the route's target steerpoint. In PRE the SMS's air-to-ground page shows, over the target lines, the station of the bomb that leaves next and *PP 1/4*: which of the planned targets it aims at, of how many. Under them stand the target's name (TGT 2, STPT 1, PT for a point of the map) and its coordinates, and at the bottom the target of the next bomb to leave. #key("GPS bomb next PRE target") steps the bomb from its own target to the other planned targets and the steerpoints.

=== The gun: strafing

+ Arm. Select the gun in air-to-ground. #then[The HUD shows the strafing dot with the slant range; the SMS format reads STRF.]
+ Dive, put the dot on the target, hold #key("Gun trigger").

#in-sim[
  - A bomb in PRE takes the target picked for it or its station before the flight, else the route's target steerpoint; on the weapons range that is the steerpoint on the targets.
  - The SMS's PRE lines (the station, PP, the target's name and place, the next bomb) are laid out by us; the real page's layout was not found.
  - The layout of the GPS-guided bomb's HUD symbols is inferred from simulators' manuals.
  - The release modes' cue scales, the arming delay's steps and the reticle's readout place are inferred; the pull-up time is worked out from the bomb's own fall.
  - #term("Not modelled"): the CCRP and LADD control pages (the release angle and the pull-up range typed in); the fuzes' different effects; a laser from another aircraft or from the ground.
]
