# Modern IAF: the F-16s' up-front controls, HUD panel, navigation and DGFT

**Terms:** ALOW = the low-altitude warning height; CNI = communication, navigation, identification (the DED's main
page); CRM = combined radar mode; DCS = the ICP's data control switch (a four-way rocker); DED = data entry display;
DGFT = dogfight; ICP = integrated control panel; INS = inertial navigation system; MSL OVRD = missile override; SOI =
sensor of interest; TACAN = tactical air navigation; TOS = time over steerpoint; UFC = up-front controls; VV/VAH = the
HUD's scales switch (vertical velocity, velocity, altitude, heading). "Inferred" = our own reasoning; "open" = no
source found.

17 November 2026 (avionics slice 5, part A; [avionics-plan.md](avionics-plan.md) H1–H4, N1–N4, N6's radios, N7's DGFT;
gaps G2, G17, G18, G28, G29). The Sufa's and the Barak's ICP and DED, the HUD control panel, the INS's effect, TACAN,
markpoints and the throttle's DGFT / MSL OVRD switch. The logic is Rust: `crates/iaf-avionics/src/ufc.rs` (every DED
page, the data entry, TACAN, the radios; a page's sub-page is typed per page, `Sub`), `real_hud/f16.rs` (the HUD
panel's symbology), `master.rs` `Override` and `radar.rs` `override_mode` (DGFT / MSL OVRD), `iaf-flight` `start.rs`
`ins_status` (the alignment's progress). The
bridge is `IafUfc` (`crates/iaf-godot/src/ufc.rs`); `shared/cockpit/cockpit.gd` holds it and applies what a key
changes. It exists with the modern F-16 MFDs only (`Settings.modern_mfds()` and the jet's real MFD look), so
reborn's jets keep their CNI page and HUD, and the F-35I has none.

The layouts follow the Block 50 dash-34 manual[^dash34] and the DCS F-16C guide[^dcs-f16] (a simulator manual), as
the plan does for the Sufa (inferred for the Sufa: its own pages are not public).

## 1. Keys and controls

The user has no HOTAS ([avionics-plan.md](avionics-plan.md) §8, decision 3): every function has a key, a click on the
3D cockpit's own control, or both (`shared/extra/models/cockpit3d/f16_controls.json` rows; `cockpit3d_controls.gd`).

| key | command | does | 3D cockpit |
|---|---|---|---|
| Ctrl + 1 … Ctrl + 9, Ctrl + 0 | 250, 1–9, 0 | ICP keys: a page (1 T-ILS, 2 ALOW, 4 STPT, 5 CRUS, 6 TIME, 7 MARK, 8 FIX, 9 A-CAL), or a digit on a page with a data field | the ICP's 0–9 |
| Alt + Return | 250, 10 | ENTR | ENTR |
| Alt + Backspace | 250, 11 | RCL: the last digit, then all; on MISC: HMCS | RCL |
| Alt + L | 250, 12 | LIST | LIST |
| Alt + [ / Alt + ] | 250, 13 / 14 | COM1 (UHF) / COM2 (VHF) | COM1 / COM2 |
| Alt + Page Up / Page Down (the laptop map: Ctrl + = / Ctrl + −) | 250, 16 / 17 | DCS up / down: the previous / next field | the DCS rocker |
| Alt + Home / Alt + End (the laptop map: Ctrl + , / Ctrl + .) | 250, 18 / 19 | DCS RTN (back to CNI) / SEQ (the page's next sub-page or mode) | the DCS rocker |
| Alt + = / Alt + - | 250, 20 / 21 | INC / DEC: the steerpoint, the TACAN channel, the radio preset | the arrows rocker |
| Alt + N | 253 | the EHSI's mode: NAV / TCN | the EHSI's M button |
| Alt + U | 254 | the backup UHF panel's channel, one on (the UHF goes to BACKUP) | — (the model has no moving backup panel) |
| Alt + K | 255 | IFF IDENT: the transponder's IDENT for 18 s ([ews.md](ews.md) §8) | — (the model has no IDENT button) |
| Alt + D | 252, 4 | HUD DED DATA: DED / PFL / OFF | the HUD control panel's DED DATA switch |
| Alt + R | 252, 5 | HUD DEPR RET: STBY / PRI / OFF | the HUD control panel's DEPR RET switch |
| Alt + X | 252, 0 | HUD SCALES: VV/VAH / VAH / OFF | the HUD control panel's SCALES switch |
| Alt + F | 252, 1 | HUD FP MARKER: ATT/FPM / FPM / OFF | the HUD control panel's FP MARKER switch |
| Alt + Z | 252, 2 | HUD VELOCITY: CAS / TAS / GND SPD | the HUD control panel's VELOCITY switch |
| Alt + A | 252, 3 | HUD ALT: RADAR / BARO / AUTO (RADAR and AUTO need RDR ALT powered) | the HUD control panel's ALT switch |
| — | — | RET DEPR: the standby reticle's depression, 0–260 mr (inferred range) | the ICP's RET DEPR wheel |
| V / Shift + V | 251, 1 / 2 | DGFT / MSL OVRD; the same key again centres the switch | — (the throttle is not clickable) |
| Shift + A | 202 | MASTER ARM; the 3D switch's lower position is SIMULATE | MASTER ARM (three positions) |

Ctrl + digits rather than Alt + digits: the laptop map's look keys are Alt + 1 … 9 ([front-end.md](front-end.md) §9.1).

## 2. The DED

Five lines of 24 characters, drawn on the 3D cockpit's DED (`cockpit3d_display.gd` `_ded`), dark without the UFC's
power (the AVIONIC POWER panel's UFC switch). Each character has its own cell, so the columns line up as on the real
display (the sim's display font is proportional). The drawing covers the whole screen: FlightGear's DED screen maps
only the top two thirds of its texture, which hid lines 4 and 5 until 17 November (`cockpit3d.gd` `_attach_display`
stretches the texture over the screen's UVs). The text keeps to the part of the screen the pilot sees from the
default eye (`DED_SEEN`, [../../docs/cockpit.md](../../docs/cockpit.md) "3D cockpit"): the ICP's right edge hides the
screen's left fifth. The selected field shows between asterisks, with the digits typed in
place of its value; ENTR enters them and moves to the next field; a wrong entry is refused (the value stays). A lone
0 then ENTR toggles a choice (M-SEL: the TACAN band, BULLSEYE, MODE).

| page | how | shows / sets |
|---|---|---|
| CNI | RTN | UHF frequency (or BACKUP), the steerpoint (↕ steps it), VHF preset, time of day, the hack clock while it runs, the transponder's modes on (`M1 3 C`, `I` during IDENT; [ews.md](ews.md) §8), the TACAN channel |
| T-ILS | 1 | TACAN mode (REC / T/R / A/A TR, SEQ), channel (1–126) and band (X / Y), the ILS frequency (108.10–111.95) and course, CMD STRG, the station's name, bearing and range |
| ALOW | 2 | CARA ALOW (the HUD's `AL`, the "ALTITUDE" voice), MSL FLOOR; the TF line as the page has it (TF is parked, G12) |
| STPT | 4 | the steerpoint's number (typed or ↕), latitude, longitude, elevation, TOS; SEQ: AUTO / MAN |
| CRUS | 5 | SEQ: TOS (system time, desired, ETA, required ground speed), RNG (fuel at the steerpoint, wind), HOME (the home steerpoint, fuel there, wind), EDR (time to bingo, fuel flow) |
| TIME | 6 | system time, the hack clock (ENTR with nothing typed starts / stops it, RCL zeroes it; inferred), DELTA TOS (added to every TOS) |
| MARK | 7 | SEQ: OFLY / FCR / TGP / HUD; ENTR marks: steerpoint 26, then 27 … 30, the sixth replacing 26 |
| FIX | 8 | SEQ: OFLY / FCR / TGP / HUD; the error found: always 0.00 NM (the sim's INS keeps its position exactly) |
| A-CAL | 9 | the altitude and position deltas: 0 (inferred, as FIX) |
| LIST | LIST | 1 DEST (the steerpoint's coordinates), 2 BNGO (the bingo: the HUD's FUEL), 4 NAV (system accuracy: HIGH once the INS navigates), 6 INS (alignment time / status, RDY, position, altitude, heading, ground speed), 8 MODE (A-A / A-G), 0 MISC |
| MISC | LIST 0 | 2 MAGV (about 5° E over Israel, inferred; shown only: the sim's headings are grid headings), 5 LASR (the TGP's laser code, 1111–1788), 8 BULL (the HSD's bullseye on or off, at the home base or a steerpoint), RCL HMCS (the helmet's blanking) |
| COM1 / COM2 | COM1 / COM2 | a preset (1–20) or a frequency typed (24250 = 242.50 MHz); ↕ steps the preset |
| EWS, IFF, DLNK, INTG | LIST 7, the IFF key, LIST ENTR, LIST RCL | the CMDS's programs, BINGO and options; the transponder, then (SEQ) the AIFF; the data link; the last interrogation ([ews.md](ews.md) §8) |

Not offered, with the reason: LIST 3 VIP, 5 MAN, 9 VRP and MISC 7 DRNG serve the release modes of slice 9 (G21); MISC
1 CORR and 4 INSM (HUD and INS corrections: the sim has no such errors), 3 OFP (the software's identities are not
public), 6 GPS (no GPS error model), 9 WPT and 0 HARM (no Harpoon or HARM in the sim); the HOME page's optimum
altitude and EDR's optimum Mach (the jet's cruise tables are not public: open).

The radios' presets and the TACAN channels are ours: the IAF's frequencies and the bases' channels are not public.
TACAN channels: Ramon 75X, Nevatim 83X, Hatzerim 62X, Ramat David 99X, Tel Nof 31X, at the airbases' reference points.
A station is received within the line of sight, 1.23 · (√ft of the jet + √30) NM, and always within 5 NM (inferred).
At the start the TACAN is tuned to the station nearest the jet (the home base on a ground start) (`ufc.rs` `tune_nearest`; inferred: the
pilot's preset).
The sim's radios have no frequency model: the tower and the AWACS answer on any preset; the ILS serves the home
runway at any frequency (the bases' ILS frequencies are not in the data).

## 3. Steerpoints, markpoints and the INS

- A steerpoint picked on the DED is the autopilot's too (`autopilot.gd` `set_waypoint`); an edited one goes to the
  flight model's autopilot again (`terrain_view.gd` `_route_points`).
- Markpoints (`cockpit.gd` `marks`) are steerpoints 26 to 30: the HUD, the EHSI and the DED steer to one picked on the
  STPT page; the HSD draws each as an X, circled while steered to (inferred: the HSD's markpoint symbol is not public).
  The autopilot flies the route only. The HUD mark is the ground along the flight path within 10 NM (inferred: the
  real HUD mark cue starts on the flight path marker).
- The INS (`start.rs`; [cockpit.md](cockpit.md) §5.2): until it can navigate (aligned, the knob at NAV or IN FLT
  ALIGN) the HUD, the EHSI and the DED's steering show no steerpoint and NAV reads LOW. The INS page counts its status
  from 99 to 10 over the alignment (ours, linear; inferred) and shows RDY when done; the HUD shows ALIGN while it
  aligns at STOR HDG or NORM and flashes it once ready (the DCS guide's behaviour; inferred place, the left column).

## 4. The HUD control panel and the HUD

What `real_hud/f16.rs` draws from the panel ([../../docs/real-hud.md](../../docs/real-hud.md) "F-16C/D"):
- SCALES: VV/VAH adds the vertical velocity scale inboard of the altitude scale (±1,500 fpm, labels in thousands,
  ticks every 500 fpm, a moving triangle; the range inferred), VAH as before, OFF leaves only the boxes (inferred).
- FP MARKER: ATT/FPM the ladder and the marker, FPM the marker alone, OFF neither.
- VELOCITY: CAS (`C`), TAS (`T`) or ground speed (`G`); CAS with the gear down or in DGFT.
- ALT: RADAR the radar altitude on the scale (`AR`), BARO, AUTO the radar altitude's thermometer below 1,200 ft, with
  `AR` and the radar altitude on its index.
- DED DATA: at DED the DED's five lines, at PFL the pilot fault list's, low in the HUD, one character per 5 px cell
  so the DED's columns line up, in the gap between the left and the right data column, from the right column's
  second row down (inferred place; the real HUD's five windows sit lower in that gap, the last three under the
  columns, at the normal text size: [../../docs/real-hud.md](../../docs/real-hud.md) "What ours draws (status)"). Where the gap is narrower than the
  block (the Barak's, whose glass holds its columns closer together; [cockpit.md](cockpit.md) §4) the block is drawn smaller as a whole, its
  characters, cells and rows, so the characters keep their spacing (2026-11-19). The roll indicator is not drawn
  meanwhile (the dash-34 as a simulator forum quotes it, [../../docs/real-hud.md](../../docs/real-hud.md) "F-16C/D").
  `f16.rs` `ded_data_overlaps_nothing_in_any_mode` checks that no cell touches another symbol in any HUD mode.
- DEPR RET at STBY: the standby reticle, a 50 mr ring with its pipper, depressed by RET DEPR.
- MASTER ARM at SIMULATE: `SIM` in place of `ARM`; nothing is released or fired.
- `FUEL` flashes below the bingo; `AL` shows the DED's ALOW.
- The HUD as the SOI (DMS up): an asterisk at the upper left[^soi] (inferred place: left of the g readout).

## 5. DGFT and MSL OVRD

The throttle's switch (dash-34 "Dogfight and missile override"): DGFT selects an IR missile (else any A-A missile),
the radar's ACM and the HUD's EEGS funnel with the missile's symbols (`DGFT` in the mode window); the trigger fires the
gun. MSL OVRD selects a radar missile (else any A-A missile) and CRM (`MSL`). Centred, the station and the radar's
mode before come back; a lock (STT) is kept (inferred). While the switch is thrown the master-mode keys (M, N and
`[`) do nothing: the switch holds the A-A mode until it is centred (inferred). `master.rs` `Override` and
`Modes::throw_override` (the switch's position), `player_weapons.gd` `override_key`.

## 6. Tests

- Rust: `ufc.rs` (every line 24 wide, CNI, STPT entry, RCL, bingo and ALOW, markpoints, TACAN and its line of sight,
  CRUS, the INS page, the radios, the hack and the laser code, the bullseye; `seq_steps_the_sub_pages_round`: SEQ steps
  CRUS, MARK, FIX, EWS and IFF through their sub-pages in order, each page opens on its first), `f16.rs`
  `the_hud_panel_switches`, `master.rs` `dgft_and_msl_override`, `radar.rs` `set_mode_for_dgft_and_back`, `start.rs`
  (the INS status), `gaaf.rs` (the ALOW setting).
- `modern-iaf/tests/test_sim_ded.gd` on the range: the DED dark cold, the pages by their keys, TACAN to Ramon, the
  EHSI's TCN, ALOW, BINGO and the HUD's FUEL, a steerpoint's elevation, markpoint 26 steered to, COM1 and the backup
  UHF, the INS's ALIGN and its effect, the HUD panel, SIMULATE, the 3D ICP's keys, DGFT and MSL OVRD.

[^dash34]: T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997:
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^dcs-f16]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), a simulator manual of a Block 50 M4
    tape: https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
[^soi]: Simulator forums quoting the dash-34 (secondary): DCS forum, "Able to slew sensors even if not displayed (SOI
    logic)", https://forum.dcs.world/topic/351850-able-to-slew-sensors-even-if-not-displayed-soi-logic; Falcon BMS
    forum, "Sensor of Interest (SOI)", https://forum.falcon-bms.com/post/1583
