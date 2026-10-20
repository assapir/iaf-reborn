# Dev helper (not run by tools/test.sh): a real-render capture of I-mode (F12) in mission 221 with friends and enemies
# placed around the jet out of view, plus one in view (no mark). Saved to IMODE_SHOT.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 IMODE_SHOT=/tmp/imode.png -- --log-file /tmp/g.log --path game -s \
#     ../tests/godot/_imode_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	tv.fm_stopped = true
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var friends := []
	var enemies := []
	for e in rt.entities.values():
		if (
			not e.player
			and int(e.get("klass", -1)) in [1, 2, 3, 0x1c]
			and e.node is Node3D
			and e.node.is_visible_in_tree()
		):
			(friends if int(e.side) == int(me.side) else enemies).append(e)
	key(tv, KEY_F12)
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var b := cam.global_basis
	var eye := cam.global_position
	# [right, ahead, up] in metres from the eye.
	var spots := {
		"f": [[-3000.0, 600.0, 200.0], [-1500.0, -200.0, -400.0]],
		"e": [[2500.0, 400.0, 1800.0], [3000.0, 300.0, -300.0], [300.0, 2500.0, 150.0]]
	}
	for i in 30:
		for e in friends + enemies:
			e.node.global_position = eye + Vector3(0, 60000, 0)
		for k in 2:
			var list: Array = friends if k == 0 else enemies
			var at: Array = spots["f" if k == 0 else "e"]
			for j in mini(list.size(), at.size()):
				var p: Array = at[j]
				list[j].node.global_position = eye + b.x * p[0] - b.z * p[1] + b.y * p[2]
		tv._imode_tick = -1
		tv._imode_update()
		await process_frame
	print("entries ", tv.cockpit.imode_entries)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("IMODE_SHOT"))
	print("saved ", OS.get_environment("IMODE_SHOT"))
