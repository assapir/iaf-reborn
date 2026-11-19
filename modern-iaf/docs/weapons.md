# Modern IAF's weapons

**Terms:** bdb = the object database the sim compiles (`sim.bdb`, [data-formats.md](data-formats.md) §2); tick = one
gun shot of the shared code, every 0.2 s ([../../docs/weapons.md](../../docs/weapons.md) §3); master arm = the switch
that lets a weapon fire.

The sim flies the shared weapons code of the original game ([../../docs/weapons.md](../../docs/weapons.md)) with its
own data: the gun, chaff and flares, and the stores the briefing's Arming page hangs (bombs, guided bombs, missiles,
tanks), which drop and fire in every flight (§4).

## 1. The gun's rounds
Each flyable jet's rounds are its unit record's `loadout` entry for the gun (`data/db/units/<id>.json`). `iaf-sim db`
compiles the count into the bdb as station 9's count, and the gun counts it down to empty. Weapon data Real's per-type
table (`real_weapons.gd` `GUN_ROUNDS`) is the original game's; the sim keeps the bdb's count
(`Settings.real_bdb()`).

| jet | gun | rounds | source |
|---|---|---|---|
| Sufa (`f16i`) | M61A1 20 mm | 511 | the F-16's[^gdots]; the two-seat Sufa's count is not published (inferred the same) |
| Barak (`f16d`) | M61A1 20 mm | 511 | as the Sufa |
| F-35I (`f35i`) | GAU-22/A 25 mm (the 20 mm record's damage stands in) | 180 | the F-35A's[^w-f35] |

The M61A1 fires 6,000 rounds a minute[^w-m61]: 20 rounds a tick, so 511 rounds last 5.1 s. The F-35I fires its
GAU-22/A's 3,300 rounds a minute at 1,040 m/s (its definition's `gun`, the shared `real_weapons.gd` `jet_gun` the
MiGs' guns use; [../../docs/f35i.md](../../docs/f35i.md) §3): 11 rounds a tick, so 180 rounds last 3.3 s.

`iaf-sim db` refuses a unit that has an `airframe` (a flyable jet) and no gun count, so no jet flies with an empty or
endless gun.

The rounds fly the shared Weapon data Real ballistics (the sim fixes `weapon_data` "real"): the jet's velocity plus
the muzzle velocity, the M56's drag (sea-level 3,450 → 1,677 ft/s over 1,000 m, fitted to the GD-OTS chart) scaled
by the air density, and gravity. The HUD's EEGS funnel reads the same time of flight, so a round passes through the
funnel's centre at its range. The GAU-22/A's 25 mm round flies the M56's drag (inferred: no public drag figure for
the PGU-47 / PGU-48). Figures, sources and tests: [../../docs/real-weapons.md](../../docs/real-weapons.md) §1.4.

## 2. The gun's and the effects' art
`iaf-sim own` draws the gun's art and the effects' sprites from formulas (no source image; ours: the gun's in
`crates/iaf-tools/src/sim.rs`, the effects' in `sim_effects.rs`) into the original's resource layout,
`converted/own/resource/3dobjects/`:

| file | drawn as | look |
|---|---|---|
| `gunfire.tga` | the muzzle flash: the original's two crossed quads, 0.6 m wide, 0.85–1.15 m long, while the gun fires | a flame white-hot at the muzzle, tapering forward to an orange tip |
| `tracer.tga` | a tracer per round slot (one a tick): two crossed quads 0.4 m wide and 18 m long behind the round, and an orange head the same size on screen at any distance (about 5 px at 1080 lines; 15 px until 2026-11-17), so a round seen end on from the cockpit still shows; the tracer shows for the first 1 s of the round's flight (inferred; until 2026-11-17 its whole flight, the user: "flare of bullets stay for too long and are too big") | a hot head fading to a red-orange tail; near the muzzle the streak is no longer than the way flown |
| `afterburn.png` | the afterburner: two nested cones from the nozzle, added (`afterburner.gd`) | a blue-white core at the nozzle, then yellow-white and orange fading to the tip, three shock diamonds as brighter bands |
| `missflr.png` | a flare (`decoy_fx.gd`) and a missile's motor glow without Detailed effects (`trails.gd`) | a white-hot point about 1 m across in a tight yellow glow, a faint warm halo, clear well inside the rim: released flares show as separate bright points |
| `chaff.png` | the chaff pieces (`decoy_fx.gd`) | grey foil with bright glints |
| `trail.png` | the smoke trails without Detailed effects, the wingtip trails (`trails.gd`) | white smoke, dense when young, wider and thinner with age |
| `w_splash.png`, `w_circle.png` | a hit's splash and ring on the water (`damage_effects.gd`) | a spray column wide at the water; a foam ring |

`player_weapons.gd` reads the gun's two from `Settings.own_dir()`, the same path that gives the original game its install's
`gunfire.tga`. The effects read theirs through `Settings.effect_art(rel)`: the converted original sprite in the
original game, the file of the same name here.

The chaff and flare records give their decoys a flight of their own (`motion`, inferred), through the shared decoy
flight ([../../docs/weapons.md](../../docs/weapons.md) §10): the decoy leaves at the jet's speed toward an aim point
2 km ahead and a little below (`_fireEndVec` 0, 2000, -60 for a flare, -30 for chaff) and slows at `_absAcceleration`
(flare -40, chaff -150 m/s²) to 5 m/s, so it falls back behind the jet as drag would slow it. At 250 m/s a flare is
about 20 m off the jet after 1 s and 80 m behind after 2 s, and burns to the 4 s cap; chaff stops in the air about 75 m
behind after 1 s. A chase view behind the jet sees the flares leave under its tail.
Until 2026-11-14 the decoys took the reader's gun-round defaults (1,200 m/s) and were never seen. From 2026-11-14 to
2026-11-16 they flew 200 m aft at |V| + 10 m/s (the original's `_fireEndVec`) and ended there in about 0.85 s: seen
from ahead, but from behind the jet (an F-35I picture shoot, 2026-11-16) they had passed the camera before any picture.
`test_sim_gun.gd` checks both flights.
Each burning flare trails a thin smoke ribbon (`trails.gd` `FLARE`: 0.2 m wide at the flare, 1.2 s, drawn with
`trail.png`; `decoy_fx.gd` when not `original_art()`) in place of the original's white puffs (3.2 → 9.6 m every
1/30 s), which around the sim's sprites read as one cloud of smoke.

**Open:** a bomb's hit on the ground draws the shared grey smoke domes, the same as the original game; the sim has no
fire, dust or debris look of its own yet.

A gun record without a model (the sim's `20mm.json`) draws its rounds as tracers; the original's gun
record has a model and draws it as before.

A 1.2 s burst at Ramon, from the cockpit (top) and the chase view (bottom), the graphics options at their best
(`modern-iaf/tests/_gun_shot.gd`):

![A burst from the Sufa's cockpit and the chase view](pictures/weapons/gun_burst.webp)

## 3. Master arm
Every sim flight starts with the master arm safe (`Settings.starts_safe()`): the gun trigger (Tab) and the weapon
release (Space) fire nothing. **Master arm** (Shift+A, record 125 of `data/keys.json`, command 202) switches between
safe and armed, and the band shows "Master arm" or "Master safe". The original game has no master arm and no key sends
command 202, so its weapons stay armed.

The original's gear-down rule still holds when armed: with the gear handle down the gun fires only with Safety off
([../../docs/weapons.md](../../docs/weapons.md) §3).

## 4. The original's fixes the sim keeps on
The sim turns on the shared fixes of the original game's weapon and damage bugs (`sim_settings.gd` `_apply_profile`;
each one's original and fixed behaviour in [../../docs/deviations.md](../../docs/deviations.md) §2):

| switch | what the sim gets |
|---|---|
| `wind` | the mission's wind drifts the falling stores (CCIP follows), moves the AI jets and turns the runways into it |
| `fix_bomb_burst` | a bomb bursts at the ground, not up to about 70 m under it |
| `fix_ghost_collision` | no collisions with hidden units or wrecks |
| `fix_lock_threat` | a radar lock makes the player the locked enemy's threat |
| `fix_fall_heading` | a falling jet keeps its heading |
| `fix_skill_damage` | enemies take the same damage at every AI level |

## 5. Dropping and firing in flight
The unguided bombs fall by gravity and their own drag (C_D 0.45 on each body's sourced diameter) through the
mission's wind, nothing steering them, and the CCIP pipper runs the same fall, so the bomb lands on the pipper
([../../docs/real-weapons.md](../../docs/real-weapons.md) §1.10).

Every sim flight carries the pilot's loadout from the briefing's Arming page (`fly.gd` `arm`, [front-end.md](front-end.md)
§10); a training mission goes on after its pass, so after the take-off the player can use them. The shared weapons code
runs them unchanged: the release, the bomb's fall, its burst on the terrain with the shared explosion, the missiles and
the gun.

| step | the Sufa / the Barak | the F-35I | key (default) | key record |
|---|---|---|---|---|
| the stores | the range lesson's own load has them; elsewhere hung on the Arming page before Fly (the record's default carries no bombs) | the same | — | — |
| power | ST STA on (with the avionics: Ctrl+A, or the start-up's four AVIONIC POWER switches) | — | Ctrl+A | 122 |
| master arm | MASTER ARM to ARM: every flight starts SAFE (§3) | the same | Shift+A | 125 |
| gear | up: nothing releases with the gear handle down | the same | G | 20 |
| bombs | A-G: the HUD's CCIP pipper (HUD mode 5) | A-G: the CCIP cue (a GPS bomb, HUD mode 6) | `[` | 65 |
| release | the pickle held: the bombs leave as a pair once the pipper reaches the aim point | held: the bay doors open, the bombs leave, the doors close | Space | 69 |
| jettison | the emergency jettison: every store and rack but the A-A missiles and the pods in one press; the SMS's S-J, then the pickle: the selected store's stations | every store but the A-A missiles and the pods, the bays' once the doors are open | Shift+C | 72 |
| missiles | A-A: the AIM-9M's seeker circle | A-A: the AIM-120 (it waits for the bay doors) | `]` | 66 |
| next target | the radar locks the next target (the Sufa: each press bugs the next target; TMS up or a click on the bug locks it) | the same | Enter | 58 |
| the Sufa's radar | the real FCR's TMS, submodes, scan width and bars, antenna elevation, OVRD and EXP ([../../docs/radar.md](../../docs/radar.md) §9.4) | — | `/`, Shift+`/`, `;`, Shift+`;`, `'`, Shift+`'`, Ctrl+`'`, Alt+Up / Down, Ctrl+`/`, Ctrl+`;`; the cursor on Ctrl+arrows | 132–142, 48–51 |
| the Sufa's ground map | GM's OSBs 7–10: FZ, SP, CZ, STP / TGT; in A-G the TMS keys designate or track and Ctrl+`;` steps EXP / DBS1 / DBS2 ([../../docs/radar.md](../../docs/radar.md) §9.7) | — | Alt+`;`, Alt+`'`, Alt+`/`, Alt+`.` | 143–146 |
| the F-16 MFDs | DMS (the SOI, each MFD's next format); LASER ARM ([../../docs/mfd.md](../../docs/mfd.md) §9 "Modern MFDs") | — | Ctrl+Page Up / Down (the laptop map: Ctrl+U / Ctrl+D), Ctrl+`[` / `]`; Shift+L | 147–151 |
| gun | the trigger held | the same | Tab | 64 |

**Every store drawn on its rack (2026-11-15).** A station that holds several stores shows each of them, on the Loadout
screen's jet, the Hangar's and in flight alike (`shared/weapons/stores.gd` `place` / `rack_layout`,
`player_weapons.gd` `hang`): the Sufa's and the Barak's three Mk 82 hang on a TER-9/A, two on its shoulders turned
45° toward it and one under it; two GBU-38 hang side by side under a BRU-57/A; the Adir's four GBU-39 sit on their
BRU-61/A as before. The racks are our own models (`shared/extra/models/stores/ter9.glb`, `bru57.glb`, made by
`tools/stores/build.gd`; their sizes are inferred: no published dimensions were found). The original's slots
([../../docs/weapons.md](../../docs/weapons.md) §2.2) come from the original store model's `pilon` helper, which the sim has no install for: they put
every store of a station on one point, so a full TER showed as one bomb (the user, 15 Nov: "if it includes 4 bombs
the visual show only 1"). A release takes the store of the last slot first (the TER's lower one); the others stay
drawn, and the rack stays when the last one goes. Reborn keeps the original's layout.

| the Sufa with two GBU-38 on 3 / 7 and three Mk 82 on 4 / 6 | one Mk 82 released from 4 |
|---|---|
| ![The Sufa's left wing: two GBU-38 under a BRU-57/A, three Mk 82 on a TER-9/A](pictures/weapons/racks_full.webp) | ![The same after a release: two Mk 82 on the TER](pictures/weapons/racks_released.webp) |

**The stores page.** The F-16s' SMS (the right MFD's format; [../../docs/mfd.md](../../docs/mfd.md) §9) and the
F-35I's SMS portal ([../../docs/f35i.md](../../docs/f35i.md)) are the original game's real formats on the shared
stores state: every station's store and count as hung on the Arming page, the selected weapon and its page (A-G with
CCIP, AAM, GUN) following `[`, `]` and the page's own OSBs, the counts going down with each release and the stations
emptying on a jettison. The sim adds its two switches: the F-16 SMS shows RDY only with the master arm on ARM and ST
STA powered, the F-35I's shows ARM or SAFE over the weapon (inferred).

A training mission's live check (training.md §3.0) runs only until its pass, so a release after the take-off fails
nothing; before the pass the release is blocked on the ground anyway (the gear handle down).

The checklist notebook's WEAPONS tab (key H; [training.md](training.md) §11) lists these steps per jet family, each
with its switch, its place and its key as bound (the weapons' controls have no switch to click in the cockpit).

**The Delilah (2026-11-14).** Dropped for now (the user): no station lists it and no default carries it. It needs a
powered cruise-missile flight class the engine does not have, and flew as a glide bomb. Its weapon record
(`data/db/weapons/delilah.json`) and the shared record (`modern_weapons.gd` 1012) stay; the original game never
offered it.

**Limits and doors.** A bomb leaves only at 600 KCAS or less and in a dive of 60° or less; the jettisoned stores fall
unarmed; the F-35I's bay doors open in 0.47 s, shut 0.5 s after the release and add 50 to the drag index while open
(sources and the inferred figures in [../../docs/real-weapons.md](../../docs/real-weapons.md) §1.11).

## 6. Tests
- `cargo test -p iaf-tools --lib sim::`: the bdb holds 511 / 511 / 180 rounds; a flyable jet without a gun count is
  refused; `iaf-sim own` writes both images (the flash opaque at the muzzle, clear at the corners).
- `modern-iaf/tests/test_weapons_flight.gd`: each jet's take-off mission set up as the front end's Fly with bombs from
  the Arming page (six Mk 82 on the F-16s, two GBU-31 in the F-35I's bays), put in the air after its pass: the master
  arm starts safe, Shift+A arms, ST STA is up, `[` selects the bombs (CCIP), Space releases, the bomb is drawn, falls
  over a kilometre and is gone at the terrain (its burst); Shift+C empties the rest; `]` and Space launch a missile
  (the F-35I's from its bay) that flies away from the jet; Tab fires the
  gun. The stores page agrees at each step: the bombs on their stations before arming, the selected weapon the HUD's,
  no RDY while safe and RDY once armed, the counts after the release, the stations empty after the jettison.
- `modern-iaf/tests/test_mvp.gd --only loadout`: three Mk 82 on a TER drawn apart, the rack on the jet; after one
  release the other two still hang.
- `modern-iaf/tests/test_sim_release.gd`: one of the Sufa's two MK-84 released (SGL) in level flight: the flight
  model's mass drops by the bomb's 925 kg, the drag index it is given drops by the bomb's on one wing, and the moment of the other bomb
  rolls the jet hands off ([flight-model.md](flight-model.md) §9.12).
- `modern-iaf/tests/test_sim_jettison.gd`: the Sufa refuses a Mk 82 release over 600 KCAS and in a 65° dive; S-J and
  Space drop six Mk 82 with their two TER-9/A (the 6-DoF's mass and drag index fall by theirs, the tanks and missiles
  stay, the bombs fall unarmed); Shift+C then drops both tanks in one press (mass −2 × 201 kg plus the fuel above the
  internal, fuel at the internal, drag index −2 × 19.1), the four AIM-9M stay. The F-35I's Shift+C opens the bay
  doors; the GBU-31s leave 0.47 s later with the doors' drag index on, and the doors are shut within 2 s.
- `modern-iaf/tests/_weapons_shot.gd` (real render): the same flown from the front end, the start-up, the tower and the
  take-off included; the pictures of the bombs leaving, the burst, the missile, the gun and the notebook tab.
- `modern-iaf/tests/test_sim_gun.gd`: the Sufa's take-off mission starts with 511 rounds and the master arm safe; the
  trigger fires nothing while safe; Shift+A arms; the tracers fly; the gun empties in 5.1 s and then fires nothing;
  the F-35I's gun record fires 11 rounds a tick at 1,040 m/s; the bomb fixes are on and a 20 kt wind reaches the
  falling stores.


## 7. The targeting pod and the laser bombs
The user's yes of 17 November 2026 ([avionics-plan.md](avionics-plan.md) §8, item 2): the Litening pod and the GBU-10, GBU-12 and GBU-16 on the
Sufa and the Barak (the F-16I carries all three and the Litening II[^sufa-at]). Their records:

| store | record | weight | stations | model |
|---|---|---|---|---|
| Litening targeting pod (SMS name `TGP`) | `data/db/weapons/litening.json`, kind `pod` (660) | 208 kg[^w-litening] | 5 (5R), the right chin | our Litening (`litening.glb`, FlightGear's AN/AAQ-28 at the real 2.20 m by 0.406 m[^w-litening]) |
| GBU-12 Paveway II | `gbu-12.json`, kind `laser_bomb` (650) | 230 kg[^w-gbu12] | 3, 4, 6, 7 | the Mk 82 with the Paveway kit (`mk82lb.glb`) |
| GBU-16 Paveway II | `gbu-16.json` | 450 kg[^w-gbu16] | 3, 4, 6, 7 | `mk83lb.glb` |
| GBU-10 Paveway II | `gbu-10.json` | 910 kg[^w-gbu10] | 3, 4, 6, 7 | `mk84lb.glb` |

- **The chin.** The real F-16 hangs its targeting pod on a chin hardpoint under the intake[^twz-litening] (the right
  one on the Sufa, inferred from photos). The sim's nine pylons are the stations 1–9; station 5, the centreline, takes
  no sim store, so the sim numbers the right chin station 5 (shown as 5R; the left one, 5L, §7.3) and hangs it under
  the right intake (`sim.rs`
  `F16_SIM_STATIONS` StationE, `F16_SIM_LUGS`): from the model's right chin pylon (`PylonChinR`, FlightGear's
  fuselage pylon, shown while the station is loaded), where FlightGear hangs its Litening, 0.69 m right of the
  centreline (2026-11-17; before, 0.3 m, against the intake's bottom with no pylon). The briefing's balance takes it
  on the jet's middle (its 0.69 m offset, about a third of a wingtip AIM-9M's moment, inferred as negligible).
- **The pod.** `player_weapons.gd` takes a store named TGP (or the 1998 game's FLIR) as the targeting pod: the TGP
  format ([../../docs/mfd.md](../../docs/mfd.md) §9 "Modern MFDs"), its picture, the track modes, the laser.
- **The laser bombs** fly the shared laser path ([../../docs/weapons.md](../../docs/weapons.md) §9.8): released as
  bombs on the CCIP rules, guided onto the laser spot while the laser fires (within 60° of the line to the bomb's
  point), else to the bomb's CCIP point. Their motion is the shared guided motion's defaults (`guided.rs`
  `GuidedMotion::default`; no new performance modelling, avionics-plan.md §7).
- **The flow** on the range: A-G with a GBU selected, the radar's ground map designates a hulk, the TGP the SOI
  (DMS), TMS down slaves the pod there (or TMS up / right tracks what is under its cross), LASER ARM (Shift+L), L
  fires the laser, MASTER ARM, the pickle. Test: `modern-iaf/tests/test_sim_mfd.gd` (a GBU-12 hits Target 1).

### 7.1 A store that needs another: the laser bombs and the pod
The user, 17 November 2026: "if there are some ammunitions that can't be used without it, it should not be allowed
to use without them" ([research/pods.md](research/pods.md) §8, items P12–P14, option A).

- **The data rule.** A weapon record names what it needs, `"needs": ["laser"]` (the GBU-10, GBU-12, GBU-16), and a
  store names what it gives, `"gives": ["laser"]` (the Litening). A jet's built-in pod (its aircraft definition's
  `flir`: the F-35I's EOTS, the Ra'am's) gives the laser too. `iaf-sim db` copies both lists into the compiled
  weapon records; one Rust rule, `iaf_avionics::stores::unmet`, compares them for the loadout, the briefing and the
  flight. A later dependency is a new name in the records, with no new code.
- **The Loadout screen.** A load with an unmet need keeps Fly off (`briefing::arming`'s `blocked`; its `unmet` lists
  each such store, the store in the jet's inventory that gives the need and the first station that takes it). The
  footer shows one short warning-coloured line at the screen's notice size (16 px, as the balance warning): "GBU-12
  needs the Litening pod" (Hebrew: "ל־GBU-12 נדרש פוד לייטנינג"). Until 17 November 2026 it was a wrapped sentence
  ("… needs a targeting pod: load the Litening on station 5, or remove the …"); the user found it "too long and
  big", so it names only what is missing. The front end's Hebrew says פוד for a pod (the user, 17 November 2026).
- **Presets.** Such a load is never saved as a preset: "+ Save this loadout" is off and the save stores nothing (the
  user, 17 November 2026: "don't allow to save presetting with laser that doesn't have it"). A preset saved before the
  rule loads with all its stores, shows the line, and keeps Fly and Save off until the pod is on.
- **The mission's needs.** A lesson that counts ground kills (its `training.ground_kills`, the range lessons' two)
  needs that many air-to-ground stores aboard (the inventory's group "ground": bombs, laser bombs, air-to-ground
  missiles). With fewer, `briefing::mission_arming` (the rule `IafBriefing.arming` asks with the mission's file) adds
  the unmet need `ground` and blocks the load; the line reads "The mission needs bombs: add a Mk 82 bomb" (Hebrew:
  "המשימה דורשת פצצות: יש להוסיף פצצת Mk 82"). A stored load or preset fit for one mission can be unfit for
  another, so the check runs per mission on the Loadout screen, the briefing and Fly. Until 19 November 2026 the rule
  saw only the stores, and a saved load with no bombs flew the range lesson (the user, 18 November 2026).
- **Fly.** `front_end.gd` `fly_mission`, which every Fly button calls, refuses a `blocked` load, so no screen flies one.
  A `--mission` run (`modern-iaf/flight/fly.gd` `arm`, a development path past the front end) asks the same rule and
  flies the mission's own load in place of a blocked stored one.
- **The briefing.** The Arming summary shows the same line under the stores in the small text, and its Fly is off.
- **In flight.** A selected store whose need is unmet shows `NO LASER` on the SMS in RDY's place (ours: the public
  dash-34 legend for this case was not found) and the pickle releases nothing (`player_weapons.gd` `unmet_need`).
  Before this rule a laser bomb with no pod was released and steered to its CCIP point. A jettisoned laser bomb falls
  unguided, as before.
- **Buddy lasing** (a wingman's or a ground team's laser) does not exist in the sim, so the jet's own pod is the only
  designator.
- **The 1998 game** names no needs, so reborn is unchanged. Every unit's own load and every mission's own load (the range lessons') meets its needs:
  `crates/iaf-tools/src/loadout.rs` `every_default_load_can_be_employed`, `every_lesson_load_can_pass_its_lesson`.

### 7.2 The pod's cockpit steps
The Litening's cockpit procedure on the Sufa and the Barak ([research/pods.md](research/pods.md) §3.1, item P5). The
public F-16 flow comes from simulator manuals, inferred for the IAF's jets. In the two-seaters the player does the
navigator's pod work. Logic: `crates/iaf-avionics/src/eo.rs` (the section "Modern IAF: the targeting pod's cockpit
procedure", bridged by `IafEo`). Wiring: `player_weapons.gd` `_update_pod`. Drawing: `f16_mfd.gd` `tgp`.

| step | what the player does / sees | control |
|---|---|---|
| Power-up | the pod powers with the avionics (MMC) and the SNSR PWR panel's RIGHT HDPT switch (since 2026-11-17; the checklist card's AFTER ENGINE START, [training.md](training.md) §12). It cools for 180 s (inferred), and the TGP page shows NOT TIMED OUT. A jet whose avionics are up from the start, or come up in the air, has a cooled pod | the avionics' and RIGHT HDPT's power |
| STBY / A-G | OSB 1 toggles STBY (the picture, no track, no laser) and A-G | TGP OSB 1 |
| Fields of view and zoom | WIDE / NARO on OSB 2; the zoom steps 1, 2, 4, 8 (the digital expand) on OSB 20 / 19 | TGP OSB 2, 20, 19 |
| Tracks | TMS up POINT (a unit under the cross) or AREA, TMS right AREA, TMS down slaved to the SPI; the legend AREA / POINT / INR (slewed). A POINT track whose unit is gone becomes an AREA track on its last point | the TMS keys |
| Cursor zero | CZ (OSB 7) zeroes the slews: the pod back on the SPI | TGP OSB 7 |
| The HUD's TD box | once the pod tracks or was slewed off the SPI, the HUD's target designator box sits on the pod's aim point with its slant range | — |
| Laser code | the DED's LASR page (LIST, 0 MISC, 5 LASR) sets the TGP CODE (default 1688). The page shows it bottom left, above ARM's place. The laser bombs carry code 1688, set on the ground (inferred). A bomb takes the spot only when the codes match | the ICP |
| Laser | LASER ARM (Shift + L, the 3D cockpit's switch), then L fires the laser until pressed again. It fires only with the pod in A-G and the line of sight clear. The legend LASR is highlighted while the laser fires | Shift + L, L |
| Automatic laser | a released laser bomb's time to impact counts down bottom right (in place of the range); with LASER ARM on the laser fires by itself within LASER ST TIME (the DED's 16 s) of the impact; the L flashes while it fires. A bomb released with LASER ARM on and the line of sight clear takes the spot | — |
| Masking | a line of sight more than 2° above the belly's plane passes through the jet (inferred: the chin pod sees the lower half). The page shows MASK and the laser holds | — |

The laser is modelled only as cockpit procedure. A bomb takes its aim at its release (the shared laser path), and its
guidance is not modelled further. Not built here: the FLIR polarity (WHOT / BHOT) and the CCD TV picture, which
change the picture's look and wait for the user's approval of a picture. Test: `modern-iaf/tests/test_sim_pod.gd`.

### 7.3 The chin stations and the navigation pods
The user, 17 November 2026: the pods "are on the side of the air intake"; the Sufa carries a Litening and a LANTIRN
navigation pod beneath its intake[^iaf-f16i], the F-16's navigation pod hangs on the left chin hardpoint,
5L[^f16net-lantirn] ([research/pods.md](research/pods.md) §1, §2.3, items P4 and P9).

| store | record | weight | drag index | station | model |
|---|---|---|---|---|---|
| LANTIRN navigation pod, AN/AAQ-13 (SMS name `NVP`, inferred) | `lantirn-nav.json`, kind `pod` | 204.6 kg[^w-lantirn] | 3.9 (0.305 m across[^w-lantirn]; the tanks' rule, inferred) | the Sufa's 10 (5L) | `lantirn.glb`: FlightGear's AN-AAQ-13 at the real 1.99 m[^w-lantirn] |
| Pathfinder, AN/AAQ-20 (SMS name `PATH`, inferred) | `pathfinder.json`, kind `pod` | 84 kg[^fi-pathfinder] | 3.9 (the AN/AAQ-13's, inferred) | the Barak's 10 (5L) | the same `lantirn.glb` (inferred: no public drawing of its own shape; 198 cm[^fi-pathfinder], 1 cm shorter) |

- **The station.** The engine's nine pylons A..I were all in use, so the left chin hardpoint is a 13th station:
  index 12, pylon letter J, frame `StationJ`, after the gun (9), chaff (10) and flares (11), so the 1998 game's indexes
  and its 12-pair armaments stay (`iaf_avionics::stores` `STATIONS`, `CHIN_LEFT`, `LETTERS`, `is_pylon`; GDScript
  `stores.gd` `PYLONS`, `LETTERS`). The unit records number it 10 (after the wing's nine, so 5 keeps its meaning) and
  show it as 5L, station 5 as 5R (the records' `labels`). It takes only the jet's own navigation pod; it has no mirror
  station. Where FlightGear hangs its AN-AAQ-13: the axis 0.66 m left, 1.02 m down, 1.40 m ahead of our origin, under
  the model's `PylonChinL`, shown while the station is loaded (`sim.rs` `F16_SIM_STATIONS`, `F16_SIM_LUGS`,
  `F16_SIM_PYLONS`).
- **Weight and drag.** The pod's weight loads the jet at its 0.66 m arm (the asymmetric-stores moment); its drag
  goes half to each side, as station 5's. The briefing's balance takes it on the jet's middle, as the Litening.
- **What changes for every table keyed by station.** The loadout (`stores::loadout`, `loadout::sim_load`, 13 entries),
  the weight and drag, jettison, the release lists, the Real jettison, the Loadout screen's lines (`briefing::arming`
  `pylons`), the turntable and the flight's store models, the AI's loads (`combat.gd`, from the same load) and the
  mission report read the 13 stations. The SMS inventory page lists 5L by OSB 3, a line under 5R, when it holds a
  store (`f16_mfd.gd` `STATION_OSB`). The 1998 game's own arming tables (`mission_weapons.gd`, the CDMEWeaponLoadItem
  flags) keep their file format's nine.
- **Jettison.** The emergency and selective jettisons keep every pod: the 1998 game's by name (FLIR, ECM) and Modern
  IAF's by its record (`kind: pod`, compiled as `"pod": true`). Until now the Litening, named TGP, was jettisoned.
- **The functions:** the FLIR picture on the HUD and the Sufa's terrain following, §7.4 (pods part 2).
- **Tests:** `crates/iaf-avionics/src/stores.rs` `left_chin_station_loads_weighs_and_drags_both_sides`,
  `crates/iaf-tools/src/loadout.rs` `chin_stations_take_their_own_pods`, `modern-iaf/tests/test_sim_chin_pods.gd`
  (load, draw, weight, jettison, the SMS inventory), `modern-iaf/tests/test_front_end.gd` (5R / 5L, the pod drawn).

### 7.4 The navigation pod's FLIR and terrain following

Pods part 2 (19 November 2026; [research/pods.md](research/pods.md) P7, P8). The procedure follows a Falcon BMS
community page that follows the dash-34, a secondary source[^bms-tfr]; every number it does not give is ours, inferred.
The logic is `crates/iaf-avionics/src/nav_pod.rs` through `IafNavPod`; `shared/weapons/nav_pod.gd` wires it (Modern
IAF's F-16s, a navigation pod on 5L).

**The FLIR (both F-16s: the LANTIRN AN/AAQ-13 on the Sufa, the Pathfinder on the Barak).**

| step | what happens | control |
|---|---|---|
| Power | LEFT HDPT and the MMC on: the FLIR format shows NOT TIMED OUT for 7 minutes (the shortest of the source's 7 to 15), then STBY. A jet powered in the air, or from its start, is warm. | the SNSR PWR panel |
| Format | FLIR by OSB 16 on the format menu, offered with a navigation pod (dash-34 menu as the DCS guide shows it[^dcs-f16]) | the MFD's OSBs |
| OPER | OSB 1 STBY / OPER: OPER draws the picture on the HUD | OSB 1 |
| Picture | under the HUD's symbols, in the HUD's green, inside the combiner glass (`shared/cockpit/hud_flir.gdshader`); the heat is inferred from the view: its brightness, the sky's and the water's blue cold, the local contrast lifted. Its cost on this laptop's Iris Xe (1,600 x 900, measured 2026-11-19 by `modern-iaf/tests/_nav_pod_shot.gd`): 0.3 to 0.7 ms of GPU time a frame, no extra memory beyond the screen copy Godot keeps | — |
| Polarity, gain, level | OSB 6 WHOT / BHOT; OSBs 20 / 19 GAIN+ / GAIN-, 18 / 17 LVL+ / LVL- (ours: the format's layout is not traced) | OSBs |
| Snap-look | with the HUD the SOI (DMS up), a held cursor key shifts the picture 20° aside or 10° up / down (ours); look-into-turn leans it 0.15 of the bank, at most 10° (ours); while shifted the flight path marker is dashed | the cursor keys (records 48–51) |

The ICP's FLIR rocker moves only: the format's OSBs set the gain.

**The TFR (the Sufa's LANTIRN; the Pathfinder has none).**

| item | the sim | control |
|---|---|---|
| Format | TFR by OSB 17 on the format menu; OSB 1 the mode NORM / WX / LPI / VLC, OSB 2 the SCP (1,000 / 500 / 300 / 200 ft; VLC 100 ft, ours), OSB 3 the ride HARD / SOFT / SMTH; the TF state at the top, an E-scope of the 6 km ahead with the clearance line, the fly-up's name, an X over the format for OBSTACLE and G-LIMIT (layout ours) | OSBs |
| RF switch | QUIET keeps the TFR in LPI, SILENT stops it (FlightGear's positions 0 NORM, 1 QUIET, 2 SILENT; the model rests at QUIET, the cockpit starts it at NORM). WX and LPI change nothing else: the sim has no rain, and emissions are parked (avionics-plan.md §7) | the MISC panel's switch |
| Command | the clearance under the jet closed over twice the ride's time (HARD 1.5 s, SOFT 2.5, SMOOTH 3.5: a level-off at the SCP from a 15° dive within the ride's g), then the ski toe: the climb over that path that 24 points every 250 m ahead need for their clearance (the jet levelled at the SCP over the ground under it); the g to fly it within the ride's limits (HARD 0 to 3 g, SOFT 0.5 to 2.5, SMOOTH 0.75 to 2), more in a bank (ours) | — |
| Manual TF | the HUD's TF box at the commanded flight path: the pilot flies the marker into it | — |
| Automatic TF | ADV MODE selected: STBY lit, ACTIVE while the TFR flies the pitch (gear up); the pilot keeps the roll and the speed, and his pitch adds to the TFR's | ADV MODE (Shift + F8, or the button) |
| Cues | LIMIT left of the TF box (the climb needed past the ride), NO TER right of it (terrain unknown ahead), the airspeed scale flashing outside 300–600 KCAS (ours) | — |
| Fly-ups | 2 g (the source's "about 2 g"): FLY UP below half the SCP (ours), OBSTACLE when the path needed is 10° above the jet's, G-LIMIT past the ride for 1 s (ours); over once above the SCP with nothing ahead. The name flashes on the HUD and the voice calls "Pull up" (the GAAF's call). With automatic TF always; in manual TF with MANUAL TF FLYUP at ENABLE (DISABLE at the start, ours: no fly-up after take-off) | MANUAL TF FLYUP (Shift + 3) |
| Paddle | held: no fly-up (the autopilot's paddle, one switch) | Shift + I (held) |
| TF FAIL | the TFR stops (SILENT, the power lost) under automatic TF: wings level and a 2 g pull until ADV MODE is let go; the eyebrow's TF FAIL lamp lights | — |

Open (no source found): LO TF's meaning; the dash-34's FLIR and TFR format layouts. **Tests:**
`crates/iaf-avionics/src/nav_pod.rs` (the warm-up, the command, the fly-ups, TF FAIL, the stick law),
`modern-iaf/tests/test_sim_nav_pod.gd` (both jets in flight).

## 8. The air-to-air missiles

The employment flow is the same on the Sufa, the Barak and the Adir (avionics-plan.md §6 slice 8, built 18 Nov 2026):
select the missile, lock the target with the radar, uncage the IR missile's seeker, wait for SHOOT, launch, then
watch the post-launch cues until the hit. The missiles fly the shared model unchanged (the original's chase motion
and the sim's records, [../../docs/weapons.md](../../docs/weapons.md) §5, §11); real missile performance stays parked
(avionics-plan.md §7). Everything here is for Modern IAF's jets only (`Settings.modern_radar()`): the 1998 game's
seeker, HUD and FCR are as before.

| step | the Sufa / the Barak | the Adir | key (default) | key record |
|---|---|---|---|---|
| select | `]` steps the air-to-air stores: AIM-9M or Python 5 (the SRM HUD mode), AIM-120 (the MRM mode) | AIM-9X (SRM), AIM-120 (MRM) | `]` | 66 |
| arm | MASTER ARM to ARM, ST STA on (§5) | the master arm | Shift + A | 125 |
| lock | the radar on, the target bugged and locked (TMS up) | the same on SRCH | Q, Enter, `/` | 56, 58, 132 |
| SPOT / SCAN | the SMS's AAM page, OSB 2 | the SMS portal shows it beside the weapon | Ctrl + S | 225 |
| uncage | the IR missile's seeker tracks the target it hears | the same | Shift + M | 224 |
| launch | SHOOT on the HUD, then the pickle | the same; the AIM-120 leaves once its bay doors are open (the bay door logic of §5) | Space | 69 |
| after the launch | A or T and the seconds in the HUD's timer row; the FCR marks the target | the same in the helmet under the DLZ and on SRCH | — | — |

### 8.1 The seeker head: cage, uncage, SPOT and SCAN

An IR missile's seeker head (Hebrew ראש ביות) is caged until the pilot uncages it[^dcs-f16][^mlu1]:

- **Caged**, the seeker looks along its axis: toward the radar's locked target when that is inside the missile's gimbal
  cone, else along the helmet's line of sight (the free-look and padlock views), else along the nose (the boresight).
  It hears the trackable target nearest that axis: the lock tone, and the HUD's small missile diamond on the axis.
- **Uncaged** (Shift + M with the lock tone), the seeker tracks that target anywhere inside its gimbal cone while the
  existing lock rule holds (`sight.rs` `can_track`): the diamond follows the target and grows (DCS: "a large Missile
  Diamond symbol" when "uncaged and tracking"[^dcs-f16]). A second press cages it. When the target leaves the cone or
  the lock rule, the seeker cages again (inferred).
- **SPOT / SCAN** (the MLU M1's AAM page shows SPOT by OSB 2[^mlu1]): SPOT hears within the seeker's narrow field (the
  original's 6°), SCAN within the original's search circle about the axis (6.45°). Both numbers are the existing model's
  (`sight.rs` `FOV_DEG`, `CIRCLE_PX2`); the real scan pattern is seeker behaviour and stays parked, so the two differ
  little. A new flight starts in SPOT (inferred).
- A launch takes the target the seeker hears or tracks, anywhere in its cone (the original takes it only inside the HUD's
  centre circle).

The logic is `crates/iaf-avionics/src/sight.rs` `Head` / `Seeker::uncage`, `toggle_scan`, `update_head`; the keys
reach it through `player_weapons.gd` `seeker_key` (command 280). The Rust tests:
`caged_holds_the_boresight_uncaged_tracks`, `uncaged_track_lost_cages_again`,
`caged_on_the_radar_lock_and_scan_widens_the_field`.

### 8.2 The post-launch cues

After a launch the pilot sees how long each missile still flies[^dcs-f16]:

- **The time.** "A" and the seconds to the AIM-120's seeker going active, then "T" and the seconds to impact; an IR
  missile shows only "T". With several missiles in the air the one with the longest time is shown (the DCS guide's
  missile of interest). The F-16s' HUD shows it in the right column's timer row (the DCS guide puts it under the DLZ;
  ours inferred, where a GPS bomb's time goes); the Adir's helmet under its DLZ; the FCR and SRCH at the top right.
- **The target's marks on the FCR and SRCH.** From the launch a rectangular tail behind the target's symbol, flashing
  once the AIM-120's seeker is active, and an X over the symbol for the last 8 s (the DCS guide's AIM-120 target; ours
  for every air-to-air missile, inferred). The real FCR shows the target, not the missile itself.
- **The numbers come from the shared model.** `missile.rs` `Missile::times`: the missile flies straight on from where it
  is at its speed now on its own motion (`ChaseMotion::travelled`, the DLZ's), while the target goes on at its velocity.
  The AIM-120 goes active at half its generation's seeker lock range (`sight.rs` `active_range`: 7.5 NM for the AIM-120's
  generation 4; inferred: the reach of the original's seeker without the target's afterburner).

The Rust tests: `missile.rs` `post_launch_times_count_down_to_the_real_flight`, `real_hud/f16.rs`
`after_a_launch_the_time_to_active_then_to_impact`, `the_srm_diamond_grows_when_uncaged_and_tracking`. The headless
test `modern-iaf/tests/test_sim_missiles.gd` flies each jet on its range with every missile it carries, at a drone
each, through the keys above, and sees the drone go down.

## 9. The bombs: release submodes and fuzing

The Sufa's and the Barak's unguided and laser-guided bombs (MK-82, MK-83, MK-84, GBU-10 / 12 / 16) have the real
SMS's five release submodes and its fuzing (avionics-plan.md §6 slice 9, G21, G22, G25; built 18 Nov 2026). The GPS
bombs keep PRE / VIS ([../../docs/weapons.md](../../docs/weapons.md) §13.2). The logic is
`crates/iaf-avionics/src/delivery.rs` (`IafDelivery`, wired in `player_weapons.gd`), the HUD's cues `real_hud/f16.rs`
`delivery_cues`. Every
solution runs the bomb's own fall (`bombs.rs` `real_fall` / `real_impact`, the fall the released bomb flies), so a
release at the solution lands on the target. The 1998 game and the Adir (GPS bombs only) are unchanged.

| submode | what the pilot does | what the jet does |
|---|---|---|
| CCIP | the impact point onto the target, then WPN REL (Space); off the HUD's bottom the delayed CCIP | as before ([../../docs/weapons.md](../../docs/weapons.md) §9) |
| CCRP | selects the target: the radar's designated point, the targeting pod's track, else the steerpoint; flies the flight path marker onto the azimuth steering line; holds WPN REL | the TD box on the target, the time to release in the HUD's timer row, the solution cue down the steering line; the bomb leaves by itself when its impact reaches the target[^mlu-ag] |
| DTOS | dives with the TD box (on the flight path marker) on the target, presses WPN REL (or TMS up) to designate; keeps it held through a dive or a pull-out | the box stays on the designated ground point; CCRP's steering and automatic release[^mlu-ag]; TMS down rejects the point |
| LADD | runs in low (the guide plans 200 ft at 550 KTAS) on CCRP's steering, WPN REL held; pulls up at 4 g to a 45° climb when the cues meet the marker | over the last 10 s the pull-up anticipation cue above the marker and a bar below it; after the pull-up the bar at the 45° climb and the solution cue; the release by itself in the climb[^mlu-ag] |
| MAN | sets the RET DEPR wheel and DEPR RET to PRI, presses with the reticle on the target | the primary reticle (a 2 mr pipper, a dashed 50 mr circle in a 100 mr one) depressed from the gun cross, its depression in mr beside it; the bomb leaves at once; nothing is computed[^mlu-man] |

**The SMS.** OSB 2 opens the submode menu (CCIP CCRP DTOS LADD MAN down the left, the current one boxed); OSB 18 steps
the fuze option NSTL → NOSE → TAIL; OSB 17 (AD/BA) steps the arming delay, shown as `AD 4.80SEC` on OSB 19's
row[^mlu-ag][^dcs-bombs]. Each weapon keeps its submode, fuze and arming delay in each of its two profiles (PROF1 /
PROF2, as the guide's profiles hold them[^dcs-bombs]); a profile never set starts as the other's copy.

**Fuzing.** A bomb arms its arming delay after the release: 4.80 s at the start (the MLU's SMS figure[^mlu-ag]);
the steps 2, 3, 4.8, 6, 8 and 10 s are ours (inferred). A bomb that hits sooner is a dud: no burst, no damage ("will
not give the bomb time to arm and result in a dud"[^dcs-bombs]). The three fuze options arm alike on the sim's slick
bombs (inferred: the guide's differences are for retarded and cluster bombs the sim does not carry); the burst stays
instant on impact.

**LOW.** `LOW` beside the flight path marker while a bomb released now would hit before its fuze arms; the pull-up
anticipation cue also rises for that minimum release height (the height a bomb falls during the arming delay), as
the real cue does[^dash34-low], besides the GAAF advisory.

**Keys** (keys.json records 226–230; a click on the SMS's OSBs does the same):

| function | key | record |
|---|---|---|
| next submode, as the missile step switch: CCIP → DTOS → CCRP → CCIP (LADD and MAN from the SMS)[^mlu-ag] | Ctrl + G | 226 |
| next fuze option | Alt + Q | 227 |
| next arming delay | Alt + 0 | 228 |
| RET DEPR wheel: the reticle 5 mr down / up (0–260 mr) | Ctrl + V / Alt + V | 229 / 230 |
| designate / reject in DTOS (the HUD the SOI) | `/` / Shift + `/` (TMS up / down) | 132 / 133 |
| WPN REL, held | Space | 69 |

**Ours (inferred where the guides give no figure):** the cue scales (10 mr a second, as the delayed CCIP's), the TD box
10 mr across, LADD's release only above a 10° climb, the pull-up time from a 4 g arc of radius V² / (g·3), the
RET DEPR keys' 5 mr step, the reticle's depression readout beside it. The CCRP and LADD CNTL pages (the release angle
and LADD's pull-up range typed in) are not started: the sim computes the pull-up from the bomb's fall. RBS, ULOFT and
the AD/BA keypad entry are not started.

**The target steerpoint.** The range missions' second steerpoint, on Target 1, is the target steerpoint (`"target":
true`, [data-formats.md](data-formats.md)): CCRP aims at it when selected, and a GPS bomb's PRE takes it when no
target was set before the flight (`gps.rs` `default_target`). A PRE target per bomb set on the briefing map needs a
new panel there, a new look that waits for the user's yes (avionics-plan.md G4).

**Tests.** `cargo test -p iaf-avionics delivery`: CCRP, DTOS (a toss), LADD and MAN each land within the MK-82's
spread of the target (its blast radius, 50 m); a release at 150 ft shows LOW and is a dud; `real_hud::f16`
`release_submodes_on_the_hud`. `modern-iaf/tests/test_sim_bombs.gd`: on each F-16's range the SMS menu, the fuze and
delay OSBs and keys; CCRP, DTOS, LADD and MAN each burst within the blast radius of Target 1; MAN at 150 ft is LOW and
a dud; a GBU-12 in CCRP with the Litening slaved and LASER ARM leaves by itself and hits on the spot.

[^dcs-f16]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), a simulator manual of a Block 50 M4
    tape, "AIM-9 Missile Seeker Cueing", "SRM HUD Symbology" and "MRM MFD Symbology" (pp. 571–598):
    https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
[^mlu1]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998): the HOTAS's
    uncage switch ("cages and uncages missile seeker heads") and fig. 1-35, the Air-to-Air Missile SMS page (SPOT by
    OSB 2): https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^gdots]: General Dynamics OTS, "F-16 20mm Gatling gun system" (511 rounds), https://www.gd-ots.com/wp-content/uploads/2017/11/F-16.pdf
[^w-f35]: Wikipedia, "Lockheed Martin F-35 Lightning II" (GAU-22/A, 180 rounds in the F-35A), https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II
[^w-m61]: Wikipedia, "M61 Vulcan" (6,000 rounds per minute), https://en.wikipedia.org/wiki/M61_Vulcan
[^sufa-at]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel" (GBU-10 / 12 / 16 carried, the Litening II
    pod): https://www.airforce-technology.com/projects/f-16i-soufa/
[^w-litening]: Wikipedia, "LITENING" (208 kg; the F-16I Sufa's Litening C4): https://en.wikipedia.org/wiki/LITENING
[^w-gbu12]: Wikipedia, "GBU-12 Paveway II" (230 kg): https://en.wikipedia.org/wiki/GBU-12_Paveway_II
[^w-gbu16]: Wikipedia, "GBU-16 Paveway II" (450 kg): https://en.wikipedia.org/wiki/GBU-16_Paveway_II
[^w-gbu10]: Wikipedia, "GBU-10 Paveway II" (910 kg): https://en.wikipedia.org/wiki/GBU-10_Paveway_II
[^iaf-f16i]: Israeli Air Force site, "F-16I הדור הבא" (two pods beneath the F-16I's air intake: a Litening and a
    LANTIRN navigation pod), https://www.iaf.org.il/522-19034-he/IAF.aspx (as the search engine returned it)
[^f16net-lantirn]: F-16.net, "AN/AAQ-13 & AN/AAQ-14 LANTIRN" (the navigation pod on 5L):
    https://www.f-16.net/f-16_armament_article2.html
[^w-lantirn]: Wikipedia, "LANTIRN" (the AN/AAQ-13: 199 cm, 30 cm across, 204.6 kg; the AN/AAQ-20 Pathfinder, its
    export version without the terrain-following radar): https://en.wikipedia.org/wiki/LANTIRN
[^fi-pathfinder]: Forecast International, "Pathfinder/Sharpshooter - Archived 02/2004" (Israel's Pathfinders of 1992;
    198 cm, 84 kg): https://www.forecastinternational.com/archive/disp_pdf.cfm?DACH_RECNO=556
[^twz-litening]: The War Zone, "We talk new features on the Litening large aperture targeting pod" (a Litening on the
    usual chin station of an F-16C):
    https://www.twz.com/news-features/we-talk-new-features-on-the-litening-large-aperture-targeting-pod
[^mlu-ag]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998), "Air-to-Ground
    Page" (figs. 1-38, 1-39: the submode menu, NOSE, AD 4.80SEC) and "Air-to-Ground Submodes" pp. 169–181 (CCRP, DTOS,
    LADD: the 4 g pull-up to 45°, the run-in at 200 ft and 550 KTAS; the missile step's cycle):
    https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^mlu-man]: the same guide, "Manual Weapon Delivery" p. 191 and fig. 6-33 (the primary reticle; the depression set
    by the RET DEPR thumbwheel and shown in the HUD): https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^dcs-bombs]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide* (EN, 2026), a simulator manual, "Unguided bombs"
    pp. 618–630 (the profiles, the submode menu, OSB 18's NOSE / TAIL / NSTL, the pull-up anticipation cue and the
    dud below the fuze's arming height):
    https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/
[^dash34-low]: T.O. GR1F-16CJ-34-1-1 (Hellenic AF, 1997), p. 1-173 "Pullup Anticipation and Breakaway Cue (Break X)",
    https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf (PDF page 189), as docs/real-hud.md reads it
[^bms-tfr]: Falcon BMS community, the LANTIRN navigation pod's FLIR and TFR as the dash-34 gives them (a simulator community page, secondary), as cited in [research/pods.md](research/pods.md) §3.2–3.3.
