#import "src.typ": *

#layout-head

This section gives the displays, the switches and the counts.

=== The threat warning display

The round display left of the #term("HUD") shows the radars that look at the jet#d34[section I, "RWR display", page 1-199, with figure 1-132]. The jet is the cross in the middle and the top of the display is the nose.

#display("threat", [The threat warning display with no radar heard: the jet's cross, the inner ring, the marks every 30°.], width: 40%)

#display("threat_radars", [The threat warning display with three radars heard: each symbol stands on its radar's bearing.], width: 40%)

#table(columns: (auto, 1fr), table.header[*Symbol*][*Means*],
  [A number under a hat], [An aircraft's radar, by type.],
  [A digit or a letter], [A surface-to-air missile system's radar.],
  [A in a box], [Anti-aircraft artillery.],
  [S], [A ship.],
  [U], [An unknown radar; shown only with UNKNOWN on.],
  [A diamond round a symbol], [The highest-priority threat.],
  [A square round a symbol], [A radar locked on the jet.],
  [A flashing circle round a symbol], [A launch of a radar-guided missile. The symbol is the radar that guides it. #then[#row("lamp_rwr_launch_0") lights and the launch tone sounds.]],
  ..if sufa { ([Chevrons either side of a symbol, \>6\<], [Your jammer is on against that radar#d34[section I, "RWR display", figure 1-133, page 1-200] (the jammer, below).]) },
)

The display hears radars only. A missile that homes on heat sends no radar signal, so its launch does not show here.

A symbol stands at the radar's bearing. A search radar is at the edge, a lock on the inner ring, a launch nearest the centre. A new symbol flashes for 4 seconds with a tone.

#table(columns: (27%, 1fr, 22%), table.header[*Control*][*What it does*][*Key*],
  [HANDOFF #ctl-ref("lamp_twd_handoff_0")], [Moves the diamond to the next threat.], [#key("Threat warning: HANDOFF")],
  [#row("pri")], [Shows the 5 highest-priority threats, or up to 16.], [#key("Threat warning: priority / open mode")],
  [#row("unk")], [Shows the unknown radars.], [#key("Threat warning: unknowns")],
  [#row("sep")], [While held, spreads symbols that overlap.], [#key("Threat warning: target separate (hold)")],
  [SYS TEST #ctl-ref("lamp_twd_test_0")], [Shows a test pattern for 3 seconds.], [#key("Threat warning: system test")],
)

#if sufa [
=== The missile approach warning

The #jet.short's warning system also watches for a missile in flight toward the jet#footnote[Janes, "Elbit Systems to equip Israel's F-16Is with self-protection suite", 28 January 2025, #link("https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite"): the suite ordered for the jet holds an infrared missile warning system. Checked 18 November 2026.]. It sees the motor of every missile, radar-guided or heat-seeking. #then[A flashing M shows at the edge of the threat warning display at the missile's direction. Under it are the missile's class and a count of seconds: AAM for a missile fired from the air, SAM for one fired from the ground. The launch tone sounds.] The display does not name the missile itself; the class from where the missile was fired is inferred. #row("MWS_50_switch") passes the warning to the dispenser.
] else [
=== The missile approach warning

The #jet.short has no missile approach warning: a heat-seeking missile fired at the jet gives no warning. #row("MWS_50_switch") has no effect.
]

=== The countermeasures dispenser

The #term("CMDS") releases chaff and flares. Its panel is on the left console.

#picture("cmds", ("CH_50_switch": "1", "FL_50_switch": "1", "MODE_50_knob": "2", "RWR_50_switch": "3", "MWS_50_switch": "3"), width: 70%)

+ #row("CH_50_switch") and #row("FL_50_switch") on: each powers its dispenser.
+ #row("MODE_50_knob") to the mode: #key("CMDS mode knob") steps it.
+ #row("RWR_50_switch") and #row("MWS_50_switch") on: a launch that the threat warning or the missile warning reports reaches the dispenser.
+ Choose the program, 1 to 4: #key("CMDS program (1-4)").
+ Dispense: #key("CMS forward: run the CMDS program"). Stop: #key("CMS aft: stop dispensing").

#table(columns: (auto, 1fr), table.header[*Mode*][*What the dispenser does*],
  [OFF, STBY], [Nothing.],
  [MAN], [CMS forward runs the selected program.],
  [SEMI], [On a launch warning the voice says "Counter": give consent with #key("CMS right: consent (SEMI) / enable AUTO") and the program runs. CMS forward runs it at any time.],
  [AUTO], [Once enabled with CMS right, a launch warning runs the program by itself and the voice says "Counter".],
  [BYP], [CMS forward releases one chaff and one flare.],
)

A program is, for chaff and for flares, a burst quantity and interval and a salvo quantity and interval. Set them, and the quantity at which the voice warns, on the #term("DED"): LIST, 7 opens EWS CONTROLS with the two counts and the options; SEQ steps to the BINGO quantities and to the chaff and flare program pages (@fig-d-ded_pages). #then[The voice says "Chaff flare, low" at the BINGO quantity and "Chaff flare, out" at none.] #row("JETT_50_switch") releases every flare. #key("Drop chaff") and #key("Drop flares") release one at any time. Nothing is dispensed with the gear down.

A flare burns hotter than the engine and draws the seeker of a heat-seeking missile. Chaff is a cloud of thin strips that gives a radar a larger echo than the jet's. A decoy acts on a missile in flight, at the moment it is released. Newer heat-seeking missiles tell a flare from a jet by the colours of its heat and by its path#footnote[Wikipedia, "Flare (countermeasure)": "More modern IR-guided missiles have sophisticated on-board electronics and secondary electro-optical sensors that help discriminate between flares and targets"; "spectral discrimination" and "trajectory discrimination", #link("https://en.wikipedia.org/wiki/Flare_(countermeasure)"). Checked 22 November 2026.]. A radar that measures speed along its line of sight tells the chaff, which slows at once, from a jet that flies toward it or away from it. A jet that turns to move across the radar's line is hard to tell from the chaff#footnote[Wikipedia, "Chaff (countermeasure)": modern radars "can thus distinguish chaff from an aircraft, which continues to move at high speed"; an aircraft moving "predominantly perpendicular to the radar source" is "more difficult to separate from the effectively stationary chaff", #link("https://en.wikipedia.org/wiki/Chaff_(countermeasure)"). Checked 22 November 2026.].

=== The jammer

#if sufa [
The #jet.short carries a self-protection jammer in its dorsal spine#footnote[Airforce Technology, "F-16I Sufa (Storm) Multirole Fighter" (the self-protection jammer of the jet's suite), #link("https://www.airforce-technology.com/projects/f-16i-soufa/"); Military Periscope, "Advanced Self-Protection System (ASPS)" (the jammer in the dorsal spine), #link("https://www.militaryperiscope.com/weapons/electronics/electronic-warfare/advanced-self-protection/overview/"). Not read again for this chapter.]. It sends noise on an enemy radar's frequency, so that the radar cannot pick the jet's echo out of the noise. Close to the radar the echo is stronger than the noise. The range inside which the radar sees the jet again is its #term("burn-through range")#footnote[Wikipedia, "Radar jamming and deception": "The burn-through range is the distance from the radar at which the jamming is ineffective", #link("https://en.wikipedia.org/wiki/Radar_jamming_and_deception"). Checked 22 November 2026.]. A smaller echo has a shorter burn-through range.

With the jammer on, an enemy radar sees the jet only inside its burn-through range. A search radar farther away does not find the jet, and a radar's lock breaks when the jet is farther away than that range.

#caution[The jammer shows the enemy where you are: a jet that jams "essentially broadcasts its position"#footnote[Wikipedia, "Radar jamming and deception", the same page. Checked 22 November 2026.]. An enemy fighter's radar sees your bearing beyond the burn-through range and the fighter flies toward it. Turn the jammer on when a radar locks on you or a missile flies at you, and off when the threat is gone.]

+ Press #key("ECM jammer"). #then[#row("lamp_ecm_enbl_0") lights. On the threat warning display each radar shows between chevrons.]
+ Press #key("ECM jammer") again. #then[The jammer is off; #row("lamp_ecm_enbl_0") goes out.]
] else [
#key("ECM jammer") turns the jammer on and off. #then[#row("lamp_ecm_enbl_0") lights.]
]

#in-sim[
  - The cockpit's MODE knob has three positions; SEMI, AUTO and BYP are on the key, with the knob left at MAN.
  - The programs' starting values are the sim's own.
  - #row("01_50_switch"), #row("02_50_switch") and #row("JMR_50_switch") move only.
  - #row("IFF_button") #then[dims the threat warning display turned down and brightens it turned up.]
  - No picture of the display with threats is in this edition.
  - *A decoy.* At each release every missile that flies at the jet may follow it: a flare a heat-seeking missile, chaff a radar-guided one. A missile that follows a decoy does not come back to the jet. The chance is each seeker's own (inferred). Within the missile's last 6 seconds a flare draws an R-73 about one time in three, an AIM-9M one in four, an AIM-9X or a Python 5 fewer than one in ten. Chaff draws a radar-guided missile about two times in five with the jet on the missile's beam. With the jet flying straight away from it, chaff draws an R-27R one time in five, and an AIM-120 or a surface-to-air missile one in twelve. A decoy has its full chance within the missile's last 6 seconds; one released earlier has less, and it burns out after 4 seconds. Above 4 g every decoy has one and a half times its chance; a flare beside a lit afterburner, a quarter.
  #if sufa [- *The jammer's burn-through range* is 0.3 of the radar's range against an echo of 5 m², times the square root of the jet's echo over 5 m² (inferred: the jammer's power is not public). Head on, an S-300 site's search radar finds the jet at 44 km in place of 210 km, its tracking radar holds it inside 29 km in place of 140 km, and an enemy fighter's radar, which takes every jet as 5 m², holds it inside 22 km in place of 74 km.] else [- #term("Not modelled"): the #jet.short's jammer. #key("ECM jammer") lights #row("lamp_ecm_enbl_0") only.]
  - #term("Not modelled"): the jammer's own controls and modes, and its effect on a missile's own seeker.
]
