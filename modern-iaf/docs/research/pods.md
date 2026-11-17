# Targeting and navigation pods (LANTIRN, Litening) — research

This page records what public sources say about the pods the Israeli Air Force's F-16I Sufa, F-16C/D Barak and F-15I
Ra'am carry, what the pilot sees and does with each, what Modern IAF has today, and what the game would need. It is
research only: it changes no code or data. The user asked for it on 17 November 2026: "do some reaserch about
lantrin/lighning pods and what needs to be added to the game, don't impl yet." Research date: 17 November 2026; round 2 the same day, after the user's answers (§7).

**Terms**
- **TGP:** targeting pod; also the F-16 MFD format that shows its picture.
- **Navigation pod:** a pod with a fixed, wide forward-looking infrared (FLIR) camera whose picture is shown on the
  HUD, and on the LANTIRN AN/AAQ-13 also a terrain-following radar (TFR).
- **SCP:** set clearance plane, the height above the ground that terrain following holds.
- **SOI:** sensor of interest, the display the cursor and the HOTAS act on.
- **5L / 5R:** the F-16's two chin hardpoints under the left and right sides of the engine intake.
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning; "open" means no source
  was found. A source marked **secondary** is a simulator manual, a simulator community page or a forum: it shows the
  public F-16 procedures as simulators model them, not the IAF's own.

Scope: what each pod does for the pilot. Sensor ranges, weapon and guidance performance and countermeasures are out
of scope (the project's parked rows, [../avionics-plan.md](../avionics-plan.md) §7). Laser designation appears only
as the cockpit procedure.

## 1. The answer first: which navigation pod each F-16 carries

Round 2 (17 November 2026), after the user's "search more. I preatty sure both the D and the I use LANTIRN". The
grades: **primary** = the IAF's own pages or a US government notice; **dated photograph** = a dated service photo
described by a reputable page (we did not download or view the pictures themselves: their captions are the
evidence); **secondary** = trade pages, encyclopedias, forums; **not found**.

| jet | navigation pod | targeting pod | grade |
|---|---|---|---|
| F-16I Sufa | **LANTIRN navigation pod, AN/AAQ-13** (with its terrain-following radar), on one chin station | Litening on the other | navigation pod: **primary** (IAF) and **dated photograph** (2007); Litening: primary (IAF) |
| F-16C/D Barak | **Pathfinder** from 1992: Lockheed Martin's export derivative of the AN/AAQ-13, a navigation FLIR **without** the terrain-following radar | **Sharpshooter** from 1992 (the AN/AAQ-14's export derivative), later the Litening | Pathfinder and Sharpshooter: **secondary** (one trade report); Litening replacing the Sharpshooter: secondary; an AN/AAQ-13 on the Barak: **not found** |

**The Sufa, the evidence:**
- The IAF's site: "To navigate at low altitude, in all visibility and weather conditions, the F-16I will be equipped
  with the navigation pod of the LANTIRN system" (כדי לנווט בגובה נמוך, בכל תנאי ראות ומזג-אוויר, יצויד ה-F-16I בפוד
  הניווט של מערכת הלנטירן), and the jet "will carry two pods beneath its air intake: a Litening pod for locating and
  acquiring targets, and a LANTIRN pod for navigation" (פוד לייטנינג לאיתור ולרכישת מטרות, ופוד לנטירן לניווט); the
  IAF calls the pairing a first of its kind[^iaf-f16i-next]. The IAF's magazine: the Sufa's navigation pod lets it fly
  low "at a fixed height and speed without the pilot's intervention"[^iaf-mag-sufa]. The IAF's Sufa page lists the
  LANTIRN navigation pod beside the Litening[^iaf-sufa]. The IAF's pages refused automated access; these quotes are
  as the search engine returned them from the pages (no other route was tried).
- The IAF describes the LANTIRN navigation pod as a FLIR night sensor and a terrain-following radar that warns of
  obstacles (its F-15I page)[^iaf-raam]: so the Sufa's pod is the AN/AAQ-13, not a FLIR-only derivative (inferred
  from the IAF naming the same LANTIRN navigation pod on both jets).
- Dated photograph: one of the F-16Is of the September 2007 strike on the Syrian reactor, released by the IDF in
  March 2018; The War Zone's caption: "the jet only carriers the navigation pod of its LANTIRN system, with the
  targeting pod left off"[^twz-syria].
- Agreeing secondary sources: Airforce Technology[^at-sufa]; the 2003 roll-out "carried both Lantirn pods"[^f16net-il];
  Joe Baugher: "The F-16I contract will also include Lockeed Martin LANTIRN navigation and targeting
  pods"[^baugher-f16i].
- 2026: no dated photo after 2018 found; the IAF's March 2026 RAMPAGE picture's write-ups name no pods[^dif-rampage].
  The IAF keeps buying the AN/AAQ-13 (50 for the F-15IA / F-15I+, 2024[^crec-2401]). In service on the Sufa in 2026:
  inferred.

**The Barak, the evidence:**
- Forecast International (February 2003): "Israel followed suit and ordered 10 Pathfinder pods and 20 Sharpshooter
  pods for delivery in 1992"; its distribution table: Israel 33 Pathfinder and 30 Sharpshooter pods; timeline "1992
  Israel receives Sharpshooter and Pathfinder pods"[^fi-pathfinder]. The Pathfinder "was designed as a scaled-down
  version of Lockheed Martin's LANTIRN AAQ-13"; "Unlike the LANTIRN navigation pod ... there is no
  terrain-following radar subsystem"; it "can present FLIR imagery on any standard Head-Up Display"; 198 cm long,
  84 kg[^fi-pathfinder]. Which IAF jets carried them is not stated; the Barak (F-16C/D, Block 30 and 40, delivered
  from 1987) is the IAF's F-16 of 1992 that F-16.net ties to the Sharpshooter (inferred for the Pathfinder too).
- The Sharpshooter "is a derivative of the LANTIRN AAQ-14 targeting pod", without "the missile boresight correlator
  used for target hand-off to Maverick (IR) missiles"[^fi-pathfinder]; F-16.net: "a downgraded version of the Martin
  Marietta AN/AAQ-14 LANTIRN targeting pod", fitted to the IAF's F-16C/D first, "later replaced by the Rafael Litening",
  the Sharpshooters going to the F-15I[^f16net-il]; F-16.net's LANTIRN page: "Pathfinder and Sharpshooter are
  (cheaper and slightly less capable) derivatives"[^f16net-lantirn].
- The 1998 US offer of 60 F-16C/D "equipped with LANTIRN pods" was not taken up: Israel bought the F-16I
  instead[^f16net-il][^baugher-f16i].
- Not found: any IAF page, notice or dated photo of an AN/AAQ-13 on a Barak; which navigation pod, if any, the
  Barak 2020 upgrade (completed 2014[^w-f16var]) flies with today.

**What round 1 got wrong.** Round 1 called the Sufa's navigation pod "commonly repeated, not confirmed" and read the
Litening's wide view as the Sufa's navigation picture: wrong; the IAF's own pages confirm the LANTIRN navigation pod.
Round 1 said the Barak flew the Sharpshooter then the Litening, "never LANTIRN": incomplete; the Sharpshooter is the
AN/AAQ-14's export derivative and the IAF also bought the Pathfinder, the AN/AAQ-13's FLIR-only derivative, both
delivered in 1992. The user's "both the D and the I use LANTIRN" holds for the Sufa exactly and for the Barak as the
LANTIRN family's export pods.

## 2. The pods

### 2.1 LANTIRN navigation pod, AN/AAQ-13

- **What it is:** a pod with a terrain-following radar and a fixed FLIR whose picture of the terrain ahead is shown
  on the HUD; the radar gives the flight control system the input to hold a preselected height above the
  terrain[^fas-lantirn][^w-lantirn]. Weight 204.6 kg[^w-lantirn] (FAS: 211.5 kg[^fas-lantirn]).
- **On the F-16:** the left chin hardpoint, 5L: the HTS pod is "mounted on the port intake hardpoint in place of
  the LANTIRN navigation pod"[^w-f16var]. The US flew it on the Block 40/42, built "with strengthened undercarriage
  for LANTIRN pods"[^w-f16var].
- **IAF:** the F-15I from 1996 ("Israel is buying both the LANTIRN navigation pod and the Sharpshooter targeting
  pod for its F-15Is", [../../../docs/f15i.md](../../../docs/f15i.md)); 50 more for the F-15IA / F-15I+ in
  2024[^crec-2401]. The F-16I Sufa: confirmed by the IAF (§1). The F-16C/D Barak: the Pathfinder, its derivative
  without the radar (§1); an AN/AAQ-13 not found.
- **In 2026:** on the Sufa (inferred, §1) and being bought for the F-15IA (sourced); its use is not public.

### 2.2 LANTIRN targeting pod, AN/AAQ-14, and the Sharpshooter

- **What it is:** a FLIR, a laser designator-rangefinder, automatic target tracking and a Maverick hand-off; 240 kg
  (Wikipedia) / 235.8 kg (FAS)[^w-lantirn][^fas-lantirn]. The Sharpshooter is the AN/AAQ-14's export derivative,
  the same pod without the Maverick hand-off[^fi-pathfinder][^f16net-il]; its navigation partner, the Pathfinder, is
  the AN/AAQ-13's without the terrain-following radar (§1).
- **On the F-16:** the right chin hardpoint, 5R (inferred from the HTS-on-the-left rule above and an F-16A test
  jet's LANTIRN on 5R[^ah-5r]).
- **IAF:** the Barak was "originally fitted with the Martin-Marietta Sharpshooter pod"; the Sharpshooters were
  "later replaced by the Rafael Litening" and went to the F-15I[^f16net-il]. The F-15I later took the Litening
  too[^hm-lantirn][^w-litening].
- **In 2026:** no source shows an AN/AAQ-14 or Sharpshooter in IAF service. Retired (inferred).

### 2.3 Litening (Rafael; Northrop Grumman in the US as AN/AAQ-28)

- **What it is:** a stabilised turret with a FLIR, a CCD television camera, a laser designator-rangefinder, a laser
  spot tracker and an infrared marker[^at-sufa][^fas-litening]; three fields of view, the wide one on the HUD for
  navigation, the medium and narrow on a head-down display for target selection[^fas-litening]. 208 kg, 2.20 m long,
  40.6 cm across[^w-litening].
- **Versions:** Litening I (for the IAF), II (1999), ER (2001), AT (2003), III, G4 (2008), 5 (2019), SE; Litening III
  adds still images for reconnaissance[^w-litening]. In 2026 a Litening with a synthetic aperture radar "reportedly
  played a significant role" in the strikes on Iran (one report, attributed to Israeli sources; the jets not
  named)[^esd-2026].
- **IAF jets:** F-16I Sufa (Wikipedia: "Litening C4", citing F-16.net; Airforce Technology: "Litening II";
  Hamichlol: "Litening 3"), F-16C/D Barak (replaced the Sharpshooter; "probably upgraded to Litening III"), F-15I
  (Litening III)[^w-litening][^at-sufa][^hm-litening][^f16net-il]. Which version flies on which jet in 2026 is open;
  the version names disagree.
- **Station:** a chin hardpoint (a Litening on the usual chin station of an F-16C[^twz-litening]). The side, round 2
  (the user: "search"): the IAF says only "beneath its air intake" for both pods[^iaf-f16i-next]. No dated photo
  description names a side. Secondary: a modelling forum lists the Sufa's "LANTIRN nav pod and LITENING II tgt pod
  on 5L/5R"[^bm-sufa], the F-16's rule puts the navigation pod on the left (5L)[^w-f16var][^f16net-lantirn], and
  Airforce Technology's caption "Litening II targeting pod (on the left) and the LANTIRN navigation pod (on the
  right)"[^at-sufa] reads the same way if it describes a photo taken from ahead (inferred). Result: **the Litening
  on the right chin station (5R), the LANTIRN navigation pod on the left (5L): secondary sources only**. The Barak:
  the same by the F-16's rule (inferred; not found for the Barak itself). The Ra'am's pod hangs under the left intake in 2021 and 2024 photos (type
  not readable; [../../../docs/f15i.md](../../../docs/f15i.md)).
- **In 2026:** in daily use; Rafael says the IAF uses targeting pods heavily and that the local pods "proved their
  superiority" over the US ones it had (December 2023)[^dif-gaza].

### 2.4 Other pods the IAF's jets carry

| pod | jets | pilot-facing function | source |
|---|---|---|---|
| Electronic jammer (Elisra SPS-3000; Elbit ASPS from 2025) | Sufa | internal, in the spine: not a pod. The pilot's side is the RWR and the jammer switch ([../avionics-plan.md](../avionics-plan.md) E1–E3) | [^at-sufa][^f16net-il] |
| Elta EL/L-8240 ECM | Barak (third batch) | internal: not a pod | [^f16net-il] |
| External ECM pod | none shown | open: no source shows an external jamming pod on today's IAF fighters (Rafael's Sky Shield exists; no IAF fighter use found) | open |
| Reconnaissance pod (RecceLite) | open | a Rafael reconnaissance pod with a ground station; no source ties it to IAF fighters. The Sufa's navigator says the jet takes photos of the target area[^twz-sufa]; the sensor is not named (the Litening III's still images would do it, inferred) | [^w-litening] |
| Training range pod (ACMI) | inferred | none: records the flight for the debrief | inferred |

The F-35I carries no pod: its targeting sensor (EOTS) is built in ([../avionics-plan.md](../avionics-plan.md) P4).

## 3. What the pilot sees and does

The IAF's own procedures are not public. Each item below is the public F-16 (or F-14) description, inferred for the
IAF jets. In the two-seat Sufa and Barak the back-seater, whom the IAF calls the navigator[^twz-sufa], usually works
the pod (inferred); in the game the player flies alone and does both (decided, §7).

### 3.1 The targeting pod page (F-16)

From the Block 50 dash-34's LANTIRN TGP format, already traced in
[../../../docs/real-mfd.md](../../../docs/real-mfd.md#wpn-and-tgp-game-pages-5-tv-and-6-flir): the top row `STBY` / `A-A` / `A-G`,
`WIDE` / `NARO`, `OVRD`, `CNTL`; on the right `WHOT` / `BHOT` and `CZ`; on the left the gain and level; `NOT TIMED OUT`
while the detector cools; bottom right the time to steerpoint, release or impact with `L` (laser range) or `T`
(passive); a box around the page when it is the SOI. The pilot's steps (the public F-16 flow, inferred for the Sufa;
secondary sources[^dcs-f16][^hb-lantirn][^bms-forum-laser]):

1. **Power and cool-down:** the pod's power switch, then wait out `NOT TIMED OUT`.
2. **Mode:** A-G or A-A on the page.
3. **Where it looks:** slaved to the steerpoint or to the radar's designation (the sensor point of interest) until
   the pilot moves it; with the TGP the SOI, the cursor slews the picture.
4. **Field of view:** WIDE / NARO, with a digital expand of the narrow view (F-14 LANTIRN: wide, narrow, expanded,
   the last "a digital zoom of the Narrow FoV"[^hb-lantirn]).
5. **Track:** TMS up starts a track; point track holds a vehicle, area track holds a patch of ground, with no track
   the line of sight is inertially stabilised (the branch's `INR`, §4); TMS down returns to slaved.
6. **Picture:** FLIR white-hot / black-hot, gain and level; CCD TV by day on the Litening[^fas-litening].
7. **Laser:** LASER ARM on the cockpit's switch panel; with the TGP the SOI and its line of sight not blocked by the
   jet, the trigger's first detent fires the laser while held[^bms-forum-laser]; the page shows the laser code and
   `L` flashing while it fires (F-14 LANTIRN[^hb-lantirn]). Laser spot search (the Litening's spot tracker) looks for
   another jet's laser spot[^fas-litening].
8. **HUD:** the pod's line of sight shows as the target designator box on the HUD and steering to the designated
   point (dash-34, already drawn by `crates/iaf-avionics/src/real_hud/f16.rs`); the Litening's wide view can fill the
   HUD as a navigation picture (§3.2).

### 3.2 The navigation FLIR on the HUD

The Sufa's LANTIRN navigation pod (and the Barak's Pathfinder, which "can present FLIR imagery on any standard
Head-Up Display"[^fi-pathfinder]; the Litening's wide field of view the same way) is drawn on the HUD as a picture of the
terrain ahead, under the HUD symbols[^fas-lantirn][^fas-litening]. The public F-16 flow (secondary: a Falcon BMS
community page that follows the dash-34[^bms-tfr]):
- the FLIR format: STBY, a 7–15 minute warm-up, then OPER puts the picture on the HUD; boresight from the format;
- the ICP's FLIR rocker sets gain, the ICP's brightness the picture's brightness;
- snap-look (DMS up with the cursor) shifts the picture sideways or up for a moment; look-into-turn shifts it into a
  bank; the flight path marker turns dashed while the picture is shifted.

The dash-34's FLIR format layout (pp. 1-241..1-249) is not traced ([../../../docs/real-mfd.md](../../../docs/real-mfd.md)).

### 3.3 Terrain following (LANTIRN TFR, F-16)

Public sources say only that the TFR holds a selected height and feeds the flight control system[^fas-lantirn]. The
cockpit side (secondary: the Falcon BMS community page following the dash-34[^bms-tfr]):
- **Modes:** NORM, WX (rain), LPI (low emission), VLC (very low clearance); the MISC panel's RF switch limits them.
- **Settings:** the TFR format's SCP (1,000 ft in the training exercise; the page lists 1,000 / 500 / 300 / 200 ft
  and VLC, per an operations-guide excerpt the search engine quoted, not seen) and the ride (HARD; SOFT and SMOOTH
  not described); the radar altimeter's ALOW set about 10 % below the SCP.
- **Automatic TF:** the ADV MODE button (green ACTIVE) couples the pitch to the TFR's commands; the pilot keeps roll
  and speed. **Manual TF:** the pilot flies the HUD's TF box; fly-up protection only with the FLCS panel's manual TF
  fly-up switch on ENABLE.
- **Cues and warnings:** the HUD's TF box, LIMIT, a flashing speed scale outside the TF speed band, NO TER, LO TF;
  a fly-up (about 2 g) when below a share of the SCP; OBSTACLE and G-LIMIT fly-ups with an X on the MFDs; PULL-UP on
  the HUD and in the voice; TF FAIL, rolling wings level and pulling up. The paddle switch holds off a fly-up while
  pressed.

These rows are secondary; a primary public source for the TFR format and cues is open.

### 3.4 Per jet

| jet | targeting pod | navigation picture | terrain following |
|---|---|---|---|
| F-16I Sufa | Litening (§2.3), the F-16 TGP format | the LANTIRN navigation pod's FLIR on the HUD (§1) | the LANTIRN navigation pod's TFR: the IAF ties the Sufa's automatic low flight to the pod[^iaf-mag-sufa][^iaf-f16i-next]; the radar's TF mode is named by one trade page only[^at-sufa] |
| F-16C/D Barak | Litening (it replaced the Sharpshooter[^f16net-il]) | the Pathfinder's FLIR on the HUD (§1; in 2026 open) | none: the Pathfinder has no TFR[^fi-pathfinder]; no radar TF mode found for the Block 30/40 (not found) |
| F-15I Ra'am (not flown yet) | a pod under the left intake (Litening per two encyclopedias[^w-litening][^hm-lantirn]) | the LANTIRN navigation pod[^crec-2401] | the LANTIRN TFR[^crec-2401] |
| F-35I Adir | built-in EOTS | the DAS and EOTS in the helmet | none |

Correction for [../avionics-plan.md](../avionics-plan.md) row B5 ("LANTIRN on the Block 40"): the IAF's Barak
carried the LANTIRN family's export pods, the Sharpshooter and the Pathfinder (1992), then the Litening in place of
the Sharpshooter (§1). The plan's decided §8.2 (the Litening on both F-16s) matches this.

## 4. What Modern IAF has today

- **The plan:** [../avionics-plan.md](../avionics-plan.md) rows M6 (TGP), S11 (laser bombs), B5, R14 (TF parked),
  gap G15, slice 4; the user's "yes" to the Litening and the GBU-10 / 12 / 16 on both F-16s (§8.2).
- **Shared logic (reborn's, reused):** the EO sensor `crates/iaf-avionics/src/eo.rs` (TV / FLIR mode, WIDE / SPOT,
  zoom 1–8, slew, gimbal limits, the laser flag) through `shared/weapons/eo_sensor.gd`; the laser bombs' aim
  `crates/iaf-avionics/src/release.rs` (`laser_aim`) and `tests/godot/test_laser_bombs.gd`; the TGP format in
  `shared/cockpit/f16_mfd.gd` (`tgp`); the HUD's target box in `crates/iaf-avionics/src/real_hud/f16.rs`. A pod is
  found by its store name (`TGP`, or the 1998 game's `FLIR`) in `shared/weapons/player_weapons.gd`; the F-35I and the
  Ra'am have a built-in pod (`flir_pod`).
- **Slice 4, merged 17 November (6af62293)**, as read on its branch in round 1: the weapon records
  `modern-iaf/data/db/weapons/litening.json`, `gbu-10.json`, `gbu-12.json`, `gbu-16.json`; the Litening on the sim's
  station 5 of both F-16s (`modern-iaf/data/db/units/f16i.json`, `f16d.json`),
  renamed "chin" (the right chin hardpoint under the intake, x 0.69 m under the model's right chin pylon since P2, in `crates/iaf-tools/src/sim.rs`), 208 kg,
  drag index 7.0 (inferred), store name `TGP`; the laser bombs on 3 / 7 and 4 / 6 of both F-16s; the kinds `pod` and
  `laser_bomb`; keys DMS and LASER ARM (`modern-iaf/data/keys.json`); in `crates/iaf-avionics/src/f16_mfd.rs` the
  modern MFD frame with SOI, DMS and the TGP's track legend (`AREA`, `POINT`, `INR`, none when slaved), and in
  `shared/cockpit/f16_mfd.gd` the track mode and `ARM` drawn on the TGP page.
- **Models:** `shared/extra/models/stores/flrpod.glb` is the **AN/AAQ-13 navigation pod** (FlightGear F-16,
  `AN-AAQ-13.ac`, GPL-2.0-or-later; `shared/extra/models/stores/SOURCES.md`), kept for the navigation pod (P9).
  The Litening record draws `litening.glb` (P2, 17 Nov), FlightGear's `LITENING_AT/AN-AAQ-28.ac` (the Litening AT) from
  the same checkout and commit, the same GPL-2.0-or-later and credited authors, at the real 2.20 m by 0.406
  m[^w-litening] ([../../../docs/aircraft-models.md](../../../docs/aircraft-models.md) §5.1). `ecmpod.glb` is an
  AN/ALQ-131. The same repository also holds `LANTIRN/AN-AAQ-14.ac` and `SniperATP`.
- **Missing everywhere:** a navigation FLIR picture on the HUD, terrain following for the player's jet (the AI's
  autopilot has a terrain-following leg, `crates/iaf-flight/src/autopilot.rs`, not a TFR), the TFR and FLIR formats
  (gap G16), laser spot search, the laser code, the pod's own power and cool-down.
- **Conditions:** every sim mission flies by day (`modern-iaf/data/missions/`, "the MVP's conditions: day"); the
  goggles (Shift+N, `shared/settings.gd`) exist. Night missions do not come first (decided, §7).
- **No navigation pod store and no station for a second chin pod:** the sim's station 5 holds one store.

## 5. What would need to be added (pick list)

Size as in [../avionics-plan.md](../avionics-plan.md) §5: S = up to a day's agent work, M = a few days, L = a week or
more. Kind: **wire** = existing logic reached; **extend** = existing logic grown; **new** = new logic.

| # | item | what the player gains | size | kind | model / art | slice |
|---|---|---|---|---|---|---|
| P1 | The Litening and laser bombs | the pod on the loadout, the TGP page, lasing, GBU-10 / 12 / 16 hits | (merged 17 Nov) | wire | — | 4 (G15) |
| P2 | Litening model: convert FlightGear's `AN-AAQ-28` in place of the AAQ-13 stand-in (approved and merged 17 Nov) | the right pod on the jet in the hangar, loadout and flight | S | art | FlightGear F-16 `LITENING_AT`, GPL-2.0-or-later, authors already credited | 4 |
| P3 | Barak: fix row B5 in the plan (the Litening is already on its station 5, slice 4) | the plan as the IAF flew it | S | docs | — | 6 |
| P4 | **Pod stations: split the sim's station 5 into 5L / 5R** (and a centreline 5): the navigation pod on 5L, the Litening on 5R (§2.3); weight and drag per pod; jettison keeps the pods. Now needed: both F-16s carry two chin pods | the real two-pod load, its weight and picture | M | extend (`sim.rs` stations, unit records, the loadout screen) | — | 6 |
| P5 | TGP cockpit procedure complete: pod power and cool-down, WIDE / NARO / expand, WHOT / BHOT, CCD TV, laser code, `L` flashing, the trigger's first detent as the laser key, masking by the jet | the real pod workflow | M | extend (`eo.rs`, `f16_mfd.rs` / `.gd`) | — | 4 (rest) or 9 |
| P6 | Laser spot search: find a wingman's or a ground team's laser spot | buddy lasing in missions | M | new (`eo.rs`; a lasing wingman in the AI) | — | 9 |
| P9 | **Navigation pods as stores on 5L:** the AN/AAQ-13 on the Sufa (204.6 kg[^w-lantirn]); the Pathfinder on the Barak (84 kg, 198 cm[^fi-pathfinder]) | the pod on the jet, its weight and drag; the FLIR and TF items need it | S | wire (data) | the AAQ-13: `flrpod.glb` (already ours); the Pathfinder: none found (the AAQ-13 shape is a stand-in, inferred) | 6, with P4 |
| P7 | **Navigation FLIR on the HUD** with the navigation pod (both jets): the FLIR format's STBY / OPER and warm-up, a thermal-look picture drawn inside the HUD, gain / level, snap-look; usable by day and at night (the user's "no" to night missions first) | the HUD picture of the terrain ahead | M–L | new (render; GPU budget on the Iris Xe) | none (a shader) | 6, after P9 |
| P8 | **Terrain following, Sufa only** (the AN/AAQ-13's TFR; the Barak's Pathfinder has none): the TFR format, SCP, ride, automatic TF on the pitch channel, manual TF box, fly-ups, TF FAIL, the HUD cues | low-level flight hands-off | L | new (`crates/iaf-flight` pitch command from `heights.rs`; `real_hud/f16.rs` cues) | none | low priority (the user's "yes, not in priority"); G12's TF row moves from the radar to the pod |
| P10 | Ra'am pods when the F-15I flies: Litening on the left intake, LANTIRN navigation pod | the strike eagle's night kit | M | wire + P7 / P8 | `flrpod.glb`, P2's model | Ra'am (not planned) |
| P11 | TGP page polish against the Litening (its own legends, not LANTIRN's) | closer look | S | extend | — | open: no public Litening page |

Left out: a reconnaissance pod (no source ties one to IAF fighters), an external ECM pod (none shown; and the parked
countermeasure rows), the Litening's SAR mode (one 2026 report; parked as sensor performance).

## 6. Recommendation (priority order)

Re-ordered after the decisions of §7:
1. **P2, P12, P13:** the real Litening shape, and the rule that the laser bombs need the pod (P1 merged).
2. **P4 and P9 together:** the 5L / 5R stations and the navigation pods as stores, the AN/AAQ-13 on the Sufa and
   the Pathfinder on the Barak; then **P3** (the plan's B5 row).
3. **P5:** the targeting pod's cockpit steps, which the player does alone in the two-seaters (§7).
4. **P7:** the navigation FLIR on the HUD for both jets; not gated on night missions.
5. **P8:** terrain following on the Sufa from the navigation pod, at low priority. **P6** when missions have a lasing
   wingman; **P10, P11** later.

## 7. Decisions (17 November 2026)

The user answered round 1's five questions on 17 November 2026. His words in quotes; the result after each.

1. **The navigation pod:** "search more. I preatty sure both the D and the I use LANTIRN". Round 2 (§1): the Sufa
   carries the LANTIRN navigation pod, AN/AAQ-13 (the IAF's own pages; a dated 2007 photo); the Barak carried the
   LANTIRN family's export pods, the Pathfinder navigation FLIR (no terrain-following radar) and the Sharpshooter,
   from 1992 (one trade report). Both become stores (P9).
2. **Night missions first:** "no". The navigation FLIR and terrain following do not wait for night missions (P7,
   P8 are not gated on them).
3. **The Litening's side:** "search". Round 2 (§2.3): the right chin station, 5R, with the navigation pod on the left,
   5L; secondary sources only.
4. **The two-seaters' pod work:** "yes". The player does the navigator's pod work alone.
5. **Terrain following:** "yes, not in priority". In the plan at low priority (P8); on the Sufa it comes from the
   navigation pod (the IAF), the Barak has none.

## 8. Weapons that need a pod

The user, 17 November 2026: "also considration for pods: if there are some ammunitions that can't be used without
it, it should not be allowed to use without them". This section lists, for every store the sim's jets carry, whether
the real jet can employ it without a pod, and proposes the game's rule. Cockpit procedure only.

### 8.1 Each store and the pod

The stores: `modern-iaf/data/db/weapons/` (the GBU-10 / 12 / 16 and the Litening since slice 4, §4).

| store | needs a pod? | delivery without a pod | what the pod adds | source |
|---|---|---|---|---|
| GBU-10 / 12 / 16 (laser-guided) | **yes, a laser designator**: the own targeting pod, or another designator | released on a spot another aircraft (buddy lasing) or a ground team designates; the bomb's laser code set to match the designator's | self-designation: find, track and lase the target from the own jet (§3.1) | the bomb homes on "the reflected light ("sparkle") of the designating laser"[^w-paveway]; F-4 manual: "unless guided by another aircraft", the pod "is the main mode to employ GBUs"[^hb-f4-lgb] (secondary); ground designation: forum only, inferred |
| GBU-31, GBU-38 (JDAM) | no | target coordinates loaded before take-off or changed by the crew in flight (PRE) | coordinates of a target found in flight, "entered by a datalink from onboard targeting equipment, such as the LITENING II or Sniper targeting pods" (VIS / target of opportunity) | [^w-jdam] |
| GBU-39 (SDB) | no | as the JDAM: coordinates (inferred from its GPS guidance, [../../../docs/weapons.md](../../../docs/weapons.md) §13.2) | as the JDAM (inferred) | inferred |
| SPICE 1000 / 2000 | no | up to 100 targets loaded before flight, picked in flight; the bomb's own camera picture in the cockpit through the pylon's data link | coordinates or an image of a new target (inferred: the source names "an image or geographical coordinates", not their origin) | [^w-spice] |
| Mk 82 / 83 / 84 | no | CCIP and the other visual or radar modes ([../avionics-plan.md](../avionics-plan.md) S2–S6) | identifying the target; laser range for the release solution (the LANTIRN targeting pod passes its laser range to the fire control system[^fas-lantirn]) | [^fas-lantirn], inferred |
| AIM-9M, AIM-9X, Python 5, AIM-120, the gun | no | the radar, the helmet and the HUD | none (an A-A pod mode exists on the TGP page; not needed) | inferred |
| Delilah (record only; on no station) | open | open | open | open |
| Tanks, chaff, flares | no | — | — | — |

**The navigation pod:** no weapon needs it. It serves night low-level flight (§2.1); the attack itself uses the
targeting pod or the weapon's own guidance (inferred). Its rule is a flight rule (night low-level), not a weapon rule:
none is proposed until night missions exist (§6).

**The F-35I:** its EOTS is built in, so it always has the laser (§2.4); the Ra'am's built-in pod (§4) the same.

### 8.2 What exists today

- **Release:** `crates/iaf-avionics/src/release.rs` `laser_aim` takes the designation only with the laser on; with
  no laser (no pod, or the laser off) a laser bomb still flies the guided motion **to the ripple aim**, the
  CCIP-style point ([../../../docs/weapons.md](../../../docs/weapons.md) §9.8, the original's rule). So today a laser
  bomb without a pod is released, and steers to the release point: the game lets it be used without a pod.
  `gps_aim` in the same file takes PRE, then the pod's point, then the radar's designation, then CCIP for the GPS
  bombs: no pod needed (correct by §8.1).
- **Stores:** `crates/iaf-avionics/src/stores.rs` knows pods only as stores that are never selected or released
  (station select refuses "a tank / pod"); no store records what it needs.
- **SMS:** the RDY legend needs MASTER ARM and the stations' power ([../weapons.md](../weapons.md) §5); nothing
  checks a pod. The TGP format shows only with a pod store (`shared/cockpit/f16_mfd.gd`).
- **Loadout screen:** `modern-iaf/menu/loadout_screen.gd` refuses a store a station's `allowed` list lacks (the
  callout shakes), and has two weight rules ([../front-end.md](../front-end.md) §10.1): over the maximum take-off
  weight the figure turns the warning colour and **Fly is off**; past the balance limit an amber warning and Fly
  stays on unless the unit record's `lateral_limit_hard`. No rule looks at two stores together.
- **Briefing:** the Arming summary lists the stores and the weight; no warning line.

### 8.3 The proposed rule (pick list)

The data side, common to all three: a weapon record gains a field such as `"needs": "laser"` (the GBU-10 / 12 / 16),
met by a pod store whose record says `"gives": "laser"` (the Litening) or by a built-in pod (the F-35I, the Ra'am).
Ours, inferred: one field, read by the loadout, the release logic and the briefing alike, in Rust (the placement
rule). Buddy lasing (P6) would later meet the need from a mission's designator instead of a pod.

| # | item: what the player sees | size | kind |
|---|---|---|---|
| P12 | **Loadout rule.** A load with a laser bomb and no designator is flagged on the loadout screen and in the stores column. Options: (A) **hard**: as the weight rule, Fly is off until the pod is loaded or the bombs removed; (B) **warning**: amber, Fly stays on (as the balance rule); (C) **auto-add**: dropping a laser bomb on a jet without a pod also loads the pod on its station, with a line saying so. Wording options (English; Hebrew in the same tone): "GBU-12 needs a targeting pod. Load the Litening on station 5, or remove the GBU-12." / "No laser designator: the GBU-12 cannot be guided." / "Litening added: the GBU-12 needs it." Ours, recommended: (A) while the sim has no buddy lasing, since nothing else could guide the bomb; (B) once missions can carry a lasing wingman or ground team | S | extend (record field; `IafBriefing` check; `loadout_screen.gd` line and Fly gate) |
| P13 | **In flight.** If a jet still flies a laser bomb without a designator (a mission's fixed load, or the pod failed): the SMS shows the laser bomb's station but not RDY, with a reason line such as `NO LASER` (ours: the public dash-34 legend for this case was not found, open); the pickle releases nothing while selected; the release rule `laser_aim` drops the "steer to the ripple aim" fallback for a jet with no designator, so a jettisoned or forced-off bomb falls unguided (inferred: it is a deviation from the 1998 original's rule, kept for reborn and changed only in Modern IAF, recorded in `docs/deviations.md` if shared code changes) | S–M | extend (`release.rs`, `f16_mfd.rs` SMS legend, `player_weapons.gd`) |
| P14 | **Briefing.** The Arming summary shows a line under the stores when a weapon's need is unmet, in the same words as P12, with Edit opening the loadout on the station to fix; nothing when the load is complete | S | extend (the briefing's Arming summary) |

Not proposed: a rule for the GPS bombs and the SPICE without a pod (they work without one, §8.1); a rule for the
navigation pod (no weapon needs it).

[^at-sufa]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel" (Litening II "targeting and navigation pod";
    the LANTIRN navigation pod; the photo caption; the Elisra SPS-3000; the radar's terrain following):
    https://www.airforce-technology.com/projects/f-16i-soufa/
[^f16net-il]: F-16.net, "Israel" users page (the Barak's Sharpshooter, then Litening; the 1998 proposal; the F-16I's
    roll-out with both LANTIRN pods, 14 November 2003; the EL/L-8240 and SPS-3000): https://www.f-16.net/f-16_users_article7.html
[^ain-2011]: AIN, "Paris 2011: Rafael celebrates Litening pod success; shows new version here", 19 June 2011:
    https://ainonline.com/aviation-news/2011-06-19/paris-2011-rafael-celebrates-litening-pod-success-shows-new-version-here
[^fas-litening]: FAS Military Analysis Network, "LITENING" (three fields of view, the wide one on the HUD for
    navigation; CCD; laser spot detector): https://man.fas.org/dod-101/sys/smart/litening.htm
[^fas-lantirn]: FAS Military Analysis Network, "LANTIRN" (the navigation pod's TFR and FLIR on the HUD; the targeting
    pod; weights): https://man.fas.org/dod-101/sys/smart/lantirn.htm
[^w-lantirn]: Wikipedia, "LANTIRN" (the two pods, weights, operators): https://en.wikipedia.org/wiki/LANTIRN
[^w-litening]: Wikipedia, "LITENING" (versions, sensors, weight and size, the IAF's jets and versions with their
    citations): https://en.wikipedia.org/wiki/LITENING
[^w-f16var]: Wikipedia, "General Dynamics F-16 Fighting Falcon variants" (Block 40/42 with LANTIRN; the HTS pod on
    the port intake hardpoint in place of the LANTIRN navigation pod):
    https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon_variants
[^crec-2401]: Congressional Record, 10 September 2024, arms sales notification, Transmittal No. 24-01, Israel F-15IA
    and F-15I+ ("Fifty (50) AN/AAQ-13 LANTIRN navigation pods with containers"):
    https://www.govinfo.gov/content/pkg/CREC-2024-09-10/html/CREC-2024-09-10-pt1-PgS5918-2.htm
[^hm-lantirn]: Hamichlol, "LANTIRN" (the IAF's name ענבר; an F-15I photo with a Litening and a LANTIRN pod):
    https://www.hamichlol.org.il/LANTIRN
[^hm-litening]: Hamichlol, "לייטנינג (פוד)" (Litening 3 on the F-15I, F-16D and F-16I):
    https://www.hamichlol.org.il/לייטנינג_(פוד)
[^ah-5r]: AirHistory.net, F-16A 81-0688 (a LANTIRN pod on station 5R, as summarised by the search engine; the page
    not opened): https://www.airhistory.net/registration/81-0688
[^twz-litening]: The War Zone, "We talk new features on the Litening large aperture targeting pod":
    https://www.twz.com/news-features/we-talk-new-features-on-the-litening-large-aperture-targeting-pod
[^twz-sufa]: The War Zone, H. Altman, "Flying and fighting in the Israeli Air Force's F-16I Sufa", 24 July 2025 (the
    navigator; jamming; taking photos of the target area):
    https://www.twz.com/air/flying-and-fighting-in-the-israeli-air-forces-f-16i-sufa
[^esd-2026]: European Security & Defence, A. Egozi, "Rafael's Litening SAR value Iran", 11 August 2026:
    https://euro-sd.com/2026/08/news/52790/rafaels-litening-sar-value-iran/
[^dif-gaza]: Defence Industry Europe, "Litening targeting pod proven in asymmetric warfare in Gaza", 23 December
    2023: https://defence-industry.eu/litening-targeting-pod-proven-in-asymmetric-warfare-in-gaza/
[^dcs-f16]: Secondary. Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), a simulator manual of a
    Block 50 M4 tape: https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
[^hb-lantirn]: Secondary. Heatblur Simulations, *DCS: F-14 manual*, "LANTIRN" (fields of view, point / area track,
    laser arm and fire, the laser code, the display): https://f14.manuals.heatblur.se/f14ab/systems/lantirn/overview.html
[^bms-forum-laser]: Secondary. Falcon BMS forum, "Key command for fire laser?" (the trigger's first detent, held;
    laser arm, TGP not masked, TGP the SOI): https://forum.falcon-bms.com/post/115243
[^w-paveway]: Wikipedia, "Paveway" (the seeker homes on the designating laser's reflection):
    https://en.wikipedia.org/wiki/Paveway
[^hb-f4-lgb]: Secondary. Heatblur Simulations, *DCS: F-4E manual*, "Laser Guided Bombs" (the own pod or buddy
    lasing; the bombs' laser code set on the ground):
    https://f4.manuals.heatblur.se/stores/air_to_ground/bombs/laser_guided_bombs.html
[^w-jdam]: Wikipedia, "Joint Direct Attack Munition" (coordinates loaded before take-off, changed in flight, or
    entered from a targeting pod such as the Litening II): https://en.wikipedia.org/wiki/Joint_Direct_Attack_Munition
[^w-spice]: Wikipedia, "Spice (bomb)" (targets loaded pre-flight and picked in flight; the pylon's data link; a new
    target as an image or coordinates): https://en.wikipedia.org/wiki/Spice_(bomb)
[^iaf-f16i-next]: Israeli Air Force site, "F-16I הדור הבא מטוס הקרב החדש של..." (F-16I, the next generation; the
    LANTIRN navigation pod and the Litening under the intake), https://www.iaf.org.il/522-19034-he/IAF.aspx (refused
    automated access; quoted as the search engine returned it, 17 November 2026)
[^iaf-mag-sufa]: Israeli Air Force magazine (בטאון חיל האוויר) on the IAF site (the Sufa's navigation pod: low
    flight at a fixed height and speed without the pilot's intervention), https://www.iaf.org.il/1424-23020-he/IAF.aspx
    (refused automated access; quoted as the search engine returned it)
[^iaf-sufa]: Israeli Air Force site, "סופה (F-16 I)" (the Sufa's page: the LANTIRN navigation pod and the Litening),
    https://www.iaf.org.il/645-21805-he/IAF.aspx (refused automated access; as the search engine returned it)
[^iaf-raam]: Israeli Air Force site, "בואינג F-15I (רעם)" (the LANTIRN navigation pod: a FLIR night sensor and a
    terrain-following radar), https://www.iaf.org.il/187-he/IAF.aspx (refused automated access; as the search engine
    returned it)
[^twz-syria]: The War Zone, J. Trevithick, "Israel Details Long Secret Raid On Syrian Nuclear Reactor, Says It's
    Willing To Do It Again", 21 March 2018 (the photo caption of an F-16I of the 2007 strike):
    https://www.twz.com/19492/israel-details-long-secret-raid-on-syrian-nuclear-reactor-says-its-willing-to-do-it-again
[^baugher-f16i]: Joe Baugher, "General Dynamics F-16I Fighting Falcon for Israel" (Peace Marble V, 1999–2001; the
    LANTIRN navigation and targeting pods in the contract): https://www.joebaugher.com/usaf_fighters/f16_42.html
[^fi-pathfinder]: Forecast International, *Electro-Optical Systems Forecast*, "Pathfinder/Sharpshooter - Archived
    02/2004" (February 2003; Israel's 1992 Pathfinder and Sharpshooter pods; the Pathfinder without the TFR, its FLIR
    on the HUD; the Sharpshooter without the Maverick correlator):
    https://www.forecastinternational.com/archive/disp_pdf.cfm?DACH_RECNO=556
[^f16net-lantirn]: F-16.net, "AN/AAQ-13 & AN/AAQ-14 LANTIRN" (the navigation pod on 5L; Pathfinder and Sharpshooter
    as derivatives): https://www.f-16.net/f-16_armament_article2.html
[^bm-sufa]: Secondary. Britmodeller forum, "Israeli F-16I Sufa questions" (the LANTIRN navigation pod and the
    Litening II on 5L / 5R; as summarised by the search engine, the thread not opened), https://www.britmodeller.com/forums/index.php?%2Ftopic%2F15480-israeli-f-16i-sufa-questions%2F=
[^dif-rampage]: Defence Industry Europe, "Israeli Air Force image shows F-16I Sufa fighter armed with four RAMPAGE
    stand-off missiles", 8 March 2026 (the IAF's photo of 6 March 2026; no pods named): https://defence-industry.eu/?p=69037
[^bms-tfr]: Secondary. Falcon BMS community wiki (Chinese), "8 低空导航" (low-altitude navigation; follows
    BMS1-F16CM-34-1-1 and the dash-34 §2.10): https://wiki.biligame.com/falconbms/8_%E4%BD%8E%E7%A9%BA%E5%AF%BC%E8%88%AA
