#import "src.typ": *

#layout-head

The #term("FCR") searches the air ahead and tracks targets for the weapons. Its picture is the FCR format (@mfd): a B-scope, where left and right are azimuth and up is range#d34[section I, "Fire control radar (FCR) format" and "Air-to-air modes", pages 1-118 to 1-125].

=== Power and standby

+ #row("FCR") on. #then[The format shows STBY.]
+ Airborne, the radar starts searching by itself; or press #key("Cycle radar mode"). On the ground it does not radiate. #then[NO RAD shows low on the scope while a mode is chosen and the radar is silent.]
+ #key("Radar to standby") returns to standby. #key("Radar override: stop radiating") or #osb(4), OVRD, silences it and drops the lock.

=== The format's buttons

#display("fcr_modes", [The FCR in air-to-air. Top: RWS at A6 B4 with two returns (the squares) and the steerpoint (the triangle); RWS at A3 with the scan limits; a bugged target with its data line. Bottom: TWS; VSR; a dogfight pattern with a lock.], width: 100%)

#table(columns: (21%, 19%, 1fr, 15%), table.header[*Button*][*Legend*][*What it does*][*Key*],
  [#osb(1)], [CRM, ACM], [The next radar mode: the combined search mode, the dogfight mode.], [#key("Cycle radar mode")],
  [#osb(2)], [RWS, TWS, VSR; 20, 60, SLEW, BORE], [The search submode, or the dogfight pattern.], [#key("Radar submode / ACM pattern")],
  [#osb(3)], [NORM / EXP], [Expands the scope four times about the bugged target or the cursor.], [#key("Radar expand (EXP)")],
  [#osb(4)], [OVRD], [Stops radiating.], [#key("Radar override: stop radiating")],
  [#osb(5)], [CNTL], [The control page.], [],
  [#osb(20), #osb(19)], [the range arrows], [The range scale, 10 to 160 NM.], [#key("Radar range up") #key("Radar range down")],
  [#osb(18)], [A6, A3, A1], [The scan's width: 60°, 30° or 10° each side.], [#key("Radar scan width (A6 / A3 / A1)")],
  [#osb(17)], [B4, B1, B2], [The number of bars: the scan's height.], [#key("Radar scan bars (B4 / B1 / B2)")],
)

The cursor is two short vertical lines. Move it with the cursor control's keys (@hotas; the FCR must be the SOI) or the pointer. The two numbers beside it are the highest and lowest altitudes, in thousands of feet, that the scan covers at the cursor's range. Tilt the scan with #key("Radar antenna up (hold)") and #key("Radar antenna down (hold)"); the marks on the left edge show the antenna's elevation. Moving the cursor to the top or bottom of the scope steps the range scale.

=== The search submodes

- *RWS, range while search.* Each return is a small square. The radar bugs nothing by itself.
- *Bugging a target in RWS.* Put the cursor on a return and press #key("Radar: bug / lock (TMS up)"), or press #key("Next target"). #then[The return becomes a circled triangle turned to its heading, with its altitude under it; the line under the top legends gives its aspect, track, speed and closing speed.] The radar goes on searching and comes back to the bugged target each sweep. #if sufa [It keeps up to four bugged targets; the newest is the weapons' target.] else [It keeps one bugged target.] Press again on the weapons' target to lock it.
- *TWS, track while scan.* The radar keeps a track file on up to ten targets, shown as triangles; a file with no fresh return flashes and then goes. Bug one as in RWS. The scan is narrower: #osb(18) or #osb(17) steps three width and bar pairs.
- *VSR, velocity search.* It shows only closing targets, placed up the scope by their closing speed.
- *Single-target track.* The radar follows one target and stops searching; the top legend names the mode the lock came from. #key("Radar: drop bug / lock (TMS down)") or #key("Drop target lock") returns to the search.
- *A jammer.* An aircraft that jams your radar shows only inside its #term("burn-through range"). Farther out, but within the range at which the radar would see it, the search shows its bearing: a dashed line from the bottom to the top of the scope. The line gives no range. The #jet.short's own jamming symbol is not public; the sim draws the angle-only jam strobe of a fighter radar's display (inferred).

=== The dogfight patterns (ACM)

In ACM the radar shows no returns: it locks the first target inside its pattern. The scale is 10 NM. Press #key("Dogfight (DGFT)") or step #osb(1).

#table(columns: (27%, 1fr, 22%), table.header[*Pattern*][*Where it looks*][*Key*],
  [20], [The #term("HUD")'s field of view. No cue on the HUD.], [#key("Radar: drop bug / lock (TMS down)")],
  [60], [A tall, narrow strip up from the nose. The HUD shows a vertical line.], [#key("Radar: next submode, ACM 10 x 60 (TMS right)")],
  [SLEW], [A patch you move with the cursor control's keys. The HUD shows a cross at its middle.], [#key("Radar: ACM slew (TMS left)")],
  [BORE], [Straight along the nose. The HUD shows a cross on the gun cross.], [#key("Radar: bug / lock (TMS up)"), or hold #key("Radar boresight (hold)")],
)

=== The control page

#display("fcr_pages", [Left: EXP about the bugged target. Middle: the control page. Right: OVRD, with NO RAD.], width: 100%)

#osb(5) opens it and closes it. TGT HIS (#osb(18)) sets how many past sweeps' returns stay on the scope, the older ones dimmer. MTR (#osb(20)) sets the least speed along the line of sight that a return needs to show. The page's other options (CHAN, MK INT, BAND, PM, ALT TRK, LVL) step their value and change nothing in the sim.

#in-sim[
  - The modes and controls above work as described. The scan's bar height and rate and the shapes of the dogfight patterns are inferred.
  - With a lock the HUD shows a box on the target (@hud).
  - #term("Not modelled"): the radar's channels, bands and pulse options, and the cues after a missile's launch.
]
