# Probe (real render): what the scenery costs the GPU over a town, by part. The jet held still at the --at pose (UTM,
# with --freeze), the cockpit view; once every cell around is built, the GPU time of the flight's viewport over 120
# frames with all the scenery shown ("nothing" hidden), none ("everything"), each part hidden in turn (the near
# buildings, the far ring's, the roofs' items, the near trees, the far trees), the roads (Roads Detailed off), the
# near buildings casting no shadow, the near model to 1,500 m (the far ring's from there), the walls' texture
# filtered trilinear (not anisotropic) or left out; in rounds, interleaved (modern-iaf/docs/scenery.md §6).
# SCENERY_CASES=a,b: only those cases (a name twice: measured twice a round). SCENERY_ROUNDS=n: n rounds (default 2).
# SCENERY_SHOT=<dir>: a picture of each case (first round). SCENERY_SHADER_B=<file>[:<file>…]: a case "shader <file
# name>" each, the buildings' shader from that file (an A/B of a shader change).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <log> \
#     --resolution 2560x1440 --path modern-iaf -s ../modern-iaf/tests/_scenery_probe.gd \
#     -- --at 668000 3550689 530 330 0 --freeze
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().blackbox = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file("res://shared/terrain/terrain_view.tscn")
	await frames(2)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var sc: Node = tv.terrain.scenery
	check(sc != null, "the scenery is on")
	if sc == null:
		return
	t0 = Time.get_ticks_msec()
	await seconds(5.0)
	# Every cell around built (its pieces arrive over frames).
	while Time.get_ticks_msec() - t0 < 180000:
		var fp: Vector3 = tv.terrain.focus.global_position
		var busy: Array = sc._cells.keys().filter(
			func(k): return sc._dist(k, fp) <= sc.RANGE and sc._cells[k].state not in ["none", "wait", "built"]
		)
		if busy.is_empty():
			break
		await seconds(1.0)
	print("BUILT after %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await seconds(3.0)
	var scenery_gd: GDScript = load("res://shared/terrain/scenery.gd")  # at run time: it needs the Settings autoload
	var roofs_end: float = scenery_gd.ROOF_ITEMS + scenery_gd.TILE_REACH
	var parts := {"buildings near": [], "buildings far": [], "roof items": [], "trees near": [], "trees far": []}
	for n in sc.find_children("*", "GeometryInstance3D", true, false):
		if n is MultiMeshInstance3D:
			if is_equal_approx(n.visibility_range_end, roofs_end):
				parts["roof items"].append(n)
			else:  # the far model by its material (with the foliage textures both start at 0 m)
				var tm: ShaderMaterial = n.multimesh.mesh.surface_get_material(0)
				var far: bool = tm.shader == scenery_gd.FOLIAGE_FAR_SHADER or tm.get_shader_parameter("far_model")
				parts["trees far" if far else "trees near"].append(n)
		elif n is MeshInstance3D:
			parts["buildings far" if n.get_instance_shader_parameter("far_model") else "buildings near"].append(n)
	for p in parts:
		print("PART %s: %d nodes" % [p, parts[p].size()])
	var on: bool = load("res://shared/terrain/ground_roads.gd").on()
	var roads: float = (2.0 if settings().scenery_ortho() else 1.0) if on else 0.0  # the global ground_roads.gd sets
	print("ROADS %s" % roads)
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var mats := {}
	for n in parts["buildings near"] + parts["buildings far"]:
		mats[n.material_override] = true
	var near_m: float = scenery_gd.NEAR
	var cast := {}
	var reach := {}  # each building mesh's reach past its model's range (scenery.gd _upload)
	for n in parts["buildings near"]:
		cast[n] = n.cast_shadow
		reach[n] = n.visibility_range_end - near_m
	for n in parts["buildings far"]:
		reach[n] = near_m - n.visibility_range_begin
	var shader: Shader = mats.keys()[0].shader
	var has_walls: bool = mats.keys()[0].get_shader_parameter("has_walls")
	var trilinear := Shader.new()
	trilinear.code = shader.code.replace("filter_linear_mipmap_anisotropic", "filter_linear_mipmap")
	var variants := {"walls trilinear": trilinear}
	for f in OS.get_environment("SCENERY_SHADER_B").split(":", false):
		var v := Shader.new()
		v.code = FileAccess.get_file_as_string(f)
		variants["shader " + f.get_file().get_basename()] = v
	var cases: Array = (
		["nothing"]
		+ parts.keys()
		+ ["everything", "no near shadows", "near 1500 m", "no roads"]
		+ variants.keys()
		+ ["no wall texture"]
	)
	if OS.get_environment("SCENERY_CASES") != "":
		cases = Array(OS.get_environment("SCENERY_CASES").split(","))
	for round in int(OS.get_environment("SCENERY_ROUNDS")) if OS.get_environment("SCENERY_ROUNDS") != "" else 2:
		for case in cases:
			for p in parts:
				for n in parts[p]:
					n.visible = case == "nothing" or not (case == "everything" or case == p)
			var near: float = 1500.0 if case == "near 1500 m" else near_m
			for n in parts["buildings near"]:
				n.visibility_range_end = near + reach[n]
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if case == "no near shadows" else cast[n]
			for n in parts["buildings far"]:
				n.visibility_range_begin = near - reach[n]
			for m in mats:
				m.set_shader_parameter("near_m", near)
				m.shader = variants.get(case, shader)
				m.set_shader_parameter("has_walls", has_walls and case != "no wall texture")
			RenderingServer.global_shader_parameter_set("ground_roads", 0.0 if case == "no roads" else roads)
			await frames(20)
			var gpu := 0.0
			var cpu := 0.0  # the render thread's: culling and draw calls
			var prims := 0.0
			for i in 120:
				await RenderingServer.frame_post_draw
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp) / 120.0
				cpu += (
					(
						RenderingServer.viewport_get_measured_render_time_cpu(vp)
						+ RenderingServer.get_frame_setup_time_cpu()
					)
					/ 120.0
				)
				prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 120.0
			if round == 0 and OS.get_environment("SCENERY_SHOT") != "":
				var path := OS.get_environment("SCENERY_SHOT").path_join(case.replace(" ", "_") + ".png")
				root.get_viewport().get_texture().get_image().save_png(path)
			print(
				(
					"SCENERY round %d, %-17s: GPU %.2f ms, %4.0fk primitives, CPU %.2f ms"
					% [round, case, gpu, prims / 1000.0, cpu]
				)
			)
