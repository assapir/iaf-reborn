#import "src.typ": *

The #jet.short has no head-up display. The #term("HMD") draws the flight and weapon symbols in the helmet's visor, in green. Looking forward you see a set of symbols that stays with the jet's nose, the virtual head-up display. Looking aside you see a smaller set that stays with your head#sld. The real symbols are public only through the maker's slides and flight-test videos. The places of the symbols below are inferred.

=== The controls <hmd-controls>

- #row("HMD_MODE") turns the helmet's display on and sets it for the night or the day.
- #row("HMD_BRT") steps its brightness. Its key is #key("Step HUD brightness").

#in-sim[OFF: the helmet shows nothing. NIGHT, AUTO and DAY show the same picture: their difference is #term("Not modelled"). The real helmet also shows the picture of the cameras round the jet, by day and by night#das-wiki: #nis.]

=== Looking forward: the virtual head-up display <hmd-forward>

#display("helmet_lock", [The helmet's display looking forward, with a radar lock: the designator's X sits on the target, ahead on the horizon.], width: 100%)

- *Top:* the heading tape with the heading in a box. A caret under the tape marks the bearing of the steerpoint (@navigation).
- *Left:* the airspeed, a number in a box. Under it the ground speed, the Mach number, the g and the angle of attack.
- *Right:* the altitude, a number in a box. Under it the vertical speed and the height above the ground from the radar altimeter, led by an R.
- *Centre:* the waterline mark of the jet's nose; the horizon line with a gap at its centre; the pitch ladder, its climb bars solid and its dive bars dashed; the flight path marker, which shows where the jet is going.
- *Bottom:* the bank scale.
- *Lower left:* the master mode, the selected weapon with its count, and ARM while the master arm is on.
- *Lower right:* the steerpoint's number, bearing and distance, and the time.

Whether the real helmet also shows a navigation aid's channel and distance there is open. The sim has no such aid (@navigation).

=== Looking aside <hmd-aside>

When you look away from the nose, the virtual head-up display stays behind and the head's set shows about the centre of your view (inferred; the maker says only that the main flight data and the tactical symbols are shown off the nose#sld):

- a cross on your line of sight;
- a heading tape for where your head points, with the steerpoint's caret;
- the airspeed and the altitude as bare numbers;
- the steerpoint's line;
- the designator on a locked target, and the cues of the selected weapon (@aa-weapons, @ag-weapons).

Look with the pointer or the view keys (#other("game", "views")).

=== The target and the threat symbols <hmd-symbols>

- *A locked target* carries the designator: an X with the shape of its identity, a circle for a friend, a square for an unknown, a diamond for a hostile (@radios). Outside the display's field the designator waits at the field's edge. The shapes in the helmet are inferred from the display's.
- *A missile that the jet's sensors see coming* shows as an M on a ring about the nose mark, at its bearing, with the seconds to its arrival under it (@fig-d-helmet_maw, @ew). Inferred: the real helmet's warning is not public.

#display("helmet_maw", [A missile warning in the helmet: the M with 10 seconds, right of the heading box. The helmet is in navigation, with the steerpoint's line at the lower right.], width: 100%)

=== The ground-avoidance cues <hmd-ground>

#display("helmet_break_x", [The break X in a steep dive: pull up now.], width: 100%)

When the jet's path leads into the ground, the sim warns you (inferred: the F-35's own cues are not public, and the F-16's stand in):

- the voice says "Pull up";
- the helmet shows a pull-up cue, and then a large X over the centre of the display (@fig-d-helmet_break_x). #sym.arrow.r *Roll the wings level and pull at once.*

The sim does not take the controls from you: an automatic recovery is #term("Not modelled").
