#import "src.typ": *

=== Generator failures <emergency-electrical>
#state("part")

An electrical fault lights *#row("lamp_caution_elec_sys_0")* and one or more lights of the ELEC panel#fm[section III, "Electrical system failures", page 3-43].

- *One generator* (*#row("lamp_main_gen_0")* or *#row("lamp_stby_gen_0")*): the other one carries the jet. Press #row("CAUTION_RESET") to try a reset, and land as soon as practical#fm[section III, "Single generator failures (in flight)", pages 3-43 and 3-44].
- *Both generators:* the #term("EPU") starts by itself (*#row("lamp_epu_run_0")*) and powers the emergency buses; much of the avionics is lost. CAUTION RESET may bring a generator back. Check the attitude indicator for warning flags, switch off what is not needed, and land as soon as possible, since the EPU runs on a limited store of fuel (@electrical)#fm[section III, "Main and standby generator failure (in flight)", pages 3-44 and 3-45; the reason given for the urgency is inferred].
- *#row("lamp_flcs_pmg_0"):* the flight controls' own generator has failed; they take power from the other sources. Land as soon as practical#fm[section III, "FLCS PMG failure", page 3-43].

#in-sim[Damage to the generators takes the radar and the warning receiver; total damage also takes the weapons, the instruments and the #term("HUD"). The #term("DED")'s fault list and the TEST format show it. The ELEC panel's lights follow the start and the shutdown only, so they stay dark after such damage. #term("Not modelled"): the EPU, the reset of a generator.]

=== Hydraulic failures <emergency-hydraulic>
#state("part")

The jet has two hydraulic systems, A and B (@hydraulic). A failure lights *#row("lamp_hyd_oil_press_0")* when either system falls below 1,000 psi#fm[section III, "Hydraulic malfunctions", page 3-123].

- *System A:* the flight controls work on B alone; the speedbrakes do not. Land as soon as practical, with smooth inputs and a straight-in approach.
- *System B:* the gear, the brakes and the nosewheel steering lose their normal supply. Lower the gear by the alternate way with the handle up (@emergency-alt-gear); brake once and steadily on the accumulators, which hold at least 75 seconds of braking; consider a cable.
- *Both:* *the controls go sluggish*. The EPU gives pressure to system A; set #row("SW_EPU") to ON if its run light is dark, and go on as for system B. If the pressure does not come back, or the controls stop answering: eject#fm[section III, "Dual hydraulic failure", page 3-124].

#in-sim[Damage to the hydraulics #sym.arrow.r *HYD/OIL PRESS and #row("lamp_flcs_0") light, system A's gauge falls to zero, and the stick has a quarter of its authority.* Fly gently and land. Not modelled: a failure of system B and its effect on the gear and brakes.]

=== Flight control faults <emergency-flcs>
#state("part")

A fault of the #term("FLCS") (@flight-controls) shows as *#row("lamp_flcs_0")* or *#row("lamp_caution_flt_cont_sys_0")* with a line in the fault list. The pilot reads the fault, acknowledges it, does the fault's own procedure, which often ends in a reset with the FLCS RESET switch, and recalls the faults to see what stays#fm[section III, "FLCS failures", page 3-108]. *#row("lamp_dbu_on_0")* means the computers run their backup software; *#row("lamp_caution_le_flaps_0")* a fault of the leading-edge flaps. Each asks for gentle flying and a landing as soon as practical; the single procedures are on the manual's pages 3-108 to 3-116 and are not repeated here.

#in-sim[Total damage to the flight controls #sym.arrow.r *the FLCS light comes on and the surfaces stop: the stick does nothing.* Eject. Not modelled: single faults, the reset, the backup software (its switch lights DBU ON only).]

=== Fuel emergencies <emergency-fuel>
#state("part")

- *Fuel low.* *#row("lamp_caution_fwd_fuel_low_0")* or *#row("lamp_caution_aft_fuel_low_0")*: a reservoir tank is nearly empty (in the two-seat jet 250 lb forward, 400 lb aft), or its sensor has failed. The cause may be a leak, external fuel that did not transfer, an imbalance or long afterburner use. Cut the fuel flow to the least that flies the jet, avoid negative g, and land as soon as possible#fm[section III, "Fuel low", page 3-118].
- *FUEL in the HUD.* The word FUEL in the HUD also shows a low fuel state: the fuel has fallen below the #term("bingo fuel") the pilot set, and the voice says "Bingo"#fm[section I, "HUD FUEL low/bingo indication", page 1-74].
- *Fuel leak.* *The total falls faster than the engine burns*, or fuel is seen. Fly for range: without afterburner, faster and higher uses fuel that would be lost anyway#fm[section III, "Fuel leak", page 3-117].
- *Trapped external fuel.* *The external tanks stay full while the internal fuel falls*; a regular look at the tanks' quantities finds it. Cut the fuel flow. Check that #row("SW_AIR_REFUEL") is at CLOSE and #row("AirSource_knob") at NORM. Set the cabin temperature to manual, which usually raises the air pressure that moves the fuel, and select the wing tanks first. Pitch the jet up and down a few times. Last, open AIR REFUEL for one second and close it: that takes the pressure off the tanks and builds it again (@air-refuelling). The fuel may take from 1 to 12 minutes to move. Until it does, only the fuselage fuel counts as usable#fm[section III, "Trapped external fuel", page 3-121].

#in-sim[
  - *FWD FUEL LOW* lights below 800 lb of total fuel and *AFT FUEL LOW* below 500 lb; the voice says "Bingo" at 1,000 lb and at 500 lb; *FUEL flashes on the HUD* below the #term("bingo fuel") you set.
  - A leak after a hit #sym.arrow.r *the fuel falls fast.* Pull the throttle back and land.
  - Not modelled: fuel that does not transfer, imbalance, the reservoirs as separate tanks.
]

=== Jettison <emergency-jettison>
#state("full")

#idx("Emergency jettison")Emergency jettison drops every store and rack except the air-to-air missiles in one press, unarmed, to make the jet light and clean: after an engine failure, on a take-off that will not climb, before a landing with damage. #row("EMER_JETT") is pressed; on the ground it works only with #row("SW_GND_JETT") at ENABLE, as a last resort#fm[section III, "Emergency jettison", page 3-108]. Selective jettison drops chosen stations from the stores page (@mfd).

#in-sim[#key("Emergency jettison") or the button #sym.arrow.r *the stores and racks fall; the missiles and the pods stay; the fuel in the tanks goes with them.* On the ground nothing is dropped; GND JETT ENABLE moves only.]

=== Canopy, cabin pressure and smoke <emergency-cockpit>
#state("none")

- *#row("lamp_canopy_0") in flight:* push the canopy handle outboard. If the canopy is lost, slow to 180 kt or less and lean forward behind the glareshield; at high speed the blast may leave only ejection#fm[section III, "Canopy loss/penetration in flight", page 3-38].
- *Cabin pressure lost or too hot:* oxygen to 100~%, below 25,000 ft and 500 kt, AIR SOURCE to OFF for 10 to 15 seconds and back to NORM#fm[section III, "Cockpit pressure/temperature malfunction", page 3-39].
- *Smoke or fumes:* any unknown smell is taken as toxic. Oxygen on, 100~% and EMER#fm[section III, "Smoke or fumes", page 3-131].

#in-sim[The CANOPY light shows an open canopy on the ground. #row("lamp_caution_cabin_press_0") is wired to the cabin altitude, which stays under its threshold in flight.]
