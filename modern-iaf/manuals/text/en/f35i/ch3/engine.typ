#import "src.typ": *

=== Engine fire <emergency-fire>
#state("part")

#idx("Engine fire")*You recognise it by #row("lamp_eng_fire_0")* and an ICAWS message. #open-proc

#in-sim[
  - A set fire #sym.arrow.r *ENG FIRE lights, on the panel and on the ICAWS format, the voice says "Warning"; the engine keeps running.* The throttle at minimum (a quarter of its travel or less) or OFF #sym.arrow.r *the fire goes out after 15 seconds.* Kept above it #sym.arrow.r *after two minutes the engine fails for good (ENGINE FAIL).* The minimum and the times are the sim's own (inferred from the F-16's procedure).
  - A fire after a hit #sym.arrow.r *ENG FIRE lights, on the panel and on the ICAWS format with ENGINE FAIL, the voice says "Warning", and the engine gives no thrust.*
  - #key("Extinguish engine fire") puts it out, once a flight. #sym.arrow.r *The light goes out and the thrust comes back.* The afterburner stays lost (*AB FAIL*). Pushing #row("lamp_eng_fire_0") does the same as the key.
]

=== Engine failure and fuel exhaustion <emergency-flameout>
#state("part")

With one engine, a failure makes the jet a glider. The public rules cover only the practice of it: the engine-out pattern is practised in the simulator alone, and its radio calls are "High key", "Low key", "Base key" and "Gear"#afi[paragraphs 7.12.4 and 7.12.5], which shows that the pattern has the same shape as other single-engine fighters' (inferred). The heights, the speeds and the restart in the air are open.

The fuel states that come before an empty tank are public: "minimum fuel" is declared at 1,800 lb or less, and "emergency fuel" at 1,200 lb or less#afi[paragraphs 3.20.4.1 and 3.20.4.2]. Fuel is dumped above 10,000 ft above the ground when the situation allows, and the dump switch is set back to normal before landing#afi[paragraph 7.14].

#in-sim[
  - An empty tank, a fire or a dead engine after a hit (*ENGINE FAIL*) #sym.arrow.r *no thrust.* Glide to a runway or eject.
  - An empty tank flames the engine out: *the #term("RPM") runs down*; in the air it settles where the airflow turns the engine, about 20~% at 250 kt. *The #term("IPP") keeps the displays up* as the jet's emergency power; on the ground below 52~% they go dark.
  - A leak after a hit (*FUEL LEAK*) #sym.arrow.r *the fuel falls fast.* The FUEL format marks #term("joker fuel") and bingo (@fuel).
  - A set flameout runs the engine down as an empty tank does.
  - With the windmilling RPM at 12~% or more (about 150 kt and faster) the engine start lights the engine again without the IPP's cranking (inferred: the F-16's rule). Slower, the start on the ground works in the air as it does there (@cold-start). #term("Not modelled"): the real restart's heights and speeds (open), and fuel dumping.
]
