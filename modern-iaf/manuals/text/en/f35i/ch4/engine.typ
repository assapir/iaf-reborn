#import "src.typ": *

The #jet.short's engine limits (temperatures, speeds, oil pressure, the limits of the start and of the #term("IPP")) are in the F-35's flight manual, which is not public: open. The engine's computer holds the engine inside its limits by itself (inferred: the cockpit has no engine control switch besides the start).

=== Fuel

- The rules of flying the F-35A set the fuel states by quantity: "minimum fuel" is declared at 1,800 lb or less and "emergency fuel" at 1,200 lb or less; the normal fuel at the final approach fix is 2,500 lb or more#afi[paragraphs 3.20.3 and 3.20.4].
- Fuel is dumped only above 10,000 ft above the ground#afi[paragraph 7.14].
- Limits of negative g, of fuel temperature and of the kinds of fuel: open.

#in-sim[
  - The start has its order and its waits (@emergency-start-order); nothing else limits the engine.
  - The displays show the engine's state. No limit can be passed, and none has a consequence.
  - #term("Not modelled"): every engine limit, the fuel dump.
]
