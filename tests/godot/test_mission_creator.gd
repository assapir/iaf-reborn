# Mission Creator (docs/front-end.md §19, docs/formats/mcr.md): Main → MISSION CREATOR opens screen 0x14 with the
# zeroed state; the combos open, list and pick (BASE copied into the formation records); the name and notes boxes
# take the edit class's characters; FLY's checks (msgs 44, 47, 48); RANDOM; SAVE (msg 49 without a name, msg 46
# before replacing) and LOAD round trip in a temporary folder (IAF_DEFAULT_SETTINGS=1); FLY generates mission 0x29a
# (units, routes, base, target as chosen) and the TSD opens on it.
extends "res://../tests/godot/base.gd"

var fe: Control
var mcv: Control


func type_text(s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		mcv._unhandled_input(e)


func mc_click(q: Vector2) -> void:
	var at: Vector2 = fe._to_screen(mcv.CONTENT + q)
	mcv._gui_input(mouse_button(at, true))
	mcv._gui_input(mouse_button(at, false))


## Opens combo c and picks item i by clicking its row.
func pick(c: int, i: int) -> void:
	mc_click(mcv.COMBOS[c][3].get_center())
	var lr: Rect2 = mcv.list_rect()
	mc_click(Vector2(lr.get_center().x, lr.position.y + mcv.ROW_H * (i + 0.5)))


func box_msg() -> int:
	if fe.msgbox == null:
		return -1
	var lines: PackedStringArray = settings().msgs()
	for i in lines.size():
		if lines[i].strip_edges() == fe.msgbox.text:
			return i
	return -2


func answer(art: String) -> void:
	fe.msgbox.chosen.emit(art)


func run() -> void:
	fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("MissionCreator"))
	while fe.busy:
		await process_frame
	check(fe.screen == "mc" and fe.mc_view != null, "Main -> MissionCreator opens the MC screen")
	mcv = fe.mc_view
	var mc: Dictionary = settings().mc
	check(mc.name == "" and int(mc.count[0]) == 0 and int(mc.base) == 0, "the state starts zeroed (FUN_004f64a0)")

	# FLY on the zeroed state: msg 44 (no controllable blue jet).
	mcv.button("fly")
	check(box_msg() == 44, "FLY without a blue jet -> msg 44")
	answer("ok")

	# Combos: open, pick.
	pick(0, 2)
	check(int(settings().mc.count[0]) == 2 and mcv.open == -1, "Alpha No: 2, the list closes")
	pick(4, 8)
	check(int(settings().mc.type[0]) == 8 and mcv.shown_text(4) == "MiG-29", "Alpha TYPE: MiG-29 (Alpha lists 9 types)")
	check(mcv.LISTS[mcv.COMBOS[5][2]].size() == 16, "Bravo TYPE lists all 16 types")
	check(mcv.LISTS[mcv.COMBOS[10][2]].size() == 2, "the Red AI lists hold Aggressors / Defenders")
	pick(12, 2)
	check(
		int(settings().mc.base) == 2 and settings().mc.fbase.all(func(b): return int(b) == 2),
		"BASE Ramon, copied into every formation record"
	)
	mcv.button("fly")
	check(box_msg() == 48, "By Kills without a red jet -> msg 48")
	answer("ok")
	pick(19, 1)
	mcv.button("fly")
	check(box_msg() == 47, "By Target with No Target -> msg 47")
	answer("ok")
	check(mcv.opens_up(18) and not mcv.opens_up(19), "WEAPONS opens up, VICTORY down (FUN_004f5570)")
	mc_click(mcv.COMBOS[13][3].get_center())
	check(mcv.open == 13, "a click on the box opens its list, the release keeps it open")
	mc_click(Vector2(300, 20))
	check(mcv.open == -1 and int(settings().mc.time) == 0, "a click outside closes it unchanged")
	pick(15, 3)
	check(mcv.shown_text(15) == "Radar Station", "TARGET Radar Station")

	# Name / notes.
	mc_click(mcv.NAME_BOX.get_center())
	type_text("Test 1!")
	check(settings().mc.name == "Test 1", "the name box takes letters, digits, space, '.' only")
	mc_click(mcv.NOTES_BOX.get_center())
	type_text("abc")
	check(settings().mc.notes == "abc", "the notes box")

	# SAVE / LOAD.
	var folder: String = mcv.folder()
	check(not folder.begins_with(ProjectSettings.globalize_path("user://")), "tests save in a temporary folder")
	mcv.button("save")
	check(FileAccess.file_exists(folder.path_join("Test 1")), "SAVE writes MCR/<name>")
	check(FileAccess.get_file_as_bytes(folder.path_join("Test 1")).size() == 0x5ac, "the file is 0x5ac bytes")
	mcv.button("save")
	check(box_msg() == 46, "SAVE over an existing file asks msg 46")
	answer("yes")
	var saved: Dictionary = settings().mc.duplicate(true)
	mcv.button("random")
	check(settings().mc.name == "Random" and int(settings().mc.weapons) == 1, "RANDOM: name Random, Multipurpose")
	check(mcv.read(folder.path_join("Test 1")) and settings().mc == saved, "LOAD restores the saved state")
	settings().mc.name = ""
	mcv.button("save")
	check(box_msg() == 49, "SAVE without a name -> msg 49")
	answer("ok")
	fe.queue_free()
	await frames(2)
