# Night-vision goggles and night aids — research

This page records what public sources say about how the Israeli Air Force's fighter pilots see at night: the
goggles, the helmet's night camera, the goggle-compatible lighting and the procedure. It covers the F-16I Sufa, the
F-16D Barak and the F-35I Adir, and briefly the F-15I Ra'am. It ends with what Modern IAF has today and the options
to build. It is research only: it changes no code or data, and it decides nothing. The user asked for it on
19 November 2026: "do we need a research for nvg? what and how it used in IAF?", then "do it now while other works
and wait for the response to comeback and then we decide what to build and how". Research date: 19 November 2026.

**Terms**
- **NVG:** night-vision goggles, two image-intensifier tubes on a mount at the front of the helmet.
- **NVIS:** night vision imaging system; "NVIS-compatible" lighting is cockpit or exterior lighting whose light the
  goggles do not see, or see only faintly.
- **HMD:** helmet-mounted display. JHMCS is the US F-15 / F-16 helmet sight; DASH is Elbit's Israeli helmet sight,
  from which JHMCS was derived; the Gen III HMDS is the F-35's helmet.
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning; "open" means no source
  was found. **Second-hand** marks a fact taken from a search engine's quote of a page that refused automated access
  or was not opened. **Secondary** marks a trade page, vendor sheet, simulator community page or forum: it shows the
  general (mostly US) practice, not the IAF's own.

Scope: what the pilot wears, sees and switches. Real missile performance, countermeasure effectiveness and electronic
attack are out of scope (the project's parked rows, [../avionics-plan.md](../avionics-plan.md) §7).

## 1. The answer first, per jet

| jet | night aid on the pilot's head | the helmet sight at night | lighting | grade |
|---|---|---|---|---|
| F-16I Sufa | goggles: the cockpit and exterior lighting suit them[^aft-sufa][^du-sufa]; the goggle model is open | DASH IV in both seats[^du-sufa]; how DASH IV works with goggles is open | NVG-compatible cockpit lighting and exterior strip lighting[^aft-sufa]; all cockpit lighting, the colour displays included, works with night vision systems[^du-sufa] | lighting: secondary (trade pages); goggles worn: inferred from the lighting |
| F-16D Barak | open: no source names goggles on the Barak | a helmet with an eyepiece (עינית) that shows data and steers the jet's systems by the pilot's look[^jdn-barak]; its maker and its use at night open | open: the USAF made its F-16 fleet NVIS-compatible from 1996[^f16nvg][^f16net-nvis]; whether the IAF's Baraks had the same change is open | open |
| F-35I Adir | no goggles: the helmet's own night camera, or the DAS's infrared video, on the visor[^afi35][^ain-gen3] | the Gen III HMDS (the Adir's helmet a variant for its Israeli systems[^caspian]) | open (the jet is lit for the helmet camera; inferred) | primary for the F-35 in general (a USAF instruction); the Adir's own use second-hand |
| F-15I Ra'am | goggles, with cockpit lighting designed not to obstruct them[^baugher-f15i][^f15i-gs] | DASH, both seats[^baugher-f15i] | goggle-compatible cockpit[^baugher-f15i] | secondary |

In plain words: the Sufa and the Ra'am were built with goggle-compatible lighting, so their crews fly with goggles at
night; no public source names the goggle or says how the DASH IV's symbols reach the pilot's eye through it. The Adir's
pilot wears no goggles: the helmet itself shows a night camera's picture or the DAS's infrared picture. For the Barak,
nothing public was found.

## 2. The systems

### 2.1 Goggles in the IAF

- **The "Zhurnal" (its Hebrew spelling open).** The IAF's magazine describes the goggle of the helicopter
  squadrons, the Zhurnal, in front of the helmet's visor with its battery on the helmet's back, in service since the
  early 1980s[^zhurnal]. An IDF English page of a helicopter squadron's night training week calls it the "Journal", a
  device on the helmet that brightens the light of the stars (second-hand: the page did not load)[^idf-dark]. Its
  maker and model are open; whether the fighter squadrons use the same goggle is open.
- **The tubes.** Elbit, an Israeli firm, makes image intensifiers and goggles[^jns-elbit]; that the IAF's fighter
  goggles are Elbit's is open.
- **The likely type** (inferred): the jets were built to US NVIS standards for the US goggles of their time, so a
  binocular aviator goggle of the ANVIS / AN/AVS-9 class (40° round view, Gen III tubes) is the likely type. The
  US Air Force's and Navy's standard aviator goggle is the F4949, an AN/AVS-9[^ads-f4949].

### 2.2 The helmet sight with goggles (F-16, F-15)

- The first JHMCS cannot be worn with goggles: at night the pilot either flies without goggles or swaps the JHMCS
  visor for goggles, so he has the helmet display or the goggles, never both[^twz-dep][^dii-jhmcs].
- Elbit and Rockwell Collins built add-ons that put the helmet's symbols into the goggles: the Digital Eye Piece
  (2014; it projects the JHMCS symbols in front of the right tube)[^aaf-dep][^twz-dep] and the Night Insert (20° × 20°
  colour symbols, under 55 g added, for AN/AVS-6 and AN/AVS-9 goggles, JHMCS, JHMCS II and Targo)[^elbit-ni]. JHMCS II
  has a night module on modified F4949 goggles that the pilot fits with one hand in flight without taking the helmet
  off (secondary)[^dii-jhmcs].
- **The Digital Eyepiece, the known way to have both** (added 19 November 2026; the sim keeps option O3, §7). The DEP
  is a clip-on add-on that overlays the helmet's targeting cues in the goggles[^dvids-dep], in front of the right
  eye[^twz-dep]. Rockwell Collins ESA Vision Systems (RCEVS), the joint venture of Rockwell Collins and Elbit Systems
  of America, introduced it in September 2016 (second-hand)[^mae-dep]. The 114th Fighter Wing (South Dakota Air
  National Guard, Block 40 F-16s) tested it on 4–19 January 2018[^dvids-dep][^twz-dep]. Whether the IAF uses it, or
  anything like it with the DASH, is open.
- **DASH IV in the Sufa: open.** No source says whether the Sufa's crews take the DASH IV's visor display off at night,
  wear goggles over it, or use an Elbit night add-on. JHMCS was derived from DASH III[^dii-jhmcs], so the same limit
  (display or goggles) is the likely case (inferred).

### 2.3 The F-35I's helmet

- The F-35's helmet replaces goggles: with the helmet the pilot picks the DAS's 360° infrared video or the
  near-infrared night vision camera[^afi35]. The camera (ISIE-10, then ISIE-11 in the Gen III helmet) brings the
  helmet's night acuity close to the 20/20 of goggles; a test pilot picks the DAS when he wants infrared and the
  helmet camera when he wants amplified light; the canopy bow blocks part of the camera's view, as the camera sits
  above the eyes[^ain-gen3][^f35]. The alternative goggle helmet was dropped in 2013[^f35alt].
- The Adir's helmet is a variant made for its Israeli systems (secondary)[^caspian]. At the Adir's first night
  sortie in January 2017 the squadron said it was learning how the jet's night systems fit its flying; the DAS shows a
  360° picture in the helmet, and night flying is "almost identical to a day flight"[^dt-adir-night].
- Helmet weight and ejection: the US Air Force's lighter Gen III helmet, with quick-change clear and dark visors
  instead of an outer visor, and a slower-opening seat with a head support panel lower the ejection risk; seat and
  helmet together weigh under 136 lb (May 2017)[^d1-helmet].

## 3. Procedure

Every row is the US practice; the IAF's own procedure is open.

| phase | what the pilot does | grade |
|---|---|---|
| Before flight | an NVG preflight is its own paragraph of the USAF's F-16 procedures (AFMAN 11-2F-16 Vol 3, 16 April 2026, §3.28.1) | second-hand (the manual refused automated access)[^afman-f16] |
| Take-off | goggles up or off; the pilot takes off unaided | second-hand[^afman-f16] |
| On the goggles | flipped down above about 2,000 ft AGL or the minimum safe altitude, whichever is higher (a US command's supplement) | second-hand[^afman-f16] |
| In use | the pilot looks under the tubes to read the cockpit with the naked eye, then back through them; he scans by moving his head, as the view is 40° | secondary[^migflug] |
| Off the goggles | before landing (an airlift wing's rule: 5 min before an unaided landing) | second-hand[^afman-f16][^ang-nvg] |
| Ejection | the goggles add weight on the neck; mounts have breakaway or quick-release couplings, some fired by the seat's first movement, others by hand[^pat-release][^pat-seat]; the risk of neck injury rises above 450 KEAS and for light pilots, but goggles do not raise the risk of major injury when the flight manual's ejection procedure is followed | the DoD inspector general's finding second-hand[^dodig] |

**The cockpit and exterior lighting.**
- One cockpit light that does not suit the goggles is enough to degrade their picture[^dtic].
- **NVIS green.** The US standard for goggle-compatible aircraft lighting, MIL-STD-3009 (2 February 2001, after
  MIL-L-85762A), sets NVIS Green A for the primary lighting (instruments, displays, consoles), the secondary (flood)
  lighting, illuminated controls and caution and advisory signals: within 0.037 of u' 0.088, v' 0.543 on the CIE 1976
  UCS diagram. NVIS Green B (u' 0.131, v' 0.623, radius 0.057) is for parts that need a more saturated colour; warning
  signals and the master caution are NVIS Yellow (u' 0.274, v' 0.622)[^ms3009]. A short video of a night F-16 cockpit
  with its goggle-compatible lighting on shows the panel's edge lighting, the consoles and the floodlights all
  green-blue (second-hand: only its thumbnail was seen; the air force is not named)[^gdp-video].
- The USAF's F-16 NVIS change replaced the white cockpit lighting with NVIS green, replaced a couple of switches on the
  lighting panels, and replaced the position and formation lights (wingtips, intakes, belly, fin, upper fuselage) and
  the tail flood with goggle-compatible ones[^f16net-nvis][^f16nvg].
- Formation lights on modern jets have a visible and a covert (infrared, seen only through goggles) mode; on the AV-8B
  the exterior lights master switch has NORM and NVG positions; the F-16 Block 50 / 52 panel has a covert selection
  whose exact positions are open (secondary)[^bms-ext][^collins-covert].
- Our F-16 cockpit model already has a lighting panel with an NVIS / NORMAL switch and an exterior lights panel with
  FORM strips ([../cockpit.md](../cockpit.md) §5.5); the switch's effect there is inferred.

## 4. What the pilot sees

| item | goggles (F-16, F-15) | the F-35's helmet camera |
|---|---|---|
| Field of view | 40° round[^ads-f4949][^rash] | open |
| Colour | green (P43, the US military standard)[^phosphor]; some newer goggles white phosphor (secondary)[^migflug] | open |
| Grain | grows as the light falls; sparkles in the dark[^rash] | open |
| Halo and bloom | halos around lights; a town or a burning target can bloom and wash out the picture[^rash][^migflug] | open |
| Acuity | about 20/20 at best (late Gen III)[^f35] | close to 20/20 with ISIE-11[^f35] |
| Weight | on the front of the helmet: one vendor's AN/AVS-9-class binocular 500 g, its mount 150 g (secondary)[^agm-a9] | built into the helmet; the helmet's own weight open (seat and helmet under 136 lb)[^d1-helmet] |
| Other limits | less depth perception; less reliable in high humidity or thick cloud[^sp-nvg] | the canopy bow in the camera's view[^ain-gen3] |

**Two tubes, one circle** (added 19 November 2026). Aviation goggles of the ANVIS class (AN/AVS-9, F4949) are
binocular: one image-intensifier tube for each eye. The two tubes are parallel[^tnvc-wfov] and aligned so that both
show the same picture: their 40° fields overlap 100%, and the pilot sees one 40° circle.
- A binocular night-vision device must line up its two tubes' images exactly; the AN/AVS-9 is aligned by turning its
  eyepieces[^itt-collim]. With the tubes set to the wearer's eyes, the two images merge into a single sharp
  image[^lumi-ipd].
- A night-vision goggle's field is 40° with one tube or with two. A "double" image, overlapping in the middle, comes
  from goggles whose tubes are angled outward; four-tube panoramic goggles such as the AN/AVS-10 widen the view to
  about 100°[^tnvc-wfov].
- The tubes' spacing follows the pilot's eye spacing: each tube adjusts on its own, together 51–72 mm (the F4949;
  second-hand)[^f4949-ipd].

## 5. Hebrew terms

Found in Israeli use; none coined here.

| English | Hebrew | where found |
|---|---|---|
| night vision device | אמצעי ראיית לילה, short אמר"ל | Hamichlol's article[^michlol] |
| image intensifier | מגבר אור כוכבים, short מא"כ | Hamichlol's article[^michlol] |
| goggles / binoculars | משקפת (plural משקפות) ראיית לילה | Hamichlol's article[^michlol] |
| the helmet display's eyepiece | עינית | the IAF site on the Barak's helmet[^jdn-barak] |
| the F-35I's night camera | מצלמת לילה | already used in Modern IAF's strings |

Open: the term the fighter squadrons use for their goggles in speech (משקפות, אמר"ל or a model name).

## 6. What the sim has today

- **The 1998 game** ([../../../docs/rendering.md](../../../docs/rendering.md) §8): Preferences → Graphics → MORE →
  Night vision = Goggles, then Shift + N in flight puts the goggles on and off (`terrain_view.gd` `_toggle_goggles`).
  A full-screen shader over the 3D view and under the cockpit: the tube's spectrum, automatic gain, blur, halos,
  grain, the P43 green and a 40° vignette; the tube by the mission's year; cockpit glare where the jet's lighting does
  not suit the goggles (`goggles_lit`); the HUD in its brightest green while they are on.
- **Modern IAF** (until 19 November 2026): Shift + N did nothing, because it needs `Settings.night_vision` and Modern
  IAF has no Preferences row for it. Since then the Sufa and the Barak have goggles on a key-table record of their own
  (O1–O4 below). As built first, the tubes' picture filled the whole screen, the 3D cockpit too; since the user's "fix"
  of the same day it fills a round field 40° across (§4) on the head's forward line, in the view's upper part, and the
  pilot sees the panel below it with the naked eye (§3, "In use"; [../cockpit.md](../cockpit.md) §5.5,
  [../../../docs/rendering.md](../../../docs/rendering.md) §8).
- **The F-35I** in Modern IAF: Alt + F7 steps the helmet's night camera, the DAS's video and off
  (`_helmet_video_step`, record 254; [../avionics-plan.md](../avionics-plan.md) P9). The night camera uses the same
  shader as the late Gen III tube; the DAS video the shader in grey. The DAS format's picture costs 1.83 ms GPU a frame
  on the Iris Xe while drawn ([../../../docs/rendering.md](../../../docs/rendering.md) §8.1).
- **The F-16s**: the lighting panel's NVIS / NORMAL switch and the exterior lights panel work
  ([../cockpit.md](../cockpit.md) §5.5); since 19 November 2026 the NVIS switch also sets the goggles' glare (§7), and
  at NVIS lights the cockpit's flood and backlit labels NVIS Green A (§3), shown as its hue at an sRGB screen's edge.

## 7. Options to build

The user's pick, 19 November 2026 (Approvals A66): "night googles: as suggested". Built the same day
([../cockpit.md](../cockpit.md) §5.5): O1 (the Sufa and the Barak, Shift + N, record 255), O2 (the NVIS / NORMAL
switch sets the glare), O3 (the helmet display's symbols off while the goggles are down, the JHMCS rule) and O4 as flip
down / up on the same key with no minimum height. O7: the Adir keeps its helmet's night camera and gets no goggles.
Not started: O5 (later, with the AI wingmen), O6 and O8.

The user's "fix", 19 November 2026 (the goggles' picture covered the whole screen, the 3D cockpit included): built the
same day. The picture is a round field 40° across, fixed to the head in the upper part of the view; the cockpit below
it keeps its own night lighting, and where the field overlaps the panel the panel shows through the tubes, with the
NVIS / NORMAL glare. The shader's gain, halos, grain and P43 green are unchanged; the 1998 game's goggles and the
Adir's helmet are unchanged. At NVIS the F-16s' cockpit is lit NVIS green (§3). O3 stays as built (the user, 19
November 2026: "no keep as is"): the helmet's symbols are off while the goggles are down; the Digital Eyepiece (§2.2)
is the known alternative.

As built, the user's "binoculars, not mono" (19 November 2026): the sim draws one 40° circle, as the binocular
goggles' fully overlapping tubes show it (§4, "Two tubes, one circle") and as the user chose the same day ("Keep one
circle").

| # | jet | option | what it needs |
|---|---|---|---|
| O1 | Sufa, Barak, Ra'am | goggles on a key: the existing shader, a late Gen III tube, always available (no Preferences row) | a key-table record for Shift + N (or another key) in the sim, `Settings.night_vision` true in `sim_settings.gd`, the controls doc and both manuals' key lists; the Barak's goggles stay "open" |
| O2 | Sufa, Barak, Ra'am | the cockpit's NVIS switch matters: in NORMAL the panel glares through the goggles, in NVIS it does not | `goggles_lit` reading the NVIS / NORMAL switch for the F-16s instead of the year; a Rust rule if it is to be a check |
| O3 | Sufa, Ra'am | the helmet sight at night: DASH IV's symbols off while the goggles are on (the JHMCS rule), or kept as through a Night Insert | a decision on which (both are inferred for the IAF); the helmet draw in `real_hud/dash.rs` gated by the goggles' state |
| O4 | all F-16s | the procedure: goggles refused below 2,000 ft AGL, or a Betty / notice line; flip up / down as a separate state from off | a rule in Rust (the altitude gate), the state on the HUD; the training's instructor lines |
| O5 | all F-16s | the exterior lights' covert mode: FORM in covert seen only with goggles on | the panel's covert position (its exact positions open), the lights drawn only under the goggles' shader |
| O6 | Sufa, Barak | white phosphor instead of green | one shader colour (the `tint` parameter); a source for the IAF's own tubes is open |
| O7 | Adir | nothing new in the helmet: it already has the night camera and the DAS video; options are the camera's own look (latency, the canopy bow's shadow) and the grain | a source for the look, else "inferred"; GPU budget on the Iris Xe |
| O8 | all | ejection with goggles on | the ejection's outcome by speed (above 450 KEAS) and goggles; a Rust rule beside the jets' limits |

## 8. Open points

- The IAF fighter squadrons' goggle: maker, model, generation, green or white phosphor.
- When IAF fighter pilots began flying with goggles; whether the Barak has goggle-compatible lighting.
- How the Sufa's and the Ra'am's DASH works at night (visor display off, goggles over it, or an Elbit night add-on).
- The IAF's own procedure: when goggles go on and off, the altitude limits, the ejection rule.
- The F-16 Block 52's exterior lights panel: its covert positions.
- The F-35 helmet camera's picture: colour, field of view, latency.
- The spoken Hebrew term in the fighter squadrons.

[^aft-sufa]: Secondary. Airforce Technology, "F-16I Soufa" (cockpit lighting and external strip lighting compatible with night
    vision goggles; the DASH IV; the LANTIRN navigation pod): https://www.airforce-technology.com/projects/f-16i-soufa/
[^du-sufa]: Secondary. Defense Update, "Israel Air Force F-16I Soufa" (DASH IV in both seats; all cockpit lighting,
    the colour displays included, designed to work with night vision systems; seen as a search summary):
    https://defense-update.com/?p=11422
[^jdn-barak]: JDN, from the IAF site, S. Stern, "a look at the helmet of the Barak (F-16C/D)", 15 December 2024 (a
    101 Squadron pilot; the helmet's eyepiece, עינית; no night use mentioned): https://www.jdn.co.il/news/2319133/
[^f16nvg]: Flight International, 24 January 1996, "NVG modifications begin on F-16s":
    https://flightglobal.com/nvg-modifications-begin-on-f-16s/11115.article
[^f16net-nvis]: Second-hand. F-16.net news, the NVIS modification of the Block 40 F-16s at Aviano (1998; cockpit:
    white lighting to NVIS green and a couple of switches replaced; exterior: position, formation and tail flood
    lights; the page returned an error, as the search engine quoted it): https://www.f-16.net/f-16-news-article383.html
[^afi35]: AFI 11-2F-35A Volume 3, "F-35A Operations Procedures", 7 June 2012, §3.19.1.1 (with the helmet the pilot
    picks the DAS's 360-degree infrared video or the near-infrared night vision camera); its cover: no releasability
    restrictions. As cited in [../avionics-plan.md](../avionics-plan.md).
[^ain-gen3]: Second-hand. AIN, "F-35 test pilots will begin flying Gen III helmet display", 8 February 2014 (ISIE-11;
    a test pilot's choice of DAS or helmet camera; the canopy bow): https://backend.ainonline.com/aviation-news/defense/2014-02-08/f-35-test-pilots-will-begin-flying-gen-helmet-display
[^f35]: AIN, "F-35 pilots will begin flying improved Gen 3 helmet", 21 January 2014 (ISIE-10 / ISIE-11, acuity, tested
    against ANVIS-9): https://backend.ainonline.com/aviation-news/2014-01-21/f-35-pilots-will-begin-flying-improved-gen-3-helmet
[^f35alt]: Military.com, "Pentagon scraps alternative F-35 helmet", 10 October 2013:
    https://www.military.com/defensetech/2013/10/10/pentagon-scraps-alternative-f-35-helmet?amp
[^caspian]: Secondary. Caspian Post, "Israeli F-35I helmet lets pilots see through aircraft" (a helmet variant for
    the F-35I's Israeli systems; two projectors; after The National Interest; year not shown):
    https://caspianpost.com/regions/israeli-f-35i-helmet-lets-pilots-see-through-aircraft
[^dt-adir-night]: Defence Talk, "Israeli Air Force flies first F-35 night sortie", 18 January 2017:
    https://defencetalk.com/israeli-air-force-flies-first-f-35-night-sortie-68832
[^d1-helmet]: Defense One, "Air Force tests new lightweight F-35 helmet", 18 May 2017 (the Gen III Light Helmet,
    quick-change visors, the seat's slower parachute and head support panel; seat and helmet under 136 lb):
    https://www.defenseone.com/defense-systems/2017/05/air-force-tests-new-lightweight-f-35-helmet/189655/
[^baugher-f15i]: Secondary. Joe Baugher, "F-15I for Israel" (the pilot can use night vision goggles; the cockpit lighting designed
    not to obstruct them; DASH; LANTIRN): https://www.joebaugher.com/usaf_fighters/f15_22.html
[^f15i-gs]: Second-hand. GlobalSecurity, "F-15I Ra'am" (night-vision-goggle compatible cockpits; seen as a search
    snippet): https://www.globalsecurity.org/military/world/israel/f-15i.htm
[^zhurnal]: IAF magazine (בטאון חיל האוויר) 125, 1 February 1999 (the Zhurnal in the helicopter squadrons since the
    early 1980s; as cited in docs/rendering.md §8.2): https://www.iaf.org.il/244-18482-he/IAF.aspx
[^idf-dark]: Second-hand. IDF, "Who's afraid of the dark? Not us" (a helicopter squadron's night week; the "Journal";
    the page did not load, as the search engine quoted it):
    https://m.www.idf.il/en/mini-sites/israeli-air-force/who-s-afraid-of-the-dark-not-us
[^jns-elbit]: JNS, "Israel's Elbit Systems supplies advanced night vision tech to US Army":
    https://www.jns.org/israels-elbit-systems-supplies-advanced-night-vision-tech-to-us-army/
[^ads-f4949]: Secondary (vendor). ADS, "System F4949" datasheet (the standard night flying system of US Air Force and
    Navy aircrews; 40° view): https://www.advanceddefense.com/hubfs/ADS-Marketing-Datasheet-System-F4949.pdf
[^agm-a9]: Secondary (vendor). AGM, "Apache A-9 aviator night vision goggle system" datasheet (binocular 500 g, mount
    150 g): https://www.agmglobalvision.com/image/catalog/product-pdf-doc/1607952403_AGM_APACHE_A-9_Datasheet_v3.pdf
[^twz-dep]: The War Zone, T. Rogoway, "New 'Digital Eye Piece' will allow U.S. fighter pilots to own the night like
    never before", 8 February 2018 (JHMCS or goggles, not both; the DEP):
    https://www.twz.com/18358/new-digital-eyepiece-will-allow-u-s-fighter-pilots-to-own-the-night-like-never-before
[^dii-jhmcs]: Secondary. Defense Industry Daily, "JHMCS: fighter pilots' 'look & shoot' helmets" (JHMCS derived from
    DASH III; the first JHMCS not goggle-compatible; JHMCS II's night module on modified F4949 goggles; seen as a
    search summary): https://www.defenseindustrydaily.com/?p=1271
[^aaf-dep]: Air & Space Forces Magazine, "Fighter helmet for the dark side", 15 October 2014:
    https://www.airandspaceforces.com/fighter-helmet-for-the-dark-side
[^elbit-ni]: Elbit Systems, "Night Insert" product page: https://elbitsystems.com/product/night-insert
[^afman-f16]: Second-hand. AFMAN 11-2F-16 Volume 3, 16 April 2026 (§3.28 NVG procedures, §3.28.1 NVG preflight; the
    2,000 ft AGL / MSA minimum is a command supplement's, quoted in a DCS forum post; the manual and the forum refused
    automated access): https://static.e-publishing.af.mil/production/1/af_a3/publication/afman11-2f-16v3/afman11-2f-16v3.pdf
    and https://forum.dcs.world/topic/60190-advice-on-using-night-vision-goggles
[^ang-nvg]: Second-hand. Minnesota ANG, "Pilot NVG AL study guide / briefing aid", 30 November 2006 (an airlift wing's
    rule: goggles off 5 min before an unaided landing):
    https://www.baseops.net/wp-content/uploads/2015/08/MN_ANG_NVGAL_StudyGuide_30Nov06.doc
[^migflug]: Secondary. M. Grünwald, "Night vision goggles: how pilots fly in the dark", MiGFlug Afterburner,
    28 September 2026: https://migflug.com/afterburner/night-vision-goggles-nvg-how-fighter-pilots-fly-at-night-anvis/
[^pat-release]: US patent 5,542,627, "Quick release coupling apparatus and method for a helmet mounted night vision
    goggle arrangement" (released by the ejection handle's switch, a harness pressure switch or the seat rail):
    https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5542627
[^pat-seat]: US patent 5,367,402, "Helmet mounted night vision apparatus and method of separation" (the goggles' weight
    on the neck; a seat microswitch fires the release): https://patents.google.com/patent/US5367402
[^dodig]: Second-hand. DoD Inspector General, "Evaluation of aircraft ejection seat safety when using advanced helmet
    sensors" (the page refused automated access):
    https://www.dodig.mil/reports.html/Article/1119133/evaluation-of-aircraft-ejection-seat-safety-when-using-advanced-helmet-sensors/
[^dtic]: DTIC ADA517298 (one incompatible cockpit light degrades the goggles' picture):
    https://apps.dtic.mil/sti/pdfs/ADA517298.pdf
[^bms-ext]: Secondary. Falcon BMS forum, "question ext. lighting control panel" (the Block 50 panel's "covert ALL",
    after GR1F-16CJ-1; seen as a search summary): https://forum.falcon-bms.com/post/352086
[^ms3009]: MIL-STD-3009, "Lighting, aircraft, night vision imaging system (NVIS) compatible", 2 February 2001, §4.3.4
    and Table II (distribution A; a copy hosted by a vendor): https://cdn.shopify.com/s/files/1/1942/0217/files/MIL-STD-3009.pdf
[^gdp-video]: Second-hand, unidentified. "General Duty Pilots", a YouTube short of a night F-16 cockpit (only its
    thumbnail was seen; the air force is not named): https://www.youtube.com/shorts/Nay4MM76IVo
[^dvids-dep]: DVIDS, L. Olson (114th Fighter Wing), "Digital eyepiece increases capabilities of F-16 pilots",
    26 January 2018 (a clip-on device; tested 4–19 January; the wing's own copy refused automated access):
    https://www.dvidshub.net/news/263376/digital-eyepiece-increases-capabilities-f-16-pilots
[^mae-dep]: Second-hand. Military & Aerospace Electronics, "Digital eye piece enhances situational awareness for F-16
    pilots" (RCEVS introduced the JHMCS DEP in September 2016; seen as a search engine's summary, not opened):
    https://www.militaryaerospace.com/commercial-aerospace/article/14229040/digital-eye-piece-enhances-situational-awareness-for-f16-pilots
[^collins-covert]: Collins Aerospace, "Dual mode covert lights": https://www.rtx.com/collinsaerospace/what-we-do/industries/military-and-defense/exteriors/exterior-lighting/dual-mode-covert-lights
[^rash]: C. E. Rash, "A 25-year retrospective on NVGs", Flight Safety Foundation AeroSafety World, August 2010 (40°
    round view, gain control, sparkles at low light, halos): https://flightsafety.org/wp-content/uploads/2016/11/asw_aug10_p14-18.pdf
[^phosphor]: Night Vision International wiki, "Phosphor Screen" (P43 the US military standard):
    https://nv-intl.com/index.php/Phosphor_Screen
[^sp-nvg]: StrategyPage, "Warplanes", 6 March 2003 (less resolution, acuity, depth perception and view than daylight;
    humidity and cloud): https://www.strategypage.com/htmw/htairfo/articles/20030306.aspx
[^michlol]: Hamichlol, "אמצעי ראיית לילה":
    https://www.hamichlol.org.il/%D7%90%D7%9E%D7%A6%D7%A2%D7%99_%D7%A8%D7%90%D7%99%D7%99%D7%AA_%D7%9C%D7%99%D7%9C%D7%94
[^itt-collim]: US patent 6,687,053, "Binocular device and method utilizing monocular devices", ITT Manufacturing
    Enterprises, 3 February 2004 (a binocular night vision device needs its two intensified images collimated in
    image space; images that do not coincide hinder binocular fusion; the AN/AVS-9 collimated by rotating its
    eyepieces): https://patents.google.com/patent/US6687053
[^lumi-ipd]: US patent 11,914,135, "Interpupillary distance adjustment mechanism for binocular optical device",
    Lumiworx, 27 February 2024 (with the IPD correct the monoculars' images overlap to form a single sharp image):
    https://patents.google.com/patent/US11914135
[^tnvc-wfov]: Secondary (vendor). A. Kim, TNVC, "WFOV (wide field of view) night vision goggle overview", TNV21-07,
    17 July 2021 (the 40° field the same with one tube or two; conventional binoculars' tubes parallel; tubes angled
    outward give a "double" image overlapping in the centre; panoramic goggles such as the AN/AVS-10 about 95–104°
    wide with four tubes): https://tnvc.com/wp-content/uploads/2025/04/TNVC_WFOV_NVG_WHITE_PAPER_REV4_DU_20210717.pdf
[^f4949-ipd]: Second-hand. A reseller's F4949 (ANVIS-9) specification sheet (interpupillary distance: independent,
    51 to 72 mm; the page refused automated access, as the search engine quoted it):
    https://punisher.com.ua/en/prylad-nichnoho-bachennia-harris-anvis-9-f4949-series/
