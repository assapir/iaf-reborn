#import "src.typ": *

#layout-head

=== Radios

COM 1 is the UHF radio and COM 2 the VHF radio. Each has 20 presets; set a preset or a frequency on its #term("DED") page (@ufc). #key("Backup UHF channel") steps the backup UHF panel's channel. The calls themselves are in #other("game", "tower").

=== The transponder

The IFF page (#row("ICP_iff")) sets the transponder: modes 1, 2, 3/A and C, each on or off, and their codes. #key("IFF IDENT") replies with IDENT #then[the main page's IFF field shows I for 18 seconds.]

=== The interrogator

#if sufa [The interrogator asks the aircraft ahead to identify themselves#d34[section I, "Interrogator operation", page 1-191].] else [The interrogator asks the aircraft ahead to identify themselves. That the #jet.short carries one is inferred.]

+ Scan: #key("AIFF: scan interrogation (TMS left)"). It covers 60° each side of the nose. #then[The radar's own targets blank for a second; each friend's reply shows as a green circle on the #term("FCR") and the HSD for 3 seconds.]
+ Line of sight: #key("AIFF: line-of-sight interrogation (TMS left held)"). It covers 15° each side of the radar's cursor.
+ No circle on a target means no reply: the target is not known to be a friend. A reply of unknown kind shows as a yellow square.

#display("fcr_aiff", [A friend's reply on the FCR: the green circle on the tracked target.])

The DED's INTG page shows the last interrogation and the replies on show; the IFF page's second sub-page (SEQ) shows the interrogator's settings.

=== The data link

The data link shows other aircraft's knowledge on your displays. Turn #row("dl-switch") on (it starts off). #then[The HSD and the FCR show the flight's other jets as cyan circles with their number, and the tracks of the airborne warning aircraft: a green circle for a friend, a red diamond for a hostile, each with a line along its heading (@fig-d-hsd).] The tracks refresh every 4 seconds. The DED's DLNK page shows the switch, the number of jets and tracks, and the refresh time. The symbols' shapes and colours on the F-16 are inferred.

#in-sim[
  - Nothing interrogates your transponder: its page is a cockpit procedure only.
  - Every unit of your side replies as a friend; no unit replies as unknown.
  - #term("Not modelled"): frequencies that change who answers, the secure modes of the transponder, #row("IFF_button").
]
