# Manual audit — the original manual against our port

This page compares the original printed manual of Jane's IAF with iaf-reborn as of 2026-10-17. It lists what the
manual describes that we lack, what we do differently, facts that only the manual gives, and open questions in our
docs that the manual answers. Rows are ranked by player impact, highest first.

**Sources**
- **EN**: the English electronic manual, `assets/manual_en/iaf_manual_en.pdf` (124 pages). Cited by the manual's
  own page numbers, e.g. "EN 4.12". It refers to a separate keyboard card.
- **HE**: the Hebrew printed manual, 72 page scans in `assets/manual_he/`. Cited by scan number, e.g. "HE p40". Its
  pages 8–11 hold the only keyboard chart. Pages 12 and 70 are blank. The scans skip chapter 5 (aircraft); EN has it.
- **The exe** (v1.1) is the authority when the manual and the exe disagree. "Exe" below says which side it takes.

**Terms**: AA / AG = air-to-air / air-to-ground; TSD = tactical situation display (the map screen, also an MFD page);
MFD = multi-function display; HUD = head-up display; TD box = target designation box on the HUD; RWR = radar
warning receiver; DASH = the helmet sight; NM = nautical miles; MP = multiplayer.

Both assets folders are git-ignored; the scans and the PDF come from the user's own copy.

## 1. Missing: the manual describes it, we lack it

Actionable rows come first. Features parked by user decision (docs/status.md "Decisions") follow, whatever
their size.

| # | Manual | What the manual says | What we do | Exe | Suggested action |
|---|---|---|---|---|---|
| 1 | EN 3.1, EN 3.3, HE p23, HE p25 | Esc in flight opens the TSD; FLY there moves you into another formation's jet at any time ("often vital"). A downed formation leaves the map; a formation without its leader puts you in the wingman's seat. Put your jet on autopilot first. | FLY makes the selected flight's current leader your jet, of any flyable type (cockpit, model, weapons with its stores left); the old jet flies on under its brain (docs/views.md §1). | Agrees with the manual: `FUN_005045b0` → `FUN_004d31f0` → `FUN_004d3250` makes the current leader (member 1 once member 0 is down) the player and gives the old jet to its brain (`FUN_004a8e70`). The manual's autopilot advice has no code behind it. | **Done** (2026-10-18). |
| 2 | EN 4.1, EN 6.1, HE p10, HE p31 | F12 toggles **I mode** in the forward, back and padlock views: lines point to every aircraft in visual range, blue for friends and red for enemies. | **Done** (2026-10-18): F12 toggles I-mode as the exe does (docs/cockpit.md "I-mode"); the flight-info line stays on Ctrl+F12. | Disagrees with the manual in detail: marks only for the aircraft **out of view** within √3 · (9270 m + size) ≈ 16 km, at most 6 (the farthest), with no line-of-sight test; the line is in the HUD colour and only the square at its end is blue / red; an aircraft behind is mirrored through the centre (`FUN_0045c530`, `FUN_0052fcc0`). | None. |
| 3 | EN 4.12, HE p39 | U puts the RWR page on an MFD. | **Done** (2026-10-19): U puts the RWR page on an MFD as T / D do theirs (docs/mfd.md §5). | Live: U sends SET_MFD_SCREEN(7), the same path as T / I / D (docs/controls.md §4). | None. |
| 4 | EN 3.1, EN 3.3, HE p23 | **VISIT** puts the camera near any unit (enemy too) and follows it; you cannot control it; it works only after the mission has started; Esc returns. Double-clicking a unit you cannot fly, or any ground unit, visits it. | VISIT puts the camera on the selected unit in the radar-target view; a double-click visits any unit that does not fly (docs/views.md §1). | Agrees: `FUN_004d3450` sets the radar-target view (`FUN_00580f50`, type 9) on the unit; the player keeps flying the own jet; Esc gives the FlyTSD. | **Done** (2026-10-18). |
| 5 | EN 3.3, HE p24 | Right-click and drag on the TSD map measures the distance between two points. | Right-drag draws the ruler, before and in flight (docs/front-end.md §8). | Agrees, with details the manual lacks: the line and arrow are white, only the texts `"%.2f NM"` and `"%03d T"` are red; the ruler stays until the next right press. | **Done** (2026-10-18). |
| 6 | EN 4.6, HE p35 | In SRM mode the right HUD column shows the aspect angle, or **AUD** when the heat seeker holds the target (the missile tone). | The row is left empty (docs/deviations.md row "HUD text rows of the weapon timers"). | Writes "AUD" in HUD mode 1 without a radar lock (S+0x3a4, docs/cockpit.md "Text block"). | Trace S+0x3a4 and draw "AUD" in that row. |
| 7 | EN 3.9 | Ctrl+P pauses on the in-flight TSD as well. | Ctrl+P on the FlyTSD pauses with the dithered snapshot and the blinking "II  PAUSE" (docs/views.md §1). | Agrees: `FUN_004edbc0` / `FUN_004ede30`; only Ctrl+P resumes it. | **Done** (2026-10-18). |
| 8 | EN 3.1, HE p23 | On the TSD the arrow keys scroll the map and Numpad + / − zoom it. | The arrows scroll 5 map units, Page Up / Down page, Numpad + / − zoom (docs/front-end.md §8). | Agrees: WM_KEYDOWN `5023e0`. Insert also zooms out (a character code '−' read as a virtual key). | **Done** (2026-10-18). |
| 9 | EN 2.5–2.6, HE p17–18 | **Mission Creator**: name, Blue / Red forces, four formations of 0–2 jets each (Alpha, Bravo friendly; Charlie, Delta enemy), plane type incl. MiG-23 / MiG-29, AI type, base, time, start altitude, weapons, victory rule, target, SAMs 0–3, AAA 0–3, notes; RANDOM, LOAD, SAVE, FLY. | The Main menu button opens an empty screen; parked (docs/status.md "Decisions": "Mission Creator much later"). | Screen 0x14; missions 0x213 / 0x29a. | Keep parked. §3 lists the parameters for when it is built. |
| 10 | EN 7.1–7.7, HE p57–63 | **Multiplayer** (2–8 players, IPX or TCP/IP): special missions, campaign missions, custom missions, All-Out War; chat with `~` and its modifiers, canned messages on F1–F12; re-entry rules; MP debrief names the winning side. | Not started; parked (docs/status.md "Open gaps": missions 511–516, 666, 777). The chat keys have no command. | v1.1 rules recorded in docs/front-end.md §17. | Keep parked. §3 lists the manual's rules. |
| 11 | EN 6.1 | The radar controller (AWACS) calls out new contacts with bearing and range. | Not built (docs/radio.md, docs/status.md "Radio"). | Has the calls. | Already on the open list; no new action. |

## 2. Different: we behave differently from the manual

| # | Manual | What the manual says | What we do | Exe | Suggested action |
|---|---|---|---|---|---|
| 1 | EN 4.12–4.13, HE p40 | **M** sets up the whole cockpit per mode and per MFD count. NAV: radar / TSD / NAV pages (3 MFDs), radar / TSD (2), TSD (1). AA: radar / TSD / RWR (3), radar / TSD (2), radar (1). AG: AG radar / TSD / stores (3), AG radar / stores (2), stores (1). It also sets the radar. | M changes the master mode, sets every MFD's page by the MFD count and switches the radar A-A / A-G (`player_weapons.gd` `master_key`, `IafModes.m_key_pages` / `m_key_radar`; docs/mfd.md §5). | **Agrees with the manual.** Case 0x63 of `FUN_0044a240` writes all three MFD pages `ctl+0x68 / 0x6c / 0x70` (the Left / Right / Middle pages that `FUN_00448120` initialises) by the MFD count and the panel-RWR flag, and calls `FUN_004ad8f0` on the radar. | Done (2026-10-19). |
| 2 | EN 3.6, HE p27 | Arming works per formation; both jets of a formation carry the same load. | Only the player's jet gets the Arming load; AI jets carry the mission's load (docs/deviations.md row "Arming loads on the aircraft"). | **Agrees with the manual**: both members, and every flight on Yes / DEFAULT. | Apply the Arming tables to the AI jets (`combat.gd` `_setup_aircraft`). |
| 3 | EN 4.20 | In MAP mode, a ground target designated on the MFD (click or Enter) gets the AG TD box on the HUD. | The HUD draws the TD box with a lock only (docs/radar.md "The designated point"); Enter and a click on a blip lock it, so the box shows then. | Calls the box with a designation too, but places it at `ctl+0xdc`, which docs/radar.md calls a different value from the designated point. Agreement with the manual is open. | Trace `ctl+0xdc`; change ours only if it is the designated point. |
| 4 | EN 3.1, EN 3.3, HE p23, HE p25 | In flight the TSD shows the live battle: current positions, downed formations removed, their buttons closed. | The FlyTSD shows the live battle: current positions and headings, the clock now, dead units and formations gone, their buttons disabled; units the radar records appear (docs/front-end.md §8.1). | Agrees: the table is rebuilt from the spawned objects on every paint (`FUN_00517cd0` → `FUN_004d2900`). | **Done** (2026-10-18). |
| 5 | EN 3.3 | Waypoints can be dragged before take-off only. | The FlyTSD leaves waypoints where they are (docs/front-end.md §8.1 "Waypoints"). | Agrees: WM_MOUSEMOVE `501cb0` moves the waypoint only before the flight (`+0x54 == 0`). | **Done** (2026-10-18). |
| 6 | EN 2.8 | The TERRAIN slider sets the ground resolution. | It sets terrain detail without the resolution drop or view-distance change (docs/deviations.md §1). | Lowers the resolution of levels 1–3 and the view distance. | Intended deviation; keep. |
| 7 | EN 4.1, HE p31 | F5 looks at the incoming missile first, else the worst threat. | F5 looks at the RWR's nearest listed emitter (docs/views.md §4.2, docs/rwr.md §5). | Agrees with us. | Keep. |
| 8 | EN 4.1, HE p31 | F9 is a fly-by from a stationary camera. | F9 starts at an offset point and glides into the chase view. | Agrees with us. | Keep. |
| 9 | EN 4.12, HE p9 | I toggles the FLIR page. | I opens the FLIR page; a shown FLIR page ignores it (docs/mfd.md "FLIR (6), TV (5)"). | Agrees with us. | Keep. |
| 10 | EN 4.25, HE p50 | The FLIR pod looks from +15° to −105° in elevation and ±60° in azimuth. | +30° / −80°, ±45°. | Agrees with us (`FUN_005817a0`, class 0x1a). | Keep. |
| 11 | EN 4.13, HE p41, HE p54 | Maverick: EN says Space locks and Backspace releases; HE says Enter locks and Space fires. | Releasing the Ctrl+arrow slew locks the camera; Space fires (docs/mfd.md "FLIR (6), TV (5)"). | Agrees with us. | Keep; the two manuals contradict each other. |
| 12 | EN 4.30, HE p54 | The guided bomb's first stage reads "TRN". | "TRA" (transit), then "TER". | Agrees with us. | Keep. |
| 13 | EN 3.4, EN 4.26 | Python 3 tracks 40° off boresight; Python 4 90° (EN 3.4) or 80° (EN 4.26). | Seeker cones 35° and 70° (docs/weapons.md §5.4). | Agrees with us. | Keep; the Real weapon data may cite the manual. |
| 14 | EN 4.24 | The RWR shows up to ten threats. | Up to 15 slots. | Agrees with us. | Keep. |
| 15 | EN 4.20 | Radar ranges are 5, 10, 20, 40 and 80 NM. | Up to 160 NM where the jet's table allows it. | Agrees with us. | Keep. |
| 16 | EN 4.23 | No weapon fires with the gear down. | The gun fires with the gear handle down when Safety is off (Shift+S). | Agrees with us (docs/controls.md §4). | Keep. |
| 17 | EN 4.32, HE p55 | ECM confuses radars trying to lock and enlarges incoming missiles' steering errors. | Each radar missile chasing the player loses guidance with chance 0.6 (docs/weapons.md "ECM"). | Agrees with us. | Keep. |
| 18 | HE p8 | Key 9 adds 5 % thrust; key 0 takes 5 % off. | 9 takes 5 % off, 0 adds 5 % (record 15 "RPM - 5" on 9). | Agrees with us (keys.trx and the key table). | Keep; the HE chart has them swapped. |
| 19 | HE p9 | Alt+T opens the tactical map. | T opens the TSD page; Alt+T orders the wingman into tactical formation. | Agrees with us; HE p11 itself lists Alt+T as the formation order. | Keep. |

## 3. Manual-only facts

Facts our docs lack that would help when building, testing or writing the pilot guides.

| # | Manual | Fact | Where it helps |
|---|---|---|---|
| 1 | EN 2.6, HE p18 | Mission Creator parameters: base Tel Nof / Ramat David / Ramon; time noon, dawn, sunset or night (HE: noon, dusk, night); start altitude 5,000 / 10,000 / 15,000 ft or the runway; weapons guns only, AA, or multipurpose; victory by kills or by target; target bunker, armoured column, radar station, terrorist camp or none; SAMs and AAA 0–3 each; at least one jet in Alpha. | Mission Creator, when built. |
| 2 | EN 7.6, HE p18, HE p62 | AI types for computer formations: Aces (AA), Bombers (AG), Defenders, Aggressors (search and intercept), Kamikaze (search ground targets). MP custom missions add re-entry count (0, 1, 2, 3, unlimited), wait time (0, 10, 20 s) and re-entry weapons (guns only, as at death, full reload). | Mission Creator and MP. |
| 3 | EN 7.4, HE p60–61 | Chat: `~` all, Alt+`~` friends, Shift+`~` enemies, Ctrl+`~` the target; Enter sends, Esc cancels. F1–F12 canned messages: Roger, Negative, Help, current target, Follow me, Break missile, Bugging out, Watch my back, Attack I'll cover, Stop shooting, I'd better fly civilian jets, a taunt. | MP chat. |
| 4 | EN 7.5–7.7 | Six special MP missions; every campaign mission can be flown in MP; a taken formation offers to join as wingman; All-Out War has no TSD; custom and All-Out War missions give no score. | MP. |
| 5 | EN 2.4, EN 2.6 | MiG-23 and MiG-29 are flyable in MP, in Mission Creator missions and in All-Out War. | docs/status.md says "AI-only, as in the original": true for single-player campaigns only. Fix that wording with the next status edit. |
| 6 | EN 4.29, EN 4.32 | Dive at 30–40°; pop up to about 10,000 ft over the target. LGB: radar-lock the target at about 15 NM, the FLIR slaves to it. Rockets: ripple 5–10. | Pilot guides, training checks. |
| 7 | EN 4.23, EN 4.3 | ILS works within 10 NM of the runway; land below 200 kt. | Matches the tower's 18,540 m (10 NM) range (docs/radio.md); pilot guides. |
| 8 | EN 4.9 | AA gun reticle range ring: a full circle is 2 NM, half is 1 NM, each mark 900 ft. | Check against the LCOS ring in docs/weapons.md. |
| 9 | EN 3.4–3.6 | Weapon notes: AIM-7 40 km, AMRAAM 50 km, Popeye 80 km, Python 3 40 g and 15 km, DEFA 1,300 rounds/min, M61 6,000 rounds/min, LAU-61 pods hold 25 rockets; TV pods are built into the jets that use them. EN names "CBU-93" where the game has CBU-97. | Real weapon data sources (docs/real-weapons.md). |
| 10 | EN 5.3–5.22 | Jane's data per jet (weights, thrust, fuel, speeds, ceilings, gun rounds: F-15 940, F-16 511, Kfir 140 per gun). | Cross-check docs/real-aircraft.md. |
| 11 | EN 5.3 | Panel clicks: gear handle, flaps, brakes, autopilot, ECM, the fire light (extinguisher) and master caution (resets it; no key). | Pilot guides; check that each click is wired (docs/cockpit.md "Panel lights"). |
| 12 | EN 2.4 | Historic campaigns and special MP missions are open from the start; Future campaigns unlock in order. | Matches docs/front-end.md §13.11. |
| 13 | EN 4.18, EN 4.26 | Double-clicking a TWS target gives STT. With DASH active, BORE locks the target you look at. | Not checked against our radar page and helmet code. |
| 14 | EN 4.1, EN 4.26 | Padlock and DASH show a "steer to target" arrow that shortens as the target nears the nose. | Not checked against the exe. Our HUD draws the target location line from the HUD centre (`hud.gd` `_draw_target_box`); confirm it is this arrow on the helmet display. |

## 4. UNCERTAIN items the manual resolves

These answers are now in the docs named in each row (2026-10-18), except row 3's HUD mode names, which
docs/cockpit.md already gives.

| # | Doc line | Manual | Answer |
|---|---|---|---|
| 1 | docs/mfd.md "TWS": hover text `"%02d" (altitude kft and +0x67c·10, UNCERTAIN which side)` | EN 4.17 | The cursor shows the target's altitude and Mach, so `+0x67c·10` is Mach × 10. |
| 2 | docs/mfd.md "RWR (7)": `0x168/0x17c/0x186→60 (ship? UNCERTAIN)` | EN 4.24, HE p49 | Row 60 of `rwrsymb.bmp` is the AAA icon (two chevrons). The manual shows ZSU-23 and AAA with that icon; the HARM page names type 360 "G" (Gun Dish). Rows 80–160 read 21, 23, 29, 25, 4, 15, 16, C, L in the bitmap. Kfir and Mirage share "C", as the exe's shared row 150 does. The manual lists Su-24 "24"; the game's row 110 is "25" (type 170, MiG-25). |
| 3 | docs/mfd.md "Open questions": `Names of master modes 1–6; RWR aircraft glyph identities` | EN 4.2, EN 4.3, EN 4.23, HE p48 | Glyphs: row 2. The manual names the HUD modes, not master modes 1–6, so that question stays open. HUD mode names: 0 NAV, 1 SRM, 2 MRM, 3 AA GUN, 4 STRF, 5 CCIP, 6 CCIP with the FLIR page, 7 TV, 8 HARM; Landing comes on with the gear down in NAV (which mode number it is stays open). |
| 4 | docs/mfd.md "TSD (3)": `type 5 (target? UNCERTAIN)` | EN 4.4, EN 4.15, EN 4.30 | Yes: the target waypoint. The NAV page names it "Target" and the HUD waypoint circle shows "T". |
| 5 | docs/mfd.md "HARM (10)": class 9 "I", class 0xb "R", 360 "G" (no names given) | EN 4.32, HE p55 | I = SA-13, R = ground radar, G = Gun Dish site (ZSU-23). |
| 6 | docs/views.md §1: `Visit … (FUN_004d3450, UNCERTAIN: a view on it)` | EN 3.1, HE p23 | A view on it: the camera follows the unit, no control, only after the mission starts, Esc returns. |
| 7 | docs/views.md §1: `Live unit positions on the FlyTSD … (UNCERTAIN what the original draws there)` | EN 3.1, EN 3.3, HE p25 | Live positions; downed formations vanish from the map and the formation buttons. |
| 8 | docs/front-end.md §8: `Dragging the map with Cur/move.cur and grab.cur pans it (UNCERTAIN)` and `This is the purpose of move.cur and grab.cur (UNCERTAIN)` | EN 3.3, HE p25 | Left-drag moves a friendly waypoint before take-off; the manual mentions no map drag. The exe loads the cursors for the TSD but never sets them there (WM_SETCURSOR `501c60`: the arrow); the Arming screen uses them. |
| 9 | docs/mfd.md "Reachability": `Whether a mission file can put the player in a MiG (Player1 type) is not verified - UNCERTAIN` | EN 2.4, EN 2.6 | The player can fly MiG-23 / MiG-29 in Mission Creator, MP and All-Out War missions. |
| 10 | docs/deviations.md row "HUD text rows": `mode 4's timer and AUD are not traced` | EN 4.6, HE p35 | AUD replaces the aspect angle when the heat seeker holds the target (the missile tone); it matches docs/cockpit.md's "mode 1 without a lock". The manual gives no timer for STRF. |
