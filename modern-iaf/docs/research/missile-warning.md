# Missile warning: which threat type each jet's warning can name — research

This page records what public sources say about how the Israeli Air Force's fighters warn the pilot of a missile, and
how far each warning names the threat's type: the radar warning receiver, the missile approach warning and their
sounds. It covers the F-16I Sufa, the F-16D Barak and the F-35I Adir, which Modern IAF flies, and the F-15I Ra'am and
the F-15C/D Baz for later. The user, 19 November 2026: "yes continue with the missle things as you needed" (step 4 of
the missile work: the missile warning names the missile type, [../avionics-plan.md](../avionics-plan.md) §7.2), and
"do the research for the F15s also, so we won't need to do it twice". Research date: 19 November 2026. What the sim
draws from it is in [../ews.md](../ews.md) §2 and §3.

**Terms**
- **RWR:** radar warning receiver. It hears radars and names each by its signal.
- **MAW:** missile approach warning. An infrared (IR) MAW sees the hot plume of a missile's motor.
- **ARH / SARH:** active / semi-active radar homing: a missile guided by its own radar, or by the launcher's radar
  reflected off the target.
- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning; "open" means no source
  was found. **Second-hand** marks a fact taken from a search engine's quote of a page that refused automated access.
  **Secondary** marks a trade page, vendor page or simulator manual: it shows the general practice, not the IAF's own.

## 1. The answer first

| jet | radar warning | missile approach warning | a radar-guided missile at the jet | an infrared missile at the jet | voice |
|---|---|---|---|---|---|
| F-16I Sufa | Elisra RWR[^sufa-at] ([../../../docs/f16i.md](../../../docs/f16i.md) §6) | Elisra's infrared warners[^sufa-at], named PAWS-2 in 2005[^du-paws] (second-hand); the 2025 suite's PAWS[^janes] | the launcher's radar symbol ("16", "35", a SAM's digit) in the launch circle | the MAW's warning: direction, time to impact and the missile's type, how finely open (§3) | none: the F-16's voice set has no missile call (§5) |
| F-16D Barak | the set is open; the dash-34's display is the nearest[^dash34] | none: an infrared missile warning is among the upgrades proposed in 2025 (avionics-plan.md B8) | as the Sufa | nothing: no system on the jet can sense it (inferred, §2) | none (§5) |
| F-35I Adir | the AN/ASQ-239 EW system: radar warning and threat identification[^asq239] | the DAS: missile detection and tracking, launch point detection[^das] | the launcher's radar on the TWD (the format's layout open) | the DAS's warning: direction; its type open | open |
| F-15I Ra'am | an Elisra suite (§6) | a missile approach warner in that suite, secondary sources only (§6) | the launcher's radar symbol (inferred, as every RWR) | the MAW's warning (inferred, as the Sufa's) | none: the F-15's voice set has no missile call (§5) |
| F-15C/D Baz | open in IAF service; the US F-15C carries the ALR-56C[^alr56] | open: no source names one (§6) | the launcher's radar symbol; an active radar missile itself as "M" (a simulator manual, §6) | nothing (inferred, §2) | none (§5) |

In short: a radar warning receiver names a radar-guided threat by the radar it hears, the launcher's; it cannot hear an
infrared missile. An infrared missile approach warner sees every missile's plume, whatever its seeker; it gives the
direction and the time to impact, and the Sufa's PAWS also "missile type". No public source shows a warning that
writes a missile's designation (AIM-120, R-73).

## 2. What a radar warning receiver can name

- An RWR detects and identifies radars: the ALR-56C's capabilities list "Detection and identification of modern
  search, acquisition, and tracking radars"[^alr56]. Its display names each by type: an aircraft's radar by the
  aircraft's number under a hat ("16" = F-16), a SAM's by its digit ("6" = SA-6), AAA by a letter in a box; a lethal
  one (a lock) in a square; "a circle around: a missile launch (it replaces the square)"[^dash34]. The MLU's ALR-69
  adds a red ML (missile launch) light flashing at 3 Hz with the symbol, and a launch tone[^mlu1].
- So the type an RWR gives for a launch is the launcher's radar, not the missile: "35" in a flashing circle says an
  F-35's radar is guiding a missile at the jet. The missile it guides follows from the launcher (inferred).
- An infrared-guided missile sends no radar signal. RWRs answered the radar-guided missiles; the infrared ones "give no
  warning of their presence prior to launch", and missile approach warners were built for them[^wp-maws]. So an RWR
  cannot hear an infrared missile's launch (inferred from how it works). A jet with an RWR and no MAW gets no warning of
  an infrared shot.
- An active radar missile's own seeker is a radar too. A simulator manual of the F-15C's ALR-56C shows it as an "M" in
  the inner ring[^dcs-f15] (secondary). The dash-34's F-16 symbol list has no such symbol[^dash34], and the Sufa's
  Elisra set's handling of it is open.

## 3. The Sufa's PAWS

- The F-16I was delivered with Elisra radar warning receivers and missile approach warners[^sufa-at]; in 2005 a
  defence site wrote that PAWS-2 "has already deployed with Israel's F-16Is"[^du-paws] (second-hand). The 2025
  contract adds an infrared missile warning and launch detection system to the jet[^janes]. That the warner the sim
  models is a PAWS rests on these: inferred.
- Janes describes PAWS (after its yearbook *C4ISR & Mission Systems: Air*): it works in the mid-infrared band and
  analyses infrared threat signatures, "providing the pilot with the direction, missile type, and time to
  impact"[^janes]. The article describes PAWS in general, not the F-16I's installation.
- Elbit, the maker: PAWS-2 "detects a wide variety of threats including SAMs, air-to-air missiles and MANPADS",
  "whether they employ active, passive or other types of seeker technology"; it gives "accurate launch locations for
  all types of missiles" and "missile time-to-Impact (TTI)"[^paws2]. The family "alert the aircrew with audio-visual
  warning signals" and "provides threat information to other EW and/or avionic systems for centralized
  display"[^paws].
- How finely "missile type" names a missile is open. The classes the maker lists (SAMs, air-to-air missiles, MANPADS)
  and the launch point it reports fit a class from where the missile came from: from the air an air-to-air missile,
  from the ground a SAM (inferred). A designation from the plume alone has no source.
- Where the pilot sees it: on the central EW display (the maker's "centralized display"; on the Sufa, inferred, the
  threat warning display). Its symbol, text and sound on the Sufa are open.

## 4. The Adir

- The AN/ASQ-239 integrates "radar warning, targeting support, and countermeasures"; it helps the pilot "identify,
  monitor, analyze, and respond to threats"[^asq239]. So its TWD names a radar by type as an RWR does (inferred).
- The DAS (AN/AAQ-37) gives "Missile detection and tracking" and "Launch point detection"; "It warns the pilot of
  incoming aircraft and missile threats"[^das]. A source on whether it names a type was not found: open. The same launch point allows the class of §3 (inferred).
- How the warning shows on the TWD and in the helmet, and its sound or voice: open (the helmet's graphics are not
  public, [../avionics-plan.md](../avionics-plan.md) H7).

## 5. Voice and tones

- The F-16's voice message system has no missile call: its words are PULL UP, ALTITUDE, WARNING, BINGO, CAUTION,
  LOCK, CHAFF FLARE / LOW / OUT, and in later software COUNTER, JAMMER, DATA, IFF
  ([../../../docs/real-betty.md](../../../docs/real-betty.md) §1). The launch is a tone of the RWR[^mlu1].
- The F-15's voice set in the sources has no missile call either (real-betty.md §1).
- The F-35's voice warnings: open (real-betty.md §1).
- The PAWS's "audio-visual warning signals"[^paws]: their sound on the Sufa is open.

## 6. The F-15s, for later

The F-15s do not fly in Modern IAF yet. This section is what their work will wire.

**F-15I Ra'am** ([../../../docs/f15i.md](../../../docs/f15i.md) §5 holds the sources):
- Delivered without the F-15E's US warning and jamming suite (TEWS: the ALR-56C warner, the ALQ-135 jammer); an Elisra
  suite in its place. Secondary sources name it SPS-2110, "which includes a missile approach warning system", with the
  SPS-3000 radar warning receiver. One encyclopedia page names an SPS-1000 RWR designed for the F-15I and later fitted
  to the F-16I[^sps1000] (second-hand).
- Elbit lists the F-15 among the PAWS family's platforms[^paws]; that the Ra'am's warner is a PAWS is inferred (the
  same maker and air force as the Sufa's).
- The crew's display (a scope, an MPD / MPCD page) and its symbols: open.
- So, inferred: its RWR names radar-guided threats by the launcher's radar, as §2; its MAW warns of every missile with
  the class of §3. Wiring: the aircraft definition's `"ews": {"maw": true}` and the shared rules of
  [../ews.md](../ews.md) §2 and §3.

**F-15C/D Baz:**
- The RWR in IAF service is open: no source names one. The US F-15C carries the ALR-56C[^alr56].
- The ALR-56C's display (TEWS), after two simulator manuals[^dcs-f15] ([../../../docs/real-mfd.md](../../../docs/real-mfd.md)
  "TEWS display"): emitters by alphanumeric type codes, an aircraft's with a hat; a launch as a flashing circle; "an
  active-radar missile shows as an M in the inner ring" (secondary).
- A missile approach warner on the Baz: open (no source names one). Without one, an infrared shot gives no warning
  (inferred, §2).
- Wiring, if the Baz flies: the threat display of [../ews.md](../ews.md) §2 on its TEWS page, no MAW. The active-radar
  "M" needs the missile's seeker state (`missile.rs`, the AIM-120's active seeker) on the threat display: not built.

[^sufa-at]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel" (Elisra radar warning receivers, missile
    approach warners): https://www.airforce-technology.com/projects/f-16i-soufa/
[^janes]: T. Rozouvan, "Elbit Systems to equip Israel's F-16Is with self-protection suite", Janes, 28 January 2025
    (PAWS after *Janes C4ISR & Mission Systems: Air*); checked 19 November 2026:
    https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite
[^du-paws]: Defense Update, "PAWS" (25 January 2005; "PAWS-2 systems are designed for fighter aircraft and has already
    deployed with Israel's F-16Is"); second-hand, the page refused automated access:
    https://defense-update.com/20050125_paws.html
[^paws2]: Elbit Systems, "PAWS-2" (product page), checked 19 November 2026:
    https://elbitsystems.com/air-space/airborne-self-protection/airborne-threat-warning-systems/paws-2
[^paws]: Elbit Systems, "PAWS Family" (product page; reference platforms include the F-15 and the F-16), checked
    19 November 2026: https://elbitsystems.com/air-space/airborne-self-protection/warning-systems/paws-family
[^wp-maws]: Wikipedia, "Missile approach warning system": https://en.wikipedia.org/wiki/Missile_approach_warning_system
[^dash34]: T.O. GR1F-16CJ-34-1-1, Hellenic AF F-16C/D Block 50 avionics and weapons delivery (dash-34), 1997, RWR
    pp. 1-197..1-203, figs. 1-132..1-136: https://falcon.blu3wolf.com/Docs/HAF-F16-34.pdf
[^mlu1]: Lockheed Martin, F-16 A/B MLU Production Tape M1 pilot's guide (16PR14341, 15 Nov 1998), the EWPI (ALR-69)
    fig. 7-3 p. 209: https://falcon.blu3wolf.com/Docs/MLU_M1.pdf
[^alr56]: BAE Systems, "AN/ALR-56 Radar Warning Receivers (RWR)" (the ALR-56C on the F-15, the ALR-56M on the F-16 and
    C-130J): https://www.baesystems.com/en/product/an-alr-56-radar-warning-receivers
[^dcs-f15]: Eagle Dynamics / Belsimtek, *DCS F-15C Flight Manual* (2014), a simulator manual: TEWS symbology figs.
    63–64, table 9-5, pp. 77–80:
    https://www.digitalcombatsimulator.com/upload/iblock/1ad/F-15C%20DCS%20Flaming%20Cliffs%20Flight%20Manual%20EN.pdf
[^asq239]: BAE Systems, "AN/ASQ-239 F-35 EW countermeasure system":
    https://www.baesystems.com/en/product/an-asq-239-f-35-ew-countermeasure-system
[^das]: F-35 Lightning II Joint Program Office, "DAS" (the functions: "Missile detection and tracking", "Launch point
    detection"; "It warns the pilot of incoming aircraft and missile threats"), checked 19 November 2026:
    https://www.jsf.mil/das
[^sps1000]: Citizendium, "Elisra SPS-1000" (a radar warning receiver first designed for the F-15I, later on the
    F-16I); second-hand, the page refused automated access: https://citizendium.org/wiki/Elisra_SPS-1000
