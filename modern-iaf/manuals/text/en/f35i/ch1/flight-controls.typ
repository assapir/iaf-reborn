#import "src.typ": *

The #jet.short is flown through a computer: the stick, the pedals and the throttle send electrical signals, and the flight control system moves the surfaces. The #row("side_stick") is an active stick: motors in it set the forces the hand feels#footnote[BAE Systems, "Active sticks: meeting the needs of tomorrow's pilots today", #link("https://www.baesystems.com/en/insight/active-sticks-meeting-the-needs-of-tomorrows-pilots-today"). #checked].

=== Control surfaces

The jet has horizontal tails, flaperons, two rudders and leading-edge flaps#av[page 13]. The computer uses them together:

- *Flaps.* The flaperons and the leading-edge flaps take their positions by themselves (inferred: the cockpit has no flap lever).
- *Speedbrake.* The jet has no speedbrake surface. To slow down, the computer deflects the other surfaces against each other#footnote[Code One magazine, an interview with the test pilot Jon Beesley, 2007: the jet "doesn't have a dedicated speed brake", #link("https://www.codeonemagazine.com/article.html?item_id=33"). #checked].

=== The limiters

The computer limits what the pilot can ask for: 9 g#card-a and an angle of attack of 50°#footnote[Second Line of Defense, "The F-35 and High Angle of Attack Flight Testing", November 2012: the jet was flown "to its 50 degree limit", #link("https://sldinfo.com/2012/11/the-f-35-and-high-angle-of-attack-flight-testing/"). #checked].

=== Automatic ground collision avoidance

The F-35A has a system that takes the controls and pulls the jet up when it is about to fly into the ground and the pilot does nothing#footnote[Lockheed Martin, "Life-Saving Anti-Collision Software Integrated into First F-35s Seven Years Ahead of Schedule", 24 July 2019, #link("https://news.lockheedmartin.com/2019-07-24-Life-Saving-Anti-Collision-Software-Integrated-into-First-F-35s-Seven-Years-Ahead-of-Schedule"). #checked]. That #row("AUTO_RECOVERY") is its switch is inferred.

=== Reset

#row("FCS_RESET") resets the flight control system after a fault (inferred from its name).

#in-sim[
  - *Limiters.* +9 and −3 g, and 50° angle of attack.
  - *Flaps.* They move by themselves: down with the gear handle down, up as the speed rises between 240 and 370 knots.
  - *Speedbrake.* #key("Speedbrakes open (hold)") opens it while held, and it stays where the key is let go; #key("Speedbrakes close") closes it.
  - *Autopilot.* #key("Autopilot: level / nav / off") steps through level flight, steering along the route, and off.
  - *Trim.* The sim trims roll only.
  - *#term("Not modelled").* Faults of the flight control system; FCS RESET, AUTO REC, #row("STICK_ACTIVE") and #row("THR_ACTIVE"), which move and do nothing; the automatic pull-up (the helmet shows a pull-up cue, @hmd).
]
