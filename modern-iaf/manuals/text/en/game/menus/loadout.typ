#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Loadout")#idx("Arming")On this screen you choose what the jet carries on the mission: its #term("loadout"). Open it from the briefing with #scr("tab_arming") or #scr("edit") (@briefing-go).

What each jet may carry on each #term("station"), and what each store is for, is in the jet's own manual: the #other("f16i", "stores"), the #other("f16d", "stores") and the #other("f35i", "stores").

#screen("loadout_f16i_inventory", [The Loadout screen of the Sufa.])

=== The parts of the screen <loadout-parts>

- *The jet,* in the middle, under the line "#scr-text("lo_seen_below")". You look at it from beneath, so its left wing is on the right of the screen. The Adir shows its weapon bays open.
- *The callouts,* in a column on each side of the jet: one for each station that takes a store. A callout shows the station's number and place (for example #scr("pos_inboard")), the store on it and the weight of that store with its rack. A line joins the callout to the station on the jet. A station with nothing on it has a dashed frame and reads #scr("arm_empty").
- *#scr("lo_loadouts"),* at one side: the mission's own loadout and the ones you saved (@loadout-saved).
- *#scr("takeoff_weight"),* at the other side: the weight, the wings' balance and three figures (@loadout-figures).
- *#scr("lo_stores"),* under the weight: every store this jet may carry. A greyed store comes in a later version.
- *The buttons* at the bottom: #scr("lo_reset"), #scr("lo_briefing") and #scr("fly").

=== To hang a store on a station <loadout-hang>

With the mouse:

+ Press the mouse button on a store under #scr("lo_stores") and hold it.
  #then[Every callout whose station takes this store gets a bright frame. The others dim.]
+ Drag the store onto a framed callout.
+ Let go of the mouse button.
  #then[The store hangs on the jet. The callout shows it, and the take-off weight changes. A store that was on the station goes back to #scr("lo_stores").]

With the keyboard or a gamepad:

+ Move the focus to a callout with #keycap("Tab") or the arrow keys.
+ Press #keycap("Enter").
  #then[The focus moves to the first store this station takes.]
+ Move to the store you want with the arrow keys.
+ Press #keycap("Enter").
  #then[The store hangs on the station.]

#keycap("Esc") leaves the callout as it was.

=== To move or take off a store <loadout-move>

- *To move a store,* drag it from its callout onto another callout.
- *To take a store off,* drag it from its callout back onto #scr("lo_stores"). With the keyboard, pick the callout with #keycap("Enter"), then choose #scr("arm_empty") at the top of the stores.

=== Racks <loadout-racks>

#idx("Racks")Some stations take several small bombs on one rack. When you hang such a bomb, the whole rack hangs, full. The callout shows a badge with the number of bombs, for example ×3. The weight counts every bomb and the rack.

To carry fewer bombs on a rack, click the badge.

#then[One bomb comes off at each click. After the last one the rack is full again.]

=== Mirror to the other wing <loadout-mirror>

#idx("Mirror to the other wing")A change touches the one station you made it on. The switch #scr("lo_mirror") makes each change fill the matching station of the other wing as well, when that station takes the store. Moving a store, taking it off and the rack's badge then act on both wings too.

The switch is off when the game starts. It keeps its position until you quit.

=== The weight and the figures <loadout-figures>

#grid-table(
  (auto, 1fr),
  ([Line], [What it shows]),
  [#scr("takeoff_weight")], [The jet's weight with its fuel and stores, in kilograms. Under it a bar and one line give the share of the jet's maximum take-off weight and the maximum itself.],
  [#scr("lo_left") to #scr("lo_right")], [The wings' balance: a marker on a track, in the middle when both wings carry the same weight. The sides are the pilot's own left and right. The line under it reads #scr("lo_balanced"), or names the heavier wing and by how many kilograms.],
  [#scr("fuel")], [The fuel on board: inside the jet and in the drop tanks you hung. Hang or take off a drop tank to change it.],
  [#scr("rounds")], [The rounds in the gun. The jet always carries its full count.],
  [#scr("lo_chaff_flares")], [The chaff and the flares on board. The jet always carries its full count.],
)

=== The mission's loadout and saved loadouts <loadout-saved>

#idx("Saved loadouts")The list #scr("lo_loadouts") holds:

- the mission's own loadout, marked #scr("lo_mission"): what the mission gives the jet;
- your saved loadouts for this jet, each marked #scr("lo_saved").

Each row lists its stores in short. The row that matches what is on the jet now is highlighted.

*To put a listed loadout on the jet,* select its row.

*To save the loadout that is on the jet:*

+ Select #scr("lo_save").
  #then[A name field opens with a name offered.]
+ Type a name of your own, or keep the one offered.
+ Press #keycap("Enter") or select #scr("save").
  #then[The loadout joins the list. A loadout saved under a name that exists replaces that one.]

*To delete a saved loadout,* select the × on its row and confirm with #scr("lo_delete").

*To go back to the mission's own loadout,* select #scr("lo_reset").

The game keeps your last loadout for each jet with your pilot (@pilots). The jet in the #scr("hangar") carries it too.

=== The rules of the screen <loadout-rules>

#idx("Loadout, refused")The screen refuses a loadout the jet could not use. It refuses it here, before the flight, and tells you why.

#grid-table(
  (1fr, 1.2fr, 1.2fr),
  ([What you did], [What the screen does], [What to do]),
  [You dropped a store on a station that does not take it.], [The callout shakes for a moment with its frame in the warning colour. The loadout stays as it was.], [Drop the store on a callout that gets a bright frame while you drag. The jet's stores section lists what each station takes.],
  [You hung a store that needs a pod, and the pod is not on the jet. A laser-guided bomb needs the Litening targeting pod.], [One line in the warning colour at the bottom names the store and the pod it needs. #scr("fly") and #scr("lo_save") are off. The briefing shows the same line.], [Hang the pod on its station, or take the store off.],
  [The stores bring the jet over its maximum take-off weight.], [The weight, its bar and the share of the maximum show in the warning colour. #scr("fly") is off.], [Take stores off until the weight is under the maximum.],
  [One wing is much heavier than the other.], [The balance marker and the line under it turn amber and name the heavier wing. #scr("fly") stays on.], [Hang the same weight on both wings, or fly with the uneven load. The jet's handling with stores is in its manual.],
  [You picked a greyed store.], [Nothing: a greyed store cannot be picked.], [Choose another store. The greyed store comes in a later version.],
)

#screen("loadout_f16i_need", [A bomb that needs a pod: the reason at the bottom, and Fly off.])

A loadout you saved before a rule existed still loads whole. The screen then shows the reason, and #scr("fly") stays off until the loadout meets the rule.

#note[The amber balance warning applies to the Sufa and the Barak. The Adir's track shows the difference between its wings without a warning.]

=== Leaving the screen <loadout-leave>

- #scr("lo_briefing") or #keycap("Esc") goes back to the briefing. Your loadout is kept.
- #scr("fly") starts the flight with the loadout on the jet (@loading).
