#import "src.typ": *

The #term("PCD") is the one large touch display across the front panel, #row("PCD"). It shows the flight data, the sensors, the stores, the engine and the fuel in areas that you arrange. The real display is two screens of 8 by 10 inches side by side that work as one. The pilot divides it into as many as four large windows, called portals, over a row of small windows#sld, or gives a whole half to one window#codeone. The strip of small legends along the top is inferred. The real pilot works the display by touch, with a cursor, or by voice#sld.

#in-sim[The display has the same parts (@fig-d-pcd). The pointer stands for your finger: a click is a touch. The layout of several formats is inferred, because the real ones are public only in part; each section of this chapter says which.]

#display("pcd", [The panoramic display from the pilot's eye. Here the left half is one large portal with the radar's SRCH format and tabs along its foot; the right half is two portals, SRCH and TFLIR, over four windows.], width: 100%)

=== The function bar <pcd-bar>

The strip along the top is the function bar. It always shows the state of the jet, in two rows of small legends:

- the engine's #term("RPM") as a dial and a number, with AB while the afterburner burns;
- the fuel: total, internal and external, in thousands of pounds, with the #term("Joker fuel") mark;
- the stores: the counts of the missiles and the bombs, the chaff, the flares and the gun's rounds;
- the jet's outline with the three landing gear lights and the flaps;
- ICAWS, with the worst message in its colour (@warnings);
- the autopilot's mode, LVL or NAV;
- the three radios, A, B and C; NAV with the steerpoint;
- the calibrated airspeed, the altitude and the Mach number;
- CABIN, GCAS and ALOW. ALOW turns yellow below 500 ft above the ground;
- the time.

Two of its legends are controls. In a simulator's manual SWAP trades the bar's left and right halves and leaves the portals as they are, and MENU opens an extra page with CRUS, which brings back the starting layout, and with the lights and the helmet's settings#ife. The real pages are not public.

+ *Click SWAP*, the two arrows at the middle of the bar. #sym.arrow.r *The bar's halves trade places. The portals stay.*
+ *Click MENU*, the grid at the right of the bar. #sym.arrow.r *The MENU page opens on the portal under it, with POP UP in magenta in its header.*
+ *Click CRUS.* #sym.arrow.r *The display goes back to the layout it starts with, the bar unswapped.*
+ *Or click the pop-up's header, or MENU again.* #sym.arrow.r *The portal shows its format again.*

#in-sim[The MENU page has CRUS only. The lights and the helmet's settings are #nis. The bar's other legends show only.]

=== Portals, tabs and windows <pcd-portals>

- *A portal* shows one format. Its header reads the format's name over the master mode: NAV, A-A or A-S.
- *A large portal* fills its half. The half's other five formats wait as tabs along its foot.
- *Two portals* share the other half. Under them are four windows. A window shows a waiting format's name and its picture at half size, without its legends.

The sim starts with the left half as one large portal and the right half as two portals over windows:

#table(
  columns: (1fr, 1fr, 2fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Half], [Shown], [Waiting]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [Left], [TSD-1], [Tabs: TSD-2, ENG, SMS, TSD-3, ICAWS],
  [Right], [SRCH and TFLIR], [Windows: TWD, FUEL, EFI, ENG],
)

=== Choosing a format <pcd-choose>

+ *Click a tab or a window.* #sym.arrow.r *Its format moves into the portal. The format that was there takes its place as a tab or a window.*
+ *Or click the portal's header*, its name at the top left. #sym.arrow.r *The MENU grid opens: a button for each of the 11 formats, the current one white.*
+ *Click a button.* #sym.arrow.r *The format shows in the portal and the grid closes.* A second click on the header closes the grid without a change.

Three keys bring a format to a portal: #key("TSD page on MFD"), #key("FLIR page") and #key("Damage page"). Selecting a weapon brings the SMS.

#display("menu", [The MENU grid on a portal: the 11 formats, the portal's own in white.], width: 60%)

=== A format's controls <pcd-cntl>

A portal's header has CNTL> at its right#ife. What the real CNTL opens is not public. The sim's control page is inferred from the F-16's CNTL page: it holds the format's controls.

+ *Click CNTL>* on a TSD, SRCH or TFLIR portal. #sym.arrow.r *The control page opens in the portal: a button for each control.*
+ *Click a button.* #sym.arrow.r *The control acts at once.* TSD: MAP, RNG UP, RNG DN. SRCH: MODE, RNG UP, RNG DN. TFLIR: ZOOM IN, ZOOM OUT, WIDE or SPOT, LSR (@tflir).
+ *Click CNTL> again.* #sym.arrow.r *The format shows again.*

#in-sim[The other formats have no control page and show no CNTL>.]

=== The formats <pcd-formats>

#table(
  columns: (0.7fr, 2.4fr, 0.9fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Format], [What it shows], [Section]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [TSD-1, TSD-2, TSD-3], [The tactical situation display: a map round the jet with the route, the tracks and the threats.], [@navigation],
  [SRCH], [The radar's air-to-air picture. Its header reads ASR while the radar looks at the ground.], [@radar-aa, @radar-ag],
  [SMS], [The stores management system: the jet from above with every station's store.], [@stores],
  [TFLIR], [The picture of the built-in targeting sensor.], [@tflir],
  [TWD], [The threat warning display.], [@ew],
  [EFI], [The electronic flight instrument: the attitude ball, the speed and altitude boxes, Mach and g, the heading arc.], [@instruments],
  [ICAWS], [Every caution, the warnings first.], [@warnings],
  [FUEL], [The fuel totals and the internal tank's bar with the JOKER and BINGO marks (#term("Bingo fuel")).], [@fuel],
  [ENG], [The RPM dial, the throttle's place, AB and the thrust.], [@engine],
)

The standby display under the glass, #row("ESIS"), is no format of the PCD: it has its own sensors and always shows attitude, airspeed, altitude and heading.

=== What the real display has and the sim lacks <pcd-missing>

All of these are #nis:

- the CNI format: the radios, the navigation aids and the identification on the glass#codeone;
- the WPN-A and WPN-S formats: the weapons' state and programming. Their layout is open;
- the DAS format: the picture of the cameras round the jet#das-wiki;
- the FCS, PHM, CHKLST and DIM formats, which a simulator's manual shows#ife;
- widening a portal over its whole half by your own choice, and the five preset layouts#codeone#sld. The sim's halves keep the arrangement they start with;
- the cursor of the throttle on the display, and voice commands.
