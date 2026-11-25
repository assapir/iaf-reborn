#import "src.typ": *

The radar's air-to-air picture is the SRCH format of the #term("PCD"). The real radar has air-to-air modes and a combat identification function#apg81. The real format's layout is open: no public source shows it. The sim's layout is inferred, and its modes and controls are those of the F-16's radar, which stand in. The names CRM, RWS, TWS, VSR and ACM are the F-16's.

=== Power <radar-aa-power>

The real jet has no radar switch on its panels; the jet's computers run the radar (inferred).

#in-sim[
  - The radar comes up in standby with the jet's power. The format reads STBY.
  - On the ground it does not transmit. If a mode is selected there, the format reads NO RAD.
  - In the air it starts to search by itself, in CRM.
  - #key("Radar to standby") puts it back in standby. #key("Radar override: stop radiating") stops the transmission and keeps the mode; the lock and the contacts go.
]

=== The format <radar-aa-format>

#display("srch_crm", [SRCH in search: two hostile tracks, the cursor with the altitudes it covers, the steerpoint's circle. The range is 80 NM; the scan is the widest, with four bars.])

The picture is a fan: the jet at its foot, the range up, the bearing off the nose to the sides (@fig-d-srch_crm).

- *Top left:* the mode and the submode, here CRM RWS.
- *Left:* the arrows and the number of the range scale, in NM.
- *Right:* MODE. A click steps the mode, as #key("Cycle radar mode") does.
- *Bottom left:* the scan's width and its bars, here A6 B4.
- *The arcs* divide the range in four.
- *The cursor* is two short bars. The two numbers beside it are the highest and the lowest altitude the scan covers at the cursor's range, in thousands of feet.
- *A track* is drawn by its identity: a red diamond, a yellow square or a green circle (@radios), with a line along its heading.
- *Two vertical lines* mark the scan's limits when it is narrower than the fan.
- *The white circle* is the steerpoint.
- *A yellow dashed line* from the jet up the fan is the bearing of an aircraft that jams your radar. Such an aircraft shows as a track only inside its #term("burn-through range"); farther out, within the range at which the radar would see it, it shows as this line, which gives no range. The real symbol is open; the line is inferred.

=== The modes <radar-aa-modes>

#key("Cycle radar mode") steps RWS, TWS and ACM. #key("Radar air / ground") changes between the air-to-air and the air-to-ground modes (@radar-ag).

#table(
  columns: (0.6fr, 2.6fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Mode], [What it does]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [CRM RWS], [Range while search: the radar searches and shows what it finds. It marks nothing by itself. You may mark up to four targets; the radar keeps searching and follows them.],
  [CRM TWS], [Track while scan: the radar keeps a track of each aircraft it sees, up to ten, and searches on.],
  [CRM VSR], [A search that shows closing targets only, placed up the picture by their closing speed.],
  [STT], [Single target track: the radar follows one target and shows nothing else. The mode line adds STT to the mode the lock came from.],
  [ACM], [Air combat: the radar locks the first target inside a pattern in front of the jet. The scale stays at 10 NM. No target shows before the lock.],
)

#key("Radar: next submode, ACM 10 x 60 (TMS right)") and #key("Radar submode / ACM pattern") step the submode of CRM: RWS, TWS, VSR.

=== The scan <radar-aa-scan>

- #key("Radar scan width (A6 / A3 / A1)") steps the width: 60°, 30° or 10° to each side. A narrow scan is centred on the cursor.
- #key("Radar scan bars (B4 / B1 / B2)") steps the number of bars: the rows the beam sweeps, one above the other.
- #key("Radar antenna up (hold)") and #key("Radar antenna down (hold)") tilt the scan.
- #key("Radar range up") and #key("Radar range down") step the range scale: 10 to 160 NM in RWS and VSR, to 80 NM in TWS. The cursor also steps it when you move it past the top or the bottom of the fan.
- #key("Radar expand (EXP)") enlarges the picture four times about the marked target or the cursor. The same key returns.

A wide scan with many bars takes longer to come back to the same place. With a target marked, the scan centres on it.

Looking down at a target, the radar also receives the ground behind it, and tells the target apart by its speed along the line of sight. A target that flies across the beam, or slower than 60 kt along the line of sight, is lost in the ground's return: it drops off the fan, and a lock on it breaks. A target that flies at you or away from you, or is above you or level with you, stays. The 60 kt are inferred; the ground's return is not drawn.

=== To lock a target <radar-aa-lock>

+ *Move the cursor onto the track* with #key("Slew EO sensor / radar cursor up"), #key("Slew EO sensor / radar cursor down"), #key("Slew EO sensor / radar cursor left") and #key("Slew EO sensor / radar cursor right").
+ *Press* #key("Radar: bug / lock (TMS up)"). #sym.arrow.r *The target is marked: the radar follows it and keeps searching.* The newest mark is the weapons' target.
+ *Press* #key("Radar: bug / lock (TMS up)") *again on the same target.* #sym.arrow.r *The mode line reads STT. The top line shows the target's range in NM, its altitude in thousands of feet and the closing speed* (@fig-d-srch_stt). *The helmet shows the designator on the target* (@hmd).
+ *To let go, press* #key("Radar: drop bug / lock (TMS down)") or #key("Drop target lock").

#display("srch_stt", [SRCH in single target track: the lock's white ring on a hostile track, and its range, altitude and closing speed on the top line. The scale has stepped down to 10 NM by itself.])

Without the cursor: #key("Next target") and #key("Previous target") mark the next or the previous contact in turn.

=== Air combat patterns <radar-aa-acm>

In ACM the radar locks by itself. #key("Radar submode / ACM pattern") steps the pattern:

#table(
  columns: (0.6fr, 2.6fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Pattern], [Where the radar looks]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [20], [A box 30° wide and 20° high about the nose.],
  [60], [A tall strip from just under the nose up to 55° above it: for a target above you in a turn. Also on #key("Radar: next submode, ACM 10 x 60 (TMS right)").],
  [SLEW], [A patch about the cursor, level with the horizon. Also on #key("Radar: ACM slew (TMS left)").],
  [BORE], [Straight along the nose. Also on #key("Radar: bug / lock (TMS up)"), or hold #key("Radar boresight (hold)").],
)

#key("Radar: drop bug / lock (TMS down)") on a lock taken in ACM returns to the first pattern, so that the same target is not locked again at once.
