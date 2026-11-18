#import "src.typ": *

#layout-head

This section gives the displays, the switches and the counts. It says nothing of how well a countermeasure works.

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
  [A flashing circle round a symbol], [A launch. #then[#row("lamp_rwr_launch_0") lights and the launch tone sounds.]],
)

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

The #jet.short's warning system also watches for a missile in flight toward the jet#footnote[Janes, "Elbit Systems to equip Israel's F-16Is with self-protection suite", 27 January 2025, #link("https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite"): the suite ordered for the jet holds an infrared missile warning system. Checked 18 November 2026.]. #then[A flashing M shows at the edge of the threat warning display at the missile's direction, with a count of seconds under it, and the launch tone sounds.] The display does not name the missile. #row("MWS_50_switch") passes the warning to the dispenser.
] else [
=== The missile approach warning

The #jet.short has no missile approach warning; #row("MWS_50_switch") has no effect.
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

=== The jammer

#key("ECM jammer") turns the jammer on and off. #then[#row("lamp_ecm_enbl_0") lights.] Electronic attack is outside this manual.

#in-sim[
  - The cockpit's MODE knob has three positions; SEMI, AUTO and BYP are on the key, with the knob left at MAN.
  - The programs' starting values are the sim's own.
  - #row("01_50_switch"), #row("02_50_switch") and #row("JMR_50_switch") move only.
  - No picture of the display with threats is in this edition.
  - #term("Not modelled"): the jammer's own controls and modes.
]
