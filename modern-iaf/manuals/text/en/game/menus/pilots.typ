#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Pilot")A pilot is your profile in the game: a name, a nickname, a picture and a log of every flight. The game can hold several pilots; one of them is the active pilot, and every flight goes into that pilot's log. A pilot also keeps its own loadouts for each jet (@loadout).

=== The Pilot screen <pilots-screen>

Select the pilot in the #term("Hangar")'s top bar to open the #scr("pilot") screen.

#screen("pilot", [The #scr("pilot") screen: the profile and the #scr("logbook").])

#grid-table(
  (auto, 1fr),
  ([Part], [What it does]),
  [#scr("pilot_name")], [The pilot's full name. A pilot needs a name to be saved.],
  [#scr("pilot_nickname")], [The short name that every screen's top bar shows. Without one the screens show the name.],
  [#scr("enemy_skill")], [How well the enemy flies and fights: #scr("skill_0"), #scr("skill_1") or #scr("skill_2"). It sets how fast the enemy's crews react, how well they aim and from how far they launch. Your flight and every friendly flight fly the same at every level. A pilot who never picked has #scr("skill_1").],
  [The picture], [A frame in the shape of an identity photo. Without a picture it shows the name's initials.],
  [#scr("choose_picture")], [Opens the system's file dialog to pick a picture file. A click on the frame does the same. The picture is cut to fill the frame.],
  [#scr("logbook")], [For each jet flown, the one with the most flight time first: its flight time, its flights, how many passed and failed, and the same for each mission flown on it. A pilot without flights reads #scr("no_flights")],
  [#scr("combat")], [Once you have flown combat: four totals of every flight. #scr("combat_air_kills"), with how many were shared; #scr("combat_ground"); #scr("combat_hits") of your missiles and bombs out of those released; #scr("combat_lost"), yours and the flight's other jets together (@pilots-combat).],
  [#scr("pilot_log")], [Opens the #term("pilot log") (@pilots-log).],
  [#scr("combat_more")], [Opens the combat statistics of every flight (@pilots-combat). Shown once you have flown combat.],
  [#scr("reset_log")], [Deletes the pilot's flights (@pilots-reset). Greyed while the pilot has no flights.],
  [#scr("delete_profile")], [Deletes the pilot (@pilots-delete).],
  [#scr("other_pilots")], [Opens the list of pilots (@pilots-change).],
  [#scr("back")], [Goes back to the Hangar. #keycap("Esc") does the same.],
  [#scr("save")], [Stores the name, the nickname, the picture and the enemy's skill, and opens the Hangar.],
)

=== Changing the name, the nickname or the picture <pilots-edit>

#idx("Pilot, name and picture")
+ Type the new text in #scr("pilot_name") or #scr("pilot_nickname"), or select #scr("choose_picture") and pick a file.
  #then[The screen shows the change. Nothing is stored yet.]
+ Select #scr("save").
  #then[The change is stored and the Hangar opens.]

When you leave the screen with a change that is not saved, the game asks #scr("discard_title") #scr("discard") drops the change; #scr("keep_editing") goes back to the screen.

=== Creating the first pilot <pilots-first>

On the first start the game opens the screen #scr("first_pilot") before the Hangar: the Pilot screen with #scr("save") only. The steps are in @start-game-first.

=== A new pilot and changing pilot <pilots-change>

#idx("Pilot, new")#idx("Pilot, change")
+ On the #scr("pilot") screen, select #scr("other_pilots").
  #then[The #scr("pilots") screen lists every pilot with its picture or initials, its nickname and its name. The active one is marked #scr("current").]
+ To fly as another pilot, select that pilot.
  #then[That pilot is active and the Hangar opens.]
+ To make a pilot, select #scr("new_pilot"), fill in the empty Pilot screen and select #scr("save").
  #then[The new pilot is stored, is active, and the Hangar opens.]

#screen("pilots", [The #scr("pilots") screen.], width: 70%)

=== Resetting the log <pilots-reset>

#idx("Pilot log, reset")
#caution[Resetting the log deletes every flight and #term("debrief") of the pilot. #scr-text("reset_sure_text") The name, the nickname and the picture stay. To keep a flight's recording, export it from its debrief first (@debrief).]

+ On the #scr("pilot") screen, select #scr("reset_log").
  #then[The game asks #scr("reset_title"), with #scr("cancel") picked.]
+ Select #scr("reset").
  #then[The game asks a second time: #scr("reset_sure_title")]
+ Select #scr("reset").
  #then[The pilot's log is empty.]

#scr("cancel") or #keycap("Esc") at either question leaves the log as it is.

#screen("pilot_reset", [The first of the two questions before the log is reset.], width: 70%)

=== Deleting the profile <pilots-delete>

#idx("Pilot, delete")
#caution[Deleting the profile deletes the pilot whole: the name, the nickname, the picture, every flight and debrief, and the pilot's loadouts. #scr-text("delete_sure_text")]

+ On the #scr("pilot") screen, select #scr("delete_profile").
  #then[The game asks #scr("delete_title"), with #scr("cancel") picked.]
+ Select #scr("delete").
  #then[The game asks a second time: #scr("delete_sure_title")]
+ Select #scr("delete").
  #then[The pilot is gone. The list of pilots opens; when no pilot is left, the screen #scr("first_pilot") opens.]

=== The pilot log <pilots-log>

#idx("Pilot log")The #term("Pilot log") lists every flight of the active pilot, the newest first. Open it with #scr("pilot_log") on the #scr("pilot") screen, or with the same button on a debrief.

#screen("log", [The #scr("pilot_log").])

#grid-table(
  (auto, 1fr),
  ([Column], [What it shows]),
  [#scr("date")], [The day and the time of the flight.],
  [#scr("mission")], [The mission flown.],
  [#scr("plane_flown")], [The jet flown.],
  [#scr("result")], [#scr("pass") or #scr("fail") (@scoring).],
)

Two filters stand over the list:

- *The jet.* #scr("all_jets"), or one of the jets the pilot has flown.
- *The mission.* #scr("all_missions"), or one of the missions flown. With a jet picked, the list offers that jet's missions only.

Select a row to open the flight's debrief (@debrief). #scr("back") or #keycap("Esc") goes back to the #scr("pilot") screen.

=== Combat statistics <pilots-combat>

#idx("Combat statistics")#idx("Kills")Every flight counts what you did in combat: the aircraft you shot down, the ground targets you destroyed, each weapon you released and how many hit, and the jets lost. #scr("combat_more") on the #scr("pilot") screen shows every flight's; the same button on a debrief shows that flight's (@debrief).

#screen("more_stats", [#scr("combat_more") of every flight.])

#grid-table(
  (auto, 1fr),
  ([Part], [What it shows]),
  [#scr("combat_kills_by_type")], [The aircraft shot down, by type. A kill is shared when another jet of your side hit it too, or when a jet of your side finished an aircraft you hit; the chip gives how many were shared.],
  [#scr("combat_ground_by_type")], [The ground targets destroyed, by type.],
  [#scr("combat_weapons")], [Each weapon you released and how many hit an enemy: #scr("combat_missiles") (#scr("combat_launched")), #scr("combat_bombs") (#scr("combat_dropped")) and the #scr("combat_gun")'s rounds (#scr("combat_rounds")).],
  [#scr("combat_losses")], [The jets lost, yours and the flight's other jets together, by what brought them down; how many of them were the flight's other jets; and the ejections. No jet is named.],
  [#scr("combat_flights")], [From the #scr("pilot") screen only: each flight with combat, the newest first, with its kills, targets and jets lost.],
)

#scr("back") or #keycap("Esc") goes back to the screen it was opened from. A flight from before this count has none.

=== Taking your data to another computer <pilots-export>

#idx("Export")The Pilot screen and the pilot log have no export of their own. Two other screens write files that you can keep or move:

- A debrief's #scr("export_flight") writes that flight's recording to a file (@debrief).
- The Settings' #scr("export_settings") and #scr("import_settings") write and read the settings (@settings-file). The pilots stay on the computer they were made on.
