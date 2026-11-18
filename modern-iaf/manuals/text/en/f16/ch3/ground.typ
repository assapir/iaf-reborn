#import "src.typ": *

=== Hot start <emergency-hot-start>
#state("part")

#idx("Hot start, procedure")A #term("hot start") is an engine start in which the turbine's temperature passes its limit: #hot-limit on the #term("FTIT") indicator#fm[section III, "Hot start (ground)", page 3-26#if not sufa [: the figure of the manual's General Electric engine, the F110-GE-129; for the #jet.short's F110-GE-100 it is inferred]]. It matters because a few seconds above the limit damage the turbine. Its usual cause is fuel let in too early (@cold-start).

*You recognise it by* the *FTIT #if sufa [climbing fast through 750~°C] else [passing 750~°C with the #term("RPM") below 40~%]* during the start; the manual tells the pilot to expect a hot start then.

+ Throttle to OFF.
+ Watch the FTIT.
+ If it stays above 500~°C: #row("JFS") to START 2. The #term("JFS") turns the engine without fuel, and the air cools it. Go on until the FTIT reads 200~°C, or for four minutes, the JFS's limit on the ground.

*What follows:* the engine is inspected before the jet flies again (inferred). Moving the throttle early is always wrong on the ground. In the air the same early throttle is the right action: an air start opens the throttle while the engine still turns slowly (@emergency-airstart).

#in-sim[The throttle moved out of OFF below 20~% #term("RPM") #sym.arrow.r *the engine shuts down.* Start again from the JFS. #term("Not modelled"): the FTIT's rise, the damage, and cooling the engine with the JFS.]

=== Hung start and no start <emergency-hung-start>
#state("part")

In a hung start the *RPM stops rising below idle* while the *FTIT stays under its limit*. In a no start the engine does not light: *no rise of FTIT within #light-off seconds* of the throttle reaching idle#fm[section III, "Hung start/no start", page 3-26#if not sufa [: the figure of the manual's General Electric engine, the F110-GE-129; for the #jet.short's F110-GE-100 it is inferred]]. Fuel that does not burn collects in the engine, so neither is waited out.

+ Throttle to OFF.
+ Report it to the ground crew.

#in-sim[The throttle moved to idle with the engine not turning #sym.arrow.r *no start*; the starter moved with #row("MAIN_PWR") off #sym.arrow.r *nothing happens.* Not modelled: the hung start. The engine waits at 20~% RPM for the throttle as long as the JFS runs.]

=== Fire, overheat or fuel leak on the ground <emergency-ground-fire>
#state("none")

A fire of the engine or of the JFS on the ground is seen as flames or smoke, or told by the ground crew; with electrical power *#row("lamp_eng_fire_0") or #row("lamp_caution_overheat_0")* may light, and the FTIT may pass its limit#fm[section III, "Fire/overheat/fuel leak (ground)", page 3-26].

+ Throttle to OFF.
+ JFS to OFF.
+ #row("SW_MASTER_FUEL") to OFF.
+ If the fire goes on: leave the jet.

=== Leaving the jet on the ground <emergency-egress>
#state("none")

The fastest way out keeps the canopy: start it opening and get ready while it moves. With a fire or a risk of explosion, get ready first and open the canopy last, so that it protects you until then. Getting ready is releasing the parachute risers, the lap belt, the survival kit and the g-suit hose; the oxygen and radio leads pull apart by themselves. The canopy can still be jettisoned when it is part open#fm[section III, "Ground egress", page 3-29].

=== Brake failure <emergency-brakes>
#state("part")

The brakes can fail in three ways: one of two circuits (both brakes work but need far more pedal force), one or both brakes lost, or a leak in one brake#fm[section III, "Brake failure", pages 3-27 and 3-28]. You recognise it by *pedals that do not slow the jet*.

+ Release the pedals, then change the brake channel, and press again.
+ Steer with the nosewheel steering if the jet turns.
+ Lower the hook if the runway has a cable.
+ With no cable and no brakes: the parking brake, early and at the lowest speed you can. It may burst the tyres.

#in-sim[Damage to the brakes #sym.arrow.r *#key("Wheel brakes (hold)") and the speedbrake keys do nothing.* Not modelled: the brake channels, the anti-skid and its #row("lamp_caution_anti_skid_0") light, the hook and the parking brake.]

=== Hot brakes <emergency-hot-brakes>
#state("none")

Brakes that have absorbed a lot of energy, after an aborted take-off or a heavy landing, can set leaking hydraulic fluid on fire, and the wheels' fuse plugs may let the tyres down within 15 minutes of the stop. The pilot keeps the engine running until the fire crew is there and leaves the parking brake off#fm[section III, "Abort", page 3-34]. Normal braking technique is in @landing-roll.

=== Nosewheel steering failure <emergency-nws>
#state("none")

A steering fault at any speed can turn the jet sharply, burst a tyre or take it off the runway. Disengage the steering, check that #row("lamp_ar_nws_0") is out, and steer with the rudder and the brakes#fm[section III, "NWS failure/hardover", page 3-33].
