# Contact sheet of every converted aircraft in its animated configurations (needs a window):
#   godot --path game -s tools/aircraft_sheet.gd -- <out-dir> [plane…]
# Per plane: landing configuration (gear down, flaps, speed brakes, stick back + right roll, rudder)
# from above-behind and from below, clean with gear up and full afterburner from above and behind.
# Writes <out>/<plane>.png (2×2) and <out>/all.png (one row per plane).
extends SceneTree

const CELL := Vector2i(640, 400)
const AircraftModel := preload("res://aircraft/aircraft_model.gd")


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://aircraft_sheet"
	DirAccess.make_dir_recursive_absolute(out)
	var only := args.slice(1)
	DisplayServer.window_set_size(CELL)
	root.size = CELL
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.42, 0.55, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.current = true
	var rows: Array[Image] = []
	var names := AircraftModel.index().keys()
	names.sort()
	for plane in names:
		if not only.is_empty() and not only.has(plane):
			continue
		var m: Node3D = AircraftModel.create(plane)
		if m == null:
			print("FAILED ", plane)
			continue
		root.add_child(m)
		var box := _box(m)
		var size := maxf(box.size.length() * 0.5, 3.0)
		var centre := box.get_center()
		var shots: Array[Image] = []
		var landing := {"gear_down": true, "flaps": 1.0, "brakes": true, "stick_x": 0.6, "stick_y": 0.8, "rudder": 1.0, "afterburner": 0, "chute": 2}
		var clean := {"gear_down": false, "flaps": 0.0, "brakes": false, "stick_x": 0.0, "stick_y": 0.0, "afterburner": 2}
		for pose in [[landing, Vector3(-0.9, 0.45, 1.0)], [landing, Vector3(-1.0, -0.55, -0.6)],
				[clean, Vector3(-0.9, 0.45, 1.0)], [clean, Vector3(0.25, 0.2, 1.0)]]:
			# Levers start from the opposite state so every ramp gets an event, then settles.
			m.update({"gear_down": not pose[0].gear_down, "flaps": 1.0 - pose[0].flaps, "brakes": not pose[0].brakes}, 0.0)
			m.update(pose[0], 0.0)
			m.settle()
			m.update(pose[0], 0.0)
			cam.position = centre + pose[1].normalized() * size * 2.3
			cam.look_at(centre, Vector3.UP)
			for i in 4:
				await process_frame
			var img := root.get_texture().get_image()
			img.resize(CELL.x, CELL.y)
			shots.append(img)
		var sheet := Image.create(CELL.x * 2, CELL.y * 2, false, shots[0].get_format())
		for i in 4:
			sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(i % 2, i / 2) * CELL)
		sheet.save_png(out.path_join(plane + ".png"))
		var row := Image.create(CELL.x * 4, CELL.y, false, shots[0].get_format())
		for i in 4:
			row.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
		row.resize(CELL.x * 2, CELL.y / 2)
		rows.append(row)
		print("sheet ", plane, " type ", m.type_code, " parts ", m.parts.size(), " flames ", m.flames.size())
		m.queue_free()
		await process_frame
	if not rows.is_empty():
		var all := Image.create(rows[0].get_width(), rows[0].get_height() * rows.size(), false, rows[0].get_format())
		for i in rows.size():
			all.blit_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, i * rows[i].get_height()))
		all.save_png(out.path_join("all.png"))
	quit()


## Bounds of the model's visible meshes.
func _box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
