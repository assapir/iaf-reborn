# Modern IAF: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **The Givatayim fly-by's faults (2026-11-25, the user: "no loose corners";
  [../../docs/real-hud.md](../../docs/real-hud.md) "DASH helmet", [../../docs/rendering.md](../../docs/rendering.md) §6,
  [../../docs/scenery.md](../../docs/scenery.md)):** the Sufa's and the Barak's helmet display blanks while the head
  looks into the cockpit (CKPT BLNK ON on the DED): its cross and numbers no longer draw over the canopy rail and the
  consoles; looking out to the side it shows as before; the Adir's helmet display is unchanged. The town's buildings
  take a material per model instead of an instance uniform: over Tel Aviv at 300 m the log had 1,039 (Sufa) and 1,145
  (Barak) "Too many instances using shader instance variables" errors, now none, the same picture; on the laptop's Iris
  Xe (Everything on, 1080p) the frame over Tel Aviv took 37.5 / 36.0 ms at 150 / 300 m before and 36.0 / 35.6 ms after.
  The engine's heat haze never bends the town or the sky over the jet's own body. With Scenery Detailed the far
  towers keep their rows of windows (box-filtered, the same mean colour) instead of plain one-colour boxes. Pictures:
  `modern-iaf/tests/_flyby_shot.gd`.
- **Only radio over the flight; no reason lines; no pane on Updates (2026-11-25, the user's third notes on A86, A98,
  A101; [front-end.md](front-end.md) §8, §14):** every in-flight line that is not a radio call (switch states,
  refusals, damage, cheats, the training's "To complete" and wrong-runway lines and its fail banner) is gone from the screen and kept in
  the recorded flight; the AWACS page dims a request it cannot take without a reason line; Settings → Updates shows no
  explanation pane. The game manual (English and Hebrew) explains each. The CMDS manual program shows on the CMDS
  panel's PRGM knob, added to the F-16 cockpit model on 2026-11-25 with the MODE knob's six positions
  ([cockpit.md](cockpit.md) §5.13).
- **The enemy's dogfight moves and the air-defence network's shared tracks (2026-11-25, the user: "no loose corners";
  the enemy-AI list's "IADS network, enemy-fighter BFM"; [ai-plan.md](ai-plan.md) K4–K6, X4;
  [../../docs/ai.md](../../docs/ai.md) §15.1, §15.5, §17, §18.2):** a MiG-29A in the dogfight also flies the reversal
  (it slows into an attacker closing fast so the attacker overshoots), the flat and rolling scissors, and the
  extension (away at full power when low on energy in the bogey's rear quarter, then back by the intercept), by its
  skill's tactics; it fires its R-73 on a bogey its pilot sees (the helmet sight), without its radar. The S-300
  network takes its fighters' radar contacts and the sites' tracks into its picture: a site cued on a MiG's track fires
  with its own search off, and the GCI vectors on a jet below the search radar's horizon that a site or a MiG holds.
  The crews' emission control and move by skill: a High crew's search radiates 20 s a minute while it is alone and
  idle; after an engagement a crew moves 60 s (Low), 20 s (Medium) or 5 s (High) after its last track. Tests:
  `crates/iaf-ai/tests/dogfight.rs`, `net.rs`, `sites.rs`, `modern-iaf/tests/test_bfm_iads.gd`. No mission places
  one.
- **The full AWACS (2026-11-25, the user: "Full AWACS"; "The eitam should be in the sky in makes sense place - where
  it not directly in the middle of the flight. It's ai should know to run away if needed or call for help"; ai-plan
  C1, C2, K10; [../../docs/ai.md](../../docs/ai.md) §24):** the radio menu's third page asks the AWACS for a picture,
  bogey dope, declare and the vectors to the target, home and the tanker; it answers in NATO brevity (BRAA from the
  player), voiced in English and Hebrew, and a request it cannot take is dimmed (since 2026-11-25 without a reason line: the game manual says when). In Scramble the Eitam
  (our own G550 CAEW model) flies a standoff racetrack behind the flight's way at 41,000 ft; a hostile group near it
  sends it away at Mach 0.85 with a call for help ("threat ... Eitam retrograding, commit"). Its radar feeds the
  picture, the contact calls and the data link; the enemy can shoot it down, which ends the service. `test_awacs.gd`, `cargo test -p iaf-ai --lib -- awacs`, `--test eitam`.
- **The Eitam's look and flight (2026-11-25, the user: "The eitam looks strange, only white. look online for pics, look
  for a better model"; [../../docs/ai.md](../../docs/ai.md) §24.3, [flight-model.md](flight-model.md) §9.22):** its
  model matched to photographs of the IAF's CAEW (the drooped nose radome, the tail radome, the side cheeks, the
  satcom bullet, the flight deck's six dark windows in thin frames; white with the blue cheatline, the roundels,
  537 and ISRAEL AIR FORCE); it flies on its own 6-DoF (the G550's wing, weights, BR710s and limits; its ceiling fit
  to 51,000 ft) under the autopilot's steer loop, banking 25° in its turns. No free G550 CAEW model was found
  (Sketchfab, FlightGear, CGTrader: only plain Gulfstreams).
- **Air refuelling (2026-11-25, the user: "Air refuelling", "it should be in coms, if available (not for every
  mission) and ask and get approval to start"; [research/air-refuelling.md](research/air-refuelling.md) §8,
  [../../docs/ai.md](../../docs/ai.md) §25):** a KC-46A Gideon or a 707 Re'em (our own models, `tools/tanker/`) on a
  left-hand racetrack at 30,000 ft, on half of Scramble's flights, a mission's `tanker`, or `--tanker kc46|reem`; a
  friendly contact on the radar. The radio menu's Tanker page (only with a tanker): "Request refuelling", then the
  boom operator's clearances; the door (Shift + F1: the F-16's AIR REFUEL switch, the F-35I's door on the PCD's FUEL
  portal), the boom flown into a receptacle held at the contact position, the pilot director lights, the fuel at
  3,000 lb a minute (Re'em 2,000), disconnects on the envelope's limits, A/R DISC (Shift + F2) or full, breakaway;
  the F-16's RDY, AR/NWS and DISC lamps; the external tanks hold their fuel with the door open. The wingmen's
  command "Refuel": each refuels in turn and they rejoin. The AWACS's "Vector to tanker" answers with a tanker in
  the air. The notebook's AIR REFUEL tab (only with a tanker; the user: "the notebook should have air-refuling part
  for checklitst of it"): the jet's refuelling checklist, ticked in flight, the same steps in the jets' manuals
  ([training.md](training.md) §11). `crates/iaf-ai/tests/tanker.rs`, `refuel.rs`, `test_air_refuel.gd`,
  `test_awacs.gd`. Open: the flight controls' gains with the door open, the hose and drogue, the radio-silent
  procedure (research §8.5).
- **Every seat's radio calls whole, Kidon 5–8 voiced (2026-11-25, the game gaps' row 15; [sound.md](sound.md) §3,
  §5.2):** the player's call to a tower ("Hatzerim tower, Kidon 3, request taxi") is one clip as Kidon 1 to 8 (160
  English clips; before, Kidon 2–4 played the address, the callsign and the request apart); the tower's "negative,
  hold position, request … first" is whole in every seat; the callsigns Kidon 5–8 (the formation names Echo,
  Foxtrot, Hotel, India) have their tower, pilot and AWACS particles and the tower's whole calls and heads, English
  and Hebrew. `iaf-sim voices --only` takes several name parts, and a line new in both languages is made by the two
  runs in either order. `test_radio_calls.gd`, `sim::tests` (every seat's particles), `sim_voices::tests`.
- **The F-35I's canopy bow and exterior lights (2026-11-25, the user on Approvals A88 and A90; [cockpit.md](cockpit.md)
  §5.5, [docs/f35i.md](../../docs/f35i.md) §4.1 "Canopy"):** from the seat the raised canopy shows one dark arch, the
  slot between its two transparencies filled with glass (it showed as a bright arch), and since the same day the
  arch's edges clean (the glass drawn as one sheet from the seat, where a faint hairline showed); the Lights Master key (Alt + F6)
  turns the navigation lights and the strobe on and off, and the jet starts with them off; the landing / taxi lamp sits
  on the nose gear's strut. Pictures: `_canopy_shot.gd`, `_lights_shot.gd` (f35i).
- **The controls and lamps that moved only, round two (2026-11-25, the user, 18 Nov: "How much of our controls
  actually controls?"; [cockpit.md](cockpit.md) §5.12):** the F-35I's firing handle ejects with the seat at ARM (three pulls, as the E key; the
  seat at SAFE on a cold jet; the card's two seat items tick from it), LAND/TAXI LIGHTS light the taxi or landing
  light, JETTISON picks ALL / EXT / SEL for EMER JETT, COM A sets the radio's volume, AUTO RECOVERY off silences "Pull
  up", IPP EMER OFF shuts the IPP down, the ENG FIRE push fires the extinguisher, VIDEO BRT / CONT step the helmet's
  picture; the F-16's ANTI SKID, STBY GAINS and AR RDY lights read their systems; the F-16's card checks its speed
  brakes. The status data now count the F-35I 28 works, 4 partly, 20 moves; the F-16 273 works, 13 partly, 29 moves,
  37 lamps lit in the lamp test only, each with the reason it stays so. `test_gap_controls.gd`.
- **The tower's readback and the runway for the wind (2026-11-24, the user, 17 Nov: "also "ramon tower, this is...
  request start" the readback and not only "roger""; 21 Oct: "can we do that the tower will give us the right runway
  for the wind?"; [sound.md](sound.md) §3, [training.md](training.md) §3.3, [../../docs/autopilot.md](../../docs/autopilot.md)
  §2.4):** the player's request is said in full ("Ramon tower, Kidon 1, request start-up", since 12 Nov) and each
  clearance is now read back in the player's voice, the callsign last ("Taxi to runway 25 right, Kidon 1",
  "Holding, Kidon 1"); only the gear advisory keeps "Roger". The take-off clearance gives the wind and the runway
  ("Kidon 1, wind 270 degrees, 10 knots, runway 25 right, cleared for take-off"). A mission's wind of 10–20 kt from more than 90° off
  its runway turns the base to the runway's other end: the tower, the briefing, the Missions screen, the notebook and
  the scoring name that end, the line-up is cleared at the main end's holding point and the jet backtracks; the AI
  flight backtracks in order, each jet holding short while one ahead is on the runway. Every mission is calm now, so
  the turn shows with a wind in a mission's file. Tests: `test_radio_calls.gd`, `test_tower_wind.gd`, `briefing.rs`,
  `training.rs`, `four_ship.rs ground_run_at_ramon_into_the_wind`. The line-up, landing and take-off clearances say
  the wind as "wind 270 degrees, 10 knots".
- **Close up / spread out (2026-11-24, the user, 20 Nov: "we should allow ask for "get closer", which will even lead
  to 10m apart"; [ai-plan.md](ai-plan.md) F4, F5; [../../docs/ai.md](../../docs/ai.md) §8.7):** the radio menu's
  Formation page has a Spacing page: Close up takes the close shapes from 60 m between the slots to 30 m, then to 12 m
  (the parade position: 2 m between an F-16's wingtips); Spread out goes back one step. The command and each wingman's
  answer are said with subtitles, English and Hebrew; "unable" past the last step, in line abreast or trail. Close up,
  the wingmen roll with the lead and use a quicker throttle, and the pull-away's distances shrink with the spacing:
  in the Rust test the tight slots held within 2 m level, no two jets nearer than 16.8 m (`four_ship.rs
  close_up_and_spread_out`; `test_four_ship.gd`'s spacing phase drives the menu). When the lead banks past 35°, rolls
  faster than 20°/s or pulls more than 1.5 g, the tight flight moves out to 30 m on its own (the parade's lead turns
  at 30° of bank; harder, the formation flies cruise) and closes back up 5 s after; in a sharp break the wingmen keep
  15 m from each other (`four_ship.rs tight_flight_loosens_in_a_sharp_roll`).
- **The combat logbook (2026-11-24, the user, 23 Nov: "Is the pilot logs count kills/targets destroyed/lost?"; the
  round-2 mock approved on A79 with his answers of 24 Nov; [storage.md](storage.md) §5, [front-end.md](front-end.md)
  §3 and §13):** each scored flight counts its combat from its recording in Rust (`crates/iaf-tools/src/combat_log.rs`):
  air kills by type with the shared ones, ground targets by type, each weapon's releases and hits (the gun's rounds
  apart), the jets lost by cause (the player's and the flight's other jets together; ejections apart). The records
  keep it per sortie (schema version 8, older sorties without one). The Pilot screen's logbook shows four totals of
  every flight and More stats / "סטטיסטיקה מפורטת"; a combat flight's debrief shows its four totals and its More
  stats. The weapons' verbs are the user's (missiles שוגרו, bombs הוטלו, the gun נורו). The same change makes the
  Pilot screen's form narrower with Choose a picture… as the picture's bottom (the user, 24 Nov), and the logbook
  counts "1 flight" / "טיסה אחת" in the singular. Tests: `cargo test -p iaf-tools --lib combat_log pilot_log`,
  `modern-iaf/tests/test_combat_log.gd` (the events from a flight), `test_combat_screens.gd` (the screens, en + he).
  The unit names in Hebrew (משגר S-300, מכ"ם גילוי S-300, גרוטת F-16 …) are ours: the system names as Israeli press
  writes them with the Hebrew noun for the vehicle; open: an IAF source for each.
- **The big fight (2026-11-23, the user, 22 Nov: "If possible create a video of your multiplabes multi sam etc
  dogfight?"; [ai-plan.md](ai-plan.md) K12, X5; [../../docs/ai.md](../../docs/ai.md) §22):** one dev-hook scenario
  with everything at once. Our four-ship flies low and gets the sort, weapons free and a ground attack. It faces a MiG-29A pair on
  CAP and a pair that scrambles from a base, the S-300 network with a Tor and a ZSU, a convoy on the road and four
  Shahed-136s. The headless test `modern-iaf/tests/test_big_fight.gd` passes: missiles fly both ways, MiGs and
  vehicles go down, no jet hits the ground, none is stuck. Profiled and fixed (23 Nov): the frame's CPU time fell
  from 24.3 to 15.2 ms on the Iris Xe, inside a 60 fps frame, at 0.38 ms per AI jet. A movie script films the fight
  (`_big_fight_movie.gd`). No mission places it.
- **The target drones on Modern IAF's AI (2026-11-23, the user, 22 Nov: "Ok follow your suggested order";
  [ai-plan.md](ai-plan.md) C4; [../../docs/ai.md](../../docs/ai.md) §21):** the weapons range's drones decide in Rust
  (`iaf_ai::target`, gdext `IafTargetDrone`) in place of the 1998 brain: each by its brain record's kind, every 3 s,
  flies its route, keeps its radar's lock on the best air contact (Drones 4), or breaks 90° or runs from a fighter
  inside 9 km (Drone 3); none shoots. The intercept lesson's drone is the route kind, non-manoeuvring. What the
  player sees is unchanged: a decision every 3 s, the brain's at the Normal AI level Modern IAF keeps. The 1998 game
  keeps its brain. Checked by `crates/iaf-ai/tests/target_drones.rs` and `modern-iaf/tests/test_sim_range.gd`.
- **The flight lands in order, the pairs line up 15 m apart (2026-11-23; [ai-plan.md](ai-plan.md) F3, F7;
  [../../docs/ai.md](../../docs/ai.md) §8.7):** going home, each wingman keeps at least 30 s behind the one sent home
  before it, slowing until the turn to final: Kidon 1-4, sent 20 s after 1-3 and faster on the circuit, had landed
  first. They now land 26-57 s apart. A pairs wingman steers onto its line on the leg to the lineup and lines up 15 m beside its lead
  (it had rolled 9.6 m beside it at Nevatim, the wings 0.2 m apart). Tests: `four_ship` (`ground_run_*`,
  `taxi_in_behind_a_stopped_lead`, `pairs_take_off_*`, `a_lead_landing_away_from_home`).
- **Low level and ground collision avoidance (2026-11-23, the user, 22 Nov: "Ok follow your suggested order", which
  named the AI's terrain following for attack runs; [ai-plan.md](ai-plan.md) K17; [../../docs/ai.md](../../docs/ai.md)
  §20):** every AI jet, ours and the enemy's, predicts a fly-up (a roll to wings level and 5 g, as the F-16's Auto
  GCAS) and flies it before it would come within 30 m of the terrain, in every mode but the take-off and the landing.
  A flight ordered low (150 to 500 ft; the dev hook `ai_flights.gd flight_low`) follows the terrain 10 s ahead, and
  its bomb runs come in low and pop up into the dive 4 nm out. A SAM site's move to its next position keeps to the
  roads. The lead orders the low level (300 ft) and its end from the radio menu's flight page or with `Ctrl + \` (record
  257); each wingman acknowledges. Tests `crates/iaf-ai/tests/lowlevel.rs`, `modern-iaf/tests/test_low_level.gd`. No
  mission sets the low level yet.
- **Release bundles, the nightly (2026-11-23, the user: "Have only the nightly builds";
  [../../docs/release.md](../../docs/release.md)):** each day `main` changed, the Nightly workflow builds both games
  for Linux, macOS (Apple silicon, unsigned) and Windows and replaces the `nightly` pre-release. The game opens its
  setup wizard while its data is missing and with `--setup`; the data goes to a per-user folder (shown on the wizard's
  first page, Change… picks another), so an update keeps it. Version `0.2.0-nightly.<date>+<hash>` under the
  Attributions screen's title, `dev` in the checkout. The bundle carries GDAL and curl for setup (`tools/`,
  conda-forge's builds), so a player installs nothing.
- **Updates on start (2026-11-24, the user: "auto update on startup for released assests", "same for setup";
  [../../docs/release.md](../../docs/release.md) §7):** the bundle offers a newer nightly (download, size and SHA-256
  check, swap with the old version kept until the new one starts, rollback); the bundle and `./start-modern-iaf` offer
  the setup steps whose stamps no longer hold and run them in the wizard. A dialog asks (a click outside is Later;
  Don't ask me again); Settings → Updates: Ask / Always download / Never (2026-11-25).
- **The lead assigns targets (2026-11-23, the user, 22 Nov: "The leader (on our side) should assign targets to the
  other pair and to their wingman"; [ai-plan.md](ai-plan.md) F5; [../../docs/ai.md](../../docs/ai.md) §8.11):** with
  no order the wingmen keep their slots, call each new radar contact and fight only a jet that attacks them. Engage my
  target names one bandit per jet or element (lock it, then the command). Sort (the radio menu, Alt + W) shares the
  bandits the flight sees out between the pairs and their jets, by side or by range (NATO GROUP, AZIMUTH, RANGE):
  #3 calls "targeted" and attacks, #2 and #4 hold their fire until their leader shoots or a threat is on them.
  Weapons free (the radio menu, `Alt + \`) sends the jets hunting round the SPI until joker fuel or rejoin. Cover me
  (Alt + P to Kidon 1-2) now fights a jet that attacks the lead, not any jet near it. Enemy pairs sort by the same
  rule, so two MiGs take two of our jets. The voices of "sort", "weapons free" and "targeted" come from `iaf-sim
  voices`. Tests: `crates/iaf-ai/tests/wing_battle.rs`, `crates/iaf-ai/src/sort.rs`,
  `modern-iaf/tests/test_target_assign.gd`.
- **Moving ground vehicles (2026-11-23, the user, 22 Nov: "Ok follow your suggested order", which named "ground
  units that move: convoys on roads; ground attack needs moving targets"; [ai-plan.md](ai-plan.md) K16;
  [../../docs/ai.md](../../docs/ai.md) §19):** a convoy of T-72s and Ural-4320s drives as one column on
  OpenStreetMap's roads (across country where no road serves), 100 m apart, at its slowest vehicle's march speed for
  road or open ground, on the terrain under it (its ground kept far from the player). A blast within 500 m (a bomb, a
  missile, rockets, gun rounds) scatters it off the road; 60 s after the last one the survivors drive back onto the
  route and on. The AI jets' attack leads a moving vehicle. The dev hook `shared/ai/convoys.gd spawn`; tests
  `crates/iaf-ai/tests/convoy.rs`, `modern-iaf/tests/test_convoy.gd`. No mission places one; the models have no wheel
  or track nodes, so nothing turns.
- **The flight's landing and the take-off in pairs (2026-11-22, the user: "Finish landing"; [ai-plan.md](ai-plan.md)
  F3, F7; [../../docs/ai.md](../../docs/ai.md) §8.7):** the wingmen go home one by one after the lead, each on the
  circuit; the tower clears each to land on its turn to final and sends it to parking after its roll ("Kidon 1-2,
  cleared to land runway 25 right"; "Kidon 1-2, welcome back, taxi to parking"), each answering with its callsign.
  Taxiing in, an AI jet holds for a jet of the flight in its way, and every AI jet slows before a taxi turn: at Nevatim
  #4 no longer swings into #2's spot (1 m, now 44 m at the least). The take-off in pairs (a dev hook, `ai_flights.gd
  flight_pairs`; no mission sets it): #2 beside #1 and #4 beside #3, each pair rolling and lifting off together; every
  AI jet's roll holds the runway's heading. Enemy flights land and space their taxi the same way, without the tower's
  calls, and take off in a stream. Tests: `four_ship` (`ground_run_*`, `taxi_in_behind_a_stopped_lead`, `pairs_take_off_*`),
  `modern-iaf/tests/test_four_ship.gd`, `modern-iaf/tests/test_pairs_takeoff.gd`.
- **The AI jets' air-to-ground attack (2026-11-23, the user, 22 Nov: "We don't have bomb release yet? So this is
  missing in ai, no?", "Both for enemies and wingman"; [ai-plan.md](ai-plan.md) F15, K15;
  [../../docs/ai.md](../../docs/ai.md) §8.10):** "engage my target" (the radio menu; Alt + E to Kidon 1-2) with no
  aircraft locked attacks the player's ground target (the radar's locked ground unit, else the one nearest the SPI,
  else the SPI; no SPI: "unable"): each wingman with bombs in turn, a 30° dive for plain bombs, a level run for
  guided ones, the release by the CCIP's vacuum impact through combat.gd's AI ripple, the egress and the rejoin; calls in / נכנס, bombs away /
  אלפא, done / ביצעתי. A new order from the lead (engage my target again, cover me, split, rejoin, RTB) ends the
  attack at once and is obeyed. An enemy pair attacks on its lead's own order (the dev hook `ai_flights.gd enemy_strike`, a
  target unit or a base's point; a MiG-29A with MK-83s standing in for its FAB-500s by `spawn`'s `arm`). Tests:
  `crates/iaf-ai/tests/strike.rs`, `modern-iaf/tests/test_ground_attack.gd`. No mission orders one; the pop-up
  attack waits for the AI's low-level flight.
- **Our wingmen in a fight (2026-11-22, the user: "Finish wingman in battle"; [ai-plan.md](ai-plan.md) F5, K4;
  [../../docs/ai.md](../../docs/ai.md) §8.9):** a wingman told "engage my target" fights it with the enemy fighters'
  leaves: the collision course, a missile inside its share of the envelope, the crank, the BFM leaf and the gun, the
  fighters' defence (a lock called, the attack goes on; a missile notched or broken with chaff or flares). "Cover me"
  (the radio menu) keeps it in its slot until a jet attacks the lead (since 23 Nov; before, any hostile jet within
  37 km of the lead); a jet attacking a wingman is fought uncommanded. Calls: engaged, Fox 1 / 2 / 3, guns, splash, winchester (voices from `iaf-sim voices`). Tests:
  `crates/iaf-ai/tests/wing_battle.rs`, `modern-iaf/tests/test_wing_battle.gd` (the four-ship put in the air by the
  dev hook `ai_flights.gd flight_in_air` against a MiG-29A pair). No mission places the enemy.
- **Countermeasures and jamming (2026-11-22, the user: "Yes start whatever you didn't finished"; [ai-plan.md](ai-plan.md)
  K8, K9; [../../docs/real-weapons.md](../../docs/real-weapons.md) §2.3, [../../docs/ai.md](../../docs/ai.md)
  §15.6):** flares and chaff act on each missile's own seeker (its record's rejection, the beam for chaff, the time to
  go, the afterburner, the g), for the player and every AI jet; the AI jets release them at a missile's launch cue and
  within 6 s of its arriving, none against a lock. The Sufa's jammer (J) holds the enemy's site, network and fighter radars to its
  burn-through; an AI jet with a jammer in its definition (the Sufa wingmen) jams under a lock or a missile, not on
  the commit alone, and an enemy fighter's radar flies at its strobe (home on jam) to the burn-through; an enemy jet
  with one would jam the player's radar (the MiG-29A (9.12) has none: its jammer came with the 9.13); the threat
  display's chevrons and the FCR's and PCD's jam strobe. Tests: `ecm.rs`, `sites`, `intercept`, `four_ship`,
  `modern-iaf/tests/test_countermeasures.gd`. Built 25 Nov: the jammer against a radar missile's own seeker: outside
  the seeker's burn-through each missile at the jamming jet rolls once on 0.6 · (1 − its rejection) and loses its
  guidance when taken ([../../docs/real-weapons.md](../../docs/real-weapons.md) §2.6;
  `modern-iaf/tests/test_threat_missiles.gd`). Not started: the Barak's jammer
  (open).
- **Shoulder-fired SAMs (2026-11-23, the user, 22 Nov: "Ok follow your suggested order"; [ai-plan.md](ai-plan.md) K16;
  [../../docs/ai.md](../../docs/ai.md) §15.8):** a Strela-2M or an Igla team (`air_defence.gd spawn("strela" |
  "igla", …)`) sees a low jet by eye to 10 km, launches after its crew's reaction and drill once the jet is inside
  its envelope and its seeker has it (the Strela only at a jet's tail), two rounds, shoot-look-shoot. Nothing shows on
  the RWR; the Sufa's MAW warns "SAM". A flare takes the Strela's seeker one time in two, the Igla's one in five
  (inferred). Drawn as a stand-in figure (no model on disk). `crates/iaf-ai/tests/sites.rs`,
  `modern-iaf/tests/test_manpads.gd`; no mission places one.
- **Enemy scramble from a base and the Tor's moving parts (2026-11-22, the user, 22 Nov: "Yes start whatever you
  didn't finished"; [ai-plan.md](ai-plan.md) K3; [../../docs/ai.md](../../docs/ai.md) §18.3, §15.4):** an enemy pair
  parked in a base's shelters, engines off, starts on the S-300 network's vector after the lead's reaction time, taxies
  and takes off by the autopilot's ground loops, intercepts, and after the sortie goes home, lands and parks in its
  shelters (`crates/iaf-ai/tests/scramble.rs`, `modern-iaf/tests/test_enemy_scramble.gd` through the dev hook
  `ai_flights.gd` `enemy_base`). The sim has no enemy base, so any base stands in by the hook's argument; no mission
  places one. The Tor-M1's search radar turns while it searches, its turret and tracking radar lay on the track and its
  cell covers open at a launch (`modern-iaf/tests/test_enemy_sites.gd`). Every AI jet has its ground wherever the
  player is, flares over the runway's height with a lead on its sink and ends GoHome when it passes near its waypoint
  ([../../docs/ai.md](../../docs/ai.md) §18.4; `crates/iaf-ai/tests/landing.rs`, `modern-iaf/tests/test_ai_far_landing.gd`).
- **Enemy fighter step 3: the dogfight (2026-11-22, the user, 21 Nov: "Ok finish all enemies things you can",
  "Ok, do it"; [ai-plan.md](ai-plan.md) K4, X4, X5; [../../docs/ai.md](../../docs/ai.md) §18.2):** inside 6 km of a
  hostile jet it sees, a committed MiG-29A flies an energy-aware BFM leaf: pursuit (lead, pure, lag) and the yo-yos when
  offensive, the break or the guns jink when defensive, the rate, radius or vertical fight when neutral, picked by its
  skill's tactics and its own turn from the 6-DoF (the corner speed), the energy heights and the bogey's turn as seen;
  it fires its 30 mm through combat.gd with its skill's laying error. A High MiG beats a Low one from head-on passes
  (`crates/iaf-ai/tests/dogfight.rs`, `modern-iaf/tests/test_dogfight.gd` through the dev hook `enemy_flight`). No
  mission places one. CPU: 4.1–7.8 µs per jet per frame for the Rust part on the build Mac, 0.16–0.18 ms per AI jet per frame on the laptop. Our
  wingmen fly it too (the entry above). Fixed the same day: a level hard turn holds its height within 30 m (the fighter's
  turn laws: an 85° bank, a fast roll-in, the lift upward held; it climbed up to 1.6 km in 12 s), and behind a jet
  flying straight it controls its closure (throttle, speed brake) and settles 480 m behind instead of passing it.
- **Enemy fighter step 2: the intercept (2026-11-22, the user, 21 Nov: "Ok finish all enemies things you can", "Ok, do
  it"; [ai-plan.md](ai-plan.md) K3, X4, X5; [../../docs/ai.md](../../docs/ai.md) §18.1):** an enemy pair of MiG-29As on
  a CAP orbit or started in the air is vectored by the S-300 network's 64N6E2 and 54K6E2 onto a hostile jet; it commits
  after the lead's reaction time, flies a collision course, shoots an R-27R or R-73 inside its skill's share of the DLZ
  after its reaction time through combat.gd's launch, cranks, and defends against a missile by its tactics (beam, notch,
  drag, break) with chaff or flares (`crates/iaf-ai/tests/intercept.rs`, `modern-iaf/tests/test_intercept.gd` through
  the dev hook `ai_flights.gd` `enemy_flight`). No mission places one. CPU: about 3.9 µs per jet per frame for the Rust
  part on the build Mac, 0.17 ms per AI jet per frame on the laptop (with the scripted jet and the network).
- **Enemy fighter step 1: the MiG-29A flies (2026-11-22, the user, 21 Nov: "Ok finish all enemies things you can",
  "Ok, do it"; [ai-plan.md](ai-plan.md) K2, X2; [../../docs/ai.md](../../docs/ai.md) §18):** the MiG-29A is an AI type
  of its own aircraft definition (type 1020). Its 6-DoF set is TP-1538's tables on its wing with its masses, RD-33s and
  limits ([flight-model.md](flight-model.md) §9.21): Mach 1.24 at sea level and 2.30 at 40,000 ft (fit), 9.3 g, α 24–25°
  at full pull, a 280 m/s climb against the published 330. Its record and its 30 mm, R-73 and R-27R records are
  approved; it is drawn with our MiG-29 model. A four-ship of them starts up, takes off, flies the route, lands and
  parks at Ramon in the Rust test, about 4.2 µs per jet per frame on the build Mac (0.149 ms with its model and sound on the laptop); one takes off, flies its route and
  lands in the headless game (`modern-iaf/tests/test_mig29.gd`, the dev hook `ai_flights.gd` `spawn`). No mission
  places one. Open: its ceiling runs high (every 6-DoF jet's does: no thrust lapse figure for the engines aloft), its roll rate (a forum's 160 deg/s with no source named, not used; searched 2026-11-25) and gear geometry (no public figure).
- **Enemy models (2026-11-22, the user's downloads of 22 Nov; [../../docs/ai.md](../../docs/ai.md) §15.4, §16.4;
  [../../docs/credits.md](../../docs/credits.md) § Model credits):** seven CC BY 4.0 Sketchfab models, made once by
  `tools/enemy_models/convert.py` and committed under `shared/extra/models/<id>/` (setup needs no login), true size:
  the S-300 launcher, the 30N6E on its 40V6M tower (a site spawned with `mast`), the Tor-M1, the ZSU-23-4, the
  Shahed-136, the T-72 and the Ural-4320. The sites and drones draw them by placed name (`Gltf.UNITS`); the Ural
  stands in for the network's 54K6E2 command post. Two ground-target records, `target_t72` and `target_ural`
  (`modern-iaf/data/db/units`, no mission places them yet). About 13 MB together. The 64N6E2 and 96L6E search radars
  and the 30N6E2 on its truck (2026-11-23, the user 22 Nov: "No, don't leave it open. Finish to the end") are our own
  low-poly radars (`tools/enemy_models/radars.py`), since 2026-11-24 on the MAZ-543 chassis of a CC BY 4.0 Sketchfab
  model, its missile and launcher cut off, repainted olive (the user, 24 Nov: "don't forget to add credits"; about
  0.9 MB each): the search radars' antennas turn while they radiate, the 30N6E2's
  lays on its track (`modern-iaf/tests/test_sam_net.gd`). The models stand in their rest pose (the S-300's canisters
  down).
- **Ground clutter for the radars (2026-11-21, the user: "Ok finish all enemies things you can";
  [ai-plan.md](ai-plan.md) K14, K5; [../../docs/radar.md](../../docs/radar.md) §9.8,
  [../../docs/ai.md](../../docs/ai.md) §15.3):** the Sufa's and the Adir's pulse-Doppler radars lose a target in
  look-down whose speed along the line of sight is under CNTL's MTR (60 kt LO, 100 kt HI; inferred): a jet on the beam
  drops off the scope and an STT lock on it breaks; a drone at 180 km/h is found at MTR LO only within about 50° of
  its nose or tail, at MTR HI not at all. Look-up is unchanged; the 1998 game's radar has no such rule. The Tor's
  pulse-Doppler radars lose a jet slower than 30 m/s along the line of sight (the wingmen's beam now breaks its
  track); the ZSU's radar loses a jet under 60 m and lays optically. The FCR page draws its contacts as symbols and
  no clutter: no source shows ground clutter on the air-to-air format (searched 25 Nov). Since 2026-11-25 the
  S-300's radars lose a jet slower than 30 m/s along the line of sight (the 96L6E's published Doppler speeds; the
  30N6E2's taken as its, inferred).
- **The AI fighters' radar sees stealth, clutter and terrain (2026-11-25, the user, 19 Nov: "They should take into
  consideration the stealth of the adir", "Also terrain shape"; [ai-plan.md](ai-plan.md) K3;
  [../../docs/ai.md](../../docs/ai.md) §18.1):** every AI jet's radar, the enemy fighters' and the wingmen's, takes
  the sites' rule: the reach for the target's cross-section seen from it (the clean Adir held head on inside 9.7 km,
  50 km with its bays open; the clean Sufa 52 km; against 74 km before), terrain sight over the earth's curvature,
  and in look-down the loss of a jet slower than 30 m/s along the line of sight (inferred). An enemy fighter shoots
  only once its radar holds the jet.
- **Enemy skill (2026-11-21, the user, 19 Nov: "wingman are always the same, it only effect enemeis, choosen from 3
  options per player"; 21 Nov: "Ok finish all enemies things you can"; [ai-plan.md](ai-plan.md) X4;
  [../../docs/ai.md](../../docs/ai.md) §17):** three levels, Low / Medium / High ("נמוכה / בינונית / גבוהה"), picked per
  pilot on the Pilot screen and stored with the pilot (Medium by default, old records too). `iaf_ai::Skill` holds the
  reaction, the drills' share, the gun's laying error and the launch range. The air-defence crews take the pilot's
  level: Low answers in 3 s with drills 1.5 times as long, lays its guns at 8 mrad and fires at the envelope's edge;
  High answers in 0.5 s, drills in three quarters of the time, lays at 2 mrad and holds fire to 80 % of the range. The
  radars, missiles and rounds are the same at every level; the wingmen stay at Medium. The drones fly a programmed
  route and take none. Checked by `cargo test -p iaf-ai --test sites skill`.
- **The voice cast (2026-11-25, the user: "for each mission, the voices not switched in the middle"; [sound.md](sound.md)
  §3.2):** the player's own radio voice is picked per pilot on the Pilot screen (Man / Woman, a man's by default; in
  English `am_puck` or `af_sarah`, in Hebrew `ariel` or `shira`); the flight's cast is drawn once per mission among
  the casts with that voice, so the tower, the AWACS, each wingman and another flight's member keep one voice for the
  whole mission and no wingman speaks in the player's. The friendly-fire calls are the wingman's voice in both
  languages, "Eject, eject, eject!" the player's. One rule for every role (`sound_table.gd` `cast_voice`), a new role
  (the boom operator) one key of the casts; `test_voice_cast.gd`.
- **Enemy AI step 3: the SAM network (2026-11-21, the user: "Ok finish all enemies things you can";
  [ai-plan.md](ai-plan.md) K6; [../../docs/ai.md](../../docs/ai.md) §15.5):** an S-300 regiment's search radar (the
  64N6E2, 300 km, a sweep every 12 s) and command post (the 54K6E2) run the sites together. The post fuses the radar's
  picture with the sites' own tracks and cues one site's track radar onto each jet, the site that can fire first, while
  the sites' own search radars stay off; a jet leaving one site's envelope goes to the next. The threat display hears
  the search radar, then only the engaging site's lock. With the radar or the post destroyed every site fights alone
  again. No mission places one: the dev hook (`AirDefence.spawn_net`) and the tests (`crates/iaf-ai/tests/net.rs`,
  `modern-iaf/tests/test_sam_net.gd`).
- **Enemy AI step 2: the one-way attack drones (2026-11-19, the user: "we need to have the code for ai enemies. Just
  isn't reachable by mission yet"; Epic Fury's air threats are drones of the Shahed-136 class; [ai-plan.md](ai-plan.md)
  K14; [../../docs/ai.md](../../docs/ai.md) §16):** a salvo of drones launched one after another flies a route of
  waypoints in Rust (`iaf_ai::drone`): 180 km/h, 500 m above the terrain within the published 60–4,000 m band, turns,
  climbs and sinks within inferred limits, then dives at 40° onto its end point, where it explodes and is removed (its
  damage there comes with the mission work). A point mass: the type has no 6-DoF data (open). The player's radar finds
  one by its cross-section (0.01 m², the one published estimate): the Sufa's TWS at about 9.5 NM instead of 45 NM, and
  the terrain hides it; the data link lists it as hostile; the gun and the missiles bring it down through the existing
  damage path; it does not shoot. The shape is our own stand-in. No mission launches one: a dev hook
  (`shared/ai/drones.gd`) and the tests (`crates/iaf-ai/tests/drones.rs`, `modern-iaf/tests/test_enemy_drones.gd`).
  Later: enemy-fighter BFM (K4), listed only.
- **Enemy AI step 1: the air-defence sites (2026-11-19, the user: "we need to have the code for ai enemies. Just isn't
  reachable by mission yet", "They should take into consideration the stealth of the adir", "Also terrain shape etc.";
  [ai-plan.md](ai-plan.md) K5, K7; [../../docs/ai.md](../../docs/ai.md) §15):** the S-300PMU-2 battery (96L6E search,
  30N6E2 track, four launchers of four), the Tor-M1 and the ZSU-23-4 run their crews' procedure in Rust (`iaf_ai::site`):
  search, acquisition, track (a lock on the RWR), two missiles per target 3 s (S-300) or 4 s (the Tor, at a halt) apart,
  six or two targets at once, shoot-look-shoot; EMCON radiate / silent / cue; relocation after the engagement; the Tor's
  duty limits; the ZSU's radar or optical laying and bursts on the move. Detection and track ranges follow the jet's
  radar cross-section (the new `rcs` on each aircraft definition: the clean Adir is found head on at about a fifth of an
  F-16's range; its open bays or external stores bring it back) and need sight over the terrain and the earth's
  curvature. They fire the existing missile and gun-round models with the AIM-120's and the 20 mm's records standing
  in; the shapes are our own stand-ins. The threat display now lists the radars searching the jet. No mission places a
  site: a dev hook (`shared/ai/air_defence.gd`) and the tests (`crates/iaf-ai/tests/sites.rs`,
  `modern-iaf/tests/test_enemy_sites.gd`). Later: the sites' own records.
- **Modern IAF in the applications menu (2026-11-19, the user: "also as game icon in windows/linux/mac? deskop files
  etc?"; [setup.md](setup.md) "Applications menu"):** the setup wizard's Done page has the tick "Add Modern IAF to
  the applications menu" (the Start menu on Windows, the Applications folder on macOS), on by default. It adds "Modern
  IAF" and "Modern IAF — Setup" with the app icon: on Linux `.desktop` files (Hebrew name הזרוע הארוכה) and the icon in
  the user's hicolor theme, on macOS app bundles in `~/Applications` (the Dock shows the icon from the start), on
  Windows Start Menu shortcuts with `icon.ico`. Unticking removes them; the choice is remembered. `logo.py` also writes
  `icon.ico`, `icon.icns` and the 24 and 48 px PNGs. One script per system for both games
  (`tools/install-launcher.sh`, `tools/windows/install-launcher.ps1`, now with `modern-iaf` and a remove switch). Tested
  on Linux (headless wizard test, `desktop-file-validate`, the entry and its icon found by GLib / GTK) and on the Mac
  (a bundle in a temporary folder); Windows is the user's test.
- **The logo (2026-11-19, the user on Approvals A67: "e3 is selected. apply it everywhere"; [front-end.md](front-end.md)
  §4):** concept 4, the four-ship, with the medium faint roundel behind it, in `modern-iaf/branding/` (SVG masters, the
  lockups' PNGs, the app icon at 1024 to 16 px; `tools/iaf-2026/logo.py`). Its horizontal lockup (the mark beside
  the name in one line) is the front end's top bar (every screen), the pause menu's and the Mission accomplished
  panel's head and the setup wizard's top bar; the stacked lockup is on the manuals' title pages and the READMEs; the
  four-ship on the navy tile is the project's window and Dock icon. Hebrew screens and the Hebrew game manual show the
  Hebrew name. Its F-35 outline is traced from the F-35I model: the F-35I credit carries it
  (docs/credits.md "Modern IAF's logo"). The desktop launchers with the icon came the same day (above).
- **The F-16s' night-vision goggles (2026-11-19, the user on Approvals A66: "night googles: as suggested";
  [research/nvg.md](research/nvg.md) options O1–O4, [cockpit.md](cockpit.md) §5.5):** in the Sufa and the Barak
  Shift + N (record 255, command 303) flips the goggles down and up, at any height; down, the late Gen III tubes'
  picture ([../../docs/rendering.md](../../docs/rendering.md) §8) fills a round field 40° across, fixed to the head in
  the view's upper part; below it the pilot sees the panel in its own night lighting with the naked eye (the user's
  "fix", 19 Nov: the picture had covered the whole screen, the 3D cockpit too). The lighting panel's NVIS / NORMAL
  switch keeps the cockpit's own light out of the tubes at NVIS and lights the cockpit NVIS Green A (MIL-STD-3009); at
  NORMAL it glares and washes out the field's lower part. By day the field washes out bright, soft and pale (since 25
  Nov, the user on Approvals A87: "it should be bright, not dark"; rendering.md §8.3). While they are down the helmet display shows no symbols. The F-35I has none (a notice): its helmet keeps the
  night camera (Alt + F7). Also fixed: the HMCS SYM INT knob at OFF now darkens the helmet display with the Real HUD
  (its symbols drew on). Not started (the user's pick): the exterior lights' covert mode (with the AI wingmen), white
  phosphor, ejection with goggles. Tests: `nvg.rs`, `real_hud::tests::the_helmet_display_is_dark_with_the_hmcs_off_or_the_goggles_down`,
  `test_cockpit_lights.gd` (the field, NVIS green), `test_sim_adir_pcd.gd`.
- **The missile warning's type (2026-11-19, missile step 4, avionics-plan.md E1, E2, E5 and §7.2; [ews.md](ews.md) §2,
  §3; the research, the F-15s' included, in [research/missile-warning.md](research/missile-warning.md)); a visible
  change on `wt/missile-warning`, awaiting the user's approval:** the RWR names a radar-guided missile by its launcher's
  radar (its symbol in the launch circle) and no longer hears an infrared one (no circle, launch lamp, tone or CMDS
  start from the RWR); the MAW (the Sufa's PAWS, the Adir's DAS) warns of every missile with its class and seconds,
  "AAM 12" or "SAM 12", on the RWR scope, the TWD, the DAS format and the Adir's helmet, its launch tone also for an
  infrared missile; the Barak gets no warning of an infrared missile. Tests: `rwr.rs`, `ews.rs`, `real_hud/f35.rs`,
  `test_sim_ews.gd`.
- **The Barak's own HUD (2026-11-19, the user's "on it's own", avionics-plan.md B9):** the Barak's 3D cockpit shows the
  F-16C/D's combiner, two slender grey posts joined by an arched bar, untinted (`hud_3d` "HUD_arch", its own node in
  `f16.glb`; the original game keeps the Block 50 frame), in place of the Sufa's wide-angle plate it drew from 17 Nov;
  the symbols on it are the Sufa's Real HUD, in a field narrowed to fit the glass (cockpit.md §4). The Block 40 came with
  the LANTIRN diffractive HUD; Barak 2020's new HUD is not named or pictured in public, so the frame is matched to the
  US Air Force's front-seat photo of a colour-display F-16C from that photo's fitted camera (its depth inferred).
  `test_sim_mfd.gd` checks each F-16's HUD node and, with `test_sim_missiles.gd`, that the combiner holds the field and
  every Real HUD symbol, in `test_sim_mfd.gd` also with every readout at its widest, in the project's window size: the
  Barak's field ±4.8°, the Sufa's ±6.0° (since 2026-11-20, the user's "Do the fix": the right data column was moved
  under the altitude scale, as in the dash-34, and the fields widened by the inset that freed; ±4.0° and ±5.6° before).
  Since 2026-11-20 ALT AUTO's `AR` box sits on the thermometer's index, off the right column. The lower data block
  is centred: the two data columns sit symmetric about the HUD centre (cockpit.json `DataColumns`: Sufa ±66 px, about
  the real place; Barak ±47 px, as far out as its glass holds the widest row), and the roll indicator has its real
  70 mr radius on both jets, clear of the columns (docs/real-hud.md "Data windows", "Scales";
  `real_hud::f16::tests::ar_and_the_roll_tics_stay_off_the_text`). Before, the block was off-centre and the arc was
  shrunk to clear the right column. The F-16D manual's HUD pictures show its
  own frame. Open: the new HUD's maker, field of view and look.
- **Real missile performance, the core (2026-11-19, the user's "ok so finish the missile works", avionics-plan.md
  §7):** the AIM-9M, AIM-9X, Python 5 and AIM-120 fly a physical missile: the motor's real thrust and burn, drag by Mach
  and height, gravity, proportional navigation within the g limit, turns bleeding speed, the flight's end when too
  slow; the DLZ, the AI's launch range and the post-launch times from the same fly-out
  ([../../docs/real-weapons.md](../../docs/real-weapons.md) §2.1). Next steps 1–5 (seekers in flight, loft, fuzes, the
  missile warning's type, the threat missiles) in avionics-plan.md §7.2. Tests: `missile.rs`, `test_sim_missiles.gd`.
  Step 1 the same day: the seekers in flight (a target outside the cone is lost) and the AIM-120's data link until its
  seeker goes active (real-weapons.md §2.2); the AIM-9X's thrust-vectored turn no longer brakes it to a stop, and the
  guidance acts across the missile's velocity, so the 70° off-boresight shot hits. The burst is the same at any frame
  rate: the closest pass of the missile and the moving target over each step (real-weapons.md §2.1).
  Steps 2 and 3 (23 Nov): the AIM-120 lofts on long shots, the enemy SAM sites' then stand-in too (real-weapons.md §2.4):
  6,000 m up its zone grows from 36 to 50 km at a still target and from 56 to 86 km head on; the AIM-9X's thrust
  vectoring adds the motor's thrust to its fins' turn. Each physical missile's proximity fuze fires only within its
  blast radius, past a wider pass it self-destructs, and a hit before it arms is a dud (§2.5).
- **No band line for a change the cockpit shows (2026-11-19, the user's "Do it"):** the master arm switch, the
  helmet's picture, the DGFT / MSL OVRD switch, LASER ARM, DL, ADV MODE, the fuel switches, IFF IDENT, the bay doors,
  the bombs' submode, fuze and delay, PRE / VIS, SPOT / SCAN and the autopilot (its switches, a refused PITCH
  switch, TRIM/AP DISC and FLCS RESET, since 2026-11-25) put no line in the top strip;
  the radio lines and the lines with no cockpit sign stay ([front-end.md](front-end.md) §8 lists each). The original
  game keeps its console lines. Tests `test_sim_adir_pcd.gd`, `tests/godot/test_cockpit_notes.gd`.
- **The Adir's DAS picture and FLC (2026-11-19, avionics-plan.md slice 7 parts D and E, P9, P12, G35):** the DAS
  format shows the forward aperture's picture, grey, from a camera on the nose that renders only while the format is
  drawn; in the helmet Alt + F7 steps the night camera, the DAS's video and off (the pilot picks one, as the AFI
  says). The throttle's FLC turned (Alt + F9 / F10) steps the cursor portal's format, pushed (Alt + F8) steps the
  TSD's layers (all, without the map and route, the tracks only; inferred from the switch's name). Keys records
  251–254 ([../../docs/f35i.md](../../docs/f35i.md) §4.3). Rust test `pcd::tests::flc_turns_formats_and_steps_the_tsd_layers`.
  Open: the per-bomb PRE pick on the briefing map (part F, G4) waits for the user's yes.
- **The Adir's panoramic display and stores (2026-11-19, avionics-plan.md slice 7 part C, P1, P3, P4, P6–P11, S13,
  S15, N8; G16, G29, G34):** the pilot lays out the display ([../../docs/f35i.md](../../docs/f35i.md) §4.3): the MENU
  grid's 20 formats, widening a portal over its half, enlarging it over its windows, a window or tab into its portal,
  the five presets, the function bar's pop-ups, its SWAP and MENU (CRUS), by taps and by keys (records 241–250, each
  with a key on the laptop map); the layout is Rust
  (`crates/iaf-avionics/src/pcd.rs`). New formats on inferred layouts: WPN-A, WPN-S (the F-16 SMS's profiles, a GPS
  bomb's per-bomb targets), CNI (radios, TACAN, IFF over the F-16's up-front controls), FCS, PHM, CHKLST, DIM, the
  HUD repeat and the DAS format's frame. The SMS draws the bays and their doors with DOORS (Ctrl + Delete); the TFLIR
  has the TGP's track modes, zoom, WIDE / NARO, laser and CZ; the TMS keys act on the cursor's portal. The SPICE 1000
  goes in the bays on 4 / 8 ([weapons.md](weapons.md) §5). Tests: `modern-iaf/tests/test_sim_pcd.gd`,
  `test_sim_adir_pcd.gd`. Open: the per-bomb PRE pick in the sim (G4: waits for the user's yes); the DAS picture and
  the FLC came with parts D and E (above).
- **A lesson's load needs its bombs (2026-11-19, fixed, [weapons.md](weapons.md) §7.1):** a load with fewer
  air-to-ground stores than the mission's ground kills is refused on the Loadout screen and the briefing ("The mission
  needs bombs: add a Mk 82 bomb"), and a `--mission` run flies the mission's own load instead. Before, a saved load
  with no bombs flew the range lesson.
- **The F-16s' fuel tanks, the STORES CONFIG light and the last own keys (2026-11-18, [cockpit.md](cockpit.md) §5.7,
  [front-end.md](front-end.md) §9.1):** the 6-DoF carries the F-16's tanks (two systems of reservoir, fuselage, wing
  and external tank, emptying from the far end; `sixdof/fuel.rs`): ENG FEED's AFT and FWD feed the engine from one
  system and move fuel into the other, OFF stops the electric pumps only (the engine runs on: until this day OFF cut
  the fuel, a misreading of the flight manual); FUEL QTY SEL shows each position's tanks, NORM runs the automatic
  forward transfer; the FUEL LOW lights read the reservoirs (and TEST). The STORES CONFIG caution lights while the
  switch is off the load's category (CAT III with air-to-ground stores or a 600 gal tank, inferred; `stores.rs`
  `loading_category`). Ctrl + F1 / F2 / F12 (quit box, cockpit / outside, flight information line) are key-table
  records 219–221, and the notebook's pages records 222 / 223 (Page Up / Page Down, the laptop map's Option + Space /
  Shift + Space). Shift + N, the 1998 game's night-vision goggles' key, is record 255 since 2026-11-19 (the F-16s'
  goggles, the entry above). Tests: `test_fuel_brake_switches.gd`, `test_switches_click.gd`, `test_notebook.gd`; the iaf-flight and
  iaf-avionics tests. Owed: the run on the Mac.
- **The F-16s' fuel and brake switches (2026-11-18, [cockpit.md](cockpit.md) §5.7):** PARKING BRAKE holds the jet
  (Shift + G; a ground start begins with it set; the F-35I's switch too), MASTER FUEL OFF flames the engine out
  (Ctrl + F), ENG FEED and FUEL QTY SEL work (Shift + E, Shift + U; over every tank since the entry above).
- **DRIFT C/O and the display knobs (2026-11-18, [cockpit.md](cockpit.md) §5.8):** DRIFT C/O centres the HUD's flight
  path marker (Shift + J), WARN RESET puts the FUEL cue and the repeating "Altitude" call out (Ctrl + R), the MFDs'
  CON and GAIN rockers set each display's contrast and sensor picture (Shift + 7 / 8 / 9 / 0). Partly: the HUD's CONT
  wheel (Ctrl + H) washes out the symbols' edges, a stand-in: the HUD draws no infrared picture. The directions of
  these and of the fuel and brake switches were checked: none reversed.
- **The F-16s' controls that moved only (2026-11-19, [cockpit.md](cockpit.md) §5.9):** of the 47 that moved and did
  nothing, 13 work their system: the OXY QTY test (OXY LOW), the EPU and its guard (its lights and EPU FUEL), the LG
  warning horn and HORN SILENCER, ALT GEAR, GND JETT ENABLE, VOICE MESSAGE, F-ACK (the fault list), COMM 1, MAX POWER
  (inoperative on the real jet); partly ILS, TACAN and INTERCOM; then ALT REL (the stick's WPN REL) and the threat
  display's brightness knob. 29 stay moves only with their reason in `f16_status.json` (no system in the sim, or
  parked; the HUD's TEST and GPS among them); 1 is still to wire (RF); the autopilot's PITCH and ROLL work since
  2026-11-19 (below). Tests: `test_move_only_wired.gd`, `test_controls_all.gd`.
- **The F-16's own autopilot (2026-11-19, [research/f16-autopilot.md](research/f16-autopilot.md), [cockpit.md](cockpit.md)
  §5.10):** the PITCH switch engages ALT HOLD or pitch ATT HOLD, the ROLL switch HDG SEL (the EHSI's heading marker),
  roll ATT HOLD or STRG SEL (the steerpoint), as the flight manual gives them: +0.5 to +2 g, 30° of bank, 20°/s, ±60°
  of attitude, stick steering in the attitude modes, the paddle (Shift + I, held), and the PITCH switch dropping to
  A/P OFF with AIR REFUEL open, ALT FLAPS below 400 kt, the gear handle down, MPO, TRIM/AP DISC (Shift + 6 or its switch), the low
  speed tone or the sim's own autopilot flying. Above 15° of α or without its data, FLCS A/P FAIL (FLCS FAULT, the fault
  list) until FLCS RESET (Ctrl + L or its switch); A/P DEGR on the manual's three timers. Its commands add to the stick's in the
  control laws. Keys Shift + 2 / 3 (PITCH), Shift + 4 / 5 (ROLL). The A key's autopilot is unchanged. Tests: the
  autopilot's Rust unit tests, `f16_autopilot_flies_each_mode_through_the_control_laws`, `test_f16_autopilot.gd`.
- **The key faults the manuals exposed (2026-11-18; the user plays on a Mac laptop's keyboard, no HOTAS;
  [front-end.md](front-end.md) §9.1):** the speedbrakes have their own switch keys (Speedbrakes open (hold) on
  B, Speedbrakes close on Shift + B: open while held, they stay when let go; [flight-model.md](flight-model.md)
  §9.11) and Wheel brakes (hold), on W, brakes the wheels only while it is held (a ground start is held by the parking brake, Shift + G; 18 Nov),
  with Next waypoint on Shift + W and Previous waypoint on Shift + Q (the user, 2026-11-18); the Drag chute key and row
  are gone (no jet has one);
  the roll trim, MANUAL PITCH, STORES CONFIG and the GPS bomb's keys are rows of the Keys screen and of the manuals' key card;
  the cards' Throttle – OFF items carry their key (Shift + 1). For the Mac: chaff and flares on Ctrl + Z / Ctrl + X,
  the weapon view on F2, laptop keys for the eight commands on Page Up / Page Down / Home / End, and Ctrl + Q /
  Ctrl + M named with Ctrl. A test fails on a listed command with no key on a Mac laptop
  (`every_listed_command_has_a_key_on_a_mac_laptop`); `modern-iaf/tests/test_switch_keys.gd`, `test_devices.gd`. Owed:
  the run on the Mac. Not started (not in the user's words): a
  SPD BRK switch to click (the cockpit models have none); the speedbrakes' own line on the F-16's landing card; a
  speedbrake button in the Hotas X's map (`data/devices/hotas_x.json`: its brake button is the wheel brakes now).
  The own keys' records and the notebook's laptop keys were done later the same day (the entry above).
  The notebook's card keeps naming no key (the user, 2026-11-13); the manuals' step tables show the throttle's keys.
  With an autopilot mode flying, the brake control still opens the speedbrakes in the air.
- **The F-16s' lighting controls (2026-11-17, the lights audit part B, [cockpit.md](cockpit.md) §5.5; approved
  17 Nov):** the lighting panel's dimmers, MAL & IND LTS, NVIS, INDV LTG CONT and DATA ENTRY DISPLAY,
  the ICP's BRT wheel, the exterior lights panel and LANDING / TAXI each do their job; LE FLAPS rests at AUTO and its
  caution lights at LOCK (`modern-iaf/tests/test_cockpit_lights.gd`). ANTI SKID and SEAT NOT ARMED stay
  test only: the anti-skid system and the seat lever are not modelled (STORES CONFIG lights since 2026-11-18, the first
  entry).
- **The Adir's TFLIR camera and display controls (2026-11-18, fixed):** the TFLIR picture starts when the pilot picks
  TFLIR (a tab, a window, the MENU grid), presses the FLIR page key with TFLIR already shown, or clicks its picture;
  it stayed at NO VIDEO before because the display set the page alone and the key refused a page already shown. The
  function bar's SWAP trades the bar's halves; its MENU opens the MENU page as a pop-up (CRUS: the default layout); a
  portal's `CNTL>` opens the format's control page (TSD, SRCH, TFLIR: zoom, WIDE / SPOT, the laser)
  ([../../docs/real-mfd.md](../../docs/real-mfd.md) "F-35I", [../../docs/f35i.md](../../docs/f35i.md) §4.3;
  `modern-iaf/tests/test_sim_adir_pcd.gd`). The MENU page's LITES and HMD are not built.
- **The bombs' release submodes and fuzing (2026-11-18, avionics-plan.md slice 9, S3–S6, S8, M4; G21, G22, G25):**
  on the Sufa and the Barak the SMS's A-G menu has CCIP, CCRP, DTOS, LADD and MAN; CCRP and LADD aim at the radar's
  designated point, the pod's track or the steerpoint and release by themselves with WPN REL held, DTOS designates
  under its TD box in the dive, LADD gives the pull-up cues for a 4 g loft to 45°, MAN shows the primary reticle on the
  RET DEPR wheel; OSB 18 the fuze, OSB 17 the arming delay; a bomb hitting before it arms is a dud, with `LOW` on the
  HUD ([weapons.md](weapons.md) §9; keys Ctrl + G, Alt + Q, Alt + 0, Ctrl + V / Alt + V;
  `modern-iaf/tests/test_sim_bombs.gd`, the laser path included). The range missions' second steerpoint is their
  target steerpoint, every GPS bomb's PRE target without a pick of its own. Not started (outside the plan's rows): RBS, ULOFT, the CNTL pages. The Adir carries
  only GPS bombs: its share is the PRE target.
- **The GPS bombs' PRE targets on the briefing (2026-11-19, A61 option A; avionics-plan.md S14, G4):** the map's
  PRE targets chip (with a GPS store aboard) puts a panel in the text card's place: each GPS station, a rack opened
  into its bombs; a click on a row, then on a mission target, a steerpoint or any point of the map sets its target, a
  right click (or Delete) clears it ([front-end.md](front-end.md) §10.2). The picks live in the pilot's loadout
  (`pre`; saved loadouts keep them, old ones have none, a mission's own loadout may carry them) under one rule in Rust
  (`gps::pick_ok`); the flight takes them (`flight/fly.gd`), each bomb flies to its own; the F-16 SMS shows the next
  bomb's PP n/N, its target's name and place and the next bomb's target, the Adir's WPN-S each bomb's target by name.
  The rows and clicks are reborn's TSD's, moved to `shared/weapons/pre_pick.gd`. `modern-iaf/tests/test_sim_pre_targets.gd`.
- **The air-to-air missiles' employment flow (2026-11-18, avionics-plan.md slice 8, W1, W4, N7, P12, S13; G26,
  G27):** on the Sufa, the Barak and the Adir: `]` selects, the radar locks, the IR missile's seeker caged on the lock,
  the helmet or the boresight hears the target; Shift + M uncages it to track (the HUD's large diamond), Ctrl + S or
  the F-16 SMS's OSB 2 steps SPOT / SCAN; SHOOT, the launch (the Adir's AIM-120 from its bays); after it the time to
  active (A) and to impact (T) on the HUD, the helmet, the FCR and SRCH, the target's tail and its X for the last 8 s
  ([weapons.md](weapons.md) §8; `modern-iaf/tests/test_sim_missiles.gd`). Not started (outside the plan's rows): the
  pre-launch time of flight, the M-pole / F-pole ranges, the SLAVE / BORE and COOL options.
- **The Adir's radar, sensors and helmet (2026-11-17, avionics-plan.md slice 7 part B, A2–A7, E5, H6–H8, N9, P5):**
  the real FCR's controls on the APG-81's row (`radar.fcr`; the Sufa's keys): SRCH with CRM RWS / TWS / VSR, SAM's
  four bugs, STT, ACM and BORE, the cursor with its altitude coverage; ASR with the ground map as a grey SAR picture
  (GM, EXP, DBS1, DBS2, FZ, SP, CZ, GMT, SEA, AGR); the combat ID (friend green circle, unknown yellow square,
  hostile red diamond) on SRCH, ASR, the TSD and the helmet's lock (`aiff.rs` `combat_id`, inferred); the TWD with the
  range's radar drones; the DAS's MAW on the TWD and in the helmet; the data link's tracks on the TSD; the helmet's
  break X and pull-up cue (the F-16's GAAF rule, inferred). `modern-iaf/tests/test_sim_adir_radar.gd`. Electronic
  attack stays out (§8.5); the SRCH layout stays inferred (G32: no source).
- **The Barak's avionics (2026-11-17, avionics-plan.md slice 6, §3 B1–B11):** today's upgraded F-16D (Barak 2020,
  the Sufa's avionics installed) as data merged over the F-16's definition (`modern-iaf/data/planes/f16.json`): the
  real FCR's controls on the APG-68's row (CRM RWS to 43 NM, SAM with one bug), the colour MFDs with the HSD's map, the
  AIFF, no MAW, the wide-angle HUD (its own HUD since 19 Nov, above). Every Sufa avionics test now flies both jets (`base.gd` `sim_f16s`;
  `IAF_SIM_JET=f16d` runs one). Found and fixed: the Barak had none of the real FCR (its definition had no
  `radar.fcr`); the TACAN started on Ramon's channel on every jet (now the home base's station).
- **The F-16s' 3D-cockpit lamps (2026-11-17, the lights audit, [cockpit.md](cockpit.md) §5.2):** every lamp of the
  model lights, the caution panel's 32 among them; each is wired to the state that lights it (the start-up's lamps on
  the battery, the ELEC panel, JFS RUN, the cautions and MASTER CAUTION with its reset and the ELEC panel's CAUTION
  RESET, the test switches, the threat warning panel's buttons, ECM ENBL), and MAL & IND LTS lights them all. Lamps of
  systems the game lacks (the EPU, TF, the AR system, the marker beacons, the seat, oxygen) light only in that test
  (`modern-iaf/tests/test_cockpit_lamps.gd`).
- **The Sufa's up-front controls, HUD panel, navigation and DGFT (2026-11-17, avionics-plan.md slice 5 part A,
  G2, G17, G18, G28, G29; [ufc.md](ufc.md)):** every DED page the sim can feed with data entry on keys and the 3D
  ICP (STPT editing, markpoints 26–30, BINGO, ALOW, CRUS, TIME, T-ILS with TACAN to the bases, INS, BULL, LASR,
  COM1 / COM2 and the backup UHF); the HUD control panel's switches, ALIGN, SIM and the SOI asterisk; no steering
  until the INS navigates; DGFT / MSL OVRD on V / Shift + V; the EHSI's TCN.
- **The F-16s' EW and identification (2026-11-17, avionics-plan.md slice 5 part B, E1, E2, E4, R15, N5, N6; G13,
  G19, G20, G30, G31; [ews.md](ews.md)):** the threat display on the 3D RWR scope after the dash-34 and the ALR-69
  (labels by class, diamond, lock square, launch circle, new-threat flash and tone, PRI / OPEN, UNKNOWN, TGT SEP,
  HANDOFF, SYS TEST, the volume knobs), the range's radar drones heard from every side as "35"; the Sufa's MAW (an
  "M" with the seconds to impact); the CMDS panel, programs 1–4 and the CMS keys (P, Shift + P, Y; Shift + Y MODE,
  Ctrl + Y program) releasing through the game's dispense with the VMS's "Counter" and "Chaff flare low / out"; the
  Sufa's AIFF (O, Shift + O, TMS left in CRM: green circles, yellow squares); the data link on the HSD and the FCR (the
  DL switch); the DED's EWS pages (programs, BINGO, REQCTR / BINGO / FDBK / REQJAM), IFF, DLNK and INTG; the transponder's modes, codes and IFF IDENT (Alt + K); the AWACS's contact calls voiced. Fixed the
  same day: the HUD's DED DATA overlapped its right column (now a block of character cells between the columns, the
  roll indicator off meanwhile), the threat symbols piled on the centre (now on rings by lethality, apart), the AIFF's
  circle sat below its FCR contact (now by slant range), the 3D DED showed 3 of its 5 lines and its columns did not
  line up.
- **The Sufa's MFDs (2026-11-17, avionics-plan.md slice 4, G8 DMS, G14–G16, G24, G25;
  [../../docs/mfd.md](../../docs/mfd.md) §9 "Modern MFDs"):** each MFD keeps three formats per master mode (NAV,
  A-A, A-G); the menu adds DTE, FLCS, BLANK and the RESET MENU; the sensor of interest with its box and NOT SOI, DMS on
  Ctrl + Page Up / Down and Ctrl + `[` / `]`, the cursor and TMS keys acting on the SOI; the HSD's DEP / CEN, CPL, EXP,
  FRZ, CNTL page, bullseye and cursor (TMS up on a steerpoint makes it current); the SMS's submode menu and PROF1 /
  PROF2 per weapon; the Litening pod on the chin with the TGP's POINT / AREA / INR tracks, slaving to the radar's
  designation or the steerpoint, LASER ARM (Shift + L, the 3D cockpit's switch) and the laser; the GBU-10, GBU-12
  and GBU-16 on both F-16s ([weapons.md](weapons.md) §7). Checked on the range: a GBU-12 lased by the pod hits a
  hulk (`modern-iaf/tests/test_sim_mfd.gd`). Pods part 1 (2026-11-17): a laser bomb needs the pod (the loadout's
  Fly off with a line saying what to add, the briefing's line, the SMS's NO LASER; weapons.md §7.1) and the pod's
  cockpit steps (power-up, STBY, CZ, the TD box, the laser code, the automatic laser, MASK; §7.2;
  `modern-iaf/tests/test_sim_pod.gd`). Open: the HUD's own SOI mark (no source shows it). The Litening
  drawn with its own model (FlightGear's AN/AAQ-28 at the real 2.20 m by 0.406 m, 2026-11-17,
  [../../docs/aircraft-models.md](../../docs/aircraft-models.md) §5.1); the Hangar and the Loadout screen hang it by its
  top from the chin station, as the flight does, under the model's right chin pylon (FlightGear's, 0.69 m right).
  Pods part 1, step B (2026-11-17): the chin stations 5R (the Litening) and 5L (the engine's 13th station, pylon J),
  the LANTIRN navigation pod (AN/AAQ-13) on the Sufa's 5L and the Pathfinder on the Barak's, carried, drawn (their
  own model, `lantirn.glb`), weighed and kept by the jettisons, on the SMS inventory under 5R (weapons.md §7.3;
  `modern-iaf/tests/test_sim_chin_pods.gd`); a load with a laser bomb and no pod is not saved as a preset, and the
  Loadout screen's line is one short line, the front end's Hebrew saying פוד. Pods part 2 (2026-11-19, weapons.md
  §7.4): the navigation pod's FLIR picture on the HUD (both F-16s: warm-up, STBY / OPER, WHOT / BHOT, gain, level,
  snap-look, look-into-turn) and the Sufa's terrain following from the LANTIRN's TFR (the FLIR and TFR formats, SCP,
  ride, manual TF box, ADV MODE automatic TF, fly-ups, the paddle, MANUAL TF FLYUP, the RF switch, TF FAIL and its
  lamp; `modern-iaf/tests/test_sim_nav_pod.gd`). Open: LO TF's meaning and the formats' real layouts (no source).
  Not started (outside pods part 2): laser spot search (P6), the Ra'am's pods (P10), Litening page polish (P11).
- **The Sufa's radar, air to ground (2026-11-17, avionics-plan.md slice 3, G9–G12;
  [../../docs/radar.md](../../docs/radar.md) §9.7):** R gives GM, Q steps GMT and SEA; NORM's fan and the EXP, DBS1
  and DBS2 patches (Ctrl + `;`) over a radar picture made from the terrain (slopes, shadows, dark water and runways,
  bright returns); the ground cursor on the cursor keys or the mouse; FZ, SP, CZ and STP / TGT (Alt + `;`, `'`, `/`,
  `.`); TMS up designates the cursor's point or tracks the return under it (FTT), and the GPS bombs, the SPICE in VIS
  and the HUD's TD box take that point; GMT lists the movers on a dimmed map, SEA the ships; AGR ranges a CCIP
  delivery for the FCR and the HUD. Each range has a towed hulk (GMT) and a barge at sea (SEA). Checked on the range
  (`modern-iaf/tests/test_sim_fcr_ag.gd`). BCN and TF stay parked (avionics-plan.md G12).
- **The Sufa's radar, air to air (2026-11-17, avionics-plan.md slice 2, G1 and G5–G8;
  [../../docs/radar.md](../../docs/radar.md) §9):** the real F-16 FCR on the game's modes: STBY at power-on, no
  radiating with weight on wheels, CRM by itself once airborne; RWS with the A6 / A3 / A1 scans, B4 / B1 / B2 bars and
  the antenna elevation; SAM keeping four bugged tracks while searching; TWS's track files kept 13 s; VSR; ACM's 20,
  60, SLEW and BORE patterns with their HUD cues; the bug centring the scan; EXP (Ctrl + `;`); the CNTL page with
  target history and MTR; NO RAD; the acquisition cursor and the TMS on keys (`/`, `;`, `'` with Shift / Ctrl, Alt +
  Up / Down, Ctrl + arrows), listed on the Keys screen. Checked against the range's drones (`modern-iaf/tests/test_sim_fcr.gd`).
- **A weapons range per jet (2026-11-17, avionics-plan.md slice 1, G3; [training.md](training.md) §3.4):** the
  Training list's third mission for the Sufa, the Barak and the Adir: a cold start, then five drones (the sim's own
  F-16 and F-35 on the shared AI under the sim's own brains: co-altitude, low, a manoeuvring one, a pair whose radars
  the RWR hears; red for the exercise, never shooting) and six ground targets (four retired airframes parked, a fifth
  towed, a target barge at sea); the mission's own load carries the bombs for them (2026-11-18, [training.md](training.md)
  §3.4: until then the load had none and the lesson could not be passed as briefed). The radar finds the
  drones, the gun, missiles and bombs destroy them, and the scorer counts air and ground kills on the debrief
  (`modern-iaf/tests/test_sim_range.gd`).
- **Every F-16 3D-cockpit control is seen to move (2026-11-16, finish list C4, [cockpit.md](cockpit.md) §5.2 "Every
  control"):** the parts FlightGear does not animate are pressed in or tilted; the proof renders every control through
  its positions (`modern-iaf/tests/_controls_shot.gd`). 2026-11-17 (C4b): the M button and the right MFD's GAIN rocker
  move (a row's own property is read from the store); the MFDs' inboard rockers and MAX POWER are seen with the head
  leaned; the proof compares full-size crops and pictures a hidden part from a lean; the EHSI draws the heading bug and
  course arrow its HDG and CRS knobs set; the ADV MODE button shows (the build hides FlightGear's Block 15 panel face
  over it) and its STBY legend lights while selected.
- **The Settings in the r3 layout (2026-11-16, the finish list's F7, [front-end.md](front-end.md) §14):** a search
  across the sections in English or Hebrew, the sections' counts, Graphics' Preset row (Laptop, Balanced, High,
  Everything on, Custom), segmented buttons for every row's choices, a cost chip per graphics row from measurements on
  the Iris Xe laptop (`tools/settings_cost.sh`), the pane on the hovered setting with its Off / On picture (our own
  renders), its description and the frame time measured during the player's last flight; Defaults and Back to the
  hangar in the footer. Devices: Keyboard with no joystick connected; the Joystick screen without axis rows then; the
  Keys and Joystick screens in the Settings' frame.
- **The autopilot's landing circuit lands every jet (2026-11-18, [flight-model.md](flight-model.md) §9.6):** NAV to a
  landing waypoint flies the 1998 circuit with laws of its own on the 6-DoF: the turns bank and pull inside the lift of
  15° α, the gear-down legs fly no slower than the speed of 11° α, the path law is as slow as the jet's g answers, and
  the final starts 7 km out, level, until the 3° path comes down. The Barak, the Sufa, the Adir and the Ra'am land at
  Ramat David from a landing weight to full fuel with 3 t of stores: 128–165 kt, 0.8–2.9 m/s of sink, stopped 0.7–1.1 km
  down the runway (were: 12 of a sweep of 24 flights crashed). Since 2026-11-25 every weight touches under the tail
  strike's 15° (13.2–14.6°): the heavier final flies 12° α and the flare stops pulling at 14.5°. Since 2026-11-19 the
  flare's sum on the 6-DoF allows for the jet's g lag: the 1998 game's Adir with 3 t of stores touches at 1.5 m/s
  (was a balloon to 2.8 m and 4.05 m/s).
- **The autopilot lands softly; the roll starts faster (2026-11-16, finish list: autopilot touchdown, roll onset,
  [flight-model.md](flight-model.md) §9.6, §9.13):** on the 6-DoF the autopilot flies a real final, 3° (inferred) at
  the speed of the F-16 manual's 13° α (about 145 kt), with a flare from about 15 m: touchdowns at 2.0–2.6 m/s (were
  4.3–9.6). The stick's roll command ramps at 688 deg/s² as reborn's Real roll does (its roll channel): 90° in
  0.80 / 0.85 s at 350 kt and 0.65 / 0.68 s at 480 kt (Barak / Sufa, were 0.87 / 0.88 and 0.78 / 0.80); the
  flaperons' sourced 62 deg/s keep it above the command's 0.55 s.
- **The Missions cards and no key caps (2026-11-16, the user, [front-end.md](front-end.md) §2):** a section's card
  shows its number, title and progress (no subtitle or "What it holds"); no button carries a key cap (Back's "Esc"
  gone everywhere, Esc still works).
- **Attributions (2026-11-16, the finish list's F8, [front-end.md](front-end.md) §5):** a footer Back, the list
  scrolls by the arrows and Page Up / Down; the six unused jet photos, their entry and credits deleted.
- **MAIN PWR's BATT, the JFS's START 1 and RDR ALT's STBY (2026-11-16, finish list C3, [cockpit.md](cockpit.md)
  §5.2):** each a position of its own in the flight model with its consequence, clicked or dragged in the 3D cockpit.
- **The crash page in Hebrew (2026-11-16, the finish list's F10, [front-end.md](front-end.md) §11):** the loading
  step by its loading-screen name in the page's language; the log's path one left-to-right run.
- **The F-16s' 3D cockpit switches work their systems (2026-11-16, finish list C2, [cockpit.md](cockpit.md) §5.2
  "Every control"):** MASTER ARM, EMER JETT, the ICP's A-A / A-G, the MFD BRT rockers, ALT FLAPS, STORES CONFIG,
  MPO, HMCS SYM INT (the helmet display's power), MAL & IND LTS (the lamp test) and MASTER CAUTION (its reset) work
  their systems, and their keys move them too. Test: `modern-iaf/tests/test_controls_systems.gd`.
- **The Pilot log, the Pilot screen, the section list (2026-11-16, the finish list's F6, [front-end.md](front-end.md)
  §2, §3):** the log's dates as the debrief's with the time, filters by jet and by mission, rows named, a footer Back;
  the Pilot screen's form in one column (no empty middle column); with every mission passed no Next on the list.
- **The pause menu and the Settings over a flight (2026-11-16, the finish list's F4, [front-end.md](front-end.md)
  §8, §9):** the pause menu names the mission and the jet; the Settings, Keys and Joystick screens over the flight
  have the front end's top bar (crumbs from Paused) and a footer with Back; a row's choices side by side, so Graphics
  fits with VSync whole. The notebook's frame cost and pictures in [training.md](training.md) §11.
- **The debrief (2026-11-15, the front-end finish list's F5, [front-end.md](front-end.md) §13):** the approved
  r3_debrief: the sheet with the goals (target, flown figure, ✓ / !) and "Next time:" from the Rust scorer, the whole
  flight on the map (the track coloured by phase, the planned route, Start / Lift-off / End pins with their times, the
  base inset) and the speed, height and load graphs with the phase band and the marked events (`IafTraining.track`);
  Pilot log, Export flight data, Back to missions, Fly again, Next mission; a record without a recording shows the
  sheet and the right column's empty state; Hebrew dates name the month.
- **The Missions and section screens, each jet's own missions (2026-11-15, the front-end finish list's M2,
  [front-end.md](front-end.md) §2, §12):** a section lists only the Hangar jet's missions (the user: "show only the
  same plane missions"), numbered 1, 2 …, with that jet's statuses, Next and progress (also on the Hangar's card); a
  mission flies in its own jet again and the debrief's Next mission is that jet's next one. The Missions screen's
  cards fill the screen and say what each section holds (Training: the jet's missions and the lessons coming later;
  the others "Coming later" with what they will hold); the section's list has a side panel on the mission under the
  focus (what it is for, base, time allowed, last result, best time); both screens have the footer's Back with Esc.
  The Settings' icon is a gear of our own, crisp at every size (Hangar, pause menu, Settings title). The Hangar's jet
  view shows no white frame while dragged; only the keyboard's focus shows a faint ring.
- **The briefing ready for several flights (2026-11-15, the front-end finish list's N1, [front-end.md](front-end.md)
  §10):** a mission names its flights (Kidon 1, the player's, and Kidon 2..4: callsign, jet, task, route, stores; Rust
  `flights.rs`, compiled into `sim.flights`); the briefing shows a mission of several flights as tabs with the
  player's picked and its line, and the map draws each other flight's route in its own colour. Every mission has one
  flight today and shows no tabs. Multi-flight missions themselves wait for their AI flights' missions.
  `cargo test -p iaf-tools --lib flights briefing sim`, `test_front_end.gd` (the sample mission
  `modern-iaf/tests/data/two_flights.json`).
- **The menu flow (2026-11-15, the front-end finish list's M, [front-end.md](front-end.md) §1, §2):** the Hangar's Fly
  opens a Missions screen with the sections Training, Campaign, Single missions and Scramble (a section without
  missions greyed, no click, no focus; Scramble opens its own screen, below); a section opens its
  list with each mission's last result (Pass with the best time, Fail, Not flown yet) and the next one to fly marked
  and focused; a row opens its briefing (no mission tabs on it any more), whose Back returns to the list; Arming
  returns to the briefing; the debrief has Next mission, Fly again and Back to missions. The list's progression logic
  is shared with reborn (`shared/mission/mission_list.gd`). Campaign and Single missions wait for their missions.
- **Scramble (2026-11-24, [front-end.md](front-end.md) §2.1, [../../docs/ai.md](../../docs/ai.md) §23):** the Scramble
  card (הזנקה) opens a screen of one panel: the flight (alone, pair, four-ship) and the start (in the air, the default;
  on the runway, engines running, lined up in pairs; cold at parking), the home base named, a line naming the Pilot
  screen's enemy skill; Arming and Fly. The Date and time row (25 November), date first: a day and month this year,
  or Random, then the start time in 24-hour military time (HHMM, an hour and five-minute steps) or Random (drawn at Fly
  from the seed, shown on the notebook's DATA page); the flight starts then, Israel time with summer time, so the
  sun's path, the day's length and the moon follow the date (the temperature and the weather stay the same in every
  season). Both start at Random on each opening of the screen (0800 today under it), never stored. Fly draws the
  fight's area (another base within 180 km of the home base, `iaf_ai::free_combat::area`) and the enemy round it
  (`roll`: the task, its target and one to three more threats by the skill, from MiG-29 pairs on CAP and on alert,
  the S-300 network, short-range air
  defence, Shahed-136 drones and a convoy); the air start puts the flight 60 km from the area at 6,000 m. The Area and
  Enemy skill rows went on the user's round-3 word (24 November). The AWACS gives the task by radio once the jet is in
  the air, in English and Hebrew ("Kidon 1, attack the convoy, bearing 040, 25 miles, free to engage"), and every minute
  while the target lives. Not scored. The first version (A81, 23 November: "Fly now", the enemy picked row by row, a
  ground start only) was renamed and cut down on the user's word of 24 November; its picture of a "cold start at home
  base" showed the jet in the air because the picture's script had put it there, not the start. Waiting on the user's
  approval (a new screen). Not started: the full AWACS (picture, bogey dope, the Eitam in the sky). The combat logbook
  is its own job.
- **The Loadout screen (2026-11-14, the front-end finish list's F3, [front-end.md](front-end.md) §10.1):** Arming on
  the briefing opens a screen of its own: the jet seen from beneath (the Hangar's live model, the camera under it, the
  F-35I's bays open) with a callout per station (number, place on the wing, store, weight; an empty one dashed) and
  its line to the station on the model; LOADOUTS (the mission's own and the pilot's saved ones, named per jet, saved,
  picked and deleted on the screen; the one on the jet tinted, no side bar); TAKE-OFF WEIGHT (figure, share of the
  maximum, the wings' balance, fuel, gun rounds, chaff / flares) and STORES; Reset to the mission's, Briefing, Fly.
  The editor's rules stay (racks, refusal, drag and drop, keyboard). Since 2026-11-15 (finish list L, the user's
  notes): an edit changes its own station only, "Mirror to the other wing" (off by default) fills the pair; Fly the
  size of its neighbours; every store of a rack drawn in its place on the Loadout screen's, the Hangar's and the
  flown jet (a TER-9/A's three Mk 82, a BRU-57/A's two GBU-38; our own rack models). Real loadouts (2026-11-25): the Sufa's "Air-to-air,
  long range" from an IAF picture, badge Operational ([data-formats.md](data-formats.md) "Real loadouts"); open: the
  Barak's, the Adir's and every strike / SEAD one (listed there). `test_front_end.gd`, `cargo test -p iaf-tools --lib loadout pilot_log`.
- **Weapon physics (2026-11-14, the physics finish list W rows):** the gun's rounds fly a ballistic path (muzzle
  velocity plus the jet's, the M56's drag by air density, gravity) and the EEGS funnel predicts it (W2,
  [weapons.md](weapons.md) §1); the unguided bombs fall by gravity and their own drag through the wind, nothing
  steering them, and CCIP predicts that fall (W5, W6); the GPS bombs miss by their published CEP (W11); a drop tank's own empty weight loads the jet until it is
  jettisoned (370 gal 443 lb, 600 gal 380 lb and 300 gal 360 lb, all sourced; F27). Shared with the original game's Weapon data Real.
- **Release limits, jettisons, bay doors (2026-11-15, W17, W18, W22):** a bomb leaves only at 600 KCAS or less and in
  a dive of 60° or less; Shift+C is the F-16's emergency jettison (every store and rack but the A-A missiles and the pods in one
  press, unarmed, the tanks' fuel with them); the F-16 SMS's S-J and Space jettison the selected store with its racks;
  the F-35I's bay doors open in 0.47 s, shut 0.5 s after the release and add drag while open
  ([../../docs/real-weapons.md](../../docs/real-weapons.md) §1.11). Shared with the original game's Weapon data Real.
  Test: `test_sim_jettison.gd`.
- **Bombs, missiles and the gun in every flight (2026-11-14, the user: "the fact that you can drop weapons"):** on
  the Sufa, the Barak and the F-35I the stores hung on the Loadout screen fly with the mission; after the
  take-off's pass the flight goes on, and Shift+A, `[` and Space release the bombs (the HUD's CCIP cue; the F-35I's
  bay doors open by themselves), which fall and burst on the terrain; `]` and Space launch a missile, Tab fires the
  gun ([weapons.md](weapons.md) §5). The notebook's WEAPONS tab (key H) lists the steps per jet with their switches
  and keys; the SMS pages show the stores, the counts and the master arm. Tests: `test_weapons_flight.gd`; pictures: `_weapons_shot.gd`, flown from the front end.
- **Flight data and settings files (2026-11-14, the front-end finish list's D1, [front-end.md](front-end.md) §2):**
  the debrief's Export flight data copies the flight's recording (greyed and out of the focus without it); the
  Settings footer's Export / Import settings file write or read a `.cfg` by the sim's rules (Hebrew without its font
  in English, the pilot and the jet kept). The file dialog and these rules are reborn's, moved to
  `shared/util/file_export.gd`, which both games call.
- **First run, Hangar, missing data (2026-11-14, the front-end finish list's F1, [front-end.md](front-end.md) §1, §3,
  §12):** "Preferences" is "Settings" on every screen (the Hangar's button, the title, the crumbs, the pause menu);
  Attributions in Hebrew "קרדיטים ורישיונות" (the front end and the setup wizard). Create your pilot shows a head and
  shoulders in the empty 3:4 frame, then the typed name's initials, and no pilot in the top bar yet; Up / Down move
  between Name and Nickname, Up from Name to Choose a picture. The Pilot screen's logbook is a panel down to the bottom
  bar. The Hangar's focus order: Settings, the pilot, the jets, Fly, Attributions; Down from Fly stays. Without the
  sim's data the Hangar and Pick a mission say what is missing and the command `./modern-iaf-setup` (Windows
  `.\modern-iaf-setup.ps1`), Fly greyed and out of the focus, and the Hangar tries no model load without the converted
  descriptor (its still picture instead). Missions and campaign stays greyed.
- **The canopy opens and closes (2026-11-14, canopy round 3):** on the Sufa, the Barak and the F-35I the canopy
  stands up at a cold start (the F-16s' 34°, measured on a photo since 2026-11-25; the F-35I's 30°) and comes down over 10 s at its checklist step (shut at once on a hot or airborne
  start), outside and from the seat alike. Each canopy has an opaque frame round the glass painted as the airframe
  and turns about its own hinge (the F-16s' aft, the F-35I's front); the F-35I's control is a yellow lever on the
  left wall, aft of the throttle ([training.md](training.md) §7.1, [cockpit.md](cockpit.md) §5.2,
  [../../docs/f35i.md](../../docs/f35i.md) §4.1, [../../docs/aircraft-models.md](../../docs/aircraft-models.md)).
  Pictures: `_canopy_shot.gd`. The F-16D model is also reborn's "Models: Detailed" F-16, which shows the new frame.
- **The start-up switches both ways (2026-11-13, the switches audit's M2, first part):** on all three jets every
  start-up switch goes back off by its key or a click and on again, with its consequence: main power off darkens
  everything, the starter off stops a crank, the avionics off darken the displays and lose the INS alignment (a
  warm-up and a new alignment when back on), the INS knob off loses it (since 2026-11-15 the knob turns through all
  six positions both ways, by the mouse and its key: STOR HDG 90 s, NORM 8 min, NAV keeps the alignment, ATT loses
  it; cockpit.md §5.2), the canopy opens; the JFS switch springs back to OFF at 52 %. The flight model holds the
  positions (`start.rs` `Start::on`); the checklist, the card and the debrief read them, so a switch back off undoes its step ([cockpit.md](cockpit.md) §5.2 "Both ways";
  `test_switches_both_ways.gd`). The in-between positions (MAIN PWR BATT, JFS START 1, RDR ALT STBY) work since
  2026-11-16 ([cockpit.md](cockpit.md) §5.2 "The in-between positions").
- **Each power switch its own system (2026-11-13, the switches audit's M2b):** on the Sufa and the Barak the
  generators give the displays' power, and each AVIONIC POWER and SNSR PWR switch powers its own system after a 3 s
  warm-up: MMC the HUD, ST STA store release, MFD the MFDs, UFC the DED, FCR the radar, RDR ALT the HUD's radar
  altitude; the INS needs main power only. Each has its own command (219); Ctrl+A throws the four AVIONIC POWER
  switches, and since 2026-11-17 the FCR and RDR ALT on with them (a keyed start had left the radar held at STBY and
  the HUD without the break X's radar altitude; `test_sim_radar.gd`); after a start by clicks the key powers the FCR
  too, and the switches work after a lesson's pass (`test_radar_cold.gd`); the avionics step is the four on
  ([cockpit.md](cockpit.md) §5.2 "One by one"; `test_switches_both_ways.gd`).
  Open: the real consequences beyond the switches' names (sources). Since 2026-11-25 the CARA ALOW and GAAF voices
  stay silent with RDR ALT off, as the HUD's R row and break X (`gaaf::alow` / `advisory` take the CARA's height).
- **The jet's checklist card (2026-11-17):** one real checklist per jet in every mission, the notebook's CHECKLIST tab:
  the F-16s' after the real F-16C/D normal procedures (68 items, 53 checked by the sim, 15 read and acknowledged since
  2026-11-25), the F-35I's from the public start flow and inferred (38 items, 28 and 10); each checked item ticks from the cockpit's
  state, the current one ringed in a lesson; the start-up lessons ask for its items through BEFORE TAXI; LEFT HDPT and
  RIGHT HDPT power the chin pods ([training.md](training.md) §12; `test_checklist_card.gd`). Since 2026-11-18: the
  F-35I's card holds the items a public US Air Force instruction requires (the survival kit switch, loose items, the
  helmet display's preflight, the ops check, the "gear down" report, the post-flight walk-around, the taxi speeds and
  the fuel calls); both cards name each control as its panel does and state the reaction the cockpit shows; BEFORE
  LANDING opens on the approach (it never did: the rule read a height above the ground the flight's state does not
  hold); `test_card_landing.gd` flies the card home to a cold jet. Since 2026-11-25 the F-16's speed brake items and the F-35I's seat items are checked
  ([cockpit.md](cockpit.md) §5.12); read and acknowledged stay the oxygen, the IFF, the trim (the sim has the roll trim
  only) and the F-16's ejection safety lever (none in its cockpit model). The autopilot's landing circuit
  with the 6-DoF jets, which sank the Sufa into the ground here, lands since 2026-11-18 (the entry above on the
  autopilot's circuit).
- **Every checklist switch by the mouse (2026-11-13, the switches audit's M1):** the throttle takes no mouse since
  2026-11-15 (the user: "shouldn't be able to move the throttle or stick from the mouse"; it took the wheel and drags);
  the landing gear handles (both F-16s, the F-35I) send the G key's
  toggle; the F-16's FCR and RDR ALT switches (FlightGear's own `fcr-switch` / `rdr-alt-switch`, now nodes of `f16.glb`) move on a click
  and power the radar and the radar altimeter since M2b ([cockpit.md](cockpit.md) §5.2). `test_switches_click.gd` checks every switch of each jet's
  start-up, take-off and landing steps resolves to a clickable part, lights and sends its command. The F-35I's
  CANOPY control is a lever on the left wall since 2026-11-14 (the canopy entry above).
- **The pointer comes back after a mouse look (2026-11-13, the user's Mac):** the right drag hides the pointer while
  held; on release, a release the view missed, a lost focus or a pause it shows again where it was
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd` checks it.
- **The right glove holds the stick (2026-11-13, the user):** looking down in the F-16s the right glove wraps the
  side-stick's grip (it hung 9 cm ahead of it) and the left palm sits on the throttle's head (it lay on the console
  beside it), its fingers closed on the grip (they spread onto the panel beside it), cold and in flight
  ([cockpit.md](cockpit.md) §5.3). `test_cockpit_view.gd` checks both hands.
- **No mission card (2026-11-13, the user):** a flight starts with nothing over it, the flight running; the in-flight
  mission card and its H key are gone (record 118 and H are the Checklist notebook's since). No key hint over the
  flight since 2026-11-15 (the Esc line removed; [front-end.md](front-end.md) §8); only the notebook's help line in
  the pilot's first start-up mission. The goals are in the briefing, the live "To
  complete" line, the completion message and the debrief. `test_flight_ui.gd` checks it.
- **Reborn's code reused (2026-11-14, the reuse audit's R1–R3):** the mission page preloads the ground and models
  with reborn's `TerrainPreload` ([front-end.md](front-end.md) §7); the briefing map's wheel zoom and the notebook's
  wheel take `Settings.zoom_steps` / `wheel_steps`; the Settings' shared rows take their choices and greying from
  `shared/util/pref_choices.gd` (MetalFX named on a Mac).
- **The pilot's checklist notebook, part 1 (2026-11-13, the approved mock-up's look A):** in every flight a paper
  notebook on the right thigh; H raises it at the screen's lower right and stows it. Tabs START-UP, TAXI / T-O, RADIO,
  LANDING, EMERGENCY, DATA; a tab click, the wheel or a trackpad's scroll (`Settings.wheel_steps`, as reborn's
  text windows, 2026-11-14), PgUp / PgDn and the page's own ‹ › with its page count turn it. No
  key hints on it; a help line in the first start-up mission only. It replaces the start-up card: the steps whose
  switches are on ticked (a switch back off unticks its step), the step to take now marked. In a start-up training
  mission an outline of the current step's switch's own shape (and of the F-16's RPM dial for the idle step), a pointer
  at the screen's edge for a part out of view, the board sliding off an outline it would cover. English and Hebrew (mirrored). RADIO's
  frequencies: OurAirports' where published, the rest invented ([training.md](training.md) §11). `test_notebook.gd`.
  Open: the GUIDE tab and the front end's Guides screen (part 2). By the mouse since 2026-11-25: the F-35I's
  ejection handle; the throttle's OFF stays the keys' (the user, 15 Nov), the toe brakes the keys' and the joystick's,
  PARKING BRAKE a click on both jets ([cockpit.md](cockpit.md) §5.12).
- **The F-16's approach speed matches the manual (2026-11-11):** TP-1538's speed-brake tables gave the open speed
  brake lift (+0.25 CL at 13° α); the 6-DoF flies the JSBSim model's speed-brake drag instead, and its flaps' lift
  (+0.122). The 13° α approach is 136–139 kt at the manual's three weights (manual 139–141 kt, was 118–121 kt)
  ([flight-model.md](flight-model.md) §9.17). Since 2026-11-15 the F-16s' speed brake stops at 43° with the main gear down
  (T.O. 1F-16A-1); the Adir's surfaces have no such limit (inferred).
- **The Adir's own flight figures (2026-11-16, finish list F23):** one F-35I set (`data_set::F35I`) that the 6-DoF
  and the original game's F-35I both read: the control law's 50° α limit (Lockheed Martin; a full pull at 150–400 kt
  peaks at 51–52° and holds 50°, a full push recovers in under 6 s), +9 g, the F-16's roll (inferred), a nose-down
  moment at high α and an α-rate lead in the limiter (both inferred), the approach at 152 KCAS and 13° α (USAF
  accident report) and a 134 kt 1 g stall (inferred; 128 kt measured) asserted ([flight-model.md](flight-model.md)
  §9.19, [../../docs/f35i.md](../../docs/f35i.md) §2.1). Open: the F-35's roll rate and climb (no public figure),
  the sustained turn's Mach and altitude (DOT&E gives 4.6 g without them; searched 2026-11-25).
- **The trailing-edge flaps droop with the gear handle (2026-11-11):** on the 6-DoF the F-16s' and the Adir's
  flaperons go 20° down with the gear handle below 240 kt, less to 370 kt, and up with the handle, in the gear's 3.1 s
  (the F-16 flight manual); their lift, drag and nose-down moment are inferred (DATCOM, FM-0's drag); the models'
  flaperons droop with them ([flight-model.md](flight-model.md) §9.16).
- **The cockpit zoom one way per scroll; every jet's view alike (2026-11-11, the Mac play test's P1):** each wheel or
  trackpad step narrows the view (the true size kept between the wide and the narrow view; a step against the scroll
  dropped until it pauses), clamped at both ends; the trackpad zooms too. The Barak, the Sufa and the F-35I open at the
  same wide view, the F-16s at the same eye ([cockpit.md](cockpit.md) §2). Home's Pilot log entry removed: the pilot
  block → the Pilot screen's Pilot log button ([front-end.md](front-end.md) §3). `test_cockpit_view.gd`,
  `test_front_end.gd`. Open: the Barak's view looked closer on the Mac; at default settings both jets render the same
  view (only the HUDs differ: the Barak's Block 50 frame against the Sufa's wide-angle glass).
- **Mouse look in the cockpit (2026-11-11, the Mac play test's finding 9):** hold the right button and move the mouse
  to turn the head, double right-click to centre it; the wheel zooms from the wide view through the true size to a
  narrow 20° view for reading the MFDs. The left button stays on the switches. No head lean with the mouse
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd`.
- **The HUD stays on its glass (2026-11-11, the Mac play test's finding 10):** looking down or aside at the dash the
  HUD's symbols stay on the combiner glass while any of it is on the screen; the DASH takes over only once the glass
  is out of view ([cockpit.md](cockpit.md) §4, docs/cockpit.md "3D cockpit").
- **The F-16s' canopy switch and yellow lock lever (2026-11-18, the user: "bring it back with the right switch and
  yellow thingy"):** on the left side wall under the canopy sill, modelled after a photo of the real jet and fitted to
  it from the photo's camera. The switch held runs the canopy, the lever down locks it and puts the CANOPY light out;
  Ctrl+K does the whole sequence ([cockpit.md](cockpit.md) §5.6). The grey rod drawn on the sill from 2026-11-11 was
  removed the same day (the user: "remove the f16 cockpit handle. It isn't right for sure"). Open: no marking, the
  jettison T-handle and a two-seater's own wall, for want of a picture.
- **The F-16s' DED DATA and DEPR RET switches (2026-11-19, waiting for the user's yes, A62):** the HUD remote control
  panel's third and fourth switch move and are clicked as its other four; each a click or its key (Alt + D, Alt + R)
  ([cockpit.md](cockpit.md) §5.11).
- **The hands on the stick and the throttle (2026-11-11, the Mac play test's finding 12):** the left glove holds the
  throttle's grip and follows it over its travel (two shape keys in `f16_pilot.glb`); the right glove holds the stick
  ([cockpit.md](cockpit.md) §5.3).
- **The start-up checklist card, one step at a time (2026-11-11, the Mac play test):** a start-up flight opens with the
  checklist card only; the card is smaller and shows the step to take now with its key, place and wait, and its number
  of the steps ([training.md](training.md) §7.1). Replaced by the pilot's notebook on 2026-11-13
  ([training.md](training.md) §11).
- **The radio lines at subtitle size (2026-11-11, the Mac play test):** 20 px at 1080, was 26
  ([front-end.md](front-end.md) §8). `test_flight_ui.gd`.
- **The F12 info line: the mission and the FPS (2026-11-11, the Mac play test):** the sim's line leaves out the 1998
  game's modes, place, speed and controls (`Settings.info_line_full`, [front-end.md](front-end.md) §8).
  `test_flight_ui.gd`.
- **The black world with TAA or Upscaling (2026-11-12):** with Anti-aliasing TAA, or Upscaling Quality / Balanced,
  the 3D cockpit's own picture lost its alpha and laid black over the whole world (reproduced on Linux, Iris Xe, with
  the player's settings; each of TAA alone, FSR 1 alone and FSR 2 did it). The cockpit's picture is now drawn at full
  size with MSAA 4× whenever the flight uses TAA or an upscaler ([cockpit.md](cockpit.md)).
- **Finding the Mac's black world (2026-11-11):** a flight's start on the Mac ended in a black world under a fine 3D
  cockpit. A bisect switch now turns graphics features off for one run (`IAF_SAFE=all ./start-modern-iaf`, then half
  the names back on per run); after the first 10 frames the log lists every shader in use and whether it compiled,
  and a failed one opens the crash page; the start watch covers those frames too, and a pause no longer counts as a
  hang (a 30 s frame only logs `hang:`: a Mac's first start can compile shaders that long in one frame) ([front-end.md](front-end.md) §11.1). Fixed on suspicion, not yet seen on a Mac:
  the Levant sky's `acos` of a direction a hair over 1 gave NaN, which Metal carries into the radiance map, the fog
  and the ambient light (`atmosphere.gdshader`, also `normalize` of a zero vector looking straight down and two
  reversed `smoothstep` edges; the same `acos` in `cloud_layer.gd`, an `exp` overflow in `city_glow.gdshaderinc`); and
  the cockpit's picture no longer goes through MetalFX, whose output need not keep its alpha (an opaque cockpit
  picture would lay black over the world; `cockpit_origin.gd`). Open: the Mac's log with these.
- **A flight's start: no hang, faster, watched (2026-11-10, the Mac's P1 finding):** the mission card opened at the
  start under the loading screen and froze the flight, so the loading never ended on a player's machine (every
  scripted run skipped the card); the card is gone since 2026-11-13. The jet, the 3D cockpit and the pilot's body parse on
  worker threads from the start; the jet, the cockpit and the weapons are each drawn first in their own frame, named
  on the bar. Ramon's take-off from the flight scene: first start (no shader cache) 18.1 s, was 26–48 s; warm 4.4 s,
  was 5.1 s ([front-end.md](front-end.md) §7). A watchdog opens the crash page (§11) when the loading stops; every log
  line starts with its time ([../../docs/logs.md](../../docs/logs.md) §2). `test_start_watch.gd`.
- **The folder `modern-iaf/` (2026-11-10, [plan.md](plan.md#decisions-of-10-november-2026)):** the code folder was `iaf-2026/`; the game
  launcher is `./start-modern-iaf` (+ `.ps1`). Built data in `assets/converted/iaf-2026` moves to `converted/modern-iaf` on the
  first run of a launcher, the wizard or `iaf-sim` ([setup.md](setup.md)).
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the F-15C Baz's data and Tel Nof (2026-11-09):** the Baz's unit record
  (`data/db/units/f15c.json`) compiles into the sim's bdb, and Tel Nof (LLEK, from OpenStreetMap and OurAirports) is
  the fifth base `iaf-sim airbases` compiles, with a Baz parking spot and a paved taxi path to 33L
  ([airbases.md](airbases.md)). `sim::tests::every_data_file_compiles_and_loads`,
  `sim_bases::tests::the_departure_is_paved`.
- **Compact JSON (2026-11-09, [plan.md](plan.md#rules-the-user-3-november-2026) rules):** every JSON file the
  sim writes is on one line ([data-formats.md](data-formats.md) §7).
- **The cockpit sound model (2026-11-09, Approvals A13, branch `wt/iaf-2026-cockpit-sound`, waits for the user's
  listening):** from the cockpit the outside sounds (engine, airframe, weapons, the world) come through the canopy and
  the HGU-55/P's ear cups: a 166 Hz low-pass and a level per class; the radio, Betty and the tones are unchanged; the
  external views hear everything unmuffled. The gun comes through the structure (a 700 Hz low-pass) and sits 5 dB
  over the engine and the wind, as in a cockpit recording (it was 6 dB, unfiltered). The wind stops at its row's level from 450 kt ([sound.md](sound.md) §1.9). The original
  game keeps its buses. `test_mvp.gd`, the original's `test_sounds.gd`.
- **The core sounds against real references (2026-11-09, Approvals A12, branch `wt/iaf-2026-core-sound`):** the
  dry engine plays its idle recording at its own pitch at idle (it was 4.2 semitones up) and rises to 1.3 and 6 dB at
  military; the start plays a JFS whine (its partials measured on an F-16 start), the engine's pitch and level by its
  RPM, a light-off thump and the JFS winding down at the generators; the gun buzzes at 100 rounds a second (it was
  48); the wind follows the dynamic pressure; the canopy closes at its checklist step; the touchdown is an airplane
  tyre skid with a thump, not a bicycle squeal ([sound.md](sound.md) §1.3–§1.8). The original game keeps its rules.
  `test_mvp.gd`, the original's `test_sounds.gd`.
- **The ground as the original game's (2026-11-13, the user's order):** the sim renders the ground with the
  original game's values (one set of terrain shader globals in both projects; Sky Atmospheric, Colour grading
  Original): no gold tint, no detail gain, no Levant haze; the Judean hills' gold speckle is gone. Its 2 m photo is
  levelled per sheet as the original game's (no match to Sentinel-2), its 4 m and 8 m levels built from it, its grey
  hills warmed as that layer's: the ground reads as the original game's photo. A rebuild of the theatre's photo
  (setup's terrain step "will run", nothing to download). Pictures in [terrain.md](terrain.md) §15.
- **Steady taxi lines (2026-11-15, the user: "the yellow marks on taxi way show strange if even a bit far"):** the
  yellow taxiway centreline is one thin line from the cockpit at every distance, fading with it, from the air too;
  before, it broke into dashes and blobs and vanished along the view (the shared shader's line read from a 2 m
  distance field, [rendering.md](../../docs/rendering.md) §7). The original game's Detailed airbases get the same fix.
- **Signs and taxi routes to the runway's start (2026-11-15, awaiting the user's yes on the pictures; the user: "ab
  signs should lead to runway start only, not to the middle of the runway, it's confusing"):** a direction sign's board
  leads only to a runway's start (a way may cross a runway on its way there); a mid-field intersection keeps its
  holding sign with both ends, and no board leads there. The departure the briefing draws and the tower clears keeps
  to the taxiways to the start instead of back-taxiing on the runway (Ramon, Ramat David, Tel Nof), so it agrees with
  the signs. Since 2026-11-16 every sign a departure to any runway end passes names that end with the route's turn
  (Ramon's way to 25R read "25L" alone; now "25L 25R" on the shared parallel taxiway). A rebuild of the airbases step (nothing to download) ([airbases.md](airbases.md) §9,
  [data-formats.md](data-formats.md) §12).
- **The borders (2026-11-15, approved 2026-11-17: "A52 approved"; the user: "the change between israel and other
  country looks bad"):** Sentinel-2 beyond the photo's edge (Lebanon, Syria, Jordan, Egypt, Gaza) toned to the
  photo's colour and brightness along the border, fading out over 10 km, with the bases' colour map per 16 km block
  ([terrain.md](terrain.md) §4). A rebuild of the theatre's border units (setup's terrain step, then the scenery:
  nothing to download). Since 2026-11-25 ("tone7") Sentinel-2 at the photo's edge takes the photo's own colour there
  (a local match over 2 km) and the photo fades onto it over 200 m, at the border and at the sheets' fill inland (the
  user: "the shim between tiles can look better"). Open: Sentinel-2 stays softer (10 m) than the photo (2 m) beside it, and in the 200 m fade its own ground shows where it differs from the 2015 photo (a tan patch beside the road west of Ramon); on a theatre built before, the border units over 10 m tiles not kept on disk
  stay untoned (nothing is fetched for them).
- **Ramon filled (2026-11-19, approved by the user the same day):** 40 hardened shelters (12 with a parked
  Sufa), 10 hangars, 14 buildings, the tower, a sunshade, the fence and ramp vehicles beside the player's spot, placed
  from Sentinel-2 and OpenStreetMap; door lamps and obstruction lights at night ([base-furniture.md](base-furniture.md)).
  Our own simple shapes, no download; GPU +1 ms over the base on the Iris Xe; a rebuild of the terrain and airbases steps (nothing to download).
- **Hatzerim, Nevatim, Ramat David and Tel Nof filled (2026-11-19, the user's order "do it for all air bases"):** the
  same method and shapes as Ramon's: shelters, hangars, sunshades and buildings from OpenStreetMap, Sentinel-2 (the
  2015 photo at Nevatim) and roofs placed by eye; parked Sufas at Hatzerim, F-35Is at Nevatim, Baraks at Ramat David;
  door lamps and obstruction lights; GPU up to +1 ms on the Iris Xe ([base-furniture.md](base-furniture.md) §2.1, §6). Open: no parked F-15 (no F-15 model
  of our own), so Tel Nof's shelters stand empty.
- **Shelters open at the back (2026-11-20, the user's order: "completely open in the back, not like now"):** every
  shelter's back is open, as wide and high as its door, with the same concrete lip ([base-furniture.md](base-furniture.md)
  §5). The shape is built in the game: no rebuild, nothing to download.
- **Start in a shelter (2026-11-19, the user's order of 17 Nov: "if there are shelters then start inside one"):** at Ramon,
  Nevatim, Ramat David, Tel Nof and (Sufas) Hatzerim the jets start cold inside shelters, nose to the door, four per unit (Ramon's Sufas in the loop-end
  shelters S2, S3, S1 and S5, the ground power unit and the extinguisher beside the leader's jet). Each parking spot has its own taxi route out of its door along the
  taxiways to the runway and back; the AI, the briefing map's taxi line, the tower's flow and the paved surface follow
  it ([airbases.md](airbases.md) §5). A base names its start shelters in `data/parking.json`. Nevatim's taxi
  is now about 3 km (from 0.3 km). Hatzerim's Sufas since a later change the same day, in S5, S6, S1 and S4 by 28L:
  the sign builder no longer puts a board on a shelter's concrete or an arrow that fits two ways
  ([airbases.md](airbases.md) §9). Open: Hatzerim's F-15I unit (not yet flyable) stays on its sunshade row, for want
  of three more shelters with room for a taxi besides S2 ([airbases.md](airbases.md) §5). A rebuild of the airbases and missions
  steps (nothing to download).
- **The airbases from the air (2026-11-14, built, awaiting the user's yes on the pictures):** the bases' Sentinel-2
  fill toned to the photo around (no tan block; one colour map per base from the medians of the ground around, an odd
  Survey sheet left out, Sentinel-2's brighter dry grass brought down to the earth tones around); the painted
  runways, taxiways and aprons out to 28 km, kept at their paved share far away, their asphalt darker so they read
  on that ground. A rebuild of the theatre's base units (setup's terrain step, then the scenery: nothing to
  download) ([terrain.md](terrain.md) §4, [airbases.md](airbases.md) §9). Open: the bases stay softer than the 2 m
  photo (10 m pixels).
  `test_sim_look.gd`, the original's `test_terrain.gd`.
- **Towns in the air photo's colours, the roads to the buildings' range (2026-11-13, look study A20):** each roof in
  its own colour from the air photo with solar heaters, the walls in the palette's colours chosen by the photo around
  each building, ribbon windows, a sun / shade step, grey city pavement (moot since the gold tint went), and every road drawn
  as dark asphalt to 5.5 km (was 1.5 km). Needs the scenery step again (no download) ([scenery.md](scenery.md) §7).
  Open: Scenery Detailed keeps its own near roofs; far shadows and contact shading (the grounding round).
- **The ground against a photo of Makhtesh Ramon (2026-11-11, Approvals A17, causes 1 and 2; dropped 2026-11-13,
  [terrain.md](terrain.md) §15.1):** a golden tint
  on the land at every hour, through Colour grading Natural (the albedo × `terrain_grade_tint` 0.86 / 0.78 / 0.43; the
  sea, inland water and the airbases' pavement keep their colour), and the photo's detail ×4.5 (it was ×2.5). The Ramon view's ground reads
  150 / 118 / 66 against the photo's 149 / 118 / 63 (it was 160 / 134 / 105); its spread 18.4 within the photo's 23.4.
  No GPU cost. Pictures and numbers in [terrain.md](terrain.md) §15.1. `test_sim_look.gd`, the original's
  `test_terrain.gd`.
- **[B4](plan.md#b4-ground-look-parity), the ground as good as the original game's (2026-11-09):** the pale,
  washed-out desert (sand 208 / 192 / 171) now reads tan with its relief (177 / 152 / 120): Colour grading Natural
  takes the photo toward a real ground's reflectance, with a little contrast and saturation after the tone mapper
  (docs/rendering.md §1.9). The close up's patches are back in tone only, the ground textures hold farther out by the
  photo's land cover, a macro tint breaks the photo's repeats, and the sim's setup fetches the ambientCG textures
  itself. Pictures beside the original game's in [terrain.md](terrain.md) §9.1. `test_sim_look.gd`, the original's
  `test_terrain.gd` (its picture unchanged with the rows off).
- **The afterburner sounds like an F-16's (2026-11-09, the Mac play test's finding 27):** measured against an F-16
  hush-house run and take-offs, the burner now rises over 1.5 s with a low thump at light-off, dies away over 1.3 s
  at the cut, sits 6 dB over the dry engine, and is a real RNLAF F-16's roar with no pulse and no pitch shift
  ([sound.md](sound.md) §1.2). The original game keeps its rule. `test_mvp.gd`, the original's `test_sounds.gd`.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), the sea and the shore's ground (2026-11-08):** the sea is one
  surface: Sentinel-2's from the beach out, with no Survey photo (its white no-data patch, its lighter blocks) beyond
  the coastline, and the open sea's fill in the composite's own tone, so its edge no longer shows as steps
  ([terrain.md](terrain.md) §3, §12). Near the camera the ground keeps the close up's grain and relief without its
  colour patches, which had speckled the pale desert orange ([terrain.md](terrain.md) §13). Pictures before and after
  in [scenery.md](scenery.md) §7. `sim_terrain::tests::the_shore_follows_the_coastline`.
- **[B2b](plan.md#b2-the-airbases) / [B3](plan.md#b3-scenery-roads-and-inland-water), the bases' ground and the shore (2026-11-08):** the taxiways and aprons
  are paved for the flight model (no rough-ground crash taxiing out), taxiway signs at the holding points and
  junctions ([airbases.md](airbases.md) §9), the sea follows OpenStreetMap's coastline in the photo and the surface
  flags ([terrain.md](terrain.md) §12), the airbases step downloads the extracts its water needs, and the wizard has
  an optional scenery step ([setup.md](setup.md) §3).
- **The gun (2026-11-08, the Mac play test):** the rounds are the unit record's (Sufa and Barak 511, F-35I 180) and
  run out; our own muzzle flash and tracers; every flight starts with the master arm safe, Shift+A arms
  ([weapons.md](weapons.md)). `test_sim_gun.gd`.
- **The Mac play test's findings (2026-11-08, [plan.md](plan.md#f-the-probe) F):** the mission card (removed 2026-11-13), the radio lines
  in the sim's band wholly in the game's language; the pause menu centred at any size in Hebrew;
  Preferences without an aid or realism row and the aids off; Home on every start;
  clickable breadcrumbs ([front-end.md](front-end.md) §1, §8). `test_flight_ui.gd`, `test_front_end.gd`.
- **Keys and Joystick (P1, 2026-11-08, the Mac run's "keys / joystick mapping"):** Settings → Devices opens a
  Keys screen (every command the sim has, by group; click and press to rebind, Cmd on macOS, conflicts with Swap /
  Use it here, Default, Reset all) and a Joystick screen (the devices, each axis' role with a live bar, Invert and a
  dead zone, the buttons and hat bound by pressing them, Reset all), in English and Hebrew. The keys and
  buttons are `Settings.key_bindings`, the store reborn uses too (2026-11-14; an older `devices.json`'s move there once);
  the axes are in `user://devices.json`, read and written by Rust (`IafDevices`). The Thrustmaster Hotas X has its own default map (`modern-iaf/data/devices/`), and a joystick connecting no
  longer asks for the install's `menu/joy` ([front-end.md](front-end.md) §9). On macOS the keys start from the
  laptop map, no numpad: the rudder on Z / X, the snap views on Alt + 1–9 (§9.1). `test_devices.gd`, the M0 probe
  with a fake joystick.
- **The Mac findings batch, devices and front end (P1, 2026-11-11, [front-end.md](front-end.md) §1, §2, §9):** the
  Joystick screen's bars show each role as the flight reads it (`Joystick.role_value`, one sense for the poller and the
  bars): the throttle forward is a full bar, checked against the 1998 game's events axis by axis (`test_devices.gd`);
  the afterburner detent on Settings → Devices (reborn's Detent = MIL rule, `Joystick.detent_choice`); the hat is
  reborn's POV again (the sim's own four hat buttons dropped the diagonals), its eight directions the snap views; the Keys and Joystick side lists follow the scroll and both
  screens have Back; one head-look key set (the snap views; F2 rear view and the Shift free look are empty slots);
  on macOS the keys say ⌘ and Option; Home has Guides and Training has Missions and campaign, both greyed with
  "Coming in a later version"; Pick a plane picks on a click (no Next, no card picked on entry, the arrows move the
  focus, Enter picks).
- **Devices: a second device's buttons, twin devices (2026-11-25, the gaps list's row 16, [front-end.md](front-end.md)
  §9.2):** a throttle's or pedals' button binds on the Joystick screen by pressing it and works in flight, shown with
  the device's name ("Pedals · Button 3"); two devices with the same name are told apart by the order they were plugged
  in (the second is "<name> #2" and keeps it while the first is out). A device with no SDL mapping gets ours, its
  buttons 12 and up off the hat's indices (`test_joy_hotplug.gd`: a fake one's button 12 raises the gear).
  `test_devices.gd` `second`, `test_joy_hotplug.gd`, the `devices` unit tests.
- **The scenery inside its GPU budget (2026-11-25, the gaps list's row 17, [scenery.md](scenery.md) §6):** on the Iris
  Xe 500 m over Tel Aviv the buildings and trees take 5.6 % of the GPU time (14.8 % before), over Beersheba
  6.9 % (13.0 %); the budget is 7 %. The buildings lit per vertex, their shadows from a copy with no material,
  their far parapets and windows' work left out; Far towns Light (the sim's default) ends the trees at 1.2 km.
  A flash, a landing light or an apron's floodlight lights the buildings within 300 m of it per pixel, so its pool
  on a wall shows as before.
- **Devices: a second device and hot-plug (2026-11-25, the gaps list's row 16, [front-end.md](front-end.md) §9.2):** a
  role's axis may sit on a second device (a throttle, rudder pedals), stored by the device's name; the Joystick screen
  lists every device's axes; a device plugged in mid-flight works from the next frame, one pulled out centres its stick
  and rudder axes and gives their keys back. The hat's diagonals were already one look direction (reborn's POV since
  2026-11-11). `test_devices.gd` `second`, `test_joy_hotplug.gd`, the `devices` unit tests.
- **The play test's polish (2026-11-09):** the Preferences back to the side layout (the sections listed, the picked
  one beside them, no line under an option); a Sound slider plays a sample of its class; Devices → Joystick greyed
  until a stick is plugged in; the Pilot screen (name, nickname shown on every screen, a 3:4 ID photo; records schema
  version 2); the loading bar follows the flight's real loading steps, named under it; the throttle up from OFF is the
  start-up's idle step (Ctrl+I gone); no drag-chute warning per flight ([front-end.md](front-end.md) §1, §4, §7, §9.2;
  [training.md](training.md) §7.1). `test_front_end.gd`, `test_devices.gd`, `test_mvp.gd`, the pilot_log unit tests.
- **The Pilot screen's findings (2026-11-10):** the nickname field editable (a hint in place of the name); Save and
  Back (a discard prompt); the picture opens the file picker; Reset the log after a warning and a second confirm;
  several pilots (a list, New pilot, the active one in `settings.cfg`); the first start makes the profile before Home;
  the logbook per plane on the Pilot screen, Home with the name and nickname only (records schema version 3, the
  sortie's plane) ([front-end.md](front-end.md) §1, §3; [storage.md](storage.md) §5). `test_front_end.gd`, the
  pilot_log unit tests.
- **Home's pilot block and Delete profile (2026-11-10):** Home's nickname, name and picture are one button to the
  Pilot screen; the Pilot screen keeps only the fields' labels and hints; Delete profile removes the pilot, its log
  and its picture after two confirms ([front-end.md](front-end.md) §1, §3). `test_front_end.gd`, the pilot_log unit
  tests.
- **The engine shutdown (2026-11-11):** Throttle OFF (Shift+1) cuts the fuel: the RPM winds down over about a minute,
  the generators drop at 52 % with the displays, the HUD and the avionics, the FTIT falls, the engine loop pitches
  down and fades; the recording's `checklist` step `cutoff` with fault `shutdown` / `no_start` fails a training
  mission; the JFS below 20 % and the throttle up from OFF restart it ([training.md](training.md) §7.2). `test_mvp.gd`
  (shutdown), the start.rs and training.rs unit tests. In the air (2026-11-25, [training.md](training.md) §7.2): the
  engine windmills (20 % at 250 kt), the throttle up from OFF relights it from 12 %, the JFS below 20,000 ft and
  400 kt; the F-16's EPU keeps the displays up while it runs, the F-35I's IPP for good.
- **The HUD's light (2026-11-09, Approvals A10):** the F-16s' HUD in the P43 green, drawn over the scene, bright by day
  and dimmed to a night floor as the sun sets, with a faint halo, the original's thin pen and the combiner glass
  untinted (2026-11-13; a quarter of 14 % before); the 3D cockpit's SYM wheel sets the day level (hover, wheel, drag; kept in the settings file) and Shift + H steps
  it, on the general clickable-control layer `cockpit3d_controls.gd` ([cockpit.md](cockpit.md) §5.1). The F-35I's HMD
  BRT knob turns the same level, its MFD BRT knob the displays' brightness (kept in the settings file too); the F-35I's
  helmet display lights as the HUD does, in P43 at that level. `test_hud.gd`, `test_mvp.gd` `_knob`. The F-16s' DAY / AUTO BRT / NIGHT switch on the right console (2026-11-11):
  clicked or scrolled, DAY keeps the day level at night, NIGHT the night floor by day, AUTO follows the sun; kept in
  the settings file (`test_mvp.gd` `_hud_mode`).
- **The HUD on a 2× display (2026-11-11, the Mac play test):** the HUD keeps its angular size, stroke and text crispness
  at every display scale: the pen's least width and the texts' raster size are physical pixels
  ([real-hud.md](../../docs/real-hud.md#modern-iafs-hud-light) "Display scale"; the rule holds in both games). The
  stroke is the original game's thin pen (0.87 mrad), the halo 0.73 mrad outside it and at least one pixel (an angle
  since 2026-11-13: one pixel at every size before), and the HUD is drawn over the scene instead of
  added (no white core over the sky), so it reads as crisp as the original game's Real HUD. The Mac's pictures matched Linux at scale 1: its "closer view" and
  "twice the size" came from an enlarged crop, and the glass is untinted. The side edge strips beside the
  HUD are removed (2026-11-12). The AoA indexer and AR / NWS bodies beside the posts' feet take the glareshield's
  paint (they drew flat black) and stand 2.5 cm outboard of them, clear of the posts as in the F-16C photo
  (2026-11-13). Their lamps are seen whole from the eye (their hoods aim at it), glow bright enough to read by day and stay
  dark when off (2026-11-16,
  [cockpit.md](../../docs/cockpit.md) "3D cockpit" lamps). The Sufa's combiner is the F-16I's: a flat rectangular plate, green tinted, leaning
  aft 42° between two straight thin side plates (2026-11-18, waiting on the user's approval).
  A 1× monitor beside a Retina screen (the user's Dell): Godot renders it at twice its pixels and the system halves the
  picture. The 14 Nov switch to the monitor's own pixels (hiDPI off) was reverted on 15 Nov at the user's word: with
  Upscaling Quality the cockpit came out soft there. Open again: the HUD's thin stroke on that monitor, two half-lit
  pixels (real-hud.md "A 1× monitor beside a Retina screen").
- **The start-up lesson's lines and waits (2026-11-17, the user: "it needs 2 clicks. the checklist isn't clear
  enough", "I also see align on the hud but no idea how to do that", "it takes to long after finishing the startup to
  get the mission accomplished screen"):** each line says the position and the clicks, the waits say WAIT, the
  notebook and the ring say what the current step still misses, the INS step goes on to NAV after the alignment, the
  alignment's 90 s wait is the INS step with a countdown (it was a silent wait after the last step) and the pass comes
  within a second of NAV, and the take-off lessons ring the start-up's
  switches ([training.md](training.md) §7.1). The radio menu marks no call ("(next)" removed). `test_lesson_steps.gd`.
- **One click sound a click (2026-11-17, the user: "the clicks on the panel are happens twice for every click I
  think"):** an ICP key's click sounded three times and entered once; every control now sounds once a click
  ([cockpit.md](cockpit.md) §5.2). `test_one_click.gd`.
- **The pilot's body off the switches (2026-11-17, the user: "I am unable to click the main power on the second
  traininig"):** Alt + H hides the body while held, Alt + G for the flight; the first lesson hides it while it covers
  the ringed switch; the body never took the click ([cockpit.md](cockpit.md) §5.3). `test_lesson_clicks.gd`.
- **No white cockpit flashes with Upscaling (2026-11-17, the user: "the cockpit goes white, brighter for a sec when
  it jumps for a sec when starting the first training", "also moving the view doing white flashs"):** the sharp
  layer's exposure grey is solid geometry that holds still, so the Mac's temporal upscaler keeps it whole; the cockpit
  is sharp with Upscaling again (2026-11-18, [cockpit.md](cockpit.md) §6.3). `_cockpit_flash_shot.gd` (real render).
- **One lean control and the full MFD view (2026-11-18, the user: "Ok hud is more important. So have a lean button +
  full MFD view", "Why need lean in arrows and also in other keys?"; approved):** Shift + arrows / Page Up / Page Down
  held lean the head (6 cm aside, 10 cm forward and on to 30 cm, the F-35I 2 cm) and the release brings it back
  (records 126–131, command 204); Shift + , / . show the left / right MFD close up with every push button on the
  screen, the F-35I's panoramic display from either key, and the same key or Esc goes back (records 198 / 199,
  command 207). From the seat the F-16s' two top inboard buttons of each MFD and the right MFD's GAIN rocker stay
  behind the ICP's corners, as in the real jet; the lean and the full view show and click them
  ([cockpit.md](cockpit.md) §2, "The MFDs from the seat"). `test_mfd_buttons_seen.gd`, `test_cockpit_view.gd`.
  Owed: the real-window run of the test on the Mac. The views moved from Shift + N / M to Shift + , / . the same day:
  Shift + N is the night-vision goggles' key (`terrain_view.gd` `_own_key`), and the manuals' build now stops when a
  key `_own_key` reads has no row in `modern-iaf/manuals/own_keys.json`. The goggles got their own record on
  2026-11-19 (record 255, command 303; the F-16s' goggles entry above).
- **Zoom toward the pointer and the lean (2026-11-15, the user's Mac play: "can't zoom in to see things under the
  throttle"):** the wheel zooms the 3D cockpit toward the point under the pointer; Shift + arrows / Page Up / Page Down
  lean the head (records 126–131, command 204; held since 2026-11-18, the entry above) short of the cockpit's surfaces,
  the pilot's body hidden while leaning, so the ELEC panel under the left glove, the consoles and the lower pedestal
  show close up; a switch under the pointer leaves the wheel to the zoom ([cockpit.md](cockpit.md) §2).
  `test_cockpit_view.gd`.
- **The start-up lesson's guidance on every step (2026-11-15, the user: "it never shows the avionics panel to turn it
  on"):** the F-16s' avionics step outlines the AVIONIC POWER switches still off (it showed none); `test_mvp.gd`
  checks on every start-up step of the Sufa, the Barak and the F-35I that the guidance names the step's control, that
  it is outlined on the screen once the head is on it, and that it moves on only as switches are done
  ([training.md](training.md) §11).
- **The NOZ POS needle glides (2026-11-16, the user: "in the right, you have 4 gauges. the second move by the
  throttle, but jump"):** the right eyebrow's second gauge is NOZ POS; each AB stage jumped it 50 % in one frame. The
  nozzle now follows with a 0.8 s lag (`iaf_flight::instruments::NozzleLag`); OIL, RPM and FTIT were already smooth
  (measured per frame). The F-35I has no round engine gauges (its engine page is on the panoramic display).
- **Click areas and the training outline by shape (2026-11-15, the user's Mac play):** a 3D cockpit control's hit area
  is its mesh's own surface (the nearest along the pointer's ray: never bigger than the part, never a neighbour's);
  the training highlight outlines the switch's own shape and the RPM dial as the ellipse it
  shows (it had circled the NOZ POS gauge). Every control of the three jets checked at 1,280 x 720 and 2,560 x 1,440
  (`_click_areas_shot.gd`; [cockpit.md](cockpit.md) §5.1, [training.md](training.md) §11). `test_switches_click.gd`.
- **The start-up switches (2026-11-09):** the F-16s' start-up checklist by the mouse in the 3D cockpit: MAIN PWR, the
  JFS switch, the throttle, the AVIONIC POWER switches, the INS knob (their own nodes of `f16.glb`, each turning to its
  on position), each sending its key's command (the canopy its switch and lock lever since 2026-11-18); the card names each switch
  and its
  place ([cockpit.md](cockpit.md) §5.2). The F-35I's the same on its own panels: BATT, IPP, ENG (or START, or the
  throttle) and CANOPY, new nodes of `f35i.glb` at inferred places. `test_mvp.gd` (the Sufa's and the F-35I's
  start-up by clicks). Open: the JFS switch's spring back to OFF, the INS knob mostly hidden by the right sill from
  the eye, the F-35I's ENG guard.
- **AVIONIC POWER switches one by one, the AoA at rest on the ground (2026-11-11, from the user's Mac):** a click
  throws one AVIONIC POWER switch with its click; the four on take the step; MFD powers the MFDs, UFC the DED
  ([cockpit.md](cockpit.md) §5.2). The AoA gauge, indexer and HUD rest at 0° below 60 kt and follow the flow above it
  through a 0.25 s lag (§5.4). `test_mvp.gd`. FCR and RDR ALT: FlightGear's console has both as own parts; clickable since
  2026-11-13.
- **Town labels: dropped from the sim (2026-11-11, the Mac play test):** the sim draws no town names over the view and
  Settings has no "Town labels" row; the sim's profile fixes the switch off. The 1998 game keeps its own (Extras →
  "Town labels", [../../docs/scenery.md](../../docs/scenery.md) §3.5). [scenery.md](scenery.md) §7. `test_sim_look.gd`,
  `test_front_end.gd`.
- **The moon, the stars and dark nights (2026-11-25, the user: "night should be much darker [...] real dark based on
  the moon phase based on date"; [terrain.md](terrain.md) §17.1):** the moon at its real place and phase for the
  flight's date, hour and place (a mission without a date: today's), drawn lit on its sun side; the night's light in
  lux from the twilight, the moon and the stars drives the ambient and the moon's light (no moon shadows: +3 ms,
  dropped), the Volumetric clouds' night light and the goggles' grain. A moonless night is near black; a full moon a dim
  grey. The stars are the Yale Bright Star Catalogue's 5,080 (public domain, credited) at their real places. The
  1998 game keeps its fixed moon and random stars. `test_night_moon.gd`.
- **Wall shading and long shadows (2026-11-09, the look study's proposal 5):** the buildings' walls away from the sun
  take less sky light, and Settings → Graphics "Long shadows" (on by default) draws the sun's shadows to 2.5 km with
  the near buildings casting them; +0.5 ms on the Iris Xe ([scenery.md](scenery.md) §7). `test_scenery.gd`. Open: at
  the Shoham pose the change is small (the sun behind the camera), so the reference's shaded street sides are still
  apart.
- **The jet's shadow sharp (2026-11-25, the 19–20 Nov look pass's "jet shadow pixelated"):** past 40 m from the
  camera a jet's shadow fell in the sun's second shadow cascade (15 cm a texel with Long shadows) and showed blocky.
  The outside views now fit the first cascade to the followed jet and its shadow on the ground, so from 60 m and at a
  low pass it is about twice as fine; no measurable GPU cost on the Iris Xe
  ([../../docs/rendering.md](../../docs/rendering.md) §3.1 "The first split"). Within 40 m the shadow keeps its 3 cm
  texels: finer needs the 8192 atlas, +1.7 ms on the Iris Xe, over the budget. `_jet_shadow_shot.gd`.
- **The cockpit holds still (2026-11-09, the Mac play test's finding 25):** far from the flight's start the whole
  cockpit jumped against the eye (32-bit floats: 3.1 mm steps 30 km out, 4.4 mm at 60 km). The sim draws the cockpit
  in its own world about the origin and lays it over the flight's view ([cockpit.md](cockpit.md) §6.2): it no longer
  moves against the eye at any distance; about +4 to +5 ms GPU a frame on the Iris Xe. `test_sim_look.gd`.
- **The world holds still far from the start (2026-11-25):** the floating origin keeps what is drawn near the camera
  within 4 km of Godot's origin (the jets near the camera, the effects, the outside views), so 300 km from the start
  nothing rounds to centimetres; the sim's positions, hits and the picture are as before
  ([../../docs/rendering.md](../../docs/rendering.md) §11, `test_floating_origin.gd`).
- **The ILS bars glide (2026-11-09, the Mac play test's finding 24):** the HUD's ILS lines sit at the exact
  deviation instead of the original's whole-pixel steps, which jumped about 5.5 screen pixels at a time on the 3D
  HUD glass ([real-hud.md](../../docs/real-hud.md#what-ours-draws-status)). `test_mvp.gd` checks all three jets.
- **The F-16s' loadout (2026-11-08, the Mac play test):** the Sufa and the Barak fly with an AIM-9M on the wingtip
  rails and on stations 2 / 8 and 3 / 7 and a 370 US gal tank on each inboard pylon, so the look back shows the stores
  instead of a bare rail and pylons ([data-formats.md](data-formats.md) §3). The Python and AIM-120 records (the
  AIM-9M stands in) and the tank's drag are open.
- **The sim's own look (2026-11-08, the Mac run):** the look switches whose 1998 value draws art the sim does not
  have are fixed to ours in `PROFILE`: Detailed airbases (the runways, taxiways and aprons were missing), the
  atmospheric sky, water, night lights, effects, the conformal ladder; the CC0 ground and model textures when setup
  downloaded them ([airbases.md](airbases.md) §9). `test_sim_look.gd`.
- **[E2](plan.md#e2-the-front-end), the front end (2026-11-08):** `./start-modern-iaf` opens Home; Pick a plane, Training, Pick a mission, Fly,
  the flight, its debrief sheet, the Pilot log, Preferences and Attributions, in English and Hebrew (mirrored), in the
  round-3 look ([front-end.md](front-end.md)). Esc over a flight opens the pause menu. `test_front_end.gd`.
- **The mission briefing, map first (2026-11-14, the approved mock r3_briefing; finish list F2):** the map fills the
  screen and opens on the base and the route, the pins numbered as the text's paragraphs; since 2026-11-15 the text card says what
  you will learn and how to fly it in prose, the keys as bound, scrolled by the wheel, the keys and the gamepad (every
  mission's texts in English and Hebrew, mission data `briefing`); the mission card holds the missions as tabs with
  their pass chips, the facts, the objectives, the Arming summary with Edit, Back, Arming (key A) and Fly; the
  map's chips turn the taxi route, the labels and the photo off and zoom. The whole map's rectangles of other tones are
  the Survey of Israel sheets' own levels (terrain.md §10, Open). From 2026-11-09: one zoomable map (the theatre's
  ground colour, roads, towns, the route, the whole airbase); from 2026-11-15 it zooms and scrolls over the whole theatre,
  its ground tiles, roads and towns loaded for the view (finish list C); Edit on the Arming summary opens the Loadout screen (until 2026-11-14 an Arming page with
  each jet's front view); the subtitles name the tail number and squadron, no wing; the missions' titles are their kinds ([front-end.md](front-end.md) §10, `IafBriefing`). `test_front_end.gd`, `cargo test -p iaf-tools --lib briefing`.
- **The briefing's switch pictures (2026-11-11, awaiting the user's approval):** a start-up's paragraph in the
  briefing's text shows its switch cut from the jet's 3D cockpit with a ring round it and the state to wait for
  (`modern-iaf/data/switches`, `modern-iaf/tests/_switch_crops.gd`; [front-end.md](front-end.md) §10). `test_front_end.gd`.
- **The loadout editor (2026-11-10, awaiting the user's approval; on the Loadout screen since 2026-11-14):** a store
  drags from the stores onto a station, between stations and back; each station takes only what the unit record's `allowed` lists
  (re-sourced per jet, data-formats.md §3; each store its own record with its weight and size), racks (a TER of three
  Mk 82, two GBU-38, four GBU-39) with a "×n" badge that cycles the count, the stores without a model greyed, an
  amber imbalance warning past the F-16's asymmetric moment limit, a refused drop shakes its station; an edit changes
  its own station, and the mirror station too with Mirror on (until 2026-11-15 a drop filled both unless Shift was
  held); the keyboard path (Enter on a station, Enter on a store); the fuel
  and the take-off weight follow, over the maximum it reads red and Fly is off; the loadout is the pilot's per jet in
  the records database and flies with the mission (mass, drag, tanks' fuel, the stores' models), Reset brings back
  the record's ([front-end.md](front-end.md) §10). Since 2026-11-11 the racks' weight rides in flight too (the
  BRU-57/A's 120.2 kg sourced), and since 2026-11-14 every store's and rack's drag index (inferred from its size, none in the F-35I's bays; [flight-model.md](flight-model.md) §9.18), the bombs, guided bombs and tanks hang by their lugs under the
  F-16's pylons (since 2026-11-25 the lugs' tops on the pylons' bottoms at their middles, every store parallel to its
  sloped wing pylon or rail, no gap; [data-formats.md](data-formats.md) §3), and the Python 5 and SPICE 2000 fly as `modern_weapons.gd` records with their public figures. The
  Delilah is dropped for now (the user, 2026-11-14): no store list offers or carries it, as it needs a powered
  cruise-missile flight class the engine does not have; its record stays. Since 2026-11-20 the 600 US gal tank has its
  model (the user: "It should be high in priority"): FlightGear's tank at IMI's 238.5 in by 32.6 in, painted as the
  370, on 4 / 6 under the inboard pylons, and the Loadout screen offers it. Since 2026-11-20 too, the 300 US gal
  centreline tank (the user: "Do the center tank, and in gray, yes"): the real jet's station 5, the engine's 14th
  station (pylon K; the records' 11, shown as 5), on the Sufa (a Commons photo of a Sufa with it) and the Barak,
  FlightGear's tank at its own size under the model's centreline pylon, 0.086 m above the ground with the gear down,
  its fuel on the FUEL QTY gauge at EXT CTR and burnt before the wing tanks';
  and the three tanks (370, 600, 300) are painted the IAF tanks' medium grey, matched to Commons photos of F-16Is and
  F-16Ds (they were the livery's near-white underside) ([weapons.md](weapons.md) §7.3). Open: a Sufa / Barak station
  chart; the 300 gal tank's size (no published figure found; FlightGear's kept).
- **Inventory counts:** no public source gives the IAF's store counts; the records list none, so the inventory is
  unlimited. `cargo test -p iaf-tools --lib loadout`, `test_front_end.gd`,
  `test_mvp.gd --only loadout`.
- **The records in SQLite (2026-11-09):** the sorties and their debrief records are in `user://modern-iaf.sqlite`
  (`iaf_tools::pilot_log`, `IafPilotLog`, a schema version and migrations); its first open imports the JSON records
  from before it once and leaves them in place; Home, Training, the Debrief and the Pilot log read it
  ([storage.md](storage.md) §5). `cargo test -p iaf-tools --lib pilot_log`, `test_front_end.gd`, `test_mvp.gd`.
- **[A4](plan.md#a4-the-gate), the gates on the original's converted data and install (2026-11-08):** every path under
  `assets/converted` a shared script reads goes through `Settings.converted()`, every path under the install through
  `Settings.install()`; the sim refuses everything but its own converted data and the M0 probe fails on any refusal
  (0 today). The sim's own loading screen in English and Hebrew ([front-end.md](front-end.md) §7).
  The flight shows no message texts until the sim's own messages. The effects draw the sim's own sprites since
  2026-11-14 (`iaf-sim own`, [weapons.md](weapons.md) §2; before: a soft dot, the afterburner a white shaft): flares as bright
  points with thin smoke trails. Since 2026-11-16 a flare sinks away under the jet and burns 4 s, chaff stops in the
  air behind it, so both show from a chase view behind the jet too (weapons.md §2); the F-35I's dispensers sit on its
  lower aft fuselage. Since 2026-11-25 a bomb's hit on land is the sim's own: flash, fireball, thrown earth, a dust
  skirt and a broad brown-grey column ([weapons.md](weapons.md) §2 "Bomb hits"; widened and greyed 2026-11-25 after the
  user's review: it was small, narrow and bluish against the photograph).
- **[A3](plan.md#a3-the-setup-wizard), the setup wizard (2026-11-03):** `./modern-iaf-setup` opens the wizard; it builds the terrain,
  the airbases, the units and weapons, the sounds and voices and the training missions as a step graph with stamps (a
  second run is all up to date), in English and Hebrew ([setup.md](setup.md)). Its look is Godot's default theme until
  the user's next round. Since 2026-11-09 Done's **Start the game** opens the front end in the same process
  (Close quits), and Install shows "this step" in the running row and "all steps" from the durations measured on
  earlier runs, or the step count before any run ([setup.md](setup.md) "Time left").
  Since 2026-11-12 every optional step (Buildings, trees and roads; Ground and model textures) has an Include tick
  with its download and disk sizes: a left-out step is neither downloaded nor built, the choice is remembered, and
  unticking a built one offers to remove its data. Each step has its own Run again tick, and a skipped or failed step
  shows its reason (in Hebrew too) with Retry ([setup.md](setup.md) §3). Since 2026-11-13 a required step has no tick
  at all (an older choice file that left one out is ignored for it), and a long "about … left" wraps inside the
  state column instead of pushing the row aside.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), scenery and inland water (2026-11-03):** `iaf-sim scenery` builds the original's buildings, trees, road
  layer and city lights in the sim's UTM theatre from the shared open-data cache ([scenery.md](scenery.md)); the sim
  shows them over its own ground when Scenery is on (Settings → Graphics → "Buildings and trees": Off / On /
  Detailed, On by default, greyed without the step, 2026-11-08); `iaf-sim airbases` flags the Dead Sea, the Sea of
  Galilee, the evaporation pans and the reservoirs as inland water ([terrain.md](terrain.md) §11). Since 2026-11-12
  the sim draws its own road layer (Roads Detailed on by default when the step made it; the probe asked for the
  original game's path before, [scenery.md](scenery.md)).
- **[E3b](plan.md#e3-the-training-missions), the training missions in the game (2026-11-03):** `./start-modern-iaf -- --mission 2011` (… 2032) flies a start-up or
  take-off mission without the front end: parked cold, the start command (Ctrl+E) runs the jet's start sequence on
  the 6-DoF, the screens and the HUD come alive at the real moments; the radio menu (Ctrl+T) asks the base's
  tower for start-up, taxi, line-up and take-off, since 2026-11-13 listing every ground call on the ground (the next one
  marked) and landing in the air, line-up its own call, a call out of order answered "negative, hold position, request
  … first", each subtitle shown as its voice starts; the pilot's own voice makes the call through the helmet chain, then the English TTS tower answers (since 2026-11-12, item A21, [sound.md](sound.md) §5.2); at the end the flight is scored, the
  sortie and its debrief record stored in the records database ([training.md](training.md) §7–§10).
  `modern-iaf/tests/test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. Since 2026-11-08
  a crash, any damage or the wheels off the pavement fail a mission at once with that reason first; a pass is kept
  and the flight goes on until the player ends it (since 2026-11-13); the debrief sheet shows only the mission's goals
  ([training.md](training.md) §3.0, §4). A pass pauses the flight under "Mission accomplished" with Continue the flight and
  Debrief (since 2026-11-15); a fail ends the flight 5 s later into the debrief (no banner since 2026-11-25); an ejection ends the sortie: silent, outside view, Fail "ejected" (§9). Since 2026-11-13 (the
  user: "missions should fail if I start without tower permissions") a take-off mission fails at once on a phase
  without the tower's clearance (the engine start, leaving the spot, entering the runway, the roll), the tower saying
  so (the start-up missions since 2026-11-15 too: the engine start and leaving the spot, after the start-up call as
  their first step); lined up on another runway end the tower names it and the roll there fails; airborne, the goal still missing
  is in the debrief (the live "To complete" line went on 2026-11-25: only radio over the flight, [front-end.md](front-end.md) §8) ([training.md](training.md) §3.3, §9). The start-up
  mission is the real start by keys: the F-16's six-step checklist and the F-35I's battery, IPP, engine, canopy, on
  a card in both languages; a step out of order has its consequence (a hot start, no power) and fails (§7.1).
- **[B2b](plan.md#b2-the-airbases), the airbases in the game (2026-11-03):** `iaf-sim airbases` compiles Ramon, Ramat David, Hatzerim and
  Nevatim into the theatre: `airbases.json` and paved masks (Detailed airbases), an own `iaf.ibx` and
  `terraintype.dat` ([airbases.md](airbases.md) §9); the missions start on the bases' parking spots; the M0 probe
  parks each jet on its spot, on the ground, at a base the flight model finds.
- **[B1](plan.md#b1-the-terrain), the terrain (2026-11-03):** `iaf-sim terrain` builds the sim's theatre `converted/terrain/israel/` from open
  data (GLO-30, Sentinel-2, the Survey of Israel), UTM 36N at 1:1 ([terrain.md](terrain.md)); the sim streams it
  (`theatre_dir()`); the M0 probe flies 5 s over it and checks the heights.
  Every download is shared with the original game in `assets/source/` (the WorldCover tiles in
  `source/imagery/sentinel2/`, also read by `iaf-imagery sentinel2`; the DEM in `source/dem/`): a complete cache
  builds with no network; the heights and the colour build at the same time ([terrain.md](terrain.md) §1.1, §4).
  Since 2026-11-09 the setup downloads only the 14 WorldCover tiles under the 8 m nodes (8.28 GB, before 21 tiles,
  10.62 GB) and reads the other 7 at 20 m over the network (offline, the build stops and says so); the DEM fetch is the shared `imagery_run::fetch_dem`
  (resumes a `.part`); every download logs its MB every 15 s ([terrain.md](terrain.md) §1, §2, §4).
  The Survey sheets' white fill shows Sentinel-2 instead, also where it lies far from the sheets' no-data (since
  2026-11-25: no grey-white blocks west of Ramon; [terrain.md](terrain.md) §4).
- **The jets' limits have consequences (2026-11-19):** on the 6-DoF an over-g or an overspeed is counted, past
  1.15 × the g limit (1.1 × the speed limit) the structure is damaged (more drag, "Structural damage", the master
  caution), past 1.5 × the g limit (1.15 × the speed limit, flutter) it fails; the gear lowered past its speed is
  damaged, main tyres past 225 kt of ground speed burst, hot brakes fade, the fuselage fuel moves the c.g., and a
  category III load departs more easily at CAT I and has a rolling g limit ([flight-model.md](flight-model.md) §9.20).
  Inferred: the margins, the brakes' energy, the tank arms and the aft c.g. limit; open: the stores supplement's
  limits. A full push holds about −3 g (the control system's push and negative g limiter, 2026-11-19,
  [flight-model.md](flight-model.md) §9.11; before it a full push or the autopilot's descent broke the airframe at
  −3.9 g); a slow push at full throttle still counts an over-g (to −3.41 g), and the Ra'am passes its −2 g there as the
  real F-15 can. The pitch loop's gain continues past the last q̄ of its schedule (2026-11-19, §9.11): low down at
  high speed the jets now fly steadily (before it the Barak's g swung −0.1 to 2.1 g with the stick centred at
  400 m/s, 500 m, and a full pull reached 11.5 g), a full pull peaks at 9.51 g and a full push at −3.07 g.
- **[C2](plan.md#c2-the-6-dof) stage (c), the 6-DoF flies the sim's jets (2026-11-03):** TP-1538's control system (g command, α limiter, roll
  and yaw), `Fm { Original, SixDof }` behind `IafFlight` chosen by `Model = 6dof` in the own data (the original game's
  data never reaches it, tested), fuel burn, Mach effects (inferred), the validation rows on the 6-DoF, a real Sufa
  flight in mission 311 ([flight-model.md](flight-model.md) §9.11–9.14). Since 2026-11-14 it takes reborn's ground
  effect, gusts, stores moment (a tank's with its fuel), the stores' drag difference, the roll trim, the systems damage and the landing limits (with Easy landing and the autopilot's landing) through the same
  functions and calls (`near_ground`, `set_stores_moment`, `trim_roll`, `landing_limits`; [flight-model.md](flight-model.md) §9.12). A release changes the 6-DoF's mass, drag and roll at once (`test_sim_release.gd`).
  Since 2026-11-14 (finish list F2) the Barak and the Sufa roll at the F-16's sourced 240 deg/s with 62 deg/s
  flaperons, the figure reborn's Real F-16 rows read ([flight-model.md](flight-model.md) §9.11, §9.13); open: their
  0 → 90° time, 0.78–0.88 s against ~0.55 s.
- **The 6-DoF's control laws (2026-11-15, finish list F3, F7, F15):** 9 g in about 2 s below the α limiter, the
  STORES CONFIG switch (CAT III α limit and roll), the MANUAL PITCH override with deep
  stall recovery by rocking, `stalled` / `spinning` from the motion ([flight-model.md](flight-model.md) §9.11, §9.13).
  Open: the autopilot's touchdown sinks 4.5–10 m/s, over the 4 m/s landing limit (§9.6).
- **[C2](plan.md#c2-the-6-dof) stage (b), engines, gear, the jets' data (2026-11-03):** TP-1538's engine model scaled to the F110-GE-100,
  F100-PW-229 and F135; a three-strut gear with brakes, steering and a braked stand; the four jets' mass, inertia and
  geometry; tests against the ratings, the spool times, a take-off roll and a stop ([flight-model.md](flight-model.md)
  §9.7–9.10). Since 2026-11-15 the take-off roll meets both F-16A SAC rolls within 10 % (2,201 / 3,623 ft against
  2,380 / 3,725 ft, the rotation at 170 kt, §9.13), and since 2026-11-25 the four sim jets' rolls at full fuel
  (1,415–1,914 ft) lie between the F-16A's and the F-15C's SAC rolls, as their thrust to weight does (§9.10); the tyres brake at NASA's antiskid figure with a friction circle,
  a 25 kt crosswind take-off and landing roll stay within 4 m of the centreline, the autopilot's taxi turns run on the
  wheels; a touchdown past 10 ft/s damages the gear, gear damage holds the gear, and the gear's 300 KCAS limit comes
  from the aircraft definition ([flight-model.md](flight-model.md) §9.8; docs/damage.md §5.2). Since 2026-11-16 full
  pedal yaws the jet hard at any speed and never tips it (air-spring strut stiffness), centred pedals let the nose
  wheel castor, and the keyboard's rudder keys ramp the pedals over 1 s. Since 2026-11-17 the nose wheel follows
  centred pedals back to straight below 30 kt (a released ground turn stops), the brakes ramp in over 0.5 s and the
  struts damp their extension four times harder: braking dips the nose 1° and it eases back with no rock
  ([flight-model.md](flight-model.md) §9.8). Since 2026-11-18 the sloping ground stays in place between two frames
  and weight on wheels is a compressed strut: the jet leaves the runway once at lift-off (before, the wheels left a
  sloping runway and fell back on it every frame).
- **[C2](plan.md#c2-the-6-dof) stage (a), the 6-DoF's core (2026-11-03):** `crates/iaf-flight/src/sixdof/`: NASA TP-1538's aerodynamic
  tables checked value by value against the scan, appendix B's coefficient build-up, a quaternion rigid body; the
  trim tests match the report's trims and Stevens & Lewis's ([flight-model.md](flight-model.md) §9). Nothing calls
  it yet.
- **[D2](plan.md#d2-units-and-weapons) drafts (2026-11-03), pending the user's decision:** the threat set's 12 units and 10 weapons as readable
  records in `modern-iaf/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **[A1](plan.md#a1-the-project-skeleton), the project (2026-11-02):** the `modern-iaf/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./start-modern-iaf` and `./modern-iaf-setup` (+ `.ps1`), `tools/test.sh` over `modern-iaf/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](../README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item [C1](plan.md#c1-fm-0-data)'s FM-0 data; `NEEDS DATA` without that file). With the terrain built
  ([B1](plan.md#b1-the-terrain), the terrain) it flies 5 s over it and checks the heights. On every flight it makes (the free flight, each jet's start-up) the
  3D-only cockpit check (2026-11-08): the cockpit dir the sim's own, no panel, lamp, HUD glass or ADI art loaded, the
  3D cockpit up ([cockpit.md](cockpit.md)).
- [A2](plan.md#a2-the-iaf-sim-compilers) (the data compilers), [B2a](plan.md#b2-the-airbases) (the airbases' layouts), [E1b](plan.md#e1-cockpit-data-sounds-and-voices) (sounds, voices, keys), [E3a](plan.md#e3-the-training-missions) (the training scoring): see
  their rows in [plan.md](plan.md).
- **[E1a](plan.md#e1-cockpit-data-sounds-and-voices), the HUD and display font (2026-11-08):** Hershey's Roman Simplex stroke font
  on the HUD, the MFDs, the small screens and the F-35I's panoramic display ([cockpit.md](cockpit.md) §5); each jet's
  cockpit by day and at night in [cockpit.md](cockpit.md) §6.
- **The voices (item A5, 2026-11-09, branch wt/iaf-2026-voices, waiting for the user's ear):** every speech clip is
  Kokoro text to speech in American voices, made by `iaf-sim voices` as Ogg: Betty measured against two real
  recordings (pace, pitch, repeat), the tower's calls in one breath, the radio chain with key clicks around each
  call ([sound.md](sound.md) §5).
- The setup wizard's headings use Heebo's weights since 2026-11-08 (the font axis is set by its tag number; a "wght"
  string key had left every weight at the regular).

## Open
- **AI for allies and enemies (2026-11-19, the user's plan session):** the plan is in [ai-plan.md](ai-plan.md): a new
  Rust AI (a behaviour tree per role, a flight and a package lead) over the existing autopilot loops and combat engine;
  milestones in his order: the four-ship of Sufas (F1–F11), the intercept lesson with a controller and the Eitam
  (C1–C7), one Epic Fury strike (K1–K13); the shared needs X1–X7; his open questions in its §9. Built (19 Nov,
  milestone 1 slice 1, no change on screen): the Rust core `crates/iaf-ai` and `IafAi`, the slot loop and the AI's
  6-DoF cases and the flight's collision avoidance ([../../docs/ai.md](../../docs/ai.md) §8.7), tested from Ramon's
  shelters to parked again and with a lead landing away from home. Built (19 Nov, slice 2): the four-ship lesson
  `ramon_four_ship` (Training, the Sufa): Kidon 1-2 to 1-4 in the next shelters with the player's load, started by the
  tower's start-up clearance, taxiing in order, a stream take-off, the join-up calling "in position", the slots in the
  player's turns, the commands through `IafAi.command`, RTB, the landing and each parked at its own shelter
  (`modern-iaf/tests/test_four_ship.gd`); 0.17 ms CPU and 0.127 ms GPU per AI jet on the Iris Xe laptop (ai-plan X5).
  Built (19 Nov, slice 4, ai-plan F12–F14, [../../docs/ai.md](../../docs/ai.md) §8.8): the two pairs (#4 on #3 when
  #3 flies on its own), the split (element 2 to its own target in the same area) and the regroup, the reactions to a
  lock or a launch (the call, the beam or the break into an infrared missile, chaff or flares by the existing decoy
  rule, the mate's break call, the rejoin) and the report of an AWACS contact; in the game a scripted ground radar's
  lock on Kidon 1-2 is called, defended with chaff and left for its slot again (`test_four_ship.gd`).
  Built (19 Nov, slice 3's logic, ai-plan F5, F8, F13, F14): every call of the flight said in the wingmen's own voice
  (Kokoro `am_eric`) with its subtitle in the game's language (the words in
  [research/radio-terms.md](research/radio-terms.md): IAF terms where a source has one, else NATO brevity);
  `IafAi.engage` ("engage my target": the jets fly at the radar's locked enemy aircraft and fire through combat.gd,
  then rejoin); a real S-300PMU-2 locking and launching at the wingmen in `test_four_ship.gd`.
  Callsigns (20 Nov, the user: "Use kidon style, where kidon 1 is the first formation the second is kidon 2 etc"):
  the flights are Kidon 1..4 and the jets Kidon 1-1..1-4 on every screen, subtitle and voice, in English and Hebrew
  ([research/radio-terms.md](research/radio-terms.md)); in Hebrew a runway's side is ימין / שמאל ("25 ימין"), the
  AWACS's clearance "רשאי לתקוף", and "מייל" is read as the mile ([sound.md](sound.md) §3.1).
  Built (20 Nov, A72): the radio menu's Tower / Wingmen / AWACS pages, the wingman commands through the menu.
- **Missiles (avionics-plan.md §7.2):** step 5 built (25 Nov): the MiG-29A's R-73 and R-27R and the SAM sites' own
  missiles (the S-300's 48N6E2, the Tor's 9M331, no longer the AIM-120's record) fly the physical missile, fitted to
  their published speed and range ([../../docs/real-weapons.md](../../docs/real-weapons.md) §2.1; `sim.rs`,
  `sites.rs`, `modern-iaf/tests/test_threat_missiles.gd`). After a pull the db setup step recompiles the R-73's and
  R-27R's records. Open: the AIM-54A (a draft record, with the F-14A).
- **The missile warning, not started (outside the user's words):** an active radar missile's own seeker as an "M" on
  the threat display (the F-15C's ALR-56C shows one, a simulator manual; the dash-34's F-16 list has none;
  [research/missile-warning.md](research/missile-warning.md) §2, §6).
- **The manuals** ([manuals.md](manuals.md)): the Typst build, the page design, each manual's outline and one written
  section per jet (Cold start to take-off) wait for the user's approval (18 November 2026); every other section is
  planned in the outlines. The Hangar's Manuals entry opens the PDFs.
- **Avionics, missiles and bombs (2026-11-17):** the inventory per jet, the gap list and the build order are in
  [avionics-plan.md](avionics-plan.md); the 15 November bugs (radar standby, break X and the HUD against reborn,
  SPICE / GPS targets, the gun flash) are its first slice; the range is slice 1. The briefing's PRE target pick for the
  GPS bombs is built (2026-11-19, A61).
- **The process staying alive after Quit on macOS**: reported once, on the user's Mac on 2026-11-15; it did not
  reproduce on Linux (headless or in a hidden real render) and is not being pursued unless it is seen again. The leak
  reported with it is fixed (docs/rendering.md §1.5; `modern-iaf/tests/test_exit.gd`).
- **The canopy, after round 3** (2026-11-14): from the F-35I's seat the frame's sides look wide with the lid open;
  the frames' colours and sizes are estimated from photos. Since 2026-11-25 the F-16s' lid opens 34°, matched to a
  side photo from the same camera (`airframe.json` `canopy_deg`), and the briefing shows the F-35I's canopy lever in
  a picture like every other step.
- **A first start's shader compilation** (2026-11-10; 2026-11-25): the front end now warms the flight's materials while
  the menus show (`shared/util/shader_warmup.gd`), and the release bundles bake Godot's own shaders, the `.gdshader`
  files and the warm-up's materials ([../../docs/rendering.md](../../docs/rendering.md) §1.6 "The first start"). On the
  Mac, cold, mission 2012 after 20 s on the mission page: Fly to the first world frame 19.1 s before, 7.0 s after; one
  menu frame of 2.3 s while the warm-up's built-in materials are made. The macOS bundles need macOS 13 (the baker's
  Metal profile; with Godot's default 11 a baked material's shader failed on the Mac,
  [../../docs/release.md](../../docs/release.md) "Baked shaders"). Open: the Linux laptop's numbers (its desktop was
  locked during the work), the 2.3 s menu frame, and a timed start of the baked macOS bundle (the Mac's hidden window
  drew nothing on 25 Nov).
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the Baz is not flyable:** it has no 3D cockpit and no model of its own,
  so the front end does not offer it and no mission flies it; type 110 flies the F-15I's flight-model row. Tel Nof's
  apron is placed by eye ([airbases.md](airbases.md) §5).
- **The core sounds' open points** ([sound.md](sound.md) §1.3–§1.8): the cockpit's idle-to-military step, the
  wind's real spectrum, the gun's spin-up, a real canopy's run time, the gear and flaps clips against a real F-16, the
  F-35I's own IPP, the tower's key clicks (on `wt/iaf-2026-voices`).
- **The cockpit sound model's open points** ([sound.md](sound.md) §1.9): the canopy's measured transmission loss, the
  helmet in flight, the air-conditioning hiss, the engine and wind levels by ear.
- **The afterburner's open points** ([sound.md](sound.md) §1.2): the light-off delay after the detent, the level in
  the cockpit, FlightGear's F-16 sounds not compared, the F-35I's own burner.
- **Keys and Joystick's open points** ([front-end.md](front-end.md) §9): maps for more sticks than the Hotas X; the
  Hotas X's button choice is ours, untried on the stick.
- **[B3](plan.md#b3-scenery-roads-and-inland-water)'s open points** ([scenery.md](scenery.md) §9).
- **The 6-DoF's wave drag is a fit ([C2](plan.md#c2-the-6-dof), the 6-DoF):** fit to each jet's published top speeds, not a sourced table; open: a public
  F-16 drag rise, the flaps' sourced aerodynamics and the approach speed
  ([flight-model.md](flight-model.md) §9.6, §9.16).
- **[E3b](plan.md#e3-the-training-missions)'s open points** ([training.md](training.md) §6): the Hebrew voice (the user), the
  pilot's request voice (sound.md §7).
- **[E2](plan.md#e2-the-front-end)'s open points** ([front-end.md](front-end.md)): a pilot list (the name is the computer's user
  name); the debrief sheet and the pilot log in the original game ([shared.md](shared.md)).
- **The airbases' open points** ([airbases.md](airbases.md) §9): the towers of Ramon, Hatzerim and Ramat David (their
  reference points stand in), one taxi hub per base. The temp-root run of item F finds any read of the
  original's data still left.
