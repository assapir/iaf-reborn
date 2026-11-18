#import "src.typ": *

#layout-head

Each #term("MFD") has 20 buttons round its screen, the option select buttons (OSB), numbered clockwise from the top left: 1 to 5 across the top, 6 to 10 down the right, 11 to 15 along the bottom from right to left, 16 to 20 up the left#d34[section I, "MFDS switches", pages 1-59 and 1-60, with figure 1-26]. A legend on the screen beside a button says what the button does now. This chapter names a button as #osb(1): the reference shows it on the left MFD's figure, and the right MFD's buttons carry the same numbers. Press a button with the pointer. The screens are dark until #row("AVIONICS_MFD") is on.

=== The bottom row, on every format

#table(columns: (22%, 20%, 1fr), table.header[*Button*][*Legend*][*What it does*],
  [#osb(15)], [SWAP], [The two MFDs trade their formats.],
  [#osb(14), #osb(13), #osb(12)], [three formats], [The MFD's three formats; the one shown is in an inverse box. Press another to show it. Press the shown one to open the format menu; press it again to close the menu.],
  [#osb(11)], [DCLT], [Hides the legends at the sides and the top; their buttons still work. On the SMS format the button is S-J (@stores).],
)

At power-up the left MFD holds #term("FCR"), TGP and TEST, and the right one HSD, SMS and WPN. Each master mode (@stores) keeps its own three formats on each MFD and brings them back.

=== The format menu

#table(columns: (22%, 20%, 1fr), table.header[*Button*][*Legend*][*Format*],
  [#osb(20)], [FCR], [The fire control radar (@radar-aa, @radar-ag).],
  [#osb(19)], [TGP], [The targeting pod (@tgp); offered only with a pod loaded.],
  [#osb(18)], [WPN], [A guided bomb's status (@ag-weapons).],
  [#osb(6)], [SMS], [Stores management (@stores).],
  [#osb(7)], [HSD], [The horizontal situation display, below.],
  [#osb(8)], [DTE], [The data cartridge.],
  [#osb(9)], [TEST], [The fault list.],
  [#osb(10)], [#term("FLCS")], [The flight control system's four branches.],
  [#osb(1)], [BLANK], [Nothing but the bottom row.],
  [#osb(5)], [RESET], [The reset menu.],
)

=== The sensor of interest

One of the #term("HUD"), the left MFD and the right MFD is the sensor of interest (SOI): the cursor and the target switch (@hotas) work on it. It starts on the left MFD. #then[The SOI MFD shows a box inside its edge; with the HUD the SOI an asterisk stands at the HUD's upper left.] An FCR, HSD, TGP or WPN format that is not the SOI reads *NOT SOI*. A format that cannot be the SOI hands it to the HUD.

=== HSD

#display("hsd", [The HSD with the data link on: the jet, the radar's scan as a wedge, three hostile tracks as red diamonds, the bullseye with the jet's bearing and distance from it.])

The HSD is a map seen from above: the jet, range rings, the route's steerpoints, the radar's scan, the threat rings and the data link's tracks (@radios).

#table(columns: (22%, 20%, 1fr), table.header[*Button*][*Legend*][*What it does*],
  [#osb(1)], [DEP / CEN], [The jet low on the display, or in its middle.],
  [#osb(2)], [DCPL / CPL], [Coupled: the range follows the radar's.],
  [#osb(3)], [NORM / EXP1 / EXP2], [Expands the picture two or four times about the HSD's cursor.],
  [#osb(4)], [FRZ], [Holds the picture; the jet moves over it.],
  [#osb(5)], [CNTL], [The control page: its buttons turn the layers on and off: FCR, the scan wedge (#osb(20)); PRE, the planned threats (#osb(19)); NAV1, the route (#osb(6)); RINGS (#osb(7)); BULL, the bullseye (#osb(8)).],
  [#osb(20), #osb(19)], [the range arrows], [The range up and down: 15, 30, 60, 120 NM.],
)

With the HSD the SOI the cursor control's keys (@hotas) move a cross over it, and TMS up on a steerpoint makes it the current one.

=== TEST, DTE, FLCS, BLANK, RESET

#display("mfd_formats", [Top: the TGP format slaved and with the laser firing; the WPN format with no guided bomb selected. Middle: DTE, FLCS, TEST. Bottom: BLANK and the reset menu.], width: 90%)

#display("mfd_menu_sms", [Top: the format menu; the HSD's control page; the SMS inventory. Bottom: the SMS in air-to-ground with a laser-guided bomb; the same page with the delivery mode chosen; the SMS in air-to-air.], width: 100%)

- *TEST* lists the faults, or NO FAULTS.
- *DTE:* #osb(3), LOAD, loads the data cartridge #then[LOAD IN PROG for 3 s, then LOAD COMPLETE.] The data is loaded at the start of a flight in any case.
- *FLCS* shows each of the four branches as OK, DEGR or FAIL. On the ground #osb(3), BIT, runs the built-in test #then[BIT RUN for 45 s, then BIT PASS or BIT FAIL.]
- *RESET:* #osb(6), MSMD RESET, puts every master mode's formats back to the start. #osb(7), DCLT RESET, shows the hidden legends on both MFDs again.

#in-sim[
  - The layouts of the HSD's control page, DTE, FLCS and the reset menu are inferred.
  - #row("MFD1_MFDButtonGain"), #row("MFD1_MFDButtonBrightness") and #row("MFD1_MFDButtonCon") and the right MFD's three are described in their figures' tables.
  - #term("Not modelled"): the FLIR, TFR, HAD and RCCE formats; the menu does not offer them.
  - No picture of the format menu and of the SMS pages is in this edition.
]
