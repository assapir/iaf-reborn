#import "src.typ": *

#layout-head

In air-to-ground the #term("FCR") draws a map of the ground ahead from its own returns, finds vehicles and ships, and measures the range to the aim point#d34[section I, "Air-to-ground modes", pages 1-142 to 1-151]. Press #key("Radar air / ground") to change between air-to-air and air-to-ground; #key("Cycle radar mode") or #osb(1) steps the ground modes.

#display("fcr_ag", [The FCR in air-to-ground. Top: the ground map (GM), EXP, DBS1. Middle: DBS2 on the same targets, DBS2 on a runway, the ground map with FZ on. Bottom: GMT, SEA, AGR with the slant range.], width: 100%)

#table(columns: (auto, 1fr), table.header[*Mode*][*Shows*],
  [GM, ground map], [A fan-shaped map, the jet at its point: level ground is one mid green near and far, slopes facing the radar are bright and slopes facing away dim, towns are bright, water and runways dark, and ground hidden behind a ridge is in shadow. Every ground return is a bright mark. Scales 10 to 80 NM.],
  [GMT, ground moving target], [Moving vehicles only, over a dimmed map. Scales to 40 NM.],
  [SEA], [Ships only.],
  [AGR, air-to-ground ranging], [Selected by itself with a bomb's impact point or the gun in air-to-ground: the radar measures the slant range along the aiming line. The FCR and the #term("HUD") show the range.],
)

=== The format's buttons

#table(columns: (21%, 19%, 1fr, 15%), table.header[*Button*][*Legend*][*What it does*][*Key*],
  [#osb(2)], [MAN], [The manual range option; it changes nothing.], [],
  [#osb(3)], [NORM / EXP / DBS1 / DBS2], [A patch about the cursor, enlarged 4, 8 or 64 times. GMT and SEA have EXP only. Near the jet's ground track the DBS steps are skipped.], [#key("Radar expand (EXP)")],
  [#osb(7)], [FZ], [Freezes the picture; the jet's symbol moves over it. A mode or range change ends it.], [#key("Radar ground map freeze (FZ)")],
  [#osb(8)], [SP], [Snowplow: holds the cursor half the scale ahead of the jet.], [#key("Radar ground cursor snowplow (SP)")],
  [#osb(9)], [CZ], [Cursor zero: puts the cursor back on the steerpoint or the designated point.], [#key("Radar ground cursor zero (CZ)")],
  [#osb(10)], [STP / TGT], [Which point CZ returns to.], [#key("Radar ground cursor: steerpoint / target (STP / TGT)")],
  [#osb(20), #osb(19)], [the range arrows], [The range scale.], [#key("Radar range up") #key("Radar range down")],
)

=== Designating a point

The ground cursor is the crossing of two lines. It stays on its ground point as the jet moves, and starts on the steerpoint. The time to reach it stands at the lower right.

+ Make the FCR the SOI (@mfd).
+ Move the cursor onto the return or the place with the cursor control's keys (@hotas) or the pointer.
+ Press #key("Radar: bug / lock (TMS up)"). #then[On a return: a solid diamond rides the return and the radar tracks it. On bare ground: the diamond marks the point. The HUD shows a box there.]
+ The point is now the weapons' and the targeting pod's point (@tgp, @ag-weapons).
+ #key("Radar: drop bug / lock (TMS down)") drops it. #then[The cursor returns to the steerpoint.]

#in-sim[
  - The picture is made from the terrain's heights and the towns' built-up area; single buildings and trees give no return of their own. Its shading and the DBS limit near the ground track are inferred.
  - No picture of GM without FZ, of EXP and of DBS1 is in this edition.
  - #term("Not modelled"): the beacon and terrain-following modes.
]
