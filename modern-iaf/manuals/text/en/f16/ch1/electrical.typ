#import "src.typ": *

The real jet has four sources of electrical power#fm[pages 1-82 and 1-83]:

- *The main generator*, 60 kVA, driven by the engine.
- *The standby generator*, 10 kVA, on the same engine gearbox. It is the backup of the main generator. A small generator built into it, the #term("FLCS") PMG, powers the flight control computer.
- *The #term("EPU") generator*, 5 kVA, for when both others are lost (@hydraulic).
- *The aircraft battery*, which powers the start and, as the last source, the flight control computer.

=== Controls and lights

#row("MAIN_PWR") has three positions#fm[figure 1-30, page 1-87]: OFF; BATT, which connects the battery alone; and MAIN PWR, which also lets the generators on line once the engine turns them.

The lights of the ELEC panel are amber and each names what has failed or is not on line#fm[figure 1-30, pages 1-88 and 1-89]: #row("lamp_main_gen_0"), #row("lamp_stby_gen_0"), #row("lamp_flcs_pmg_0"), #row("lamp_epu_gen_0"), #row("lamp_epu_pmg_0"), and three for the battery: #row("lamp_to_flcs_0") (the battery is feeding the flight controls), #row("lamp_flcs_rly_0") and #row("lamp_flcs_fail_0"). Any of them also lights the #row("lamp_caution_elec_sys_0") caution. #row("CAUTION_RESET") puts the caution out and resets a tripped generator#fm[figure 1-30, page 1-89].

With the engine off, MAIN GEN and STBY GEN are on, as no generator turns (inferred). In flight either light means a lost generator; the procedure is in @emergency-systems.

#in-sim[
  The sim has three states of power:
  #table(
    columns: (auto, 1fr),
    stroke: none,
    inset: (x: 6pt, y: 3.5pt),
    fill: (_, y) => if calc.even(y) { paper },
    [MAIN PWR at OFF (#key("Main power / battery"))], [Everything is dark.],
    [BATT, or MAIN PWR before the generator is on line], [The lights work and the #term("INS") can align. The displays are dark.],
    [The generator on line: 52~% #term("RPM") in the start, and 3 seconds], [The #term("MFD")s, the #term("DED"), the EHSI, the threat warning display and the exterior lights have power. The #term("HUD") also needs #row("AVIONICS_MMC").],
  )
  - #sym.arrow.r *MAIN GEN and STBY GEN are on* until the generator is on line. *FLCS PMG and FLCS RLY are on* until the #term("JFS") turns the engine. *TO FLCS is on* while the engine is below 44~% in a start or a shutdown. *ELEC SYS is on* with any of them; CAUTION RESET acknowledges it. *MAIN GEN lights after damage to the main generator, MAIN GEN and STBY GEN after total damage* (@emergency-systems).
  - The engine gauges' needles move without electrical power.
  - *#term("Not modelled").* The standby generator and the EPU as separate sources, bus failures; ACFT BATT FAIL lights in the lamp test only. *EPU GEN and EPU PMG light while the EPU is commanded and not running* (@hydraulic; inferred).
]
