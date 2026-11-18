#import "src.typ": *

The F-35 is a "more electric" aircraft: electricity does work that hydraulics do in older jets, the flight controls included (@hydraulic). Its electrical system gives 270 V direct current for that heavy work, and 28 V direct current and 115 V alternating current for the rest#av[page 13].

The parts#av[page 13]:

- *One engine starter/generator.* It turns the engine in a start and is the jet's generator once the engine runs.
- *Two inverter/converter/controllers*, ICC 1 and ICC 2, which control the starter/generator and convert its power.
- *Batteries*, 28 V and 270 V.
- *The #term("IPP")*, which gives power on the ground before the engine runs and emergency power in flight (@engine).

=== Controls

#row("BATT") connects the batteries. #row("ICC1") and #row("ICC2") switch the two controllers. What the switches of this cockpit do in the real jet is inferred from their names.

#in-sim[
  - #key("Main power / battery") is the BATT switch. With BATT alone the lights work; the #term("PCD"), the standby display and the helmet's symbols come on once the IPP runs.
  - The avionics then test themselves: they are ready about 90 seconds after BATT.
  - *#term("Not modelled").* ICC1 and ICC2, which move and do nothing; the BATT switch's RESET position; electrical faults and the IPP's emergency power.
]
