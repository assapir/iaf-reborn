# Real MFDs: per-aircraft reference (Extras, planned)

The "Real MFDs" option is a planned Extras switch. With it on, each jet's MFDs (multi-function displays) draw that
jet's real head-down formats in place of the original 1998 pages. With it off (the default), the MFDs draw the
original pages ([mfd.md](mfd.md)). This file is the reference the option will be built from: per jet, which real
display stands for each game page, its layout, and the game state that drives it. Status: research done, nothing
built ([roadmap.md](roadmap.md) "Real MFDs").

Key facts:
- Researched October 2026 from public sources. The repo keeps no source images.
- Real-world documents give the F-16, F-15, F-4E and Mirage displays in detail[^dash34][^f15-1][^f4e-1][^raaf]. The
  F-15's radar and threat displays, the F-4E's scopes, the F-35I's formats and the MiG-29's displays come mostly from
  simulator manuals; each such footnote says so.
- The Lavi, Kurnass 2000 and Kfir formats are public only in outline; ours are reconstructions (inferred).
- The game's pages are listed in mfd.md §3: 0 NAV (waypoint list), 1 stores, 2 radar (A-A and A-G sub-modes), 3 TSD
  (tactical situation display), 4 damage, 5 TV (EO weapon), 6 FLIR, 7 RWR, 8 MENU, 9 ADI, 10 HARM.
- How many MFDs each jet has, and their default pages, is in mfd.md §7: one MFD on the Mirage, Kfir, F-4E and
  MiG-23; two on the F-16, Kurnass 2000 and MiG-29; three on the F-15 and Lavi. The F-35I draws the game's pages in
  the portals of its panoramic display ([f35i.md](f35i.md) §4.3).
- The pages draw through the primitives of `mfd.gd` in MFD px (mfd.md §8), so the real formats can reuse them.

Sources are footnotes; a simulator source says so in its footnote. "Inferred" marks our own reasoning; "open" marks
what no source gives.

Terms used throughout:
- A-A = air-to-air; A-G = air-to-ground; A-S = air-to-surface.
- OSB = option select button (the buttons around a display's edge).
- B-scope = a radar picture with azimuth across and range up; PPI (plan position indicator) = a fan from an apex at
  the bottom, true to the ground's shape.
- RWR = radar warning receiver; SAM = surface-to-air missile; IFF = identification friend or foe.
- HSI = horizontal situation indicator (a compass card with course and bearing pointers); ADI = attitude director
  indicator (the attitude ball).
- SOI = sensor of interest; TDC = target designator control; HOTAS = hands on throttle and stick.
- STT = single-target track; TWS = track while scan; ASE = allowable steering error (the circle the steering dot must
  be inside to shoot).
- NM = nautical miles; kft = thousands of feet.

## Decisions (user, 2026-10-21)

- A game page with a real counterpart on that jet draws the real format. A game page with no real counterpart is not
  offered on that jet: it cannot be selected (it is not in the menu and it is not a default page). No MFD is ever left
  blank.
- Build order: the F-35I first (make its panoramic display close to the real one), with the F-16 at the same time;
  then all the other jets.
- The F-4E, the Mirage and the other jets with dedicated scopes (a radar scope, an RWR scope) get those scopes drawn
  inside the game's MFD frames for now. This changes once a jet has its original-style cockpit.
- F-15: the real displays: the VSD, the TEWS display, the HSI on the middle MFD, and the ADI.
- Lavi: the formats as in the cockpit photo (a list on the left, a radar fan in the centre, a colour navigation rose
  on the right), provided the cockpit art needs no redraw.

## Summary per jet

"Game MFDs" is the original's set (mfd.md §7). "Not offered" follows the first decision. Each jet's section gives
the details.

| Jet | Game MFDs | Real head-down displays | Game page → real format | Not offered |
|---|---|---|---|---|
| F-35I Adir | the panoramic display: 4 portals + 8 lower windows | one 20 × 8 in touchscreen: portals, sub-portals, the function bar | TSD → TSD-1; radar A-A → SRCH; radar A-G → ASR; stores → SMS; RWR → TWD; TV / FLIR → TFLIR; damage → ICAWS; ADI → EFI; MENU → the MENU grid | HARM, NAV |
| F-16C/D Barak | L radar, R TSD; panel RWR dial; panel ADI | two 4 × 4 in monochrome MFDs | radar → FCR; stores → SMS; TSD → HSD; TV → WPN; FLIR → TGP; damage → TEST (fault list); MENU → the format menu; HARM → HAS (open: out of era) | NAV (on the DED), ADI, RWR (already not an MFD page) |
| F-15C/D Baz | L radar, M TSD, R RWR; ADI page | VSD (radar CRT), TEWS display (round CRT), ADI and HSI (instruments) | radar → VSD; TV → VSD video; RWR → TEWS; TSD → HSI (middle MFD); ADI → ADI | NAV, damage, FLIR, HARM, MENU; stores open |
| Lavi | L radar, M TSD, R RWR; ADI page | three Elbit head-down displays (two colour, one monochrome) | stores → the left list; radar → the centre radar fan; TSD → the right colour navigation rose | FLIR, HARM; the rest open |
| F-4E Kurnass | L radar; panel RWR dial | the radar scope; the RHAW (threat) scope | radar → the APQ-120 scope; TV → the DSCG's TV mode (open: which jets); panel RWR → the RHAW scope | NAV, stores, TSD, damage, FLIR, ADI, HARM, MENU |
| Kurnass 2000 | L radar, R RWR; ADI page | Elbit head-down displays in both cockpits (formats open) | inferred: radar, stores, NAV, TV, ADI, RWR | open: TSD, FLIR, damage, HARM |
| Kfir C7 | L radar; panel RWR dial | the System 82 4 in CRT; the SPS-200 3 in threat CRT | stores, TV, damage → the System 82 CRT; panel RWR → the SPS-200 | radar (the radar ranges only), TSD, FLIR, ADI, HARM; NAV open |
| Mirage IIICJ Shahak | L radar; RWR as a page | the Cyrano radar scope | radar → the Cyrano B-scope | stores, TSD, NAV, damage, TV, FLIR, ADI, HARM; RWR open |
| MiG-23ML | L radar | none (the radar picture is on the sight) | none (open: the MFD must not be blank) | open |
| MiG-29 9.12 | L radar, R RWR | the ИПВ head-down CRT; the SPO-15LM lamp unit; the Экран message line | radar → ИПВ; RWR → SPO-15LM; damage → Экран | stores, TSD, NAV, TV, FLIR, ADI, HARM, MENU |

## F-35I Adir: the panoramic cockpit display (PCD)

Built today (f35i.md §4.3, `game/cockpit/pcd.gd`): a status bar (ICAWS and its count, AP, the time), 4 portals that
hold the game's pages (radar, TSD, stores, RWR) tinted navy, 8 lower windows (FUEL, ENG, GEAR, ICAWS × 2, AP, CM,
CNI) and the ESIS (the standby display).

### Sources

| Source | What it gives | Pictures |
|---|---|---|
| Code One, "The New Front Office" (2006)[^codeone] | size, window splits, colour rules, black background | none useful |
| SLDinfo "The F-35 Cockpit" (2012), with LM's slides[^sld-cockpit][^lm-slides] | 4 portals + 8 secondary windows, 5 preset configurations, example layouts (slides 5–8) | slides: traceable layout blocks, low resolution |
| SLDinfo overview whitepaper[^sld-overview] | the TSD 10 × 7 in, up to 3 TSDs (2 shown at once), one symbol set | none |
| Skaff (LM), "Impact of Advanced Fusion…" (2013), quoted on a forum[^skaff] | track shapes and colours | none |
| Skaff, SAE 2010-01-2330[^sae] | holds a TSD graphic (per the forum) | open: paywalled, not read |
| Hush-Kit, an anonymous F-35 pilot (2021)[^hushkit] | the function bar always shows a fuel section; the FUEL page | none |
| Driven Technologies, simulated PCD for training simulators[^driven] | a populated PCD: function bar, 4 portals (TSD1, TFLIR, SMS, TSD3), sub-portal tabs; 2560 × 1024 px | traceable, but only 800 × 550 px |
| IndiaFoxtEcho F-35 user manual v1.2.2 (2023), a simulator manual[^ife] | function bar items, portal controls, format list, colours, per-format content | screenshots of every page (PDF pp. 32–53) |
| f-16.net "MFD pages details" (2015)[^f16net-pages] | the MENU format list read off LM simulator videos | none |
| The demonstrator photo (f35i.md §5) | the PCD with live content on dark blue backgrounds | traceable |

### Layout

- **Glass:** a 20 × 8 in touchscreen in two 10 × 8 in halves. A failed half's formats move to the other
  half[^codeone]. The pilot uses touch, cursor hooking (HOTAS) or voice[^sld-cockpit].
- **Splits:** 2 large (10 × 8 in), 4 medium (5 × 8 in), or a mix, down to 12 windows[^codeone]. The standard set is
  4 portals plus 8 smaller secondary windows along the bottom. The pilot programs 5 portal configurations in mission
  planning and changes them in flight by touch[^sld-cockpit]. LM's slide 7 shows 4 portals + 6 secondary windows;
  slide 8 shows 3 portals + 4 windows (a double-width TSD on the left, EOTS and SAR on the right)[^sld-cockpit].
- **Widths:** a quarter portal is 5 × 8 in. A format can widen over two portals (10 × 8 in, "half"), with the LEFT /
  RIGHT arrows[^codeone][^ife] (p. 35). A single format over the whole glass: open.
- **Sub-portals** (a simulator manual)[^ife] (pp. 33, 35): each portal is a main window with 2 sub-portals below it.
  Tapping a sub-portal swaps it with the main window. The DOWN arrow enlarges the main window and turns the
  sub-portals into tabs. The Driven picture shows the same: each portal ends in two cyan tabs (`TSD2 | WPN-A`,
  `TWD | EFI`, `TSD3 | BLANK`)[^driven]. Inferred: the real "8 secondary windows" are these sub-portals (4 × 2 = 8).
- **Function access buttons (the top bar):** "the FAB along the top of the display always has a small fuel
  section"[^hushkit]. A simulator manual gives the items left to right[^ife] (p. 34):
  - ENG: an RPM dial and the throttle; a yellow / black box in afterburner.
  - FUEL: gross weight, total / internal / external, light purple bars, white JOKER / BINGO marks.
  - WEAPONS: MRM / SRM / GUN / bomb counts.
  - FCS: a planform with 3 green gear lights.
  - ICAWS: the conditions on the left, the overall warning / caution on the right.
  - AP / AT, SWAP (mirrors the bar's halves), COM A / B / C, the NAV source (RTE / VOR / TACAN), MENU, IFF, BARO /
    cabin / GCAS / ALOW, the time (Z / L) and the wind.
  - Tapping an item opens its pop-up format in the portal below it, marked by a magenta "POP UP" in the corner.
  The Driven picture shows the same order up to MENU: a round engine dial, purple fuel bars, `2 MRM / … SRM /
  2 BOMB-C`, a green planform, `ICAWS`, `AP` over `AT`, a diamond `SW AP`, COM `A U 1 / B U 1 / C U 1`, `RECORDER`, a
  grid icon `MENU`, then the time, `CABIN`, `GCAS`, `ALOW`[^driven].
- **Portal header** (a simulator manual)[^ife] (p. 35)[^driven]: the format name over the master mode at the upper
  left (`TSD1` / `NAV`, `SMS` / `NAV`); tapping it opens the MENU grid. `CNTL>` at the upper right. Option legends in
  cyan down both edges.
- **Master modes:** NAV, A-A, A-S[^ife] (p. 36).
- **ESIS:** a separate 480 × 480 px standby display under the PCD[^driven] (built, f35i.md §4.3).

### Colours

- Symbology sits on "the absolute black of the display screen background". Green = good / advisory / friend;
  yellow = caution / unknown; red = warning / hostile; blue and magenta sparingly; grey outlines the maps and the
  aircraft planform[^codeone].
- A simulator manual adds: cyan = active (and the option legends), white = on / selected, magenta = off-board
  navigation, grey = an info box or unavailable, light purple = fuel[^ife] (p. 33).
- Ours paints the portals' background dark navy (`pcd.gd` `NAVY`), read off the demonstrator photo. Code One and the
  Driven picture are black. Inferred: the Real MFDs use black.

### Formats

The MENU list, read off LM simulator videos[^f16net-pages] and a simulator manual's menu[^ife] (p. 36), has 21
formats: ASR, CHKLST, CNI, DAS, DIM (DTM), EFI, ENG, FCS, FUEL, HUD, ICAWS, PHM, SMS, SRCH, TFLIR, TSD-1, TSD-2,
TSD-3, TWD, WPN-A, WPN-S. The radar's A-A page is SRCH and its A-S page ASR. The EOTS (the targeting sensor) "is
called TFLIR on the cockpit displays"[^baseline]. The threat format is TWD. MENU is the grid of formats.

| Format | What it shows | Evidence |
|---|---|---|
| TSD-1/2/3 | the fused picture (own sensors and datalink) as a plan view or a side view; range rings / compass rose, route, tracks; 3 independent copies, each with its own range; 10 × 7 in when large | [^sld-overview][^skaff]; a simulator manual[^ife] pp. 52–53; picture[^driven] |
| Track symbols | friend: green circle; suspect / unknown: yellow square; foe: red diamond. Air and ground threats differ in shape; a line from a symbol shows its direction of travel; "altitude is displayed in unambiguous fashion" | [^skaff][^codeone]; a forum (weak)[^f16net-ncoic] |
| Ownship | open. The Driven TSD1 draws a small cyan symbol at the rings' centre | [^driven] |
| SRCH | the A-A radar's azimuth / elevation search page | open (a forum's reading of blurry video)[^f16net-pages] |
| ASR | the A-S radar map / SAR image (a grey picture) | slide 8[^sld-cockpit]; a simulator manual[^ife] p. 37 |
| TFLIR | the EOTS infrared / TV picture with legends; NAV (forward) or A-S modes | [^baseline]; picture[^driven]; a simulator manual[^ife] p. 50 |
| DAS | the distributed aperture system's imagery (mainly used in the helmet) | [^sld-cockpit]; a simulator manual[^ife] p. 40 |
| SMS | a top-view planform with the bay and wing stations, the selected weapon, `NO WPN SELECTED`, master arm, CHAFF / FLARE counts, a DOORS control, and a front view of the stations below | picture[^driven]; a simulator manual[^ife] p. 49 |
| WPN-A / WPN-S | weapon status and programming, A-A and A-S | open (a forum's guess) |
| TWD | the threat warning display | open: no picture or description |
| FUEL | each tank's contents, the pumps running, fuel temperature, CG; the small version shows the basics | first-hand[^hushkit]; JOKER / BINGO and dump from a simulator manual[^ife] p. 45 |
| ENG | thrust %, EGT, nozzle, N1, N2, oil, fuel flow, hydraulics A / B; out-of-limit values in red | a simulator manual[^ife] p. 43 |
| ICAWS | the list of warnings (red), cautions (yellow) and advisories (green); BIT | colours[^codeone]; a simulator manual[^ife] p. 47 |
| EFI | an ADI over a partial HSI when large; one of them when small | a simulator manual[^ife] p. 42 |
| CNI | radios, navigation and IFF ("all radio … identification and navigation controls are on glass") | [^codeone]; a simulator manual[^ife] |
| AP | a pop-up from the function bar: the AP / AT state and modes | a simulator manual[^ife] p. 34 |
| FCS, PHM, CHKLST, DIM, HUD | control surfaces and gear; health; checklists; data transfer; a HUD repeat | a simulator manual[^ife] |

### Game page → real format

| Game page | Real format | Driven by (game state) |
|---|---|---|
| 3 TSD | TSD-1 (plan view) | ownship position and heading, the waypoints and route, radar and AWACS contacts by side (green circle / yellow square / red diamond; "unknown" = a contact not yet identified, inferred), the mission's SAM sites as threat rings (inferred; the ring graphics are open), the range scale |
| 2 radar A-A | SRCH (layout open; inferred: an azimuth / range B-scope like the F-16's) | `IafRadar` contacts, scan, lock, sub-mode |
| 2 radar A-G | ASR (a grey map) | the game's ground-map radar picture |
| 1 stores | SMS (with WPN-A / WPN-S) | `IafStores` stations A–I → planform stations 1–11 (f35i.md §3.1), bay door state, chaff / flare, master arm |
| 7 RWR | TWD (graphics open) | `IafRwr` contacts; inferred alternative: the threats on the TSD |
| 6 FLIR, 5 TV | TFLIR | the `IafEo` camera; the EOTS stands in for the pod |
| 4 damage | ICAWS (with PHM) | the damage flags (damage.md §5.2) → warning and caution lines |
| 9 ADI | EFI | attitude, heading, ILS deviation |
| 8 MENU | the MENU grid of the 21 formats | page selection |
| 10 HARM | not offered: the F-35I carries no HARM | — |
| 0 NAV | not offered: the route is on the TSD, the steerpoint in the CNI / NAV pop-up (inferred) | — |
| — (new) | FUEL, ENG, FCS, AP, CNI in the function bar and the sub-portals | fuel, RPM / throttle / afterburner, gear / flaps, autopilot mode, heading / speed |

### What the real PCD needs beyond ours

1. The function bar as the real one (engine dial, fuel bars with JOKER / BINGO, weapon counts, gear planform, ICAWS,
   AP / AT, COM, NAV source, MENU, IFF, BARO / GCAS / ALOW, time). Ours has 3 of its items.
2. The portal chrome: name and master mode at the upper left, `CNTL>`, cyan edge legends, 2 sub-portal tabs per
   portal. The lower 8 windows become the sub-portals (inferred).
3. A black background in place of navy.
4. The real formats in place of the F-16 pages: TSD-1 with F-35 symbology, SRCH / ASR, the SMS planform, TFLIR, TWD,
   EFI; ENG and FUEL as full formats; ICAWS as a format.
5. A double-width TSD, as in LM's slide 8 (inferred: a good default layout).

## F-16C/D Barak (Block 30/40)

Main source: the Hellenic AF F-16C/D Block 50 avionics manual (the dash-34, 1997)[^dash34]. It is a scan with no text
layer, but every MFD figure is a clean black line drawing that can be traced. Page "1-N" is PDF page N + 16 (for
example 1-62 is PDF page 78), as in real-hud.md. The MLU M1 pilot's guide[^mlu1] adds FCR and HSD figures, with
colour symbology from a later tape. Flight manuals[^haf1][^usaf1] and a tactics manual[^rokaf] give the cockpit keys
and the TEST page in text only.

**Era (inferred).** The dash-34 describes a 1997 Block 50 tape. The IAF Block 30 (1987) and Block 40 (1991) used
older tapes of the same display set: the same 4 × 4 in monochrome MFDs, 20 OSBs, and the FCR / SMS / WPN / TGP / TEST
formats. Some Block 50 features may be later than the Barak: the HSD (its first tape is open), AIM-120 symbols, the
AIFF (advanced IFF) symbols (real-hud.md rules AIFF out for the Barak), HARM (AGM-88) and the bullseye. The text marks
each one. The F-16I Sufa's colour MFDs belong to the Sufa option ([f16i.md](f16i.md)).

### Common frame: OSBs, rockers, format labels, colours

**OSB numbering** (fig. 1-26 "MFD Symbology and Power Controls", p. 1-60)[^dash34]:
- 20 OSBs, 5 per side, numbered clockwise from the top left:
  - top row, left to right: OSB 1–5
  - right column, top to bottom: OSB 6–10
  - bottom row, right to left: OSB 11–15 (OSB 11 is bottom right, 15 bottom left)
  - left column, bottom to top: OSB 16–20 (OSB 20 is top left)
- A rocker switch at each corner: GAIN (top left), SYM (top right), BRT (bottom left), CON (bottom right). Their
  labels are printed on the bezel.
- "In general, the OSB's at the bottom … control the selection of display formats while the OSB's at the top select
  sensor modes. The OSB's at the sides … control functions unique to the selected format/mode."
- "The mnemonic adjacent to a specific OSB flashes when the OSB is depressed" (p. 1-60).

**Bottom row, on every format** (fig. 1-43 "Basic MFD Display", p. 1-81; text p. 1-63):
- OSB 15 `SWAP` swaps the left and right MFD.
- OSB 14, 13 and 12 are the three formats assigned to this MFD. The primary one is highlighted (an inverse box); the
  other two are the secondary formats. An empty slot shows no mnemonic (the BLANK format).
- OSB 11 is `DCLT` (declutter: it removes the labels on the left, top and right edges; the OSBs still work). On the
  SMS format OSB 11 reads `S-J` (selective jettison).
- Pressing the primary format's OSB opens the format menu.
- The DMS (display management switch), left or right, steps the primary format on that MFD.
- Each MFD holds 3 formats (6 across both). A format shows on one MFD at a time, except BLANK.

**On most formats** (fig. 1-43): the airplane reference symbol (a small "W") and the steering bars at the lower left;
the horizon line; and the SOI symbol. A format that isn't the SOI shows "NOT SOI" near the centre (p. 1-119,
fig. 1-77).

**Format menu** (fig. 1-29 "Display Format Selection", p. 1-64; fig. 1-43; text p. 1-81):
- Ten formats plus BLANK:
  - left column: `FCR`, `TGP`, `WPN`, `TFR`, `FLIR` (FCR on OSB 20, FLIR on OSB 16; inferred from the drawing)
  - right column: `SMS`, `HSD`, `DTE`, `TEST`, `FLCS`
  - top: `BLANK` at the left, `RESET MENU` at the right (OSB 5, p. 1-63), `PROG DCLT RST` at the top left
    (fig. 1-29).
- The current format is highlighted.
- RESET MENU page (fig. 1-30, p. 1-63, text only): OSB 6 / 7 SBC DAY / NIGHT RESET; OSB 8 SBC DFLT RESET; OSB 9 / 10
  SBC DAY / NIGHT SET; OSB 19 PROG DCLT RESET; OSB 20 MSMD RESET.

**Steps and data entry** (p. 1-76; figs. 1-39..1-42, pp. 1-77..1-80):
- Up and down triangles (one step) or arrowheads (held, continuous) sit next to a pair of OSBs, for example the range
  scale.
- The data entry page (fig. 1-42, p. 1-80): digits 1–5 on the left OSBs and 6, 7, 8, 9, 0 on the right; `ENTR RTN
  RCL` across the top; a prompt in the centre (e.g. "ENTER RELEASE PULSES") with the value between two highlighted
  asterisks.

**Colours and font:**
- Green on black. "Symbols that were not colorized remain green as they appear on typical F-16 monochromatic
  displays" (MLU M1 p. 19, table 1-1)[^mlu1]. The MLU's colour HSD / FCR is a 1998 tape for the European F-16A/B,
  out of era.
- Highlight: an inverse-video box around the mnemonic.
- Font: a stroke sans-serif in capitals; its size is open. For 132 px, a 5 × 7 capital font gives about 18 characters
  across (inferred).

**Game frame (inferred).** The game's 132 × 132 MFD has its own button rows (mfd.md §1). The real frame needs 5 OSB
label places per side. How the game's buttons 0xb..0x14 map onto the real OSB numbers is open until the cockpit's
button layout is compared. The real convention: format selection at the bottom, sensor modes at the top. The game's
MENU page becomes the real format menu.

### FCR (fire-control radar): game page 2

**Modes** (p. 1-118): STBY, ACM, and CRM with its submodes RWS / LRS / VSR / TWS; the ground modes GM, GMT, SEA, BCN,
AGR. OSB 1 shows the mode; pressing it opens the mode menu (fig. 1-77, p. 1-120): A-A `CRM`, `ACM`, `STBY`; A-G `GM`,
`GMT`, `SEA`, `BCN`, `STBY`; NAV gets the full menu.

**Top row in CRM** (figs. 1-84, 1-85, pp. 1-130, 1-132): OSB 1 `CRM`; OSB 2 `RWS` / `LRS` / `VSR` / `TWS` (the
submode); OSB 3 `NORM` / `EXP` (field of view); OSB 4 `OVRD` (override: radiate off); OSB 5 `CNTL` (the control
page).

**Left edge, top to bottom** (fig. 1-85; pp. 1-122, 1-125):
- The range scale: the number (e.g. `20`) with up / down triangles on OSB 20 / 19. RWS ranges: 160 (RWS / VSR only),
  80, 40, 20, 10 NM.
- OSB 18: the azimuth scan, `A` over a digit: 6 = ±60°, 3 = ±30°, 2 = ±25° (TWS only), 1 = ±10°.
- OSB 17: the elevation bars, `B` over a digit: 1, 2, 3 (TWS only) or 4.
- Bottom left: the bullseye bearing / range (e.g. "045 10"); open for the Barak. The AIFF status below it is out of
  era.

**Control page `CNTL`** (fig. 1-76, p. 1-116; pp. 1-117..1-118): right edge OSB 6 CHAN 1–4, OSB 7 MK INT 1–4, OSB 8
BAND WIDE / NARO, OSB 9 BCN DLY, OSB 10 PM ON / OFF; left edge OSB 20 MTR HI / LO (moving target reject), OSB 19 ALT
TRK ON / OFF, OSB 18 TGT HIS 1–4 (target history, default 3), OSB 17 LVL.

**Scope** (a B-scope; pp. 1-122..1-125):
- Range ticks: 3 marks on the right edge, each a quarter of the range scale (p. 1-122).
- Antenna azimuth: a T-shaped marker on the bottom edge, −60° at the left and +60° at the right. Seven fixed tics in
  the centre at 10° steps up to ±30°. Two vertical scan lines show the scan limits in search, TWS and SAM (p. 1-125).
- Antenna elevation: a horizontal T caret on the left edge, +60° at the top and −60° at the bottom; seven tics, the
  upper one +30°, the centre 0°, the lower −30°.
- Acquisition cursor: two short parallel vertical lines (p. 1-124), with the max and min search altitude in kft
  beside it, e.g. `25` / `10` (fig. 1-85).
- Horizon line: a broken horizontal line with end ticks (fig. 1-85).
- Steerpoint: a filled triangle at the steerpoint's range and bearing (p. 1-124).
- Bullseye: a ring with a dot (fig. 1-81).
- Reacquisition elevation symbol: on the left scale for 10 s after a track is lost (p. 1-124).
- Altitude line tracker: a horizontal "Y" on the range scale (p. 1-125; OSB 19 on CNTL).

**Target symbols** (pp. 1-122..1-123; figs. 1-28, 1-80):
- Search target: a small solid square. Up to 3 history frames are drawn dimmer (TGT HIS, p. 1-134).
- Track or bugged (designated) target: an open triangle inside a circle.
- TWS track file: an open triangle; up to 10 of them, and only the bugged target is circled.
- The triangle turns in 22.5° steps to show the target's aspect / heading (p. 1-122). A line from its nose grows with
  the target's speed (fig. 1-28: MIN and MAX VELOCITY).
- The altitude shows under the symbol as 2 digits in kft.
- A TWS track flashes 8 s before the radar drops it, and extrapolates for 13 s (p. 1-140).
- AIM-120 additions (a tail, an X at impact, "LOSE") are out of era. Fig. 1-28 (p. 1-62) also draws a "NEXT-TO-SHOOT"
  circle (open for the Barak).

**STT data line**, under the mode row from the left (figs. 1-84 / 1-85 / 1-93; pp. 1-130..1-131):

| Field | Example | Content |
|---|---|---|
| Aspect angle | `15L` | tens of degrees, plus L or R |
| Target ground track | `210°` | to the nearest degree, shown in 10° steps |
| Raid cluster | `2` | count |
| Calibrated airspeed | `450` | 10 kt steps |
| Closure | `+700K` | rate in knots |

Intercept steering: a small thick "+" at the target's range, moved in azimuth to give collision steering; drawn only
within ±60° (fig. 1-84).

**Range scale** (pp. 1-122, 1-131): bumping the cursor below 5 % or above 95 % of the scale steps it down or up. The
scale also steps by itself: in SAM and TWS up when the target is beyond 90 % of the scale; in TWS down when it is
closer than 45 %; in STT down below 40 % and up above 95 %.

**ACM** (fig. 1-89, p. 1-136; p. 1-131): the RWS display with the range fixed at 10 NM, no acquisition cursor, and no
targets until lock. OSB 2 shows the scan pattern: `20` (30° × 20°), `60` (10° × 60°), `SLEW`, `BORE`.

**TWS** (fig. 1-93, p. 1-140; p. 1-139): the range starts at 40 NM (10, 20, 40, 80). Scans: ±10° / 4 bars, ±25° /
3 bars, ±60° / 2 bars. `EXP` gives a 4:1 expansion about the bugged target with a 2 NM box (p. 1-140).

**VSR** (fig. 1-92, p. 1-139) adds velocity marks on the right edge.

**Coverage:** fig. 1-86 (p. 1-133) gives the RWS / TWS elevation coverage in kft per range and bar count, and the
azimuth coverage in NM.

**A-G modes:**
- GM (fig. 1-97, p. 1-147; pp. 1-142..1-150):
  - Top row `GM MAN NORM OVRD CNTL`. MAN is the range-scale option; OSB 3 steps NORM / EXP / DBS1 / DBS2 (DBS =
    doppler beam sharpening).
  - Left edge: a gain gauge at the top left, then the range 80 / 40 / 20 / 10 with up / down arrows.
  - The map is a PPI fan with range arcs: 10 NM range, 1 arc at 5 NM; 20 NM, 3 arcs 5 NM apart; 40 NM, 3 arcs 10 NM
    apart; 80 NM, 3 arcs 20 NM apart.
  - Cursors: a horizontal and a vertical line (the "X-Y cursors") with 4 expansion cues.
  - Right edge, written vertically: OSB 7 `FZ` (freeze), OSB 8 `SP` (snowplow), OSB 9 `CZ` (cursor zero), OSB 10
    `STP` / `TGT`.
  - Bottom right: the time to go, e.g. `00:29`.
  - A tracked ground target is a solid diamond at the cursor crossing, and the video around it is blanked (p. 1-146).
  - EXP or DBS adds a thin "+" where the cursors would be in NORM, and a ¼-mile (1500 ft) yardstick at the top left.
- GMT (p. 1-150): GM with ranges 10, 20 and 40 only and no DBS. Moving targets show as bright symbols on a dimmed map;
  a track shows a diamond.
- SEA (fig. 1-100, p. 1-151): GM without DBS.

**Driven by** (inferred; the fields from mfd.md §3 "Radar (2)"):

| Real element | Game state |
|---|---|
| Target symbols | contacts (up to 15): searched → square, tracked → triangle, locked → triangle in a circle; altitude → 2-digit kft; aspect → the triangle's rotation in 22.5° steps; speed → the velocity line and the CAS; azimuth / range → the B-scope place |
| Mode and submode | sub-mode `state+0xa04`: LRS → CRM `LRS` (or `RWS`), TWS → `TWS`, STT → the STT layout, ACM / BORE → ACM `20` / `BORE`, GMT → GMT, MAP → GM |
| Range scale | `state+0xa08`: the game's 5..160 NM onto the real 10..160 NM (5 NM has no real step: open; clamping to 10 is inferred) |
| Antenna carets | `state+0xa0c` / `+0xa10` |
| Steerpoint triangle | the current waypoint |
| Horizon | roll, pitch |
| DLZ | the missile envelope, on the right edge in A-A missile modes (fig. 1-27 "DYNAMIC LAUNCH ZONE") |
| GM map | the game's isr.bmp ground picture |

The game has no state for the bullseye, AIFF, AIM-120 tails, the CNTL page, target history or the altitude tracker:
draw them static or leave them out (inferred).

### SMS (stores management): game page 1

**Inventory `INV`** (figs. 1-48, 1-49, pp. 1-86..1-87):
- The stations form an inverted V: station 1 at the lower left, station 5 at the top centre, station 9 at the lower
  right.
- Each station shows its rack and its store on two lines, e.g. `1 MAU` / `1 TK300`, `1 TER` / `2 BD33T`.
- An empty station shows one dashed line per possible store or rack.
- Gun: `GUN` with the rounds left in tens, e.g. `51GUN`, and the ammunition type `M56`, next to OSB 20.
- Top row: the mode (`STBY`, `AAM` …) at the top left, `RCL` on OSB 2, `INV` on OSB 4 (highlighted), `CLR` on OSB 5;
  `CHNG` on OSB 6.
- `HUNG STORE` at the bottom centre.

**A-A gun page** (fig. 1-65, p. 1-102): top row `GUN`, `EEGS` (or LCOS), `INV`; left edge `SCOR OFF`; right edge
`51GUN`; the gun status `RDY` / `SIM` / `SAF` / blank in the centre and at the bottom centre.

**A-A missile page** (fig. 1-66, p. 1-102):
- Top row `AAM`, `SPOT` / `SCAN`, `INV`.
- Left edge `BORE` / `SLAVE`, then `BP` / `TD`.
- Right edge: the count and type, e.g. `4A-9LM` (4 × AIM-9L/M), and `COOL` / `WARM`.
- Bottom row: the other missile types loaded (`1 2 M`) at the left; the missile stations (`M 8 9`) at the right, the
  selected one boxed.
- Status `REL` / `RDY` / `MAL` / `SIM` / blank.

**A-G pages** (fig. 1-70, p. 1-108; fig. 1-71, p. 1-109):
- Top row: OSB 1 `A-G`; OSB 2 the submode (`CCRP`; menu `CCIP CCRP DTOS LADD MAN`); OSB 4 `INV`; OSB 5 `CNTL`.
- Left edge: `RBS` (radar bomb scoring), then `NSTL` / `NOSE` / `TAIL` (fuzing).
- Right edge: OSB 6 the count and weapon (e.g. `6M82`); OSB 7 `PROF1` / `PROF2`; OSB 8 `2PAIR` / `SGL`; OSB 9 `50FT`
  (release interval); OSB 10 `RP` / `2` (release pulses).
- `RDY` next to the weapon and above OSB 13 (p. 1-109).
- A-G gun: `GUN STRF INV`, `51GUN`.

**Master modes:** NAV (shows INV), A-A (MSL; DGFT and MSL override from the throttle), A-G (pp. 1-86, 1-119).

**Driven by** (inferred):
- The game's 9 stations (0x1c-byte records {type, count, name} at `state+0x3a8`) → stations 1..9; the two text lines
  ← count and name. The order of game stations 0..8 against the real left-to-right numbering is open (the game's
  position table puts st0 at the lower left and st3..5 across the top).
- Quantity (1..14) → `RP`; interval (10..200) → the release interval in feet (the game's unit is open).
- The game's A-A / A-G selection → the AAM / A-G pages. Gun rounds → `ftol(rounds/10)` + `GUN`.
- Fuel (on the game's stores page) has no SMS field; the F-16 shows fuel on a gauge and the DED. Inferred: leave it
  out, or put it at the bottom centre.

### HSD (horizontal situation display): game page 3

**Base page** (fig. 1-45 "Horizontal Situation Display (HSD) (Typical)", p. 1-82; pp. 1-82..1-83):
- Depressed view: the ownship sits ¼ of the way up from the bottom. The centred view is an MLU feature[^mlu1], out of
  era.
- Three range rings around the ownship, always shown:

  | Range scale | Ring spacing |
  |---|---|
  | 15 NM | 5 NM |
  | 30 NM | 10 NM |
  | 60 NM | 20 NM |
  | 120 NM | 40 NM |

  The scale stops at its ends. Its number and up / down triangles are on the left (OSB 20 / 19 in the figure;
  inferred).
- A magnetic north tic.
- The route: the past steerpoint, the current one (a circle) and the next two, as lines through steerpoints 1–25.
  NAV1 on CNTL toggles the route.
- Also: the A-A and A-G ghost cursors; the radar's scan as a pie wedge (the sensor volume); data-link threats; LINE1
  (steerpoints 16–20, solid) and LINE2 (steerpoints 21–25, dashed); the bullseye, with its bearing and range at the
  bottom left.
- `CNTL` on OSB 5. The CNTL page (fig. 1-46, p. 1-83): `DLNK`, `NAV1`, `LINE1`, `LINE2` and others.

**Threat rings:** the dash-34 base page has none. Preplanned threat circles are on the MLU HSD (figs.
1-18..1-19)[^mlu1]; for the Barak they are open, and drawing them from the game's SAM list is inferred.

**Driven by** (inferred):
- Waypoints (`state+0x7c..`, current `+0x320`) → the route and the current steerpoint circle.
- The game's TSD scales {10, 20, 40, 80} → the real {15, 30, 60, 120}. The rings are fixed, so the game's SCL ring
  goes.
- The game draws heading-up with the ownship at (65,85), 0.64 of the way down: already near "¼ up from the bottom".
- The radar's azimuth scan and range → the sensor volume wedge.
- The map EMF (map.emf) has no real counterpart: left out.

### WPN and TGP: game pages 5 (TV) and 6 (FLIR)

**WPN, AGM-65 Maverick video** (fig. 1-75 "EO WPN Page", p. 1-113):
- Top row: `OPER` (power OFF / STBY / OPER), `VIS` / `PRE` / `BORE` (the EO submode), `FOV`, `HOC` / `COH` / `AREA`
  (track polarity for the 65D/G; 65A/B use `BOW` / `WOB` / `AUTO`).
- Left edge: `BSGT` (boresight).
- Right edge: the count and type at the top (e.g. `4 AG65D`); the MLE (missile launch envelope) scale with `RMAX` and
  `RMIN` ticks and a caret for the range to the target.
- Centre: a fixed cross and four corner brackets (the track gate).
- Bottom: `RDY` and a time, e.g. `000:12`.
- `NOT TIMED OUT` for the first 3 minutes of EO warm-up; `WPN OFF` at the bottom centre when the weapon is off; `NOT
  SOI` at the centre.

**TGP, the LANTIRN targeting pod** (pp. 1-217..1-240; fig. 1-163 "Targeting Pod Standby Mode", p. 1-234; fig. 1-164,
p. 1-235):
- Top row: `STBY` / `A-A` / `A-G`, `WIDE` / `NARO` (FOV), `OVRD`, `CNTL`.
- Right edge: `WHOT` / `BHOT` (polarity), `CZ`.
- Left edge, top to bottom: the FLIR gain caret with `99G`, `GRAY`, `OFF`, `MGC` / `AGC`, `40L` (the level).
- `NOT TIMED OUT` while the detector cools.
- Bottom right: the time to steerpoint / release / impact. `L` (laser) or `T` (passive) before the range.
- A box frames the page when the TGP is the SOI.
- The TGP came with the LANTIRN on the Block 40 (inferred: the Block 30 had none).

The FLIR format (the LANTIRN navigation pod's picture, pp. 1-241..1-249) is open: its layout was not traced.

**Driven by** (inferred): TV page → WPN: the camera picture under the cross and gate, the count and type from the
selected store, `RDY` from the release state; the EO lock closes the gate on the target. FLIR page → TGP: the same
picture, WHOT by default.

### HAS (HARM as sensor): game page 10

**POS base page** (fig. 1-296 "AGM-88 Weapon Base Page – POS Submode", p. 1-458; pp. 1-457..1-460):
- Top row: `POS` / `HAS` / `DL` (modes), `TBL1..3` (threat table), `EOM` / `RUK` / `PB` (submodes), `UFC`.
- Left edge: the threat types in the table (e.g. `10`, `12`) and `MN1` (manual threat).
- In the field: the selected threat type and a boxed threat location (steerpoints 21–25); TOF (time of flight) / TOT
  (time on target) before launch; TUI (time until impact), lock-on type and threat type after launch.
- Bottom: the loaded stations, the selected one boxed (`3`, `7`).

**HAS** (figs. 1-297 / 1-298, p. 1-461; p. 1-460):
- Top row `HAS TBL1 WIDE SRCH UFC`. Under it, a detected-threat status box lists the threat numbers, e.g. `6 4 10`.
- The centre is the missile's boresight view: a horizontal line (zero pitch / roll) and a vertical line (boresight).
- Each detected threat is a number with an ID letter (e.g. `10T`, `6A`), placed by azimuth and elevation; at most 5.
- After handoff the threat is boxed and highlighted, and the weapon shows `RDY`.
- The left edge holds the threat table entries (`6`, `4`, `10`, `12`, `MN1`); `DR` above the table means degraded
  against that type.

**Era:** this HARM page is a Block 50 feature; no source puts the AGM-88 on the IAF Block 30/40 (open). The game's
HARM list (targets inside ±15°, mfd.md §3 "HARM") maps onto the HAS display: azimuth across, each target's type
number, the selected target boxed with `RDY` (inferred).

### TEST (fault list): game page 4

The F-16 has no GO / NOGO page. Faults go to the PFL (pilot fault list) on the DED (dash-34 pp. 1-475..1-518), and to
the MFL (maintenance fault list) on the MFD TEST format (p. 1-470 on; "MFL's present on the MFD test page"[^haf1]).
Inferred: the damage page draws as the TEST format's fault list. Its layout (the MFL figures from PDF page 486) is
open.

### Not offered on the F-16

- **NAV (0):** the steerpoints are on the DED (the STPT page and the ICP keypad[^haf1]); the MFD shows the route on
  the HSD.
- **ADI (9):** the F-16 has a mechanical ADI; the MFD's attitude cues are the horizon line and steering bars on every
  format. The game never shows page 9 on the F-16 (mfd.md §3).
- **RWR (7):** the RWR is a round indicator on the glare shield ("THREAT WARNING Azimuth Indicator"[^usaf1]), the
  game's panel dial. The game shows no RWR page on the F-16.

### The threat azimuth indicator (the panel RWR dial)

The dash-34 shows the HAF jet's RWR display (figs. 1-132..1-136, pp. 1-199..1-203) without naming the set; a
simulator forum reads it as the ALR-93[^bmsforum] (open). Which RWR the IAF Block 30/40 carried is open; this is the
nearest primary layout.

**Display** (p. 1-199, fig. 1-132):
- A round scope with an ownship "+" in the centre; an inner ring at 25 NM and the edge at 50 NM (the maximum
  detectable range).
- Threats sit at their range estimated from the received power; beyond 50 NM on the edge.
- Separation: the highest-priority threat stays at its true place; threats too close to it move outward, then
  counter-clockwise along the edge.
- 12 radial ticks at 30° around the edge (from the figure).
- Two `MA` (missile activity) lights at the top left, for night and day; a `BRIL` knob and a NIGHT / DAY switch.

**Symbols** (fig. 1-133, p. 1-200; fig. 1-134, p. 1-201):

| Symbol | Meaning |
|---|---|
| a diamond around a symbol | the highest-priority threat (one at a time) |
| a square around | a lethal threat (within lethal range) |
| a circle around | a missile launch (it replaces the square) |
| a digit with an arrow on its left (`/2`, `/6`, `/H`) | a SAM type, e.g. 2 = SA-2 |
| a small box with a digit (a gun-mount shape) | AAA, the type inside |
| a "wingform" hat over a number (16 = F-16) | an air-to-air threat |
| a T shape with a digit on its right | a search radar |
| 2 digits (PRI class, band), e.g. `14` | an unknown emitter (fig. 1-135 tables) |
| `CW3` | an unknown CW (continuous-wave) emitter |
| chevrons `>6<` | jam request (flashing) or jamming (steady) |
| a chevron under a symbol | dispense request or dispensing |

The ALR-69 (the MLU's EWPI, fig. 7-3, p. 209)[^mlu1]: PRI mode shows the 5 highest-priority threats, open mode up to
16; a red ML (missile launch) light flashes at 3 Hz with a flashing symbol and a launch tone; `SEP` and `UNK`
buttons.

**Driven by** (inferred; the emitters in rwr.md): bearing → angle; strength / range → radius (inner ring = 25 NM);
class → SAM digit / AAA box / wingform; lock → the lethal square; launch → the circle and a flashing `MA`; the top
threat → the diamond. This dial is a panel instrument, outside the MFDs.

## F-15C/D Baz

### Displays

All IAF Baz A/B/C/D airframes (the C/D are FY80/83) predate the MSIP cut-in at F-15C 84-0001 / F-15D
84-0042[^f15-1]. Their head-down displays:

| Real display | Kind | Where | Game page (decision) | Game MFD |
|---|---|---|---|---|
| VSD (vertical situation display) | a monochrome radar CRT, square face, no option buttons; bezel knobs and a BIT button[^dcs-f15] (fig. 21, p. 36); by Honeywell[^baugher-f15] | upper left | radar (2); TV (5): "the video for TV weapons" shows on the VSD (TO 1F-15A-1 p. 1-82)[^f15-1] | Left |
| TEWS display (the ALR-56 threat display) | a round CRT in a square bezel, "TEWS" label and BIT button[^dcs-f15] (fig. 22, p. 36) | upper right | RWR (7) | Right |
| HSI | an electromechanical compass card, by Collins[^baugher-f15] | centre, below the ADI | TSD (3) | Middle |
| ADI | an electromechanical ball | centre, below the HUD | ADI (9) | open (see below) |
| Armament control panel | switches and weapon status lights[^f15-1] (foldout) | lower left | stores (1): open | — |
| MPCD (multi-purpose colour display) | a true MFD with 20 buttons, MSIP jets only (TO 1F-15A-1 pp. 1-59/1-60, fig. 1-11C)[^f15-1] | lower left | stores (1): open | — |
| Caution lights panel | lights | right | — | — |

IAF's own upgrade, Baz Meshopar (from 1995), added three Elbit MFDs whose formats are not public[^twz-baz]. A 2024
IAF photo shows a later portrait colour centre MFD and an Astronautics up-front control display[^twz-baz]. Both are
out of the game's era; the Real MFDs Baz is the original US cockpit (inferred).

No public primary document gives the VSD or TEWS symbology: TO 1F-15A-1 refers to the dash-34 (TO 1F-15A/C-34-1-1)
for the radar, VSD, TEWS and IFF (pp. 1-80/1-81)[^f15-1], and the dash-34 is not public. The layouts below come from
two simulator manuals[^bms-f15][^dcs-f15]. Both describe a later F-15C (APG-63(V)1, ALR-56C, alphanumeric threat
codes).

Not offered on the F-15 (first decision): NAV, damage, FLIR, HARM (the F-15A/C has no FLIR or HARM) and MENU (the
real menu is on the MSIP MPCD only). The stores page is open.

### VSD (radar and TV): game pages 2 and 5

The VSD shows "the IFF confidence symbols, the video for TV weapons, and aircraft flight status symbology"
(TO 1F-15A-1 p. 1-82; the rear VSD repeats the front)[^f15-1]. It also shows the BIT matrix (fig. 1-11A) and the
overload warning (fig. 1-10A)[^f15-1]. TV video replaces the radar picture.

**Format:** a B-scope, green on black, square face. Pages from a simulator manual[^bms-f15] (§8 pp. 43–45, radar §9
pp. 55, 63, IFF §16 p. 83) unless marked.

| Element | Layout | Driven by |
|---|---|---|
| Grid | 3 vertical lines (0°, ±30° of a ±60° field) and 3 horizontal range lines (about ¼, ½, ¾; from the figure) (p. 43) | the radar's azimuth limits |
| Range scale | the number at the top right (`80`); 10 / 20 / 40 / 80 / 160 NM; changed by bumping the acquisition symbol over the top or bottom edge (p. 45, §8.1.4) | the radar range |
| Azimuth scan | 20° or 120° (p. 45); scan-limit ticks along the bottom edge (p. 43); the antenna azimuth caret on the bottom edge | the scan width, antenna azimuth |
| Elevation | the antenna elevation caret `<` on the left edge; the altitude coverage in kft with a small circle, top (`46`) and bottom (`-4`) of the left edge (p. 43) | antenna elevation and range → coverage (inferred) |
| Acquisition symbol | two short vertical bars, moved by the TDC (p. 43) | the radar cursor |
| Destination | a triangle at the steerpoint's range and bearing, the waypoint number under it (`3`) (pp. 43, 45) | the current waypoint |
| Horizon line | a line across with a gap in the centre, rolling with bank (p. 45; TO 1F-15A-1 p. 1-82) | roll, pitch |
| Search hits | small filled rectangles; full brightness on the current bar, half when aged (p. 44) | contacts in search |
| TWS track | a small filled square with a short heading vector (p. 44) | contact heading |
| Secondary designated target | a hollow square with a medium vector (p. 44) | the second target |
| Primary designated target / STT lock | a hollow square with a long heading vector (p. 63); on the A-A designated format a star marks it (p. 45) | the lock |
| Angle-only jam | a strobe (p. 44) | a jamming contact (if modelled) |
| Window 1 (top) | the locked target's true airspeed, aspect and heading, e.g. `440 18L 190` (p. 45) | the lock's speed, aspect, heading |
| Window 4 (left edge, middle) | the target's altitude in thousands-hundreds: `21-6` = 21,600 ft (p. 45) | the lock's height |
| Window 2 (right edge) | closure `1160>` beside the range caret (p. 45) | closure |
| Launch scale (right edge) | RAERO, ROPT, RPI, RTR, RMIN marks, the range caret `>`, the loft angle `10°` (p. 45) | the missile envelope |
| ASE circle | a centre circle with a steering dot (p. 45) | the MRM sight |
| Window 3 (bottom) | `G 602` ground speed; the cursor's bullseye bearing-range `357-25`; the missile time of flight `74SEC`; `T 503` true airspeed (p. 45) | own speeds, cursor |
| BIT window (bottom left) | bar scan and PRF, `1 MED` / `1HIGH` (pp. 43, 45) | the radar bars (PRF inferred) |
| IFF | a circle = a high-confidence mode-4 reply; a diamond = low confidence; at the reply's range and azimuth (p. 83; real-hud.md "IFF") | the contact's `hostile` flag and the interrogate key |
| A-G | open (not in the simulator manual) | — |

- The VSD has no option buttons: the radar is run from the radar control panel and the HOTAS. Inferred: clicks on the
  game's MFD step the range at the top and bottom edges and the scan width at the left and right edges, like
  bumping the acquisition symbol over an edge.
- Era (inferred): for a 1990s Baz, leave out the bullseye, the AMRAAM time of flight and the aircraft ID.
- Pictures to trace: the simulator manual's pp. 43–45 (clean labelled renders); DCS fig. 21.

### TEWS display (RWR): game page 7

TEWS is classified; the flight manual refers to TO 1F-15A-34-1-1-1[^f15-1]. The layout comes from two simulator
manuals: DCS pp. 76–80, figs. 22, 62–64, table 9-5[^dcs-f15], and BMS §14.2, pp. 70–71[^bms-f15]. Pages below are
DCS's.

| Element | Layout | Driven by |
|---|---|---|
| Face | a round CRT; an outer ring of 12 ticks (every 30°); an inner ring; a `+` ownship cross at the centre (fig. 22, p. 36) | — |
| Emitter place | bearing around the centre; distance from the centre shows signal strength (stronger = nearer the centre); early-warning radars and AWACS never in the inner ring; up to 16 threats; 7 s history (p. 77) | the emitters' bearing and power / lethality |
| Symbols | alphanumeric type codes (`29`, `23`, `15`, `F4`, `E3`, SAM codes); airborne radars carry a `^` hat (p. 80) | the emitter's type code, ground or air |
| New threat | a half-circle above the symbol (pp. 77–80) | the emitter's age |
| Primary threat | a diamond around the symbol | the top-priority emitter |
| Launch | a flashing circle; an active-radar missile shows as an `M` in the inner ring, half way to the shooter (p. 79) | the launch / guide state |
| ECM status | an open `X` at the centre: flashing = standby, steady = active (fig. 62, p. 76) | left out (no ECM state) |
| Colour | green on black (fig. 22) | — |

The codes are the ALR-56C (MSIP) / ALR-56M style (BMS p. 71). A pre-MSIP F-15A/C carried the ALR-56(A), whose symbol
set is open. Inferred: the same scheme, as the game's RWR page already uses (rwr.md).

### HSI on the middle MFD: game page 3

- TO 1F-15A-1 pp. 1-61/1-62, fig. 1-12[^f15-1]: an aircraft symbol over a turning compass card, the heading under
  the lubber line, index marks every 45°. Modes NAV / TCN / ILS-NAV / ILS-TCN (the steering mode panel, fig. 1-13).
- Inferred, from the usual HSI: a course / bearing pointer, a range counter (NM), a course deviation bar.
- Driven by: heading; the current waypoint's bearing and distance (the waypoint records of `FUN_004459f0`, mfd.md §3
  NAV); the course to it.

### ADI: game page 9

The real ADI ball: 5° pitch marks, 10° bank marks (larger every 30°), the bank steering bar and the glideslope
indicator (TO 1F-15A-1 p. 1-61, fig. 1-12)[^f15-1]. Driven by pitch, roll and the steering to the waypoint.

### Stores (open)

Two candidates, both open:
- The armament control panel's station lights (pre-MSIP). Its layout is open: the flight manual's foldout names the
  panel, but the figure's text is not legible in the scan.
- The MPCD ARMT page (MSIP only): TO 1F-15A-1 fig. 1-11C[^f15-1], BMS §3.2 pp. 22–25[^bms-f15], DCS fig. 23
  p. 37[^dcs-f15]:
  - A cyan plan-view outline of the jet. Station key: `L` = left STA 2, `LC` = left CFT, `C` = centre STA 5, `RC` =
    right CFT, `R` = right STA 8.
  - The missile stations on it: wing pairs 2A/2B and 8A/8B, the fuselage stations LA / LB and RA / RB.
  - Each station: a state word (`RDY` green / `STBY` / `HUNG`) above its type (`9X`, `120C`, `7M`); the selected
    station boxed.
  - A tank row on top: `FUEL` / `PYLON` for L, C, R. Gun rounds at the top left (`GUN 940`); chaff / flare at the
    right (`CHF 120`, `FLR 60`).
  - Button labels: left `HIGH` / `SCAN` / `MODE`; right `MENU`, `COOL` (AIM-9), target size `SML` / `MED` / `LRG`
    (AIM-120).
  - Colours: green, amber, cyan, white[^f15-1].
  - Driven by: the stations at `state+0x3a8`, the selected station, gun rounds, MRM / SRM totals (mfd.md §3
    "Stores"), through a game-station → F-15 station table (inferred).

## Lavi

### What is public

- **Displays:** Elbit was prime contractor for the integrated display system: the Hughes wide-angle diffractive HUD;
  "three head-down displays (HDD) (two of them were color presentations and the third black and white)"; the display
  computers, which back up the ACE-4 mission computer; and one El-Op up-front control panel. "Data-sharing between the
  HDDs would ensure display redundancy". The stick, throttle and display keyboard feed the display
  computers[^deurenberg].
- **Radar:** the EL/M-2035. A-A: automatic acquisition, boresight, look-down, look-up, TWS; "track several targets at
  46 km". A-G: beam-sharpened ground mapping / terrain avoidance, sea search[^deurenberg].
- **EW:** an Elta / Elisra internal ESM / ECM system[^deurenberg].
- **Stores:** the Elbit SMS-86 stores management system, for conventional and smart weapons[^deurenberg].
- **Formats:** open. No manual, symbology description or display drawing was found.

### The cockpit photo

One uncredited colour photo (750 × 860) shows the three displays lit[^wt-lavi]. Inferred: an IAI press photo of a
prototype or a full mock-up (the HUD and all displays are lit while parked). The 1985 mock-up photo with Shimon
Peres[^peres] shows only the up-front keypad and the HUD.

| Display | Colour seen | Content | Format (inferred) |
|---|---|---|---|
| Left (upper left, square, about 20 bezel buttons) | green | a Hebrew title line and a numbered list 1–8 of right-aligned Hebrew lines | a text page: checklist, menu or stores list |
| Centre (below the up-front panel, smaller) | green | a PPI fan: about 5 radial lines and 3 range arcs from an apex at the bottom, a smaller offset sector box inside it on the right, labels on the edges | radar; the box looks like an expand patch (A-G map) or a scan sub-volume (open) |
| Right (upper right) | colour: green, yellow, red, magenta, cyan | a compass rose of dots and ticks, a boxed heading on top, a yellow course / bearing pointer, coloured labels on the top row and in the corners | an HSI / navigation situation format, possibly with EW |

The photo fits "two colour, one monochrome" only if one green display is a colour tube showing a green page (open).
The buttons: about 5 per side on all four sides (low resolution; inferred).

### Formats (decision: as in the photo)

All inferred, from the photo and the F-16 formats IAF pilots knew[^dash34]:
- **Left: the list (stores, game page 1).** A text list in the manner of the F-16 SMS: the stations with type and
  count, the selected station boxed, `GUN` rounds. Hebrew labels are open: the game's font has no Hebrew glyphs.
  Driven by the stations at `state+0x3a8`, the selected station, gun rounds, quantity / interval.
- **Centre: the radar fan (game page 2).** A PPI fan of ±60° with 3 range arcs (¼, ½, ¾ of the range). Contacts in
  the F-16's manner: filled squares in search, hollow in track, a heading vector, the lock's aspect / closure /
  altitude as text on the edges. OSB labels: range up / down and the mode (`CRM`, `ACM`, `TWS`, `GM`). In A-G, the fan
  with an expand box, as in the photo. Driven by the radar contacts, the lock, mode, range, scan width, antenna,
  cursor, the missile envelope, the current waypoint, own roll / pitch.
- **Right: the colour navigation rose (game page 3, the TSD).** An HSI-style compass rose with a boxed heading, a
  bearing pointer to the current waypoint, the range and time to go, in colour. Driven by heading and the waypoint
  records (bearing, distance, current waypoint, ETA).
- **Defaults (inferred):** the photo's order is Left = stores, Middle = radar, Right = navigation, against the game's
  Left radar, Middle TSD, Right RWR (mfd.md §7). Whether the option swaps the defaults is open.
- **RWR (7):** the EW display is open. Inferred: the threat symbols inside the right display's compass rose.
- **ADI (9):** the Lavi had electromechanical standby instruments (three round gauges under the centre display in the
  photo). Inferred: an ADI ball.

## F-4E Kurnass

The F-4E has dedicated CRT scopes. The game's one MFD stands for the front cockpit's radar scope, and its
panel RWR dial for the RHAW (radar homing and warning) scope (third decision).

### Cockpit

TO 1F-4E-1 (1979) foldout FO-10 (front cockpit, later aircraft) lists item 38 "Radar scope", item 17 "AN/APR-36
strobe display scope" and item 4 "Threat display panel"; FO-11 (later configuration) lists a "CRT azimuth indicator"
and a "Threat display panel"[^f4e-1]. The ALR-46 came with TO 1F-4E-591 (72-1498 and up; 66-284 thru 72-1497 by
retrofit)[^f4e-1]. The scope symbology is in the dash-34, which was not found (open). The foldouts are line drawings
of the whole panel: traceable for position, not for symbology.

### APQ-120 radar scope (DSCG): game page 2

From a simulator manual[^hb-interface][^hb-a2a][^hb-a2g]:
- **Formats:** the Display knob gives B WIDE / B NAR / PPI WIDE / PPI NAR / VI. B-scope: x = azimuth, y = slant
  range. PPI: x = distance left / right, y = distance along track, the ownship at the bottom centre. NAR = a 45°
  sweep, WIDE = 120°. At the 5 NM range the picture is always a B-scope.
- **Ranges:** up to 50 NM are the AI ranges (auto track); 100 / 200 NM for spotlight. The selected range lights a
  lamp and shows its number on the scope: upper right on the pilot's DSCG[^hb-dscg], upper left per the interface
  page (open). The range knob's set (5 / 10 / 25 / 50 / 100 / 200 NM) is open.
- **Grid:** vertical lines at 30° left and right; horizontal lines at 1/5 of the range. A horizon line only with the
  stab switch at NOR / DRIFT OUT. The EL strobe shows the antenna elevation (±60°), with a readout in degrees. Range
  scales on the bezel edges.
- **Search:** a radar cursor at the selected range and azimuth. Acquisition: a B-sweep along the antenna azimuth and
  the acquisition symbol on the echo; half action shows the range strobe.
- **Track:** the ASE circle, the range strobes, the aim (steering) dot, and a readout chosen by the Aspect knob
  (closure in knots, + closing; or altitude, aspect, heading). The range-rate digits flash at 4 Hz in memory. Range
  marks: Rmax and Rmax2 (Sparrow), Rmax and Rmin (Sidewinder).
- **ASE circle size:** AIM-7E max 25°, AIM-7F 35°; AIM-9 caged 1.2°, uncaged max 25°. It grows past Rmax and shrinks
  towards Rmin. Inside Rmin a Break X replaces the circle (VI: under 1,000 ft).
- **Aim dot:** collision steering from 2 NM outside Rmax, lead pursuit inside Rmax. The shoot light comes on when the
  dot is in the circle and Rmin < R < Rmax.
- **Home on jam:** the last closure digit becomes H and flashes.
- **A-G:** MAP (PPI, 1 bar) with a range cursor (an arc) and an offset cursor (a line parallel to the drift; only in
  TGT FIND / OFFSET / BEACON); AIR-GRD ranging (the antenna at boresight, range track on the clutter, 5 / 10 NM).
- **Pictures:** the simulator manual's screenshots (search, acquisition, track, ASE circle, aim dot, Break X, map
  cursors): traceable, but a simulator's art.
- **IAF fit:** the DSCG came with Block 60 and retrofits[^hb-overview]; which IAF F-4Es had the DSCG or the older DVST
  is open. Elbit / Singer-Kearfott "Jason" (1977) gave Israeli F-4Es a rear-seat CRT navigation display[^flight1983]
  (format open).
- **Driven by** (inferred): contacts (range, bearing → B-scope x / y; altitude → readout); the lock (the ASE circle
  sized by the selected missile, the aim dot from the steering, Rmax / Rmin marks from the launch envelope, closure);
  A-G ranging.

### DSCG TV mode: game page 5

The DSCG shows weapon or pod video in its TV mode[^hb-overview]. Driven by the EO camera. Open: which IAF jets had the
DSCG.

### RHAW scope: the panel RWR dial

- The ALR-46, from a simulator manual[^hb-rwr]: a round CRT, the nose at 12 o'clock; distance from the centre = threat
  level; the middle ring = engagement range; up to 16 threats; alphanumeric and generic symbols (2, 3, 6,
  A, H, S, a fighter triangle …); a diamond on the top-priority emitter; a circle on an engaging / launching emitter;
  U for unknowns (1–3 dots by band). Excess-noise T strobes at 9, 12 and 3 o'clock.
- Which RWR the Kurnass carried in 1998 is open: a game wiki says ALR-46; IAF Phantoms may have had Elisra units (the
  SPS-200 family existed by 1983[^flight1983]); no source ties one to the Kurnass.
- **Driven by** (inferred): the game's dial (rwrsymb.bmp glyphs) is already a symbolic azimuth scope. The real one
  places each symbol by threat level (lethality), with the priority diamond and the launch circle.

Not offered on the F-4E: NAV, stores, TSD, damage, FLIR, ADI, HARM, MENU.

## Kurnass 2000 (F-4E 2000)

No manual or display format is public.
- "Elbit heads-down displays in both cockpits", a display computer driving new multifunction displays, an Elbit
  ACE-3 mission computer, the Norden / UTC APG-76 multi-mode radar with SAR[^baugher-k2000]. First flight 15 Jul 1987,
  conversions from Apr 1989; APG-76 test sets in 1992, then "to fit in all Kurnass 2000 conversions in the coming
  years"[^baugher-k2000]. Whether a 1998 Kurnass 2000 had the APG-76 or kept the APQ-120 is open.
- Displays in the pilot's and the navigator's stations, a wide-angle HUD, the APG-76 (Hebrew Wikipedia, citing the
  IAF website)[^he-wiki]. 55 jets upgraded with HOTAS, the APG-76 and Popeye support[^natint-k2000].
- The MFD count per cockpit, monochrome or colour, the formats and any moving map: open. The APG-76's display formats
  (SAR patch, GMTI): open[^wiki-apg76].
- Inferred: an Elbit late-1980s MFD set (the Lavi's era) with a radar B-scope, SMS, NAV / waypoint data and weapon
  video pages. The game's two MFDs with an RWR page are plausible but not sourced. The pages would be a
  reconstruction, as `real_hud/k2000.rs` is.
- Offered (inferred): radar, stores, NAV, TV, ADI, RWR. Open: TSD (no source gives a moving map), FLIR, damage, HARM.

## Kfir C7

- **Radar:** the Elta EL/M-2001B, a "dual-mode pulse-Doppler radar used for ranging only"[^periscope]. It feeds the
  WDNS gun and bomb solutions; the HUD's content comes from the WDNS[^wt-kfir]. The real jet has no radar scope, so
  the radar page is not offered; the radar lock shows only on the HUD.
- **System 82 WDNS** (Flight International, 27 Aug 1983, p. 542)[^flight1983]: a stores management computer, an
  "armament control and display panel", and "the 4in CRT can display sensor or weapon video plus alphanumeric weapon
  inventory, release parameter, or malfunction warning data"; a keyboard terminal. The article's photo of "Elbit's
  head-down display" (bezel labels BRIGHTNESS / CONTRAST / DISPLAYS / OFF) is too small to trace.
  - Game pages on the CRT: stores (1) as the weapon inventory and release parameters (quantity, interval); TV (5) as
    the weapon video; damage (4) as the malfunction warnings. Exact layout: open.
  - NAV: waypoints are entered on the keyboard terminal; whether the CRT shows a waypoint list is open.
  - Driven by: the stations, counts, quantity and interval; the TV seeker video; the damage flags.
- **RWR:** the Elisra (then AEL Israel) SPS-200, per a hobbyist research thread citing an Elisra poster and C7 cockpit
  photos[^wt-kfir]. Flight 1983 describes the SPS-200: pulsed radars 1–8 GHz, a separate CW receiver, and "a 3in CRT
  azimuth indicator displays type, bearing, relative lethality, and status of analysed radar threats"[^flight1983].
  The thread describes a square bezel with scope-like lines. The symbol set is open. This fits the game's panel dial
  (bearing and type); "relative lethality" suggests a radial place by threat level, as on the ALR-46 (inferred).
  Driven by the RWR emitters.
- **Default page:** the game's one MFD shows the radar by default (mfd.md §7). With the radar not offered, the
  default becomes a System 82 page (inferred: stores).
- Not offered: radar, TSD, FLIR, ADI, HARM. NAV open.

## Mirage IIICJ Shahak

- **Radar:** the IIIC / IIICJ carried the Cyrano I bis (monopulse, A-A)[^sp-cyrano]; no manual for it was found
  (open). The nearest documented set is the Cyrano IIB of the RAAF Mirage IIIO[^raaf]. The IIIO had ground-map modes
  the IIICJ's Cyrano I bis probably lacked (inferred, open).
- **Cyrano IIB scope** (AAP 7213.003-1, pp. 1-93..1-105, figs. 1-53..1-59)[^raaf]:
  - A round scope in the centre of the panel with two polaroid discs, one with an etched centreline, one turnable
    with an etched base line; a rubber glare shield.
  - A column of 19 antenna-elevation lights left of the scope (−35..+55 in steps of 5; A-A 2.5° a press, A-G 0.5°).
    Range-scale lights "15 NM 5" / "50 NM 10" on top (p. 1-94).
  - A-A picture: a B-scope. The 15 NM switch gives a 6 NM scale with one mark at 5 NM; 50 NM gives a 27 NM scale with
    marks every 5 NM (p. 1-97). Maximum range: A-A 27 NM, A-G 50 NM (p. 1-93).
  - Scan programmes: 60° (±60° about the aircraft axis), 30° (±30° about the strobe's azimuth), SPIRAL (20°, auto
    lock-on, the strobe wobbles ±2 NM), anti-jam, and A-A ranging (a 5° cone, 72 mils down, gate 2.5 hm–2.7 NM, on a
    "5 NM scope", fig. 1-56). Single or dual bar (5° / 10°).
  - The range-gate marker ("strobe") is moved in azimuth and range by the radar stick. Lock-on: the strobe's right
    edge under the echo. A "stop programme" 5° wide about the strobe. A movable artificial horizon (H control).
  - Fig. 1-53: a filled rectangle the width of the scan, echoes as short horizontal dashes, the strobe as a vertical
    bar.
  - After lock, the steering is in the sight: sequence lights (red / green / amber / blue) right of the sight head
    (p. 1-95); the closing speed (−100..+1600 kn) in a window 5 mils above the fixed cross (p. 1-98). The scope's
    picture after lock is open.
  - A-G (IIIO only): a PPI ground map at 50 / 15 NM, map freeze, an estimated point marker (fig. 1-58, offset by the
    Doppler drift).
  - Pictures: scanned line drawings of the scope (figs. 1-53..1-58), traceable.
- **Driven by** (inferred): the radar contacts as echo dashes on the B-scope (range, azimuth); the strobe at the lock
  or the cursor; the range marks per scale; the elevation lights from the antenna elevation; the lock only as sight
  cues and lights.
- **RWR (7):** no source shows an RWR display in the Shahak; the game's RWR page is its own (open).
- Not offered: stores, TSD, NAV, damage, TV, FLIR, ADI, HARM.

## MiG-23ML

- **No head-down radar display.** "Вся прицельная информация выводилась на индикатор на лобовом стекле АСП-23МЛ
  (позже ставился и АСП-17МЛ)" (all aiming data went to the windscreen indicator); "Информация от РЛС и
  теплопеленгатора, включая прицельную сетку для стрельбы из пушки, выводится на ИЛС" (the radar and IRST data,
  including the gun reticle, go to the sight)[^airwar-ml]. US / Israeli evaluations: the sight "doubles as a
  radarscope"[^warhistory]. The ML's instrument list names no head-down display (inferred: none)[^airwar-ml].
- The navigation data (РСБН-6С) and the autopilot's director signals also go to the sight and the attitude
  instrument[^airwar-ml]. The IRST's T-II mode "увеличивает масштаб изображения" (enlarges the picture)[^airwar-ml];
  its drawing is open.
- «Лазурь» ground-control commands: HUD arrows and lamps, and an extra command needle on the instrument
  bezels[^capss].
- The radar picture's symbology on the sight is open; the Real HUD reconstructs it (`real_hud/mig23.rs`,
  mig-cockpits.md §5).
- **RWR:** the СПО-10 «Сирена-3»[^airwar-ml]: 4 direction lamps (front, left, rear, right); search = blinking toward
  the radar; lock = a higher tone and flickering lamps; at 2–5 km all four light (a MiG-21bis manual, quoted on a
  forum[^wt-spo10]). The game's art paints an SPO-15 (the MLD's), already driven (`spo15`, mig-cockpits.md §4, item 4.4).
- **Game pages:** the cockpit has one MFD (Left, radar). No game page has a real head-down counterpart; a photo of a
  real cockpit shows a bare plate where the game's MFD sits[^kiev]. Since no MFD is left blank, what it shows is open
  (inferred candidate: a stand-in that repeats the sight's radar symbology in green on black, recorded as a deviation;
  driven by the radar contacts, lock and range, the IR seeker and the steering ring).

## MiG-29 9.12

- **Displays:** a classic T of dials[^ea][^wiki-29]. The СЕИ-31 indication system is the ИЛС-31 HUD and the ИПВ
  head-down display[^studfile]. The ИПВ (a "direct vision indicator") sits at the upper right of the panel with a
  sunshade and a brightness knob; it "duplicates and partially supplements the information displayed on the HUD", for
  a HUD failure or bright sun. Above it are the switches "TARGET – TRACK" and "TAC – DUPL"[^ea] (pp. 65, 67).
- **ИПВ in radar search** adds to the HUD picture: a horizon mark, the radar's elevation coverage and visibility zone,
  the current scan-line number[^ea] (p. 87, fig. 87: the HUD and the head-down display side by side, green on a black
  CRT; traceable). An older simulator manual draws a top-down tactical view in TWS on it[^fc3] (p. 52, fig. 39);
  inferred: a simplification, since the newer manual says repeater. The "TAC" position's picture is open. Range
  scales up to 150 km are cited[^ed-ipv].
- **SPO-15LM «Берёза»:** a lamp unit on the right of the central panel[^ea] (pp. 33, 105–109; traceable figures on
  pp. 33, 106): an own-aircraft silhouette; front azimuth lamps (10° steps within ±50°, ±20° beyond; the 90° lamp is
  virtual) and rear lamps; yellow main-threat lamps over the azimuth and type lamps; a red centre track lamp (steady =
  track, with a continuous high tone); a round power-level scale in 2 dB steps (a flashing lamp = the SAM's engagement
  edge); 6 green type letters П З Х Н F С; В / Н elevation lamps; a ready lamp. A search detection flashes at least
  125 ms.
- **Экран (Ekran):** a one-line text message unit on the right console with FAIL, TURN / QUEUE and MEMORY lamps and a
  CALL button. Messages queue by priority, the master caution flashes, and the voice says "see Ekran"[^ea]
  (pp. 31–32).

| Game page | Real counterpart | Driven by |
|---|---|---|
| 2 radar (left MFD) | the ИПВ: the Real HUD's MiG-29 symbology (`real_hud/mig29.rs`) on a green-on-black CRT, plus the horizon mark, elevation zone and scan-line number | the Real HUD's state; the radar's scan, elevation and bar |
| 7 RWR (right MFD) | the SPO-15LM lamp unit, drawn in the MFD frame (inferred) | the RWR contacts: bearing → lamps, kind → type letter, lock → the red lamp, the strongest → the power scale and main-threat lamps (the MiG-23's `spo15` mapping) |
| 4 damage | the Экран message line (inferred: in an MFD) | the damage flags → messages |

Not offered: stores (a weapons panel with lamps; its layout open), TSD, NAV, TV, FLIR, ADI (the panel's attitude
instrument), HARM, MENU.

## Open questions

1. **Page switching without a menu:** on jets where MENU is not offered (F-15, F-4E, Mirage, MiG-29, Kfir), how the
   pilot changes pages: keys, MFD clicks, or fixed pages.
2. **MiG-23ML:** no game page has a real counterpart, and no MFD may be blank. What the MFD shows (a stand-in for the
   sight's radar picture, or another choice); the radar and IRST picture on the sight.
3. **F-15:** where the ADI goes with three MFDs taken by the VSD, HSI and TEWS; whether the stores page is offered
   (the armament control panel's lights, whose layout is open, or the MSIP MPCD ARMT page); the VSD's A-G picture;
   the pre-MSIP ALR-56 symbol set; the primary VSD / TEWS / armament panel layouts (the F-15 dash-34s are not
   public).
4. **F-16:** whether the HAS (HARM) page is offered (Block 50, out of era); the game-button → OSB mapping; the 5 NM
   range step; the TEST fault-list and FLIR layouts; the HSD's era; the IAF Block 30/40's RWR.
5. **F-35I:** the TWD, SRCH and WPN-A / WPN-S graphics; the ownship and threat-ring drawing on the TSD; the real
   pixel size. The best unread source is Skaff's SAE paper[^sae].
6. **Lavi:** every format's details, and which display was monochrome; the photo's origin and date; whether the
   defaults follow the photo; the RWR, ADI, TV, NAV and damage pages; Hebrew labels.
7. **Kfir:** the System 82 CRT layout; whether it shows a waypoint list; the SPS-200 symbol set.
8. **F-4E:** which IAF jets had the DSCG; the range knob's set; which RWR the Kurnass carried in 1998.
9. **Kurnass 2000:** every format; the APG-76 in 1998; the TSD, FLIR, damage and HARM pages.
10. **Mirage:** the Cyrano I bis scope and its picture after lock; an RWR display.
11. **MiG-29:** what the ИПВ's "TAC" position shows.
12. **IFF:** the radar formats show friends as the real jets do (real-hud.md "IFF"): the F-15C's and F-4E's
    interrogation replies, and the F-35I's track colours and shapes.

[^dash34]: T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997: MFDS
    pp. 1-59..1-83 (figs. 1-26..1-46), SMS pp. 1-84..1-114 (figs. 1-48..1-75), radar pp. 1-115..1-151
    (figs. 1-76..1-100), RWR pp. 1-197..1-203 (figs. 1-132..1-136), TGP pp. 1-217..1-240 (figs. 1-163..1-166),
    AGM-88 pp. 1-456..1-466 (figs. 1-295..1-298). PDF page = 1-N + 16: https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^mlu1]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998): colour symbology
    p. 19 (table 1-1), HSD figs. 1-18..1-23, EWPI / ALR-69 fig. 7-3 p. 209: https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^rokaf]: RoKAF AFTTP 3-3 Vol 5, F-16C Basic Employment Manual (2005), tactics text with an MFD TEST page reference:
    https://falcon.blu3wolf.com/Docs/Basic-Employment-Manual-F-16C-RoKAF.pdf
[^haf1]: T.O. GR1F-16CJ-1, Hellenic AF F-16C/D flight manual (dash-1): the MFD TEST page / MFL, the DED STPT page:
    https://falcon.blu3wolf.com/Docs/HAF-F16.pdf
[^usaf1]: T.O. 1F-16A-1, USAF / EPAF F-16A/B flight manual: cockpit keys, "THREAT WARNING Azimuth Indicator":
    https://falcon.blu3wolf.com/Docs/USAF-F16.pdf
[^bmsforum]: Falcon BMS forum (a simulator community), "AN/ALR-56M range indications":
    https://forum.falcon-bms.com/post/7196
[^f15-1]: TO 1F-15A-1, F-15A/B/C/D flight manual (1984, with changes): MPCD pp. 1-59/1-60 fig. 1-11C; ADI / HSI
    pp. 1-61/1-62 figs. 1-12, 1-13; VSD BIT fig. 1-11A; overload display fig. 1-10A; TEWS / radar / weapons "refer to
    TO 1F-15A-34-1-1" pp. 1-80/1-81; rear VSD p. 1-82; the instrument-panel foldout; the MSIP cut-in. A scan, figures
    traceable at low quality: https://archive.org/details/f-15-manual
[^bms-f15]: Falcon BMS, *TO 1F-15C-34-1-1 BMS* (Change 4.37.6), a simulator manual: VSD §8 pp. 43–45; radar §9
    pp. 55, 63; MPCD §3.2 pp. 22–26; TEWS / ALR-56C §14 pp. 70–73; IFF §16 p. 83. Clean labelled renders:
    https://cdn.falcon-bms.com/docs/4.37/TO%201F-15C-34-1-1%20BMS.pdf
[^dcs-f15]: Eagle Dynamics / Belsimtek, *DCS F-15C Flight Manual* (2014), a simulator manual: panel fig. 20 p. 34; VSD
    fig. 21 and TEWS fig. 22 p. 36; MPCD fig. 23 p. 37; TEWS ECM fig. 62 p. 76; TEWS symbology figs. 63–64, table 9-5
    pp. 77–80:
    https://www.digitalcombatsimulator.com/upload/iblock/1ad/F-15C%20DCS%20Flaming%20Cliffs%20Flight%20Manual%20EN.pdf
[^baugher-f15]: Joe Baugher, "Electronics suite of F-15A" (Honeywell VSD, Collins HSI):
    https://www.aircraftinformation.info/JB_AIF/usaf_fighters/f15_4.html
[^twz-baz]: The War Zone, "F-15A 'Baz' upgraded cockpit seen in rare Israeli Air Force photo" (Baz Meshopar 1995,
    three Elbit MFDs per Janes, the Astronautics up-front display):
    https://www.twz.com/f-15a-baz-upgraded-cockpit-seen-in-rare-israeli-air-force-photo
[^deurenberg]: Ruud Deurenberg, *IAI Lavi* (citing Flight International / Jane's): the cockpit, ACE-4, EL/M-2035, EW,
    SMS-86: https://www.dror-aero.com/pro/lavi5.pdf
[^wt-lavi]: War Thunder forum, "The Lavi" (a community research thread; cockpit photo `lavi-6`, uncredited):
    https://forum.warthunder.com/t/the-lavi/49149; image:
    https://forum-en-cdn.warthunder.com/original/3X/2/2/226a16e7fc0b048c183c58f019ed5bc7b818ffcf.jpeg
[^peres]: GPO / Wikimedia Commons, "P.M. Peres in a Lavi fighter" (1985 mock-up), CC BY-SA 3.0:
    https://commons.wikimedia.org/wiki/File:Flickr_-_Government_Press_Office_(GPO)_-_P.M._Peres_in_a_Lavi_Fighter.jpg
[^f4e-1]: TO 1F-4E-1 flight manual (1979), foldouts FO-10 / FO-11, modification TO 1F-4E-591:
    https://archive.org/details/f-4e-1-flight-manual
[^hb-overview]: Heatblur, DCS F-4E manual, "Radar system" (DSCG), a simulator manual:
    https://f4.manuals.heatblur.se/systems/radar/overview.html
[^hb-interface]: Heatblur, DCS F-4E manual, radar interface, a simulator manual:
    https://f4.manuals.heatblur.se/systems/radar/interface.html
[^hb-a2a]: Heatblur, DCS F-4E manual, radar air-to-air, a simulator manual:
    https://f4.manuals.heatblur.se/systems/radar/air_to_air.html
[^hb-a2g]: Heatblur, DCS F-4E manual, radar air-to-ground, a simulator manual:
    https://f4.manuals.heatblur.se/systems/radar/air_to_ground.html
[^hb-dscg]: Heatblur, DCS F-4E manual, pilot DSCG controls, a simulator manual:
    https://f4.manuals.heatblur.se/cockpit/pilot/dscg_controls.html
[^hb-rwr]: Heatblur, DCS F-4E manual, AN/ALR-46 RWR, a simulator manual:
    https://f4.manuals.heatblur.se/systems/defensive_systems/radar_warning_receiver.html
[^flight1983]: Flight International, 27 Aug 1983, p. 542 (System 82, Jason, SPS-200):
    https://cdnc.heyzine.com/files/uploaded/v3/3c1262af2443f80fe2c7293f1cedb885c62cfe96.pdf
[^baugher-k2000]: Joe Baugher, Kurnass 2000: https://www.aircraftinformation.info/JB_AIF/usaf_fighters/f4_35.html
[^he-wiki]: Hebrew Wikipedia, Kurnass 2000 (cites the IAF website): https://he.wikipedia.org/wiki/קורנס_2000
[^natint-k2000]: National Interest, "In the 1980s, Israel Developed a 'Heavy Hammer' F-4 Super Phantom":
    https://nationalinterest.org/blog/buzz/1980s-israel-developed-heavy-hammer-f-4-super-phantom-what-happened-44702
[^wiki-apg76]: Wikipedia, "AN/APG-76 radar family": https://en.wikipedia.org/wiki/AN/APG-76_radar_family
[^periscope]: Military Periscope, EL/M-2001B overview:
    https://www.militaryperiscope.com/weapons/sensorselectronics/airborne-radars/elm-2001b/
[^wt-kfir]: War Thunder forum, Kfir research thread (System 82 CRT, SPS-200 poster, C7 cockpit photos), a hobbyist
    source:
    https://forum.warthunder.com/t/kfir-aircraft-c-1-c-10-blk-60-from-cub-to-lion-discussion-analysis-and-research/285880
[^sp-cyrano]: Secret Projects forum, "Cyrano Radar Family" (Cyrano I bis for the IIIC, Cyrano II for the IIIE):
    https://www.secretprojects.co.uk/threads/cyrano-radar-family.37016/
[^raaf]: RAAF AAP 7213.003-1, Mirage IIIO / IIID flight manual (1978), Cyrano IIB pp. 1-92..1-106, figs. 1-53..1-59
    (PDF pages 129–143 of the Docdroid copy): https://docdro.id/MtUOJBE (listing:
    https://aviationarchives.blogspot.com/2023/03/australia-dassault-mirage-iiio-and-iiid.html)
[^codeone]: Code One, J. Kent, "The New Front Office" (2006): https://www.codeonemagazine.com/u2_article.html?item_id=35
[^sld-cockpit]: SLDinfo, "The F-35 Cockpit: Enabling the Pilot as a Tactical Decision Maker" (2012), with LM's slides:
    https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/
[^lm-slides]: Lockheed Martin, "The F-35 Cockpit" slides (the same deck):
    https://www.slideshare.net/slideshow/the-f35-cockpit/12572694
[^sld-overview]: SLDinfo, "An Overview of the F-35 Cockpit":
    https://sldinfo.com/whitepapers/an-overview-of-the-f-35-cockpit-what-5th-generation-aircraft-are-all-about/
[^skaff]: M. Skaff (LM), "The Impact of Advanced Fusion in 5th Generation Fighters" (2013), quoted on f-16.net:
    https://www.f-16.net/forum/viewtopic.php?f=22&t=29126
[^sae]: M. Skaff, "F-35 Lightning II Cockpit Vision", SAE 2010-01-2330 (paywalled):
    https://saemobilus.sae.org/articles/f-35-lightning-ii-cockpit-vision-2010-01-2330
[^hushkit]: Hush-Kit, "What is good and bad about the F-35 cockpit" (2021):
    https://hushkit.net/2021/01/21/what-is-good-and-bad-about-the-f-35-cockpit-a-panthers-pilots-guide-to-modern-cockpits/
[^driven]: Driven Technologies, "F-35 Simulated Displays" (simulator display hardware; a PCD picture):
    https://www.driven-technologies.com/portfolio-2-1/project-one-j6axm-fwwcg-gj2r2-b4k8y-z3954 (image:
    https://images.squarespace-cdn.com/content/v1/62a0d78809deef4f386d7706/b896b0f1-40a1-4f74-853c-0a53d92a682c/PCD.jpeg)
[^ife]: IndiaFoxtEcho, *F-35 Lightning II for Microsoft Flight Simulator, User Manual* v1.2.2 (2023), a simulator
    manual built from LM simulator footage, PDF pp. 32–53:
    https://orbx-user-guides.storage.googleapis.com/indiafoxtecho-f35-msfs-user-guide-3475b3.pdf
[^f16net-pages]: f-16.net forum, "MFD pages details" (2015; the menu list from LM simulator videos):
    https://www.f-16.net/forum/viewtopic.php?t=27773
[^f16net-ncoic]: f-16.net forum, "Panoramic Cockpit Display/Screen Explanation?" (2012):
    https://www.f-16.net/forum/viewtopic.php?p=228553
[^baseline]: SLDinfo, "The Baseline F-35" report (2012):
    https://www.sldinfo.com/wp-content/uploads/2012/05/The-Baseline-F-35-Report.pdf
[^airwar-ml]: airwar.ru, "МиГ-23МЛ": https://www.airwar.ru/enc/fighter/mig23ml.html
[^warhistory]: warhistory.org, "Mikoyan MiG-23": https://warhistory.org/article/mikoyan-mig-23
[^capss]: CAPSS, "Stickers, scans and radar beats: an operational view of the MiG-23MF with the Indian Air Force":
    https://capssindia.org/stickers-scans-and-radar-beats-an-operational-view-of-mig-23mf-with-indian-air-force/
[^wt-spo10]: War Thunder forum, "SPO-10" (quotes the MiG-21bis manual p. 70): https://forum.warthunder.com/t/spo-10/106497
[^kiev]: Wikimedia Commons, "Cockpit Mig23 high resolution.jpg":
    https://commons.wikimedia.org/wiki/File:Cockpit_Mig23_high_resolution.jpg
[^ea]: Eagle Dynamics, *DCS MiG-29A Early Access Manual* (Sept 2025), a simulator manual:
    https://www.digitalcombatsimulator.com/upload/iblock/aa2/ulzl67k42kj99ushy9m29hlvmtk0y2tg/DCS%20MiG-29A%20Early%20Access%20Manual%20EN.pdf
[^fc3]: Eagle Dynamics, *DCS MiG-29 Flight Manual* (Flaming Cliffs 3), a simulator manual:
    https://www.digitalcombatsimulator.com/upload/iblock/463/DCS%20MIG-29%20Flight%20Manual%20EN.pdf
[^wiki-29]: Wikipedia, "Mikoyan MiG-29": https://en.wikipedia.org/wiki/Mikoyan_MiG-29
[^studfile]: "СЕИ-31", studfile: https://studfile.net/preview/5383865/
[^ed-ipv]: ED forum (a simulator community), "ИПВ" thread: https://forum.dcs.world/topic/64-ipv
