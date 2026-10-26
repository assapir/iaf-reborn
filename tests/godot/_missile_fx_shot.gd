# Dev helper (not run by tools/test.sh): real-render pictures of a missile's motor flame and smoke trail with
# Preferences > Graphics > MORE "Particle effects: Detailed" (mission/missile_fx.gd, docs/rendering.md §6): the launch
# from beside, the climb seen from behind, the trail mid-flight, and the trail lingering after the hit. A stand-in
# missile (a 3 m grey cylinder) flies from 250 m/s at 100 m/s², its motor burning MFX_BURN s (default 5), then coasts
# and bursts at 9 s. Needs a window:
#   tools/godot_window.sh MFX_OUT=/tmp/mfx MFX_CLOCK=19.2 IAF_DEFAULT_SETTINGS=1 -- --log-file /tmp/m.log \
#     --path game --resolution 1920x1080 -s ../tests/godot/_missile_fx_shot.gd
# Saves MFX_OUT/<shot>_<clock>_<after|before>.png; MFX_CLOCK = the time of day in hours (default: the mission's),
# MFX_LOOK=before = the same shots with Particle effects Original, FX_MISSION the mission (default 231).
extends "res://../tests/godot/base.gd"

var tv: Node
var cam: Camera3D
var out := ""
var tag := ""
var look := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("MFX_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	# MFX_LOOK=before: the same shots with Particle effects Original.
	look = "before" if OS.get_environment("MFX_LOOK") == "before" else "after"
	settings().particle_effects = look == "after"
	settings().show_info = false
	var mid := OS.get_environment("FX_MISSION")
	seed(231)  # the same cloud texture (cloud_layer.gd: randi() % 6) before and after
	tv = await start_mission(int(mid) if mid != "" else 231)
	tv.frozen = true
	tv.fm_stopped = true
	var clock := OS.get_environment("MFX_CLOCK")
	tag = clock if clock != "" else "mission"
	if clock != "" and tv.runtime != null:
		tv.runtime.misc["0x460"] = float(clock) * 3600.0 - tv.runtime.now
		tv._tod_t = -INF
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = false
	var keep := GDScript.new()
	keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
	keep.reload()
	cam = Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.far = 60000.0
	tv.add_child(cam)
	cam.make_current()
	var fwd: Vector3 = -tv.rig.global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var l0: Vector3 = _ground(tv.rig.global_position + fwd * 1500.0) + Vector3(0, 1200, 0)
	var dir := (side + Vector3(0, 0.12, 0)).normalized()
	var burn := float(OS.get_environment("MFX_BURN")) if OS.get_environment("MFX_BURN") != "" else 5.0
	var body := _missile()
	tv.add_child(body)
	var shots := [
		[0.35, "launch", l0 - fwd * 45.0 + Vector3(0, 4, 0) + dir * 20.0, l0 + dir * 60.0],
		[1.6, "behind", l0 - dir * 25.0 + Vector3(0, 3, 0), l0 + dir * 400.0],
		[3.5, "midflight", l0 - fwd * 350.0 + dir * 500.0 + Vector3(0, 60, 0), l0 + dir * 900.0],
		[13.0, "linger", l0 - fwd * 600.0 + dir * 900.0 + Vector3(0, 120, 0), l0 + dir * 1300.0],
	]
	_look(shots[0][2], shots[0][3])
	await frames(20)
	var t := 0.0
	var gone := false
	var k := 0
	while k < shots.size():
		var dt: float = tv.get_process_delta_time()  # the same clock as missile_fx.gd
		t += dt
		var s := 250.0 * t + 50.0 * t * t if t < burn else 250.0 * burn + 50.0 * burn * burn + 750.0 * (t - burn)
		var v := dir * (250.0 + 100.0 * minf(t, burn))
		var p := l0 + dir * s
		if t < 9.0:
			body.global_position = p
			body.basis = Basis.looking_at(v.normalized(), Vector3.UP)
			if t < burn:
				tv.trails.emit("shot_missile", p - dir * 2.5, tv.trails.MISSILE)
		elif not gone:
			gone = true
			body.visible = false
			tv.effects.explosion(p, tv.effects.F_FIREBALL | tv.effects.F_PUFF, 1.0, 5.0, 0.0)
		if t >= shots[k][0]:
			_look(shots[k][2], shots[k][3])
			await _save_png(shots[k][1])
			k += 1
		await process_frame


func _missile() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.065
	c.bottom_radius = 0.065
	c.height = 3.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.75, 0.72)
	c.material = m
	mi.mesh = c
	mi.rotation = Vector3(PI / 2, 0, 0)
	n.add_child(mi)
	return n


func _ground(p: Vector3) -> Vector3:
	var h = tv.terrain.height_at(p)
	return Vector3(p.x, float(h) if h != null else p.y, p.z)


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _save_png(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join("%s_%s_%s.png" % [name, tag, look])
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
