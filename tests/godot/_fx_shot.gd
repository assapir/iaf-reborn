# Dev helper (not run by tools/test.sh): real-render pictures of the effects (docs/rendering.md §6)
# from a fixed camera near the player's jet: a ground vehicle's and an air kill's explosion, a missile hit, a missile
# trail and the engine heat haze. FX_DETAILED=1 turns on Preferences > Graphics > MORE "Particle effects: Detailed". Needs a window:
#   FX_OUT=/tmp/fx FX_DETAILED=1 IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_fx_shot.gd
# Saves FX_OUT/<scene>_<t>_<original|detailed>.png; FX_MISSION picks the mission (default 231).
extends "res://../tests/godot/base.gd"

var tv: Node
var cam: Camera3D
var out := ""
var mode := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("FX_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Settings().particle_effects = OS.get_environment("FX_DETAILED") == "1"
	mode = "detailed" if Settings().particle_effects else "original"
	Settings().show_info = false
	var mid := OS.get_environment("FX_MISSION")
	tv = await start_mission(int(mid) if mid != "" else 231)
	tv.frozen = true
	tv.fm_stopped = true
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = false
	# A camera that stays current after terrain_view's own view update each frame.
	var keep := GDScript.new()
	keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
	keep.reload()
	cam = Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.far = 60000.0
	tv.add_child(cam)
	cam.make_current()
	var fx: Node = tv.effects
	var fwd: Vector3 = -tv.rig.global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var g := _ground(tv.rig.global_position + fwd * 900.0)
	if OS.get_environment("FX_ONLY") != "haze":  # FX_ONLY=haze: only the engines
		await _scenes(g, fwd, side, fx)
	# 6. The engines at full afterburner, from behind and above.
	for f in tv.aircraft.flames:
		f.set_process(false)
		f.level = 100
	var tail: Vector3 = tv.aircraft.global_position
	var nz: Vector3 = (
		tv.aircraft.flames[0].global_transform * tv.aircraft.flames[0].nozzle
		if not tv.aircraft.flames.is_empty()
		else tail
	)
	_look(nz - fwd * 12.0 + side * 2.5 + Vector3(0, 1.0, 0), nz + fwd * 60.0)
	tv.views.set_cockpit(tv.views.CHASE)
	for i in 30:
		tv.aircraft.visible = true
		for f in tv.aircraft.flames:
			f.level = 100
			f.rebuild()
		await process_frame
	await _save_png("haze")


func _scenes(g: Vector3, fwd: Vector3, side: Vector3, fx: Node) -> void:
	# 1. A bomb's hit on the ground (the generic bomb: flash + smoke streamers, player_weapons.gd).
	_look(g - fwd * 380.0 + side * 60.0 + Vector3(0, 70, 0), g + Vector3(0, 35, 0))
	await frames(30)
	fx.explosion(g, fx.F_FLASH | fx.F_SMOKE_TRAILS, 4.0, 95.0, g.y)
	await _shots("bomb", [0.15, 0.6, 2.0, 6.0])
	# 2. A ground vehicle destroyed (class 8: 0x188a, scale 4).
	var g1 := _ground(g + side * 500.0)
	_look(g1 - fwd * 260.0 + Vector3(0, 45, 0), g1 + Vector3(0, 20, 0))
	var e: Dictionary = fx.explosion_for(8, 0, true, false)
	fx.explosion(g1 + Vector3(0, 2, 0), e.flags, e.scale, e.duration, g1.y, 6.0)
	await _shots("vehicle", [0.3, 1.5, 6.0])
	# 3. A missile's hit on the ground (fireball + puff, player_weapons.gd).
	var g2 := _ground(g - side * 500.0)
	_look(g2 - fwd * 450.0 + Vector3(0, 80, 0), g2 + Vector3(0, 60, 0))
	fx.explosion(g2, fx.F_FIREBALL | fx.F_PUFF, 1.0, 5.0, g2.y)
	await _shots("hit", [0.2, 0.6, 1.5])
	# 4. An aircraft destroyed in the air (class 1, high: 0x407a).
	var a := g + Vector3(0, 900, 0)
	_look(a - fwd * 900.0 + Vector3(0, -150, 0), a)
	e = fx.explosion_for(1, 0, false, false)
	fx.explosion(a, e.flags, e.scale, e.duration, g.y, 8.0)
	await _shots("air", [0.3, 0.9, 3.0])
	# 5. A missile trail crossing the view at 500 m/s.
	if tv.trails != null:
		var p0 := g + side * 2000.0 + Vector3(0, 400, 0) - side * 900.0
		_look(
			g + side * 2000.0 + Vector3(0, 385, 0) - fwd * 140.0, g + side * 2000.0 + Vector3(0, 400, 0) + side * 200.0
		)
		var t := 0.0
		while t < 2.5:
			var dt: float = tv.get_process_delta_time()
			t += dt
			tv.trails.emit(
				"shot_missile", p0 + side * 500.0 * t + Vector3(0, 40.0 * sin(t * 2.0), 0), tv.trails.MISSILE
			)
			await process_frame
		var head: Vector3 = p0 + side * 500.0 * t
		await _save_png("trail_2.5")


func _ground(p: Vector3) -> Vector3:
	var h = tv.terrain.height_at(p)
	return Vector3(p.x, float(h) if h != null else p.y, p.z)


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _shots(name: String, times: Array) -> void:
	var t0 := Time.get_ticks_msec()
	for t in times:
		while Time.get_ticks_msec() - t0 < t * 1000.0:
			await process_frame
		await _save_png("%s_%s" % [name, str(t)])


func _save_png(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join("%s_%s.png" % [name, mode])
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
