# The tyres stand on the drawn ground (the user, 2026-11-15: "the wheels of the plane are not strictly above ground
# but half on it"): each jet at its base (the Sufa at Ramon, the Barak at Ramat David, the F-35I at Nevatim), parked
# after the gear settles, taxiing along the base's taxi-out path, and lined up on the runway; its outside model's tyre
# bottoms (the lowest vertices of the nose wheel and of each main wheel) within TOLERANCE_M of the terrain's surface
# under each (the apron and the runway are the terrain's own mesh, painted by terrain.gdshader). The 6-DoF stands its
# gear at the model's wheels (IafFlight.set_gear_clearance) and each wheel on the ground under itself
# (set_ground_slope). The taxi is test_mvp.gd's (_start, _taxi).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_wheels.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

## A tyre's bottom within this of the ground, m (above: floating; below: sunk). Strut sag is not drawn.
const TOLERANCE_M := 0.06


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-wheels-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	for id in JETS:
		var tv := await _start(JETS[id][1] + "_takeoff")
		tv.addon.rules = {}  # unscored: no clearance needed to taxi
		tv._command([28, 6, 0])  # the chase view: the outside model drawn
		await fly(tv, 3.0)
		_check_tyres(tv, "%s parked" % JETS[id][0])
		tv._command([200, 0, 0])  # Start engine
		check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "%s: the engine runs" % id)
		var s: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))[JETS[id][2]]
		var path: Array = []
		for i in int(s.TaxiWayPtsFrom):
			path.append(Vector2(float(s["FromTaxiPtX%d" % i]), float(s["FromTaxiPtY%d" % i])))
		tv.brakes = false
		tv.flight.set_switch("parking_brake", 0)  # a ground start is held by it
		tv.scripted_stick = Vector2.ZERO
		# The taxi out runs on while the tyres are measured on the way (20 s of sim time in).
		var done := {}
		var go := func() -> void: done.ok = await _taxi(tv, path, float(s.RunwayNumber))
		go.call()
		await fly(tv, 20.0)
		var kt := float(tv.flight.state().get("speed_kt", 0.0))
		check(kt > 3.0, "%s: taxiing (%.0f kt)" % [id, kt])
		_check_tyres(tv, "%s taxiing" % JETS[id][0])
		while not done.has("ok"):
			await process_frame
		check(done.ok, "%s: lined up on the runway" % id)
		await fly(tv, 2.0)
		_check_tyres(tv, "%s on the runway" % JETS[id][0])
		Engine.time_scale = 1.0


## The lowest vertex of each wheel (nose: more than 1.5 m ahead of the c.g.; mains: either side) against the
## terrain's height under it.
func _check_tyres(tv: Node, what: String) -> void:
	var a: Node3D = tv.aircraft
	var fwd: Vector3 = -tv.rig.global_transform.basis.z
	var right: Vector3 = tv.rig.global_transform.basis.x
	var low := {}
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		for sf in mi.mesh.get_surface_count():
			var arr = mi.mesh.surface_get_arrays(sf)
			if arr.is_empty():
				continue
			for v in arr[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = xf * v
				var d: Vector3 = w - tv.rig.global_position
				var k := "nose" if d.dot(fwd) > 1.5 else ("right" if d.dot(right) > 0.0 else "left")
				if not low.has(k) or w.y < low[k].y:
					low[k] = w
	check(low.size() == 3, "%s: the three wheels found %s" % [what, low.keys()])
	for k in low:
		var g = tv.terrain.height_at(low[k])
		var gap: float = low[k].y - float(g) if g != null else INF
		check(absf(gap) <= TOLERANCE_M, "%s: the %s tyre on the ground (%+.3f m)" % [what, k, gap])
