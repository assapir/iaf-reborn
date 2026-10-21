# MiG cockpits: Better cockpit and Real HUD research

This page is the research for the two MiGs the player can fly from the Mission Creator: the MiG-23 (`mig23`, type 160)
and the MiG-29 (`mig29`, type 180). It covers:
* what each 1998 panel paints and what the original drives (§2, §3);
* what each painted instrument is in the real jet (§2, §3);
* which "Better cockpit" items apply, and the MiG-only items (§4);
* the real HUDs (§5, §6).

What ours draws: docs/cockpit.md "Gauges on their labelled dials" / "MiG gauges" (the panels) and docs/real-hud.md
"MiG-23ML" / "MiG-29 9.12" (the HUDs). The opt-in changes are in docs/deviations.md. Research date: 2026-10-20.

**Terms**
* **Panel px:** a point on the 1920-px panel strip, as in docs/cockpit.md. The converted art is 4× that.
* **Clock degrees:** 0 = 12 o'clock, clockwise.
* **Sources:** a footnote names the source of each outside fact. "Inferred" marks our own reasoning; "open" means no
  source was found. "(photo)" marks our reading of a cockpit photograph, not a document.
* **[SIM]:** a fact found only in a simulator manual. The DCS MiG-29A Early Access manual[^ea] says it was built from
  a museum aircraft, factory diagrams and the German flight manual. It describes the Luftwaffe / export cockpit,
  whose scales read knots and feet.

**Which real jets the game models:** the MiG-23ML and the MiG-29 9.12 (docs/real-aircraft.md §9.2, §9.4).

**Pictures** (local research captures, not in the repo because they hold the original art; panel crops at the full 4×
resolution):
* `mig/mig23_annotated.png` and `mig/mig29_annotated.png`: each panel with the numbered items of the tables below.
* `mig/mig23-z-*.png`, `mig/mig29-z-*.png`: zooms of each dial.
* `mig/lights_both.png`: the two lights bitmaps. `mig/huds.png`: the two HUD glass bitmaps.
* `mig/photo_08.png` and `mig/photo_010.png`: two dials from a real MiG-23 cockpit photo[^kiev].

## 1. Summary

* **Both panels are composites.** The MiG-23 panel is a real MiG-23 cockpit photograph with some instruments moved
  or left out. The MiG-29 panel puts real Soviet dials next to Western parts: two F-16-style MFDs, an F-4 nav-mode
  panel, a "LBS TOTAL INTERNAL" fuel gauge and English lamp legends.
* **The original draws most needles on the wrong dials.** It drives the MiG panels with the same records as the
  Western jets, in knots, feet and ft/min:
  * MiG-23: the airspeed needle is on the **Mach meter**, RPM is on the **fuel gauge (× 1000 l)**, fuel is on the
    **exhaust-temperature dial**, TEMP is on the **hydraulic pressure gauge** and THROTTLE is on the **wing-sweep
    indicator**.
  * MiG-29: the airspeed needle is on the **radar altimeter** and vertical speed is on the **AoA / g meter (UUA)**.
* **Neither panel paints a dial for some values.** The MiG-23 panel has no airspeed dial and no tachometer. The
  MiG-29 panel has no airspeed dial, no VVI (vertical speed indicator), no HSI (horizontal situation indicator), no EGT
  (exhaust gas temperature) dials and no RWR (radar warning receiver).
* **Built (2026-10-20; test `tests/godot/test_mig_cockpit.gd`):**
  * `dials_by_label` for both MiGs (`gauges.gd` `DIALS`): the MiG-23's Mach, EGT, litre and VVI needles on their
    faces, RPM / THROTTLE / the hydraulic needle off; the MiG-29's tachometer per engine, its airspeed and vertical
    speed off the radar altimeter and the UUA. The scales were measured again on the art; they differ from the first
    reading by up to 10°.
  * `turning_compass` on the MiG-23's ПНП; `fuel_total`, `smooth_needles`, `crisp_mfd`, `engine_rpm`, `engine_temp`
    as for the other jets.
  * The MiG-only items 4.1 `metric_gauges`, 4.2 `uua`, 4.3 `radar_alt` and 4.5 `rsbn_counter`.
  * The Real HUD for both: `Jet::MiG23` (`real_hud/mig23.rs`) and `Jet::MiG29` (`real_hud/mig29.rs`).
* **Open:** 4.4 (SPO-15 lamps), 4.6 (the HSI bars, the hydraulic gauge), `panel_clock` on the MiG-23's # 13 (the art
  paints hands on that face, so they would need erasing).

## 2. MiG-23 panel (`mig23`)

### 2.1 What the art paints and what the original drives

The art matches the MiG-23 cockpit in the Commons photograph[^kiev] (`img/k_left.jpg`, `k_mid.jpg`, `k_right.jpg`):
the same dial faces, the КПП (ADI, attitude director indicator) over the ПНП (HSI), the 2 × 5 red lamp boards with
the ДЕНЬ / НОЧЬ (day / night) dimmer, the "000 КМ" counter, the wing-sweep indicator and the fuel gauge with its
orange hub. The art leaves out the photograph's airspeed dial (СКОРОСТЬ), AoA dial (УГОЛ АТАКИ), g-meter (УСКОРЕНИЕ),
radar altimeter and tachometer (ОБОРОТЫ RPM). In their places it paints the weapons selector, an MFD under the sight
and the SPO-15 indicator.

The numbers match the annotated picture (`mig/mig23_annotated.png`).

| # | Painted item (centre, panel px) | Real instrument | Original draws | Note |
|---|---|---|---|---|
| 1 | altimeter, 0–9 outer ring, inner ring (735,198) | ВДИ-30К two-needle barometric altimeter[^airwar-ml][^ub]: the long needle 1000 m per turn (inferred from the 0–9 face); the inner scale km | `ALTITUDELOCK`: 1000 ft per turn, the short needle 10,000 ft per turn | a metric face read in feet |
| 2 | dial numbered 0.6 … 3 clockwise from 1 o'clock (735,275) | the Mach meter, УСМ-1К[^airwar-ml] or the Mach half of a combined УСИМ[^ub]; the photo's dial below the altimeter has the same 1.2 … 2.8 numbers[^kiev] | `SPEEDCLOCK`: 1000 kt per turn | **the airspeed needle on a Mach face** |
| 3 | lens ADI with its bank ring and slip ball (824,133) | КПП: attitude with the flight director bars; the САУ-23АМ autopilot gives its director signals to the КПП and to the sight[^airwar-ml] | `LENHORIZON` (live) | the ball is grey over black (`adi.bmp`) |
| 4 | HSI: compass card, a vertical bar, a horizontal bar, flags К and Г (≈ 826,228) | ПНП: heading card, course (К) and glide-slope (Г) bars[^kiev] | static | `turning_compass` (built) |
| 5 | MFD under the sight (903,120 top-left) | the real ML has **no** radar scope here: the Sapfir-23ML radar picture shows on the sight[^warhistory][^airwar-ml]; the photo shows a bare plate[^kiev] | the radar page (the original's MFD) | ours keeps the MFD (the game needs it) |
| 6 | SPO-15 indicator: aircraft symbol, ring of sector lamps, power strip, the bottom type lamps (1185,140) | СПО-15Л «Берёза» RWR: on the MLD; the ML had the СПО-10 «Сирена»[^airwar-ml][^airwar-mld] | its two lower boxes are `LIGHT004` / `LIGHT003` ("ML" / "AI" lamps); the rest is static | the art follows the MLD here |
| 7 | dial with 0 at 9 o'clock and 1, 2, 4, 6 both ways (1099,270) | vertical speed indicator (inferred from the face); type and unit open (× 10 m/s or × 1000 ft/min, as the Mirage's identical face) | `VARIOCLOCK`: 30,000 ft/min per turn from 9 o'clock (6000 ft/min reads at 72°; the painted 6 is at 180°) | live, but off the face's scale |
| 8 | dial 2 … 10 with a red-yellow-green arc and a painted "FUEL" plate; the legend under the hub reads like "× 100 °C" (1184,226) | the photo's 0–10 dial under the lamp board[^kiev] (photo, unlabelled there); the ИТГ-1 exhaust-temperature indicator[^airwar-ml] is likely (inferred from the legend) | `FUELCLOCK` (fuel fill) | the game's artist made it the fuel gauge; the face itself is likely the EGT |
| 9 | dial 0–8, orange hub, legend "× 1000 Л" (1176,280) | the fuel gauge in thousands of **litres** (photo: "×1000Л" on the same face[^kiev]; РТСТ-50Т in the ML list[^airwar-ml]) | `RPMCLOCK`: clamp(rpm, 0.6, 0.97), one turn = 1, 0 on the painted 0 (204°) | **RPM on the fuel gauge**; the face is 37.6° per 1000 l, 0–8 over 301° |
| 10 | small framed dial: aircraft planform, arc scale, legends "235 … M / V" at the top (1245,192) | the wing-sweep indicator: 16 / 30 / 45 / 60 marks and "235 M 1400 V", the speed / Mach limits per sweep (photo[^kiev]); the sweep settings are 16 / 45 / 72°[^nmusaf] | `THROTTLECLOCK`: rpm | the game has no wing sweep (docs/aircraft.md: the wing parts are dropped) |
| 11 | twin-arc dial with a plate "…ГИДРО… / ГИДРОСИСТ." (1051,336) | the two-needle hydraulic pressure gauge (УИ2-300К on the MiG-23UB[^ub]) | `TEMPCLOCK`: clamp(rpm, 0.5, 0.8) | TEMP on a hydraulics face |
| 12 | 3-digit drum counter "30Я" with "км" (876,325) | the RSBN range counter (ППД-2 on the MiG-23UB[^ub]; the photo's "000 КМ"[^kiev]) | static | `rsbn_counter` (4.5) |
| 13 | small dial with dense ticks and a knob at lower left (1240,160) | likely the АЧС-1 clock[^ub] (inferred from the knob; the numbers are unreadable) | static | `panel_clock` candidate, open |
| 14 | two red lamp boards with ДЕНЬ / НОЧЬ knobs (1060..1150,160..225) | the red and green warning boards (табло Т-10У2 / Т-4У2 on the MiG-23UB, legends not public[^ub]) | `LIGHT000` MASTER CAUTION at 1059,165 and `LIGHT001` FIRE at 1059,185 cover the left board's top cells; the others are static | legends unreadable |
| 15 | white card with a table (1244,250) | a placard (inferred) | static | — |
| 16 | CHF / FLR counter windows (1082,79 / 93) | the game's own (English legends) | the chaff / flare counts | — |
| 17 | FLP / BRK lamps, APLT lamp (798,47 / 797,64 / 856,76) | the game's own (English legends, `lights.bmp`) | `SLIGHT003` flaps, `LIGHT005` air brake, `LIGHT008` autopilot | — |
| 18 | three gear lamps (711 / 727 / 743,151) and the gear handle (672,262) | gear lamps | `SLIGHT000..002`, `LIGHT009` | — |
| — | "АРК" box under the MFD (≈ 880..980,255..285) | the ARK radio-compass control (АРК-10 / АРК-15М[^airwar-ml]) | static | — |
| — | weapons selector top left (≈ 700..790,70..140): СТРОБ, УС Т, ЗОНА, СБРОС | the sight / weapons control panel (photo: the same panel[^kiev]) | static | — |
| — | HUD frame: three round lamps left (red, red, green), two right (dark green, orange), no legends (`hud.bmp`) | the sight's side lamps; the photo's sight reads «БАЗА» and «УГЛЫ» on its side windows[^kiev] | static | legends unreadable |

The lens ADI and the lamps are drawn by the original. No `[HORIZON]` disc (Active 0), no `[PANELRWR]` (Active 0), no
`[PANELAOA]` / `[PANELVARIO]` tapes (Active 0; `Aoa.bmp` / `Vario.bmp` are not shipped in `mig23/`).

### 2.2 Units

The original HUD and gauges use kt, ft and ft/min on every jet (docs/cockpit.md "HUD symbology"). The MiG-23's faces
are metric: the altimeter reads metres, the Mach meter reads Mach, the fuel gauge reads thousands of litres and the
EGT reads × 100 °C (inferred). So no MiG-23 needle reads the number its face prints, except the vertical speed by
chance (open).

## 3. MiG-29 panel (`mig29`)

### 3.1 What the art paints and what the original drives

The real 9.12 panel is a classic "T" of dials with no MFDs[^ea][^wiki-29]. Its right side carries the radar altimeter,
the engine, fuel and hydraulic gauges, the Ekran text display and the SPO-15LM[^ea][^fc3]. The game's art keeps the
Soviet flight and engine dials but adds Western parts (see §1).

| # | Painted item (centre, panel px) | Real instrument | Original draws | Note |
|---|---|---|---|---|
| 1 | dial 0, 20 … 100, 200, 400, 600, 1000, 1500 (non-linear), "МЕТРЫ", red flag window, yellow index (904,168) | the radar altimeter indicator (A-037 set): needle, danger-height index that sets off a lamp and the voice warning, red failure flag[^ea][^fc3]; the metric cockpit reads 0–1000 m[^fc3] (the art's face goes to 1500) | `SPEEDCLOCK`: 1000 kt per turn | **airspeed on the radar altimeter** |
| 2 | dial 0–9 with a counter window at 3 o'clock (948,229) | the barometric altimeter: needle plus counter; metric: inner 0–30,000 m, outer 0–1000 m per turn[^ea][^fc3] (ВДИ-30 is open) | `ALTITUDELOCK`: 1000 ft per turn (no FullClock: the exe ignores it) | a metric face read in feet |
| 3 | lens ADI with bank ring (1038,181) | КПП-СИ: pitch ±80°, bank ±60°, director bars, flags[^ea] | `LENHORIZON` (live) | the ball is blue over black |
| 4, 5 | two dials "100 %" at 12, 80, 60, 40, 20 anticlockwise; legend under the hub unreadable (1009,253 / 1062,253) | the real jet has **one** tachometer with two needles (ИТЭ-2ТБ, 0–110 %, one per RD-33)[^ea] | `THROTTLECLOCK` / `…SECONDARY`: rpm, one turn = 1 from 12 o'clock | the faces measure 20 % 104°, 40 % 167°, 60 % 230°, 80 % 294°, 100 % 348° (about 3.1° per %, 0 at about 41°); the original's needle is up to 32° off at low RPM |
| 6 | dial "α" left scale 0 … 30 with a red-hatched band near 25–30; "nᵧ" right scale 0 … 10, red from 8 (1116,56) | the AoA / g meter: AoA on the left with 15° and 25° marks and a red sector; g on the right with a red mark and a reset button[^ea] (УУАП-72 is open) | `VARIOCLOCK`: 30,000 ft/min per turn | **vertical speed on the AoA / g meter** |
| 7 | dial with a red-yellow-green arc, "LBS TOTAL INTERNAL" (Western) (1174,76) | the real gauge is a tape in hundreds of kg, with a range-to-go readout and a 550 kg minimum mark[^ea] | `FUELCLOCK` | the art's face is in lb, as the game |
| 8 | two orange lamp boxes, no legend (945,161 / 181) | the game's own | `LIGHT001` / `LIGHT002`: left / right engine fire | — |
| 9 | amber MASTER CAUTION box (1103,9) | the real master caution lamp-button flashes with any red annunciator or Ekran message[^ea] | `LIGHT000` | English legend |
| 10 | three empty frames top left (754 / 780 / 806,20) | the game's own | `LIGHT004` ML, `LIGHT003` AI, `LIGHT006` ECM | — |
| 11, 12 | two F-16-style MFDs (707,138 and 1115,139 top-left) | the real 9.12 has none; its head-down display (ИПВ) at the top right repeats the HUD[^ea][^ed-ipv] | the radar (left) and RWR (right) pages | the RWR lives on MFD page 7 (no `[PANELRWR]`) |
| 13 | F-4-style nav-mode panel: HDG / TACAN / ADF / NAV COMP (≈ 700..800,40..90) | Western (the F-4's) | static | — |
| 14 | three gear lamps and a mirrored "WHEELS" handle (655..670,169..184; 655,210) | gear lamps | `SLIGHT000..002`, `LIGHT009` | — |
| 15 | FLQ / BRK lamps (873,212 / 233) | the game's own | `SLIGHT003`, `LIGHT005` | — |
| 16 | AQLT lamp (1257,91) | the game's own | `LIGHT008` autopilot | — |
| 17 | two identical blocks with a guarded switch and a yellow cover, Cyrillic legends unreadable (≈ 960 / 1010,300) | one per engine (inferred from the pair) | static | — |

### 3.2 Units

The radar altimeter (m), barometric altimeter (m) and AoA / g meter (°, g) are metric / Soviet faces. The tachometers
are in %, as the game. The fuel face is in lb (Western art), as the game.

## 4. Better cockpit items per MiG

The items: `Settings.BETTER_COCKPIT` (`game/settings.gd`) and docs/cockpit.md "Better cockpit". "Applies" means the
item changes something on that panel.

| Item | MiG-23 | MiG-29 |
|---|---|---|
| `turning_compass` | **yes**: the ПНП card turns (`compass.gd` `INSTRUMENTS`; the card's painted course arrow and lubber erased). The painted К / Г bars stay (4.6) | no dial (the art paints no HSI) |
| `engine_rpm` | alone: a better RPM, still **on the fuel gauge**. With `dials_by_label` RPM has no dial (the art paints no tachometer), as the F-16's throttle | `RPMCLOCK` is inactive; the tachometers are `THROTTLECLOCK` records. With `dials_by_label` they read RPM, Better RPM with this item |
| `engine_temp` | alone: `TEMPCLOCK` on the hydraulic gauge. With `dials_by_label`: on the EGT face (# 8), × 100 °C | no dial (the art paints no EGT gauge; `TEMPCLOCK` inactive) |
| `throttle_ab` | alone: on the wing-sweep indicator. With `dials_by_label` the throttle needle goes (the real jet has no throttle dial) | alone: the tachometers pass 12 o'clock ("100 %") in AB. With `dials_by_label` they read RPM instead (the real tachometer reads 100 % in full AB[^fc3]) |
| `fuel_total` | the needle applies. With `dials_by_label` it moves to the litre gauge (# 9): litres = kg / 0.78 (inferred: a kerosene density), 0–8000 l at 37.6° per 1000 l. The original's capacity (12,500 lb internal) is far above the real one (docs/real-aircraft.md §9.2), so the full needle sits near 7 | **yes**: total fuel on the lb face. No counter (the face's digit windows sit under the hub, as the F-4's) |
| `aoa_indexer` | no indexer painted | no indexer painted; the UUA is 4.2 |
| `panel_clock` | candidate: # 13 if a closer look confirms a clock face (open) | no clock painted |
| `standby_instruments` | the VVI (# 7) is already live, off its scale (`dials_by_label` fixes it) | none painted |
| `warning_lamps` | none: the red boards' legends are unreadable | none: no readable unwired legend |
| `crisp_mfd` | yes (one MFD) | yes (two MFDs) |
| `dials_by_label` | **yes, the main fix**: the Mach number on # 2; fuel in litres on # 9; TEMP on # 8; the VVI on its measured face; THROTTLE, RPM and the hydraulic needle off | **yes**: each engine's RPM on its tachometer (`RPM_R` for the right one); `SPEEDCLOCK` off the radar altimeter (4.3) and `VARIOCLOCK` off the UUA (4.2) |
| `ar_nws_lights` | no AR / NWS lamp painted | no AR / NWS lamp painted |
| `smooth_needles` | yes, every needle | yes, every needle |

The measured scales (value / clock-degree pairs) are in `gauges.gd` `DIALS`.

### Proposals (MiG-only)
4.1, 4.2, 4.3 and 4.5 are built; 4.4 and 4.6 are open.

**4.1 Metric gauges (`metric_gauges`, built).** Each MiG face reads its own unit: the altimeters in metres (one turn =
1000 m), the radar altimeter in metres, fuel in litres (MiG-23) and the MiG-23's vertical speed in × 10 m/s (unit
inferred; open, §7 question 2). The original reads ft and kt everywhere. The HUD stays in the original's units
unless the Real HUD is on (§5, §6).

**4.2 MiG-29 AoA / g meter live (`uua`, built).** Two needles on the UUA (# 6): AoA on the left scale (0 … 30°, with the
15° / 25° marks[^ea]) and g on the right (0 … 10). It replaces the vertical speed the original draws there. A max-g
memory needle is open (the real meter has a reset button[^ea], which suggests one).

**4.3 MiG-29 radar altimeter live (`radar_alt`, built).** The needle shows the radar height (`agl_ft` → m) on the
non-linear 0–1500 m face (# 1). The red flag hides while the height is valid: at most 1500 m and 60° of bank
(inferred). The yellow danger-height index stays as painted. It replaces the airspeed the original draws there, so
the panel shows no airspeed; the HUD and the MFD still do.

**4.4 MiG-23 SPO-15 lamps live (`spo15`, open).** The SPO-15's sector lamps light toward each emitter, the power strip
shows the strongest signal, and the red centre lamp lights on a lock (steady) or a launch (flashing)[^su25t][^hoggit].
Threat-type lamps: П airborne radar, З long-range, Х medium-range, Н short-range SAM radars[^su25t][^fc3]. Data from
`iaf-avionics` `rwr.rs` (the contacts' bearings and kinds). About 10° resolution within ±50°[^spo15-ed]. The
original's ML / AI boxes stay. Open: the lamp count on the MLD panel.

**4.5 MiG-23 RSBN range counter (`rsbn_counter`, built).** The drum (# 12) shows the distance to the current waypoint
in km. The real counter shows the range to the RSBN beacon[^ub]; the game has no beacons, so the waypoint stands in
(inferred).

**4.6 MiG-23 HSI bars and hydraulic gauge (open).** The ПНП's К / Г bars follow the ILS deviation when the original
HUD shows its ILS (gear down), and the flags drop otherwise. The hydraulic gauge's two needles show the normal
pressure (value open), and fall to 0 with the hydraulics damage (18).

## 5. Real HUD: MiG-23ML (АСП-17МЛ sight)

### 5.1 What the real jet has

* **The sight:** early MLs carried the АСП-23ДЦМ optical sight; the MLA / MLD the **АСП-17МЛ**[^airwar-ml]. A later
  conversion to the 23-12A standard gave most MLs the АСП-17МЛ (forum claim, uncertain[^wt-23]). The MLD's sight
  is named С-17МЛД[^airwar-mld].
* **One display for everything:** the ML has no radar scope. The Sapfir-23ML's picture, the IRST data and the gun
  reticle go onto the sight[^warhistory][^airwar-ml]. US / Israeli evaluations say the sight "doubles as a
  radarscope"[^warhistory].
* **What it can show:** CRT symbology for radar / IRST targets, navigation, the A-A gun and flight data; a fall-back
  electromechanical gunsight mode «АСП/РП»; CCIP / CCRP from the ASP-17 base (a modeller's description[^sketchfab]).
  The symbology is "almost identical" to the АСП-23Д, documented in the Polish ASP-23D / S-23E and MiG-23MF
  manuals[^il2pl].
* **Designation limits:** the АСП-17МЛ points +16 / −18° vertically and ±12° in azimuth[^airwar-ml]. The АСП-23ДЦМ
  only vertically, +8 / −5.5°, set by twisting the throttle grip[^airwar-ml].
* **Legends:** «НОП» (недопустимая ошибка прицеливания, "aiming error too large") when the target's angular rates are
  too high[^airwar-ml]. «ПР» (пуск разрешён, launch authorised) once the missiles are ready and in range (a forum
  description of MLD HUD photos, read only as a search summary: uncertain[^key-aero]).
* **Navigation:** the pilot follows "К" (course) and "Г" (glide) symbols in the НВГ mode[^n003e]. The autopilot's
  director signals go to the sight[^airwar-ml].
* **Radar modes:** БСВ, БС I / II / III (27 / 45 / 65 km), СМВ, МВ[^n003e]. Range scale and the R-24R's Dmin / Dmax
  shown, the range scale stepping from 20 km down to 3 km (uncertain[^key-aero]).
* **IRST:** Т-I (60° × 15° scan), Т-II (15° × 6°), Т-III (auto track)[^n003e].
* **Close combat:** the MLD's Sapfir-23MLA-2 adds a close-combat mode with a vertical scan[^rp23].
* **Datalink:** «Лазурь» ground-control commands show as sight symbols (e.g. turn arrows) and cockpit lamps[^capss].
* **No HUD-style flight data:** no source shows a pitch ladder or speed / altitude tapes on the ML's sight
  (inferred; open). The original's `[HUD]` agrees: `ShowHorizon 0`, `ShowLRScales 0` (the marker without a ladder, no
  speed / altitude scales).
* **No helmet:** the ML has no helmet sight (inferred: no source names one). The original's `Dash 1` still draws its
  helmet display when the pilot looks aside.
* **Open:** the colour of the symbology, the reflector's field of view, the exact reticle drawing and the lamp
  legends.

### 5.2 Ours

`real_hud/mig23.rs`, a reconstruction: docs/real-hud.md "MiG-23ML".

## 6. Real HUD: MiG-29 9.12 (ИЛС-31, СЕИ-31)

### 6.1 What the real jet has

**Hardware.**
* The СЕИ-31 unified indication system is the ИЛС-31 HUD and the ИПВ head-down display[^studfile].
* The ИЛС-31 is a CRT with a collimator and combiner glass[^ea]. Some sources call it K-31 and give the ИЛС-31 to the
  Su-27 (unreliable).
* **Field of view:** 13° azimuth × 18° elevation instantaneous at 600 mm from the eye; 24° circular in total with head
  movement[^ea].
* A DAY / NIGHT / GRID switch changes the symbol colour or shows a fixed reticle[^ea]. The real colour is open.
* The ИПВ repeats the HUD, sometimes with small changes[^ed-ipv].

**Basic symbols, every mode** [SIM][^ea][^fc3]:
* indicated airspeed as a **number** at the upper left (km/h in the metric cockpit), the commanded speed above it, an
  acceleration triangle below it;
* a heading tape at the top, read in tens of degrees ("11" = 110°);
* the altitude as a **number**: the radar height to 1 m below 1000 m, the barometric height to 10 m above; the
  commanded height above it;
* a pitch scale on the **right**, the horizon line and a bank scale;
* a fixed aircraft symbol (cross) and a large steering circle;
* the range to the waypoint at the bottom centre (km) and the mode name at the lower left.

**Navigation** [SIM][^ea][^fc3]: sub-modes МРШ (route), ВЗВ (return), ПОС (landing). The circle shows the azimuth to
the waypoint. On the approach, the glide-slope and localizer marks show on the HUD and the ADI / HSI directors repeat
them.

**A list from the Russian MiG-29A manual** (radar plus «Лазурь» ground control, quoted on the ED forum[^ed-datalink]):
«РЛ» radar on, ППС / ЗПС (head-on / pursuit), own IAS, target IAS, range to target, heading, target height, own height,
lock box, IFF mark, target mark, beacon mark, horizontal steering ring, antenna azimuth, antenna elevation, scan bar
number. Ground-control commands such as a zoom climb («Горка») also show.

**Long-range combat (ДВБ)** [SIM][^fc3][^ea]:
* Search: targets as rows of dots, a range scale on the left, an elevation scale (±60°) on the right, the azimuth zone
  at the bottom, «ППС» / «ЗПС» / «АВТ», «АП» when jammed.
* Mode legends «ОБЗ», «СНП ДВБ», «АТК ДВБ».
* After lock: a target diamond, a range caret, an aspect line and an attack symbol. The range scale marks Rmax, Rtr
  (no-escape) and Rmin.
* Legends: **«ПР»** launch authorised, **«Г»** zoom-climb command (the circle jumps), **«ОТВ»** break away.
* Range scale steps 100 / 50 / 25 / 10 km (inferred from [EA]'s 54 / 27 / 13.5 / 5.4 nm); 150 km and the optical 5 /
  1 km scales are cited too[^ed-ipv].

**IRST (ОЛС)** [SIM][^ea]: a lock strobe round the target mark, «ТП», «ПП» (gain reduced).

**Close combat** [SIM][^ea][^fc3]:
* Vertical scan: two vertical lines from −10° to +50°, «РЛ» or «ТП».
* ШЛЕМ (helmet, Щель-3УМ[^wiki-29]): ±60° azimuth, +60 / −14° elevation; a flashing «ПР» on the helmet sight; an X
  when the target is outside the seeker's limits.
* ОПТ: a manual aiming mark with the laser rangefinder.
* Boresight (Ф0): a fixed cross on the missile seeker; a 2.5° circle[^fc3].

**Gun** [SIM][^ea][^fc3]: an LCOS-type ring and moving cross with the range; target wingspan setting; rounds left in
quarters; a funnel without a lock; a fixed reticle as the back-up.

**Air to ground** [SIM][^fc3][^ea]: «ОПТ ЗЕМЛЯ»: a range scale with Rmax / Rmin and a moving pipper at the impact
point (CCIP-like); «ОТВ» flashing at the minimum range; level / toss release (КБР) with a g vector and a commanded-g
ring, a time-to-release scale and «Г» at the pull-up.

**Limits shown:** the AoA limiter: 26° with the SOS-3M (forum, uncertain[^wt-29]); 9 g below M0.85, 7 g above
(forum[^wt-29]); the СОС-3М shows the current and limit AoA and g[^ru-wiki-29].

### 6.2 Ours

`real_hud/mig29.rs`, laid out from the simulator manuals[^ea][^fc3]: docs/real-hud.md "MiG-29 9.12".

## 7. Open questions

1. MiG-23 # 8: is the face the ИТГ-1 EGT (× 100 °C) or a fuel gauge? The legend under the hub reads like "× 100 °C";
   the game's artist added a "FUEL" plate and the coloured arc.
2. MiG-23 # 7: the VVI's type and unit (the face's 1 / 2 / 4 / 6 marks). Ours reads × 10 m/s (inferred).
3. MiG-23 # 13: is it the АЧС-1 clock? Its numbers are unreadable on the art.
4. MiG-23 internal fuel: 4,250 l in docs/real-aircraft.md, 5500 kg on airwar[^airwar-ml]; the litre gauge's full
   mark depends on it.
5. The real designations: КУС-*, ВДИ-30 (MiG-29), УУАП-72, ИТ-23: no source confirms them for these jets.
6. The HUD colours of both jets, the АСП-17МЛ's field of view and reticle drawing.
7. The lamp legends on both jets: the MiG-23's red boards and the sight's side lamps, the MiG-29's blocks (# 17).
8. The best unread source: an ML flight manual PDF on an expired Discord link (cited on the War Thunder forum[^wt-23]),
   and the Markovsky / Prikhodchenko book on Calameo[^calameo].

[^ea]: Eagle Dynamics, *DCS MiG-29A Early Access Manual* (Sept 2025), pp. 8–31 (instruments), 65–104 (HUD):
https://www.digitalcombatsimulator.com/upload/iblock/aa2/ulzl67k42kj99ushy9m29hlvmtk0y2tg/DCS%20MiG-29A%20Early%20Access%20Manual%20EN.pdf
[^fc3]: Eagle Dynamics, *DCS MiG-29 Flight Manual* (Flaming Cliffs 3), pp. 21–31 (panel), 40–59 (HUD):
https://www.digitalcombatsimulator.com/upload/iblock/463/DCS%20MIG-29%20Flight%20Manual%20EN.pdf
[^wiki-29]: Wikipedia, "Mikoyan MiG-29" (conventional dials, HUD, Shchel-3UM helmet): https://en.wikipedia.org/wiki/Mikoyan_MiG-29
[^ru-wiki-29]: Wikipedia (ru), "МиГ-29" (СОС-3М, fire warning): https://ru.wikipedia.org/wiki/МиГ-29
[^studfile]: "СЕИ-31" (ИЛС-31 + ИПВ), studfile: https://studfile.net/preview/5383865/
[^ed-ipv]: ED forum, "ИПВ" thread (the HDD repeats the HUD; range scales): https://forum.dcs.world/topic/64-ipv
[^ed-datalink]: ED forum, "MiG-29A data link" (the Russian manual's HUD list): https://forum.dcs.world/topic/33602-mig-29a-data-link/
[^wt-29]: War Thunder forum, MiG-29 dissection, p. 199 (AoA limiter, g limits): https://forum.warthunder.com/t/mikoyan-gurevich-mig-29-fulcrum-history-design-performance-dissection-part-1/28118?page=199
[^airwar-ml]: airwar.ru, "МиГ-23МЛ" (instrument list, sights, СПО-10, radar data on the sight, НОП): https://www.airwar.ru/enc/fighter/mig23ml.html
[^airwar-mld]: airwar.ru, "МиГ-23МЛД" (СПО-15Л, С-17МЛД sight): https://www.airwar.ru/enc/fighter/mig23mld.html
[^ub]: "МиГ-23УБ" front cockpit instrument list, crown-airforce: http://crown-airforce.narod.ru/retro/migi/mig23ub_01.html
[^kiev]: Wikimedia Commons, "Cockpit Mig23 high resolution.jpg" (a СПО-10 aircraft, variant unconfirmed): https://commons.wikimedia.org/wiki/File:Cockpit_Mig23_high_resolution.jpg
[^warhistory]: warhistory.org, "Mikoyan MiG-23" (no radar scope; the HUD doubles as a radarscope): https://warhistory.org/article/mikoyan-mig-23
[^nmusaf]: National Museum of the USAF, "Mikoyan-Gurevich MiG-23MS Flogger E" (16 / 45 / 72° sweep): https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/1162493/mikoyan-gurevich-mig-23ms-flogger-e/
[^sketchfab]: Sketchfab, "MiG-23ML HUD ASP-17ML" (description): https://sketchfab.com/3d-models/mig-23ml-hud-asp-17ml-fa94cb18343241dba2ed22cfa183bd74
[^il2pl]: il2forum.pl, MiG-23 thread p. 240 (ASP-17ML vs ASP-23D symbology): http://il2forum.pl/index.php?topic=9711.240
[^n003e]: "N003E modes", Soviet aircraft tech: https://sites.google.com/site/sovietaircrafttech/mig-23/n003e/modes
[^rp23]: Wikipedia, "RP-23 Sapfir" (MLD close-combat vertical scan): https://en.wikipedia.org/wiki/RP-23_Sapfir
[^key-aero]: Key.Aero forum, "MiG-23MLD in Afghanistan, HUD shots" (read only as a search summary; HTTP 403): https://www.key.aero/forum/modern-military-aviation/35762-mig-23mld-in-afghanistan-hud-shots
[^capss]: CAPSS, "Stickers, scans and radar beats: an operational view of the MiG-23MF with the Indian Air Force" (Лазурь commands): https://capssindia.org/stickers-scans-and-radar-beats-an-operational-view-of-mig-23mf-with-indian-air-force/
[^wt-23]: War Thunder forum, MiG-23 dissection (ASP-17ML conversion): https://forum.warthunder.com/t/mikoyan-gurevich-mig-23-flogger-history-design-performance-dissection/40222/57 ; the ML manual link: https://forum.warthunder.com/t/mig-23m-ml-mld-performance-discussion/8732/4
[^calameo]: Markovsky / Prikhodchenko, MiG-23 book, Calameo: https://www.calameo.com/read/00188772198ad5eede3a8
[^su25t]: Eagle Dynamics, *DCS World Su-25T Flight Manual* (SPO-15 lamps and threat letters): https://www.digitalcombatsimulator.com/upload/iblock/61b/DCS%20World%20Su-25T%20Flight%20Manual%20EN.pdf
[^hoggit]: Hoggit wiki, "Su-25T" (SPO-15: red steady = lock, flashing = launch): https://wiki.hoggitworld.com/view/Su-25T
[^spo15-ed]: Fly and Wire, "MiG-29's SPO-15 RWR: Q&A with Eagle Dynamics" (2025): https://flyandwire.com/2025/09/04/mig-29s-spo-15-rwr-qa-with-eagle-dynamics/
