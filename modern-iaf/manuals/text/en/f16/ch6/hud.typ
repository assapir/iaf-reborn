#import "src.typ": *

#layout-head

The #term("HUD") shows the flight data and the aiming symbols over the view ahead#d34[section I, "Head-up display (HUD)", page 1-156]. Its symbols follow the master mode (@stores).

#if not sufa [
The sim's #jet.short is a Block 40, which came with the wide-angle HUD made for the LANTIRN pods, whose combiner works by diffraction#footnote[F-16.net, "F-16 Versions: Block 40/42": "the associated holographic HUD", "a diffractive optics heads-up display"; Block 40s went to Israel. #link("https://www.f-16.net/f-16_versions_article7.html"). Checked 19 November 2026.]. The Barak 2020 upgrade fitted a new HUD#footnote[FlightGlobal, "Israel completes F-16 Barak upgrade", 5 November 2014: "a new head-up display". Paywalled: read through a search engine's quote, second-hand. #link("https://www.flightglobal.com/israel-completes-f-16-barak-upgrade/115034.article").], whose maker and field of view are not public, and the Sufa's avionics#footnote[Hamichlol (a Hebrew encyclopedia), "F-16 Fighting Falcon": by 2018 every Barak was upgraded to "Barak 2020", with the Sufa's avionic systems installed. A secondary source. #link("https://www.hamichlol.org.il/F-16_%D7%A4%D7%99%D7%99%D7%98%D7%99%D7%A0%D7%92_%D7%A4%D7%90%D7%9C%D7%A7%D7%95%D7%9F"). Checked 19 November 2026.]. The sim draws the F-16C/D's combiner, two slender posts joined by an arched bar, and on it the Sufa's symbols, in a slightly narrower field: that the #jet.short's are the same is inferred. The HUD's pictures in this chapter show the #jet.short's frame. The cockpit's panel pictures are the Sufa's: its HUD is a flat rectangular plate, and the controls are the same.
]

#display("hud_modes", [The HUD with the #term("DED")'s lines repeated on it. Top: navigation, air-to-air. Bottom: air-to-ground with the bomb's impact point, dogfight.], width: 100%)

=== What every mode shows

The airspeed scale on the left, the altitude scale on the right, the heading scale, the pitch ladder, the flight path marker (where the jet is going), the gun cross (where the nose points), the g, and the master arm's state: ARM, or SIM with #row("master-arm-switch") at SIMULATE. The lower right column holds the slant range, the low-altitude warning height (AL), the time and distance to the steerpoint. *FUEL* flashes below the #term("Bingo fuel"). *ALIGN* shows while the #term("INS") aligns and flashes when it is ready.

#table(columns: (auto, 1fr), table.header[*Mode*][*Added symbols*],
  [Navigation], [The steerpoint's diamond and the steering cue. With the gear down: the ILS's two needles.],
  [Air-to-air, a missile selected], [The missile's circle. With a radar lock: a box on the target, a range scale on the right with the target's caret, and the closing speed. Without a lock in a dogfight pattern: the pattern's line or cross (@radar-aa).],
  [Air-to-air, the gun], [The funnel of the gun's sight; with a lock, the aiming dot (@aa-weapons).],
  [Air-to-ground, a bomb], [The impact point (a dot in a circle) at the end of the bomb fall line (@ag-weapons).],
  [Air-to-ground, a guided bomb], [The target's box, a steering line and a range scale (@ag-weapons).],
  [Air-to-ground, the gun], [The strafing dot with the slant range.],
)

=== Ground-avoidance cues

A large *X* flashes when the radar altitude and the dive call for an immediate pull-up, and the voice says "Pull up". The cue and both voices need #row("RDR_ALT") on: with it off they stay silent. Below the height set on the DED's ALOW page *AL* flashes and the voice says "Altitude".

=== The HUD control panel

#table(columns: (27%, 1fr, 22%), table.header[*Switch*][*Positions*][*Key*],
  [#row("w_vah-switch")], [VV/VAH adds the vertical velocity scale beside the altitude scale. VAH: the speed, altitude and heading scales. OFF: the read-outs alone.], [#key("HUD SCALES (VV/VAH / VAH / OFF)")],
  [#row("att_fpm-switch")], [ATT/FPM: the ladder and the flight path marker. FPM: the marker alone. OFF: neither.], [#key("HUD FP MARKER (ATT/FPM / FPM / OFF)")],
  [#row("tas-switch")], [Calibrated airspeed (C), true airspeed (T) or ground speed (G). With the gear down or in dogfight the scale is calibrated airspeed.], [#key("HUD VELOCITY (CAS / TAS / GND SPD)")],
  [#row("altrad-switch")], [RADAR: the radar altitude on the scale. BARO. AUTO: the radar altitude's own scale below 1,200 ft.], [#key("HUD ALT (RADAR / BARO / AUTO)")],
  [#row("deddata-switch")], [Repeats the DED's five lines, or the fault list's, low in the HUD.], [#key("HUD DED DATA (DED / PFL / OFF)")],
  [#row("depr-ret-switch")], [STBY shows the standby reticle, a ring with its dot; PRI the manual bombing mode's reticle. #row("depr_ret") lowers either.], [#key("HUD DEPR RET (STBY / PRI / OFF)")],
  [#row("SYM")], [The symbols' brightness.], [#key("Step HUD brightness")],
)

=== The helmet display

The helmet sight puts an aiming cross on the visor. Look at a target to point a short-range missile's seeker at it; a diamond shows where the seeker tracks. #row("HMCS_SYM_INT_KNOB") dims it to off. The helmet display blanks while you look through the HUD, where the HUD shows, and while you look down into the cockpit: its symbols never cover the canopy rail or the consoles (the DED's HMCS page: CKPT BLNK ON). That the real helmet's symbols look the same is inferred: no figure of them is public.

#display("helmet", [The helmet looking 54° left at a locked target, a short-range missile selected: the aiming cross, the radar's box and the seeker's diamond on the target, the circle whose gap shows where the head looks from the nose, the head's heading above, the g and speed at the left, the altitude and steerpoint at the right.], width: 90%)

#in-sim[
  - #row("test-step-switch") moves only: the HUD's four test patterns#d34[page 1-158] are not drawn.
  - #row("drift") at DRIFT C/O (#key("DRIFT C/O (DRIFT C/O / NORM)")) #then[centres the flight path marker and the ladder.] At WARN RESET (#key("WARN RESET")) #then[the flashing FUEL cue and the repeating "Altitude" call stop.]
  - #row("cont") (#key("HUD CONT (contrast): next step")) is partly modelled: #then[the symbols' edges wash out as it turns down.] The HUD draws no infrared picture for it to set.
  - The release modes' cues (TD box, steering line, solution and pull-up cues, the manual reticle, LOW) are described with the modes (@ag-weapons).
]

=== Night-vision goggles <hud-goggles>

At night the pilot can wear night-vision goggles on the helmet: two image tubes that amplify the faint light of the night and show it in green. The F-16I's cockpit and outside lights are built to suit them#footnote[Airforce Technology, "F-16I Soufa" (a trade page; a secondary source): #link("https://www.airforce-technology.com/projects/f-16i-soufa/"). Checked 19 November 2026.]. Which goggles the Israeli Air Force's fighter pilots wear is not public: open. For the F-16D Barak no source names goggles: open. The first US helmet display of the F-16 could not be worn with goggles: the pilot had the helmet display or the goggles, never both#footnote[T. Rogoway, "New 'Digital Eye Piece' will allow U.S. fighter pilots to own the night like never before", The War Zone, 8 February 2018: #link("https://www.twz.com/18358/new-digital-eyepiece-will-allow-u-s-fighter-pilots-to-own-the-night-like-never-before"). Checked 19 November 2026.]. How the #jet.short's helmet works with goggles is open. The goggles show a round field of about 40°; the pilot reads the instruments with the naked eye by looking under the tubes#footnote[C. E. Rash, "A 25-year retrospective on NVGs", AeroSafety World, August 2010: #link("https://flightsafety.org/wp-content/uploads/2016/11/asw_aug10_p14-18.pdf"); M. Grünwald, "Night vision goggles: how pilots fly in the dark", MiGFlug Afterburner (a secondary source): #link("https://migflug.com/afterburner/night-vision-goggles-nvg-how-fighter-pilots-fly-at-night-anvis/"). Checked 19 November 2026.].

#in-sim[
  - #key("Night-vision goggles: down / up (F-16)") flips the goggles down before the eyes. #then[A round field about 40° across, in the upper part of the view, shows the goggles' green picture. It moves with the head. Below it the panel shows as the naked eye sees it.] The same key flips them up again. A flight starts with them up; they work at any height.
  - By day the goggles' picture washes out: #then[the round field shows a bright, pale green with soft, faint detail.] A tube holds its picture's brightness as the light grows and loses its sharpness in bright light#footnote[US patent 5,949,063, "Night vision device having improved automatic brightness control and bright-source protection": #link("https://patents.google.com/patent/US5949063A/en"). Checked 25 November 2026.].
  - With the goggles down the helmet display shows no symbols, as the US helmet's (inferred). The HUD stays.
  - #row("mms-switch") at NVIS keeps the cockpit's own light out of the goggles' picture. At NORMAL the cockpit glares in them and washes out the lower part of the round field (@lighting).
  - The goggles hold their picture at one brightness, but its grain follows the night's light: #then[under a full moon the picture is clean; on a moonless night it sparkles with noise.] An image tube's noise grows as the light falls (inferred from the photon noise).
]
