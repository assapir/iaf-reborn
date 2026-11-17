# Modern IAF: the F-16s' threat warning, MAW, countermeasures, AIFF, data link and AWACS

**Terms:** AIFF = advanced identification friend or foe (an interrogator); AWACS = the airborne early-warning
controller; CMDS = countermeasures dispenser set; CMS = countermeasures management switch (on the throttle); DL = data
link; LOS = line of sight; MAW = missile approach warning; RWR = radar warning receiver; TTI = time to impact; TWP =
threat warning prime panel; VMS = the F-16's voice message system. "Inferred" = our own reasoning; "open" = no source
found.

17 November 2026 (avionics slice 5, part B; [avionics-plan.md](avionics-plan.md) E1, E2, E4, R15, N5, N6, N7; gaps
G3's threat display, G13, G19, G20, G30, G31). The Sufa's and the Barak's electronic warfare and identification in the
3D cockpit. The logic is Rust in `crates/iaf-avionics` (`ews.rs`, `cmds.rs`, `aiff.rs`, `datalink.rs`), bridged by
`IafEws` (`crates/iaf-godot/src/ews.rs`); `shared/weapons/ews.gd` wires it to the game and `player_weapons.gd` runs it
on the modern F-16s only (`modern_f16`), so reborn's own jets are unchanged. Every modern F-16 has the threat display,
the CMDS and the data link; the aircraft definition adds the AIFF and the MAW (`airframe.json` `"ews": {"aiff": true,
"maw": true}`, the Sufa's). The Barak has neither (avionics-plan.md B4, B8).

## 1. Keys and controls

The user has no HOTAS ([avionics-plan.md](avionics-plan.md) §8, decision 3), so each function has a key, a click in the 3D cockpit, or both.

| key | command | does |
|---|---|---|
| O | 260, 0 | AIFF SCAN interrogation (the real TMS left, short) |
| Shift + O | 260, 1 | AIFF LOS interrogation about the FCR's cursor (TMS left, held) |
| Shift + `;` | 221, 3 | TMS left: in CRM and STT also the AIFF's SCAN (ACM keeps its SLEW pattern) |
| P | 261, 0 | CMS forward: run the selected program |
| Shift + P | 261, 1 | CMS aft: stop dispensing; AUTO's enable and SEMI's request dropped |
| Y | 261, 2 | CMS right: consent in SEMI, enable AUTO |
| Shift + Y | 262 | the CMDS MODE knob, one position on (OFF, STBY, MAN, SEMI, AUTO, BYP, round) |
| Ctrl + Y | 263 | the next manual program (1–4) |
| Alt + Y | 264, 0 | TWP HANDOFF: the diamond to the next threat |
| Alt + I | 264, 1 | TWP MODE: PRI (the 5 highest-priority threats) or OPEN (up to 16) |
| Alt + O | 264, 2 | TWP UNKNOWN: the unknown emitters shown |
| Alt + J (held) | 264, 3 | TWP TGT SEP: overlapping symbols spread wider |
| Ctrl + I | 264, 4 | TWP SYS TEST: a test pattern for 3 s |
| — | — | the DL switch: a click on the 3D cockpit's DL switch only (ews.gd `link_power`) |

Clickable (`shared/extra/models/cockpit3d/f16_controls.json`, each row's `system` in `cockpit3d_controls.gd`): the
TWP's `pri`, `unk` and `sep` buttons; the CMDS panel's `MODE_50_knob`, `CH_50_switch`, `FL_50_switch`,
`01_50_switch`, `02_50_switch`, `RWR_50_switch`, `JMR_50_switch`, `MWS_50_switch` and `JETT_50_switch`; the AVIONIC
POWER panel's `dl-switch`; the THREAT and MSL volume knobs (`threat-vol-knob`, `msl-vol-knob`). A key moves its
switch too (the switch shows the system's state each frame). The model has no HANDOFF, LAUNCH or SYS TEST button and no
PRGM knob: those are keys only. Its MODE knob has three positions (OFF, STBY, MAN; the FlightGear model's); SEMI, AUTO
and BYP are on Shift + Y only and leave the knob at MAN.

## 2. The threat display (E1)

On the 3D cockpit's RWR scope (`cockpit3d_display.gd` `_threats`), from the RWR's cockpit copy (`rwr.rs` `display`),
after the dash-34's threat azimuth indicator ([../../docs/real-mfd.md](../../docs/real-mfd.md) "The threat azimuth
indicator") and the MLU's ALR-69[^mlu1]:
- the ownship "+" in the centre, 12 ticks at 30° on the edge, the inner ring at 25 NM and the edge at 50 NM; a threat
  at its range, beyond 50 NM on the edge (dash-34 p. 1-199);
- the label by class (`ews.rs` `identify`, inferred from figs. 1-133 / 1-134): an aircraft by its number under a hat
  ("16", "15", "35" for the F-35), a SAM by its digit ("2", "6", "H"), AAA "A" in a box, a ship "S"; anything else
  "U", shown only with UNKNOWN on;
- priority: a launch, then a lock, then the nearest; the top one in a diamond (HANDOFF moves it); a lock in a square,
  a launch in a circle flashing at 3 Hz (the MLU's launch light);
- PRI shows 5, OPEN up to 16 (MLU fig. 7-3); PRI at power-up (inferred);
- a new threat flashes for 4 s with the new-threat tone (WRN_NEW_GUY; the time inferred); HANDOFF plays the same tone
  (inferred: the real set plays the handed-off threat's own tone, which the sim does not have);
- separation: a symbol within 0.14 of the scope's radius of one already placed moves outward, then counter-clockwise
  along the edge (dash-34 p. 1-199); TGT SEP held doubles the gap (inferred);
- SYS TEST: one symbol of each class on the inner ring for 3 s (inferred).

The THREAT knob scales the new-threat tone, the MSL knob the launch tone. On the modern F-16s the RWR hears an
aircraft's radar from every side (`rwr.rs` `all_aspect`); the 1998 rule heard an aircraft only more than 120° off the
nose. With that and the "35" label the range's radar drones (`drone_radar`, Drones 4) show on the scope: before this
change their lock was listed but neither active from ahead nor drawn (the 1998 glyphs have no F-35).

## 3. The MAW (E2)

The Sufa's PAWS gives "the direction, missile type, and time to impact"[^janes]. `ews.rs` `Maw` reads the RWR's list
of missiles launched at the jet: for each, its direction off the nose and the range over the closing speed (TTI;
inferred), "--" while it does not close. The RWR scope shows an "M" on the edge at that direction, flashing, with the
seconds under it. The tone is the RWR's launch tone (the same list). The missile type is open: the sim's missiles carry
no class the warning could name.

## 4. The CMDS (E4)

A cockpit procedure only (avionics-plan.md §7: what a decoy does stays the game's decoy rule, docs/weapons.md §10).
After the simulator manual the plan cites[^dcs]: MODE OFF / STBY / MAN / SEMI / AUTO / BYP; CMS forward runs the
selected program in MAN, SEMI and AUTO (BYP one chaff and one flare); CMS aft stops it; CMS right gives consent in SEMI
and enables AUTO. A missile launch heard by the RWR (RWR switch on) or seen by the MAW (MWS switch on) makes SEMI ask
for consent with the VMS's "Counter", and AUTO, enabled, run the program and say "Counter". The JMR switch's input
starts nothing (the sim has no jammer cues for the CMDS). CH and FL power each dispenser; O1 and O2 move only (the sim
carries no other dispenser). JETT releases every flare, one each 0.1 s (inferred). Each release goes through the
game's own dispense (`player_weapons.gd` `dispense`), so it is counted, refused with the gear down and limited by the
decoy pool as Insert and Delete are.

The programs (ours, inferred): burst quantity and interval, salvo quantity and interval per expendable.

| program | chaff | flares |
|---|---|---|
| 1 | 1 × 1 | 1 × 1 |
| 2 | 2 bursts 0.1 s apart, 2 salvos 1 s apart | the same |
| 3 | 2 bursts 0.1 s apart, 4 salvos 0.75 s apart | none |
| 4 | none | 2 bursts 0.1 s apart, 3 salvos 1 s apart |

"Chaff flare, low" as either count falls to its BINGO quantity (10 at first, inferred; set on the EWS page) and "Chaff
flare, out" as one reaches none, both with the EWS page's BINGO option on (the VMS's words; the sim's Betty clips `BTY_CHAFF_FLARE`, `BTY_LOW`, `BTY_OUT`, `BTY_COUNTER`, [sound.md](sound.md)
§3). The panel starts as a hot jet's: STBY, CH, FL, RWR, JMR and MWS on (inferred). The DED's EWS pages set the
programs, the BINGO quantities and the options (§8).

## 5. The AIFF (R15)

The Sufa only (`airframe.json` `ews.aiff`). After the MLU M1 guide[^mlu1] (docs/real-hud.md "IFF"): SCAN covers ±60°
in azimuth and elevation, LOS ±15° in azimuth about the FCR's cursor; a friend replies with a green circle, a reply of
unknown nature with a yellow square, no reply shows nothing; the replies show where they came from, on the FCR's A-A
format and the HSD, for 3 s (a simulator guide's figure); a SCAN blanks the FCR's own targets meanwhile (1 s, inferred).
The interrogator reaches 160 NM, the FCR's longest scale (inferred). In the sim a unit on the player's side is a
friend and a hostile one does not reply; no unit answers "unknown" yet (the sim has no neutral aircraft).

## 6. The data link (N5)

With the DL switch on (it starts off), the HSD and the FCR show the flight's other jets (a cyan circle with their
number in the flight) and the AWACS's tracks of the aircraft it sees (a green circle for a friend, a red diamond for a
hostile, after the F-35's identity shapes, docs/real-hud.md "IFF"), each with a line along its heading; the symbols and
their colours on the F-16 are inferred. The AWACS sees as the game's AWACS calls do (`fctrl.rs`: about 96 km round the
jet, aircraft above the terrain + 175 m) and names each track by its side (inferred). The tracks refresh every 4 s
(inferred). On the FCR they show in the A-A search modes, not over EXP.

## 7. The AWACS (N6)

The game's contact calls (docs/radio.md §4, `fctrl.rs`, `radio.gd` `_awacs`) run in every mission: from 60 s into the
flight, every 12 s, an aircraft within 35 NM: "Alpha, bearing 090, 15 miles, target, heading 270, free to engage". The
range's drones are the calls' contacts. Open: the sim's voices file has no templates or clips for them yet. They are
written (`ACFT_FCTRL_LONG`, `_SHORT` and 97 particles in the AWACS's voice `am_fenrir`, with Hebrew subtitles) on the
branch `wt/avionics-s5-awacs-voices`, which waits for the `voices` step (Kokoro, [sound.md](sound.md) §5) to make the
clips; `own` refuses a voices file whose clips are missing, so the branch merges with its clips.

## 8. The DED pages

On the ICP and DED of [ufc.md](ufc.md) (`ufc.rs` `ews_lines`; the jet's state through `Nav.ews`, an entry back as
`Effect::Cmds`, applied by `ews.gd` `ded_edit`). The layouts follow the DCS guide's EWS, IFF, DLNK and INTG pages[^dcs]
as far as the sim has the data (inferred where they differ). A jet without these systems (reborn's) has none of them.

| page | how | shows / sets |
|---|---|---|
| EWS CONTROLS | LIST 7 | the chaff and flare counts, the CMDS mode; the options REQCTR ("Counter" in SEMI / AUTO), BINGO (the low / out calls), FDBK ("Chaff flare" as a program starts), REQJAM (shown and set only: the sim's jammer takes no request), each toggled by M-SEL (0, ENTR) |
| CMDS BINGO | SEQ | the chaff and flare BINGO quantities (0–99) |
| CMDS CHAFF / FLARE PRGM | SEQ, SEQ; INC / DEC the program 1–4 | BQ (0–99), BI (typed in thousandths: 20 = 0.020 s, to 10.000 s), SQ (0–99), SI (typed in hundredths: 50 = 0.50 s, to 150.00 s) |
| IFF | the ICP's IFF button (a click on the 3D ICP only; the AIFF itself is on O / Shift + O) | the AIFF's SCAN and LOS volumes, reach and reply time; "NO INTERROGATOR" without one (the Barak) |
| DLNK | LIST ENTR | the DL switch, the flight's jets and the tracks on the link, its update time |
| INTG | LIST RCL | the last interrogation (SCAN / LOS) and the friendly and unknown replies on show |

The real IFF page sets the transponder's modes and codes; the sim has no transponder (nothing interrogates the
player's jet), so the page shows the interrogator only, and the CNI page's IFF field stays empty (open until a
transponder model exists).

## 9. Tests

- Rust: `ews.rs` (symbols, priority, PRI / OPEN, separation, HANDOFF, SYS TEST, the MAW's direction and TTI),
  `cmds.rs` (a program's count at its interval, SEMI / AUTO, low / out, JETT), `aiff.rs` (a friend replies, a hostile
  does not; SCAN and LOS volumes), `datalink.rs` (members, AWACS tracks, the switch), `rwr.rs` (all-aspect, stable
  ids), `betty.rs` (the CMDS calls).
- Headless: `modern-iaf/tests/test_sim_ews.gd` on the range: the drones' lock as "35", each TWP key, the MAW, the CMDS
  in MAN and SEMI, the AIFF by O and by TMS left, the data link, the DED's EWS, IFF, DLNK and INTG pages. `ufc.rs`
  `ews_pages_edit_the_cmds`, `iff_dlnk_and_intg_pages`; `cmds.rs` `the_ews_options_and_edited_programs`.

## 10. Open

- The missile type on the MAW (above).
- The transponder's modes on the IFF page and the CNI page's IFF field (§8).
- The AWACS's clips are made by the `voices` step (Kokoro); until it runs, `own` stops at the first missing clip.

[^mlu1]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998): AIFF pp. 49–55, the
    EWPI (ALR-69) fig. 7-3 p. 209: https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^janes]: Janes, "Elbit Systems to equip Israel's F-16Is with self-protection suite", 27 January 2025:
    https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite
[^dcs]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), "CMDS", a simulator manual of a Block 50 M4
    tape: https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
