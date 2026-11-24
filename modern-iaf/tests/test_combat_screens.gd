# The combat logbook on the screens (modern-iaf/docs/front-end.md §3.2), headless, in English and Hebrew: sorties
# stored with their combat records (IafPilotLog.log_sortie) beside the fixture's training flights. The Pilot screen's
# logbook: the four totals of every flight and More stats beside Pilot log; More stats: the kills and the ground targets
# by type, the weapons in their groups (each with its verb), the jets lost by cause, the combat flights; Back to the
# Pilot screen. A combat flight's debrief: its four totals on the sheet and More stats in the footer, that flight's
# page and Back to the debrief; a debrief of a flight without combat shows neither. A pilot with no combat: no block.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_combat_screens.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Two combat flights: a four-ship (two MiG-29 kills, one shared; Kidon 1-3 lost to a SAM) and a range (two T-72s).
const FOUR := {
	"kills": {"mig29a": 2},
	"shared": {"mig29a": 1},
	"weapons":
	{
		"AIM-120": {"fired": 2, "hits": 1},
		"PYTH-5": {"fired": 1, "hits": 1},
		"20 MM": {"fired": 180, "hits": 4, "gun": true}
	},
	"lost": {"sam": 1},
	"wingmen_lost": 1,
}
const RANGE := {"ground": {"target_t72": 2}, "weapons": {"MK-82": {"fired": 4, "hits": 2}}}


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	var ids: Dictionary = load("res://tests/test_front_end.gd").fixture(s)
	var db: String = s.records_db()
	var log := func(mid: int, mission: String, date: String, combat: Dictionary) -> int:
		var d := {"mission": mission, "pass": true, "date": date, "elapsed_s": 900.0, "plane": "f16i", "items": []}
		d["combat"] = combat
		return IafPilotLog.log_sortie(db, s.pilot(), mid, JSON.stringify(d))
	var four: int = log.call(2014, "ramon_four_ship", "2026-11-21T09:40:00", FOUR)
	log.call(2013, "ramon_range", "2026-11-17T07:30:00", RANGE)
	IafPilotLog.set_pilot(db, s.pilot(), "Noa Golan", "Viper")
	s.sim_jet = "f16i"
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	for lang in ["en", "he"]:
		var he: bool = lang == "he"
		s.language = lang
		# The Pilot screen's logbook.
		fe.show_page("pilot")
		await frames(2)
		var tiles: Control = fe.find_child("CombatTotals", true, false)
		check(tiles != null, "%s: the logbook's combat totals" % lang)
		if tiles == null:
			return
		var t := _labels(tiles)
		check(
			t.slice(0, 3) == ["2", "הפלות" if he else "Air kills", "משותפות: 1" if he else "1 shared"],
			"%s: %s" % [lang, t]
		)
		check(
			t.slice(3, 6) == ["2", "מטרות קרקע" if he else "Ground targets", "הושמדו" if he else "destroyed"],
			"%s: ground" % lang
		)
		check(
			t.slice(6, 9) == ["4", "פגיעות" if he else "Hits", "מתוך 7 חימושים" if he else "of 7 fired"],
			"%s: hits, the gun left out: %s" % [lang, t]
		)
		check(
			t.slice(9, 12) == ["1", "מטוסים שאבדו" if he else "Jets lost", "הופלו" if he else "shot down"],
			"%s: lost" % lang
		)
		var more: Button = fe.find_child("CombatMore", true, false)
		check(more != null and more.text == ("סטטיסטיקה מפורטת" if he else "More stats"), "%s: More stats" % lang)
		more.pressed.emit()
		await frames(2)
		var page: Control = fe.find_child("CombatMore", true, false)
		check(fe.page == "combat" and page is PanelContainer, "%s: the More stats page" % lang)
		var all := _labels(page)
		for x in [
			"מיג-29" if he else "MiG-29",
			"טנק T-72" if he else "T-72 tank",
			"שוגרו" if he else "Fired",
			"הוטלו" if he else "Dropped",
			"נורו" if he else "Rounds fired",
			"פיתון 5" if he else "Python 5",
			"הופלו בטיל קרקע-אוויר" if he else "Shot down by a SAM",
			"מהם, משאר מטוסי המבנה" if he else "Of them, the flight's other jets",
			"טיסות קרב" if he else "Combat flights",
			"2 הפלות" if he else "2 kills",
			"מטוס אחד אבד" if he else "1 jet lost",
		]:
			check(x in all, "%s: More stats shows %s" % [lang, x])
		check(not ("נטישות" if he else "Ejections") in all, "%s: no ejection row without one" % lang)
		fe.back()
		await frames(2)
		check(fe.page == "pilot", "%s: Back from More stats is the Pilot screen" % lang)
		# The four-ship's debrief: its own totals, More stats of that flight.
		check(fe.open_debrief(four), "%s: the four-ship's debrief" % lang)
		await frames(2)
		var sheet: Control = fe.find_child("Combat", true, false)
		check(
			sheet != null and _labels(sheet).has("2") and _labels(sheet).has("1"),
			"%s: the sheet's combat totals" % lang
		)
		more = fe.find_child("CombatMore", true, false)
		check(more != null, "%s: More stats in the debrief's footer" % lang)
		more.pressed.emit()
		await frames(2)
		all = _labels(fe.find_child("CombatMore", true, false))
		check(
			fe.page == "combat" and not ("טיסות קרב" if he else "Combat flights") in all, "%s: that flight only" % lang
		)
		check(not ("טנק T-72" if he else "T-72 tank") in all, "%s: not the range's targets" % lang)
		fe.back()
		await frames(2)
		check(fe.page == "debrief", "%s: Back from More stats is the debrief" % lang)
		# A flight without combat: neither.
		check(fe.open_debrief(ids.pass), "%s: the take-off's debrief" % lang)
		await frames(2)
		check(fe.find_child("Combat", true, false) == null, "%s: no combat block without combat" % lang)
		check(fe.find_child("CombatMore", true, false) == null, "%s: no More stats without combat" % lang)
	# A pilot with no combat flight: no block, no More stats.
	IafPilotLog.reset(db, s.pilot())
	fe.show_page("pilot")
	await frames(2)
	check(fe.find_child("CombatTotals", true, false) == null, "no combat: no totals")
	check(fe.find_child("CombatMore", true, false) == null, "no combat: no More stats")
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	s.language = "en"


func _labels(root: Node) -> Array:
	return (
		root
		. find_children("*", "", true, false)
		. filter(func(n): return n is Label or n is Button)
		. map(func(n): return n.text.replace("\u200f", ""))
	)
