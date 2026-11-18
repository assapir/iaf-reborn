#import "src.typ": *

=== Engine fire <emergency-fire>
#state("part")

#idx("Engine fire")*You recognise it by #row("lamp_eng_fire_0")* and an ICAWS message. #open-proc

#in-sim[
  - A fire comes from a hit only. #sym.arrow.r *ENG FIRE lights, on the panel and on the ICAWS format with ENGINE FAIL, the voice says "Warning", and the engine gives no thrust.*
  - #key("Extinguish engine fire") puts it out, once a flight. #sym.arrow.r *The light goes out and the thrust comes back.* The afterburner stays lost (*AB FAIL*). Pushing the light itself does nothing.
]

=== Engine failure and fuel exhaustion <emergency-flameout>
#state("part")

With one engine, a failure makes the jet a glider. The public rules cover only the practice of it: the engine-out pattern is practised in the simulator alone, and its radio calls are "High key", "Low key", "Base key" and "Gear"#afi[paragraph 7.12], which shows that the pattern has the same shape as other single-engine fighters' (inferred). The heights, the speeds and the restart in the air are open.

The fuel states that come before an empty tank are public: "minimum fuel" is declared at 1,800 lb or less, and "emergency fuel" at 1,200 lb or less#afi[paragraphs 3.20.4.1 and 3.20.4.2]. Fuel is dumped only above 10,000 ft above the ground, and the dump switch is set back to normal before landing#afi[paragraph 7.14].

#in-sim[
  - An empty tank, a fire or a dead engine after a hit (*ENGINE FAIL*) #sym.arrow.r *no thrust.* Glide to a runway or eject.
  - A leak after a hit (*FUEL LEAK*) #sym.arrow.r *the fuel falls fast.* The FUEL format marks #term("joker fuel") and bingo (@fuel).
  - The start on the ground works in the air as it does there (@cold-start). #term("Not modelled"): the real restart, and fuel dumping.
]
