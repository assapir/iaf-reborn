#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Loading screen")After #scr("fly") the game prepares the flight and shows the loading screen. It shows the mission's title, the base, a progress bar and, under the bar, the step under way.

=== The steps <loading-steps>

#screen("loading", [The loading screen.], width: 60%)

The steps come in this order:

#grid-table(
  (auto, 1fr),
  ([Step], [What the game prepares]),
  [#scr("loading_cockpit")], [The mission itself: where you start and which jet you fly.],
  [#scr("loading_scenery")], [The buildings' and trees' materials, the sounds and the radio.],
  [#scr("loading_effects")], [Explosions, smoke and the jet's damage.],
  [#scr("loading_flight_model")], [The flight model of your jet.],
  [#scr("loading_jet")], [The jet's outside model.],
  [#scr("loading_jet_cockpit")], [The cockpit and the pilot's body.],
  [#scr("loading_jet_weapons")], [The stores on the jet, the views, the displays.],
  [#scr("loading_terrain")], [The ground near your jet at full detail.],
  [#scr("loading_models")], [The models of the mission's other units.],
  [#scr("loading_views")], [The outside view and the last of the scenery.],
)

The bar moves forward from step to step. When it is full, the flight starts at once: you sit in the cockpit and the clock runs.

=== A slow first start <loading-slow>

#idx("First start, slow")The first flight after you install or update the game takes longer to load. The game prepares its graphics for your computer then, once, part by part. The bar may stand still for some seconds inside a step. During such a wait the screen adds this line under the step:

#scr-text("loading_slow")

The next start is quick: the game keeps what it prepared.

#note[The game watches its own loading. When a step makes no progress for 30 seconds, the game stops and opens the #term("crash page") (@crash-page), which names the step.]

The ground near the base starts to load while you read the briefing, so a flight started after some seconds on the briefing loads faster.
