#import "src.typ": *

The real jet's stick and throttle carry the switches that work the sensors and the weapons, so the pilot's hands stay on them#d34[section I, "Hands-on control", page 1-43]. The sim's #row("anim000") and #row("THROTTLE") are drawn and move; their switches are keys. Each switch acts on the _sensor of interest_ (SOI): the one display, of the #term("HUD") and the two #term("MFD")s, that the cursor and the target switch work on (@mfd).

#table(columns: (27%, 1fr, 22%), table.header[*Switch*][*What it does in the sim*][*Key*],
  [Target management switch (TMS) up], [Radar: bugs the target under the cursor (marks it as the one to follow while the search goes on), then locks it. Ground map: tracks or designates. Targeting pod: tracks. HSD: picks the steerpoint under the cursor.], [#key("Radar: bug / lock (TMS up)")],
  [TMS down], [Drops the lock, the bugs, the track or the designation. Targeting pod: slaves it to the designated point.], [#key("Radar: drop bug / lock (TMS down)")],
  [TMS right], [Radar: the next search submode; in the dogfight patterns the vertical scan. Targeting pod: an area track.], [#key("Radar: next submode, ACM 10 x 60 (TMS right)")],
  [TMS left], [Radar: interrogates (@radios); in the dogfight patterns the slewable scan.], [#key("Radar: ACM slew (TMS left)")],
  [Display management switch (DMS) up], [Makes the HUD the SOI.], [#key("DMS up (SOI to the HUD)")],
  [DMS down], [Moves the SOI to an MFD, then from one MFD to the other.], [#key("DMS down (SOI to an MFD)")],
  [DMS left, right], [Shows the next format of the left or the right MFD.], [#key("DMS left (left MFD's next format)") #key("DMS right (right MFD's next format)")],
  [Cursor control], [Moves the SOI's cursor, or slews the targeting pod.], [#key("Slew EO sensor / radar cursor up") #key("Slew EO sensor / radar cursor down") #key("Slew EO sensor / radar cursor left") #key("Slew EO sensor / radar cursor right")],
  [Antenna elevation wheel], [Tilts the radar's scan while held.], [#key("Radar antenna up (hold)") #key("Radar antenna down (hold)")],
  [Expand (the stick's pinky switch)], [Expands the radar's picture.], [#key("Radar expand (EXP)")],
  [Countermeasures management switch (CMS) forward, aft, right], [Runs the dispenser's program, stops it, gives consent (@ew).], [#key("CMS forward: run the CMDS program") #key("CMS aft: stop dispensing") #key("CMS right: consent (SEMI) / enable AUTO")],
  [Dogfight and missile override switch], [Dogfight: a short-range missile, the gun's sight and the dogfight radar patterns at once. Missile override: a radar missile and the search radar. The same key again centres the switch, and the weapon and radar mode from before come back; a lock is kept.], [#key("Dogfight (DGFT)") #key("Missile override (MSL OVRD)")],
  [MAN RNG / UNCAGE (the throttle's knob, pressed)], [Uncages a short-range missile's seeker so that it follows the target it hears; a second press cages it (@aa-weapons).], [#key("Missile seeker: UNCAGE / CAGE")],
  [Trigger], [Fires the gun.], [#key("Gun trigger")],
  [Weapon release button], [Releases the selected weapon while held.], [#key("Release selected weapon")],
)

The pointer also works the displays: on the radar's format it places the cursor, and a click on a target presses TMS up there.

#in-sim[#term("Not modelled"): the paddle switch and the stick's trim hat as a switch (the trim has its keys). The speedbrake switch has its keys (@handling-general).]
