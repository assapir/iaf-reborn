# The F-35 cockpit's physical controls — research

This page records what public sources show of the F-35A cockpit's physical controls and their layout, so that the
F-35I Adir's 3D cockpit (`tools/f35i/cockpit3d.py`, [f35i.md](../../../docs/f35i.md) §4) can model each one as a
correct, labelled, moving part. It replaces the F-35I part of the cockpit-controls finish list of 2026-11-15, which
rested on a simulator add-on's manual. Research dates: 2026-11-15 and 2026-11-16.

**Terms**
- **PCD:** the panoramic cockpit display, the 20 × 8 in touchscreen.
- **SFD:** the standby flight display under the PCD (USAF and USMC name; the simulator manual calls it BFI, backup
  flight instrument).
- **Confidence:** **high** = two good independent sources (two photos, or a photo and an official text); **medium**
  = one good source (a readable photo or an official text); **low** = one weak source only (the simulator manual).
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning from the sources; "open"
  means no source was found.

## 1. The sources and how far they reach

No flight manual, cockpit drawing or labelled production-cockpit photo is public. What exists:

- **A full-scale cockpit mock-up, May 2026** (Black Sea Defense & Aerospace, Bucharest; public domain, 4176 ×
  2784)[^bsda]. Production layout, the forward panel's legends readable. The best single source. It is a mock-up,
  so a legend on it is counted as one good source, not two.
- **The flight-test jet CF-1, January 2012** (public domain, 4256 × 2832)[^cf1]. A real jet: it confirms every
  shape and place of the mock-up's forward panel, but its legends are too dim to read. It also carries test-only
  equipment (an orange-bordered FTI toggle panel above the jettison knob, a keypad unit under the SFD) that a game
  leaves out.
- **Cockpit demonstrators** of 2015 and 2019[^demo2015][^futenma]: the same forward layout, legends unreadable.
- **The US Air Force's 2019 solicitation for replica HOTAS grips** "with the same switch locations, movement, and
  functions as current F-35 HOTAS": it names every switch on both grips[^hotas]. The grips' maker shows them in
  small product photos[^essexs][^essext].
- **Lockheed Martin texts:** Code One's "The New Front Office" (2006)[^c1], the mission systems paper
  (JSF18-502)[^lmms], a PCD screenshot released in 2012[^lmpcd], the cockpit lead's slides[^skaff].
- **The seat maker's data sheet** (Martin-Baker US16E)[^mb] and public USAF photos of egress work[^luke].
- **IndiaFoxtEcho's F-35 for Microsoft Flight Simulator, user manual v1.2.2**[^ife]: a commercial simulator that
  numbers 43 physical controls on pp. 30–32 and says it "should not be used as source of real-world information".
  It names its references: six public YouTube videos. Every control it shows that a photo also shows sits where the
  photos put it, except its parking-brake counter (§2.1 F4). It is the only source for the left console behind the
  throttle and for the right console: those rows are low.

Not used: documents on file-sharing sites that may be leaked manuals (Scribd "F-35A" uploads, flash-card sets on the
IPP); none was opened.

## 2. Inventory of the physical controls

Each row's **ID** matches the layout sketches (§4) and the numbered photo (§4.1). Places are as seen from the seat.

### 2.1 Left forward panel

A panel under the PCD's left end: an inboard strip with the gear lever beside the PCD's left edge, an outboard strip
with the jettison knob. It is the left console's forward end: the console runs forward from the throttle and rises
as one column, its face toward the pilot, up to the PCD's lower-left corner, with no gap between the throttle's deck
and the column[^bsda][^cf1]. The right console rises the same way from the side-stick's housing to the right forward
panel beside the PCD's right edge[^bsda][^demo2015][^usersim]. The column's lean (about 45° on the left, steeper on the right) and
where the deck turns into it are inferred from the photos' perspective (re-checked 2026-11-17). Seen over the
headrest, a simulator's cab shows the same: each console one surface from behind the seat to its column, the seat's
cushion filling nearly all the room between the consoles, the side columns' outer edges about 1.6 PCD widths apart
(inferred from a simulator photo[^usersim]).

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| F1 | HOOK/STOVL | square lit push button, split legend | push | spring (push-on / push-off logic, inferred) | lowers and raises the arresting hook (F-35C); converts to STOVL mode (F-35B); on the F-35A the hook (inferred) | top of the panel, just under the PCD's lower-left corner | high | [^bsda][^cf1][^c1][^usmc] |
| F2 | LDG GEAR, UP / DN | lever with a large round black wheel knob, lamp in the knob | UP, DN | latched | raises and lowers the gear | inboard strip, vertical slot beside the PCD's left edge; the knob sticks out inboard | high | [^bsda][^cf1] |
| F3 | JETTISON, ALL / EXT / SEL | rotary selector, grey knurled knob on a yellow-black striped plate; its centre cap striped too, probably a push to jettison (inferred) | 3: ALL, EXT, SEL | latched | selects what is jettisoned: all stores, external stores, selected stores | outboard strip, level with the gear lever's foot | high (kind, stripes); medium (legends) | [^bsda][^cf1][^ife] |
| F4 | TOW MODE STATUS | indicator window, about four lamps | — | — | shows the towing mode's state (inferred from the legend) | outboard strip, under JETTISON | medium | [^bsda][^cf1] (shape) |
| F5 | PARKING BRAKE, (ON) / OFF | metal toggle | 2: up ON, down OFF | latched | sets the parking brake | outboard strip, under TOW MODE STATUS | high | [^bsda][^cf1][^ife] |
| F6 | ALT GEAR EXTENSION | switch under a red wire-bail guard (a toggle on the mock-up; the simulator draws a push button) | guarded; normal / extend (inferred) | latched (inferred) | lowers the gear by the alternate (emergency) system | inboard strip, just under the gear lever | high (place, red guard); medium (legend, kind) | [^bsda][^cf1][^ife] |
| F7 | LAND/TAXI LIGHTS, … / OFF | lever-lock toggle | OFF down; LAND and TAXI above (inferred from the legend) | latched | landing and taxi lights | bottom of the inboard strip | high | [^bsda][^cf1][^ife] |

The simulator puts a "remaining parking brake applications" counter where both photos show TOW MODE STATUS; the
counter is not on the photos (open whether the real jet has one).

### 2.2 Centre pedestal (under the PCD, between the knees)

A narrow stack under the PCD's centre: a strip of six controls across its top, then three radio knobs and a toggle on
the left half and the SFD on the right half; a handle at its foot. About 0.19 m wide (measured on a simulator photo
with its camera solved, round 6, 2026-11-17; inferred from a simulator photo[^usersim]); ours 0.20 m (0.27 m until
then), its standby display 62 × 49 mm (84 × 66 mm until then).

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| P1 | BRT (HMD) | rocker | up / down | spring (inferred) | helmet display brightness | top strip, 1st from left | medium | [^bsda][^ife] |
| P2 | HMD, OFF / NIGHT / AUTO / DAY | lever-lock rotary | 4 | latched | helmet display mode | top strip, 2nd | medium | [^bsda][^ife] |
| P3 | VIDEO BRT | paddle rocker | up / down | spring (inferred) | helmet video brightness | top strip, 3rd | medium | [^bsda][^ife] |
| P4 | VIDEO CONT | paddle rocker | up / down | spring (inferred) | helmet video contrast | top strip, 4th | medium | [^bsda][^ife] |
| P5 | (MFD) NIGHT / DAY | lever-lock rotary | 2 | latched | PCD day or night range | top strip, 5th | medium | [^bsda][^ife] |
| P6 | BRT (MFD) | rocker | up / down | spring (inferred) | PCD brightness | top strip, 6th | medium | [^bsda][^ife] |
| P7 | COM A (legend unreadable) | grey knurled knob with a long shaft | continuous | — | radio A tuning or volume (the simulator: tuning) | left column, top | medium (kind); low (function) | [^bsda][^cf1][^ife][^usmc] |
| P8 | COM B | as P7 | continuous | — | radio B | left column, middle | medium; low | as P7 |
| P9 | C/BUR (COM C / backup radio) | as P7 | continuous | — | radio C or backup radio | left column, bottom | medium; low | as P7 |
| P10 | MASTER ARM | metal bat toggle | 2 (labels open) | latched | arms the weapons; the PCD shows "Mstr Arm On" | left column, between P7 and P8, right of them | medium | [^bsda][^cf1][^ife][^lmpcd] |
| P11 | — | standby flight display, square | — | — | attitude, airspeed, altitude, heading | right half of the pedestal | high | [^bsda][^cf1][^demo2015][^usmc] |
| P12 | (none read) | knob | continuous | — | barometric setting (the simulator) | SFD's upper right corner | medium (kind); low (function) | [^bsda][^cf1][^ife] |
| P13 | ALIGN | small push button | push | spring | aligns the SFD's attitude | along the SFD's bottom edge, left | medium | [^bsda][^ife] |
| P14 | BRT | small push button | push | spring | SFD brightness | along the SFD's bottom edge, right | medium | [^bsda][^ife] |
| P15 | PEDAL ADJ | round handle, legend on its face | pull and turn (inferred) | — | adjusts the rudder pedals fore and aft | foot of the pedestal | high | [^bsda][^cf1] |

### 2.3 Right forward panel (right of the PCD)

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| R1 | one word, unreadable; the simulator: AUTO RECOVERY | red lever-lock switch in a yellow-black striped U surround | 2 (open) | latched | the simulator: arms the automatic recovery (Auto-GCAS) function | the right column's inboard strip, about level with the PCD's bottom edge (inferred from a simulator photo[^usersim]) | high (switch, colours); medium (place); low (name) | [^bsda][^cf1][^futenma][^ife][^usersim] |
| R2 | two lines, unreadable; the simulator: BYPASS / NORM / ZEROIZE | white or grey rotary | 3 | latched | the simulator: zeroizes the jet's classified data | a strip just outboard of R1, a little lower | medium (kind, place); low (labels) | [^bsda][^futenma][^ife][^usersim] |

The right forward panel is the right console's column rising beside the PCD's right edge: two black strips
from about the PCD's bottom edge down to the console, R1 near the top of the inboard one, R2 near the top of the
outboard one (inferred from a simulator photo[^usersim]). Until round 4 (2026-11-17) ours had them high on the cheek
beside the PCD's top and a blank insert on the column.

### 2.4 Glareshield

A plain hood over the PCD with one small dome on top near its centre: no up-front controls, no HUD, no warning
lamps[^cf1]. A simulator cab shows it as a deep dark box over the PCD, with two groups of vent slots on its top either
side of the centre (inferred from a simulator photo[^usersim]). Measured on that photo with its camera solved
(round 6, 2026-11-17; docs/f35i.md §4.1 "Display and hood"): a thin lip on the glass's top edge, flush with the
display's face; a chamfer rising 2.3 cm over 7 cm, then a level deck to 0.18 m back; 0.60 m wide at the lip, 0.36 m at
its far edge; light flanks falling from its sides to the columns. Ours since round 6 as measured, six slots each side,
a dark matte blue-grey as the in-flight frames show it (docs/f35i.md §4.1); the view over it 13.3° under the eye. Rounds
4–5: a 0.74 m box with a 3 cm rear face standing proud of the display, its top falling 1 in 4 (16–17°). Past the PCD's
ends its sides fall outboard to the side panels' columns (the simulator photo and the real jet's photo from behind
the seat[^cf1]); nothing stands beside the PCD (ours had grey cheeks there until round 5, 2026-11-17, removed after
the user's "they don't exist").

### 2.4a The PCD unit's shape

What the references agree on (round 5, 2026-11-17): one wide display unit standing proud of the panel like a slab, in
a thin dark bezel, its top tucked under the glareshield box's brow; it is wider than the knee panel under it, and the
side panels' columns rise beside its lower half[^usersim][^cf1]. The simulator photo also shows its lower outer
corners cut off at an angle, the unit leaning back toward the eye, and the pedestal's switch row (P1–P6) right under
its bottom edge[^usersim]; the real jet's photo shows the slab and the brow but not the corners clearly, so the cut
corners and the lean are inferred for the jet. Proportions from the simulator photo (inferred, the camera's angle
foreshortens the height): the unit about 1.1 times the gap between the side panels' inner edges. Measured in round 6
(2026-11-17) with the photo's camera solved from the glass's corners (docs/f35i.md §4.1 "Display and hood"; inferred
from a simulator photo): the dark frame about 4.5 cm beside the glass (3.2 cm left, 5.9 cm right), its top outer
corners rounded, its sides tapering in over the lower part, 1.3 cm under the glass, the hood's lip on the glass's top
edge; past the frame no panel, only the hood's flanks and the columns. The lean cannot be read off the photo (every
lean from 10° to 26° fits with the camera moved). Ours since round 6: the frame 4.5 cm beside the glass with 1.2 cm
rounded top corners, tapering in 1.6 cm over its lower 9.5 cm, 1.3 cm under the glass, 3.8 cm proud of a face that
reaches 1 cm past it, leaning with the panel at 18°. Round 5: a 14 mm bezel, the corners cut 3.4 × 1.8 cm, the face
0.40 m out.

The split of its glass in the simulator photo: a narrow bar along the top; the left half one large portal (the round
tactical picture, its tabs along its foot); the right half two portals side by side over four small windows[^usersim].
This matches LM's layouts of 4 portals over 8 secondary windows, a portal widened over its half and enlarged over its
windows (docs/real-mfd.md "Layout"). Ours draws this split by default (since 2026-11-17). Cautions and warnings show on the PCD (ICAWS) and the helmet, with spoken cues[^lmpcd][^usmc]. No
master caution or fire lamp was found on any photo (open whether one exists).

### 2.5 Left console and wall

Forward of the throttle the mock-up shows the trim plate; behind it, the simulator alone (low). The order behind the
throttle is read from the simulator's picture: its start panel lies aft of the throttle, the canopy lever on the sill
between them (inferred from where its rudder-trim plate sits, which the mock-up confirms).

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| L1 | RUDDER, L / R | toggle between two wire-loop guards | L, centre, R | spring to centre (inferred) | rudder trim | small plate forward and inboard of the throttle, at the left forward panel's foot | high | [^bsda][^cf1] (shape)[^ife] |
| L2 | FCS/ENG RESET | push button | push | spring | resets flight-control and engine faults | on the same plate, beside L1 | medium | [^bsda] (partly legible)[^ife][^aero] |
| L3 | — | throttle (active, motorised) | cut-off none; idle, MIL, detent, AB | — | engine thrust | in its track on the console | high | [^c1][^bae][^bsda] |
| L4 | — | knurled knob | continuous | — | throttle friction | inboard of the track, aft | low | [^ife] |
| L5 | (Throttle Active) | red switch | 2 | latched | engages the throttle's active (motorised) feel | aft of the throttle, by L4 | low | [^ife] |
| L6 | ENGINE, NORM / MOTOR / OFF | toggle under a red guard | 3 | latched | runs, motors or cuts the engine (the throttle has no cut-off; "a single toggle switch" cuts it) | small panel aft of the throttle, outboard | medium (engine switch); low (labels, place) | [^c1][^ife] |
| L7 | VS BIT | push button | push | spring | starts a built-in test (vehicle systems, inferred) | beside L6 | low | [^ife] |
| L8 | DEFOG, MIN … MAX | slide lever | continuous | — | windscreen defog | on the wall between L6 and the throttle | low | [^ife] |
| L9 | — | yellow lever | forward shut, aft open | latched | opens and shuts the canopy (powered) | on the left sill, between the start panel and the throttle | low | [^ife] |
| L10 | IPP, ON / OFF/RESET | toggle | 2 | latched | integrated power package master | start panel (aft), left column, top; the column is labelled ENGINE | low | [^ife] |
| L11 | ICC1, ON / OFF/RESET | toggle | 2 | latched | inverter/controller/converter 1 (power electronics) | under L10 | low | [^ife] |
| L12 | ICC2, ON / OFF/RESET | toggle | 2 | latched | inverter/controller/converter 2 | under L11 | low | [^ife] |
| L13 | CABIN PRESSURE, DUMP / NORM / ALTN | rotary | 3 | latched | cabin pressure mode | start panel, top right | low | [^ife] |
| L14 | BATT, ON / OFF / RESET; 28V LOW and 270V LOW lamps | toggle | 3 | latched | battery | start panel, centre | low | [^ife] |
| L15 | IPP EMER OFF | red push button under a guard | push | spring | shuts the IPP down in an emergency | start panel, right | low | [^ife] |
| L16 | IPP, OFF / AUTO / START | rotary | 3 | START spring-loaded (inferred) | starts the IPP, which starts the engine | start panel, bottom right | low | [^ife] |

### 2.6 Right console

The real right console carries only the side-stick, an arm rest and little else[^ife][^pilot].

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| C1 | — | side-stick (active), adjustable palm rest | — | — | pitch and roll | the console's inboard part, by the seat cushion's front corner: its base 0.36 m right of and 0.19 m ahead of the eye, measured on a simulator photo with its camera solved (round 6; inferred from a simulator photo[^usersim]) | high (exists); medium (place) | [^c1][^bae][^essexs][^bsda][^usersim] |
| C2 | (Stick Active) | red switch | 2 | latched | engages the stick's active feel | beside the stick's base, outboard | low | [^ife] |
| C3 | — | arm rest | — | — | supports the forearm | behind the stick | low | [^ife] |

Until round 4 (2026-11-17) ours stood the stick 0.18 m further forward and 8 cm further outboard (0.74 m from the
throttle), near the PCD, with a 0.36 m arm rest behind it.

### 2.7 Seat and canopy

| ID | Label as printed | Kind | Positions | Latch | What it does | Place | Conf. | Sources |
|---|---|---|---|---|---|---|---|---|
| S1 | (EGRESS placard beside it) | yellow-black striped loop ("D-ring") | pull | — | fires the seat; the canopy is shattered by its explosive cord just before | seat bucket front, between the knees | high | [^mb][^luke] |
| S2 | SAFE (window), EGRESS; "SAFE/ARM/MOH" | lever over a quadrant plate with a window | SAFE, ARM, MOH (manual override, ground egress) | latched, pinned on the ground | arms the seat; MOH frees the pilot for a quick ground egress | side of the seat bucket (which side open) | high (labels); medium (MOH) | [^luke][^mb] |
| S3 | — | switch | up / down | spring (inferred) | electric seat height, 7.4 in stroke | open | medium (exists); open (place) | [^mb] |
| S4 | — | handle | stowed / pulled | — | the simulator: fires the canopy's cord (MDC) from inside | right sill | low | [^ife] |
| S5 | — | grab handle | — | — | a handhold on the canopy bow | canopy bow | medium | [^rescue] |

The canopy has no jettison: the seat data sheet lists "Canopy jettison: No" and a canopy fracturing system[^mb];
rescue crews open it from outside ("RESCUE / EMERGENCY CANOPY RELEASE OTHER SIDE")[^rescue].

### 2.8 Not found as physical controls

No public photo or text shows a physical control for these; Code One and the simulator put them on the PCD (§3):
exterior light dimmers and modes (one Lights Master button on the throttle, §2.9), cockpit floodlight and console
dimmers, fuel dump, air-refuelling door, IFF, countermeasures programs (dispense from the HOTAS), oxygen (OBOGS with a
bottle in the seat[^mb]; no control seen), cabin temperature. Open: each could be a small switch that no photo shows.

### 2.9 HOTAS

The USAF solicitation's names[^hotas]; the grip maker lists the same functions[^essexs][^essext]. Shapes and places
on the grip are read from the maker's 500 px photos: low.

**Side-stick (S1–S10)**

| No. | Public name | Function | Shape and place on the grip (low) | Name conf. |
|---|---|---|---|---|
| S1 | Pickle | weapon release | red round button, top left of the head | high |
| S2 | TMS | target management (designate) | 4-way hat on the head | high |
| S3 | Trim | pitch and roll trim | ribbed 4-way hat, top centre | high |
| S4 | DMS | display management | 4-way hat on the head | high |
| S5 | Active Mark Point | marks a point | small switch on the side | medium |
| S6 | Expand/Zoom FOV | sensor field-of-view zoom | small switch or hat | medium |
| S7 | Trigger | gun, laser | red trigger on the front face; detents open | high |
| S8 | CMS | countermeasures management | hat or lever on the thumb side | medium |
| S9 | Paddle | autopilot disconnect | hinged lever low on the front | high |
| S10 | Pinkie | nosewheel steering | low front button | high |

**Throttle (T1–T11)**

| No. | Public name | Function | Shape (low) | Name conf. |
|---|---|---|---|---|
| T1 | Cage/Uncage | cages or uncages a seeker | small push button | medium |
| T2 | Weapons Master Mode Select | air-to-air / air-to-surface master mode | multi-position hat | high |
| T3 | Cursor Slew | PCD cursor, push to select | mini-stick on top | high |
| T4 | Virtual Speed Brake | speed brake made by the control surfaces | slide on the inboard face | high |
| T5 | Countermeasures | dispenses chaff and flares | hat or switch | high |
| T6 | AB Detent | releases the afterburner detent | finger lever | medium |
| T7 | Comm VR | radio transmit and voice-recognition press-to-recognize | multi-way hat | high |
| T8 | FLC Format Layer Control ("R2D2") | display format and layer control | domed rotary with a push (inferred) | medium |
| T9 | APC | approach power compensator (autothrottle) | button | medium |
| T10 | Polarity | infrared picture white-hot / black-hot | button | medium |
| T11 | Lights Master | exterior lights master | button or toggle, outboard | medium |

Both grips are active: the stick's forces are programmable, the throttle's detents can be moved, and the throttle
moves itself under autothrottle[^c1][^bae]. The throttle has no cut-off position (L6)[^c1].

## 3. On the display instead of switches

These are touch functions, not physical controls. Lockheed Martin moved air refuelling, flight-control tests, all
radio controls, the mission computers, IFF and navigation to the PCD[^c1]. Touch, the throttle's cursor (T3) and
voice are co-primary ways to reach every function, the cursor the backup if touch fails[^skaff].

- **Top bar** ("function access buttons"), left to right on the 2012 screenshot[^lmpcd][^hush]: engine dial; fuel
  (total, internal, external); weapons inventory; the jet's planform (gear, flight controls); ICAWS; PHM; AP; SWAP
  arrows; two radios; recorder; navigation source (ILS, TACAN); MENU; IFF codes; baro, cabin altitude, ALOW; local
  and Zulu time, wind. A bar item opens a pop-up portal (a magenta "POP-UP" tag on a FUEL portal)[^lmpcd].
- **Portals:** up to 12 windows: 4 portals with up to 8 small windows under them; 5 layouts set in mission planning,
  changed by touch in flight[^skaff][^c1]. A portal has its title top left and touch options down its right edge
  (CNTL, EXP, SEND, STOR, RECL, ASGN)[^lmpcd].
- **Formats seen in public material:** TSD 1/2, TFLIR, SMS, DAS, FUEL, HUD, HSI, AAR, ICAWS, PHM, SAR[^lmpcd][^skaff].
  The simulator adds ASR, CHKLST, CNI, DIM, EFI, ENG, FCS, SRCH, TWD, WPN-A, WPN-S and a MENU page with LITES, CRUS
  and HMD (low)[^ife].
- **Voice:** a press-to-recognize switch (T7) for radios, navigation, data entry and checklists, never for
  tactical tasks[^c1][^speech]; a pilot reports it is little used[^hush].
- **Failure:** each 10 × 8 in half has its own power and computer; if one fails, its formats move to the
  other[^lmms][^c1].

## 4. Layout sketches

Seen from the seat; forward is up in the console sketches. IDs as in §2.

```
                 ________________ glareshield (plain hood, one dome) ________________
                |                     PCD (20 x 8 in, touch)                         |
                |____________________________________________________________________|
 LEFT FORWARD PANEL          CENTRE PEDESTAL                         RIGHT FORWARD PANEL
 outboard   inboard     [P1 P2  P3 P4  P5 P6]  top strip              [R1 red/striped] [R2 rotary]
 [F1 HOOK/STOVL]        [P7 ]                 [ P12 knob ]
 [F3 JETTISON]  F2 |    [   ] [P10]  [  P11 SFD  ]
 [F4 TOW MODE]  gear|   [P8 ]        [           ]
 [F5 PARK BRK] [F6 ALT] [P9 ]        [P13]  [P14]
              [F7 LAND/TAXI]          (P15 PEDAL ADJ)
 [L1 RUDDER | L2 RESET]                                   (S1 ejection D-ring on the seat front)
```

```
 LEFT CONSOLE (forward up)          RIGHT CONSOLE (forward up)
 [L1 RUDDER][L2 FCS/ENG RESET]      [C1 side-stick][C2 STICK ACTIVE]
 [L3 throttle in its track]         [C3 arm rest]
   L4 friction  L5 THR ACTIVE
 sill: L9 canopy lever   wall: L8 DEFOG     sill (aft): S4 canopy MDC handle
 [L6 ENGINE][L7 VS BIT]
 start panel: L10 IPP  L13 CABIN PRESS
              L11 ICC1 L14 BATT  L15 IPP EMER OFF
              L12 ICC2           L16 IPP OFF/AUTO/START
```

### 4.1 Numbered photo

The mock-up's front with the IDs marked is kept with the reference files (public domain, not committed):
`callouts_bsda2026_front.jpg` in the user's `~/.claude/iaf-2026-pages/reference/f35-cockpit/`, cut from the
mock-up photo[^bsda]. The CF-1 photo[^cf1] shows the same front on a real jet.

## 5. Our Adir cockpit against the real one

Our controls are `CONSOLE_PANELS`, `CONTROLS`, the forward panel's build and `hotas()` in
`tools/f35i/cockpit3d.py` (state of 2026-11-16).

| Ours | Verdict | The real control |
|---|---|---|
| L0 BATT toggle (forward left console) | wrong place | L14, on the start panel aft of the throttle (low) |
| L0 IPP toggle | wrong place | L10 IPP master, aft start panel (low) |
| L0 ENG guarded red toggle | wrong kind, wrong place | L6 ENGINE NORM / MOTOR / OFF, three positions, aft of the throttle |
| L0 START push | wrong kind | L16 IPP OFF / AUTO / START rotary (low) |
| canopy lever, yellow, left wall aft of the throttle's track | matches | L9 (low) |
| L1 LDG LT and TAXI toggles (left wall) | wrong place, wrong kind | one toggle, F7 LAND/TAXI LIGHTS, on the left forward panel |
| L1 FORM knob | not a real physical control (belongs on the display) | lights on the PCD; T11 Lights Master |
| L2 DUMP, FUEL, AR DOOR | not real physical controls (display) | fuel and refuelling on the PCD[^c1] |
| L3 FLOOD, CONSOLE, NVIS | not real physical controls (display, low) | LITES page[^ife] |
| R1 OBOGS, BKUP O2, TEMP | not real physical controls | none seen; L13 CABIN PRESSURE is the one cabin control (low) |
| R2 CHAFF, FLARE, CMDS | not real physical controls | HOTAS T5, S8 and the PCD |
| R3 POSN, STROBE, ANTI COLL | not real physical controls (display) | T11 and the PCD |
| R4 ZEROIZE guarded toggle | wrong kind, wrong place | R2, a three-position rotary on the right forward panel |
| R4 IFF push | not a real physical control | top bar IFF and PCD[^c1] |
| R4 EMER push | not a real physical control (no source) | — |
| HMD knob + rocker, MFD knob + rocker, "OFF NT DAY" | wrong labels, missing parts | P1–P6: HMD has OFF / NIGHT / AUTO / DAY, the MFD knob NIGHT / DAY; VIDEO BRT and VIDEO CONT rockers between them; the strip spans the pedestal's top |
| ESIS with 8 side buttons | wrong kind | P11 SFD with one knob (P12) and two buttons under it (P13 ALIGN, P14 BRT) |
| gear handle, LDG GEAR UP / DN | matches (kind); place close | F2 is beside the PCD's left edge, on the left forward panel's inboard strip |
| EMER JETT push in a yellow ring | wrong kind, wrong label | F3 JETTISON rotary ALL / EXT / SEL on a striped plate |
| MASTER CAUTION and ENG FIRE push-lights | no source (not on any photo) | cautions on the PCD and helmet (§2.4) |
| side-stick: trim hat top, release ahead left, three thumb hats, trigger, lever low behind | partly matches | S1 pickle top left, S3 trim top centre, S2 / S4 hats, S7 trigger; the paddle S9 is low on the front, not behind; add S5, S6, S8, S10 |
| throttle: slew top, comm and four-way hats, boat switch, finger buttons, speed brake slide outboard | partly matches | T3 slew top, T7 comm; the speed brake T4 is on the inboard face; 11 named switches |
| throttle track, IDLE / MIL / AB | matches | no cut-off position (L3) |

Real controls we lack: F1 HOOK/STOVL, F3 as a rotary, F4 TOW MODE STATUS, F5 PARKING BRAKE, F6 ALT GEAR
EXTENSION, F7 LAND/TAXI LIGHTS, P3 VIDEO BRT, P4 VIDEO CONT, P7–P9 the radio knobs, P10 MASTER ARM, P12–P14 the
SFD's controls, P15 PEDAL ADJ, R1 the red striped switch, R2 the rotary, L1 RUDDER trim (trim stays off the mouse
by the user's rule, but the part is real), L2 FCS/ENG RESET, L4 friction (geometry only today), L5 THROTTLE ACTIVE,
L7 VS BIT, L8 DEFOG, L11–L13 ICC1, ICC2, CABIN PRESSURE, L15 IPP EMER OFF, C2 STICK ACTIVE, C3 arm rest, S1 the
ejection D-ring, S2 SAFE/ARM/MOH, S3 seat height, S4 canopy MDC handle.

Since 2026-11-16 (finish list C1b) our model carries every control above at the place listed in §2, each a moving
part with its positions; the 21 invented console switches and the standby display's eight side buttons are gone
([f35i.md](../../../docs/f35i.md) §4.2 "The real controls"). The table above is the state before that change.

Inferred from the count: the real cockpit has about 48 physical controls and indicators outside the HOTAS (§2),
against our 36 of which 20 have no real counterpart.

## 6. What remains open

- **Legends on the pedestal and the right panel:** the radio knobs' legends, MASTER ARM's positions, the right
  panel's switch name (R1) and rotary labels (R2) rest on the simulator alone; no photo reads them.
- **Left console behind the throttle, the right console, the canopy lever, the stick-active switch, the canopy MDC
  handle:** the simulator only (low). Every production-jet photo found is taken from the side, the consoles under
  the sill.
- **Single good source only:** every forward-panel legend (the mock-up); the seat height switch (data sheet);
  MASTER ARM existing (mock-up and the PCD flag).
- **Not established at all:** spring or latch behaviour of most switches; the SFD knob's function; whether a brake
  applications counter, master caution or fire lamps, physical light or oxygen controls exist; the seat SAFE/ARM
  handle's side; the HOTAS hats' number of ways and the trigger's detents; the throttle's detent positions.
- **Israeli differences:** none published. The F-35I's own C4 system, built by IAI's LAHAV division on
  software-defined radios, runs inside the jet's avionics[^iai][^globes]; the helmet is the standard Gen III made by
  Collins Elbit Vision Systems for the F-35[^cevs]. No source mentions Hebrew labels, other panels or extra switches;
  that the Adir's controls are the F-35A's is inferred.

Not readable by tools (the user may open them himself): the USMC command investigation of the 2023 F-35B mishap,
which names cockpit controls,
https://www.hqmc.marines.mil/Portals/61/Docs/FOIA/F-35%20Mishap%20CI%20-%2018%20Jan%2024%20Part%201%20of%203.pdf;
the Eielson accident report, https://www.pacaf.af.mil/Portals/6/documents/3_AIB%20Report.pdf; DVIDS search pages
(single image pages work); Wraith Systems' F-35 HOTAS user guide,
https://wraithsystems.com/wp-content/uploads/2024/05/Wraith-Systems-F-35-HOTAS-Users-Guide-v1.5.pdf; the paywalled
FlightGlobal simulator test, https://www.flightglobal.com/flight-test-f-35-simulator-virtual-fighter/75335.article;
the paywalled SAE paper 2010-01-2330 "F-35 Lightning II Cockpit Vision"; the Israeli Air Force site
https://www.iaf.org.il/ (403). Wikimedia Commons refused full-size downloads for hours (HTTP 429); its 1920 px copies
were used. No walk-around video was watched (open).

[^usersim]: An F-35 simulator cab photographed from over the headrest, supplied by the user on 2026-11-17 (a Facebook post; no direct link fetched); `user_1117_sim_cockpit_from_seat.jpg` in the reference folder.
[^bsda]: U.S. Embassy Romania, F-35 cockpit mock-up at Black Sea Defense & Aerospace, 13 May 2026 (public domain), https://commons.wikimedia.org/wiki/File:BSDA_Day_1_-_Deputy_Chief_of_Mission_Michael_Dickerson_visit_(55271792185).jpg
[^cf1]: US Navy 120120-D-BW835-017, jet CF-1 at Patuxent River, 20 Jan 2012 (public domain), https://commons.wikimedia.org/wiki/File:US_Navy_120120-D-BW835-017_Secretary_of_Defense_Leon_E._Panetta_and_Congressman_Steny_Hoyer_(D-Md)_are_shown_the_cockpit_of_the_F-35_Joint_Strike_F.jpg
[^demo2015]: US Navy 150608-N-MH885-026, F-35 cockpit demonstrator, 8 Jun 2015 (public domain), https://commons.wikimedia.org/wiki/File:F-35_demonstrator_150608-N-MH885-026.jpg
[^futenma]: USMC, F-35 cockpit demonstrator at MCAS Futenma, 17 Dec 2019 (public domain), https://www.dvidshub.net/image/5993318
[^hotas]: US Air Force Test Center, solicitation FA2823-19-Q-0050 "F-35 HOTAS throttle and side stick", 25 Jul 2019, https://sam.gov/opp/6481842093ca4c35c0461b221c26cb0b/view (mirror read: https://www.highergov.com/contract-opportunity/f-35-hotas-throttle-and-side-stick-fa2823-19-q-0050-k-bdb63/)
[^essexs]: Essex Industries, F-35 sidestick grip, https://essexindustries.com/products/f-35-joint-strike-fighter-sidestick-grip/
[^essext]: Essex Industries, F-35 throttle grip, https://essexindustries.com/products/f-35-joint-strike-fighter-throttle-grip/
[^c1]: Code One, "The New Front Office" (2006), https://www.codeonemagazine.com/article.html?item_id=35
[^lmms]: Lockheed Martin, "F-35 Mission Systems Design, Development and Verification" (AIAA, JSF18-502), https://sustainability.lockheedmartin.com/content/dam/lockheed-martin/eo/documents/webt/F-35_Mission_Systems_Design_Development_and_Verification.pdf
[^lmpcd]: Lockheed Martin PCD screenshots (approved for public release), in The Aviationist, 19 Jan 2012, https://theaviationist.com/2012/01/19/sneak-preview-f35/
[^skaff]: M. Skaff (Lockheed Martin), "The F-35 Cockpit" slides, https://www.slideshare.net/robbinlaird/the-f35-cockpit ; SLDinfo write-up (2012), https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/
[^hush]: Hush-Kit, "What is good and bad about the F-35 cockpit" (2021), https://hushkit.net/2021/01/21/what-is-good-and-bad-about-the-f-35-cockpit-a-panthers-pilots-guide-to-modern-cockpits/
[^speech]: Speech Technology, "Speech Technologies Take to the Skies in Newest Fighter Jet" (2007), https://speechtechmag.com/Articles/Editorial/Features/Speech-Technologies-Take-to-the-Skies-in-Newest-Fighter-Jet-39947.aspx
[^bae]: BAE Systems, F-35 production milestones (active inceptors), https://www.baesystems.com/en/article/bae-systems-achieves-key-production-milestones-for-the-f-35-fighter
[^mb]: Martin-Baker, US16E seat data sheet (2026), https://martin-baker.com/wp-content/uploads/2023/06/US16E-2026-Data-Sheet.pdf
[^luke]: US Air Force, egress specialists at Luke AFB, 2020 (public domain), https://www.dvidshub.net/image/6241877/egress-specialists-maintain-escape-systems
[^rescue]: US Air Force, Cope Thunder 25-2 (public domain), https://www.dvidshub.net/image/9170287 ; MacDill F-35 training (public domain), https://www.dvidshub.net/image/9611938/macdill-supports-f35-training
[^pilot]: "Pilot in F-35 cockpit", https://commons.wikimedia.org/wiki/File:Pilot_in_F-35_cockpit.jpg
[^usmc]: Code7700 case study of the F-35B 16-9591 mishap (17 Sep 2023), summarising the USMC command investigation, https://www.code7700.com/case_study_f-35_16-9591.htm
[^aero]: Aerossurance, "Cold Comfort Conference Call: USAF F-35A Alaska Accident" (2025), summarising the Eielson accident report: the pilot "initiated an FCS/ENG RESET", https://aerossurance.com/?p=27383
[^ife]: IndiaFoxtEcho, F-35 for MSFS user manual v1.2.2, pp. 28–36 (a simulator: weak), https://orbx-user-guides.storage.googleapis.com/indiafoxtecho-f35-msfs-user-guide-3475b3.pdf
[^iai]: Defense Update, "IAI Develops C4 Apps for Israel's F-35 ADIR" (2016), https://defense-update.com/?p=60082
[^globes]: Globes, "Israel Aerospace begins producing F-35 C4 systems" (2016), https://en.globes.co.il/en/article-israel-aerospace-begins-producing-f-35-c4-systems-1001115860
[^cevs]: RTX, "Collins Elbit Vision Systems delivers 3,000th F-35 Gen III Helmet Mounted Display System" (2024), https://www.rtx.com/news/news-center/2024/02/26/collins-elbit-vision-systems-delivers-3-000th-f-35-gen-iii-helmet-mounted-display
