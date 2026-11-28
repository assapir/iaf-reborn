#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Jets")#idx("Squadrons")The game flies three jets. Each belongs to a squadron and flies from that squadron's home base, so choosing a jet also chooses the base its missions start from. The air bases are described in @airbases.

=== The jets <hangar-jets>

#grid-table(
  (auto, auto, auto, 1fr),
  ([Jet], [Squadron], [Base], [Its manual]),
  [F-16I #scr("sufa")#idx("Sufa")], [201 Squadron, "The One"], [#scr("base_ramon")], [#other("f16i", "description")],
  [F-16D #scr("barak")#idx("Barak")], [109 Squadron, "The Valley"], [#scr("base_ramat_david")], [#other("f16d", "description")],
  [F-35I #scr("adir")#idx("Adir")], [116 Squadron, "Lions of the South"], [#scr("base_nevatim")], [#other("f35i", "description")],
)

Two more jets stand in the list, greyed. They come in a later version; until then they cannot be picked.

#grid-table(
  (auto, auto, 1fr),
  ([Jet], [Squadron], [Base]),
  [F-15I #scr("raam")], [69 Squadron], [#scr("base_hatzerim")],
  [F-15C #scr("baz")], [133 Squadron], [#scr("base_tel_nof")],
)

=== Choosing a jet <hangar-choose>

#idx("Jet, choosing")
+ On the #term("Hangar"), look under #scr("aircraft").
  #then[Each row shows a jet's full name, its squadron's number and its base.]
+ Select a jet's row, or move to it with the arrow keys and press #keycap("Enter").
  #then[The jet stands in the middle of the screen, carrying its #term("loadout"). The card shows its #scr("squadron_l"), its #scr("base_l") and its #scr("tail_number"), and your last flight on it.]
+ Select #scr("fly").
  #then[The #scr("missions") screen opens for that jet (@mission-list).]

The game remembers the jet. The next start opens the Hangar with it.

=== What the choice changes <hangar-effect>

- *The training and the missions.* Each jet has its own training course and its own missions, from its own base. The #scr("missions") screen shows the picked jet's only, and counts only them in its progress.
- *The loadout.* The stores under the jet in the Hangar are the loadout you last set for it, or the missions' own when you set none (@loadout).
- *The cockpit and the procedures.* Each jet has its own cockpit and its own checklist. They are in the jet's flight manual (@manuals).

The F-16I and the F-16D share most of their cockpit and procedures; the F-35I differs throughout.
