# Dev helper (not run by tools/test.sh): a real-render capture of the Arming screen of mission ARM_MISSION (default
# 221, F-16s) for its first flight, saved to ARM_SHOT; ARM_F16=sufa shows the F-16I Sufa's (docs/f16i.md §8.1),
# ARM_F15=raam every F-15 as the F-15I Ra'am (docs/f15i.md). ARM_SCREEN=jet: the Jet list instead, its F15 row picked
# hovered (ARM_LANG=he in Hebrew). ARM_REAL=1: Weapon data on Real.
# ARM_JET = a Jet list id to fly (ARM_F35I = the F-35I's slot), ARM_MODERN=1 Extras "Weapons" on Modern, ARM_TAB = the
# list's tab (0 AA, 1 AG; docs/weapons.md §13), ARM_PUT = 9 comma-separated weapon ids put on stations 1..9 (0 empty).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ARM_F16=sufa ARM_SHOT=/tmp/arm.png -- --log-file /tmp/a.log \
#       --path game --resolution 1280x960 -s ../tests/godot/_arm_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	if OS.get_environment("ARM_F16") != "":
		settings().f16_variant = OS.get_environment("ARM_F16")
	if OS.get_environment("ARM_F15") != "":
		settings().f15_variant = OS.get_environment("ARM_F15")
	if OS.get_environment("ARM_LANG") != "":
		settings().language = OS.get_environment("ARM_LANG")
	if OS.get_environment("ARM_JET") != "":
		settings().jet_id = int(OS.get_environment("ARM_JET"))
	if OS.get_environment("ARM_F35I") != "":
		settings().f35i_slot = int(OS.get_environment("ARM_F35I"))
	if OS.get_environment("ARM_REAL") == "1":
		settings().weapon_data = "real"
	settings().modern_weapons = OS.get_environment("ARM_MODERN") == "1"
	var id := int(OS.get_environment("ARM_MISSION")) if OS.get_environment("ARM_MISSION") != "" else 221
	settings().mission_id = id
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	if OS.get_environment("ARM_SCREEN") == "jet":
		fe.screen = "jet"
		fe._enter_screen()
		await _settle(fe)
		fe.hover_key = fe._key_for_label("F15")
		fe.queue_redraw()
		await _shot()
		return
	fe._reset_tsd_checks()
	fe.tsd_return = "jet"
	fe.screen = "tsd"
	fe._enter_screen()
	await _settle(fe)
	fe._on_button(fe._key_for_label("Alpha"))
	await _settle(fe)
	fe._on_button(fe._key_for_label("Arm"))
	await _settle(fe)
	check(fe.screen == "arm", "the Arming screen is open")
	if OS.get_environment("ARM_PUT") != "":
		var ids := OS.get_environment("ARM_PUT").split(",")
		for i in mini(9, ids.size()):
			var w: Dictionary = fe.arm.data.weapon(int(ids[i]))
			if not w.is_empty() or int(ids[i]) == 0:
				fe.arm.data.put(fe.arm.flight, i, w)
	if OS.get_environment("ARM_TAB") != "":
		fe.arm.set_tab(int(OS.get_environment("ARM_TAB")))
		fe.arm._check_tab()
	await _shot()


func _shot() -> void:
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("ARM_SHOT"))
	print("saved ", OS.get_environment("ARM_SHOT"))


func _settle(fe) -> void:
	await frames(2)
	var n := 0
	while fe.busy and n < 600:
		await process_frame
		n += 1
