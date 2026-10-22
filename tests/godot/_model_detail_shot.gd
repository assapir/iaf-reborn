# Dev helper (not run by tools/test.sh): Model detail (docs/rendering.md §9) before / after in the same
# view, and its GPU cost. Mission 311 on Ramat David's runway in the Kfir (Mk-82s and a drop tank on its pylons), with
# an F-4, more Kfirs, a tank and truck column, a hardened shelter and a hangar placed beside it. Each shot is saved
# twice, SHOT_DIR/<shot>_original.png and <shot>_ambientcg.png, the detail switched in place between them.
# SHOT_BENCH=1: no pictures; from the busy external view, the GPU time with the detail off / on alternated every 120
# frames, 12 pairs (the median difference, robust to other work on the machine), at the window's resolution.
# SHOT_ONLY=pylons,wheels: only those shots. SHOT_SET="key=value,…" sets Settings keys first (str_to_var values; e.g.
# SHOT_SET='ground_textures="ambientcg"' for Ground textures under both shots).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 MESA_VK_WSI_PRESENT_MODE=immediate SHOT_DIR=/tmp/md -- \
#     --log-file /tmp/g.log --path game --resolution 1920x1080 -s ../tests/godot/_model_detail_shot.gd
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")
const ModelDetail := preload("res://util/model_detail.gd")
## Pylon loads (weapon names in the mission's Weapons table, as _model_shot.gd matches them): Mk-82s and a centre tank.
const LOADOUT := {1: "MK82", 2: "MK82", 4: "300", 6: "MK82", 7: "MK82"}
## Props: [model under converted/objects or "jet:<plane>", metres right / forward of the player's jet (jets: at true
## size, scaled with the jet's drawn size), heading (deg from the jet's), length (m; jets: the player's scale)].
const PROPS := [
	["jet:f42000", 22.0, 4.0, 20.0, 0.0],
	["jet:cfir", 20.0, -22.0, 0.0, 0.0],
	["jet:cfir", -20.0, -24.0, 0.0, 0.0],
	["jet:cfir", -22.0, 6.0, -20.0, 0.0],
	["groundforces/t62/t62_h.gltf", -70.0, 20.0, 0.0, 9.3],
	["groundforces/t62/t62_h.gltf", -70.0, 32.0, 0.0, 9.3],
	["groundforces/m113/m113_h.gltf", -70.0, 44.0, 0.0, 4.9],
	["groundforces/wrftrk/wrftrk_h.gltf", -70.0, 56.0, 0.0, 7.0],
	["stationary/hgrdr1/hgrdr1_h.gltf", 110.0, 40.0, -90.0, 30.0],
	["stationary/hgrsk1/hgrsk1_h.gltf", 110.0, -40.0, -90.0, 40.0],
]
## Shots: [name, camera (right, up, forward m from the jet), look-at (right, up, forward), in the jet's true size
## (scaled with its drawn size) or plain metres].
const SHOTS := [
	["kfir_ramp", Vector3(6.5, 1.6, 7.5), Vector3(0.0, 0.2, 0.5), true],
	["pylons", Vector3(3.5, -0.2, 3.0), Vector3(0.0, -0.6, -0.5), true],
	["wheels", Vector3(3.2, -0.6, -2.5), Vector3(0.0, -1.4, 0.6), true],
	["f4_ramp", Vector3(14.0, 2.0, 12.0), Vector3(22.0, 0.3, 4.0), true],
	["column", Vector3(-60.0, 2.5, 12.0), Vector3(-70.0, 1.0, 32.0), false],
	["shelter", Vector3(80.0, 5.0, 62.0), Vector3(110.0, 4.0, 40.0), false],
	["hangar", Vector3(84.0, 5.0, -14.0), Vector3(110.0, 4.0, -40.0), false],
	["busy", Vector3(-10.0, 16.0, 90.0), Vector3(0.0, 0.0, 0.0), false],
]

var tv: Node
var _cam_xf := Transform3D()
var _detail := {}  # MeshInstance3D -> {surface: ShaderMaterial}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var hitch := OS.get_environment("SHOT_HITCH") == "1"
	settings().model_detail = OS.get_environment("SHOT_DETAIL") if hitch else "ambientcg"
	settings().jet_id = 5  # the Kfir
	settings().show_info = false
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(hitch or ModelDetail.enabled(), "the materials are there")
	if hitch:
		await _hitch()
		return
	tv = await start_mission(311)
	print("mission up, %.1f fps" % Engine.get_frames_per_second())
	tv.text_messages = false  # no instructor text over the pictures
	tv.cockpit.subtitles = [] as Array[String]
	_arm()
	_place_props()
	tv.in_cockpit = false
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	var pin := CamPin.new()
	pin.place = _place_camera
	pin.process_priority = 100000
	tv.add_child(pin)
	for mi: MeshInstance3D in tv.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var m := mi.get_surface_override_material(s)
			if m is ShaderMaterial and m.has_meta("base"):
				_detail.get_or_add(mi, {})[s] = m
	print("detail on %d mesh instances" % _detail.size())
	if OS.get_environment("SHOT_BENCH") == "1":
		await _bench()
		return
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("SHOT_ONLY").split(",", false)  # e.g. SHOT_ONLY=pylons,wheels
	for s in SHOTS:
		if not only.is_empty() and not s[0] in only:
			continue
		_aim(s[1], s[2], s[3])
		await _settle()
		for on in [false, true]:
			_set_detail(on)
			await frames(20)
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png(dir.path_join("%s_%s.png" % [s[0], "ambientcg" if on else "original"]))
			print("shot %s %s" % [s[0], on])
	check(true, "shots in %s" % dir)


## SHOT_HITCH=1 (SHOT_DETAIL = original / ambientcg, one run each): the mission's start time (as from the briefing:
## the front end's preload has run), the worst frame over the first 30 s from the external view, and the worst frame
## while new models appear: four jets, a vehicle column and two buildings placed at once, then four Mk-82s (a store
## release makes the same model the same way, player_weapons.gd).
func _hitch() -> void:
	ModelDetail.preload_packs()
	await frames(60)  # the briefing's time
	var t0 := Time.get_ticks_msec()
	tv = await start_mission(311)
	var start_ms := Time.get_ticks_msec() - t0
	tv.text_messages = false
	tv.in_cockpit = false
	tv._apply_view()
	var worst_start := await _worst(30.0)
	await process_frame
	var t := Time.get_ticks_usec()
	_place_props()
	for i in 4:
		var bomb := Gltf.instance(Gltf.object("weapons/mk82/mk82_m.gltf"))
		tv.add_child(bomb)
		bomb.global_position = _at(Vector3(3.0 + i, -1.0, 4.0))
	await process_frame
	var spawn_frame := (Time.get_ticks_usec() - t) / 1000.0
	var worst_after := await _worst(5.0)
	print(
		(
			"HITCH %s %s: start %d ms; worst frame first 30 s %.1f ms; spawn frame %.1f ms; worst next 5 s %.1f ms"
			% [settings().model_detail, root.get_viewport().size, start_ms, worst_start, spawn_frame, worst_after]
		)
	)
	check(true, "hitch done")


## The longest frame (ms) over `s` seconds, and the mean frame rate printed.
func _worst(s: float) -> float:
	var worst := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < s * 1e6:
		var t := Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
		n += 1
	print("  %.0f s: %.1f fps mean, worst %.1f ms" % [s, n / s, worst])
	return worst


func _place_camera() -> void:
	tv.chase.global_transform = _cam_xf
	tv.chase.fov = 45.0


func _bench() -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_aim(SHOTS[-1][1], SHOTS[-1][2], SHOTS[-1][3])
	await _settle()
	var gpu := [[], []]  # per pair, off / on: mean GPU ms
	var frame := [[], []]  # mean frame ms (vsync off: the frame rate)
	for pair in 12:
		for on in [0, 1]:
			_set_detail(on == 1)
			await frames(30)
			var t := 0.0
			var t0 := Time.get_ticks_usec()
			for i in 120:
				await process_frame
				t += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			gpu[on].append(t / 120.0)
			frame[on].append((Time.get_ticks_usec() - t0) / 120000.0)
	var med := func(a: Array) -> float:
		var c := a.duplicate()
		c.sort()
		return (c[5] + c[6]) / 2.0
	var diffs := []
	for i in 12:
		diffs.append(gpu[1][i] - gpu[0][i])
	print(
		(
			(
				"BENCH %s off: %.1f fps (frame %.2f ms, GPU %.2f ms); on: %.1f fps (frame %.2f ms, GPU %.2f ms);"
				+ " GPU on − off median %.3f ms"
			)
			% [
				root.get_viewport().size,
				1000.0 / med.call(frame[0]),
				med.call(frame[0]),
				med.call(gpu[0]),
				1000.0 / med.call(frame[1]),
				med.call(frame[1]),
				med.call(gpu[1]),
				med.call(diffs),
			]
		)
	)
	print(
		(
			"VRAM texture %.1f MiB"
			% (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0)
		)
	)
	check(true, "bench done")


func _set_detail(on: bool) -> void:
	for mi in _detail:
		for s in _detail[mi]:
			mi.set_surface_override_material(s, _detail[mi][s] if on else null)


func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	await frames(10)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	await frames(30)
	print("settled, %.1f fps" % Engine.get_frames_per_second())


## The jet's frame on the ground: right, up, forward (flat).
func _frame() -> Array:
	var b: Basis = tv.aircraft.global_basis.orthonormalized()
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	return [fwd.cross(Vector3.UP).normalized(), fwd]


## A point given in the jet's frame (right, up, forward m at true size), scaled with the jet's drawn size (World scale
## Original draws the jets ×2), in the world.
func _at(v0: Vector3, jet_size := true) -> Vector3:
	var v: Vector3 = v0 * (tv.aircraft.scale.x if jet_size else 1.0)
	var f := _frame()
	var right: Vector3 = f[0]
	return tv.aircraft.global_position + right * v.x + Vector3.UP * v.y + f[1] * v.z


func _aim(cam: Vector3, look: Vector3, jet_size: bool) -> void:
	var c := _at(cam, jet_size)
	_cam_xf = Transform3D(Basis.looking_at(_at(look, jet_size) - c, Vector3.UP), c)


func _arm() -> void:
	var hp := []
	var db: RefCounted = load("res://weapons/mission_weapons.gd").create(311)
	for i in 9:
		var want: String = LOADOUT.get(i, "")
		var id := 0
		for w in db.weapons:
			if want != "" and String(w.name).replace("-", "").replace(" ", "").to_upper().contains(want):
				id = int(w.id)
				break
		hp.append_array([id, 1 if id != 0 else 0])
	var w = tv.weapons
	var w2 = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w2)
	var bdb: Dictionary = tv.mission_bdb
	w2.setup(tv, {"armament": {"hardpoints": hp}}, tv._player_object(bdb), bdb, w.descriptor)
	tv.weapons = w2
	w.queue_free()
	print("loadout ", hp)


func _place_props() -> void:
	var am: GDScript = load("res://aircraft/aircraft_model.gd")
	var ground: float = tv.aircraft.global_position.y
	var hp := tv.aircraft.find_child("height", true, false) as Node3D
	if hp != null:
		ground = hp.global_position.y
	for p in PROPS:
		var node: Node3D
		var path := String(p[0])
		if path.begins_with("jet:"):
			node = am.create(path.trim_prefix("jet:"), -1, true)
			node.scale = tv.aircraft.scale
		else:
			node = Gltf.instance(Gltf.object(path))
		tv.add_child(node)
		var raw := Gltf.model_aabb(node)
		if not path.begins_with("jet:"):
			node.scale = Vector3.ONE * float(p[4]) / maxf(raw.size.x, raw.size.z)
		var pos := _at(Vector3(p[1], 0.0, p[2]), path.begins_with("jet:"))
		var f := _frame()
		node.global_basis = Basis.looking_at(f[1], Vector3.UP).rotated(Vector3.UP, deg_to_rad(p[3])).scaled(node.scale)
		node.global_position = Vector3(pos.x, ground, pos.z)
		if path.begins_with("jet:"):
			var h := node.find_child("height", true, false) as Node3D
			if h != null:
				node.global_position.y += ground - h.global_position.y
		else:
			var h = tv.terrain.height_at(node.global_position)
			node.global_position.y = (float(h) if h != null else ground) - raw.position.y * node.scale.y


class CamPin:
	extends Node
	var place: Callable

	func _process(_delta: float) -> void:
		place.call()
