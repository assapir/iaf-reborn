# Dev helper (not run by tools/test.sh): the big fight (big_fight.gd; docs/ai.md §22) in a real render, from a scripted
# camera director: it cuts every few seconds to what is happening, first a missile just launched (the camera trails
# it), then Kidon 1-2's attack run, the based pair's take-off, then in turn a jet chased with its nearest enemy in
# view, the convoy, the drones and the S-300 battery. Prints "SEG <kind> <name> <first frame> <last frame>" for each
# shot (process frames from the start: the movie's frames) to cut the clip from. MOVIE_S: the sim seconds flown
# (default 240). "DOWN <name> <frame>" marks each unit going down. With Godot's movie writer:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> \
#     --resolution 1280x720 --path modern-iaf --write-movie <out.avi> --fixed-fps 30 \
#     -s ../modern-iaf/tests/_big_fight_movie.gd
# BIGFIGHT_BENCH=1 instead measures the drawing cost (modern-iaf/docs/ai-plan.md X5, K12) 20 s after the sort, the
# camera chasing Kidon 1-3: the GPU time with everything drawn against each part hidden alone, by turns (Kidon 1-3,
# the other AI jets, the ground units and the drones), and the frame time (vsync off, no movie writer):
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 BIGFIGHT_BENCH=1 -- \
#     --log-file <temp> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_big_fight_movie.gd
extends "res://../tests/godot/base.gd"

const SHOT_MIN := 5.0
const SHOT_MAX := 9.0
const MISSILE_MAX := 12.0
const STRIKE_MAX := 14.0
## A missile shot: the launcher this long, then its target with the missile coming in.
const LAUNCH_S := 3.0
const LEAD_GAP := 40.0

var sc
var tv: Node
var _cam: Camera3D
## The shot now: {kind, ent (an entity or a missile), foe (an entity or {}), t0 (sim s), f0 (frame), name}.
var _shot := {}
var _shown := {}
var _turn := 0
var _at_lead := -INF
var _eye := Vector3.INF
## The camera's kind in the last frame (a missile shot cuts from the launcher to the target).
var _kind := ""


func run() -> void:
	settings().show_info = false
	sc = load("res://../modern-iaf/tests/big_fight.gd").new()
	if not await sc.start(self) or not sc.spawn(self):
		return
	tv = sc.tv
	tv.addon.ui.visible = false
	tv.in_cockpit = false
	_cam = tv.chase
	if OS.get_environment("BIGFIGHT_BENCH") == "1":
		await _bench()
		return
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	var total := float(OS.get_environment("MOVIE_S")) if OS.get_environment("MOVIE_S") != "" else 240.0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < total:
		sc.step()
		_direct()
		await process_frame
	_end_shot()
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	check(true, "the big fight filmed (%.0f s)" % total)


## Picks the next shot when the one now has run its time or lost its subject; prints "DOWN <name> <frame>" for
## each unit of the fight that goes down.
func _direct() -> void:
	var now: float = tv._sim_time
	for e in sc.jets() + sc.sites + sc.convoy.ents + sc.salvo.ents:
		if e != null and int(e.state) >= 3 and not _shown.has(e.key):
			_shown[e.key] = true
			print("DOWN %s %d" % [e.name, Engine.get_process_frames()])
	var fresh = _fresh_missile()
	if not _shot.is_empty():
		var age: float = now - float(_shot.t0)
		var gone: bool = _shot.kind != "missile" and int(_shot.ent.get("state", 0)) >= 3 and age > 3.0
		var done: bool = age > float({"missile": MISSILE_MAX, "strike": STRIKE_MAX}.get(_shot.kind, SHOT_MAX))
		if _shot.kind == "missile" and _shot.ent.ended and age > float(_shot.get("end", age)) + 2.5:
			done = true
		if _shot.kind == "missile" and _shot.ent.ended and not _shot.has("end"):
			_shot["end"] = age
		var cut: bool = fresh != null and _shot.kind not in ["missile", "strike"] and age > SHOT_MIN
		if not (done or gone or cut):
			return
		_end_shot()
	if fresh != null:
		_shown[fresh.get_instance_id()] = true
		var o: Dictionary = fresh.get_meta("owner", {})
		if fresh.target_key == String(tv.runtime.player_entity().key):
			_at_lead = now
		_begin("missile", fresh, tv.runtime.entities.get(fresh.target_key, {}), String(o.get("name", "?")))
		return
	var fa = tv.ai.flight_ai
	var w2: Dictionary = sc.wing[0]
	if int(w2.state) < 3 and String(fa.state(2).get("strike", "")) == "run":
		if not _shown.has("strike") or not _shown.strike:
			_shown["strike"] = true
			_begin("strike", w2, sc.convoy.ents[0], "Kidon 1-2 attack")
			return
	for e in sc.based:
		var st: Dictionary = e.pilot.flight.state()
		var key := "takeoff%d" % int(st.get("on_ground", false) and float(st.get("speed_kt", 0.0)) > 40.0)
		if int(e.state) < 3 and st.engine_on and not e.pilot.airborne and not _shown.has(key):
			_shown[key] = true
			_begin("side", e, {}, "scramble " + key)
			return
	_turn += 1
	var air: Array = sc.jets().filter(func(e): return int(e.state) < 3 and e.pilot.airborne)
	match _turn % 4:
		0:
			var g: Array = sc.convoy.ents.filter(func(e): return int(e.state) < 3)
			if not g.is_empty():
				_begin("ground", g[0], {}, "convoy")
				return
		1:
			var d: Array = sc.salvo.ents.filter(func(e): return e != null and e.has("drone"))
			if not d.is_empty():
				_begin("chase", d[0], {}, "drone")
				return
		2:
			if int(sc.sites[1].state) < 3:
				_begin("ground", sc.sites[1], {}, "S-300")
				return
	if not air.is_empty():
		var e: Dictionary = air[_turn % air.size()]
		_begin("chase", e, _nearest_foe(e), String(e.name))


## A missile launched within the last second, not shown yet; null none. One at the lead (invulnerable: the dull
## end) at most every LEAD_GAP s.
func _fresh_missile():
	var me := String(tv.runtime.player_entity().key)
	for m in tv.weapons.missiles:
		if _shown.has(m.get_instance_id()) or m.ended or tv.weapons.now - float(m.t0) > 1.0:
			continue
		if m.target_key == me and tv._sim_time - _at_lead < LEAD_GAP:
			continue
		return m
	return null


func _nearest_foe(e: Dictionary) -> Dictionary:
	var best := {}
	var d := INF
	var others: Array = sc.jets() + [tv.runtime.player_entity()]
	for o in others:
		if int(o.side) != int(e.side) and int(o.state) < 3:
			var x: float = Vector3(o.world).distance_to(e.world)
			if x < d:
				d = x
				best = o
	return best


func _begin(kind: String, ent, foe: Dictionary, name: String) -> void:
	_shot = {"kind": kind, "ent": ent, "foe": foe, "t0": tv._sim_time, "f0": Engine.get_process_frames(), "name": name}
	_eye = Vector3.INF


func _end_shot() -> void:
	if not _shot.is_empty():
		print("SEG %s %s %d %d" % [_shot.kind, _shot.name, _shot.f0, Engine.get_process_frames()])
	_shot = {}


## The camera of the shot, in the world, each frame before drawing (the views would move it otherwise).
func _pre_draw() -> void:
	if _shot.is_empty() or not is_instance_valid(_cam):
		return
	var kind: String = _shot.kind
	var e: Dictionary = {}
	var m = null
	if kind == "missile":
		# The launcher first (a jet chased, a site from the ground), then the target with the missile coming in.
		m = _shot.ent
		var o: Dictionary = m.get_meta("owner", {})
		var target: Dictionary = _shot.foe
		if tv._sim_time - float(_shot.t0) < LAUNCH_S or target.is_empty():
			e = o
			kind = "chase" if o.get("pilot") != null or o.get("player", false) else "ground"
		else:
			e = target
			kind = "incoming"
	else:
		e = _shot.ent
	if e.is_empty():
		return
	var at: Vector3 = tv.runtime._world_of(e)
	var h := deg_to_rad(float(e.get("heading", 0.0)))
	var fwd := Vector3(sin(h), cos(h), 0)
	var flat := Vector3(fwd.x, fwd.y, 0).normalized() if Vector2(fwd.x, fwd.y).length() > 0.01 else Vector3(0, 1, 0)
	var right := Vector3(flat.y, -flat.x, 0)
	var eye: Vector3
	var look := at
	match kind:
		"incoming":
			# Beyond the target from the missile: it comes in toward the camera past the target.
			var mp: Vector3 = m.last_pos if m.ended else m.position(tv.weapons.now)
			var away: Vector3 = (at - mp).normalized() if mp.distance_to(at) > 1.0 else -fwd
			eye = at + away * 45.0 + right * 12.0 + Vector3(0, 0, 8)
		"chase", "strike":
			eye = at - flat * 30.0 + right * 9.0 + Vector3(0, 0, 7)
			var f: Dictionary = _shot.foe
			look = at + flat * 60.0
			var to_f: Vector3 = (tv.runtime._world_of(f) - at) if not f.is_empty() else Vector3.ZERO
			if to_f.length() < 15000.0 and to_f.normalized().dot(flat) > 0.3:
				look = at + to_f.normalized() * 60.0  # the enemy ahead in the frame beyond it
		"side":
			eye = at + right * 70.0 - flat * 30.0 + Vector3(0, 0, 12)
		"ground":
			eye = at + Vector3(70, -90, 28)
	# The camera eases after its subject (no jolt as the subject turns), set at once on a cut.
	if kind != _kind:
		_eye = Vector3.INF  # a cut within the shot
	_kind = kind
	_eye = eye if _eye == Vector3.INF or kind == "ground" else _eye.lerp(eye, 0.5)
	var g = tv.mission_ground(_eye)
	if g != null and _eye.z < float(g) + 3.0:
		_eye.z = float(g) + 3.0
	var e3: Vector3 = tv.world_to_scene(_eye)
	var xf := Transform3D(Basis.looking_at(tv.world_to_scene(look) - e3, Vector3.UP), e3)
	_cam.global_transform = xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
	_cam.set_perspective(50.0, 0.1, 40000.0)


## The drawing cost, each part by turns shown and hidden (the fight moves on, so the parts are compared interleaved).
func _bench() -> void:
	var t0: float = tv._sim_time
	while not "sort" in sc.orders and tv._sim_time - t0 < 120.0:
		sc.step()
		await process_frame
	await fly(tv, 20.0)
	var near: Dictionary = sc.wing[1]
	_shot = {"kind": "chase", "ent": near, "foe": {}, "t0": 0.0, "f0": 0, "name": "bench"}
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var shown := func(e): return e != null and e.get("node") is Node3D and e.node.visible
	var jets: Array = sc.jets().filter(func(e): return shown.call(e) and not is_same(e, near))
	var ground: Array = (sc.sites + sc.convoy.ents + sc.salvo.ents).filter(shown)
	var a: Array = await _compare("the chased jet (30 m off)", [near])
	var b: Array = await _compare("the other AI jets", jets)
	var c: Array = await _compare("the ground units and drones", ground)
	print(
		(
			(
				"K12 GPU: whole scene %.2f ms GPU, %.2f ms a frame; the chased jet (30 m off) %.3f ms GPU, %.3f ms "
				+ "per other AI jet (%d), %.3f ms per ground unit or drone (%d)"
			)
			% [
				a[0],
				a[2],
				a[0] - a[1],
				(b[0] - b[1]) / maxi(jets.size(), 1),
				jets.size(),
				(c[0] - c[1]) / maxi(ground.size(), 1),
				ground.size()
			]
		)
	)
	check(true, "bench done")


## [GPU ms shown, GPU ms hidden, frame ms shown] of the entities `ents`: 20 rounds of 40 frames shown, then 40 hidden,
## the first 10 frames after each switch left out.
func _compare(what: String, ents: Array) -> Array:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := [0.0, 0.0]
	var ft := 0.0
	var n := 0
	for r in 40:
		var hide := r % 2 == 1
		for e in ents:
			if is_instance_valid(e.node):
				e.node.visible = not hide
		for i in 40:
			sc.step()
			var t := Time.get_ticks_usec()
			await process_frame
			if i >= 10:
				gpu[int(hide)] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				if not hide:
					ft += (Time.get_ticks_usec() - t) / 1000.0
					n += 1
	for e in ents:
		if is_instance_valid(e.node):
			e.node.visible = true
	var out := [gpu[0] / n, gpu[1] / n, ft / n]
	print("BENCH %s: GPU %.2f ms shown, %.2f ms hidden (frame %.2f ms)" % [what, out[0], out[1], out[2]])
	return out
