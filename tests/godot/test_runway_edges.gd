# Landings at the edges of every airbase's runway footprint (terraintype.dat bit 0x10, docs/formats/ptt.md
# "Terrain types"): for the ten bases of iaf.ibx (docs/ai.md §9) the jet touches down gently 40 m inside and
# 40 m outside the footprint at the threshold end, the far end and both sides. Inside is airbase ground (no
# crash); outside, land above 25.7 m/s is rough ground and water is water (FUN_005bb9f0, docs/flight-model.md
# §15.6). The flight model is fed as the flight scene feeds it (terrain_view.gd _process), without a mission,
# so a crash ends nothing.
extends "res://../tests/godot/base.gd"

const BASES := ["Ramon", "David", "TelNof", "Refidim", "Inshas", "Damescuss", "Kuzeir", "Bley", "Ryak", "Aman"]
const MARGIN := 40.0
const SPEED := 70.0  # m/s along the heading at the touchdown (above the 25.7 m/s rough-ground limit)
const DT := 1.0 / 60.0

var install := ""
var clearance := 0.0
## How far the jet floats from its start to the touchdown (measured on the first base's runway).
var lead := -1.0


func run() -> void:
	install = Settings().assets_dir().path_join("install")
	# The F-16's gear clearance as the flight scene sets it (its model's `height` helper).
	var tv = await start_mission(311)
	var h := tv.aircraft.find_child("height", true, false) as Node3D
	clearance = -h.position.y * tv.aircraft.scale.y if h != null else 0.0
	tv.frozen = true
	var bases := _bases()
	check(bases.size() == BASES.size(), "iaf.ibx: %d airbases" % bases.size())
	for b in bases:
		await _base(b)


func _base(b: Dictionary) -> void:
	var t: Node3D = load("res://terrain/terrain.gd").new()
	var focus := Node3D.new()
	root.add_child(focus)
	root.add_child(t)
	t.world_origin = Vector2(b.LineupLocX, b.LineupLocY)
	t.focus = focus
	await frames(1)
	var hdg: float = b.RunwayNumber
	var fwd := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	var left := Vector2(-fwd.y, fwd.x)
	var at := func(along: float, lat: float) -> Vector2: return fwd * along + left * lat
	var mask := func(p: Vector2) -> int: return t.surface_at(Vector3(p.x, 0, -p.y))
	var on := func(p: Vector2) -> bool: return (mask.call(p) & t.SURFACE_RUNWAY) != 0
	check(on.call(Vector2.ZERO), "%s: the lineup point is inside the runway footprint" % b.name)
	# The footprint along the runway axis (5 m steps) and across it at the middle (1 m steps).
	var far := 0.0
	while on.call(at.call(far + 5.0, 0.0)) and far < 40000.0:
		far += 5.0
	var back := 0.0
	while on.call(at.call(-back - 5.0, 0.0)) and back < 40000.0:
		back += 5.0
	var mid := (far - back) / 2.0
	var lw := 0.0
	while on.call(at.call(mid, lw + 1.0)) and lw < 20000.0:
		lw += 1.0
	var rw := 0.0
	while on.call(at.call(mid, -rw - 1.0)) and rw < 20000.0:
		rw += 1.0
	print("%s: footprint %d m along the runway (%d behind the lineup point), %d m wide at the middle" % [b.name, far + back, back, lw + rw])
	# [case, touchdown point, heading]: the ends are approached along the runway, the sides parallel to it.
	var cases := [
		["threshold end inside", at.call(-back + MARGIN, 0.0), hdg],
		["threshold end outside", at.call(-back - MARGIN, 0.0), hdg],
		["far end inside", at.call(far - MARGIN, 0.0), hdg],
		["far end outside", at.call(far + MARGIN, 0.0), hdg],
		["left edge inside", at.call(mid, lw - MARGIN), hdg],
		["left edge outside", at.call(mid, lw + MARGIN), hdg],
		["right edge inside", at.call(mid, -rw + MARGIN), hdg],
		["right edge outside", at.call(mid, -rw - MARGIN), hdg],
	]
	var flight = ClassDB.instantiate("IafFlight")
	if lead < 0.0:
		await _touch_down(t, focus, flight, at.call(mid, 0.0), hdg)
	for c in cases:
		var r: Dictionary = await _touch_down(t, focus, flight, c[1], c[2])
		var m: int = r.mask
		var inside: bool = String(c[0]).ends_with("inside")
		check(((m & t.SURFACE_RUNWAY) != 0) == inside, "%s %s: touched down %s the footprint (mask %x)" % [b.name, c[0], "inside" if inside else "outside", m])
		var want := ""
		if not inside:
			want = "water" if (m & t.SURFACE_WATER) != 0 else "rough ground"
		check(r.crash == want, "%s %s: %s (got %s)" % [b.name, c[0], "no crash" if want == "" else want + " crash", r.crash if r.crash != "" else "no crash"])
	focus.queue_free()
	t.queue_free()
	await frames(2)


## A gentle touchdown at terrain-local point `p` (metres east / north of the lineup point): 1 m above the wheels,
## sinking 1.5 m/s at SPEED, idle, gear down, starting `lead` metres before `p` (the float, measured by the first
## call, which starts at `p`: a later or harder touchdown fails the landing check, the attitude it tests is the
## 5 Hz update's and the gear needs ~3 s).
## Returns the surface mask at the touchdown and the crash reason ("" = none in 0.5 s on the ground).
func _touch_down(t: Node3D, focus: Node3D, flight, p: Vector2, hdg: float) -> Dictionary:
	focus.position = Vector3(p.x, 100.0, -p.y)
	var t0 := Time.get_ticks_msec()
	while (not t.ground_ready() or t.height_at(focus.position) == null) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	var s := p - dir * maxf(lead, 0.0)
	var start := Vector3(s.x, 0.0, -s.y)
	var g = t.height_at(start)
	start.y = (g if g != null else 0.0) + clearance + 1.0
	flight.start(install, "F-16", start, hdg, 0.0, 0.0, Vector3(dir.x, 0, -dir.y) * SPEED + Vector3(0, -1.5, 0), true, true, false)
	flight.set_gear_clearance(clearance)
	flight.set_easy_landing(true)
	flight.set_controls(0.0, 0.0, 0.0, 0.0, 0.0, true, false)
	var touch := -1
	var td_mask := 0
	for i in 600:
		var pos: Vector3 = flight.state().position
		var gh = t.height_at(pos)
		flight.set_ground_height(gh if gh != null else -1.0e9)
		var surface: int = t.surface_at(pos)
		flight.set_ground_surface(_normal_z(t, pos), (surface & t.SURFACE_WATER) != 0, (surface & t.SURFACE_ROUGH) != 0)
		flight.step(DT)
		var st: Dictionary = flight.state()
		if st.on_ground and touch < 0:
			touch = i
			td_mask = t.surface_at(st.position)
			if lead < 0.0:
				var d: Vector3 = st.position - start
				lead = Vector2(d.x, -d.z).dot(dir)
				print("float from the start to the touchdown: %.0f m" % lead)
		if st.crashed:
			return {"mask": td_mask if touch >= 0 else t.surface_at(st.position), "crash": String(st.crash_reason)}
		if touch >= 0 and i - touch >= 30:
			break
	return {"mask": td_mask, "crash": "" if touch >= 0 else "no touchdown"}


## The vertical share of the ground normal from heights 3 m either side (terrain_view.gd _ground_normal_z).
func _normal_z(t: Node3D, p: Vector3) -> float:
	const D := 3.0
	var hx0 = t.height_at(p - Vector3(D, 0, 0))
	var hx1 = t.height_at(p + Vector3(D, 0, 0))
	var hz0 = t.height_at(p - Vector3(0, 0, D))
	var hz1 = t.height_at(p + Vector3(0, 0, D))
	if hx0 == null or hx1 == null or hz0 == null or hz1 == null:
		return 1.0
	return Vector3(-(hx1 - hx0) / (2.0 * D), 1.0, -(hz1 - hz0) / (2.0 * D)).normalized().y


## The ten airbase sections of iaf.ibx (INI text): name, LineupLocX / Y, RunwayNumber.
func _bases() -> Array:
	var out := []
	var sec := ""
	for line in FileAccess.get_file_as_string(install.path_join("iaf.ibx")).split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			sec = line.trim_prefix("[").trim_suffix("]")
			if sec in BASES:
				out.append({"name": sec})
		elif "=" in line and sec in BASES and not line.begins_with(";"):
			var kv := line.split("=")
			out[-1][kv[0].strip_edges()] = kv[1].strip_edges().to_float()
	return out
