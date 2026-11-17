# One click, one action, one click sound (the user, 17 Nov: "the clicks on the panel are happens twice for every click
# I think"): a press and release of the pointer, as the OS sends them (Input.parse_input_event), on the F-16's ICP
# keys (a digit reaches the DED's scratchpad once), a toggle and MAIN PWR (one position a click) play SFX_BUTTON once a
# click; the INS knob no more than once.
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-oneclick-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramon_takeoff")
	Engine.time_scale = 1.0
	tv.flight.start_switch("main_power", 1)
	await fly(tv, 2.0)
	tv._command([250, 1, 0])  # CNI -> T-ILS: the digits go to TACAN CHAN's scratchpad
	await frames(3)
	var sounds_before: int = _buttons(tv)
	await _os_click(tv, "5")
	check(_chan(tv) == "5", "ICP 5 clicked once: CHAN reads 5 (%s)" % _chan(tv))
	await _os_click(tv, "3")
	check(_chan(tv) == "53", "ICP 3 clicked once: CHAN reads 53 (%s)" % _chan(tv))
	check(_buttons(tv) - sounds_before == 2, "two ICP clicks: two click sounds (%d)" % (_buttons(tv) - sounds_before))
	for node in ["AVIONICS_MMC", "MAIN_PWR"]:
		var n0: int = _buttons(tv)
		await _os_click(tv, node)
		check(_buttons(tv) - n0 == 1, "%s clicked once: one click sound (%d)" % [node, _buttons(tv) - n0])
	check(tv.flight.start_position("main_power") == 2, "MAIN PWR one position a click: BATT, then MAIN PWR")
	var n1: int = _buttons(tv)
	await _os_click(tv, "INS")
	check(_buttons(tv) - n1 <= 1, "the INS knob: no doubled click sound (%d)" % (_buttons(tv) - n1))
	tv.views.snap = Vector2.ZERO


func _chan(tv: Node) -> String:
	var l: String = tv.cockpit.ufc.lines(tv.cockpit.ufc_nav())[2]
	var a := l.find("*")
	return l.substr(a + 1, l.find("*", a + 1) - a - 1).strip_edges()


func _buttons(tv: Node) -> int:
	return tv.sounds.played.count("SFX_BUTTON/None")


## A press and release of the left button over control `node`, the head turned to it, through Input as the OS's.
func _os_click(tv: Node, node: String) -> void:
	var mi: MeshInstance3D = tv.cockpit_3d.find_child(node, true, false)
	var at := await _aim(tv, func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center(), 0.0)
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	Input.parse_input_event(mv)
	await frames(2)
	for pressed in [true, false]:
		var e := _click(at, MOUSE_BUTTON_LEFT, pressed)
		e.global_position = at
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(e)
		await frames(2)
	await frames(3)
