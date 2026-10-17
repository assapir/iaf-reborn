# Airbases (Preferences → Graphics → MORE → Airbases; docs/rendering.md §7): Original draws nothing; Detailed gives the
# terrain shader the nearest base's runways (ends, width, designation numbers from the heading), taxi lines and paved
# mask, for every runway of the mission's base. The night runway lights (lt_dvd_h, placed by 214) line up with the
# derived runway edges.
extends "res://../tests/godot/base.gd"

var Airbases: GDScript


func run() -> void:
	Airbases = load("res://terrain/airbases.gd")
	var bases: Array = Airbases.bases()
	check(bases.size() == 10, "airbases.json: the ten iaf.ibx bases (%d)" % bases.size())
	for b in bases:
		var ok: bool = not b.runways.is_empty() and FileAccess.file_exists(Settings().assets_dir().path_join("converted/terrain").path_join(b.mask.file))
		for r in b.runways:
			var e0 := Vector2(r.ends[0][0], r.ends[0][1])
			var e1 := Vector2(r.ends[1][0], r.ends[1][1])
			var hdg := fposmod(rad_to_deg(atan2(e1.x - e0.x, e1.y - e0.y)), 360.0)
			# The number at each end: the landing heading over ten (01–36).
			var n0 := int(round(hdg / 10.0)) % 36
			ok = ok and int(r.numbers[0]) == (36 if n0 == 0 else n0) and absi(int(r.numbers[0]) - int(r.numbers[1])) == 18 \
				and e0.distance_to(e1) >= 1800.0 and float(r.width) >= 35.0 and float(r.width) <= 120.0
		check(ok, "%s: %d runways with numbers, lengths and widths; its mask" % [b.name, b.runways.size()])

	# Original: nothing reaches the shader.
	Settings().airbases = "original"
	var tv = await start_mission(311)
	await frames(5)
	check(not Airbases._on and Airbases._current == -1, "original: no airbase surface")

	# Detailed at Ramat David (311 starts on its runway): the base's three runways and its taxi lines.
	Settings().airbases = "detailed"
	tv = await start_mission(311)
	await frames(5)
	check(Airbases._on and Airbases._current >= 0 and bases[Airbases._current].name == "David", "detailed: Ramat David is drawn")
	var david: Dictionary = bases[Airbases._current]
	check(david.runways.size() == 3, "Ramat David: three runways (%d)" % david.runways.size())
	var hdgs := []
	for r in david.runways:
		hdgs.append(int(round(fposmod(rad_to_deg(atan2(r.ends[1][0] - r.ends[0][0], r.ends[1][1] - r.ends[0][1])), 180.0))))
	hdgs.sort()
	check(hdgs == [30, 90, 150], "Ramat David's runways run at 030, 090, 150 (%s)" % [hdgs])
	check(not david.taxi.is_empty(), "Ramat David: taxi lines")
	# The player starts on the base's paved surface (its mask).
	var p: Vector3 = tv.rig.position
	var here := Vector2(tv.terrain.world_origin.x + p.x, tv.terrain.world_origin.y - p.z)
	var mask := Image.load_from_file(Settings().assets_dir().path_join("converted/terrain").path_join(david.mask.file))
	var px := Vector2i(int((here.x - float(david.mask.origin[0])) / float(david.mask.px_m)), int((float(david.mask.origin[1]) - here.y) / float(david.mask.px_m)))
	check(mask.get_pixelv(px).r > 0.5 or david.runways.any(func(r): return _inside(r, here, 0.0)), "the start spot lies on the paved surface %s" % here)

	# Night: 214 places lt_dvd_h on Ramat David; its edge lights stand at the derived runways' edges.
	Settings().night_lights = "detailed"
	tv = await start_mission(214)
	await frames(5)
	var lights = tv.runtime.entities.values().filter(func(e): return e.get("light_set", false) and e.node != null \
		and Vector2(e.world.x, e.world.y).distance_to(Airbases.centre(david)) < 5000.0)
	check(lights.size() == 1, "214: one light set on Ramat David (%d)" % lights.size())
	if lights.size() == 1:
		var devs := []
		var o: Vector2 = tv.terrain.world_origin
		for mi in lights[0].node.find_children("*", "MeshInstance3D", true, false):
			var arr: Array = mi.mesh.surface_get_arrays(0)
			for v in arr[Mesh.ARRAY_VERTEX]:
				var g: Vector3 = mi.global_transform * v
				var e := Vector2(o.x + g.x, o.y - g.z)
				for r in david.runways:
					var a := _axes(r, e)
					# Edge lights: beside the runway's middle part, within 20 m of its edge.
					if absf(a.x) < _half_len(r) - 100.0 and absf(absf(a.y) - float(r.width) / 2.0) < 20.0:
						devs.append(absf(a.y) - float(r.width) / 2.0)
		devs.sort()
		var med: float = devs[devs.size() / 2] if not devs.is_empty() else INF
		check(devs.size() > 50 and absf(med) < 4.0, "lt_dvd_h's edge lights at the runway edges: %d lights, median %+.1f m" % [devs.size(), med])
		print("INFO edge-light offsets: quartiles %+.1f / %+.1f / %+.1f m" % [devs[devs.size() / 4], med, devs[devs.size() * 3 / 4]])
	Settings().night_lights = "original"
	Settings().airbases = "original"


## (along from the middle, across) of engine point p in runway r's frame.
func _axes(r: Dictionary, p: Vector2) -> Vector2:
	var e0 := Vector2(r.ends[0][0], r.ends[0][1])
	var e1 := Vector2(r.ends[1][0], r.ends[1][1])
	var d := (e1 - e0).normalized()
	var q := p - (e0 + e1) * 0.5
	return Vector2(q.dot(d), q.dot(Vector2(d.y, -d.x)))


func _half_len(r: Dictionary) -> float:
	return Vector2(r.ends[0][0], r.ends[0][1]).distance_to(Vector2(r.ends[1][0], r.ends[1][1])) / 2.0


func _inside(r: Dictionary, p: Vector2, pad: float) -> bool:
	var a := _axes(r, p)
	return absf(a.x) < _half_len(r) + pad and absf(a.y) < float(r.width) / 2.0 + pad
