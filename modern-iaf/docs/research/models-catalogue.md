# 3D models for targets and airbases — research catalogue

This page lists 3D models that Modern IAF could use for ground, sea and air targets and to fill its airbases with
shelters, hangars, vehicles and parked aircraft. It is research only: nothing here is implemented, and no model was
downloaded to write it. The user asked for it on 17 November 2026: "find models for targets etc, without implementing
them- sam, tanks, whatever might be useful" and "fill the base with hangers and building and other airplanes".
Research date: 17 November 2026.

**How to read the tables**
- **Licence:** as the source states it. "Ships" means the file may sit in this repository (GPL-3.0-or-later, the
  root `LICENSE`); "setup download" means it may not, so setup would fetch and convert it on the player's machine, as
  it does for the F-15 (`crates/iaf-tools/src/f15.rs`, GPL-2.0-only).
- **Format:** `.ac` is AC3D, FlightGear's format. The repo reads it in Rust (`crates/iaf-formats/src/ac3d.rs`, used by
  the F-15 and MiG-29 converters) and in Godot (`tools/stores/build.gd`). glTF / GLB is Godot's native format (the
  F-35I is a `.gltf`). OBJ and FBX open in Godot's importer, but no repo tool uses them yet (inferred).
- **Faces / size:** the listing's face count, and the download size the listing gives (Sketchfab: its glTF archive;
  FlightGear's model database: the sum of the model's files). "Unknown without download" where no listing says.
- **On disk:** whether the files are already on this machine, so no new download is needed.
- "Inferred" marks our own reasoning; "open" means no source was found.

Scope: what each object is, where its model comes from, and its licence. Performance and use of any weapon system are
out of scope (parked in this project).

## 1. What the sim has today

**Models in the repo** (credits: [docs/credits.md](../../../docs/credits.md) "Model credits"):

| what | file | source, licence |
|---|---|---|
| F-16D Barak, F-16I Sufa | `shared/extra/models/f16/` | FlightGear F-16 (NikolaiVChr/f16), GPL-2.0-or-later |
| 3D F-16 and F-35I cockpits, pilot | `shared/extra/models/cockpit3d/` | FlightGear F-16, GPL-2.0-or-later; F-35I cockpit our own |
| MiG-29 9.12 | `shared/extra/models/mig29/` | FlightGear MiG-29 9-12 (Mercenary-Mercury), GPL-3.0 |
| F-35I Adir | `shared/extra/planes/f35i/` | Sketchfab, andertan, CC BY 4.0 |
| F-15C Baz, F-15I Ra'am | made by setup into `assets/converted/` | FlightGear F-15 (Zaretto), GPL-2.0-only: setup download |
| 39 stores and pods | `shared/extra/models/stores/` | FlightGear F-16, MiG-21bis, MiG-29 9-12 (GPL); a few our own |

**Units** (`modern-iaf/data/db/units/`): the five flyable or drone jets (`f15c`, `f15i`, `f16d`, `f16i`, `f35i`,
`drone_f16`, `drone_f35`) and three range targets: `target_f16` and `target_mig29` (hulks drawn with our jet models)
and `target_barge`, whose note says "The repo holds no ship model, so the hulk is drawn on the water and the barge is
not drawn". No tank, truck, SAM vehicle, building or ship model exists.

**The bases** ([airbases.md](../airbases.md) §2, §9): Ramon, Hatzerim, Nevatim, Ramat David and Tel Nof. The airbases
step draws runways, taxiways, aprons and signs, and paves the shelters' pads. It places no building: the hangars and
shelters in the OSM data are outlines only, and the scenery step leaves the bases' footprints empty
([scenery.md](../scenery.md) §4, §9 "The bases' buildings"). The only aircraft on a base is the player's jet.

**The units the plan wants** ([threats.md](../threats.md) §2–§4, [threat-records.md](../threat-records.md) §1), as
unit types only: long-range SAM launcher, its search and fire-control radars (S-300PMU-2 family); medium SAM launcher
and search radar (3rd Khordad, 2K12 Kub / Fater-1 with the 1S91 radar); short-range SAM vehicle (Tor-M1); AAA vehicle
(ZSU-23-4); MANPADS team (Misagh-2); fighters MiG-29A, F-14A, F-4E; ballistic-missile launchers and their shelters;
rocket and drone launchers; parked aircraft and hardened shelters at enemy bases; tunnel shafts; ports, fuel and power
plants; fast-attack boats.

**Sources already fetched** (names only; nothing unpacked for this page):
- `~/.cache/fg-f16`: the FlightGear F-16 checkout (GPL-2.0-or-later, its `copyright.txt` covers every file). Besides
  the jet it holds `Models/Ramp/`: `chock.ac`, `chocks.ac`, `extinguisher.ac`, `fuel-truck_f600.ac`,
  `generic-trailer-GPU.ac` and their textures: base furniture already on disk.
- `assets/source/f15/`: the F-15's `f15c.ac`, `f15-interior-back.ac`, `f15c-interior-front.ac` and textures.
- `assets/source/mig29/`: `MiG-29.ac`, `fighter_pilot_proto.ac`, `K-36DM.ac` and textures.
- `assets/source/` also holds `dem`, `imagery`, `osm`, `ourairports`, `roads`, `scenery`: no 3D models.
- The MiG-21bis checkout the stores came from is not on disk (rebuilt from git when needed,
  [docs/aircraft-models.md](../../../docs/aircraft-models.md) §5.3).

## 2. Sources and their licences

| source | what it holds | licence as stated | in this repo |
|---|---|---|---|
| FlightGear scenery models database[^sm-api] | about 600 shared airport, military, vehicle and ship models, `.ac` with PNG textures, low poly | the submission form: "I release my contribution under the GNU GPL v2"[^sm-form] (no "or later": GPL-2.0-only, inferred) | setup download, as the F-15; credit each author |
| FGAddon (FlightGear's aircraft repository)[^fgaddon-svn] | full aircraft: C-130, KC-135, 707, CH-53E, UH-60, Apache, King Air, T-6 Texan II, Mi-24, F-4 … | per aircraft: a `COPYING` with the GPL 2 text, or a header; the repository's policy is GPLv2+ since August 2015 ([threats.md](../threats.md) `fg-addon`) | GPL-3.0-or-later or "or later" stated: ships; GPL v2 alone: setup download until the author confirms "or later" (the stance threats.md takes for the MiG-29 and F-4) |
| FlightGear F-16 `Models/Ramp/` (on disk) | chocks, extinguisher, F-600 fuel truck, trailer GPU | GPL-2.0-or-later (`copyright.txt`) | ships, as the F-16 does |
| OPRF assets (l0k1/oprf_assets)[^oprf] | SAM sites, AAA, radars, ships, depots, hangars, shelters, ground vehicles; 155 MB | no licence file; some `-set.xml` files carry a GPL-3.0-or-later header (© 2015 onox); the depot folders bundle other authors' FlightGear scenery models | excluded until its authors state a licence (§3) |
| Sketchfab, licence "CC Attribution"[^sf-cc] | single models, glTF archives | CC BY (Sketchfab's free CC licences are version 4.0, inferred from the F-35I's page) | ships with credit, as the F-35I; download needs a free Sketchfab account |
| Sketchfab, airmuseums.co.uk (user mgg8)[^mgg8] | about 240 aircraft, CC0 | "Free download under CC0 1.0 (public domain) … attribution is optional"; "Created in Blender with AI assistance … some details and markings are approximate"[^mgg8-c130] | ships; free account to download |
| Kenney, City Kit (Industrial)[^kenney] | low-poly factories and warehouses | "Creative Commons CC0" | ships |

How the repo handles share-alike and GPL today: it is GPL-3.0-or-later as a whole; GPL-2.0-or-later and GPL-3.0
models ship inside it under their own licence (each with a `SOURCES.md`); a GPL-2.0-only model never enters the repo,
setup downloads it at a pinned commit with checksums and converts it locally (`crates/iaf-tools/src/f15.rs`). CC BY
4.0 and CC BY-SA models ship with their credit (the F-35I and its badge). Every third-party model is credited in
[docs/credits.md](../../../docs/credits.md), on the setup wizard's Attributions page and in the credits roll.

## 3. The catalogue

### 3.1 Ground targets

| what it is | source (author) | licence | format | faces / size | quality from the listing | on disk |
|---|---|---|---|---|---|---|
| SA-2 launcher with missile (generic Cold War SAM launcher) | FlightGear models DB #2192 (Jack Mermod)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown without download / 2.4 MiB | detailed launcher, 1.2 MiB texture | no |
| SA-2 guidance van (generic radar van) | FlightGear models DB #2193 (Jack Mermod)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown / 1.6 MiB | trailer van | no |
| Rotating radar on a shelter, olive drab | FlightGear models DB #980 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown / 31 KiB | low poly | no |
| Humvee pickup, olive drab | FlightGear models DB #727 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown / 60 KiB | low poly | no |
| Generic small truck | FlightGear models DB #1626 (SAVAGE)[^sm-api] | GPL v2 (setup download) | `.ac` | unknown / 267 KiB | civilian | no |
| Earth-covered ammunition bunker | FlightGear models DB #851 (Jon Stockill)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown / 73 KiB | simple mound | no |
| Concrete army shelter | FlightGear models DB #4495 (Martin Herweg)[^sm-mil] | GPL v2 (setup download) | `.ac` | unknown / 118 KiB | simple | no |
| Storage tanks 10 / 20 / 30 m, sand; 50 m grey; 65 m hydrocarbon tank | FlightGear models DB #734–736 (Alexis Bory), #2617 (Thomas Grossberger), #7603 (Alex Hudghton)[^sm-api] | GPL v2 (setup download) | `.ac` | 2 KiB each; 88 KiB; 288 KiB | fuel depot pieces | no |
| 20 ft ISO container | FlightGear models DB #2527 (Frank Goeldner)[^sm-api] | GPL v2 (setup download) | `.ac` | 4 KiB | box | no |
| Truss bridge span, 48 m | FlightGear models DB #8554 (David Megginson)[^sm-api] | GPL v2 (setup download) | `.ac` | 104 KiB | steel truss | no |
| T-72 main battle tank, very low poly | Sketchfab, lebedeventerprise[^sf-t72a] | CC BY | glTF | 977 faces / 19 KB | far-view only, 64 px texture | no |
| T-72 main battle tank, "Low Poly … Game Ready" | Sketchfab, MrTheRich[^sf-t72b] | CC BY | glTF | 1,488 faces / 16.9 MB (2048 px textures) | game-ready | no |
| Ural-4320 army truck | Sketchfab, davidbroutian[^sf-ural] | CC BY | glTF | 8,492 faces / 4.2 MB | "ready for use in game engines" | no |
| BM-21 Grad rocket launcher truck, low poly | Sketchfab, lm9241221[^sf-bm21] | CC BY ("noai" tag) | glTF | 16,131 faces / 5.9 MB | low poly | no |
| MAZ-543 8×8 launcher chassis (stand-in for a ballistic-missile launcher), low poly | Sketchfab, lm9241221[^sf-maz] | CC BY | glTF | 31,031 faces / 13.7 MB | low poly | no |
| Toyota Hilux 1983 pickup (stand-in for a "technical") | Sketchfab, elkarimeldino[^sf-hilux] | CC BY | glTF | 12,140 faces / 3.6 MB | civilian pickup | no |
| S-300 5P85 launcher (9M83 missiles) | Sketchfab, xFORTUNAx ([threats.md](../threats.md) `sf-s300`) | CC BY | glTF | 285,136 faces / 21.6 MB | detailed; the missile is not the PMU-2's (threats.md) | no |
| ZSU-23-4, low poly | Sketchfab, S1Priv ([threats.md](../threats.md) `sf-zsu`) | CC BY | glTF | unknown without download | low poly | no |
| Factories, warehouses (generic depot / plant buildings) | Kenney, City Kit (Industrial)[^kenney] | CC0 | unknown without download | unknown | stylised low poly (inferred from the tags) | no |

### 3.2 Sea

| what it is | source (author) | licence | format | faces / size | quality from the listing | on disk |
|---|---|---|---|---|---|---|
| Barge (the range's target barge) | FlightGear models DB #753 (SAVAGE)[^sm-sea] | GPL v2 (setup download) | `.ac` | 494 KiB (370 KiB texture) | flat cargo barge | no |
| Oliver Hazard Perry frigate (generic frigate) | FlightGear models DB #758 (Alexis Bory)[^sm-sea] | GPL v2 (setup download) | `.ac` | 679 KiB | with wake texture | no |
| PSC9 patrol ship | FlightGear models DB #759 (SAVAGE)[^sm-sea] | GPL v2 (setup download) | `.ac` | 756 KiB, untextured | coastal patrol ship (inferred from the name) | no |
| LCM-6 landing craft | FlightGear models DB #754 (SAVAGE)[^sm-sea] | GPL v2 (setup download) | `.ac` | 378 KiB, untextured | small landing craft | no |
| Chemical-oil tanker, LNG tanker (port targets) | FlightGear models DB #8896, #8762 (Claudio Pavan)[^sm-civ] | GPL v2 (setup download) | `.ac` | unknown without download | merchant ships | no |
| Patrol Boat PBR Mk II (small fast patrol boat) | Sketchfab, SavyTheCreator[^sf-pbr] | CC BY | glTF | 24,522 faces / 8.2 MB | river patrol boat | no |
| M21 patrol boat | Sketchfab, agt14032013[^sf-m21] | CC BY | glTF | 253,134 faces / 7.8 MB | detailed; OBJ and DAE in the download | no |
| Dhow | Sketchfab, nmoq[^sf-dhow] | CC BY | glTF | 92,684 faces / 1.5 MB, untextured | wooden trading boat | no |
| Speedboat, very low poly | Sketchfab, 3DDomino[^sf-speed] | CC BY | glTF | 562 faces / 12 KB | far view only | no |

### 3.3 Air: parked aircraft and targets

| what it is | source (author) | licence | format | faces / size | quality from the listing | on disk |
|---|---|---|---|---|---|---|
| F-16I, F-16D, F-15C, F-15I, F-35I (the IAF's fighters) | our own models (§1) | as §1 | GLB / glTF | in the repo | detailed | yes |
| MiG-29 9.12 (adversary) | our own model (§1) | GPL-3.0 | GLB | in the repo | detailed | yes |
| Boeing 707 (the IAF's Re'em tanker type) | FGAddon "707" (M. Kraus)[^fg-707] | GPL-3.0-or-later (its header) | `.ac` | unknown without download | full aircraft with a tanker variant set (`707-TT-set.xml`) | no |
| C-130 Hercules, low poly | FlightGear models DB #1099 (Bertrand Augras)[^sm-air] | GPL v2 (setup download) | `.ac` | 197 KiB | static, USAF grey | no |
| KC-135, low poly (707-family tanker shape) | FlightGear models DB #738 (Alexis Bory, from David Culp's KC-135)[^sm-air] | GPL v2 (setup download) | `.ac` | 275 KiB | static | no |
| HH-60G Pave Hawk, low poly (Black Hawk family) | FlightGear models DB #975 (Alexis Bory)[^sm-air] | GPL v2 (setup download) | `.ac` | 244 KiB | static | no |
| C-130 Hercules (full aircraft) | FGAddon "C130" (Emmanuel Baranger, Didier Fabert)[^fgaddon-svn] | `COPYING`: GPL 2 text; "or later" open | `.ac` | unknown without download | flyable model | no |
| CH-53E Super Stallion (the Yas'ur family) | FGAddon "ch53e" (Pierre Duval, Josh Babcock, StuartC)[^fgaddon-svn] | `<license>GPL v2</license>`; "or later" open | `.ac` | unknown | flyable model | no |
| UH-60 Black Hawk | FGAddon "UH-60"[^fgaddon-svn]; the same author's Sketchfab copy (helijah)[^sf-uh60] | FGAddon: GPL 2 text; Sketchfab: CC BY | `.ac`; glTF | Sketchfab: 47,763 faces / 3.4 MB | full aircraft | no |
| Beechcraft King Air (the Tzofit), T-6 Texan II (the Efroni) | FGAddon "Beechcraft-King-Air", "Beechcraft-T6-Texan-II" (Emmanuel Baranger)[^fgaddon-svn] | `COPYING`: GPL 2 text; "or later" open | `.ac` | unknown | flyable models | no |
| AH-64D Apache | Sketchfab, mgg8: "Westland WAH-64D Apache AH Mk.1"[^mgg8] | CC0 | glTF | 88,922 faces / 1.1 MB | AI-assisted, "approximate" | no |
| C-130 Hercules (C.3) | Sketchfab, mgg8[^mgg8-c130] | CC0 | glTF | 254,892 faces / 3.7 MB | AI-assisted, "approximate" | no |
| F-4 Phantom (FGR.2; adversary F-4 shape) | Sketchfab, mgg8[^mgg8] | CC0 | glTF | 144,770 faces / 2.8 MB | AI-assisted, RAF markings | no |
| Mi-24D Hind, MiG-21PF, MiG-23ML (generic adversary types) | Sketchfab, mgg8[^mgg8] | CC0 | glTF | 125–187k faces / 2.3–2.7 MB each | AI-assisted | no |
| MQ-1B Predator (UAV stand-in) | Sketchfab, mgg8[^mgg8] | CC0 | glTF | 117,802 faces / 1.6 MB | AI-assisted | no |
| F-14A / F-14B Tomcat | FGAddon "f-14b"; Sketchfab ioai25312 ([threats.md](../threats.md) §5) | licence open (threats.md); CC BY | `.ac`; glTF | unknown | — | no |

### 3.4 Air-base furniture

| what it is | source (author) | licence | format | faces / size | quality from the listing | on disk |
|---|---|---|---|---|---|---|
| TAB-VEE hardened aircraft shelter, type C and type B | FlightGear models DB #7673, #7647 (J Maverick 16, the F-16's 3D artist)[^sm-has] | GPL v2 (setup download) | `.ac` | 898 KiB, 877 KiB | textured arch with doors | no |
| Hardened aircraft shelter (simple) | FlightGear models DB #287 (author "unknown")[^sm-mil] | GPL v2; author unknown | `.ac` | 6 KiB | bare shape | no |
| USAF hangar 60 × 70 m, sand | FlightGear models DB #731 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 51 KiB | low poly | no |
| Open military hangar, one aircraft, grey | FlightGear models DB #904 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 90 KiB | low poly | no |
| Hush house (engine test hangar) | FlightGear models DB #729 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 58 KiB | low poly | no |
| Sunshade roofs for fighters, 1 / 2 / 3 modules | FlightGear models DB #724–726 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 29–70 KiB | light steel roofs | no |
| Covered parking for fuel trucks | FlightGear models DB #973, #974 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 13 KiB | low poly | no |
| Control tower, 40 m (USAF) | FlightGear models DB #870 (Josh Babcock)[^sm-mil] | GPL v2 (setup download) | `.ac` | 40 KiB | low poly | no |
| Military fuel truck, medium and low poly | FlightGear models DB #723, #722 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 163 KiB, 89 KiB | US Air Force style | no |
| F-600 fuel truck | FlightGear F-16 `Models/Ramp/fuel-truck_f600.ac` | GPL-2.0-or-later | `.ac` | 285 KB | the F-16's ramp prop | **yes** |
| Generic GPU on trailer | FlightGear F-16 `Models/Ramp/generic-trailer-GPU.ac` (also models DB #1876, Don Lavelle) | GPL-2.0-or-later (in the F-16) | `.ac` | 621 KB + 122 KB texture | detailed | **yes** |
| Wheel chocks, fire extinguisher | FlightGear F-16 `Models/Ramp/` | GPL-2.0-or-later | `.ac` | 30 KB, 343 KB | small props | **yes** |
| Aircraft towing tractor (Coleman) | FlightGear models DB #721 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 38 KiB | low poly | no |
| Ground power unit | FlightGear models DB #1144 (Bertrand Augras)[^sm-veh] | GPL v2 (setup download) | `.ac` | 105 KiB | low poly | no |
| Airport crash tender (fire truck) | FlightGear models DB #2156 (David Glowsky)[^sm-veh] | GPL v2 (setup download) | `.ac` | 80 KiB | red, civil | no |
| Arresting gear BAK-12 | FlightGear models DB #918 (David Culp)[^sm-mil] | GPL v2 (setup download) | `.ac` | 36 KiB | runway-edge unit | no |
| Wind sock | FlightGear models DB #5227 (Erik Hofman)[^sm-ws] | GPL v2 (setup download) | `.ac` | 29 KiB | standard | no |
| Apron light pole, 38 m grey | FlightGear models DB #720 (Alexis Bory)[^sm-lp] | GPL v2 (setup download) | `.ac` | 13 KiB | with red light | no |
| Fence, 2 m green | FlightGear models DB #2510 (Frank Goeldner)[^sm-fence] | GPL v2 (setup download) | `.ac` | 280 KiB (texture) | tiling fence | no |
| Military airport beacon | FlightGear models DB #217 (Josh Babcock)[^sm-mil] | GPL v2 (setup download) | `.ac` | 22 KiB | rotating beacon | no |
| H-shaped barracks / apartment block (Nellis style) | FlightGear models DB #732 (Alexis Bory)[^sm-mil] | GPL v2 (setup download) | `.ac` | 42 KiB | generic | no |
| Hardened aircraft shelter, draft | Sketchfab, samuelbrunner[^sf-has] | CC BY | glTF | 58,511 faces / 24 MB | "DRAFT"; the aircraft in it is a prop | no |
| Ground power unit | Sketchfab, omri_ha_muglob[^sf-gpu] | CC BY | glTF | 7,952 faces / 1.2 MB | detailed | no |
| Aircraft tug (carrier type) | Sketchfab, Chukk007[^sf-tug] | CC BY | glTF | 2,269 faces / 485 KB | low poly | no |

### 3.5 Excluded

| candidate | reason |
|---|---|
| OPRF assets (SA-2, SA-3, SA-6, ZSU-23, Buk-M2, S-300, Patriot, frigates, speedboat, depots, hangars, M1, Bradley, Stryker, MLRS)[^oprf] | no licence file; mixed provenance (bundles textures and models by FlightGear scenery authors, such as Alexis Bory's Humvee). Would be the first pick for ground targets if its authors state a licence (§6) |
| Sketchfab user 42manako (BMP-2, and threats.md's picks for 3rd Khordad, Tor-M1, the 1S91 radar and the 2T7 transloader) | the uploader's BMP-2 says "Model ripped from Squad"[^sf-42m]: a commercial game. Every model of the uploader stays out until each one's provenance is shown |
| Sketchfab user MirzaArrafiERV_45 (Patriot, MAZ-543 Uragan, T-90, UH-60M, KC-135R, KC-46A) | the T-90AM is tagged "World of Tanks"[^sf-t90]: provenance unclear |
| Sketchfab "Free Standard" models (helijah's T-6 Texan II, Super King Air, F-4 Phantom, Bell 206) | not an open licence; whether the files may sit in an open repository is unclear (Sketchfab's help pages, second-hand (search quote)[^sf-std]) |
| War Thunder or other game rips | the licence rule ([threats.md](../threats.md) §5) |
| CGTrader, TurboSquid, Unity Asset Store military packs | paid or account-only, licences not open |
| Poly Pizza "Tank" models | cartoon style; licence shown per model page only[^polypizza] |

## 4. Gaps

Looked for and not found under a usable licence; these would be modelled in-house, as the F-35I's cockpit was
(`tools/f35i/`):
- **IAF types:** M-346 Lavi, Gulfstream G550 (Eitam, Oron) and G-V (Shavit), KC-46A (only uploads with unclear
  provenance or 320k faces), Heron and Hermes UAVs, AS565 Panther.
- **Threat vehicles with clean provenance:** 3rd Khordad TELAR and radar, Bavar-373, Tor-M1, 2K12 Kub launcher and
  1S91 radar (after excluding 42manako), S-300 radars (30N6, 64N6), the Misagh-2 team; modern Iranian ballistic-missile
  launchers (the MAZ-543 is a stand-in).
- **Sea:** fast-attack boats of the Gulf type (only river patrol boats and a dhow).
- **Bases:** shelters and towers of the IAF's own designs (the TAB-VEE is a US / NATO shelter; how close the IAF's
  are is open), blast walls and revetments (none in the FlightGear database: searches for "revetment", "blast wall",
  "hesco" found nothing).
- **Ground:** tunnel shafts (a hole and a hatch: simple in-house, inferred).

## 5. Recommendation

| group | first pick | why | download if yes |
|---|---|---|---|
| Air-base furniture | the FlightGear scenery models database set in §3.4 (shelters, hangars, sunshades, tower, trucks, GPU, tug, crash tender, BAK-12, wind sock, light poles, fence, beacon, barracks), plus the F-16's `Models/Ramp/` on disk | one source covers nearly every row, low poly (kilobytes each), `.ac` our converters already read; the TAB-VEE is by J Maverick 16, already credited | about 3.1 MiB; the F-16's ramp props 0 |
| Air (parked, targets) | our own jets for the IAF fighters; the FGAddon 707 for the tankers (GPL-3.0-or-later: ships); FlightGear low-poly C-130, KC-135, HH-60 for parked transports and helicopters; then mgg8's CC0 Apache, Mi-24, F-4, MiG-21 / MiG-23 | no download for the fighters; the low-poly static models suit rows of parked aircraft on a laptop GPU (inferred); mgg8 is the widest CC0 set but "approximate" and 90–250k faces each, so decimated for distance (inferred) | 0.7 MiB low poly; 707 unknown without download; mgg8 picks about 17 MB |
| Sea | FlightGear barge, Oliver Perry frigate, PSC9, LCM-6 | the barge is the range target the sim lacks; same source and pipeline as the bases | about 2.3 MiB |
| Ground targets | FlightGear SA-2, van, radar shelter, Humvee, truck, bunker, tanks, container, bridge; Sketchfab CC BY T-72, Ural, BM-21, MAZ-543, Hilux; the S-300 and ZSU from threats.md | no single clean source; the FlightGear pieces share the base pipeline, the Sketchfab vehicles are the only usable modern vehicles found | about 5 MiB FlightGear; about 66 MB Sketchfab (most of it the 2048 px textures of the T-72 and the S-300) |

**Order that gives the most for the least** (inferred):
1. The F-16's `Models/Ramp/` (on disk, ships): GPU, fuel truck, chocks on the player's spot at once.
2. One setup step that fetches the FlightGear database models (§3.4, §3.2, the FlightGear rows of §3.1, the low-poly
   aircraft of §3.3) by id through its public files endpoint and converts them, as the F-15 step does: about 11 MiB,
   one credit block (the authors' names), every base and the barge at once.
3. The FGAddon 707 (ships): the Re'em at Nevatim.
4. Sketchfab vehicles and mgg8 aircraft, if the user accepts a free Sketchfab account for the download.
5. In-house models for the gaps (§4), starting with whatever the first strike missions need.

Total if the user says yes to all first picks: about 3.1 + 2.3 + 0.7 + 5 MiB from the FlightGear database (about 11
MiB), about 17 MB of mgg8 aircraft, about 66 MB of Sketchfab CC BY vehicles, and the 707 (unknown without download):
roughly 95 MB plus the 707.

## 6. Filling the bases

What public sources show of the real bases, in general terms:
- **Hardened shelters** hold the fighters. Ramat David's jets stand in "underground hangar systems and shelters with
  several entrances and exits"[^w-rd]; OSM maps 25 shelters there and 11 at Nevatim ([airbases.md](../airbases.md)
  §2); at Ramon small white shelter roofs sit at the ends of the loop taxiways ([airbases.md](../airbases.md) §5); an F-16I in its
  shelter is on Commons ([docs/aircraft-models.md](../../../docs/aircraft-models.md) `sufashelter`). Rows: the TAB-VEE
  shelters (§3.4), as a stand-in.
- **Sunshade rows** over fighter aprons: Hatzerim's F-15I and Sufa spots are on two sunshade rows ([airbases.md](../airbases.md) §5).
  Rows: the sunshade roofs, 1 to 3 modules.
- **Hangars**: 7 (Ramon) to 21 (Hatzerim) in OSM; a hangar complex at Nevatim and the 2010 tanker building[^w-nv];
  Ramon's UAV hangars[^w-rm]. Rows: the 60 × 70 m hangar, the open hangar, the hush house.
- **Transports, tankers and special aircraft** at Nevatim: C-130J and C-130H, 707 tankers, KC-46A (since May 2026),
  Gulfstream G-V and G550[^w-nv]. Rows: the 707, C-130, KC-135 (stand-in), gaps for the KC-46 and Gulfstreams.
- **Helicopters**: CH-53 at Tel Nof[^w-ek]; attack helicopters at Ramon since 1990[^w-rm]. Rows: CH-53E, Apache.
- **Trainers** at Hatzerim (the flight academy): M-346, T-6 Texan II, King Air, Grob 120[^w-hb]. Rows: the T-6 and
  King Air (FGAddon); the M-346 is a gap.
- **Everywhere**: fuel trucks, tugs, GPUs, crash tenders, fences, light poles, a wind sock and a tower (inferred:
  standard at any military airfield).

What each of the sim's five bases lacks today:

| base | what the sim has | lacks |
|---|---|---|
| Ramon | runways, taxiways, 7 aprons, a Sufa spot; since 2026-11-19 shelters, hangars, buildings, the tower, parked Sufas, vehicles ([base-furniture.md](../base-furniture.md), our own shapes) | Apaches |
| Hatzerim | runways, 89 taxiways, 9 aprons, F-15I and Sufa spots | the sunshade rows, 21 hangars, the tower, parked F-15Is and Sufas, trainers, vehicles |
| Nevatim | runways, 16 aprons, the tower point, an F-35I spot | 11 shelters, 19 hangars, the tower building, parked F-35Is, transports and tankers, vehicles |
| Ramat David | runways, 52 taxiways, 1 apron, a Barak spot | 25 shelters, 15 hangars, the tower, parked Baraks, vehicles |
| Tel Nof | runways, 26 taxiways, 1 apron placed by eye, a Baz spot | every building (OSM maps none), the tower, parked Baz jets, CH-53s, vehicles |

## 7. Decisions (the user, 17 November 2026)

- **The bases**: "fill the base with hangers and building and other airplanes"; "for bases, look on air photos of
  the bases and try to put hings as in reality".
- **Sketchfab account** (question 1): "yes".
- **GPL v2 models fetched at setup time** (question 2): "yes".
- **Ask the project with no licence file for a licence** (question 3, OPRF assets): "yes".
- **Parked-aircraft detail** (question 4): "why not just use the same models": parked aircraft use the flying jets'
  models.
- **Which base first** (question 5): "pick". The orchestrator picked Ramon, the Sufa's home base.

## 8. Open questions for the user (asked before the decisions)

1. **Sketchfab downloads** need a free account (the F-35I's did). Is that acceptable for the CC BY vehicles and the
   mgg8 CC0 aircraft, or should the first round use only sources without an account?
2. **GPL v2 FlightGear models** (the database's and the older FGAddon aircraft): fetch them in setup like the F-15,
   or first ask their authors for "or later" so they can ship?
3. **OPRF assets**: ask its maintainers for a licence statement? One "yes" would add SAM sites, AAA, ships, depots and
   M1 / Bradley / MLRS vehicles from one 155 MB source.
4. **Parked aircraft detail**: low-poly static models (about 200 KiB each) or detailed ones (2–4 MB, 90–250k faces
   each) within the Iris Xe budget?
5. **Which base first**: Nevatim (shelters, hangars and the transports) or Ramon (the Sufa's base)?

[^sm-api]: FlightGear Scenemodels, model list and file sizes through the site's public API, read 2026-11-17:
    https://scenery.flightgear.org/api/models (per model: `/api/models/<id>` and `/api/models/<id>/files`)
[^sm-form]: FlightGear Scenemodels, "Add model" form ("I release my contribution under the GNU GPL v2",
    https://www.gnu.org/licenses/gpl-2.0.html), in the site's script `assets/AddModelView-*.js`, read 2026-11-17;
    the older form (t3r/smweb): https://github.com/t3r/smweb/blob/master/scenemodels/view/submission/model/add_model_form.php
[^sm-mil]: FlightGear Scenemodels, group "Shared - Military" (id 6), 147 models, read 2026-11-17:
    https://scenery.flightgear.org/api/models?group=6
[^sm-veh]: FlightGear Scenemodels, group "Shared - Airport Vehicles" (id 23), read 2026-11-17:
    https://scenery.flightgear.org/api/models?group=23
[^sm-air]: FlightGear Scenemodels, group "Shared - Airport Immovable Aircraft" (id 14), read 2026-11-17:
    https://scenery.flightgear.org/api/models?group=14
[^sm-sea]: FlightGear Scenemodels, groups "Shared - Maritime, Military" (id 15) and "Maritime, Civilian" (id 16), read
    2026-11-17: https://scenery.flightgear.org/api/models?group=15
[^sm-civ]: FlightGear Scenemodels, group "Shared - Maritime, Civilian" (id 16), read 2026-11-17:
    https://scenery.flightgear.org/api/models?group=16
[^sm-has]: FlightGear Scenemodels, model 7673 "TAB-VEE Type C Hardened Aircraft Shelter" ("as seen on air bases across
    Europe, Asia", J Maverick 16) and its files, read 2026-11-17: https://scenery.flightgear.org/api/models/7673
[^sm-ws]: FlightGear Scenemodels, search "windsock", read 2026-11-17: https://scenery.flightgear.org/api/models?search=windsock
[^sm-lp]: FlightGear Scenemodels, search "light pole", read 2026-11-17:
    https://scenery.flightgear.org/api/models?search=light%20pole
[^sm-fence]: FlightGear Scenemodels, search "fence", read 2026-11-17: https://scenery.flightgear.org/api/models?search=fence
[^fgaddon-svn]: FlightGear FGAddon, trunk `Aircraft/` listing and each aircraft's `COPYING`, `-set.xml` and read-me,
    read 2026-11-17: https://svn.code.sf.net/p/flightgear/fgaddon/trunk/Aircraft/
[^fg-707]: FlightGear FGAddon, "707" (`707-set.xml` header: "Boeing 707 for Flightgear, Copyright (C) 2013 M.Kraus …
    either version 3 of the License, or (at your option) any later version"; `LICENSE`: GPL 3),
    https://svn.code.sf.net/p/flightgear/fgaddon/trunk/Aircraft/707/
[^oprf]: l0k1, "oprf_assets" (README; file tree; no licence file; `BUK-M2-set.xml` and others: "Copyright (c) 2015 onox
    … either version 3 of the License, or (at your option) any later version"), read 2026-11-17:
    https://github.com/l0k1/oprf_assets
[^sf-cc]: Sketchfab, search API with the "downloadable" and licence filters (face counts, archive sizes, licence
    labels), read 2026-11-17: https://api.sketchfab.com/v3/search?type=models&downloadable=true
[^mgg8]: Sketchfab, user mgg8 (airmuseums.co.uk), downloadable models, read 2026-11-17: https://sketchfab.com/mgg8
[^mgg8-c130]: Sketchfab, mgg8, "Lockheed C-130 Hercules" (description: "Created in Blender with AI assistance … Free
    download under CC0 1.0 (public domain) … attribution is optional"):
    https://sketchfab.com/3d-models/d2f92fa0bc004cbba8d4733b29014588
[^kenney]: Kenney, "City Kit (Industrial)" (licence "Creative Commons CC0"), read 2026-11-17:
    https://kenney.nl/assets/city-kit-industrial
[^sf-t72a]: Sketchfab, lebedeventerprise, "T-72": https://sketchfab.com/3d-models/d71852d8757942a0a5e955215b0ee172
[^sf-t72b]: Sketchfab, MrTheRich, "Low Poly T-72 Tank - Game Ready":
    https://sketchfab.com/3d-models/8c9d0d6640a244e39082cd9fdf565cef
[^sf-ural]: Sketchfab, davidbroutian, "Ural 4320": https://sketchfab.com/3d-models/f953c51a5dbc4a15949f4dcc0905c4e8
[^sf-bm21]: Sketchfab, lm9241221, "BM-21 GRAD (LOW POLY)": https://sketchfab.com/3d-models/0a358a81e71140d7b0446c2fb25291cc
[^sf-maz]: Sketchfab, lm9241221, "MAZ-543 8X8 (LOW POLY)": https://sketchfab.com/3d-models/59c9c7fe709e4d37bcdb9f4aa79de008
[^sf-hilux]: Sketchfab, elkarimeldino, "Toyota Hilux 1983": https://sketchfab.com/3d-models/d874f5e016fe41bd8461adb0c6d41ede
[^sf-pbr]: Sketchfab, SavyTheCreator, "Patrol Boat PBR MK2": https://sketchfab.com/3d-models/dbd87172b2934063aa93ffd0c6f85750
[^sf-m21]: Sketchfab, agt14032013, "M21 Patrol Boat": https://sketchfab.com/3d-models/598d3938b4214f2e9f385c29b3a3744a
[^sf-dhow]: Sketchfab, nmoq, "Dhow01": https://sketchfab.com/3d-models/44cd10977ae646268d87f850ff321186
[^sf-speed]: Sketchfab, 3DDomino, "Speedboat": https://sketchfab.com/3d-models/ee69bea3e40849909d73f6a896e7382a
[^sf-uh60]: Sketchfab, helijah, "Sikorsky UH-60 Black Hawk" (tagged "flightgear"):
    https://sketchfab.com/3d-models/ee81eb66006b4d8980d0cf9ff6304b69
[^sf-has]: Sketchfab, samuelbrunner, "Hardened Aircraft Shelter HAS -DRAFT-":
    https://sketchfab.com/3d-models/ccc398978c0f4bb3955ada9d9a1dcf3c
[^sf-gpu]: Sketchfab, omri_ha_muglob, "GPU (Aiport Ground Power Unit)":
    https://sketchfab.com/3d-models/b18e62dda2e04e97a95312bb6a284f1c
[^sf-tug]: Sketchfab, Chukk007, "Aircraft_Tug": https://sketchfab.com/3d-models/ac1c0a974a734864a27fe84dbbcb0de8
[^sf-42m]: Sketchfab, 42manako, "BMP-2" (description: "Model ripped from Squad"):
    https://sketchfab.com/3d-models/a843e922897c499ca53e718235b3875a
[^sf-t90]: Sketchfab, MirzaArrafiERV_45, "Uralvagonzavod T-90AM Main Battle Tank" (tags include "World of Tanks"):
    https://sketchfab.com/3d-models/619de9f0908e4c8395fe036ffe6e3884
[^sf-std]: Sketchfab Help Center, "Store License Usage FAQ" (second-hand (search quote): the Standard licence allows
    use "in all types of derivative works"; buyers may not "offer others the ability to download models"):
    https://help.sketchfab.com/en/articles/16152225-store-license-usage-faq
[^polypizza]: Poly Pizza, search "tank", read 2026-11-17: https://poly.pizza/search/tank
[^w-rd]: Wikipedia, "Ramat David Airbase", read 2026-11-17: https://en.wikipedia.org/wiki/Ramat_David_Airbase
[^w-nv]: Wikipedia, "Nevatim Airbase", read 2026-11-17: https://en.wikipedia.org/wiki/Nevatim_Airbase
[^w-rm]: Wikipedia, "Ramon Airbase", read 2026-11-17: https://en.wikipedia.org/wiki/Ramon_Airbase
[^w-ek]: Wikipedia, "Tel Nof Airbase", read 2026-11-17: https://en.wikipedia.org/wiki/Tel_Nof_Airbase
[^w-hb]: Wikipedia, "Hatzerim Airbase", read 2026-11-17: https://en.wikipedia.org/wiki/Hatzerim_Airbase
