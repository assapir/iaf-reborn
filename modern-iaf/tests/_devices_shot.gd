# Real-render pictures of Modern IAF's Keys and Joystick screens (modern-iaf/docs/front-end.md §9), English and Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/dev -- --log-file /tmp/dev.log --path modern-iaf \
#     -s ../modern-iaf/tests/_devices_shot.gd
# Writes SHOT_DIR/<shot>_<lang>.png at 1920×1080: keys (Pitch up rebound to K), keys_wait (Pitch down waiting for its
# key), keys_conflict (K pressed for Pitch down), joystick (a fake stick, its axes moved, the throttle lever forward:
# a full bar), joystick_buttons, prefs_detent (the afterburner detent set), keys_mac (English: the Views as on a
# Mac). The store is a temporary file.
extends "res://../tests/godot/base.gd"

const KeyTable := preload("res://shared/controls/key_table.gd")


func axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	s.devices_path = OS.get_temp_dir().path_join("iaf2026-shot-devices-%d.json" % OS.get_process_id())
	DirAccess.remove_absolute(s.devices_path)
	s.sim_jet = "f16i"
	var js: Node = root.get_node("Joystick")
	js.fake_devices = [0]
	load("res://menu/joystick_screen.gd").fake_names = {0: "Thrustmaster T.Flight Hotas X"}
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	var k := 0x25  # K
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		s.key_bindings = {}
		KeyTable.load_table().set_column(s.key_bindings, 24, "key", k)
		fe.show_page("keys")
		await frames(5)
		var ks: Node = fe.get_node("Keys")
		ks.scroll.scroll_vertical = int(ks._rows[19].row.position.y) - 1
		await frames(5)
		await shot(vp, dir, "keys", lang)
		ks.listen(25)
		await frames(5)
		await shot(vp, dir, "keys_wait", lang)
		ks.choose(25, k)
		await frames(10)
		await shot(vp, dir, "keys_conflict", lang)
		ks.cancel()
		fe.show_page("joystick")
		axis(0, 0.4)
		axis(1, -0.7)
		axis(2, -0.9)  # the lever near full forward: a near-full throttle bar
		await frames(10)
		await shot(vp, dir, "joystick", lang)
		var scr: Node = fe.get_node("Joystick")
		var tab: Button = fe.find_child("Tab_joy_buttons", true, false)
		tab.button_pressed = true
		tab.grab_focus()
		tab.pressed.emit()
		await frames(5)
		await shot(vp, dir, "joystick_buttons", lang)
		s.throttle_detent = 82
		fe.pref_group = "devices"
		fe.show_page("prefs")
		await frames(5)
		await shot(vp, dir, "prefs_detent", lang)
		s.throttle_detent = -1
	s.language = "en"
	# keys_mac: the Views group as a Mac shows it (the laptop map, Option and ⌘).
	var kt: GDScript = KeyTable
	var was: bool = kt.cmd_is_ctrl
	kt.cmd_is_ctrl = true
	s.laptop_keys = true
	s.pilot_name = "Noa Golan"
	fe.show_page("keys")
	await frames(5)
	var km: Node = fe.get_node("Keys")
	km.scroll.scroll_vertical = int(km._heads["views"].position.y)
	await frames(5)
	await shot(vp, dir, "keys_mac", "en")
	kt.cmd_is_ctrl = was
	s.laptop_keys = OS.get_name() == "macOS"
	s.pilot_name = ""
	js.fake_devices = []
	DirAccess.remove_absolute(s.devices_path)
	s.devices_path = ""


func shot(vp: SubViewport, dir: String, what: String, lang: String) -> void:
	var path: String = dir.path_join("%s_%s.png" % [what, lang])
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
