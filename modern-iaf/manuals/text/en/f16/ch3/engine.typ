#import "src.typ": *

For any engine fault the first move is the same: trade speed for height. Above 350 kt, pull up at 3 g into a 30° climb; below it, hold the height and let the speed fall to the one you want. Avoid turns unless a runway is within gliding distance: height is time#fm[section III, "Engine malfunctions", page 3-61].

#if not sufa [The signs and actions of this section are read from the manual's pages for the F100-PW-229, except where a footnote names its General Electric engine, the F110-GE-129. That the #jet.short's F110-GE-100 shows the same signs and takes the same actions is inferred.]

=== Engine fire <emergency-fire>
#state("part")

#idx("Engine fire")A fire in the engine bay can burn through to the fuel, the hydraulics and the flight controls around the engine. You recognise it by *#row("lamp_eng_fire_0")*, usually the first sign; the fuel quantity or flow may read oddly, and the #term("FTIT") is probably normal. Explosions, vibration or swinging engine gauges mean that the engine may fail at once#fm[section III, "Engine fire", page 3-61].

+ On take-off: abort, or climb (@emergency-takeoff-fire).
+ At a safe height: throttle to the least power that keeps the jet flying.
+ If the light goes out: press #row("FIRE_OHEAT_DETECT"), to learn whether the detector still works.
+ If the fire goes on: eject (@ejection). If its signs stop: land as soon as possible#fm[section III, "Engine fire", page 3-62].

The signs of a fire that goes on are the light staying on, flight control faults and the loss of a hydraulic system. A fire in the nozzle while in afterburner lights no warning, because it burns behind the detector; it is seen from outside, and leaving the afterburner puts it out in 30 to 45 seconds#fm[section III, "Engine fire", page 3-61]. The real jet has no extinguisher (inferred: the procedure names none).

#in-sim[
  - A fire comes from a hit only. #sym.arrow.r *ENG FIRE and OVERHEAT light, the voice says "Warning", the FTIT reads 900~°C, and the engine gives no thrust.*
  - #key("Extinguish engine fire") puts it out, once a flight. #sym.arrow.r *The lights go out and the thrust comes back.* The afterburner stays lost. This extinguisher is the sim's own.
  - #term("Not modelled"): a fire that spreads, and the nozzle fire.
]

=== OVERHEAT caution light <emergency-overheat>
#state("part")

*#row("lamp_caution_overheat_0")* means hot air in the engine bay, the air-conditioning bay, the main wheel wells or the #term("EPU")'s bay. Throttle to the least practical power; press FIRE & OHEAT DETECT to check the detector; if the light stays on, come down below 25,000 ft, slow below 500 kt and set #row("AirSource_knob") to RAM. Land as soon as possible#fm[section III, "OVERHEAT caution light", page 3-62].

#in-sim[The light comes on with an engine fire only. AIR SOURCE at OFF, or at RAM below 70 kt, lights #row("lamp_caution_equip_hot_0") and does nothing else.]

=== Engine failure and flameout <emergency-flameout>
#state("part")

#idx("Flameout")A flameout is an engine whose flame has gone out: fuel starvation or a mechanical failure. The jet becomes a glider, and its generators and hydraulic pumps stop with the engine. You recognise it by *falling FTIT and #term("RPM") falling below about 60~%*, no thrust and no answer to the throttle; *#row("lamp_engine_0") below 55~%*; *#row("lamp_main_gen_0") and #row("lamp_stby_gen_0") below 45~%*, when the EPU starts by itself and *#row("lamp_epu_run_0")* shows it#fm[section III, "Engine failure or flameout", page 3-70]. If the run light stays dark, #row("SW_EPU") goes to ON#fm[section III, "Engine malfunctions", page 3-61].

The actions are the air start, below, or the flameout landing (@emergency-flameout-landing). Below 2,000 ft above the ground with no thrust and no runway in reach, eject#fm[section III, "Airstarts", page 3-79].

#in-sim[
  - An empty tank, a fire or a dead engine after a hit #sym.arrow.r *no thrust.* After a hit *ENGINE lights and the voice says "Warning".*
  - With an empty tank the RPM gauge stays near idle and the generators stay on line: the run-down is not modelled there. #key("Throttle OFF (engine shutdown)") in the air runs the engine down truly: *below 52~% the displays go dark and MAIN GEN, STBY GEN and #row("lamp_caution_elec_sys_0") light.*
  - Not modelled: the EPU. Its switch moves, its lights come on in the lamp test only, and the flight controls keep working without it.
]

=== Air start <emergency-airstart>
#state("part")

#idx("Air start")An air start lights the engine again in flight. It is tried at once, before any glide for range, unless it is plainly impossible (no fuel, a seized engine): the RPM falls with time, and a slow engine is hard to light#fm[section III, "Airstarts", page 3-79].

+ Throttle to OFF, then to midrange. This is the early throttle that is wrong on the ground (@emergency-hot-start): in the air the airflow through the engine comes from the jet's speed.
+ Speed: above 30,000 ft dive at 400 kt; below it hold about 250 kt.
+ Below 20,000 ft and below 400 kt: #row("JFS") to START 2. The #term("JFS") helps to turn the engine; above 20,000 ft it is not allowed, since it is unlikely to start and empties its accumulators.
+ Jettison the stores if needed.
+ No light, a #term("hot start") or a hung start: throttle to OFF, the engine's secondary control (ENG CONT at SEC) below 30,000 ft, and throttle to midrange again#fm[section III, "Airstart procedures", page 3-80#if not sufa [; the steps read here are the Pratt & Whitney engine's. The manual gives its General Electric engine, the F110-GE-129, an air start of its own on pages 3-96 to 3-98, which differs in detail: it selects SEC when the RPM keeps falling below 50~%, and waits for the FTIT to fall below 700~°C before the throttle is advanced again. The procedure of the #jet.short's F110-GE-100 is open]].
+ When the engine runs: JFS off, #row("CAUTION_RESET") and check the generator lights out, EPU switch to OFF and back to NORM#fm[section III, "Airstart procedures", page 3-98].

With #row("lamp_jfs_run_0") on, the speed may come down to the best glide (about 200 kt, more with weight)#fm[section III, "Airstart procedures", page 3-80].

#in-sim[The start on the ground works in the air as it does there: with the RPM under 20~%, JFS to START 2, and the throttle to idle at 20~%. Not modelled: the windmilling engine, the speeds and heights of the real air start, SEC.]
