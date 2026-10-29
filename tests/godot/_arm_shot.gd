# Dev helper (not run by tools/test.sh): a real-render capture of the Arming screen of mission ARM_MISSION (default
# 221, F-16s) for its first flight, saved to ARM_SHOT; ARM_F16=sufa shows the F-16I Sufa's (docs/f16i.md §8.1).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ARM_F16=sufa ARM_SHOT=/tmp/arm.png -- --log-file /tmp/a.log \
#       --path game --resolution 1280x960 -s ../tests/godot/_arm_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	if OS.get_environment("ARM_F16") != "":
		settings().f16_variant = OS.get_environment("ARM_F16")
	var id := int(OS.get_environment("ARM_MISSION")) if OS.get_environment("ARM_MISSION") != "" else 221
	settings().mission_id = id
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
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
