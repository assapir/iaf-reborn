# World scale Real: every airbase at its real place (docs/world-scale.md §3.3, steps 6–8). Mission 311 (a ground
# start at Ramat David) in Real: the base data moved (the radio's tower, the flight model's start rule), the new
# site flat and on runway ground, the old site rough ground; the mission's units moved with the base; Original
# unchanged.
extends "res://../tests/godot/base.gd"

const DAVID_LINEUP := Vector2(356483, 602383)


func _scene(tv: Node, w: Vector2) -> Vector3:
	return Vector3(w.x - tv.terrain.world_origin.x, 0.0, -(w.y - tv.terrain.world_origin.y))


func run() -> void:
	var prefs := settings()
	prefs.world_scale = "original"
	var tv: Node = await start_mission(311)
	check(not IafBases.active(), "Original: no base moves")
	check(tv.terrain._inset.is_empty(), "Original: no warped insets")
	check(tv.terrain.surface_at(_scene(tv, DAVID_LINEUP)) & 0x10 != 0, "Original: the lineup is on runway ground")

	prefs.world_scale = "real"
	tv = await start_mission(311)
	check(IafBases.active(), "Real: the bases move")
	var m: PackedFloat64Array = prefs.base_moved(DAVID_LINEUP.x, DAVID_LINEUP.y)
	check(m.size() == 5, "Ramat David's lineup moves")
	var new := Vector2(m[0], m[1])
	print(
		(
			"David lineup -> %s (%.0f m), turn %.1f°, k %.2f, dz %.1f"
			% [new, new.distance_to(DAVID_LINEUP), m[2], m[3], m[4]]
		)
	)
	check(new.distance_to(DAVID_LINEUP) > 5000.0, "it moved %.1f km" % (new.distance_to(DAVID_LINEUP) / 1000.0))
	check(tv.terrain.surface_at(_scene(tv, new)) & 0x10 != 0, "the moved lineup is on runway ground")
	check(tv.terrain.surface_at(_scene(tv, DAVID_LINEUP)) & 0x10 == 0, "the old lineup is rough ground")
	# The new site's fine ground: the old site's level-0 art warped there (terrain.gd _add_insets), unless a layer has
	# its own node there.
	var t: Vector2 = tv.terrain.godot_to_terrain(_scene(tv, new)) / tv.terrain._span(0)
	var n0 := Vector3i(floori(t.x), floori(t.y), 0)
	check(
		tv.terrain._inset.has(n0) or tv.terrain._layer_dir.has(n0),
		"the moved lineup's level-0 node has fine ground (%d inset nodes)" % tv.terrain._inset.size()
	)
	# The radio's tower and lineup follow (radio.gd).
	var rb: Dictionary = {}
	for b in tv.radio.bases:
		if b.name == "David":
			rb = b
	check(not rb.is_empty() and Vector2(rb.lineup.x, rb.lineup.y).distance_to(new) < 1.0, "the radio's lineup moved")
	check(
		rb.get("hdg", 0) == wrapi(roundi(270 + m[2]), 0, 360), "the radio's runway heading turned (%s)" % rb.get("hdg")
	)
	# The tower's runway: the real designator (Ramat David's 09/27: 27 at 267° true) × 10.
	check(rb.get("rwy", 0) == 270, "the radio's runway is the real designator (%s)" % rb.get("rwy"))
	# The taxi signs (terrain_view.gd _real_sign): David's 27 / 09 agree with the real 09/27; Ramon's 23 is the
	# real 25L (the main runway 07R/25L): re-lettered.
	var TV = load("res://terrain/terrain_view.gd")
	var ramon: Vector3 = tv.radio.bases.filter(func(b): return b.name == "Ramon")[0].lineup
	check(
		(
			TV._real_sign_label("stationary/rw_ul_1/signdvid.gltf", {"world": Vector3(new.x, new.y, 0)}) == ""
			and TV._real_sign_label("stationary/rw_ul_1/sign09l.gltf", {"world": Vector3(new.x, new.y, 0)}) == ""
		),
		"signs: David's 27 / 09 kept"
	)
	check(
		(
			IafBases.sign_designation(ramon.x, ramon.y, 23) == "25L"
			and TV._real_sign_label("stationary/rw_ul_1/signrmon.gltf", {"world": ramon}) == "25L"
			and TV._real_sign_label("stationary/rw_ul_1/sign23l.gltf", {"world": ramon}) == "25L"
		),
		"signs: Ramon's 23 reads the real 25L (%s)" % IafBases.sign_designation(ramon.x, ramon.y, 23)
	)
	# The new site is flat at its elevation (the height images patched as they load).
	var heights := []
	for d in [Vector2.ZERO, Vector2(400, 0), Vector2(-300, 250), Vector2(800, -400)]:
		var g = tv.terrain.height_at(_scene(tv, new + d))
		heights.append(g)
	var flat: bool = heights.all(func(h): return h != null and absf(h - heights[0]) < 0.01)
	check(flat, "the site is flat (%s)" % [heights])
	check(
		heights[0] != null and absf(heights[0] - (63.0 + m[4])) < 0.5,
		"at the lineup's moved height (%s, %.1f)" % [heights[0], 63.0 + m[4]]
	)
	check(
		IafFlight.start_rule(prefs.assets_dir().path_join("install"), new.x, new.y, 63.0 + m[4]) == Vector2i(1, 1),
		"the start rule: at the moved base, engine on at the moved lineup"
	)

	# --- step 7: the mission data moves with the base ---
	var MR = load("res://mission/mission_runtime.gd")
	var o_start: Vector3 = _start_of(prefs, MR, 311, "original")
	var r_start: Vector3 = _start_of(prefs, MR, 311, "real")
	var ms: PackedFloat64Array = prefs.base_moved(o_start.x, o_start.y)
	check(
		(
			Vector2(r_start.x, r_start.y).distance_to(Vector2(ms[0], ms[1])) < 0.01
			and absf(r_start.z - (o_start.z + ms[4])) < 0.01
		),
		"311: the player starts on the moved base (%s)" % r_start
	)
	check(tv.terrain.world_origin.distance_to(Vector2(r_start.x, r_start.y)) < 0.01, "311: the flight starts there")
	await frames(30)
	var p: Vector3 = tv.rig.global_position
	var g = tv.terrain.height_at(p)
	check(
		g != null and absf(p.y - g - 1.69) < 0.1,
		"311: on its wheels on the moved site (%.2f m)" % [p.y - g if g != null else -1.0]
	)
	check(
		not tv.flight.state().get("crashed", false) and tv.terrain.surface_at(p) & 0x10 != 0,
		"311: on runway ground, not crashed"
	)
	check(
		tv.start_engine_on == (Vector2(o_start.x, o_start.y).distance_to(DAVID_LINEUP) <= 100.0),
		"311: the engine rule as in Original"
	)
	# The base's units: distances × k, headings + the turn (zone A); the parked jets of 122; 237's SA-3 site at Ryak.
	for id in [311, 122]:
		var o := _units(prefs, MR, id, "original")
		var r := _units(prefs, MR, id, "real")
		var bad := 0
		var n := 0
		var keys := o.keys()
		for i in keys.size():
			var a: Array = o[keys[i]]
			var b: Array = r[keys[i]]
			if float(b[2]) == 1.0 or Vector2(b[0].x, b[0].y).distance_to(new) > 6000.0:
				continue  # not on Ramat David (its zone A)
			n += 1
			if absf(fposmod(b[1] - a[1] - m[2] + 180.0, 360.0) - 180.0) > 0.01:
				print("  heading: %s %s -> %s" % [keys[i], a, b])
				bad += 1
			for j in range(i + 1, keys.size()):
				var c: Array = o[keys[j]]
				var d: Array = r[keys[j]]
				if (
					float(d[2]) != 1.0
					and Vector2(d[0].x, d[0].y).distance_to(new) < 6000.0
					and (
						absf(
							(
								Vector2(b[0].x, b[0].y).distance_to(Vector2(d[0].x, d[0].y))
								- m[3] * Vector2(a[0].x, a[0].y).distance_to(Vector2(c[0].x, c[0].y))
							)
						)
						> 0.5
					)
				):  # float32 positions
					print("  distance: %s %s" % [keys[i], keys[j]])
					bad += 1
		check(
			n >= 2 and bad == 0,
			"%d: %d units on the moved base, relative distances × k and headings turned (%d wrong)" % [id, n, bad]
		)
	var o237 := _units(prefs, MR, 237, "original")
	var r237 := _units(prefs, MR, 237, "real")
	var rk := ""
	for k in o237:
		if String(k).begins_with("RADARsa3"):
			rk = k
	var ok: bool = rk != "" and o237[rk][0] != r237[rk][0]
	for k in o237:
		if String(k).begins_with("sa3l") and ok:
			var d0 := Vector2(o237[k][0].x, o237[k][0].y).distance_to(Vector2(o237[rk][0].x, o237[rk][0].y))
			var d1 := Vector2(r237[k][0].x, r237[k][0].y).distance_to(Vector2(r237[rk][0].x, r237[rk][0].y))
			ok = ok and absf(d1 / d0 - 1.0) < 0.05
	check(ok, "237: the SA-3 site at Ryak moved with the base, its launchers kept around the radar")

	# --- step 8: the Detailed airbases surface at the new site ---
	var AB = load("res://terrain/airbases.gd")
	var david: Dictionary = {}
	for b in AB.bases():
		if b.name == "David":
			david = b
	var r0: Dictionary = david.get("runways", [{}])[0]
	var e0 := Vector2(r0.ends[0][0], r0.ends[0][1]) if r0.has("ends") else Vector2.ZERO
	var e1 := Vector2(r0.ends[1][0], r0.ends[1][1]) if r0.has("ends") else Vector2.ZERO
	check(
		david.has("mask_affine") and absf(float(r0.get("width", 0)) - 44.2) < 0.01,
		"Detailed: David's runways at the real width (%s m, OurAirports' 145 ft)" % r0.get("width")
	)
	check(
		absf(e0.distance_to(e1) - 2934.0) < 60.0 and AB.centre(david).distance_to(new) < 3000.0,
		"Detailed: the main runway at its real length on the new site (%.0f m)" % e0.distance_to(e1)
	)
	var nums: Array = r0.get("numbers", [])
	check(
		nums.size() == 2 and 9 in nums and 27 in nums,
		"Detailed: the main runway painted 09 / 27, the real designator (%s)" % [nums]
	)
	check(r0.get("letters", []) == ["", ""], "Detailed: David's 09/27 has no letter (%s)" % [r0.get("letters")])
	# A parallel pair's letter: Ramon's main runway lies on 07R/25L.
	var rr: Dictionary = AB.bases().filter(func(b): return b.name == "Ramon")[0].runways[0]
	check(
		rr.numbers == [25, 7] and rr.letters == ["L", "R"],
		"Detailed: Ramon's main runway painted 25L / 07R (%s %s)" % [rr.numbers, rr.letters]
	)
	# The flight model's runway surface: the real width (+ 5 m) on the centreline, the 1998 runway's wider part beside
	# it ground, except where a taxiway or apron joins.
	var dir := (e1 - e0).normalized()
	var side := Vector2(dir.y, -dir.x)
	var cut := 0
	var centre := 0
	for f in [0.2, 0.35, 0.5, 0.65, 0.8]:
		var c := e0.lerp(e1, f)
		centre += 1 if tv.terrain.surface_at(_scene(tv, c)) & 0x10 != 0 else 0
		for sgn in [-1.0, 1.0]:
			var q: Vector2 = c + side * sgn * (0.5 * float(r0.width) + 5.0 + 4.0)
			cut += 1 if tv.terrain.surface_at(_scene(tv, q)) & 0x10 == 0 else 0
	check(centre == 5, "the FM: runway ground on the centreline (%d / 5)" % centre)
	check(cut >= 6, "the FM: ground 9 m beyond the real edge (%d / 10, the rest taxiway joins)" % cut)
	check(AB._on, "Detailed: the surface is drawn in Real whatever the Graphics setting")
	# Mission 322 starts at Ramon: its SIGNRMON boards shown, re-lettered 25L.
	tv = await start_mission(322)
	var signs: Array = tv.runtime.entities.values().filter(func(e): return e.get("sign_label", "") != "")
	check(
		not signs.is_empty() and signs.all(func(e): return e.sign_label == "25L" and e.node.visible),
		"322: Ramon's taxi signs shown, re-lettered 25L (%d)" % signs.size()
	)
	var mi: MeshInstance3D = null if signs.is_empty() else signs[0].node.find_children("*", "MeshInstance3D")[0]
	check(
		(
			mi != null
			and mi.get_surface_override_material(0) != null
			and mi.get_surface_override_material(0).albedo_texture != mi.mesh.surface_get_material(0).albedo_texture
		),
		"322: the boards take a re-lettered copy of parts.png"
	)
	prefs.world_scale = "original"
	prefs.sync_bases()
	check(not AB.bases()[0].has("mask_affine"), "Original: the bases as measured")
	tv = await start_mission(322)
	var plain: Array = tv.runtime.entities.values().filter(func(e): return e.get("sign_label", "") != "")
	check(plain.is_empty(), "322 Original: no sign re-lettered")


## The player's start (engine X, Y, z) of a menu mission in a world scale.
func _start_of(prefs: Node, mr, id: int, scale: String) -> Vector3:
	prefs.world_scale = scale
	return mr.player_start(id)


## A mission's placed entities in a world scale: name -> [Vector3 (X, Y, z), heading, base_scale] (every file).
func _units(prefs: Node, mr, id: int, scale: String) -> Dictionary:
	prefs.world_scale = scale
	var out := {}
	var files: Array = mr.mission_files(id)
	for fi in files.size():
		for e in files[fi].data.get("entities", {}).get("items", []):
			if e is Dictionary and float(e.get("0x2e4", -1)) >= 0:
				out[String(e.get("0x2bc", "")) + "#%d:%d" % [fi, int(e["0x1e"])]] = [
					Vector3(float(e["0x2e4"]), float(e["0x2ee"]), float(e.get("0x2f8", 0))),
					float(e.get("0x302", 0)),
					float(e.get("base_scale", 1.0))
				]
	return out
