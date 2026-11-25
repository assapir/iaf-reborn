#import "src.typ": *

When the radar looks at the ground, the SRCH portal of the #term("PCD") reads ASR in its header. The real radar maps the ground in fine detail and tracks moving vehicles#apg81, and the map can fill a portal of the display#sld. The sim's picture is grey in a square (inferred); its modes, legends and controls are those of the F-16's radar, which stand in (inferred). The names GM, GMT, SEA, EXP and DBS are the F-16's.

=== The modes <radar-ag-modes>

#key("Radar air / ground") changes from the air-to-air modes to GM. #key("Cycle radar mode") then steps GM, GMT and SEA.

#table(
  columns: (0.6fr, 2.6fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Mode], [What it shows]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [GM], [Ground map: the ground's picture with every ground return. Scales 10 to 80 NM.],
  [GMT], [Ground moving target: the moving vehicles only, over the dimmed map. Scales to 40 NM.],
  [SEA], [Ships only.],
  [AGR], [Air-to-ground ranging. The radar selects it by itself when a weapon aimed by eye is selected: it measures the distance along the aiming mark to the ground and shows it at the centre of the format.],
)

=== The format <radar-ag-format>

#display("asr_gm", [ASR in GM at 80 NM: the ground as a fan in front of the jet, the sea black at the upper left, a group of ground returns in yellow squares, and the cursor's two lines.])

- *Top left:* the mode and the picture's size: NORM, EXP, DBS1 or DBS2.
- *Top right:* STP or TGT, the point the cursor returns to; before it FZ or SP while that function is on.
- *The picture:* level ground is one mid grey near and far; slopes that face the radar are bright, slopes that face away dim; towns are bright; water and runways are black; ground hidden behind a ridge is dark.
- *The cursor* is the crossing of two lines over the whole picture. It marks a point on the ground and stays on it while the jet moves. It starts on the steerpoint.
- *A return* is drawn by its identity (@radios): the yellow squares of @fig-d-asr_gm are unknown.

=== To enlarge the picture <radar-ag-exp>

#key("Radar expand (EXP)") steps NORM, EXP, DBS1 and DBS2. Each step shows a smaller patch of ground about the cursor, larger (@fig-d-asr_dbs1). GMT and SEA have EXP only.

#display("asr_dbs1", [ASR in DBS1: the patch about the cursor, with four ground targets apart from each other.])

DBS needs the patch to be off the jet's track: within 10° of it the step is skipped (inferred). A change of the range scale returns to NORM.

=== The cursor's keys <radar-ag-cursor>

+ *Move the cursor* with #key("Slew EO sensor / radar cursor up"), #key("Slew EO sensor / radar cursor down"), #key("Slew EO sensor / radar cursor left") and #key("Slew EO sensor / radar cursor right").
+ *Press* #key("Radar: bug / lock (TMS up)"). #sym.arrow.r *A return under the cursor is tracked: a solid diamond, and the cursor rides it. With no return there, the point itself is designated. The helmet shows a box on it.* This point is where the bombs in VIS aim (@ag-weapons).
+ *To drop it, press* #key("Radar: drop bug / lock (TMS down)"). #sym.arrow.r *The cursor returns to the steerpoint.*

#table(
  columns: (1.5fr, 2.4fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Key], [What it does]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [#key("Radar ground map freeze (FZ)")], [Holds the picture; the jet's symbol moves over it. The same key, or a change of mode or range, ends it.],
  [#key("Radar ground cursor snowplow (SP)")], [Holds the cursor ahead of the jet at half the range scale, until you move it or designate.],
  [#key("Radar ground cursor zero (CZ)")], [Removes your movements of the cursor: it returns to the steerpoint or to the designated point.],
  [#key("Radar ground cursor: steerpoint / target (STP / TGT)")], [Chooses which of the two points that is.],
)
