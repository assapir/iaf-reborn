# Dev helper (not run by tools/test.sh): Scramble's start time (modern-iaf/docs/front-end.md §2.1): the Sufa pair's air
# start from Ramon round Hatzerim at SHOT_TIME (HHMM, 24-hour; today's date) through flight/fly.gd prepare_free, as
# the game flies it: the cockpit (SHOT_DIR/<SHOT_NAME>_cockpit.png) and the pair from beside the wingman
# (<SHOT_NAME>_external.png). A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_TIME=1650 \
#     SHOT_NAME=dusk -- --log-file <temp> --resolution 1600x900 --path modern-iaf \
#     -s ../modern-iaf/tests/_scramble_time_shot.gd
extends "res://../tests/godot/base.gd"


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := OS.get_environment("SHOT_DIR").path_join("%s_%s.png" % [OS.get_environment("SHOT_NAME"), name])
	check(img.save_png(path) == OK, "saved " + path)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.sim_jet = "f16i"
	s.show_info = false
	var hhmm := int(OS.get_environment("SHOT_TIME"))
	var fc := {"flight": 2, "area": "Hatzerim", "home": "Ramon", "start": "air", "seed": 1}
	fc.start_min = hhmm / 100 * 60 + hhmm % 100
	var id := sim_mission("ramon_free")
	load("res://flight/fly.gd").prepare_free(id, fc)
	s.free_combat = fc
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	s.invulnerable = true
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 2.0)
	await frames(10)
	await _save("cockpit")
	tv.addon.ui.visible = false
	tv.in_cockpit = false
	var cam: Camera3D = tv.chase
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	var at: Vector3 = tv.ai.world_of(wing[0]) if not wing.is_empty() else tv.player_world()
	var me: Vector3 = tv.player_world()
	var e3: Vector3 = tv.world_to_scene(at + (at - me).normalized() * 40.0 + Vector3(0, 0, 8))
	var xf := Transform3D(Basis.looking_at(tv.world_to_scene(me) - e3, Vector3.UP), e3)
	var hold := func():
		cam.global_transform = xf
		RenderingServer.camera_set_transform(cam.get_camera_rid(), xf)
	RenderingServer.frame_pre_draw.connect(hold)
	await frames(30)
	await _save("external")
	RenderingServer.frame_pre_draw.disconnect(hold)
