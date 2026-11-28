#import "src.typ": *

=== Generator failures <emergency-electrical>
#state("part")

An electrical fault lights *#row("lamp_caution_elec_sys_0")* and one or more lights of the ELEC panel#fm[section III, "Electrical system failures", page 3-43].

- *One generator* (*#row("lamp_main_gen_0")* or *#row("lamp_stby_gen_0")*): the other one carries the jet. Press #row("CAUTION_RESET") to try a reset, and land as soon as practical#fm[section III, "Single generator failures (in flight)", pages 3-43 and 3-44].
- *Both generators:* the #term("EPU") starts by itself (*#row("lamp_epu_run_0")*) and powers the emergency buses; much of the avionics is lost. CAUTION RESET may bring a generator back. Check the attitude indicator for warning flags, and land as soon as possible, since the EPU runs on a limited store of fuel (@electrical)#fm[section III, "Main and standby generator failure (in flight)", pages 3-44 and 3-45; the reason given for the urgency is inferred].
- *#row("lamp_flcs_pmg_0"):* the flight controls' own generator has failed; they take power from the other sources. Land as soon as practical#fm[section III, "FLCS PMG failure", page 3-43].

#in-sim[
  - Damage to the generators takes the radar and the warning receiver; total damage also takes the weapons, the instruments and the #term("HUD"). The #term("DED")'s fault list and the TEST format show it. *MAIN GEN lights after damage to the main generator, MAIN GEN and STBY GEN after total damage, and #row("lamp_caution_elec_sys_0") with them.* With total damage #sym.arrow.r *the EPU starts by itself: EPU run and AIR light.*
  - A set failure of the main generator #sym.arrow.r *MAIN GEN and ELEC SYS light, GEN MAIN FAIL on the fault list; the standby generator keeps everything up.*
  - A set failure of both generators #sym.arrow.r *MAIN GEN, STBY GEN and ELEC SYS light and the displays go dark; the EPU starts by itself, EPU run and AIR light, and the displays come back while its hydrazine lasts* (10 minutes at low thrust).
  - The same with the EPU's automatic start lost #sym.arrow.r *EPU run and AIR stay dark, the displays stay dark.* #row("SW_EPU") to ON #sym.arrow.r *the EPU runs and the displays come back.*
  - #term("Not modelled"): the reset of a generator: ELEC CAUTION RESET leaves it failed.
]

=== Hydraulic failures <emergency-hydraulic>
#state("part")

The jet has two hydraulic systems, A and B (@hydraulic). A failure lights *#row("lamp_hyd_oil_press_0")* when either system falls below 1,000 psi#fm[section III, "Hydraulic malfunctions" and "Single hydraulic failure", page 3-123].

- *System A:* the flight controls work on B alone; the speedbrakes do not. Land as soon as practical, with smooth inputs and a straight-in approach.
- *System B:* the gear, the brakes and the nosewheel steering lose their normal supply. Lower the gear by the alternate way with the handle up (@emergency-alt-gear); brake once and steadily on the accumulators, which hold at least 75 seconds of braking; consider a cable.
- *Both:* *the controls go sluggish*. The EPU gives pressure to system A; set #row("SW_EPU") to ON if its run light is dark, and go on as for system B. If the pressure does not come back, or the controls stop answering: eject#fm[section III, "Dual hydraulic failure", page 3-124].

#in-sim[
  - Damage to the hydraulics #sym.arrow.r *HYD/OIL PRESS and #row("lamp_flcs_0") light, system A's gauge falls to zero, and the stick has a quarter of its authority.* Fly gently and land.
  - A set failure of system A #sym.arrow.r *HYD/OIL PRESS and #row("lamp_caution_flt_cont_sys_0") light, ISA ALL FAIL on the fault list, gauge A at zero; the speedbrakes stay where they are.* The flight controls work as before.
  - A set failure of system B #sym.arrow.r *the same lights, gauge B at zero; the gear handle leaves the gear where it is and the nose wheel turns freely.* #row("alt-gear") pulled #sym.arrow.r *the gear comes down.* The brakes work for 75 seconds of pressing in all.
  - #term("Not modelled"): a failure of both systems.
]

=== Flight control faults <emergency-flcs>
#state("part")

A fault of the #term("FLCS") (@flight-controls) shows as *#row("lamp_flcs_0")* or *#row("lamp_caution_flt_cont_sys_0")* with a line in the fault list. The pilot reads the fault, acknowledges it, does the fault's own procedure, which often ends in a reset with the FLCS RESET switch, and recalls the faults to see what stays#fm[section III, "FLCS failures", page 3-108]. *#row("lamp_dbu_on_0")* means the computers run their backup software; *#row("lamp_caution_le_flaps_0")* a fault of the leading-edge flaps. Each asks for gentle flying and a landing as soon as practical; the single procedures are on the manual's pages 3-108 to 3-116 and are not repeated here.

#in-sim[Total damage to the flight controls #sym.arrow.r *the FLCS light comes on and the surfaces stop: the stick does nothing.* Eject. *#row("lamp_caution_flt_cont_sys_0") lights with every fault of the fault list's FLCS class and with total damage.* #row("f-ack") #sym.arrow.r *the fault list's page leaves the PFLD and its FAULT caution and MASTER CAUTION go out*; pressed with nothing left to acknowledge #sym.arrow.r *the faults still active come back to the list*#fm[pages 1-146 and 1-147]. The autopilot's FLCS A/P FAIL and FLCS A/P DEGR are modelled (@flight-controls); #key("FLCS RESET") clears them. Not modelled: the other single faults, the backup software (its switch lights DBU ON only).]

=== Standby gains <emergency-stby-gains>
#state("part")

A second failure of the air data puts the #term("FLCS") on its standby gains: *the FLCS light, #row("lamp_stby_gains_0"), STBY GAIN and FLCS ADC FAIL on the fault list*. The gains are fixed, those of sea level at 600 kt with the gear handle up and 230 kt with it down, and the leading-edge flaps stay at 0° or 15°; the jet flies less well#fm[section III, "Air data malfunctions", page 3-108].

+ 1 g, with at most 12° angle of attack, at 240 to 650 kt with the gear up.
+ #row("SW_FLCS-RESET") to RESET.
+ Land as soon as practical. Stay above 240 kt until the gear is down.

#in-sim[Set standby gains #sym.arrow.r *the lights and lines above; the stick flies the jet on the fixed gains.* FLCS RESET does not bring the normal gains back.]

=== Fuel emergencies <emergency-fuel>
#state("part")

- *Fuel low.* *#row("lamp_caution_fwd_fuel_low_0")* or *#row("lamp_caution_aft_fuel_low_0")*: a reservoir tank is nearly empty (in the two-seat jet 250 lb forward, 400 lb aft), or its sensor has failed. The cause may be a leak, external fuel that did not transfer, an imbalance or long afterburner use. Cut the fuel flow to the least that flies the jet, avoid negative g, and land as soon as possible#fm[section III, "Fuel low", page 3-118].
- *FUEL in the HUD.* The word FUEL in the HUD also shows a low fuel state: the fuel has fallen below the #term("bingo fuel") the pilot set, and the voice says "Bingo"#fm[section I, "HUD FUEL low/bingo indication", page 1-74].
- *Fuel leak.* *The total falls faster than the engine burns*, or fuel is seen. Fly for range: without afterburner, faster and higher uses fuel that would be lost anyway#fm[section III, "Fuel leak", page 3-117].
- *Trapped external fuel.* *The external tanks stay full while the internal fuel falls*; a regular look at the tanks' quantities finds it. Cut the fuel flow. Check that #row("SW_AIR_REFUEL") is at CLOSE and #row("AirSource_knob") at NORM or DUMP. Set the cabin temperature to manual, which usually raises the air pressure that moves the fuel, and select the wing tanks first. Pitch the jet up and down a few times. Last, open AIR REFUEL for one second and close it (@air-refuelling). The fuel may take from 1 to 12 minutes to move. Until it does, only the fuselage fuel counts as usable#fm[section III, "Trapped external fuel", page 3-121].

#in-sim[
  - *FWD FUEL LOW* lights below 250 lb in the forward reservoir and *AFT FUEL LOW* below 400 lb in the aft one; the voice says "Bingo" at 1,000 lb and at 500 lb; *FUEL flashes on the HUD* below the #term("bingo fuel") you set.
  - A leak after a hit #sym.arrow.r *the fuel falls fast.* Pull the throttle back and land.
  - An imbalance, made with #row("SW_KNOB_ENG_FEED") at AFT or FWD, shows on the pointers at NORM; the same knob corrects it (@fuel).
  - Not modelled: fuel that does not transfer, a failed fuel flow proportioner.
]

=== Jettison <emergency-jettison>
#state("full")

#idx("Emergency jettison")Emergency jettison drops every store and rack except the air-to-air missiles in one press, unarmed, to make the jet light and clean: after an engine failure, on a take-off that will not climb, before a landing with damage. #row("EMER_JETT") is pressed; on the ground it works only with #row("SW_GND_JETT") at ENABLE, as a last resort#fm[section III, "Emergency jettison", page 3-108]. Selective jettison drops chosen stations from the stores page (@mfd).

#in-sim[#key("Emergency jettison") or the button #sym.arrow.r *the stores and racks fall; the missiles and the pods stay; the fuel in the tanks goes with them.* On the ground nothing is dropped unless #row("SW_GND_JETT") is at ENABLE#fm[figure 1-38, page 1-107].]

=== Canopy, cabin pressure and smoke <emergency-cockpit>
#state("part")

- *#row("lamp_canopy_0") in flight:* push the canopy handle outboard. If the canopy is lost, slow to 180 kt or less and lean forward behind the glareshield; at high speed the blast may leave only ejection#fm[section III, "Canopy loss/penetration in flight", page 3-38].
- *Cabin pressure lost or too hot:* oxygen to 100~%, below 25,000 ft and 500 kt, AIR SOURCE to OFF for 10 to 15 seconds and back to NORM#fm[section III, "Cockpit pressure/temperature malfunction", page 3-39].
- *Smoke or fumes:* any unknown smell is taken as toxic. Oxygen on, 100~% and EMER#fm[section III, "Smoke or fumes", page 3-131].

#in-sim[The CANOPY light shows a canopy that is open or not locked on the ground. With #row("AirSource_knob") at NORM the cabin altitude stays under 27,000 ft. At OFF, DUMP or RAM the cabin has the jet's own altitude #sym.arrow.r *#row("lamp_caution_cabin_press_0") lights above 27,000 ft.*]
