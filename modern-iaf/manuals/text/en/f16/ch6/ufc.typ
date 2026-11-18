#import "src.typ": *

#layout-head

The up-front controls are the #term("ICP"), the keyboard under the #term("HUD"), and the #term("DED"), the small display right of it. The pilot reaches the radio, navigation and identification data and the weapon delivery data there#d34[section I, "Upfront controls (UFC)", page 1-48]. The DED is dark until #row("AVIONICS_UFC") is on.

=== The keys

#table(columns: (27%, 1fr, 22%), table.header[*Control*][*What it does*][*Key*],
  [#row("1") to #row("9"), #row("0")], [Opens a page from the main page, or types a digit into a data field.], [#key("ICP 1 (T-ILS)") to #key("ICP 0 (M-SEL)")],
  [#row("entr")], [Enters the typed digits and moves to the next field.], [#key("ICP ENTR")],
  [#row("rcl")], [Clears the last digit, then the whole entry.], [#key("ICP RCL (clear)")],
  [#row("list")], [Opens the list of further pages.], [#key("ICP LIST")],
  [#row("com1"), #row("com2")], [Open the UHF and the VHF radio's page.], [#key("ICP COM1 (UHF)") #key("ICP COM2 (VHF)")],
  [#row("ICP_iff")], [Opens the IFF page (@radios).], [the pointer],
  [#row("switchSquareUp") up, down], [The previous or next field of the page.], [#key("DED field up (DCS up)") #key("DED field down (DCS down)")],
  [DCS to RTN], [Back to the main page.], [#key("DED back to CNI (DCS RTN)")],
  [DCS to SEQ], [The page's next sub-page or mode.], [#key("DED next sub-page (DCS SEQ)")],
  [#row("cursor-up")], [Steps the steerpoint, the channel or the preset.], [#key("ICP increment") #key("ICP decrement")],
  [#row("a-a"), #row("a-g")], [Select the air-to-air or the air-to-ground master mode (@stores).], [#key("Cycle master mode")],
)

*Entering data.* The selected field stands between two asterisks. Type the digits #then[they replace the field's value]. Press ENTR #then[the value is taken and the asterisks move to the next field]. A value outside the field's range is refused #then[the old value stays]. A field that is a choice changes with 0 and then ENTR.

=== The pages

#display("ded_pages", [The DED's pages. Left, from the top: the main page (CNI), STPT, MARK, IFF. Right: T-ILS, LIST, EWS, DLNK.], width: 80%)

#display("ded_ins", [The DED's #term("INS") page: the alignment's time and state, the jet's position, the altitude, the heading and the ground speed.], width: 60%)

#table(columns: (22%, 20%, 1fr), table.header[*Page*][*Opened by*][*Shows and sets*],
  [CNI, the main page], [DCS to RTN], [The UHF frequency, the steerpoint (the rocker steps it), the VHF preset, the time, the stopwatch while it runs, the transponder's modes that are on, the TACAN channel.],
  [T-ILS], [1], [The TACAN's mode (REC, T/R, A/A TR), channel (1 to 126) and band (X or Y); the ILS frequency and course; the tuned station's name, bearing and distance.],
  [ALOW], [2], [The low-altitude warning height: below it the HUD shows AL and the voice says "Altitude". The MSL floor.],
  [STPT], [4], [The steerpoint's number, latitude, longitude, elevation and time over it. SEQ: automatic or manual stepping to the next steerpoint.],
  [CRUS], [5], [SEQ steps four pages: TOS (the time over the steerpoint and the ground speed it needs), RNG (the fuel at the steerpoint, the wind), HOME (the fuel at the home steerpoint), EDR (the time to #term("Bingo fuel"), the fuel flow).],
  [TIME], [6], [The time; the stopwatch (ENTR with nothing typed starts and stops it, RCL zeroes it); a time added to every time over a steerpoint.],
  [MARK], [7], [Stores the present place as a markpoint. SEQ chooses how: overflying it, the radar's cursor, the targeting pod, the HUD. ENTR marks. The markpoints are steerpoints 26 to 30.],
  [FIX], [8], [The position update's page. The sim's #term("INS") does not drift, so the error it shows is always zero.],
  [A-CAL], [9], [The altitude calibration's page; its corrections are zero.],
  [LIST], [LIST], [1 DEST, the steerpoint's coordinates. 2 BNGO, the bingo fuel. 4 NAV, the navigation accuracy. 6 INS, the alignment's status. 7 EWS (@ew). 8 MODE. 0 MISC. ENTR: DLNK. RCL: INTG (@radios).],
  [MISC], [LIST, 0], [2 MAGV, the magnetic variation, shown only. 5 LASR, the targeting pod's laser code (@tgp). 8 BULL, the bullseye on the HSD on or off. RCL: the helmet display's blanking.],
  [COM 1, COM 2], [COM 1, COM 2], [A preset (1 to 20) or a typed frequency; the rocker steps the preset.],
)

#in-sim[
  - Every page above works as described.
  - The radios have no frequency model: every station answers on any preset, and the ILS serves the runway at any frequency. The TACAN channels are the sim's own.
  - #term("Not modelled"): the list's VIP, MAN and VRP pages and the remaining MISC pages; they are not offered.
  - #row("drift") works: DRIFT C/O and WARN RESET as in @hud. #row("wx") and #row("flir_ud") move only.
]
