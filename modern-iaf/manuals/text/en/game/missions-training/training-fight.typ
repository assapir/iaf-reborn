#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Training fight")#idx("Aggressor")A training fight puts you against an aggressor: a Sufa flown by the computer with an instructor's tactics, callsign Red 1. Shots between the two jets are simulated, as in real training. The air-to-air #term("lesson")s fly it: the fight starts when you reach the training area, and after the lesson's last engagement Red 1 leaves the fight and you fly home. In the lesson against enemy types Red 1 is a MiG-29A.

=== The set-ups <training-fight-setups>

#idx("Training fight, set-ups")Each engagement starts in the air from a set-up. Both jets are put there, with their stores full.

#grid-table(
  (auto, auto, 1fr),
  ([Set-up], [You], [Red 1]),
  [Offensive], [3,000 ft behind Red 1, the same heading, 15,000 ft], [ahead of you],
  [Defensive], [ahead of Red 1, 15,000 ft], [3,000 ft behind you],
  [High aspect], [head-on, 6 km apart, passing side by side, 15,000 ft], [head-on],
  [BVR], [head-on, 40 nautical miles apart, 20,000 ft], [head-on],
)

=== Simulated shots <training-fight-shots>

#idx("Training fight, shots")A missile fired at the other jet flies unseen and hurts nothing. Neither jet can be damaged. When the missile bursts within its blast of the other jet, that jet is killed. Three gun hits on the other jet are a kill too. Chaff, flares and turning away defeat a simulated missile as they defeat a real one. A shot at anything else, a drone for example, is live with MASTER ARM at ARM. With MASTER ARM at SIMULATE your air-to-air missiles and the gun fire, and every shot is simulated.

You get no launch warning for a simulated missile: listen for the call.

=== The calls <training-fight-calls>

#idx("Training fight, calls")The calls come on the radio with a subtitle. Yours are said in your voice.

#grid-table(
  (auto, 1fr),
  ([Call], [When]),
  ["Kidon 1, Fox one", "Fox two", "Fox three"], [you fire a radar-guided, heat-seeking or active radar missile],
  ["Kidon 1, guns"], [the first round of your burst],
  ["Kidon 1, kill"], [your shot killed Red 1],
  ["Red 1, Fox two", "Red 1, guns", "Red 1, kill"], [the same for Red 1],
  ["Red 1, knock it off"], [the engagement ends],
)

A killed jet leaves the fight: Red 1 stops attacking you when you are killed, and flies away when it is killed.

=== Knock it off <training-fight-kio>

#idx("Knock it off")Red 1 calls "knock it off" 3 seconds after a kill, when the two jets are more than 20 km apart (BVR: 150 km), after 3 minutes (BVR: 5 minutes), or when either jet is below 5,000 ft above the ground. To end an engagement yourself, press #key("Training fight: knock it off"). The next set-up starts 6 seconds after the call.
