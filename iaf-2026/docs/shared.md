# What Modern IAF gives the original game

Every enhancement the sim builds is also offered to the reborn game (the original 1998 game on this engine) as an
opt-in Preferences row; the original stays the default ([plan.md](plan.md) Rules). This page is the ledger: one row per
enhancement, its sim item, the reborn switch it becomes, and where it stands. Switches are recorded in
[../../docs/deviations.md](../../docs/deviations.md) when built.

**Status values:** built in reborn = a Preferences row exists and is documented; partly built = a developer switch or a
first step exists; to do = nothing in reborn yet; not applicable = the reason is given with its date.

**Terms:** DEM = digital elevation model; FM = flight model; OSM = OpenStreetMap; RWR = radar warning receiver; TSD =
tactical situation display (map); TTS = text to speech.

| enhancement | sim item | reborn switch | status | notes |
|---|---|---|---|---|
| Open-data terrain in the UTM frame (Copernicus GLO-30 heights, Sentinel-2 colour, Survey of Israel photo) | [B1](plan.md#b1-the-terrain) | Extras → World scale Real + "Terrain: Open data (Copernicus / Sentinel-2)"; the roadmap's [Modern DEM](../../docs/roadmap.md#later) | partly built | the developer switch `IAF_THEATRE=israel` streams the theatre ([deviations.md](../../docs/deviations.md) "Modern IAF's theatre in the original game"); the Extras row and missions at the real positions are to do |
| Airbases from OSM: Ramon, Ramat David, Hatzerim, Nevatim with real runways, taxiways, shelters, tower, parking spots | [B2](plan.md#b2-the-airbases) | Extras → "More airbases" (roadmap [More airbases](../../docs/roadmap.md#later)) | partly built | `Settings.airbases_file()` already makes Detailed airbases draw a theatre's own bases; the picker for the home base and the bases in the 1998 frame are to do |
| Terrain types, runway and sea planes (`terraintype.dat`) in the real frame | [B2](plan.md#b2-the-airbases) | rides on the open-data terrain row | to do | needs the terrain row first |
| Scenery, roads and lakes in the real frame | [B4](plan.md#b4-ground-look-parity), [B2](plan.md#b2-the-airbases) | rides on the open-data terrain row | partly built | reborn already has today's main roads (roadmap [A modern TSD map](../../docs/roadmap.md#later)); lakes and the scenery step are to do |
| TSD / briefing map from OSM with the West Bank and Golan lines | [E2](plan.md#e2-the-front-end) (the sim's TSD map) | Extras → "Briefing map: Modern" (roadmap [A modern TSD map](../../docs/roadmap.md#later)) | partly built | the eight city dots and the main roads are built; borders, names, places and the two lines are to do |
| RWR symbol sheet | [E1](plan.md#e1-cockpit-data-sounds-and-voices) | Extras → Real HUD / Real MFD options (RWR glyphs) | to do | the sheet is the sim's own art; reborn keeps the original glyphs unless the switch is on |
| ADI texture | [E1](plan.md#e1-cockpit-data-sounds-and-voices) | Extras → Real HUD / Real MFD options (ADI) | to do | as the RWR sheet |
| The CC0 sound set | [E1](plan.md#e1-cockpit-data-sounds-and-voices) | Extras → "Extra sounds" (roadmap [Extra sounds](../../docs/roadmap.md#extra-sounds-not-in-the-original)) | to do | the unused and silent rows get the sim's clips; the original sounds stay the default |
| Betty per real jet and the TTS towers for every base | [E1](plan.md#e1-cockpit-data-sounds-and-voices), [E3](plan.md#e3-the-training-missions) | Extras → "Real Betty" (roadmap [Real Betty](../../docs/roadmap.md#real-betty-option-extras-switch-wishlist-researched-2026-10-19)) | partly built | Real HUD speaks the F-16 and F-35I warnings; the TTS tower voices and the radio filter are to do |
| The own 6-DoF for the modern jets (TP-1538) | [C2](plan.md#c2-the-6-dof) | Physics → "Flight model: 6-DoF (TP-1538)" | to do | `Model = 6dof` in the own data selects it inside `IafFlight`; the original types never reach it (tested); the Physics row is to do |
| FM-0 rows for Sufa, Barak, F-35I and F-15I | [C1](plan.md#c1-fm-0-data) | Physics → Flight data: Real | built in reborn | the Sufa, Ra'am and F-35I rows are Extras switches that force their row ([deviations.md](../../docs/deviations.md)); the Barak is reborn's Real F-16 row |
| Training scoring (pass / fail rules as data) | [E3](plan.md#e3-the-training-missions) | Extras → a "Training missions" option on the Mission Creator list | to do | the scorer `iaf-training` is shared Rust; reborn's missions carry no `training` data |
| The real-format debrief record (English and Hebrew) | [E3](plan.md#e3-the-training-missions), [E2](plan.md#e2-the-front-end) | the debrief page option (roadmap [AI debrief](../../docs/roadmap.md#ai-debrief-later)) | to do | the page itself is open in the sim (E2) |
| The threat set (12 units, 10 weapons) for the Mission Creator | [D1](plan.md#d1-the-threats-research), [D2](plan.md#d2-units-and-weapons) | Extras → "Modern aircraft and weapons" (roadmap [Modern aircraft and weapons](../../docs/roadmap.md#modern-aircraft-and-weapons-post-everything)) | to do | the records are drafts awaiting the user's decision |
| Compact JSON and ogg audio | [Rules](plan.md#rules-the-user-3-november-2026) | none | not applicable | shared by construction: the same writers and loaders serve both games (2026-11-03) |
| Hebrew wording rules (gender-neutral, formal) | [E2](plan.md#e2-the-front-end) | reborn's Hebrew pack | to do | both games read one string-table shape; the rules apply to reborn's pack when it is next edited |
| The keys table | [E1](plan.md#e1-cockpit-data-sounds-and-voices) | none | not applicable | the original's keys stay the original's (2026-11-03); the sim's table is its own file |
