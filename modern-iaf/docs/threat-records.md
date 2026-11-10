# The threat set's records (drafts)

**Terms:** AAA = anti-aircraft artillery; ARH = active radar homing; DLZ = the launch zone (docs/weapons.md §11.2);
IR = infrared; MANPADS = man-portable air-defence system; SAM = surface-to-air missile; SARH = semi-active radar
homing; TEL / TELAR = launcher vehicle (with its own radar); "inferred" = our own reasoning; "open" = no source
found.

**Status: every record here is a draft, pending the user's decision** (item D2, 2026-11-03). The records hold the
threat set that [threats.md](threats.md) §6 recommends, in the unit and weapon formats of
[data-formats.md](data-formats.md) §3 and §4. They sit in `modern-iaf/data/db/drafts/`, which `iaf-sim db` does not
read, so nothing in `assets/` changes until the user approves them. Approving a record is one move and one edit
(data-formats.md §11).

Every figure in a record names its source (data-formats.md §1). The sources below are the records' own footnotes,
read on 2026-11-03.

## 1. Units

| unit (file) | role | class, type | key figures | sources | open | model source (threats.md §5) |
|---|---|---|---|---|---|---|
| MiG-29A 9.12 (`mig29a`) | fighter | `fighter`, 180 | Mach 2.3, 18,000 m, +9 g, 700 km combat range; GSh-30-1 150 rounds; 2 R-27R + 4 R-73 | [^w-mig29] | N019 range; chaff / flare counts (60 held); an own flight-model row; the stations | FlightGear "Mig-29" (GPL-2.0, "or later" open); Sketchfab "Mig 29 (9-13)" (CC BY) |
| F-14A (`f14a`) | interceptor | `fighter`, 1010 (ours) | Mach 2.34, 16,154 m, +7.5 g (all F-14D); M61A1 675 rounds; 4 AIM-54A | [^w-f14] | the F-14A (TF30) figures; AWG-9 range; range; Iran's AIM-54 stock; an own flight-model row; type 1010's place in the type-keyed tables (§4) | FlightGear "f-14b" (licence open); Sketchfab "Grumman F-14B Tomcat" (CC BY) |
| S-300PMU-2 TEL (`s300-tel`) | long-range SAM launcher | `radar_sam`, 310 | 3–200 km, 10 m–27 km; sensor 200 km held; four 48N6E2 | [^w-s300] | vehicle size (6 m held); missiles per TEL (4 inferred); the 30N6E2's range | Sketchfab "S-300 5P85 Launcher" (CC BY, a 9M83 to rework) |
| 30N6E2 (`s300-30n6e2`) | S-300 fire-control radar | `radar_sam`, 310 | I/J band, 6 targets; 200 km held | [^w-s300] | range; vehicle size | as the TEL; Commons "S-300PMU2" photos |
| 64N6E2 (`s300-64n6e2`) | S-300 search radar | `ground_radar`, −1 | — | [^w-s300] | range and band; vehicle size | Commons "S-300PMU2" photos |
| 3rd Khordad TELAR (`khordad3-telar`) | medium SAM launcher | `radar_sam`, 320 | 105 km, to 30 km; sensor 105 km held; three Ta'er-2B | [^w-3kh] | minimum range; X-band radar range; vehicle size | Sketchfab "Iranian Sevom Khordad SAM" (CC BY) |
| Bashir (`khordad3-bashir`) | 3rd Khordad search radar | `ground_radar`, −1 | S band, 350 km | [^w-3kh] | vehicle size | own modelling (no source found) |
| Tor-M1 (`tor-m1`) | short SAM TELAR | `radar_sam`, 330 | 1.5–12 km, to 6 km; search 25 km; eight 9M331 | [^w-tor] | — | Sketchfab "9K331 Tor-M1" (CC BY) |
| Kub 2P25 / Fater-1 (`kub-2p25`) | medium SAM launcher | `radar_sam`, 320 | 4–24 km, 50–14,000 m; sensor 75 km (the 1S91's); three 3M9 | [^w-kub] | vehicle size (3.5 m held) | Sketchfab "2K12 Kub" (CC BY), "2T7 transloader" (CC BY) |
| 1S91 (`kub-1s91`) | Kub radar | `radar_sam`, 320 | G/H band, 75 km | [^w-kub] | vehicle size | Sketchfab "1S91 Straight Flush radar" (CC BY) |
| ZSU-23-4 (`zsu-23-4`) | AAA | `aaa`, 360 | 2.5 km, 1.5 km up; Ku band 20 km; 2,000 rounds | [^w-zsu] | reaction time; the rate of fire (no field) | Sketchfab "Lowpoly Zsu-23-4" (CC BY) |
| Misagh-2 team (`misagh-2-team`) | MANPADS | `ir_sam`, −1 | 6 km, to 5 km; sensor 10 km (inferred); one missile | [^w-misagh] | a sourced sensor range | none found; Commons "Misagh-2" photos |

## 2. Weapons

| weapon (file) | kind, generation | key figures | power / blast | sources | open | model source |
|---|---|---|---|---|---|---|
| 48N6E2 (`48n6e2`) | `radar_sam`, 4 | 1,900 m/s, 3–200 km, 10 m–27 km, 1,900 kg, 180 kg warhead; 3 s between launches | 400 / 31 m | [^w-s300] | reaction time; g limit; the speed's reliability | as the TEL |
| Ta'er-2B (`taer-2b`) | `radar_sam`, 5 (ours) | 105 km, to 30 km; the 9M317's Mach 4, 715 kg and 70 kg warhead held | 400 / 22 m held | [^w-3kh], [^w-taer2], [^w-buk] | speed, weight, warhead, reaction time, launch interval, g limit | as the TELAR |
| 9M331 (`9m331`) | `radar_sam`, 3 | 850 m/s, 1.5–12 km, 6,000 m, 30 g, 167 kg, 15 kg warhead; reaction 6.5 s | 400 / 13 m | [^w-tor] | launch interval | as the TELAR |
| 3M9 (`3m9`) | `radar_sam`, 1 | Mach 2.8, 4–24 km, 50–14,000 m, 599 kg, 59 kg warhead; reaction 25 s | 400 / 21 m | [^w-kub] | launch interval; g limit | as the TEL |
| Misagh-2 (`misagh-2`) | `ir_sam`, 4 | 850 m/s, 6 km, 5 km, 12.74 kg, 1.42 kg warhead | 250 / 6 m | [^w-misagh] | reaction time; g limit; whether the weight holds the tube | none |
| R-73 (`r-73`) | `ir_missile`, 4 | Mach 2.5, 30 km, 105 kg, 7.4 kg warhead | 400 / 11 m | [^w-r73] | g limit | Sketchfab "R-73 Vympel" (CC BY) |
| R-27R (`r-27r`) | `semi_radar_missile`, 3 | Mach 4.5 (uncited), 73 km, 253 kg, 39 kg warhead | 400 / 18 m | [^w-r27] | a cited speed; g limit | none found |
| AIM-54A (`aim-54a`) | `radar_missile`, 2 | Mach 4.3, 135 km, 454 kg, 60 kg warhead | 400 / 21 m | [^w-aim54] | g limit | none found |
| 23 mm (`23mm`) | `gun`, 1 | 975 m/s; fires within 2.5 km | 100 / 5 m | [^w-zsu] | the round's drag | — |
| 30 mm (`30mm`) | `gun`, 2 | 860 m/s | 200 held / 5 m | [^w-gsh30] | a per-round damage figure | — |

## 3. The rules the drafts follow
These choices are ours (inferred); each record's `notes` repeats the one it uses.

- **Generation** keys a weapon's weapons.ibx section (`generation · 1000 + type`), and the compiler refuses two
  weapons on one section (data-formats.md §4). The drafts take the generation of their service year (weapons.ibx's
  3 = 1983–1995, 4 = from 1995) where that section is free. Three take another:
  - The R-73 (in service 1984) takes 4, since the AIM-9M holds 3570.
  - The Ta'er-2B takes 5 (ours), since the 48N6E2 holds 4630.
  - The guns take 1 (23 mm) and 2 (30 mm) beside the 20 mm's 0.
  A SAM's or gun's generation keys nothing else. The player's IR seeker reads a missile's generation (docs/weapons.md
  §5.1), so the R-73 would get generation 4's 70° cone if the player ever carried it.
- **Motion:** a = 120 m/s² (the AIM-9M record's) and β = a / the top speed. Every drafted missile holds `burn`, so
  `missile.rs` takes its launch zone from the distance the motion really travels, as with Weapon data Real
  (docs/real-weapons.md §2). The burn:
  - a SAM's gives a launch zone from rest equal to its published range, since a site fires from its pose at speed 0
    (docs/ai.md §14). The drafts test checks each zone within 2 % of `range_km`.
  - an air-to-air missile's flies its published range from 250 m/s before its flight ends 6 s after the burn
    (`missile.rs real_burn`, the AIM-9M's rule).
- **Reaction and launch interval:** weapons.ibx's `_reactionTime` and `_fireReleaseInterval` (the ground units'
  first shot and the time between shots, `combat.gd`), in a SAM's motion where a source gives one (the middle of a
  range). Where none does, the reader's defaults hold (10 s and 0.5 s), and the notes say "open".
- **Power:** 400, so one hit destroys a fighter of strength 300, as the AIM-9M. The Misagh-2 gets 250, so one hit
  damages and two destroy (a 1.42 kg warhead).
- **Blast edge** (`blast_m`): no lethal radius is published for these missiles. The edge is the AIM-9A / B's 9 m for a
  4.5 kg warhead[^ds-aim9] times the cube root of the warhead mass ratio (blast scaling).
- **Strength:** fighters 300 (our damage scale, data-formats.md §6). Every vehicle and radar is held at 300 too,
  until D2 calibrates the scale for ground units. The MANPADS team has 100 (one 20 mm hit).
- **Sensor reach:** the unit's `radar_km`, compiled into its Objects row, which the AI takes before the type code's
  range (docs/ai.md §14). A launcher holds its battery's radar reach: the 1S91's 75 km for the Kub; for the S-300 and
  the 3rd Khordad the radar's range is open and the missile's range is held.
- **Type codes:** the shared code keys the RWR symbol and the SPO-15 lamp on the type (docs/rwr.md). The drafts take
  the 1998 game's code of the closest system:
  - SA-5 310 for the S-300;
  - SA-6 320 for the Kub and the 3rd Khordad;
  - SA-8 330 for the Tor;
  - 360 for the ZSU;
  - −1 for the search radars and the MANPADS (no radar glyph).

  A battery's radars share its launchers' code. The HARM sensor and Extras "RWR: Real" find a class-8 radar by
  "RADAR" in its placed name (`harm.rs` `radar_class`, docs/rwr.md §7), so a mission names the 30N6E2 and 1S91
  sites with it and the launchers without it, so one battery shows one symbol.
- **What the records hold:** our own figures, from the sources above, and the 1998 game's type codes for the RWR
  symbol and the type-keyed tables (threats.md's licence rule keeps every figure public).

## 4. What is left
- **The user's decision:** approve, change or drop each record (data-formats.md §11).
- **Open figures:** the list per record above, and threats.md §6's open list (every g limit, the 3rd Khordad
  missile's speed, the S-300's reaction time, the F-14A's TF30 figures, the AWG-9 and N019 ranges).
- **Not taken by any reader yet:** the rate of fire (no field: the ZSU's stays in `notes`), and the figures
  `range_km` … `warhead_kg` other than `radar_km`, which are checked for sources only.
- **Type 1010 (the F-14A):** the type-keyed tables have no row for it. An approved F-14A would have no RWR symbol
  (`cockpit.gd` `RWR_GLYPH`: aircraft 100–200), no SPO-15 lamp (`rwr.rs` `spo15_type`: 100–210), and no flight-model
  row, so it could not fly. Either it takes a 1998 code in 100–200 (the RWR would then show that jet's symbol) or
  these tables get a row for 1010 (open, the user decides).
- **Models:** none yet. Each record's `model` is empty. The model sources are in §1 and threats.md §5, and the
  FlightGear licences are open.
- **Flight models:** the MiG-29 and the F-14A need own rows in the sim's `bd.ibx` (as item C1's) before a mission can fly them.
- **Missions:** red flights (`set_red_flight`) and SAM sites placed from these units come with the combat missions
  (a radar site's name holds "RADAR", §3).

[^w-s300]: Wikipedia, "S-300 missile system", https://en.wikipedia.org/wiki/S-300_missile_system (PMU-2 range, altitude, radars, launch interval; the comparison table's missile mass and 180 kg warhead).
[^w-3kh]: Wikipedia, "Sevom Khordad", https://en.wikipedia.org/wiki/Sevom_Khordad (TELAR and Bashir radars; Ta'er-2B 50–105 km, 25–30 km; 3 per TELAR).
[^w-taer2]: Wikipedia, "Taer 2", https://en.wikipedia.org/wiki/Taer_2 (50 km, ceiling 25–27 km, citing Deagel).
[^w-tor]: Wikipedia, "Tor missile system", https://en.wikipedia.org/wiki/Tor_missile_system (TELAR 7.5 m; radars; 9M331 167 kg, 15 kg warhead, 850 m/s, 30 g).
[^w-kub]: Wikipedia, "2K12 Kub", https://en.wikipedia.org/wiki/2K12_Kub (1S91; 3M9 599 kg, 59 kg warhead, Mach 2.8, 4–24 km, 50–14,000 m).
[^w-zsu]: Wikipedia, "ZSU-23-4 Shilka", https://en.wikipedia.org/wiki/ZSU-23-4_Shilka (6.535 m; RPK-2; 2,000 rounds; 970–980 m/s; ranges).
[^w-misagh]: Wikipedia, "Misagh-2", https://en.wikipedia.org/wiki/Misagh-2 (12.74 kg, 1.42 kg HE, 850 m/s, 6 km, 5 km).
[^w-mig29]: Wikipedia, "Mikoyan MiG-29", https://en.wikipedia.org/wiki/Mikoyan_MiG-29 (span 11.36 m, Mach 2.3+, 18,000 m, +9 g, combat range, GSh-30-1 150 rounds).
[^w-gsh30]: Wikipedia, "Gryazev-Shipunov GSh-30-1", https://en.wikipedia.org/wiki/Gryazev-Shipunov_GSh-30-1 (860 m/s).
[^w-f14]: Wikipedia, "Grumman F-14 Tomcat", https://en.wikipedia.org/wiki/Grumman_F-14_Tomcat (F-14D specifications; span 19.54 m unswept; M61A1 675 rounds).
[^w-r73]: Wikipedia, "R-73 (missile)", https://en.wikipedia.org/wiki/R-73_(missile) (105 kg, 7.4 kg warhead, Mach 2.5, 30 km).
[^w-r27]: Wikipedia, "R-27 (air-to-air missile)", https://en.wikipedia.org/wiki/R-27_(air-to-air_missile) (253 kg, 39 kg warhead, R-27R 73 km, Mach 4.5–5.8 "citation needed").
[^w-aim54]: Wikipedia, "AIM-54 Phoenix", https://en.wikipedia.org/wiki/AIM-54_Phoenix (A/B 135 km, Mach 4.3, 1,000–1,040 lb, 133 lb warhead).
[^w-buk]: Wikipedia, "Buk missile system", https://en.wikipedia.org/wiki/Buk_missile_system (9M317: 715 kg, 70 kg warhead, Mach 4; the 3rd Khordad is compared with the Buk family).
[^ds-aim9]: designation-systems.net, "Raytheon AIM-9 Sidewinder", https://www.designation-systems.net/dusrm/m-9.html (AIM-9A / B effective kill radius about 9 m).
