# The floating origin (docs/rendering.md §11, terrain_view.gd _rebase), headless, on the Sufa's weapons range: the
# jet put 300 km from the flight's start, flying.
# - The scene node is moved by −render_shift, a multiple of REBASE_M within REBASE_M of the camera on X and Z.
# - A rebase while flying: the camera's scene position goes on without a jump.
# - Precision there: moved 0.5 mm a frame, a part of the jet 1.3 m from the eye keeps its place against the camera to
#   0.5 mm, inside the F-35I's 9.6 mm screen pull (cockpit3d.gd SCREEN_PULL); without the shift a global position
#   300 km out rounds to 31 mm.
# - The HUD's projection of a world point lands on the node drawn there.
# - Hit accuracy: a gun pass brings down a drone 300 km from the start.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_floating_origin.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const FAR_M := 300000.0

var tv: Node
var w


func _press(k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


## The jet level at world `at` on `heading` (degrees) at `speed` m/s.
func _put(at: Vector3, heading: float, speed: float) -> void:
	var h := deg_to_rad(heading)
	var sp: Vector3 = tv.world_to_scene(at)
	var v: Vector3 = w.Terrain.dir_to_scene(Vector3(sin(h), cos(h), 0)) * speed
	tv.rig.position = sp
	tv.flight.start(settings().own_dir(), tv.player.fm_section, sp, Vector3(0, 0, heading), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _behind(e: Dictionary, dist: float, speed: float) -> void:
	var h := deg_to_rad(float(e.heading))
	_put(tv.runtime._world_of(e) - Vector3(sin(h), cos(h), 0) * dist, float(e.heading), speed)


func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await fly(tv, 0.1)
	return f.call()


func _shift_ok() -> bool:
	var c: Vector3 = tv.to_local(tv.get_viewport().get_camera_3d().global_position)
	var s: Vector3 = tv.render_shift
	return (
		tv.position == -s
		and fmod(s.x, tv.REBASE_M) == 0.0
		and fmod(s.z, tv.REBASE_M) == 0.0
		and s.y == 0.0
		and maxf(absf(c.x - s.x), absf(c.z - s.z)) <= tv.REBASE_M
	)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	check(load("res://flight/fly.gd").prepare(id), "mission %d prepared as the front end's Fly" % id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-origin", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true
	w = tv.weapons
	check(tv.render_shift == Vector3.ZERO and tv.position == Vector3.ZERO, "at the start: no shift")
	# 300 km from the start, inside the theatre (the first way with terrain there).
	var j: Vector3 = tv.player_world()
	var far := Vector3.INF
	for d in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var p: Vector3 = j + d * FAR_M
		var t: Vector2 = tv.terrain.godot_to_terrain(tv.world_to_scene(p))
		var th: Array = tv.terrain._theatre
		if t.x > th[0] and t.x < th[2] and t.y > th[1] and t.y < th[3]:
			far = p
			break
	check(far != Vector3.INF, "terrain 300 km from the start")
	if far == Vector3.INF:
		return
	var g = tv.mission_ground(far)
	far.z = float(g if g != null else 0.0) + 1500.0
	var shifts := []
	tv.rebased.connect(func(d: Vector3): shifts.append(d))
	_put(far, 0.0, 200.0)
	await fly(tv, 1.0)
	check(not shifts.is_empty() and _shift_ok(), "300 km out: the scene shifted by %s (%s)" % [tv.render_shift, shifts])

	# A rebase in flight: due east at 250 m/s from 1 km short of the next cell's edge; the camera's scene position
	# moves on by its speed each frame, without a jump.
	var e0: float = tv.render_shift.x + tv.REBASE_M - 1000.0
	_put(Vector3(tv.terrain.world_origin.x + e0, far.y, far.z), 90.0, 250.0)
	await frames(2)
	shifts.clear()
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var prev: Vector3 = tv.to_local(cam.global_position)
	var worst := 0.0
	var t0: float = tv._sim_time
	while shifts.is_empty() and tv._sim_time - t0 < 10.0:
		await process_frame
		var now: Vector3 = tv.to_local(cam.global_position)
		worst = maxf(worst, (now - prev).length())
		prev = now
	for i in 5:
		await process_frame
		var now: Vector3 = tv.to_local(cam.global_position)
		worst = maxf(worst, (now - prev).length())
		prev = now
	check(
		shifts.size() == 1 and shifts[0] == Vector3(tv.REBASE_M, 0, 0) and _shift_ok(),
		"flying east the scene shifted one cell (%s)" % [shifts]
	)
	# 250 m/s: about 4 m a frame; a jump would be the cell, 4096 m.
	check(worst < 20.0, "the camera moved on through the rebase without a jump (at most %.1f m a frame)" % worst)

	# Precision: the flight model stopped, the rig moved 0.5 mm a frame; a part of the jet 1.3 m from the eye (a 3D
	# cockpit's screen, drawn in the flight's world) keeps its place against the camera.
	tv.fm_stopped = true
	var part := Node3D.new()
	tv.rig.add_child(part)
	part.position = Vector3(0.31, -0.47, -1.13)
	var want: Vector3 = tv.camera.transform.affine_inverse() * part.position
	var err := 0.0
	var base: Vector3 = tv.rig.position
	for i in 20:
		tv.rig.position = base + Vector3(i * 0.0005, 0, i * 0.0005)
		await process_frame
		var rel: Vector3 = tv.camera.global_transform.affine_inverse() * part.global_position
		err = maxf(err, (rel - want).length())
	part.queue_free()
	check(err < 5e-4, "300 km out a part 1.3 m from the eye holds its place against it to %.3f mm" % (err * 1000.0))
	tv.fm_stopped = false

	# Hit accuracy: a drone 300 km out, a gun pass from 200 m behind it (as test_enemy_drones.gd).
	var dr: Node = load("res://shared/ai/drones.gd").of(tv)
	var at: Vector3 = tv.player_world()
	at.z -= 1000.0
	var salvo: Dictionary = dr.spawn([at, at + Vector3(0, 4000, 0)], 1, 500.0, 5.0)
	check(not salvo.is_empty(), "a drone spawned 300 km out")
	if salvo.is_empty():
		return
	check(await _until(func(): return salvo.ents.all(func(x): return x != null), 12.0), "launched")
	var drone: Dictionary = salvo.ents[0]
	_behind(drone, 300.0, 200.0)
	await fly(tv, 0.2)
	# The HUD's frame: the drone's world point projects where its node is drawn.
	var a: Vector2 = tv.camera.unproject_position(tv.world_to_global(tv.runtime._world_of(drone)))
	var b: Vector2 = tv.camera.unproject_position(drone.node.global_position)
	check(a.distance_to(b) < 1.0, "the HUD's projection lands on the drone (%.2f px off)" % a.distance_to(b))
	_press(KEY_A, true, true)
	_press(KEY_A, false, true)
	w.safety_off = true
	for attempt in 3:
		_press(KEY_TAB)
		for k in 12:
			_behind(drone, 200.0, 200.0)
			await frames(1)
			var o: Dictionary = w.own()
			_put(tv.runtime._world_of(drone) - w.GunRounds.shot_dir(o.fwd, o.up) * 200.0, float(drone.heading), 200.0)
			await fly(tv, 0.05)
		_press(KEY_TAB, false)
		await fly(tv, 1.0)
		if int(drone.state) >= 3:
			break
	check(int(drone.state) >= 3, "300 km out a gun pass brings the drone down (state %d)" % drone.state)
	check(_shift_ok(), "the shift still follows the camera (%s)" % tv.render_shift)
