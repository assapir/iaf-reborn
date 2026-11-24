# The first enemies: models, flight data, site make-up and behaviour — research

This page gathers what public sources say about the enemies of AI milestone 3, one Epic Fury strike
([../ai-plan.md](../ai-plan.md) §8, rows K2–K7, K11; needs X2–X3, §5). The user, 19 November 2026: "Start gathering
more info for later enemies models and behavior". His decisions of the same day set the scope: a smaller first set (one
long-range SAM, one short-range SAM, AAA and the MiG-29), the SAM pair picked "by sources", every enemy jet on the
6-DoF, models from what is on disk first and then a named download list for his word, skill as reaction time, aim and
tactics, and SAMs that follow the real procedure first, then the network. Research date: 19 November 2026. Nothing was
downloaded for this page.

What other pages already hold is cited, not repeated: the threat survey with radar bands, operators and the first
model leads ([../threats.md](../threats.md) §1–§6); the draft unit and weapon records
([../threat-records.md](../threat-records.md)); the models and licence rules for targets and bases
([models-catalogue.md](models-catalogue.md)); the 1998 engine's ground-defence fire, which the new AI uses as its hands
([../../../docs/ai.md](../../../docs/ai.md) §14); the MiG-29's hit radius and gun
([../../../docs/real-weapons.md](../../../docs/real-weapons.md) §1.4, §1.5).

**Limit.** This page holds no missile performance (ranges, speeds, guidance, seekers, fuzing, kill probability) and no
countermeasure or jamming effectiveness. Where an item needs such a figure it says "out of scope here". Site make-up,
crew procedure, appearance and aircraft flight data are in scope.

**Terms**
- **SAM:** surface-to-air missile. **AAA:** anti-aircraft artillery. **IADS:** integrated air defence system (sites,
  radars and command posts that pass targets to each other).
- **TEL / TELAR:** transporter-erector-launcher (a launcher vehicle); TELAR: one with its own radar.
- **CP:** command post. **SOC:** sector operations centre. **GCI:** ground-controlled intercept.
- **EMCON:** emission control (a radar kept off by choice).
- **KADHQ:** Khatam al-Anbiya Air Defense Headquarters, Iran's national air-defence command (DIA spelling
  "Khatemolanbia").
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning; "open" means no source was
  found. **Second-hand** marks a fact taken from another page's quote of a source not read here. **Secondary** marks an
  enthusiast, trade or vendor page.

## 1. The answer first

| type | pick | model | flight or site data | the main gap |
|---|---|---|---|---|
| long-range SAM | **S-300PMU-2** (SA-20): a 30N6E2 engagement radar, a 96L6E search radar and four towed 5P85TE2 launchers, as Iran's batteries were seen (§2.3) | none on disk; CC BY candidates for the launcher and the 30N6 radar; our own low-poly 96L6E, 64N6E2 and truck-borne 30N6E2 models (§6) | make-up well documented; procedure documented at the level of who searches, who designates, targets per radar, missiles per target, set-up time (§2.4) | the crew's timings between designation and launch; the Iranian command post's make-up |
| short-range SAM | **Tor-M1** (SA-15): a self-contained tracked vehicle, four per battery with a Ranzhir CP (§2.5) | none on disk; one CC BY candidate built from scratch (§6) | make-up and the engagement sequence published, step by step (§2.6) | Iran's own Tor battery layout |
| AAA | **ZSU-23-4 Shilka**, as drafted; Iran's towed guns later (§3) | none on disk; CC BY low-poly candidate (§6) | crew, radar and optical modes, burst rules, how it deploys (§3.1) | Iran's own employment of its ZSUs |
| fighter | **MiG-29A (9.12)** | **on disk:** `shared/extra/models/mig29/mig29.glb`, GPL-3.0, no download (§4.1) | geometry, masses, engine and published performance; **no aerodynamic tables public** (§4.2) | lift, drag and moment tables; inertia; the α limit |
| fighter, later | F-14A (not in the first set) | candidates in [../threats.md](../threats.md) §5 | **public wind-tunnel and engine data exist** (AFWAL, NASA) (§4.3) | the licence of the FlightGear F-14 that uses them |

The behaviour sources (§5) are three public ones that suit a sim's AI: the US Army's opposing-force tactics manual
(how an air-defence force passes targets, keeps radars off, relocates and ambushes), DIA's report on Iran (how Iran's
air-defence command is organised and layered), and open analyses of the June 2025 war (how integrated it was in
practice: not well).

## 2. The SAM pair

### 2.1 What was compared

Scored on what is public about the site's make-up (radars, launchers, vehicles), the crew's procedure, and the look, for
the systems on the draft list and the other Iranian candidates.

| system | make-up public | procedure public | look public | in Iran in 2026 | for the first set |
|---|---|---|---|---|---|
| S-300PMU-2 | full: every vehicle, its chassis and role[^apa-s300]; Iran's batteries seen on the ground[^bc-mashhad] | who searches and designates, targets and missiles per radar, set-up time[^fas-s300] | photos, site layouts from imagery[^apa-sites] | four batteries delivered 2016; launchers seen at two sites near Tehran in February 2026 without their radars[^acw-s300] | **long-range pick** |
| Bavar-373 | the launcher truck (Zoljanah 10×10, two canisters) and a phased-array radar on a ZAFAR truck; no battery make-up[^w-bavar] | none | parade photos only | in service; perhaps beside an S-300 launcher near Tehran[^acw-s300] | no: too little public |
| 3rd Khordad | battery = one TELAR + two TELs; battalion = four batteries, a Bashir radar and a C2 unit[^w-3kh] | targets and missiles per TELAR only[^w-3kh] | exhibition photos | in service; struck June 2025 and 28 February 2026[^w-3kh] | no: medium range, procedure thin; first of the later list |
| 15th Khordad | the Najm-804 radar named at Natanz[^bd-natanz] | claims only ([../threats.md](../threats.md) §2) | few | near Natanz[^bd-natanz] | no |
| Tor-M1 | full: the vehicle's sensors, eight missiles, the battery and its CP, reload vehicles[^mis-tor][^w-tor] | the engagement sequence step by step, launch spacing, duty cycle[^mis-tor] | many photos | 29 vehicles; one Tor among the defences of Natanz[^bd-natanz] | **short-range pick** |
| 2K12 Kub / Fater-1 | full (Soviet-era) | partly | full | Houthis, Syrian remnants ([../threats.md](../threats.md) §2) | no: not Iran's |
| Pantsir-S1 | full | partly | full | listed in Iran's inventory on Wikipedia[^w-iriadf], not by DIA[^dia] | no |

### 2.2 Recommendation: S-300PMU-2 and Tor-M1

1. **They are the two best-documented systems on the list.** The S-300PMU-2's vehicles, chassis and roles are all
   published[^apa-s300], Iranian batteries have been photographed with their parts named[^bc-mashhad], and site
   layouts are drawn from imagery[^apa-sites]. The Tor-M1's engagement is published as a numbered sequence[^mis-tor].
2. **They are Iran's own two tiers.** DIA lists the SA-20c (S-300PMU-2) first among Iran's long-range systems and the
   SA-15 (Tor-M1) first among the short-range ones, and says Iran would most likely use the SA-20c to protect its
   nuclear sites and Tehran[^dia].
3. **They meet at a real kind of target.** The researchers who mapped Natanz's defences from an Iranian video found one
   Tor among four radars there[^bd-natanz]; S-300 batteries sat at Esfahan, Bushehr and Khavar Shahr, and one based at
   Mehrabad deployed to Mashhad[^bc-mashhad]. A strike on a defended site in central Iran meets this pair (inferred;
   the target is the user's choice, [../ai-plan.md](../ai-plan.md) §9 question 7).
4. **Clean models exist for both** (§6): launcher and Tor models built from scratch under CC BY, and a radar the
   uploader drew himself.

**Against the S-300:** in 2026 its real state is poor. Most S-300 sites were reported empty after Israel's strikes of
October 2024[^fpri]; in February 2026 launchers stood at two sites near Tehran without the radars a working battery
needs, one beside a domestic launcher, perhaps a Bavar-373[^acw-s300]. The sim can place a whole battery (the
documented make-up) and leave the 2026 state to the mission (inferred). The 3rd Khordad, Iran's own system and in
combat in 2025–2026, is the first of the later list for the medium tier.

### 2.3 S-300PMU-2: the site

| part | role | vehicle and look | per Iranian battery | sources |
|---|---|---|---|---|
| 83M6E2 battle management: the 54K6E2 command post and the 64N6E2 "Big Bird" search radar | search for the regiment; designate targets to up to six batteries | 54K6E2: a container on a Ural-532361 8×8 with a deployable mast; 64N6E2: a radar on a MAZ-79100 tractor | open: whether Iran's order held a 54K6E2 / 64N6E2 | [^apa-s300] |
| 96L6E all-altitude search radar | gives one battery its own search, so it can fight alone | radar on an MZKT-7930 chassis | one, seen at Mashhad (not deployed in July 2017) | [^apa-s300][^bc-mashhad][^fas-s300] |
| 30N6E2 "Tomb Stone" engagement radar | tracks targets and directs the battery's fire | radar and control cabins on a MAZ-79100 chassis, a flat phased-array face on a mast; an optional 40V6M / 40V6MD tower lifts it over trees or terrain | one | [^apa-s300][^bc-mashhad] |
| launchers 5P85SE2 (self-propelled) or 5P85TE2 (semi-trailer) | four sealed missile canisters each, raised upright to fire | 5P85TE2: a semi-trailer behind a KrAZ-260 or BAZ-6402 tractor; 5P85SE2: on a MAZ-79100; four hydraulic jacks level the vehicle | up to 12 per radar; a full Iranian battery has four 5P85TE2, two were seen at Mashhad; about 15–16 m long in imagery | [^apa-s300][^fas-s300][^bc-mashhad][^acw-s300] |
| support | reloads, power, survey | 5T58-2 missile transporters and 22T6-2E2 transloaders (KrAZ-260, Ural-532361), a 5I57 diesel generator, power converters on MAZ trailers, a crew vehicle, a fuel tanker, a survey vehicle | open | [^apa-s300] |
| relay | links the parts | 15Ya6ME digital radio relay, up to 90 km | open | [^apa-s300] |

**Layout.** On mobile sites, four launch positions surround a central raised berm that holds the engagement radar;
revetments, where built, take two to four or more launchers each, and some sites have none. Mast-mounted radars stand
where forest or terrain calls for them. Many batteries reuse older SAM sites[^apa-sites]. No source gives the
distances between the parts (open). Iran built a pad on the north side of Mashhad's runway for a battery that comes
and goes with the Supreme Leader's visits, moving by highway from Mehrabad[^bc-mashhad].

### 2.4 S-300PMU-2: the procedure

What is public, as the site's AI can use it:

| step | what the sources say | sources |
|---|---|---|
| search | the Big Bird at the regiment's CP makes the first detection; a battery with a 96L6E searches for itself | [^fas-s300][^apa-s300] |
| designation | the CP relays the coordinates and orders to the batteries (the handover itself is not described) | [^apa-s300] |
| track and engage | the 30N6E2 engages up to six targets at once, two missiles per target | [^fas-s300] |
| launch spacing | "three missiles per second" for the battery (FAS, 2000); a 3 s launch interval (Wikipedia's table, [../threats.md](../threats.md) §2): the sources conflict (open) | [^fas-s300] |
| set-up | "five minutes to deploy once it comes to the halt"; no cables between vehicles (radio links) | [^fas-s300] |
| relocation | a navigation set (NK Orientir) is fitted for "hide, shoot and scoot" | [^apa-s300] |
| emission control | no S-300-specific source; the general rule in §5.2 (radars off until cued, on for the last seconds) | [^tc7100] |
| missile fly-out, envelope | out of scope here | — |

**For row K5 (inferred):** a battery's tree: search (96L6E, or a cue from the network) → designation to the 30N6E2 →
track → two missiles per target, at most six targets → the radars off and the battery's move to an alternate position
by the rules in §5.2. The 1998 engine's quirks (one missile in the air, no shot 90° off the heading;
[../../../docs/ai.md](../../../docs/ai.md) §14) are what K5 replaces.

### 2.5 Tor-M1: the vehicle and the battery

| part | what it is | sources |
|---|---|---|
| 9A331 combat vehicle | tracked (GM-5955 chassis), 7.5 m long, 3.3 m wide, 5.1 m high with the radar raised; crew 3 (the infobox; the text says four) | [^w-tor] |
| its sensors | a search radar on top of the turret (a "truncated parabolic antenna" that folds flat for travel; F-band pulse-Doppler), a phased-array tracking radar on the turret's front (G/H-band, later K-band, pulse-Doppler), an optical tracker (Iran's Dezful upgrade adds a thermal camera), a two-processor computer | [^w-tor][^mis-tor] |
| its missiles | eight, upright between the two radars, in two modules of four (9M334 modules of 9M331 rounds) | [^w-tor][^mis-tor] |
| battery | four vehicles with a mobile command post (Ranzhir-M / 9S737) | [^w-tor][^mis-tor] |
| reload | 9T244 transport-loader with a crane (two modules per load), 9T245 transporter; loading two modules takes 25 minutes | [^mis-tor] |
| wheeled versions | Tor-M1TA (the cabin on a Ural-5323, the antenna-launcher on a trailer), Tor-M1TB (towed, three trailers): 8–15 minutes to deploy | [^mis-tor] |
| in Iran | 29 vehicles (IISS 2025, [../threats.md](../threats.md) §1.1); one among Natanz's defences | [^bd-natanz] |

### 2.6 Tor-M1: the procedure

The engagement, as the Russian textbook source of missilery.info describes it[^mis-tor]:

1. The search radar watches all round, detects targets and identifies them.
2. The computer analyses the picture and picks the most dangerous targets.
3. The tracking radar searches for and captures one designated target and tracks it in three coordinates.
4. One or two missiles are launched at it in sequence, about 4 s apart.
5. After launch the vehicle takes over each missile (its guidance: out of scope here).

Around it:
- **On the move and at a halt.** The vehicle searches and tracks on the move; it fires only at a halt[^w-tor].
- **Two targets at once** on the Tor-M1 (the first Tor: one); up to 48 detected and 10 tracked at once[^w-tor].
- **Duty limits:** the equipment runs in cycles of 10 minutes on and 10 minutes off; after three engagements it needs
  at least an hour's break, during which it may be switched on once for one minute to fire[^mis-tor] (as the page
  states; inferred: an equipment duty limit, not an emission-control rule).
- **Missile fly-out, envelope, reaction-time figures:** out of scope here ([../threats.md](../threats.md) §2 holds the
  drafted figures).

**For row K5 (inferred):** a Tor tree: move or hold → search → pick the most dangerous → halt → track → one or two
shots 4 s apart → second channel free for a second target → back to search; the duty limits as a cap on how long it
can radiate.

## 3. AAA

### 3.1 ZSU-23-4 Shilka

| item | what the sources say | sources |
|---|---|---|
| crew | four: the driver (front left of the hull); the commander, gunner and radar operator in the turret | [^fas-zsu] |
| fire control | radar (the RPK-2 "Gun Dish" on the turret) for search, acquisition, tracking and ranging, with "many false returns (ground clutter) under 60 m (200 ft) of altitude"[^w-zsu]; a computer for the lead; conventional optical sights as well; it fires on the move | [^fas-zsu] ([../threats.md](../threats.md) §2 for the band) |
| bursts | "normally fired in bursts (2-3 rounds per barrel)" in the text; the same page's table lists 30 rounds per barrel per burst (conflict, open) | [^fas-zsu] |
| load | about 2,000 rounds on the vehicle, about three HE-T to one API-T; supply trucks follow with more | [^fas-zsu] |
| organisation (Soviet) | a platoon of four ZSU-23-4s with four SA-9s in a regiment's AA battery; two ZSUs behind each first-echelon battalion, about 200 m apart and about 400 m behind the lead elements; supply trucks 1.5–2.5 km behind | [^fas-zsu] |
| range, rate of fire, muzzle speed | in [../threats.md](../threats.md) §2 and the draft record; no more here | — |

The rules a gun crew follows (the opposing-force manual[^tc7100], inferred to fit a ZSU): self-propelled AA guns fire on
the move with passive electro-optical sights (§11-70); the greatest threat is engaged first, with as many weapons as
possible, and fire stays on one target rather than switching (§11-132); it is better to fire early and waste rounds
than to let the aircraft reach a good attack position (§11-132); the radar stays off until the last seconds when the
gun gets targets from elsewhere (§11-134); single guns or teams sit in ambush on likely approaches, chosen by where
radar cover is masked by terrain (§11-137–§11-145), and tracer may be removed from the belts so that near misses do
not alert the target aircraft (§11-143).

### 3.2 Iran's guns

Iran's guns, by the Wikipedia article on its air-defence force: ZU-23-2, Oerlikon GDF 35 mm (with "modest numbers" of
Skyguard fire control), the domestic Samavat 35 mm, KS-19 and its automatic Sa'ir version (100 mm), Mesbah-1,
ZSU-23-4, ZSU-57-2[^w-iriadf]. In the June 2025 war, videos showed AAA firing at Israeli aircraft while "SAMs were
notably absent"[^fpri]. No source found names which guns stand at which Iranian site (open).

**Recommendation:** keep the ZSU-23-4 as drafted: Iran holds about 100 ([../threats.md](../threats.md) §1.1), its
crew and fire rules are the best documented, and a clean low-poly model exists (§6). A towed site gun (ZU-23-2, or a
35 mm pair with its fire-control radar) fits a fixed target better (inferred) and is a later row, outside the first
set.

## 4. The MiG-29

### 4.1 Model

On disk and in the repo: `shared/extra/models/mig29/mig29.glb`, converted by `crates/iaf-tools/src/mig29.rs` from
the FlightGear MiG-29 9-12 by Enrique Laso Leon (external model) and Sergey Salov, whose read-me states "GNU General
Public License version 3"[^fg-mig29-gh]. It needs no download. Two notes:
- [../threats.md](../threats.md) §5's MiG-29 row (licence "GPL version 2", "open") is about a different FlightGear
  MiG-29, the FGAddon one; the repo's model is the GitHub one above (`shared/extra/models/mig29/SOURCES.md`).
- The model wears our Syrian roundels; an Iranian MiG-29 needs the IRIAF's markings, a repaint in the converter
  (inferred). The record (`modern-iaf/data/db/units/mig29a.json`, approved with K2 on 2026-11-22) points to it.

### 4.2 Flight data

The 6-DoF needs, per jet ([../flight-model.md](../flight-model.md) §9): lift, drag and moment tables over α, β, Mach
and the controls; the engines' thrust over Mach and altitude; masses and inertia; the control laws; the limits. What
is public for the MiG-29 (9.12):

| item | value | source |
|---|---|---|
| size | length 17.32 m, span 11.36 m, height 4.73 m, wing area 38 m² | [^w-mig29] |
| masses | empty 11,000 kg; gross 14,900 kg; maximum take-off 18,000 kg; internal fuel 3,500 kg | [^w-mig29] |
| fuel tanks | 4,300 L internal (Wikipedia, citing Gordon 2006: six tanks); the FlightGear model's comments split the same 4,300 L into 650, 870, 1,810, 2 × 155 and 2 × 330 L, with a 1,500 L drop tank | [^w-mig29][^fg-mig29-gh] |
| engines | two Klimov RD-33: 49.4–50.0 kN dry, 81.3–81.6 kN with afterburner each (the two Wikipedia pages differ slightly); specific fuel consumption 75 kg/(kN·h) dry, 188.1 with afterburner; bypass ratio 0.49; 1,055 kg each | [^w-mig29][^w-rd33] |
| performance | Mach 2.3+ at altitude; ceiling 18,000 m; climb 330 m/s; +9 g | [^w-mig29] |
| α limit | 24–28° by variant and by the limiter's setting, and a lift coefficient of 1.5 at 26° (second-hand: forum posts quoting MiG-29 manuals; open) | [^wt-forum] |
| handling | in the 1995 Luftwaffe–USAF exercise at Decimomannu: "exceptional nose-pointing capability" below 200 kt; above 200 kt the F-16 accelerates away; "not a continuous nine-g machine"; poor view to the rear (second-hand: the National Interest quoting Code One's "Schlemming with the Fulcrum") | [^ni-f16] |
| first-hand flight report | Lambeth flew the MiG-29UB at Kubinka on 15 December 1989 and reported its handling (RAND R-4000-RC, 1991, free PDF); the PDF is a scan without text, not yet read (open) | [^rand-lambeth] |
| aerodynamic tables | **none found public**: searches of NASA, AGARD and DTIC listings found no MiG-29 wind-tunnel or flight-test tables (open). A Russian military textbook, "Практическая аэродинамика самолета МиГ-29" (practical aerodynamics of the MiG-29), holds lift, drag and pitching-moment graphs: Eagle Dynamics checked its own CFD against them (second-hand). Copies found online are unofficial scans and are not linked here | [^ed-cfd][^avid-pa] |
| a published manual | Schiffer sells "MiG-29 Flight Manual: Unclassified" in English; its contents were not seen (open) | [^schiffer] |
| the FlightGear MiG-29's model | its flight model (`MiG-29.xml`, GPL-3.0) was generated by the JSBSim tool Aeromatic in 2010 from size and weight (its inputs: lift slope 3.6 per radian, maximum lift coefficient 1.0, zero-lift drag 0.024, induced-drag factor 0.12) and then tuned by hand; the file cites no source. Usable as a shape to compare against, not as sourced data (inferred) | [^fg-mig29-gh] |
| inertia, control laws, roll rate, sustained turn | open | — |
| the R-73, R-27R and the gun's ballistics | the missiles: out of scope here; the gun: [../../../docs/real-weapons.md](../../../docs/real-weapons.md) §1.5 | — |

**Route (inferred), as the F-35I was built** ([../flight-model.md](../flight-model.md) §9.19): no MiG-29 tables are
public, so its 6-DoF set would take TP-1538's tables on the MiG-29's wing (38 m², 11.36 m) with its own masses, the
RD-33's thrust (the static figures above; the lapse with Mach and altitude taken from the F-16's table shape, open),
+9 g, an α limit inside 24–28° once a manual gives the figure, and the published performance (Mach 2.3, 18,000 m,
330 m/s) as the fit targets. The textbook's graphs, if a legitimate copy is found, would replace the inferred lift and
drag. A MiG-29 so built is an F-16-shaped jet with MiG-29 weights and engines; that the real jet points its nose better
at low speed and holds energy worse (above) is then a tuning note, not data.

### 4.3 The F-14A (later, after the first set)

The F-14 has much better public data than the MiG-29. The FlightGear F-14's author lists his sources[^zaretto]:
- AFWAL-TR-80-3141, Parts I and III (Johnston, Mitchell, Myers, 1980), "Investigation of High-Angle-of-Attack
  Maneuver-limiting factors": analysis, simulation and the aerodynamic models.
- NASA TN D-6909 (Grafton, Anglin, 1972): dynamic stability derivatives from −5° to 90° α for a variable-sweep fighter
  with twin tails.
- NASA TM X-3106 (Szuch, Bruton, 1974): a real-time model of the TF30-P-3 engine (Iran's F-14A has a later TF30;
  the author calls the P-3 "a good model than can be adapted").
- A FlightGear change log names NASA TM-X-62306 for the longitudinal, spoiler and flap data (second-hand)[^fg-f14wiki].

A 6-DoF from these is feasible (inferred). The FlightGear F-14's licence statement is still open
([../threats.md](../threats.md) §5); the reports themselves are what the sim would use.

## 5. Behaviour sources

### 5.1 Enemy fighters

- **Fighters flown from the ground.** The US Army's opposing-force manual: the force is "heavily reliant" on its
  vectoring and target-designation posts (radar posts with radio) for counter-air, which "identify enemy targets and
  redirect fighters in flight to the proper location at the most opportune time"; an airborne control station or
  visual observers can stand in for them (§10-32–§10-35, §10-72)[^tc7100].
- **Iran.** DIA: the IRIAF's missions include air intercept; the KADHQ controls the radar network, the SAMs and the
  visual observation posts, so Iran's fighter control sits in the air-defence command, not in the fighter units
  (inferred from DIA)[^dia]. In March 2026 MiG-29As and Yak-130s were seen over Tehran, assessed as interceptors of
  drones and cruise missiles (Defense Mirror, from a Telegram channel; unconfirmed)[^dm-tehran].
- **How a MiG-29 fights.** The handling notes in §4.2 (strong nose pointing below 200 kt, weaker energy fight above,
  poor rear view) are what a MiG-29 BFM leaf weighs (inferred, row K4).
- **BFM itself.** A published reference is Robert Shaw's "Fighter Combat: Tactics and Maneuvering" (Naval Institute
  Press, 1985)[^shaw]. A US Navy basic-fighter-manoeuvring training instruction (CNATRA P-826, 2018) turned up only as
  a third-party copy; its release status is open.
- **BVR shots and the defence after them** depend on the missile's envelope: out of scope here.
- **Iranian fighter tactics:** no open doctrine source found (open). The rows take the opposing-force rules above.

### 5.2 Air-defence networks

**How Iran's is meant to work (DIA, 2019)[^dia]:**
- The KADHQ oversees and coordinates air defence across the army's air-defence force (IRIADF) and the IRGC's aerospace
  force: "It controls the country's air defense C2, air surveillance radars, SAM systems, and network of visual
  observation posts."
- Control is centralised in peacetime at the national Air Defense Operations Center "and can be decentralized during
  crisis or conflict", handing decisions down to "a network of fixed and mobile regional sector operations centers
  (SOCs)", which run their areas and coordinate with adjacent sectors.
- Layers: long range SA-20c (S-300PMU-2), SA-5, Bavar-373, Sayyad-3; medium I-HAWK / Mersad, CSA-1, 3rd Khordad, Raad,
  Talash, Sayyad-1 / 2; short SA-15 (Tor-M1), Rapier. Priorities: Tehran, the nuclear sites and the Gulf bases.
- Early-warning radars named on Wikipedia: over-the-horizon Sepehr, Ghadir and Nazir; Falaq, Matla-ul-Fajr, Kashef,
  Alim, Asr, Arash, Ghamar; about six Chinese JY-14s[^w-iriadf].

**How it worked in 2025 (open analyses):**
- At Natanz, an Iranian video showed three screens with four radars on them (a Najm-804, two P-12 derivatives, a Tor):
  separate screens, "siloed and fragmented" (James Martin Center for Nonproliferation Studies, May 2025)[^bd-natanz].
- A gap between early-warning sensors and the SAMs: data had to be handed between systems, "introducing delays
  and uncertainty"; early-warning radars were destroyed in the opening strikes (FPRI, October 2025)[^fpri].

**The general rules a network's AI can take (US Army opposing-force manual, chapter 11)[^tc7100]:**

| rule | paragraph |
|---|---|
| every level has its own IADS and passes early warning, acquisition, tracking and firing data up, sideways and down | §11-15 |
| sectors with overlapping coverage; risk is accepted at the seams | §11-17–§11-19 |
| a cue needs only "time, bearing, range, speed, altitude/height, and aircraft type": enough for the receiving radar to know where and when to look and when to switch on | §11-35 |
| units fight with their radars off on data from the higher radars; knocking out one radar does not break the net | §11-36, §11-45 |
| radars stay off, and "if required, the radar will turn on at the last few seconds to acquire the target before launching" | §11-134 |
| engage the greatest threat first, with as many weapons as possible; stay on one target; fire early rather than late | §11-132 |
| two or three alternate positions; move after a reconnaissance overflight, after an attack is beaten off, or after 4–6 hours in place, as often as every 10 minutes for a capable system; at night when possible | §11-121 |
| no more than one third of a unit's assets move at once; those longest on alert move first | §11-119, §11-187 |
| ambushes on likely approaches where radar cover is masked by terrain; tracer removed so near misses do not alert the aircraft | §11-137–§11-145 |
| dummy positions and decoys | §11-184 |

**For rows K5–K6 (inferred):** the network as an early-warning layer (named radars) feeding sector centres that cue the
batteries with the §11-35 track data; each battery's tree turns its own radar on late (§11-134) and relocates by
§11-121; a per-mission "integration" setting from fully linked (the doctrine) to siloed with a hand-over delay (Iran in
2025, above), the delay drawn from the skill's reaction time (X4).

## 6. Models: the list for the user's word

Already on disk: only the MiG-29 (§4.1). Searched on this machine: `assets/`, `~/.cache` (the FlightGear F-16 checkout,
whose ramp props are base furniture, [models-catalogue.md](models-catalogue.md) §1), `tools/`, `shared/extra/models/`
and the home folder: no SAM, radar or gun model. The 1998 game's own units are its data and are not used by Modern
IAF. Candidates were found through Sketchfab's public search API (downloadable, CC BY or CC0) on 19 November
2026[^sf-api]; sizes are the listing's glTF archive; a free Sketchfab account is needed, which the user accepted on 17
November ([models-catalogue.md](models-catalogue.md) §7). Each download waits for his word.

| # | unit | candidate (author) | licence | faces / size | provenance from the listing | note |
|---|---|---|---|---|---|---|
| 1 | MiG-29 | `shared/extra/models/mig29/mig29.glb` (FlightGear MiG-29 9-12) | GPL-3.0 | in the repo | `SOURCES.md` | **on disk**; Iranian markings to paint |
| 2 | S-300 launcher | "S-300 5P85 Launcher with 9M83 Missiles" (xFORTUNAx)[^sf-5p85] | CC BY | 285,136 / 21.6 MB | "Built from scratch in Blender from public ref[erences]" | self-propelled MAZ-543 with S-300V-type missiles, where Iran's launchers are towed 5P85TE2 (a stand-in, inferred); heavy for a battery of four on the Iris Xe (a simpler level of detail needed, inferred) |
| 2a | S-300 launcher, alternative | "S-400 Launcher on MAZ-543 with 5V55R Missiles" (xFORTUNAx)[^sf-s400] | CC BY | 278,250 / 19.3 MB | "Built from scr[atch]" | the same base vehicle; the 5V55R is an earlier S-300P missile (inferred), so its canisters may be the closer look |
| 2b | S-300 launcher, low poly | "Lowpoly S300" (S1Priv)[^sf-s1-s300] | CC BY | 24,028 / 0.4 MB | "Based on the real life S-300"; tags "pixel-art", "blockbench" | a blocky style unlike the sim's jets (inferred) |
| 3 | 30N6E2 engagement radar | "30N6E 'Flap Lid' B Phased Array Radar" (aardque)[^sf-30n6] | CC BY | 25,227 / 1.3 MB | the uploader's own model, first on SketchUp's 3D Warehouse in 2013, reworked | the 30N6E of the PMU-1; how much the PMU-2's 30N6E2 differs in look is open |
| 4 | 96L6E and 64N6E2 search radars | none found | — | — | — | our own low-poly models, 2026-11-23 ([../../../docs/ai.md](../../../docs/ai.md) §15.4) |
| 5 | Tor-M1 | "Tor-M1 SAM with 9M331 Missiles (Animated)" (xFORTUNAx)[^sf-tor-xf] | CC BY | 155,034 / 25.3 MB | "Built from scratch in Blender from public reference drawings"; turret, antennas, tracks and cell covers animated, two launches | the listing says four missiles on a rack, where the real vehicle carries eight (open: check on download) |
| 5a | Tor-M1, low poly | "TOR-M1" (urastyzh)[^sf-tor-ur] | CC BY | 14,074 / 0.2 MB | no description (open) | provenance to check |
| 6 | ZSU-23-4 | "Lowpoly Zsu-23-4" (S1Priv)[^sf-zsu] | CC BY | 67,456 / 0.9 MB | "Based on real life Soviet military technology" | the low-poly pick ([../threats.md](../threats.md) §5) |
| 6a | ZSU-23-4, detailed | "ZSU-23-4 \| High-Quality model" (scout.)[^sf-zsu-sc] | CC BY | 211,263 / 4.1 MB | no description (open) | provenance to check |

**First picks if he says yes:** 2 (or 2a), 3, 5 and 6: about 49 MB.

**Left out:**
- Uploads marked as taken from games ("War Thunder", "WARNO"): the S-300 5P85SE and its 5N63S / 5N64S radars, several
  ZSU-23-4s, a Tor-M1, an Oerlikon 35 mm (KojfDiscord, Johnan1)[^sf-api]. The licence rule of
  [../threats.md](../threats.md) §5 excludes them.
- 42manako's 3rd Khordad, Tor-M1, MiG-29s and Chinese radars: the uploader marks another model as ripped from a game
  ([models-catalogue.md](models-catalogue.md) §3.5).
- Chenzoss's "s300 launcher iran", "s300 radar" and "russian s300 air defense systems": each about 120,000 faces,
  published the same day, no description beyond the title[^sf-api]: provenance open, left out until shown.
- The OPRF assets: they hold an S-300, a ZSU-23 and a GCI radar; the S-300's file header says GPL-3.0-or-later
  (© 2015 onox; authors pinto, Nikolai V. Chr., onox), but the repository still has no licence file (last change
  21 October 2026)[^oprf]. Excluded until its authors state one; the user's 17 November yes to asking them stands
  ([models-catalogue.md](models-catalogue.md) §7). Nikolai V. Chr. is also the F-16 model's author, already credited
  (inferred: one contact for both).

## 7. Gaps

- **Out of scope here:** every missile's performance (the S-300's, the Tor's, the R-73's, the R-27R's), the AAA's
  ballistics beyond [../threats.md](../threats.md), and the effect of chaff, flares and jamming on any of them.
- **MiG-29:** aerodynamic tables, inertia, the α limit, the engines' Mach and altitude lapse, roll rate, sustained turn;
  the RAND flight report unread (§4.2).
- **S-300:** the crew's timings from designation to launch; the launch spacing (sources conflict); whether Iran's
  batteries have the 54K6E2 / 64N6E2; distances between the parts on a site.
- **Tor-M1, ZSU-23-4:** how Iran deploys them around a site (battery layout, spacing).
- **Fighters:** no open source on Iranian fighter tactics; the GCI reliance is the opposing-force manual's, applied to
  Iran by inference.
- **Models:** the 96L6E and 64N6E2 radars are our own models (the 64N6E2 models found are War Thunder rips, excluded). Picks 2, 3, 5 and 6 were downloaded by the user on 22 November 2026 and are in the game ([../../../docs/ai.md](../../../docs/ai.md) §15.4); the Tor model's "four missiles on a rack" are a display rack beside the vehicle (left out); its turret's cell covers are shut, so its own count does not show.

[^apa-s300]: Carlo Kopp, Air Power Australia, "S-300PMU2 Favorit / SA-20 Gargoyle", May 2009, updated to April 2012, https://www.ausairpower.net/APA-S-300PMU2-Favorit.html (83M6E2 = 54K6E2 + 64N6E2, up to six batteries; 30N6E2 with up to twelve 5P85SE2 / TE2; 96L6E for autonomous batteries; chassis; 15Ya6ME relay; NK Orientir for "hide, shoot and scoot"; read 2026-11-19).
[^apa-sites]: Sean O'Connor, Air Power Australia, "Soviet/Russian SAM Site Configuration Part 2", APA-TR-2009-1205-B, January 2010, updated April 2012, https://ausairpower.net/APA-Rus-SAM-Site-Configs-B.html (S-300P layouts: four launch positions around a raised radar berm; revetments; masts; reused sites; no spacing figures; read 2026-11-19).
[^fas-s300]: Federation of American Scientists, "S-300PMU SA-10 GRUMBLE", updated 30 June 2000, https://nuke.fas.org/guide/russia/airdef/s-300pmu.htm (battery of up to 12 TELs with four canisters; Big Bird at the regimental CP for first detection; six targets, two missiles per target; "three missiles per second"; five minutes to deploy at the halt; 96L6E with the 83M6E2; read 2026-11-19).
[^bc-mashhad]: Bellingcat, "Iran: New SAM Site At Mashhad", 23 October 2018 (first in Offiziere.ch), https://bellingcat.com/news/2018/10/23/iran-new-sam-site-masshad (two 5P85TE2, a 30N6E2 and a 96L6E at Mashhad; a full Iranian battery has four TELs; other active sites Bushehr, Khavar Shahr, Esfahan; the battery came from Mehrabad, its usual site; read 2026-11-19).
[^acw-s300]: Sam Lair, Arms Control Wonk, "Whither the Iranian S-300?", 20 February 2026, https://www.armscontrolwonk.com/archive/1221458/whither-the-iranian-s-300/ (one S-300 launcher at each of two sites near Tehran, about 15–16 m long, "Notably absent from both sites are the radars"; a domestic launcher, perhaps a Bavar-373, beside one; possibly decoys; read 2026-11-19).
[^fpri]: Sam Lair, Foreign Policy Research Institute, "Shallow Ramparts: Air and Missile Defenses in the June 2025 Israel-Iran War", 17 October 2025, https://www.fpri.org/article/2025/10/shallow-ramparts-air-and-missile-defenses-in-the-june-2025-israel-iran-war/ (gap between early warning and SAMs, "introducing delays and uncertainty"; AAA seen firing, "SAMs were notably absent"; early-warning radars hit in the opening strikes; S-300 sites reported empty after October 2024; read 2026-11-19).
[^bd-natanz]: Aaron Mehta, Breaking Defense, "Iran's air defenses around nuclear site more brittle than expected: Exclusive analysis", 15 May 2025, https://breakingdefense.com/2025/05/irans-air-defenses-around-nuclear-site-more-brittle-than-expected-exclusive-analysis/ (James Martin CNS, Sam Lair: a Najm-804, two P-12 derivatives and a Tor around Natanz, on separate screens; "siloed and fragmented"; read 2026-11-19).
[^dia]: Defense Intelligence Agency, "Iran Military Power: Ensuring Regime Survival and Securing Regional Dominance", 2019, appendix D pp. 63–71, https://www.govinfo.gov/content/pkg/GOVPUB-D5_200-PURL-gpo128931/pdf/GOVPUB-D5_200-PURL-gpo128931.pdf (KADHQ; centralised national ADOC, decentralised to fixed and mobile SOCs; the layers table; SA-20c for nuclear sites and Tehran; IRIAF missions; read 2026-11-19).
[^tc7100]: US Army, TC 7-100.2 "Opposing Force Tactics", 9 December 2011, approved for public release, chapters 10 (aviation, §10-32–§10-35, §10-72) and 11 (air defence), https://www.govinfo.gov/content/pkg/GOVPUB-D101-PURL-gpo122554/pdf/GOVPUB-D101-PURL-gpo122554.pdf (read 2026-11-19).
[^w-bavar]: Wikipedia, "Bavar-373", https://en.wikipedia.org/wiki/Bavar-373 (two canisters on a Zoljanah 10×10; phased-array radar on a ZAFAR truck; 200 targets tracked, claim; read 2026-11-19).
[^w-3kh]: Wikipedia, "3rd Khordad", https://en.wikipedia.org/wiki/3rd_Khordad (battery one TELAR + two TELs; battalion four batteries, a Bashir radar and a C2 unit; 4 targets, 2 missiles each per TELAR; struck June 2025 and 28 February 2026; read 2026-11-19).
[^w-zsu]: Wikipedia, "ZSU-23-4 Shilka", https://en.wikipedia.org/wiki/ZSU-23-4_Shilka (the radar's ground clutter under 60 m; read 2026-11-21).
[^w-tor]: Wikipedia, "Tor missile system", https://en.wikipedia.org/wiki/Tor_missile_system (GM-355 / GM-5955 tracked chassis; 7.5 × 3.3 × 5.1 m; search radar on top, PESA tracker at the front, both pulse-Doppler (read 2026-11-21), optical tracker; eight missiles upright in two groups of four; battery of four with a Ranzhir-M CP; tracks on the move, fires at a halt; M1 two targets; 48 detected, 10 tracked; Iran 29, Dezful upgrade; read 2026-11-19).
[^mis-tor]: Missilery.info, "Anti-aircraft missile system 9K331 Tor-M1", https://en.missilery.info/node/1028 (secondary; cites a BGTU Voenmekh textbook and Tekhnika i vooruzheniya: the combat vehicle's equipment, 9T244 / 9T245, Ranzhir 9S737, wheeled M1TA / M1TB, the engagement sequence, about 4 s between launches, 25 min to load two modules, the 10 min on / 10 min off cycle and the hour's break after three engagements, crew 3; read 2026-11-19).
[^fas-zsu]: Federation of American Scientists, "ZSU-23-4 Shilka", updated 22 January 1999, https://man.fas.org/dod-101/sys/land/row/zsu-23-4.htm (crew; radar and optical sights; bursts; basic load; platoon of four with four SA-9s; deployment distances; read 2026-11-19).
[^w-iriadf]: Wikipedia, "Islamic Republic of Iran Air Defense Force", https://en.wikipedia.org/wiki/Islamic_Republic_of_Iran_Air_Defense_Force (radars, guns and missile systems named; several entries marked "citation needed"; read 2026-11-19).
[^fg-mig29-gh]: Mercenary-Mercury, "MiG-29_9-12" (FlightGear), commit d4a299bf88412f579b2067874989a8088b2f6d66, https://github.com/Mercenary-Mercury/MiG-29_9-12 (`ReadMeEng.txt`: authors and "GNU General Public License version 3"; `MiG-29.xml`: "Aeromatic v 0.91", 2010-12-21, its inputs and outputs, the fuel tanks in its comments; `Engines/RD-33.xml`; read 2026-11-19).
[^w-mig29]: Wikipedia, "Mikoyan MiG-29", specifications, https://en.wikipedia.org/wiki/Mikoyan_MiG-29 (size, masses, fuel, RD-33 49.42 / 81.58 kN, performance, +9 g; credited to Mikoyan, Airforce Technology, Deagel and Business World; read 2026-11-19).
[^w-rd33]: Wikipedia, "Klimov RD-33", specifications, https://en.wikipedia.org/wiki/Klimov_RD-33 (50.0 / 81.3 kN; 75 / 188.1 kg/(kN·h); bypass 0.49; 1,055 kg; credited to Janes Aero Engines and Klimov; read 2026-11-19).
[^wt-forum]: War Thunder forum, "Mikoyan-Gurevich MiG-29 Fulcrum - History, Design, Performance & Dissection", https://forum.warthunder.com/t/mikoyan-gurevich-mig-29-fulcrum-history-design-performance-dissection-part-1/28118 (second-hand: posts quoting MiG-29 manuals, as quoted by a search engine on 2026-11-19; a game forum, so a lead to check, not data).
[^ni-f16]: The National Interest, "Russia vs. America: What If an F-16 Battled a MiG-29 Fighter?", https://nationalinterest.org/node/70521 (second-hand: quotes David Sarvai's "Schlemming with the Fulcrum" in Code One on JG 73's May 1995 deployment to Decimomannu, as quoted by a search engine on 2026-11-19).
[^rand-lambeth]: Benjamin S. Lambeth, "From Farnborough to Kubinka: An American MiG-29 Experience", RAND R-4000-RC, 1991, https://www.rand.org/pubs/reports/R4000.html (free PDF; first flight of a US citizen in a MiG-29, Kubinka, 15 December 1989; read 2026-11-19: the abstract and front matter only).
[^ed-cfd]: Eagle Dynamics, "MiG-29 CFD Case Study", https://www.digitalcombatsimulator.com/upload/medialibrary/2e0/MiG-29%20CFD%20Case%20Study%20EN.pdf (second-hand: a search engine's summary says it compares CL, CD and Cm at landing configuration with the graphs of "Practical Aerodynamics of MiG-29"; the PDF is an image without text; read 2026-11-19).
[^avid-pa]: avidreaders.ru, "Практическая аэродинамика самолета МиГ-29. Учебное пособие", https://avidreaders.ru/book/prakticheskaya-aerodinamika-samoleta-mig-29-uchebnoe.html (second-hand: the textbook's catalogue entry, as quoted by a search engine on 2026-11-19; authors open).
[^schiffer]: Schiffer Publishing, "MiG-29 Flight Manual: Unclassified", https://schifferbooks.com/products/mig-29-flight-manual (second-hand: as quoted by a search engine on 2026-11-19; contents open).
[^zaretto]: Richard Harrison, Zaretto, "F-14 Aerodynamic data sources", https://zaretto.com/node/30 (AFWAL-TR-80-3141 Parts I and III; NASA TN D-6909; NASA-TM-101717; NASA TM X-3106; NASA CR-134996; read 2026-11-19).
[^fg-f14wiki]: FlightGear wiki, "Grumman F-14 Tomcat", https://wiki.flightgear.org/F-14, and the FGAddon change log naming NASA TM-X-62306 (second-hand: as quoted by a search engine on 2026-11-19).
[^dm-tehran]: Defense Mirror, "Iranian MiG-29A, Yak-130 Jets Seen over Tehran Engaging Israeli, U.S. Missiles, Drones", 3 March 2026, https://defensemirror.com/news/41238 (from the "Russian Arms" Telegram channel; the role is experts' assessment; read 2026-11-19).
[^shaw]: Robert L. Shaw, "Fighter Combat: Tactics and Maneuvering", Naval Institute Press, Annapolis, 1985 (book; not read for this page).
[^sf-api]: Sketchfab, public search API, downloadable models with the licence filters "by" and "cc0", queries for the S-300 family, its radars, Tor, ZSU-23-4, MiG-29, F-14, ZU-23 and 35 mm guns, read 2026-11-19: https://api.sketchfab.com/v3/search?type=models&downloadable=true (and `/v3/models/<uid>` for each candidate's description and tags).
[^sf-5p85]: Sketchfab, xFORTUNAx, "S-300 5P85 Launcher with 9M83 Missiles", https://sketchfab.com/3d-models/none-da2204450fda471a949e4100e62e14a4.
[^sf-s400]: Sketchfab, xFORTUNAx, "S-400 Launcher on MAZ-543 with 5V55R Missiles", https://sketchfab.com/3d-models/none-a174bb760614407c8af1e614cecf7457.
[^sf-s1-s300]: Sketchfab, S1Priv, "Lowpoly S300", https://sketchfab.com/3d-models/none-db81bd95b7a14ecf8e0be4e605681a7f.
[^sf-30n6]: Sketchfab, aardque, "30N6E 'Flap Lid' B Phased Array Radar", https://sketchfab.com/3d-models/none-12d2dea1efbf4296891e512b16c57880.
[^sf-tor-xf]: Sketchfab, xFORTUNAx, "Tor-M1 SAM with 9M331 Missiles (Animated)", https://sketchfab.com/3d-models/none-4cc7af0120ac460b96aabd5135f63b70.
[^sf-tor-ur]: Sketchfab, urastyzh, "TOR-M1", https://sketchfab.com/3d-models/none-f1090c1b461048e98238d1b9aa86f359.
[^sf-zsu]: Sketchfab, S1Priv, "Lowpoly Zsu-23-4", https://sketchfab.com/3d-models/none-53bea8003bfc4a80b429d4f1f5d9206c.
[^sf-zsu-sc]: Sketchfab, scout., "ZSU-23-4 | High-Quality model", https://sketchfab.com/3d-models/none-e15b2ad28ad34a61a1a7ae071e90d1d1.
[^oprf]: l0k1, "oprf_assets", https://github.com/l0k1/oprf_assets (no licence file, last push 21 October 2026; `S-300/S-300-set.xml` header GPL-3.0-or-later © 2015 onox, authors "pinto, Nikolai V. Chr., onox"; folders S-300, ZSU-23, gci-radar; read 2026-11-19).
