# Air refuelling — research and design

The user picked air refuelling on 25 November 2026 ("Air refuelling"), one of the two bigger features he chose from
the never-started list. The same day he added: "Israel just got kc-47 (I think) research it" and "No need to be able
to control the refuler, it should be in coms, if available (not for every mission) and ask and get approval to
start". This page holds what public sources say about the Israeli Air Force's (IAF) tankers, the flying boom, the
procedure and the receivers' cockpits (§1 to §7), and how the sim models it (§8). Research date: 25 November 2026.

Sources are cited as footnotes. "Inferred" marks our own reasoning; "open" means no source was found;
"second-hand" means the fact is known only from a search engine's quote of a page. The US Air Force's sites (af.mil,
e-publishing.af.mil) and some news sites refused automated access, so they were left alone.

## 1. The IAF's tankers

| Fact | Source |
|---|---|
| The **Re'em** (ראם) is a Boeing 707 converted into a boom tanker. It flies with 120 Squadron ("Desert Giants") from Nevatim. | [^wiki120][^iai-howto] |
| 707-300s replaced the 707-100s in 1979. Israel Aerospace Industries (IAI, its Bedek division) converted them, and more were converted in the 2000s. | [^twz707][^fg2002] |
| The fleet: "no more than seven" in January 2025; six in service in May 2026. | [^twz707][^avn-del] |
| The boom: "Israel's earlier tankers feature a locally produced boom". In 2004 one 707 was fitted with the KC-135's boom for the first time. | [^fg2004] |
| In 2002 each tanker also had two pod-mounted hose reels for the A-4. Whether the pods are still fitted is open. | [^sp2002] |
| The boom operator sits in the main cabin and flies the boom through a locally developed 3D remote vision system: cameras at the tail, a monitor and special glasses, in use since the early 1980s. There is no rear window. | [^twz707][^twz46] |
| The crew is five: two pilots, a navigator, a flight engineer and the boom operator. A transfer "usually" takes a few minutes. | [^iai-howto] |
| The F-35I takes fuel from the Re'em: test flights with 120 Squadron before its initial operating capability, operational refuelling by 2024. The year it was cleared is open. | [^ati][^avn-f35] |
| The **KC-46A Pegasus**, named **Gideon** (גדעון) in the IAF: its first flight was announced on 4 May 2026, and the first one arrived at Nevatim on 27 May 2026 (flying as RCH301). | [^avn-del][^twz46][^boeing-del] |
| The second one arrived in August 2026: two have served since then. The order is six, with two more as an option; the US approval of 2020 covered eight. | [^eurosd][^avn-del] |
| Its squadron is reported as a new squadron, 46 (second-hand). | [^eurosd] |
| The KC-46 "will gradually replace" the 707s. No date for the Re'em's retirement is published. | [^eurosd][^twz46] |
| Israel's KC-46 has the boom, and "will be equipped with a hose-and-drogue refueling system". Which one (the centreline drogue, the wing pods or both) is open. | [^eurosd][^boeing-del] |

## 2. The offload rate

| Fact | Source |
|---|---|
| The F-16's flight manual gives the average transfer rate: 2,000 lb a minute from a KC-135 (two pumps), 3,000 lb a minute from a KC-10. | [^to1f16a] page 8-2 |
| A KC-135's boom gives up to about 6,000 lb a minute; fighters take 1,000 to 3,000 lb a minute, so the receiver sets the rate (second-hand). | [^crs] |
| The KC-46's boom: 1,200 US gallons a minute (about 8,000 lb a minute, inferred at 6.7 lb a gallon). Its centreline drogue and wing pods: 400 gallons a minute each. | [^boeing46] |
| The Re'em's rate: open. A press report gives about two minutes per fighter. | [^inn] |
| The F-35's acceptance rate: open. | |

## 3. The boom's envelope and the pilot director lights

| Fact | Source |
|---|---|
| The KC-135's envelope: the telescope's inner limit at 6 ft extended, its outer limit at 18 ft, the lowest elevation 40° below the tanker. | [^to1f16a] page 8-15, figure 8-6 |
| The KC-10's: inner limit 6 ft, outer 21 ft, lowest elevation 40°. The azimuth limits' figures are not legible in the public copy (open). | [^to1f16a] page 8-16 |
| A Boeing patent: an elevation envelope of 20° to 40° has been "acceptable based on service history". The KC-135's boom is about 27 ft long retracted and 47 ft extended. | [^pat4129270] |
| With an F-16, "the boom operator will disconnect at 25 degrees elevation (upper envelope limit)". Coming to the limits fast can pull the boom out by force (a brute-force disconnect). | [^to1f16a] page 8-12 |
| The KC-135's pilot director lights (PDLs) sit under the fuselage just aft of the nose gear, in two rows. The left row is the elevation: five coloured panels (a green-striped centre, green, red) with white reference panels between them, and the letters D (down) and U (up). The right row is the telescope, with A (aft) and F (forward). No azimuth lights: the receiver lines up on a yellow stripe along the belly. | [^to1f16a] page 8-11 |
| The KC-10's PDLs: elevation one striped green, two amber and two red triangles, with U and D; telescope a striped green, two amber, two red and four white rectangles, with A and F. The lights command the receiver's move. | [^to1f16a] page 8-11 |
| Radio silent, the PDLs show red only: steady red a large correction, flashing red a small one. Flashing PDLs with the lower beacon mean breakaway. | [^to1f16a] page 8-6 |
| The KC-46's boom is fly-by-wire, 57 ft 6 in long at full extension (second-hand), and its receiver envelope "three times larger than the KC-135". A pilot describes "lights underneath the aircraft" for fore and aft (second-hand). The exact PDL layout and envelope figures are open. | [^boeing46] |
| The KC-46's boom operators sit behind the flight deck (two seats) in front of a 3D display, with 3D glasses. The RVS 2.0 upgrade has two 4K cameras and a projector with a curved mirror. The boom is flown with the right hand and extended with the left. | [^afmag-rvs] |

## 4. The procedure

From the F-16A/B flight manual's section VIII[^to1f16a] unless marked.

- **Speed and height:** "Cruise and air refueling KCAS is 310 knots at 30,000 feet unless specifically directed
  otherwise" (page 8-2).
- **The anchor:** a left-hand racetrack, its legs 20 NM apart and at least 50 NM long (page 8-23).
- **Rendezvous (point parallel):** the tanker and the receiver fly towards each other on parallel tracks, offset by
  the tanker's turn diameter (about 9.5 NM for a KC-135 at 30° of bank). The tanker turns at the turn range and rolls
  out 1–3 NM ahead of the receiver, which flies 1,000 ft below the tanker until it has it in sight
  (pages 8-22, 8-23).
- **Observation:** the receiver flight waits on the tanker's wing (the observation position). Each receiver in turn
  goes to **pre-contact**, about 50 ft behind the contact position and a little below it, stabilises with no closure
  and is cleared to contact. It closes at 2–3 kt to the **contact** position and holds it; the boom operator flies the
  boom into the receptacle (pages 8-6, 8-27, 8-28).
- **Calls** (EMCON 2, the normal level): the receiver calls pre-contact and contact or disconnect; the boom operator
  clears the receiver to contact and answers contact and disconnect ("(call sign), contact"). The boom operator
  gives directions first, then distances ("Forward 50", "Up 4", "Back 2") (page 8-6, figures 8-1 and 8-2).
- **Breakaway:** "breakaway" called three times after the call sign. The receiver disconnects, takes the throttle
  back, descends (with the speed brake if needed) and drops back until the whole tanker is in sight; the tanker
  speeds up in level flight (page 8-35).
- **After refuelling:** the receivers rejoin on the tanker's right wing (the outside wing of their element), then
  leave, offset at least 1 NM before they climb (pages 8-12, 8-19).

## 5. The F-16's receptacle and controls

| Fact | Source |
|---|---|
| The receptacle is on the spine's centreline behind the canopy. A slipway door, worked by hydraulic system B, opens by turning its aft end down into the fuselage. | [^to1f16a] page 1-79 |
| AIR REFUEL at OPEN opens the door, puts the flight controls in their take-off and landing gains, depressurises the external tanks (no external fuel feeds, so they can be filled) and turns on the slipway's lights and the floodlights. | [^to1f16a] pages 1-78, 1-79 |
| The AR status indicator, right of the HUD: RDY (blue) the door open and the receptacle ready; AR/NWS (green) the boom latched; DISC (amber) a disconnect, with RDY again 3 s later. | [^to1f16a] page 1-80; [^f16-ar] |
| The disconnect: the NWS A/R DISC MSL STEP button on the stick. The boom also unlatches by itself when the jet's last refuel valve closes (the tanks full). | [^to1f16a] pages 1-79, 1-80, 8-34 |
| The checklist. Pre-contact: MASTER ARM off, the laser off, chaff and flares off; at night the lights dim and steady; AIR REFUEL OPEN, RDY on. Contact: AR/NWS on. Disconnect: the button, DISC on. After: AIR REFUEL CLOSE (left OPEN, the flight controls stay in the take-off and landing gains with the roll rate limited). | [^to1f16a] page 8-34 |
| The F-16I Sufa: no source of its own (open). Inferred: the Block 50/52's receptacle and controls. | inferred |

## 6. The F-35I's receptacle

- The receptacle is on the spine behind the cockpit; its doors open upward (second-hand: a search engine's quote; no page could be read). The F-35A's first boom
  contacts were in 2008, its first night refuelling from a KC-135 in 2012[^af-night].
- Its door's control: Lockheed Martin moved the air refuelling functions to the panoramic display (PCD), not a
  switch ([research/f35-cockpit.md](f35-cockpit.md) §3). The door's indications and the jet's acceptance rate: open.

## 7. Hebrew terms

| English | Hebrew | Source |
|---|---|---|
| air refuelling | תדלוק אווירי | Hamichlol[^hamichlol] |
| tanker | מטוס תדלוק (also מכלית אווירית) | Hamichlol[^hamichlol] |
| boom | בום | Hamichlol[^hamichlol] |
| boom operator | בומר | Hamichlol[^hamichlol] |
| receptacle | פתח התדלוק | Hamichlol[^hamichlol] |
| the two tankers | ראם; גדעון | Hamichlol[^hamichlol]; the IAF's post quoted by The Aviationist[^avn-del] |

No iaf.org.il page came up for these (open). The radio calls' Hebrew (§8.4) is ours around these terms, as
[radio-terms.md](radio-terms.md) does for calls with no IAF term.

## 8. How the sim models it (design, 25 November 2026)

### 8.1 The tanker

- **Type:** the KC-46A Gideon, the IAF's new tanker (§1); the 707 Re'em, which still serves, is the second type. A
  tanker is one record of figures in the AI's crate and one model. Both models are ours, low-poly, from the
  published dimensions (no free model was on disk), built by a script of our own.
- **Where:** a tanker is there only when the flight has one: a mission's flag, or Scramble's draw (not every flight;
  the user, 25 November 2026). It flies a left-hand racetrack, legs 50 NM long and 20 NM apart (§4), at 30,000 ft and
  310 KCAS: 480 kt true (ISA; inferred conversion), so its turns are flown at 18.6° of bank. The track is a path, not
  the flight model: a tanker on the track flies its autopilot, a steady platform (inferred).
- **On the radar:** the tanker is a friendly aircraft contact, as the AI jets are.
- **The boom:** a hinge under the tail, a fixed tube and a telescope. Its envelope (inferred from §3 where the KC-46's
  own figures are open):

| | KC-46A | 707 Re'em |
|---|---|---|
| boom at full extension | 57.5 ft (17.5 m) | 47 ft (14.3 m): the KC-135's boom (§1, §3) |
| telescope | 6 to 21 ft (the KC-10's) | 6 to 18 ft (the KC-135's) |
| elevation | 25° (the F-16's upper limit) to 40° | the same |
| azimuth | ±10° (inferred: the figures are open) | the same |
| contact position | 30°, the telescope's middle (inferred) | the same |
| offload | 3,000 lb a minute (inferred: the receiver's limit, the KC-10's figure, §2) | 2,000 lb a minute (the KC-135's, §2) |

- **The boom operator (the AI):** works one receiver at a time, in the order they asked. A receiver held at
  pre-contact (15 m behind the contact position and 3 m below it, within 6 m, with under 1 m/s of closure) for 2 s
  with its receptacle ready is cleared to contact. Then, with the receptacle within the envelope and within 4 m of
  the nozzle, the boom flies to it at 6° a second and 1.5 m a second of telescope, and latches within 0.15 m
  (inferred figures). In contact the boom follows the receptacle; it disconnects when the receptacle leaves the
  envelope, the receiver presses its disconnect button, closes its door, or its tanks are full. A receptacle more than
  1.5 m inside the telescope's inner limit or 5° above the upper elevation limit is a **breakaway** (inferred
  thresholds); the receiver is cleared to pre-contact again once 30 m back.
- **The pilot director lights:** two rows under the tanker's nose: elevation (D, U) and telescope (A, F), five lamps
  each: a striped green centre, then amber, then red (the KC-10's colours, §3; the KC-46's are open). The lit lamp
  commands the move: one step for each 2.5° of elevation and each 0.9 m of telescope off the contact position.

### 8.2 The receivers

- **The F-16s:** AIR REFUEL at OPEN opens the door (RDY with hydraulic system B up), and holds the external fuel
  (no feed from the external tanks while it is open, §5). The stick's NWS A/R DISC button (a key) disconnects. The AR
  status lamps work: AR/NWS on in contact, DISC for 3 s after a disconnect. The flight controls' take-off and landing
  gains are not modelled: the 6-DoF flight controls have no gains schedule by configuration.
- **The F-35I:** its door is opened and closed by the same key as the F-16's AIR REFUEL switch (the real one is a
  PCD function, §6, whose page is open); the PCD's FUEL portal shows the door's state: AR DOOR OPEN, AR CONTACT, AR
  DISC (inferred: no source shows the real indication). The same disconnect key.
- **The receptacle's place:** each jet's aircraft definition (`airframe.json` `receptacle`: forward, right, up metres
  from the model's centre), read off the models (inferred).
- **Fuel:** the offload fills the jet's tanks from the engine out, at most to their capacity.
- **The door seen from outside** (`shared/aircraft/ar_door.gd`): open, a dark opening on the spine at the receptacle
  and the door's leaf, by the aircraft definition's `receptacle_door`. The F-16s: the slipway, the leaf ahead of the
  receptacle (§5). The F-35I: one leaf up about its aft edge (§6: "its doors open upward"; the leaf's hinge inferred).
  The models have no cut there, so the opening is drawn flush on the spine; the sizes (0.34 m by 0.62 m) are
  inferred. The player's door follows the AIR REFUEL switch (or the F-35I's door key); an AI jet's is open while the
  tanker has it as a receiver.

### 8.3 The radio (the user's words: "in coms, if available … ask and get approval to start")

The tanker is an addressee on the radio menu's first page only while the flight has one. The player's one call is
**Request refuelling**; everything after it is the boom operator's:

1. The player: "Gideon, Kidon 1, request refuelling." The tanker: "Kidon 1, Gideon, cleared pre-contact", or, with
   another jet on the boom, "Kidon 1, stand by, observation left".
2. Held stable at pre-contact with the receptacle ready: "Kidon 1, cleared contact".
3. Latched: "Kidon 1, contact".
4. Unlatched: "Kidon 1, disconnect".
5. Too close or too high: "Kidon 1, breakaway, breakaway, breakaway".
6. Full: "Kidon 1, refuelling complete, cleared right wing"; the next receiver is cleared to pre-contact.

The player's wingmen: the wingmen's command **Refuel** sends the AI wingmen addressed to the tanker; each asks in
turn, waits on the tanker's left wing (the observation position), refuels, then waits on the right wing until the
last one is done, and rejoins the lead.

### 8.4 The calls' words

| call | English voice | Hebrew subtitle (ours around the terms of §7) |
|---|---|---|
| request | "Gideon, Kidon 1, request refuelling." | "גדעון, כאן כידון 1, בקשת תדלוק" |
| cleared pre-contact | "Kidon 1, Gideon, cleared pre-contact." | "כידון 1, כאן גדעון, אישור לעמדת טרום מגע" |
| stand by | "Kidon 1, stand by, observation left." | "כידון 1, המתנה בעמדת תצפית משמאל" |
| cleared contact | "Kidon 1, cleared contact." | "כידון 1, אישור למגע" |
| contact | "Kidon 1, contact." | "כידון 1, מגע" |
| disconnect | "Kidon 1, disconnect." | "כידון 1, ניתוק" |
| breakaway | "Kidon 1, breakaway, breakaway, breakaway." | "כידון 1, ניתוק חירום, ניתוק חירום, ניתוק חירום" |
| complete | "Kidon 1, refuelling complete, cleared right wing." | "כידון 1, התדלוק הושלם, אישור לכנף ימין" |
| refuel (lead to wingmen) | "Kidon 1, refuel." | "כידון 1, תדלוק" |

The tanker's callsign is its type's name, Gideon or Re'em (ours: the IAF tankers' callsigns are open). The boom
operator's voice is a role of its own.

### 8.5 Built

Built 25 November 2026: the tanker and its boom operator `crates/iaf-ai/src/tanker.rs` (`IafTanker`), the scene
`shared/ai/tanker.gd`, the models `tools/tanker/build.py`, the radio `modern-iaf/flight/sim_flight.gd` and
`shared/audio/radio.gd`, the AI wingmen [../../../docs/ai.md](../../../docs/ai.md) §25. The figures this section calls
inferred are those constants.

### 8.6 Not modelled

The rendezvous's geometry (the tanker flies its track; the player finds it on the radar and flies
to it), the hose and drogue, the boom operator's directions by distance ("Forward 50"), the radio-silent (EMCON 3)
procedure, the tanker's speed-up on a breakaway, the lights at night, the brute-force disconnect, and the flight
controls' gains with the door open (§8.2).

[^to1f16a]: T.O. 1F-16A-1, Flight Manual, F-16A/B Block 10 and 15, August 2003 (change 13): section I, the air
    refuelling system, pages 1-78 to 1-80; section VIII, pages 8-2 to 8-36.
    <https://archive.org/details/to-1-f-16-a-1-flight-manual-f-16-a-b-block-10-15-august-2003>
[^f16-ar]: T.O. GR1F-16CJ-1, "Air Refueling (AR) Status Indicator", page 1-78 (RDY blue, AR/NWS green, DISC amber);
    the source of the sim's F-16 lamps ([cockpit.md](../cockpit.md)).
[^wiki120]: Wikipedia, "120 Squadron (Israel)". <https://en.wikipedia.org/wiki/120_Squadron_(Israel)>
[^iai-howto]: Israel Aerospace Industries, "Air refueling: this is how it's done".
    <https://www.iai.co.il/news/air-refueling-this-is-how-its-done/>
[^twz707]: The War Zone, "Our Best Look So Far Inside Israel's Once Secretive 707 Tankers", 6 January 2025.
    <https://www.twz.com/air/our-best-look-so-far-inside-israelis-once-secretive-707-tankers>
[^fg2002]: FlightGlobal, "Israel convert more Boeing 707s into tankers", 29 January 2002.
    <https://www.flightglobal.com/isreal-convert-more-boeing-707s-into-tankers/45140.article>
[^fg2004]: FlightGlobal, "Israel invests in refuelling", 20 April 2004.
    <https://www.flightglobal.com/israel-invests-in-refuelling-/54074.article>
[^sp2002]: StrategyPage, "Support: March 1, 2002". <https://www.strategypage.com/htmw/htcbtsp/articles/20020301.aspx>
[^inn]: Israel National News, "Refueling midair", 8 June 2014. <https://www.israelnationalnews.com/news/181482>
[^ati]: Aerospace Testing International, "Israeli Air Force moves F-35 towards IOC".
    <https://www.aerospacetestinginternational.com/news/flight-testing/israeli-air-force-moves-f-35-towards-ioc.html>
[^avn-f35]: The Aviationist, "Key Insights from the Video of the Israeli F-35I Adir Refueling over Lebanon",
    26 August 2024. <https://theaviationist.com/2024/08/26/israeli-f-35-over-lebanon-video/>
[^avn-del]: The Aviationist, "Israeli Air Force Takes Delivery of Its First KC-46A 'Gideon'", 27 May 2026.
    <https://theaviationist.com/2026/05/27/israeli-air-force-takes-delivery-of-its-first-kc-46a-gideon/>
[^twz46]: The War Zone, "Israel's First KC-46 Tanker Is Now Flying", 4 May 2026.
    <https://twz.com/air/israels-first-kc-46-tanker-is-now-flying>
[^boeing-del]: Boeing, "Boeing delivers first KC-46 to the Israel Air Force", May 2026.
    <https://www.boeing.com/features/2026/05/boeing-delivers-first-kc-46-to-the-israel-air-force>
[^eurosd]: European Security & Defence, "Israel's second KC-46 Pegasus", 24 August 2026.
    <https://euro-sd.com/2026/08/news/53284/israel-second-kc-46-pegasus/>
[^boeing46]: Boeing, "KC-46 Pegasus" (product page). <https://www.boeing.com/defense/tankers-and-transports/kc-46-pegasus>
[^crs]: Congressional Research Service, RL32910, "Air Force Aerial Refueling Methods: Flying Boom versus
    Hose-and-Drogue", 11 May 2005.
    <https://www.everycrsreport.com/files/20050511_RL32910_69ac8cdf47521ce623859aeb2825c6114529793c.html>
[^pat4129270]: US Patent 4,129,270, "Air refueling boom pivot gimbal arrangements".
    <https://patents.google.com/patent/US4129270A/en>
[^afmag-rvs]: Air & Space Forces Magazine, "Eyes on the Boom: Re-visioning the KC-46", 20 January 2023.
    <https://www.airandspaceforces.com/article/eyes-on-the-boom-re-visioning-the-kc-46/>
[^af-night]: Edwards Air Force Base, "F-35A completes first night refueling mission".
    <https://www.edwards.af.mil/News/AFMC-News/Article/153683/f-35a-completes-first-night-refueling-mission/>
[^hamichlol]: Hamichlol, "תדלוק אווירי". <https://www.hamichlol.org.il/תדלוק_אווירי>
