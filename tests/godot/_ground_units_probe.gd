# Dev helper (not run by tools/test.sh): a mission's ground units against the ground under them. Prints each unit
# standing on the ground: its drawn height and the terrain height there (terrain.height_at). PROBE_MISSION=id (default 323), PROBE_SET=key=value,... settings first (e.g. world_scale=real).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 PROBE_SET=world_scale=real -- --log-file /tmp/p.log --path game \
#     -s ../tests/godot/_ground_units_probe.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	for kv in OS.get_environment("PROBE_SET").split(",", false):
		var p := kv.split("=")
		var v: Variant = settings().get(p[0])
		settings().set(p[0], p[1] if v is String else str_to_var(p[1]))
	var id := int(OS.get_environment("PROBE_MISSION")) if OS.get_environment("PROBE_MISSION") != "" else 323
	var tv := await start_mission(id)
	await frames(120)
	var cam: Vector3 = tv.get_viewport().get_camera_3d().global_position
	for ent in tv.runtime.entities.values():
		var node: Node3D = ent.get("node")
		if node == null or not node.visible or ent.get("airborne_class", false) or ent.player:
			continue
		var p := node.global_position
		var h = tv.terrain.height_at(p)
		print(
			(
				"UNIT %-14s klass %3d  dist %6.0f m  y %8.1f  height_at %s"
				% [str(ent.get("name", ent.key)), int(ent.get("klass", 0)), p.distance_to(cam), p.y, h]
			)
		)
	check(true, "probed")
