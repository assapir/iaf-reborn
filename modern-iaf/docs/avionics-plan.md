# Modern IAF avionics: inventory and plan

**Terms:** A-A = air-to-air; A-G = air-to-ground; ACM = air combat mode; AIFF = advanced identification friend or foe
(an interrogator); CCIP / CCRP = continuously computed impact / release point; CRM = combined radar mode; DAS =
distributed aperture system (the F-35's six infrared cameras); DED = data entry display; DLZ = dynamic launch zone;
DMS / TMS / CMS = display / target / countermeasures management switch; DTOS = dive toss; EOTS = the F-35's
electro-optical targeting system; FCR = fire-control radar; GM / GMT = ground map / ground moving target; HMD =
helmet-mounted display; HOTAS = hands on throttle and stick; HSD = horizontal situation display; ICP = integrated
control panel; LADD = low-altitude drogue delivery (a loft); LAR = launch acceptability region; MAW = missile approach
warning; OSB = option select button; PCD = panoramic cockpit display; RWR = radar warning receiver; SAR = synthetic
aperture radar; SMS = stores management; SOI = sensor of interest; STT = single-target track; TACAN = tactical air
navigation; TSD = tactical situation display; TWS = track while scan; WOW = weight on wheels.
"Inferred" = our own reasoning; "open" = no source found.

17 November 2026. The user lifted the avionics park: "Yes avionics and playability is the next big thing";
"Priority inside playability: avionics, missle and bombs. We need a proper plan before training and campaign";
"Avionics includes all radar mode (sufa, Barak, adir, in that order),missle and bombs launching etc. Most of it should
already be in reborn"; "All mfds"; "All possible avionics tldr". On missiles, employment on the existing shared model
and data "is good enough, just have real physical performance" for the jet and the bombs.

This document is the inventory and the plan only. It changes no code. It holds:
1. per jet, the real jet's avionics as far as public sources go, each row with what exists today and where (§2–§4);
2. the gap list with sizes and tests (§5);
3. the build order in slices, each ending playable and testable (§6);
4. the parked rows (§7) and the user's decisions of 17 November (§8).

The Ra'am (F-15I) gets no column: Modern IAF does not fly it yet (`modern-iaf/menu/front_end.gd` `SOON`). Its Real
HUD (`crates/iaf-avionics/src/real_hud/f15e.rs`) and SPICE 1000 test (`tests/godot/test_raam.gd`) exist in reborn
for when it does.

## 1. How to read the inventory

Each row is one function of the real jet. The "Today" column names the code that does it; the status says how far
Modern IAF reaches it:

| status | meaning |
|---|---|
| **Sim** | works in Modern IAF today |
| **Partly** | in the sim, with the gap named in §5 |
| **Reborn** | the logic exists in `shared/` or `crates/` and runs in iaf-reborn; the sim does not reach it yet |
| **Missing** | no code anywhere |

Facts that hold for every jet (verified in the code, 17 November 2026):
- The sim runs the shared weapons and avionics code unchanged: `shared/weapons/player_weapons.gd` owns the radar
  (`shared/weapons/radar.gd` over `crates/iaf-avionics/src/radar.rs`), the RWR (`rwr.rs`), the stores (`stores.rs`),
  the bombs (`bombs.rs`), the GPS bombs (`gps.rs`), the release rules (`release.rs`), the gun (`gun.rs`), the
  missiles (`missile.rs`, `sight.rs`) and the EO sensor (`eo.rs`). Its profile fixes the real options on
  (`modern-iaf/sim_settings.gd` `PROFILE`: `hud_style` real, `real_mfds` real, `weapon_data` real, `bomb_release`
  real).
- The radar has the 1998 game's nine modes: OFF, STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP
  ([../../docs/radar.md](../../docs/radar.md) §1). Every real mode below maps onto one of them or is new.
- **The weapons range is the sim's only hostile set** (slice 1, built 17 Nov): each jet's range mission
  (`<base>_range`, [training.md](training.md) §3.4) has five drones (the sim's own F-16 and F-35 flown by the shared
  AI, red for the exercise, never shooting) and six ground targets (four retired airframes parked, a fifth towed, a
  target barge). The threat records stay
  drafts awaiting the user (`modern-iaf/data/db/drafts/`, [threat-records.md](threat-records.md)); the other
  missions carry no targets.
- The keys are the 1998 game's (`modern-iaf/data/keys.json`: Q radar mode, R A-A / A-G, S standby, `.` / `,` range,
  `\` boresight, Return / Shift+Return target, Backspace drop lock, M master mode, `[` / `]` weapons, Space release,
  Tab gun, L laser, I / T / U / D pages). K and Shift+K (GPS PRE / VIS, next PRE target) are hard-wired in
  `shared/terrain/terrain_view.gd`, so the Keys screen and the notebook do not list them.

## 2. F-16I Sufa

The Sufa is a Block 52+ with the AN/APG-68(V)9 radar, colour MFDs with a moving map, an Elbit wide-angle HUD, the DASH
IV helmet and an Elisra / Elbit EW suite[^sufa-at][^sufa-lm-radar][^sufa-dash4][^sufa-janes]. Its displays and modes
are not public; the rows take the Block 50 dash-34 manual[^dash34], the MLU pilot's guide[^mlu1] and a Block 50
simulator manual[^dcs-f16] as the nearest public layout (inferred for the Sufa, as [../../docs/f16i.md](../../docs/f16i.md) §4 already does).

### 2.1 Radar (AN/APG-68(V)9)

The (V)9's named modes: range-while-search, air combat, TWS, STT, cluster resolution, target illumination, a
situation-awareness mode with four tracked targets; SAR with 2 ft resolution, GMT, sea surveillance, terrain
following[^sufa-at][^sufa-lm-radar]. The pilot's view of each is the dash-34's FCR format
([../../docs/real-mfd.md](../../docs/real-mfd.md) "FCR").

| # | function (real) | what the pilot sees and does | today | status |
|---|---|---|---|---|
| R1 | Power, warm-up, STBY, OVRD | FCR switch on the SNSR PWR panel; the FCR format shows STBY until a mode is chosen; OVRD stops radiating. Forums agree the radar does not radiate with weight on wheels; whether NO RAD shows is open[^wow] | the FCR switch powers the radar (`player_weapons.gd` holds it off through `IafRadar.set_damaged`); powered it comes up in STBY, does not radiate with weight on wheels, goes to CRM on the first Q / R or by itself once airborne; OVRD on OSB 4 / Ctrl + `/`; `NO RAD` low on the scope while a mode is chosen and nothing radiates (inferred) (`radar.rs`, [../../docs/radar.md](../../docs/radar.md) §9.1) | Sim (17 Nov) |
| R2 | CRM RWS / LRS search | B-scope, range 10–160 NM, search returns as squares, altitude in kft beside the acquisition cursor | LRS (`radar.rs` `Mode::Lrs`, the F-16I row: 58 NM), shown as `CRM RWS` with the real FCR's 10–160 NM scales and the cursor's range bump (radar.md §9.3) | Sim |
| R3 | Scan width and bars, antenna elevation | OSB 18 `A6 / A3 / A1`, OSB 17 `B1–B4`; the elevation thumbwheel; the cursor's altitude coverage | the real scan volumes: A6 / A3 / A1, B4 / B1 / B2, TWS's pairs, the antenna elevation held on Alt + Up / Down, the cursor's altitude coverage, the scan limits and carets on the FCR (`radar.rs` `volume`, radar.md §9.2; bar height and scan rate inferred) | Sim (17 Nov) |
| R4 | TWS | triangles turned to the heading, up to 10 tracks, the bug circled | `Mode::Tws`, the triangles and bug on the FCR; the real FCR's files kept 13 s, flashing their last 8 s, at most 10, no bug by itself; the bug centres the scan; EXP 4:1 about the bug (OSB 3 / Ctrl + `;`) (radar.md §9.3) | Sim |
| R5 | STT | the lock, the STT data line (aspect, track, CAS, closure), the DLZ on the right edge | `radar.rs` `lock_stt`, `f16_mfd.gd` `_stt_line` / `_dlz` | Sim |
| R6 | VSR (velocity search) | closure speed up the scale, velocity marks on the right edge | closing targets only, up the scope by closure (0–1,200 kt, inferred), marks every 400 kt (radar.md §9.3) | Sim (17 Nov) |
| R7 | Situation awareness, four tracked targets | (V)9: four tracks kept while searching[^sufa-lm-radar]; layout open | SAM in RWS: four bugs revisited every frame while the search goes on, the newest the weapons' target; `radar.fcr.sam_tracks` (radar.md §9.3) | Sim (17 Nov) |
| R8 | ACM: 20 / 60 / SLEW / BORE | 10 NM, no targets until lock; the four patterns on OSB 2 and the HOTAS | the four patterns as volumes (20, 60, SLEW stabilised on the cursor, BORE; inferred from simulator forums), OSB 2 and the TMS keys; no targets until lock; the HUD's 10 × 60 line and SLEW / BORE crosses (inferred; radar.md §9.2, §9.5) | Sim (17 Nov) |
| R9 | Cursor, bug and lock by the TMS | the cursor slewed by the throttle's cursor control, TMS up to bug / lock, TMS down to drop | the acquisition cursor on Ctrl + arrows or the mouse; TMS up / down / right / left on `/`, Shift + `/`, `;`, Shift + `;` (radar.md §9.4); Return / Shift+Return walk the contacts; Backspace drops | Sim (17 Nov; DMS / SOI slice 4) |
| R10 | GM: NORM / EXP / DBS1 / DBS2, FZ, SP, CZ, STP / TGT, designate, FTT | the PPI fan, X-Y cursors, a tracked point as a diamond | the real FCR's GM (`radar.rs` "air-to-ground"): the fan and the EXP / DBS patches over a radar picture of the terrain, the ground cursor, FZ, SP, CZ, STP / TGT, TMS up designating or tracking (FTT), the weapons' point ([../../docs/radar.md](../../docs/radar.md) §9.7) | Sim (17 Nov) |
| R11 | SAR, 2 ft | a still high-resolution patch around the cursor | DBS2's patch (64:1) held by FZ, from the terrain's heights; the (V)9's own SAR format is not public (inferred) | Sim (17 Nov) |
| R12 | GMT | bright movers on a dimmed map | `Mode::Gmt`; the real FCR's to 40 NM, its map dimmed, EXP; the range's towed hulk moves for it | Sim |
| R13 | SEA | GM tuned for ships, no DBS | GM listing ships only, no DBS; the range's barge off the coast | Sim (17 Nov) |
| R14 | AGR, BCN, TF | ranging for the A-G solution; beacon; terrain following[^sufa-at] | AGR with a CCIP bomb or the A-G gun: the slant range along the pipper's line on the FCR and the HUD; BCN parked by G12 (no beacons in the sim); TF from the LANTIRN navigation pod's TFR, not the radar ([weapons.md](weapons.md) §7.4) | AGR Sim (17 Nov); TF Sim (19 Nov, the pod); BCN parked (G12) |
| R15 | AIFF interrogation | TMS left; a green circle (friend) or yellow square (unknown) at the reply on the FCR[^mlu1] | O (SCAN), Shift + O (LOS) and TMS left in CRM; green circles / yellow squares on the FCR and the HSD for 3 s, SCAN blanking the FCR; the DED's IFF and INTG pages ([ews.md](ews.md) §5, §8; `aiff.rs`); the transponder's modes, codes and IDENT (Alt + K) on the IFF and CNI pages, a cockpit procedure only ([ews.md](ews.md) §8) | Sim (17 Nov) |

### 2.2 MFD formats (colour)

| # | format | real content | today | status |
|---|---|---|---|---|
| M1 | Frame | 20 OSBs, SWAP, three formats per MFD, DCLT, the format menu, the DMS stepping formats | `crates/iaf-avionics/src/f16_mfd.rs`, `shared/cockpit/f16_mfd.gd`; the 3D cockpit's OSBs press through their own path ([cockpit.md](cockpit.md) §5.2 "Every control"); the formats kept per master mode, DMS on keys, RESET's MSMD / DCLT ([../../docs/mfd.md](../../docs/mfd.md) §9 "Modern MFDs") | Sim (17 Nov) |
| M2 | FCR | §2.1 | `f16_mfd.gd` `fcr`; the CNTL page (OSB 5) with TGT HIS and MTR acting on the search (radar.md §9.3) | Sim |
| M3 | HSD | depressed view, rings, route, scan wedge, threat rings, colour map; CNTL, data-link tracks, bullseye | `f16_mfd.gd` `hsd` with the sim's map; DEP / CEN, CPL, EXP1 / 2, FRZ, the CNTL page (FCR, PRE, NAV1, RINGS, BULL), the bullseye (the home base, inferred), the HSD cursor and TMS up on a steerpoint (`f16_mfd.rs` `Hsd`); data-link tracks (the DL switch; [ews.md](ews.md) §6) | Sim (17 Nov) |
| M4 | SMS | INV, AAM, A-G (CCIP / CCRP / DTOS / LADD / MAN, profiles, fuzing NSTL / NOSE / TAIL, pairs, interval, pulses), GUN, S-J | INV, AAM, A-G with the GPS block, GUN (EEGS / STRF), S-J (`f16_mfd.gd` `sms_format`); RDY needs MASTER ARM and ST STA ([weapons.md](weapons.md) §5); the A-G submode menu with CCIP, CCRP, DTOS, LADD and MAN, OSB 18 the fuze, OSB 17 the arming delay, PROF1 / PROF2 per weapon keeping them ([weapons.md](weapons.md) §9); RBS and the CNTL page not started | Sim (18 Nov) |
| M5 | WPN | weapon video (Maverick), HAS, a GPS bomb's status | `f16_mfd.gd` `wpn` / `_jdam`; the sim carries no Maverick or HARM | Sim (GPS) |
| M6 | TGP | the Litening picture, WIDE / NARO, laser, polarity, range | `f16_mfd.gd` `tgp`, `shared/weapons/eo_sensor.gd`; the Litening on station 5 (the chin; [weapons.md](weapons.md) §7); POINT / AREA / INR track, slaved to the radar's designation or the steerpoint (TMS down), the zoom, LASER ARM and the laser | Sim (17 Nov) |
| M7 | TEST | the fault list | `f16_mfd.gd` `test` | Sim |
| M8 | SOI | the SOI box, NOT SOI, the DMS moving it | the SOI box and NOT SOI on the MFDs, DMS on keys, the cursor and TMS keys acting on the SOI (`f16_mfd.rs` `dms`, `cockpit.gd` `soi_format`); the HUD's asterisk as the SOI ([ufc.md](ufc.md) §4) | Sim (17 Nov) |
| M9 | DTE, FLCS, FLIR, TFR, BLANK, RESET | data transfer, flight controls, navigation FLIR, terrain following | DTE (LOAD), FLCS (branches, BIT on the ground), BLANK, RESET MENU (inferred layouts); FLIR (OSB 16, with a navigation pod) and TFR (OSB 17, the Sufa's LANTIRN): [weapons.md](weapons.md) §7.4 | Sim (17 Nov; FLIR, TFR 19 Nov) |

### 2.3 HUD and helmet

| # | function | real | today | status |
|---|---|---|---|---|
| H1 | NAV / A-A / A-G layouts | dash-34 figs. 1-110 / 1-111 / 1-115 ([../../docs/real-hud.md](../../docs/real-hud.md) "F-16C/D") | `crates/iaf-avionics/src/real_hud/f16.rs` through `shared/cockpit/hud.gd`, in the sim's P43 light; the HUD control panel's SCALES (VV/VAH), FP MARKER, VELOCITY, ALT (AUTO's thermometer), DED DATA, DEPR RET ([ufc.md](ufc.md) §4) | Sim (17 Nov) |
| H2 | Break X, GAAF, pull-up cue, ALOW | flashing X at the GAAF advisory, steady inside Rmin; the U; `AL` below ALOW[^dash34gaaf] | `crates/iaf-avionics/src/gaaf.rs`, `f16.rs` `pullup_cue`; the original's own break X rule also runs (`player_weapons.gd` `_break_x_cue`); RDR ALT gates the radar altitude; ALOW set on the DED | Sim (17 Nov; G2) |
| H3 | DGFT / MSL override | the throttle's switch: the dogfight radar, gun and SRM at once | V / Shift + V: the radar's ACM / CRM, the SRM / MRM, the HUD's DGFT with the EEGS funnel ([ufc.md](ufc.md) §5) | Sim (17 Nov) |
| H4 | VVI, ALIGN / RDY, SIM | the vertical velocity scale; the INS alignment cue; SIM training mode | VV/VAH's scale, ALIGN steady / flashing, MASTER ARM's SIMULATE with `SIM` ([ufc.md](ufc.md) §3–4) | Sim (17 Nov) |
| H5 | DASH IV helmet | the aiming cross, the seeker diamond, HOBS cues | `crates/iaf-avionics/src/real_hud/dash.rs`; the HMCS SYM INT switch darkens it ([cockpit.md](cockpit.md) §5.2) | Sim |

### 2.4 RWR and EW

| # | function | real | today | status |
|---|---|---|---|---|
| E1 | RWR display | Elisra RWR[^sufa-at]; the threat azimuth indicator's symbols (real-mfd.md "The threat azimuth indicator") | `rwr.rs` (all-aspect on the modern F-16s) and `ews.rs` on the 3D RWR scope: labels by class, the diamond, lock square, launch circle, new-threat flash, PRI / OPEN, UNKNOWN, TGT SEP, HANDOFF, SYS TEST, the THREAT / MSL knobs; the range's radar drones show as "35" ([ews.md](ews.md) §2) | Sim (17 Nov) |
| E2 | MAW | PAWS: "the direction, missile type, and time to impact"[^sufa-janes] | `ews.rs` `Maw` from the RWR's missile list: an "M" on the RWR scope at the missile's direction with the seconds to impact, the launch tone ([ews.md](ews.md) §3); no missile type: a missile's type and performance belong to the parked rows (§7) | Sim (17 Nov) |
| E3 | Jammer | SPS-3000 / internal jammer[^sufa-at][^sufa-periscope] | the shared ECM (J; [../../docs/weapons.md](../../docs/weapons.md) §10) | Partly (G3) |
| E4 | Chaff / flares, programs | dispenser programs from the CMS | `cmds.rs`: the CMDS panel (MODE, CH, FL, O1, O2, RWR, JMR, MWS, JETT), programs 1–4, the CMS keys (P, Shift + P, Y), SEMI / AUTO on a launch, "Counter", "Chaff flare low / out"; releases through the game's dispense ([ews.md](ews.md) §4); the DED's EWS pages: programs, BINGO, options ([ews.md](ews.md) §8) | Sim (17 Nov) |

### 2.5 Stores, release and weapons

| # | function | real | today | status |
|---|---|---|---|---|
| S1 | Master arm, ST STA, release limits, jettison | MASTER ARM, the stations' power, emergency and selective jettison | [weapons.md](weapons.md) §3, §5; `crates/iaf-avionics/src/release.rs` | Sim |
| S2 | CCIP and delayed CCIP | pipper, fall line, designate and steer[^dash34ccip] | `bombs.rs` fall with drag, `f16.rs` delayed CCIP | Sim |
| S3 | CCRP | TD box on a designated point, azimuth line, solution cue, automatic release | `delivery.rs` `solve` on the bomb's own fall, `f16.rs` `delivery_cues`; the target the radar's designated point, the pod's track or the steerpoint ([weapons.md](weapons.md) §9) | Sim (18 Nov) |
| S4 | DTOS | designate in a dive, then a CCRP-style release | the TD box on the flight path marker, WPN REL / TMS up designates, TMS down rejects, CCRP's release in a dive or a toss | Sim (18 Nov) |
| S5 | LADD | a loft with a pull-up cue and release timing | the pull-up time for a 4 g pull to 45° from the bomb's fall, the anticipation cue and bar, the 45° bar, the release in the climb | Sim (18 Nov) |
| S6 | MAN | a fixed, depressible reticle | the primary reticle at DEPR RET PRI, depressed by the RET DEPR wheel (keys Ctrl + V / Alt + V), the release at once | Sim (18 Nov) |
| S7 | Pairs, interval, pulses | SMS OSBs 8–10 | `release.rs` `Ripple`, the SMS OSBs | Sim |
| S8 | Fuzing, arming time, LOW cue | NSTL / NOSE / TAIL; LOW when the release is below the fuze's arming height | OSB 18 the fuze, OSB 17 the arming delay (4.80 s), a bomb that hits sooner a dud; `LOW` beside the marker, the pull-up anticipation cue rising for the arming height (`delivery.rs`; [weapons.md](weapons.md) §9) | Sim (18 Nov) |
| S9 | GPS bombs (GBU-31, GBU-38, GBU-39) PRE / VIS, LAR, TMR, TTI | [../../docs/weapons.md](../../docs/weapons.md) §13.2–13.3 | `crates/iaf-avionics/src/gps.rs`, the HUD and WPN cues; the range missions' target steerpoint is every GPS bomb's PRE target (18 Nov, `"target": true`), Shift + K steps the planned targets and the steerpoints; since 19 Nov (A61, G4) each station and each bomb of a rack takes its own PRE target on the briefing's PRE targets panel | Sim (19 Nov) |
| S10 | SPICE 1000 / 2000 | INS / GPS then scene matching[^sufa-spice] | the GPS bomb code with wings (LD 6.8); listed on the sim's F-16s | Partly (G4) |
| S11 | Laser bombs, pod lasing | Litening II pod; GBU-10 / 12 / 16 carried[^sufa-at] | `release.rs` `laser_aim`, `tests/godot/test_laser_bombs.gd`; the sim's GBU-10 / 12 / 16 and Litening records ([weapons.md](weapons.md) §7), `modern-iaf/tests/test_sim_mfd.gd` | Sim (17 Nov) |
| S12 | Gun: EEGS, LCOS, strafe | dash-34 EEGS levels, STRF | `gun.rs`, `f16.rs`; 511 rounds ([weapons.md](weapons.md) §1) | Partly (G23: the flash) |
| W1 | SRM (AIM-9M): seeker, tone, uncage | the cage / uncage button, SPOT / SCAN | caged on the radar's lock, the helmet or the boresight, the tone when it hears a target; Shift + M uncages it to track, Ctrl + S or the SMS's OSB 2 steps SPOT / SCAN (`sight.rs` `Head`; [weapons.md](weapons.md) §8.1) | Sim (18 Nov) |
| W2 | Python 5 HOBS, LOAL | 100° off boresight, LOAL[^sufa-python] | [../../docs/weapons.md](../../docs/weapons.md) §13.1, the DASH cues | Sim |
| W3 | MRM (AIM-120): ASEC, ASC, DLZ, SHOOT | dash-34 A-A missile HUD | `sight.rs` MRM sight, `f16.rs` DLZ | Sim |
| W4 | Post-launch cues | time to active / to impact, the missile's target on the FCR | A / T and the seconds on the HUD and the FCR, the target's tail and its X for the last 8 s (`missile.rs` `times`; [weapons.md](weapons.md) §8.2) | Sim (18 Nov) |

### 2.6 Navigation, communication, controls

| # | function | real | today | status |
|---|---|---|---|---|
| N1 | INS alignment | the INS knob, the DED INS page, the HUD ALIGN / RDY | the knob and 90 s / 8 min alignment (`start.rs`), the DED's INS page, the HUD's ALIGN, no steering until it navigates ([ufc.md](ufc.md) §3) | Sim (17 Nov) |
| N2 | Steerpoints, DED, ICP | STPT page, keypad entry, markpoints, bingo, ALOW setting | every DED page with data entry (`ufc.rs`): STPT editing, markpoints 26–30, BINGO, ALOW, CRUS, TIME, BULL, FIX, the radios ([ufc.md](ufc.md) §2) | Sim (17 Nov) |
| N3 | TACAN | channel, bearing and range to a base | T-ILS page, the bases' stations (our channels), the EHSI's TCN ([ufc.md](ufc.md) §2) | Sim (17 Nov) |
| N4 | ILS | localizer and glide slope | the HUD's ILS lines at the exact deviation ([../../docs/real-hud.md](../../docs/real-hud.md) "What ours draws") | Sim |
| N5 | Data link | Link 16 / IDM tracks on the HSD and FCR | `datalink.rs`: the flight's jets and the AWACS's tracks on the HSD and the FCR with the DL switch, the DED's DLNK page ([ews.md](ews.md) §6, §8) | Sim (17 Nov) |
| N6 | Radios | UHF / VHF, the tower, AWACS | COM1 / COM2 presets and the backup UHF on the DED ([ufc.md](ufc.md) §2); the tower menu ([training.md](training.md) §8); the AWACS's contact calls (`fctrl.rs`) on the range in the AWACS's voice ([ews.md](ews.md) §7) | Sim (17 Nov) |
| N7 | HOTAS functions | TMS, DMS, CMS, cursor, uncage, DGFT, expand, pickle, trigger | pickle, trigger, chaff / flare as keys; TMS, the cursor and DMS on keys (slices 2 and 4); DGFT / MSL OVRD on V (slice 5); the CMS ([ews.md](ews.md) §1); uncage on Shift + M (slice 8) | Sim (18 Nov) |

## 3. F-16D Barak: its differences

The Barak in the sim is today's upgraded F-16D (§8.4): the Block 40 two-seater after Barak 2020, which "installed the
avionic systems of the Sufa" (2010–2014)[^barak-hm][^barak-upi][^barak-fg]. Its definition is the F-16's
(`shared/extra/planes/f16/airframe.json`, the original game's Barak, unchanged) with the sim's own file merged over it
(`modern-iaf/data/planes/f16.json`, `sim_settings.gd` `airframe_def`). Rows not listed here are the Sufa's, with the
same status; slice 6 flew every Sufa test on the Barak (§6).

| # | function | real (Barak 2020) | today | status |
|---|---|---|---|---|
| B1 | Radar | the Block 40's AN/APG-68; no source names a radar change in Barak 2020 (open); no (V)9 situation mode | the F-16 row of `radar.rs` (CRM RWS to 80 km, 43 NM, Weapon data Real's; the Sufa 104 km) with the real FCR's controls, SAM with one bug (`radar.fcr.sam_tracks` 1; inferred) | Sim (17 Nov) |
| B2 | MFDs | the Sufa's avionics[^barak-hm] and new high-resolution screens[^barak-upi]; colour inferred | the colour formats (`mfd` "colour") | Sim (17 Nov) |
| B3 | HSD map | with the colour displays (inferred) | the HSD's map, as the Sufa's | Sim (17 Nov) |
| B4 | AIFF | with the Sufa's avionics (inferred: no source names the interrogator) | the Sufa's AIFF (`ews.aiff`) | Sim (17 Nov) |
| B5 | Pods | the Sharpshooter, then the Litening; the Pathfinder navigation FLIR, without a TFR ([research/pods.md](research/pods.md) §1) | the Litening on 5R, the Pathfinder on 5L with its FLIR on the HUD ([weapons.md](weapons.md) §7.4), the laser bombs (§8.2); no TF | Sim (17 Nov; FLIR 19 Nov) |
| B6 | Helmet | an Elbit helmet sight[^barak-upi] | `dash.rs` | Sim |
| B7 | RWR | the set is open (the dash-34's display is the nearest) | as the Sufa's E1 | Partly (G3) |
| B8 | MAW, SAM mode, SAR | no MAW: an infrared missile warning is among the upgrades proposed for the Barak in 2025[^barak-dn]; SAM keeps one bug (B1); DBS as the APG-68's (dash-34) | no MAW (`ews.maw` false); DBS1 / DBS2 as the Sufa's | Sim (17 Nov) |
| B9 | HUD | a new head-up display[^barak-fg]; the Sufa's wide-angle frame inferred | the 3D cockpit's wide HUD (`hud_3d` "HUD_wide"), the Real HUD | Sim (17 Nov) |
| B10 | TACAN at the start | the home base's station (inferred: the pilot's preset) | tuned to the nearest station when the jet is placed (the home base on a ground start) (`ufc.rs` `tune_nearest`); before, every jet started on Ramon's 75X | Sim (17 Nov) |
| B11 | Rear seat | the navigator works the pod; in the game the player does it (pods decision 4) | the front seat's keys and controls | Sim |

## 4. F-35I Adir

The Adir carries the AN/APG-81 (air-to-air modes, SAR mapping, multiple GMTI and track, combat identification,
electronic attack and support)[^apg81], the EOTS (called TFLIR on the displays)[^baseline], the DAS (missile
detection, aircraft tracking and IRST, imagery for the helmet)[^das], the Gen III helmet[^collins] and the PCD
([../../docs/real-mfd.md](../../docs/real-mfd.md) "F-35I Adir"). Its formats are public only through simulator
manuals[^ife] and LM slides[^sld-cockpit]; each row says so.

| # | function | real | today | status |
|---|---|---|---|---|
| A1 | Radar power and standby | managed by the mission systems (inferred); no FCR switch on the panel ([research/f35-cockpit.md](research/f35-cockpit.md) §2) | the radar comes up in STBY with power and searches once airborne (radar.md §9.1); the definition's `radar.auto` gives the same in the 1998 game, whose F-35I showed `RADAR OFF` on the display until Q (fixed 17 Nov, `tests/godot/test_f35i_radar.gd`) | Sim (17 Nov) |
| A2 | SRCH (A-A search) | layout open[^f16net-pages] | `shared/cockpit/pcd_formats.gd` `radar` on the F35I row of `radar.rs` with the real FCR's controls (`radar.fcr`, sam_tracks 4, inferred): CRM RWS / TWS / VSR, the 10–160 NM scales, the scan width and bars, the scan limits, the cursor with its altitude coverage, NO RAD; the Sufa's keys ([../../docs/radar.md](../../docs/radar.md) §9); the fan layout inferred (G32: no source shows it) | Sim (17 Nov) |
| A3 | A-A track, TWS, STT, ACM, BORE | fused tracks; layout open | the shared real-FCR modes on SRCH: SAM's four bugs, STT by TMS up, TWS's files, ACM's patterns and BORE, the lock's range, altitude and closure (`test_sim_adir_radar.gd`) | Sim (17 Nov) |
| A4 | ASR: SAR map | a grey SAR picture (LM slide 8, a simulator manual)[^sld-cockpit][^ife] | the real FCR's ground map (`radar.rs` `render`, the F-16's DBS patch) grey and square on ASR: GM, EXP, DBS1, DBS2, FZ, SP, CZ, STP / TGT, SEA, AGR; the X-Y cursor on Ctrl + arrows ([../../docs/f35i.md](../../docs/f35i.md) §4.3) | Sim (17 Nov) |
| A5 | GMTI | multiple movers tracked | the real FCR's GMT on ASR: the movers as tracks over the dimmed map | Sim (17 Nov) |
| A6 | EA, passive ESM | electronic attack and support[^apg81] | the shared ECM (J); the ESM's part of combat ID (A7: a heard radar names its unit hostile) | Parked: electronic attack is out (§8.5, §7) |
| A7 | Combat ID, fused identity | green circle friend, yellow square unknown, red diamond hostile[^codeone] | `aiff.rs` `combat_id` (inferred): a friend answering the interrogator (on by itself) is a friend; the data link's AWACS naming it hostile, or its radar heard on the TWD, makes it hostile; else unknown; on SRCH, ASR, the TSD and the helmet's lock (`ews.gd` `state.ident`, `pcd_formats.gd` `track_kind`) | Sim (17 Nov) |
| P1 | PCD frame | function bar, the halves (one large portal with tabs, or two portals over four windows), MENU grid, touch[^codeone][^ife] | `shared/cockpit/pcd.gd` draws the layout of `IafPcd` (`crates/iaf-avionics/src/pcd.rs`): the MENU grid's 20 formats by a tap or by keys (Home, Ctrl + F9 / F10, End), the cursor's portal (DMS left / right, a tap), a window or tab into its portal (a tap, Ctrl + Home), the function bar's SWAP (its arrows, Shift + End: its halves trade places, the portals stay; a simulator manual[^ife] p. 34), its MENU page with CRUS, the bar's items opening their pop-ups; keys records 241–250 ([../../docs/f35i.md](../../docs/f35i.md) §4.3) | Sim (19 Nov) |
| P2 | TSD-1 / 2 / 3 | the fused picture, route, threats | `pcd_formats.gd` `tsd`: the radar's and the data link's tracks by their combat ID, the route, the SAM sites | Sim (17 Nov) |
| P3 | SMS | planform, stations, master arm, doors | `pcd_formats.gd` `sms`: ARM / SAFE, a tap selects a station, the bays drawn with their doors' state (grey shut, yellow moving, white open) and DOORS | Sim (17 Nov) |
| P4 | TFLIR (EOTS) | the EOTS picture, NAV / A-S, laser | `pcd_formats.gd` `tflir`; the EOTS stands in as a built-in pod (`player_weapons.gd` `flir_pod`); the F-16 TGP's functions it shares: the track mode (POINT / AREA / INR by the TMS keys with the TFLIR the SOI), zoom, WIDE / NARO, the laser, CZ as legends down its edge | Sim (17 Nov) |
| P5 | TWD | the threat format: layout open | `pcd_formats.gd` `twd` with the shared threat display (`ews.rs` `Twd`): the range's radar drones as "35", lethality rings, the diamond, lock and launch marks; the TWP keys (Alt + Y / I / O / J, Ctrl + I); the circle layout inferred | Sim (17 Nov) |
| P6 | EFI, ICAWS, FUEL, ENG, ESIS | [^ife] pp. 42–47 | `pcd_formats.gd`, `pcd.gd`; the EFI's TACAN caret with the navigation source on TCN | Sim |
| P7 | WPN-A / WPN-S | weapon status and programming: open | `pcd_formats.gd` `wpn_a` / `wpn_s` (layouts inferred): the A-A stores and the lock; the A-S store's status, mode (CCIP, PRE / VIS), the F-16 SMS's profiles (PROF, SGL / PAIR, pulses, interval; `release.rs` `Profiles`) and a GPS bomb's per-bomb targets | Sim (17 Nov) |
| P8 | CNI | radios, navigation, IFF on glass[^codeone] | `pcd_formats.gd` `cni` over the F-16's up-front controls (`ufc.rs`): COM1 / COM2 presets, the navigation source RTE / TCN, the TACAN to the bases, the transponder's modes, code and IDENT, the scratchpad and a keypad; the ICP keys work it; the function bar shows the radios, the source and IFF | Sim (17 Nov) |
| P9 | DAS | imagery on the PCD and the helmet; missile warning; IRST[^das]; in the helmet the pilot picks the DAS's infrared video or the night vision camera[^afi35] | the DAS format (`pcd_formats.gd` `das`): the forward aperture's picture (`terrain_view.gd` `_update_das_view`: a camera on the nose 90° across, 320 px wide, grey through the night-vision shader's DAS look; it renders only while the format is drawn), the six apertures' sectors, the MAW marks; in the helmet Alt + F7 steps the night camera, the DAS's video and off (`_helmet_video_step`, record 247). Inferred: which aperture the format shows (the forward one, as a simulator shows it[^ife]) and the look (the scene's light amplified, grey: the scene has no heat). IRST stays with the radar's tracks | Sim (19 Nov; slice 7 part D) |
| P10 | FCS, PHM, CHKLST, DIM, HUD repeat | [^ife] | `pcd_formats.gd` (layouts inferred): FCS the planform, gear, flaps, channels A–D and BIT (the F-16 FLCS's rule); PHM the fault list; CHKLST the start-up checklist's steps; DIM LOAD; HUD the helmet's flight symbols repeated | Sim (17 Nov) |
| P11 | Double-width formats, 5 preset layouts | [^codeone][^sld-cockpit] | `IafPcd`: a portal widened over its half (the header's arrows, Ctrl + End), enlarged over its windows (▼, Shift + Home), the five presets (Alt + `,`; their contents inferred from LM slides 7 and 8 and Code One) | Sim (17 Nov) |
| P12 | HOTAS: cursor slew, TMS, DMS, FLC, cage / uncage, master mode hat | the USAF grip names[^hotas] | the cursor on Ctrl + arrows; TMS on the sensor of interest (the radar with SRCH under the cursor, the EOTS's track with TFLIR); DMS up / down the SOI between the helmet and the display, left / right the cursor's portal; M the master mode; cage / uncage on Shift + M (slice 8, [weapons.md](weapons.md) §8.1); FLC (19 Nov, slice 7 part E): turned (Alt + F9 / F10) the cursor's portal steps through the MENU grid's formats, pushed (Alt + F8) the portal's TSD steps its layers (all; without the map and the route; the tracks only, `pcd.rs` `flc_turn` / `flc_push`, records 244–246). Decision 19 Nov: the USAF list names the switch "Format Layer Control" and nothing more[^hotas]; its two actions follow the name (inferred) | Sim (19 Nov; FLC inferred) |
| H6 | Helmet: virtual HUD, off-boresight set | LM slides[^lm-slides] | `crates/iaf-avionics/src/real_hud/f35.rs` | Sim |
| H7 | Helmet A-A / A-G / gun cues | graphics not public | the F-16's stand-ins in `f35.rs`; the lock's designator carries its combat ID's shape (circle, square, diamond; inferred); the DAS's missile warnings as an "M" with the seconds about the boresight (inferred) | Sim (17 Nov; inferred) |
| H8 | Auto-GCAS / pull-up | inferred: Auto-GCAS lineage | the PULL UP voice; the F-16's break X and pull-up U in the helmet (`f16.rs` `ground_cues`; [../../docs/real-hud.md](../../docs/real-hud.md) "Pull-up and break marks") | Sim (17 Nov; inferred) |
| S13 | Bay doors, AIM-120 from the bay, AIM-9X | [../../docs/f35i.md](../../docs/f35i.md) §3 | `player_weapons.gd` bay logic over `release.rs` `bay_doors` / `bay_release_waits`; DOORS on the SMS and Ctrl + Delete hold them open; [weapons.md](weapons.md) §5 | Sim |
| S14 | GBU-31, GBU-39 (four per bay, each its own target) | [^raaf39] | `gps.rs` per-bomb targets and the pick rule (`pick_ok`); each bomb's target by name on the WPN-S and the F-16 SMS; picked on the briefing's PRE targets panel (`modern-iaf/menu/pre_panel.gd`, the shared `shared/weapons/pre_pick.gd` as reborn's TSD; A61, the user's option A, 19 Nov), kept in the loadout's `pre` | Sim (19 Nov, slice 7 part F) |
| S15 | SPICE 1000 | integration announced 2026[^twz-spice] | on the bays' air-to-ground stations 4 / 8, one each, inside (the source: "expected to be carried internally"; the stations inferred); the GPS bomb code with wings | Sim (17 Nov) |
| S16 | Gun GAU-22/A | 180 rounds | `gun.rs`, [weapons.md](weapons.md) §1 | Partly (G23) |
| E5 | MAW | through the DAS[^das] | `ews.rs` `Maw` (the Sufa's): the missile's bearing and seconds to impact on the TWD and in the helmet, the RWR's launch tone; no missile type (§7) | Sim (17 Nov) |
| N8 | INS ready, steerpoints, ILS, TACAN | 90 s ready[^ayton]; the steerpoint in the helmet; the NAV source on the function bar | the 90 s step, the helmet's steerpoint caret and square, the ILS lines; the TACAN on the CNI (the home base's station at the start), the function bar's NAV source, the EFI's caret | Sim (17 Nov) |
| N9 | Data link (MADL, Link 16) | fused tracks from other jets | `datalink.rs` (the F-16s'): the flight's jets and the AWACS's tracks on the TSD, on from the start (no DL switch; inferred) | Sim (17 Nov) |

## 5. The gap list

Size: S = up to a day's agent work, M = a few days, L = a week or more. Kind: **wire** = existing shared logic reached
by the sim; **extend** = existing shared logic grown; **new** = new logic in a Rust crate. Every new rule goes in
`crates/iaf-avionics`; Godot wires and draws.

### 5.1 The bugs of 15 November (first, by the "bugs first" rule)

| # | gap | size | kind | test |
|---|---|---|---|---|
| G1 | **Radar standby.** Powered, the radar sits at OFF until Q or R; the real FCR comes up in STBY and shows it. Make power-on go to STBY with the FCR's `STBY` legend, keep it from radiating with WOW (forum-level source[^wow]; inferred), go to CRM on the first mode press or after take-off (inferred). The F-35I the same without the switch. The user's own description of the fault is to be read back to him before the fix. **Found and fixed 17 Nov:** his words were "radar isn't working? can't move out of stby?": a start by the checklist's keys left the SNSR PWR panel's FCR off, so the radar was held dead, the FCR format showed STBY and Q / R did nothing; Ctrl+A (the avionics step) now turns FCR and RDR ALT on with the four (`start.rs`). The power-on STBY and the WOW rule were built with slice 2 (17 Nov; radar.md §9.1) | S | extend (`radar.rs` power-on state; `player_weapons.gd` FCR hold) | Rust unit test in `radar.rs`; new modern-iaf/tests/test_sim_radar.gd: FCR on → STBY on the FCR format, no contacts on the ground, CRM LRS after Q in the air |
| G2 | **Break X and the HUD against reborn.** Two break X rules run in the sim: the original's (`_break_x_cue`, the 1998 pull-up rule) and the Real HUD's GAAF (`gaaf.rs`), which reads the radar altitude the RDR ALT switch gates. First compare reborn's F-16 Real HUD and the sim's in the same states (dive, A-A lock inside Rmin, RDR ALT off), list each difference, then fix in the shared code. **Found and fixed 17 Nov** (his words: "no x on pull up?!"): the sim draws reborn's Real HUD code (`real_hud/f16.rs`) unchanged; its break X needs the radar altitude, and RDR ALT stayed off after a keyed start (the G1 cause; the GAAF voice spoke without it). The rest (17 Nov, slice 5): the sim and reborn draw the same `f16.rs`; the sim adds only the HUD panel's switches and the UFC's cues ([ufc.md](ufc.md) §4), so with the panel at its default both HUDs are the same frame | S–M | extend | `tests/godot/test_real_hud.gd` gains the states; a sim twin in new modern-iaf/tests/test_sim_hud.gd; pictures side by side (`tests/godot/_hud_compare_shot.gd`) |
| G4 | **SPICE / GPS targets.** In the sim a GPS bomb in PRE has no target: PRE targets come from reborn's briefing TSD only (`iaf-reborn/menu/tsd_gps.gd`), the sim's missions have no target steerpoint, and VIS needs a MAP designation. Fix: move the PRE target store and its pick into `shared/` (the reuse rule), let the sim's briefing map set them, and give missions a target steerpoint that `gps.rs` `default_target` reads. **Found 17 Nov** (his words: "is spice bombs really works? do we even support gps pre?"): VIS works once the radar is up (the G1 fix: R and Q give MAP, a MAP click designates, the SPICE aims there; `test_sim_radar.gd`). PRE has nothing to aim at: the sim's missions hold no target and one steerpoint at the base, and the sim's briefing has no target pick; that waits for G3's targets and the user's yes on a briefing pick. **18 Nov (slice 9):** the range missions mark their second steerpoint, on Target 1, as the target (`"target": true`, compiled as action 5), so every GPS bomb's PRE has it; the per-bomb pick on the sim's briefing map is a new panel there (reborn's `tsd_gps.gd` moved into `shared/`), a visible new look waiting for the user's yes on its own branch. **19 Nov (A61, his pick: option A):** built: the briefing's PRE targets chip and panel (`modern-iaf/menu/pre_panel.gd`; the rows and clicks of reborn's TSD moved to `shared/weapons/pre_pick.gd`), the picks in the loadout's `pre` under one rule in Rust (`gps::pick_ok`, `briefing::pre` / `pre_set`), the flight's targets from them (`flight/fly.gd`), the stores pages naming each bomb's target; `modern-iaf/tests/test_sim_pre_targets.gd`. Done | M | wire + extend | `modern-iaf/tests/test_weapons_flight.gd` gains a GBU-38 PRE and a SPICE 1000 VIS run against a ground target; `tests/godot/test_modern_weapons.gd` stays green |
| G23 | **Gun flash.** The muzzle flash hangs on the outside model only (`player_weapons.gd` `_muzzle_flash` added to `host.aircraft`); the stores are mirrored on the cockpit-view model (`own_bc`), the flash is not (inferred cause; confirm with the user's report). **Found 17 Nov:** his words were "flare of bullets stay for too long and are too big": the rounds' own tracer heads (`player_weapons.gd` `_tracer`, a fixed-size glow on every round for its whole flight), not the muzzle flash; a smaller, shorter glow waits for his yes | S | wire | `modern-iaf/tests/test_sim_gun.gd`: the flash node visible in the cockpit view while firing, hidden after |

### 5.2 Prerequisite

| # | gap | size | kind | test |
|---|---|---|---|---|
| G3 | **Targets.** **Built 17 Nov (slice 1; their radars on the threat display with slice 5, [ews.md](ews.md) §2):** a range mission per jet (`ramon_range`, `ramat_david_range`, `nevatim_range`; training.md §3.4): five drones (our F-16 and F-35 models on the shared AI under the sim's own brains, data-formats.md §5.1: co-altitude, low, a manoeuvring one, a pair with radars on) and four ground targets (F-16 and MiG-29 hulks); kills scored by the range's training kind. The SAM site with a radar waits for approved records | M | wire (shared AI, mission runtime) + data | modern-iaf/tests/test_sim_range.gd: per jet the drones fly, the radar finds one, a gun kill is scored |

### 5.3 Radar

| # | gap | size | kind | test |
|---|---|---|---|---|
| G5 | Selectable scan width (A6 / A3 / A1) and bars (B1–B4), antenna elevation, the cursor's altitude coverage | M | new (`radar.rs`: the scan volume becomes a setting; the hit test reads it) | Rust: a target outside ±10° is found with A6, not with A1; the FCR shows the coverage |
| G6 | VSR; the (V)9's four-track situation mode (Sufa only) | M | new | Rust: VSR orders by closure; the situation mode keeps four tracks while searching |
| G7 | ACM patterns 20 / 60 / SLEW / BORE | S | extend | Rust: each pattern's volume locks the target inside it |
| G8 | HOTAS layer: cursor slew, TMS (bug, lock, drop, AIFF), DMS (formats, SOI), CMS, uncage, DGFT / MSL override, expand; new keys and joystick buttons, listed on the Keys screen and in the notebook (K / Shift+K moved into `modern-iaf/data/keys.json`). **Cursor and TMS built with slice 2, DMS and the SOI with slice 4 (17 Nov); the F-35I's DMS, SOI and display keys with slice 7;** CMS, uncage, DGFT with G20, G26, G17 | M | new (a HOTAS state in Rust, keys in `modern-iaf/data/keys.json`) | `modern-iaf/tests/test_devices.gd` sees the new records; a sim test slews the cursor onto a blip and locks it with TMS up |
| G9 | GM: DBS1 / DBS2, FZ, CZ, SP. **Built 17 Nov (slice 3)** with STP / TGT, the ground cursor, designation and FTT | S | extend (`radar.rs`, `f16_mfd.gd` `_ground_map`) | Rust: freeze holds the picture; the FCR test reads the legends |
| G10 | SAR / DBS patch picture (F-16 GM DBS, F-35I ASR) from the terrain and the sim's imagery. **Built 17 Nov (slice 3)** for the F-16 (`radar.rs` `render`); the F-35I's ASR takes it, grey (slice 7, 17 Nov) | M–L | new (picture from the height field, `crates/iaf-avionics/src/heights.rs`) | a picture test: the patch shows the runway of the base under the cursor |
| G11 | SEA mode: ships as returns over water. **Built 17 Nov (slice 3)**, with the range's barge | S | extend | Rust: a ship shows, land returns do not |
| G12 | AGR (ranging for the A-G solution), BCN, TF. **AGR built 17 Nov (slice 3)**; **TF built 19 Nov from the navigation pod (pods part 2)**; BCN stays parked | S each | new | parked as low value unless the user asks |
| G13 | AIFF (Sufa) and combat ID (Adir): replies and identity on the FCR, HSD, SRCH and TSD; unknown = yellow square. **The Sufa's AIFF built 17 Nov (slice 5, [ews.md](ews.md) §5)**; the Adir's combat ID built 17 Nov (slice 7, `aiff.rs` `combat_id`) | M | new (`fctrl.rs` or a new `iff.rs`) | Rust: a friend replies, a hostile does not; the PCD and FCR draw the symbols |

### 5.4 Displays, HUD, navigation, EW

| # | gap | size | kind | test |
|---|---|---|---|---|
| G14 | HSD CNTL, bullseye, data-link tracks. **Built 17 Nov (slice 4):** CNTL, bullseye, DEP / CEN, CPL, EXP, FRZ, the cursor; the data-link tracks come with G30 | S | extend | `tests/godot/test_f16_mfd.gd` |
| G15 | Targeting pod (the Litening on both F-16s) and laser bombs in the sim's data: a pod store and laser bomb records; the TGP format, laser and laser bombs are shared already. **Built 17 Nov (slice 4):** the Litening on both F-16s (§8.2), the GBU-10 / 12 / 16, the TGP's track modes and LASER ARM ([weapons.md](weapons.md) §7) | S (data) | wire | `tests/godot/test_laser_bombs.gd` and a sim run: the pod's laser guides a GBU-12 onto a range target |
| G16 | The low-value formats (DTE, FLCS, TFR; F-35 FCS, PHM, CHKLST, DIM). **The F-16's built 17 Nov (slice 4; the user: "All mfds"):** DTE, FLCS, BLANK, RESET; FLIR and TFR built 19 Nov (pods part 2). **The F-35's built 17 Nov (slice 7):** FCS, PHM, CHKLST, DIM, the HUD repeat | S each | new (drawing) | listed, built only on the user's word |
| G17 | DGFT / MSL override. **Built 17 Nov (slice 5)** | S | extend (`master.rs`) | Rust: DGFT selects ACM, the gun and the SRM at once |
| G18 | HUD VVI; INS ALIGN / RDY on the HUD and the DED INS page. **Built 17 Nov (slice 5)** | S | extend (`f16.rs`, `start.rs` state) | Rust snapshot of the HUD; `modern-iaf/tests/test_switches_both_ways.gd` sees ALIGN then RDY |
| G19 | MAW (Sufa PAWS, Adir DAS): direction and time to impact of a missile launched at the jet, from the RWR's missile list. **The Sufa's built 17 Nov (slice 5, [ews.md](ews.md) §3)**; the Adir's DAS built 17 Nov (slice 7: the TWD and the helmet) | M | new (`rwr.rs`) | Rust: a launch shows its bearing and a falling time; voice and symbol in the sim |
| G20 | Chaff / flare programs (bursts, intervals) on the CMS. **Built 17 Nov (slice 5, [ews.md](ews.md) §4)** | S | extend | Rust: program 1 drops its count at its interval |
| G28 | DED / ICP pages: STPT entry, markpoints, bingo, ALOW setting. **Built 17 Nov (slice 5)** with every page the sim can feed ([ufc.md](ufc.md)) | M | new (Rust page state; `cockpit3d_display.gd` draws) | sim test: a markpoint over the jet becomes a steerpoint on the HSD |
| G29 | TACAN to the bases (channel, bearing, range) on the HSI / EHSI, the HUD and the F-35's function bar. **The F-16s' built 17 Nov (slice 5)**; the F-35's 17 Nov (slice 7: the CNI, the function bar, the EFI) | S | new (base channels in `modern-iaf/data/airbases`) | Rust: bearing and range to Ramon from a known point |
| G30 | Data link: tracks of the flight's other jets and of AWACS on the HSD, FCR and TSD. **The F-16s' built 17 Nov (slice 5, [ews.md](ews.md) §6)**; the F-35I's TSD built 17 Nov (slice 7) | M | new | Rust: a wingman's radar contact appears on the player's HSD |
| G31 | AWACS in the sim's missions (the shared radio calls). **Built 17 Nov:** the calls' templates and clips in the AWACS's voice ([ews.md](ews.md) §7) | S | wire | `modern-iaf/tests/test_sim_ews.gd` hears a contact call |
| G32 | SRCH layout once a source shows it. 17 Nov (slice 7): no public source shows the APG-81's search format; the fan stays, inferred, with the real FCR's content | S | extend | picture |
| G33 | F-35I electronic attack and passive ESM | M | new | open: sources are one line[^apg81]; built only on the user's word |
| G34 | F-35I WPN-A / WPN-S, CNI pop-up, double-width formats, the 5 presets. **Built 17 Nov (slice 7)** with the layout in Rust (`pcd.rs`) | M | new (drawing) | PCD test: each format opens from MENU and widens |
| G35 | DAS: the missile warning (G19) and the IR picture in the helmet at night. **Built 19 Nov (slice 7 part D, P9):** the DAS format's forward picture and the helmet's DAS video (Alt + F7); the camera 1.83 ms GPU a frame on the Iris Xe while drawn ([../../docs/rendering.md](../../docs/rendering.md) §8.1) | L | new (render) | picture at night; GPU budget on the Iris Xe |

### 5.5 Weapons

| # | gap | size | kind | test |
|---|---|---|---|---|
| G21 | CCRP, DTOS, LADD, MAN release modes with their HUD cues and SMS submodes. **Built 18 Nov** (`delivery.rs`; [weapons.md](weapons.md) §9) | L | new (`release.rs`, `bombs.rs` solution; `f16.rs` cues) | Rust: each mode's release lands within the bomb's own spread of the designated point; sim run per mode on the range |
| G22 | Fuzing and arming time; the LOW cue; a bomb released below its arming height does not burst. **Built 18 Nov** | S | new | Rust: a release at 150 ft shows LOW and the bomb is a dud |
| G24 | SMS profiles PROF1 / PROF2. **Built 17 Nov (slice 4)** | S | extend | `tests/godot/test_f16_mfd.gd` |
| G25 | SMS A-G submode menu (CCIP / CCRP / DTOS / LADD / MAN). **The menu built 17 Nov (slice 4)** with the submodes the release has (CCIP, PRE / VIS); G21 added its modes to it (18 Nov) | S | extend (with G21) | as G21 |
| G26 | SRM cage / uncage, SPOT / SCAN. **Built 18 Nov** ([weapons.md](weapons.md) §8.1) | S | extend (`sight.rs`) | Rust: caged, the seeker holds the boresight; uncaged it tracks |
| G27 | Post-launch cues: time to active and to impact on the HUD and the FCR, the missile's target marked on the FCR (the real FCR marks the target, not the missile: the DCS guide[^dcs-f16]), the times from the existing shared missile model. **Built 18 Nov** ([weapons.md](weapons.md) §8.2) | S | extend | Rust snapshot of the HUD after a launch |

## 6. Build order

Each slice ends playable and testable, merges once, and is shown to the user with pictures before the merge
(nothing visible ships unapproved). The rule that holds: reborn's logic is reused through `shared/` and
`crates/`, never its 1998 data formats or looks; game logic goes in Rust; Godot wires and draws. Pictures are real
renders through `tools/godot_window.sh`, with every graphics setting on, from the cockpit and the outside.

| slice | scope | gaps | size | files | headless test | pictures |
|---|---|---|---|---|---|---|
| 0 Bugs | radar standby, break X and HUD parity, SPICE / GPS targets, gun flash | G1, G2, G4, G23 | M | `radar.rs`, `player_weapons.gd`, `gaaf.rs`, `real_hud/f16.rs`, `gps.rs`, `iaf-reborn/menu/tsd_gps.gd` moved into `shared/`, the sim's briefing | the tests in §5.1 | FCR at STBY on the ground; the HUD in reborn and the sim side by side; the briefing map with a PRE target; the flash from the cockpit |
| 1 Range (built 17 Nov) | targets for every later slice: the sim's own jets as drones and plain ground targets (§8.1; no threat records); the briefing's PRE target pick (built 19 Nov, A61) | G3 | M | `modern-iaf/data/missions/*_range.json`, `data/db/brains/`, the drone and target unit records, `sim.rs` (drones, brains), `training.rs` (kind `range`) | test_sim_range.gd | the range in the mission list, the drones on the radar and from the cockpit, the ground targets, the debrief after a kill |
| 2 Sufa radar A-A (built 17 Nov) | scan and bars, VSR, situation mode, ACM patterns with their HUD cues, cursor and TMS (keyboard keys first, §8.3), EXP, the CNTL page, NO RAD; G1's power-on STBY and weight on wheels | G5–G8 | L | `radar.rs`, `f16_mfd.rs` / `.gd`, `modern-iaf/data/keys.json` | modern-iaf/tests/test_sim_fcr.gd: each mode finds, bugs and locks a range target | the FCR in each mode with targets |
| 3 Sufa radar A-G (built 17 Nov) | GM DBS / FZ / SP / CZ, the ground cursor, designation and FTT, SAR patch, SEA, AGR; a towed hulk and a barge on the range | G9–G12 (AGR) | M–L | `radar.rs`, `heights.rs`, `f16_mfd.gd` | the same test, A-G part | GM, DBS, SAR and SEA pictures |
| 4 Sufa MFDs (built 17 Nov) | SOI and DMS (keys, §8.3), HSD CNTL / bullseye, SMS profiles and submode menu, the Litening pod, TGP and the GBU-10 / 12 / 16 (§8.2) | G8 (DMS), G14, G15, G24, G25 | M | `f16_mfd.rs` / `.gd`, the sim's pod and laser bomb records | `tests/godot/test_f16_mfd.gd`, a sim TGP run | each format, both MFDs |
| 5 Sufa rest | DGFT, VVI, ALIGN / RDY, DED pages, TACAN, MAW, CMS programs, AIFF, data link, AWACS | G13, G17–G20, G28–G31 | L (two merges: HUD / nav first, EW / IFF / link second) | `master.rs`, `real_hud/f16.rs`, `start.rs`, `rwr.rs`, `fctrl.rs`, `cockpit3d_display.gd` | Rust tests per gap; a sim run per merge | HUD in DGFT, the DED pages, the MAW cue, AIFF symbols |
| 6 Barak (built 17 Nov) | its rows of §3 as today's upgraded jet (§8.4), with the Litening pod and laser bombs (§8.2) | B1–B11 | S | data and switches on `Settings.airframe` | the Sufa's tests with the Barak | the Barak's MFDs and HUD |
| 7 Adir (parts A and B built 17 Nov; part C, the PCD and the stores, 19 Nov: P1, P3, P4, P6–P11, S13, S15, N8; part D the DAS picture on the PCD and in the helmet (P9, G35) and part E the FLC (P12), 19 Nov; part F, the per-bomb PRE pick (S14, G4), built 19 Nov after A61) | SRCH / ASR with the SAR picture, combat ID, TWD with emitters, WPN-A / WPN-S, CNI, portal management (widen a portal over its half, enlarge it over its windows, the bar's SWAP, the 5 preset layouts; the default split is in since 2026-11-17), HOTAS cursor (keys, §8.3), GCAS mark, DAS warning, the SPICE 1000 (§8.6); last and low priority a simple DAS camera picture (§8.5); no electronic attack | A1–A7, P2, P5, P7–P12, H8, E5 | L (two merges: radar and PCD first, DAS second) | `pcd.gd`, `pcd_formats.gd`, `radar.rs`, `real_hud/f35.rs` | a PCD sim test against range targets | each portal format; the helmet with the GCAS mark |
| 8 Missiles (built 18 Nov) | the employment flow on all three jets against range targets: select, uncage, lock, SHOOT, launch, post-launch cues, the F-35's bay; values from the existing shared model | G26, G27 | M | `sight.rs`, `missile.rs` (cues only), `real_hud/f16.rs`, `real_hud/f35.rs` | new test_sim_missiles.gd: each jet kills an air target with each of its missiles | the HUD and FCR at SHOOT and after launch |
| 9 Bombs (built 18 Nov; the per-bomb PRE pick on the briefing built 19 Nov, G4) | release modes, fuzing and LOW, the PRE target UI per bomb, the laser path | G21, G22, G25 | L (two merges: CCRP / DTOS first, LADD / MAN / fuzing second) | `release.rs`, `bombs.rs`, `real_hud/f16.rs`, `f16_mfd.gd` | new test_sim_bombs.gd: each mode hits a range target within the bomb's spread | each mode's HUD cue through the release |

Slice 0 goes first by the standing rule that open bugs take every slot. Its GPS target fix needs a target to test
against; until slice 1 lands, its test places a ground unit in the test itself, as `tests/godot/test_modern_weapons.gd`
does.

## 7. Parked: real missile performance

A safety check stopped the rows on real missile performance. They stay parked: no research, design or plan here.
The missiles fly the existing shared model and data, which the user called good enough for gameplay. Parked rows:
- motors (thrust, burn time, impulse);
- range envelopes (Rmax, Rmin, no-escape zones) from real data;
- guidance laws, seeker acquisition and tracking behaviour, datalink mid-course updates;
- fuzing and warhead lethality of missiles;
- countermeasure effectiveness against seekers.

In scope and planned above: bomb ballistics and release computation (G21, G22), the GPS bombs' targeting (G4), and
every cue, display and control the employment flow needs, driven by the existing model's numbers (G26, G27).

## 8. Decisions (17 November 2026)

The user answered the six open questions on 17 November. His words in quotes; the orchestrator's reading after each.

1. **Targets for the range:** "ok". The sim's own jets fly as drones, with plain ground targets, first. The draft
   threat records stay unapproved; slice 1 does not need them.
2. **Targeting pod and laser bombs on the F-16s:** "yes". The Litening pod and the GBU-10 / 12 / 16 go on the Sufa
   and the Barak, with the TGP format and the laser path that reborn has.
3. **HOTAS functions:** "yes, and I don't have hotas". Every HOTAS function (TMS, DMS, cursor, uncage, DGFT and the
   rest) gets a keyboard key beside the existing keys. The keyboard is the first-class input; a joystick button is
   optional and never the only way.
4. **Which Barak:** "yes". Today's upgraded jet (the sim is set in 2026), not the Block 40 as delivered.
5. **The F-35I's DAS picture and electronic attack:** "yes, less in priority". A simple DAS camera picture, at low
   priority, after the rest of the Adir's slice. Orchestrator's reading: electronic attack stays out; it also falls
   under the parked countermeasure-effectiveness rows (§7).
6. **The F-35I's SPICE 1000:** "yes". It goes on the Adir's list; carriage as announced in 2026[^twz-spice]
   (integration announced; the stations and the bay or external carriage inferred until a source shows them).

[^barak-hm]: Hamichlol, "ג'נרל דיינמיקס F-16 פייטינג פלקון" (all the Baraks upgraded to "Barak 2020", with the Sufa's
    avionic systems installed), an encyclopedia, secondary:
    https://www.hamichlol.org.il/F-16_%D7%A4%D7%99%D7%99%D7%98%D7%99%D7%A0%D7%92_%D7%A4%D7%90%D7%9C%D7%A7%D7%95%D7%9F
[^barak-upi]: UPI, "Israel fears F-35 delay, upgrades F-16s", 12 December 2011 (new avionics from 2010, the flight
    control system and the central display unit, new high-resolution screens, an Elbit helmet system):
    https://www.upi.com/Business_News/Security-Industry/2011/12/12/Israel-fears-F-35-delay-upgrades-F-16s/UPI-11121323708656/
[^barak-fg]: FlightGlobal, "Israel completes F-16 Barak upgrade", 5 November 2014 (new head-up display and digital
    debriefing systems; through a search engine's quote, the page is paywalled: second-hand):
    https://www.flightglobal.com/israel-completes-f-16-barak-upgrade/115034.article
[^barak-dn]: defence-network.com, "Israel rüstet F-16C/D mit modernster Schutz- und Avioniktechnik auf", 25 September
    2025 (proposed: new EW, infrared missile warning and launch detection, better dispensers and displays); All Israel
    News, 15 September 2025 (the upgrade under consideration):
    https://defence-network.com/israel-ruestet-f-16c-d-mit-modernster-technik/,
    https://allisraelnews.com/israel-plans-to-upgrade-its-aging-f-16-fleet-after-excellent-performance-in-iran-war
[^dash34]: T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997:
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^mlu1]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998):
    https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^dcs-f16]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), a simulator manual of a Block 50 M4
    tape: https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
[^dash34gaaf]: T.O. GR1F-16CJ-34-1-1, pp. 1-313..1-315 "Ground Avoidance Advisory Function (GAAF)" and fig. 1-212,
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^dash34ccip]: T.O. GR1F-16CJ-34-1-1, pp. 1-429..1-430 "CCIP Visual Submode" and fig. 1-283,
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^sufa-at]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel": https://www.airforce-technology.com/projects/f-16i-soufa/
[^sufa-lm-radar]: Lockheed Martin, "Performance Flight Testing of Updated Radar Under Way for Lockheed Martin F-16",
    25 June 2002:
    https://news.lockheedmartin.com/2002-06-25-Performance-Flight-Testing-of-Updated-Radar-Under-Way-for-Lockheed-Martin-F-16-New-Technology-Expected-to-Significantly-Increase-Radar-Performance
[^sufa-dash4]: Defense Update, "Helmet Mounted Display and Sight Systems" (DASH IV in the F-16I):
    https://defense-update.com/?p=24924
[^sufa-janes]: Janes, "Elbit Systems to equip Israel's F-16Is with self-protection suite", 27 January 2025:
    https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite
[^sufa-periscope]: Military Periscope, "Advanced Self-Protection System (ASPS)":
    https://www.militaryperiscope.com/weapons/electronics/electronic-warfare/advanced-self-protection/overview/
[^sufa-spice]: Wikipedia, "Spice (bomb)": https://en.wikipedia.org/wiki/Spice_(bomb)
[^sufa-python]: Wikipedia, "Python (missile)", Python-5: https://en.wikipedia.org/wiki/Python_(missile)
[^wow]: Simulator forums, secondary: DCS forum, "Is the radar bugged on ground again",
    https://forum.dcs.world/topic/183966-is-the-radar-bugged-on-ground-again/; Falcon BMS forum, "FCR Manual DRAFT",
    https://forum.falcon-bms.com/post/160194 (NO RAD with weight on wheels: the posters disagree)
[^apg81]: Wikipedia, "AN/APG-81" (air-to-air modes, SAR mapping, multiple GMTI and track, combat identification,
    electronic protection, attack and support): https://en.wikipedia.org/wiki/AN/APG-81
[^das]: Wikipedia, "AN/AAQ-37" (missile detection and tracking, aircraft tracking and IRST, imagery for the helmet):
    https://en.wikipedia.org/wiki/AN/AAQ-37
[^afi35]: AFI 11-2F-35A Volume 3, "F-35A Operations Procedures", 7 June 2012, §3.19.1.1 (with the helmet the pilot
    picks the DAS's 360-degree infrared video or the near-infrared night vision camera); its cover: no releasability
    restrictions.
[^baseline]: SLDinfo, "The Baseline F-35" report (2012):
    https://www.sldinfo.com/wp-content/uploads/2012/05/The-Baseline-F-35-Report.pdf
[^collins]: Collins Aerospace, F-35 Gen III HMDS datasheet: https://prd-sc102-cdn.rtx.com/-/media/ca/f/f35/jsf-f35-datasheet.pdf
[^codeone]: Code One, J. Kent, "The New Front Office" (2006): https://www.codeonemagazine.com/u2_article.html?item_id=35
[^sld-cockpit]: SLDinfo, "The F-35 Cockpit: Enabling the Pilot as a Tactical Decision Maker" (2012), with LM's slides:
    https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/
[^lm-slides]: Lockheed Martin, "The F-35 Cockpit" slides (c. 2012): http://www.slideshare.net/robbinlaird/the-f35-cockpit/download
[^ife]: IndiaFoxtEcho, *F-35 Lightning II for Microsoft Flight Simulator, User Manual* v1.2.2 (2023), a simulator
    manual: https://orbx-user-guides.storage.googleapis.com/indiafoxtecho-f35-msfs-user-guide-3475b3.pdf
[^f16net-pages]: f-16.net forum, "MFD pages details" (2015): https://www.f-16.net/forum/viewtopic.php?t=27773
[^hotas]: US Air Force Test Center, solicitation FA2823-19-Q-0050 "F-35 HOTAS throttle and side stick", 25 Jul 2019,
    https://sam.gov/opp/6481842093ca4c35c0461b221c26cb0b/view
[^raaf39]: Australian Defence Magazine, "RAAF F-35As receive Small Diameter Bombs":
    https://australiandefence.com.au/news/raaf-f-35as-receive-small-diameter-bombs
[^twz-spice]: The War Zone, "Israel is bringing SPICE 1000 standoff weapon to the F-35":
    https://www.twz.com/air/israel-is-bringing-spice-1000-standoff-weapon-to-the-f-35
[^ayton]: Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net:
    https://www.f-16.net/forum/viewtopic.php?p=317934
