# Roads (Preferences → Graphics → MORE → Roads; docs/rendering.md §1.8): Original asks no mask and leaves the shader
# off; Detailed makes the road mask around the camera: road texels on the roads drawn on the ground (in the mask's own
# frame, as the shader reads it), none on the runway the flight starts on (Ramat David) and none on the sea (Tel
# Aviv); railways as ballast strips, and the marking mask's lanes and rails on the Ayalon's motorway and railway. With
# Night lights Detailed the city lights' blocks get lamps along the lit roads, Amman's road-only block too, and
# switching Roads or Night lights during a night flight adds or removes them at once. Needs setup's road layer (skips
# without it).
extends "res://../tests/godot/base.gd"

## Tel Aviv (engine metres): its coast in the 1998 map (the sea west of x ≈ 311.2 km), and the city.
const COAST := Vector3(312000.0, 540500.0, 0.0)
const TEL_AVIV := Vector3(317000.0, 540500.0, 0.0)
## The Ayalon: the motorway and the railway side by side; Amman, Jordan (no city lights' buildings there).
const AYALON := Vector3(312500.0, 537000.0, 0.0)
const AMMAN := Vector3(430218.0, 517154.0, 0.0)

var roads: GDScript


func run() -> void:
	await require_data()
	roads = load("res://terrain/ground_roads.gd")
	if not roads.available():
		print("SKIP: no road layer (tools/setup-cli.sh): Roads = Detailed needs it")
		return
	# Original: nothing asked, the shader's switch off.
	settings().ground_roads = "original"
	var tv: Node = await start_mission(311)
	await frames(10)
	check(not roads._on and not roads._pending and roads._tex == null, "original: no road mask asked or held")

	# Detailed at Ramat David (311 starts on its runway).
	settings().ground_roads = "detailed"
	tv = await start_mission(311)
	var img := await _mask(tv.terrain.world_origin + Vector2(tv.rig.position.x, -tv.rig.position.z))
	check(img != null, "detailed: the road mask is made")
	if img == null:
		return
	var here: Vector2 = tv.terrain.world_origin + Vector2(tv.rig.position.x, -tv.rig.position.z)
	check(_sd(img, here) > 3.0, "no road on the runway under the jet (%.1f m from a road)" % _sd(img, here))
	var n_road := 0
	for j in range(0, img.get_height(), 4):
		for i in range(0, img.get_width(), 4):
			n_road += int(img.get_pixel(i, j).r * 255.0 < 128.0)
	check(n_road > 200, "road texels around the base: %d (every 4th texel)" % n_road)
	# Each drawn way's segment middles lie on road texels.
	var ways: Array = IafRoads.roads_in_rect(here - Vector2(1500, 1500), here + Vector2(1500, 1500), 7)
	var on := 0
	var off := 0
	for w: Dictionary in ways:
		if w.tunnel or w.off_ground:
			continue
		var p: PackedVector2Array = w.points
		for k in p.size() - 1:
			var m := (p[k] + p[k + 1]) * 0.5
			if m.distance_to(here) < 1500.0:
				if _sd(img, m) < 0.0:
					on += 1
				else:
					off += 1
	check(on > 0 and off == 0, "segment middles on road texels: %d on, %d off" % [on, off])

	# Tel Aviv's coast: no road texel over the sea (terraintype.dat's water, as the road layer's cut and the shader's).
	settings().night_lights = "detailed"
	tv = await start_mission(231)
	tv.frozen = true
	tv.fm_stopped = true
	tv.rig.position = tv.world_to_scene(COAST)
	tv.rig.position.y = 300.0
	roads._tex = null  # a new texture: the headless renderer reads back an ImageTexture's first image only
	img = await _mask(Vector2(COAST.x, COAST.y))
	check(img != null, "Tel Aviv: the road mask is made")
	if img == null:
		return
	var sea := 0
	var sea_road := 0
	var land_road := 0
	var nw: Vector2 = roads._nw
	var water: PackedByteArray = IafSurface.raster_rg8(nw.x, nw.y, 16.0, 256)
	for j in range(0, img.get_height(), 8):
		for i in range(0, img.get_width(), 8):
			var road := img.get_pixel(i, j).r * 255.0 < 128.0
			if water[2 * (i / 8 + j / 8 * 256)] > 128:
				sea += 1
				sea_road += int(road)
			else:
				land_road += int(road)
	check(sea > 1000 and sea_road == 0, "no road over the sea: %d of %d sea texels" % [sea_road, sea])
	check(land_road > 1000, "Tel Aviv's roads: %d road texels (every 8th)" % land_road)

	# Lamps along the lit roads: a Tel Aviv block made with and without them.
	IafCityLights.open(load("res://terrain/scenery.gd").dir())
	var b := Vector2i(-1, -1)
	var near: PackedInt32Array = IafCityLights.blocks_near(TEL_AVIV.x, TEL_AVIV.y, 0.0)
	if near.size() >= 3:
		b = Vector2i(near[0], near[1])
	var counts := []
	for lamps in [false, true]:
		IafCityLights.set_road_lamps(lamps)
		var r := {"retry": true}
		var t := Time.get_ticks_msec()
		while not r.has("near") and Time.get_ticks_msec() - t < 30000:
			if r.has("retry"):
				IafCityLights.request(b.x, b.y, true)
			await frames(10)
			r = IafCityLights.take(b.x, b.y)
		counts.append(0 if not r.has("near") else r.far[0].size() + r.near[0].size())
	check(counts[0] > 0 and counts[1] > counts[0], "road lamps added to the block: %d → %d lights" % counts)

	# The Ayalon: the railway's ballast in the road mask; the marking mask's rails on it and lanes on the motorway.
	tv.rig.position = tv.world_to_scene(AYALON)
	tv.rig.position.y = 300.0
	roads._tex = null
	roads._marks = null
	img = await _mask(Vector2(AYALON.x, AYALON.y))
	check(img != null and roads._marks != null, "Ayalon: the road and marking masks are made")
	if img == null or roads._marks == null:
		return
	var marks: Image = roads._marks.get_image()
	var here2 := Vector2(AYALON.x, AYALON.y)
	var tally := {0: [0, 0, 0], 8: [0, 0, 0]}  # class -> [points, on its strip, marked]
	for w: Dictionary in IafRoads.roads_in_rect(here2 - Vector2(900, 900), here2 + Vector2(900, 900), 8):
		if w.tunnel or w.off_ground or not tally.has(int(w["class"])):
			continue
		var t: Array = tally[int(w["class"])]
		var p: PackedVector2Array = w.points
		var pts := []  # every 10 m along the way, 5 m clear of its vertices (junctions)
		for k in p.size() - 1:
			for d in range(5, int(p[k].distance_to(p[k + 1])) - 4, 10):
				pts.append(p[k].move_toward(p[k + 1], d))
		for m: Vector2 in pts:
			if m.distance_to(here2) > 900.0:
				continue
			var g := _px(img, m)
			var mk := _px(marks, m, 0.5)
			t[0] += 1
			if int(w["class"]) == 8:
				t[1] += int(g.r < 0.5 and (int(g.g * 255.0) & 64) != 0)
				t[2] += int((int(mk.b * 255.0) & 64) != 0)
			else:
				t[1] += int(g.r < 0.5 and (int(g.g * 255.0) & 128) != 0)
				t[2] += int((int(mk.b * 255.0) & 128) != 0)
	for c: int in tally:
		var t: Array = tally[c]
		var what := "railway" if c == 8 else "motorway"
		check(t[0] > 20 and t[1] >= t[0] * 0.8, "%s on its strip: %d of %d points" % [what, t[1], t[0]])
		check(t[2] >= t[0] * 0.8, "%s marked (rails / edge lines): %d of %d points" % [what, t[2], t[0]])

	# Amman: a road block where the city lights have no buildings; its lit roads get lamps with the road lamps on.
	IafCityLights.set_road_lamps(false)
	var dark: PackedInt32Array = IafCityLights.blocks_near(AMMAN.x, AMMAN.y, 0.0)
	IafCityLights.set_road_lamps(true)
	var lit: PackedInt32Array = IafCityLights.blocks_near(AMMAN.x, AMMAN.y, 0.0)
	check(
		dark.is_empty() and lit.size() >= 3,
		"Amman: a block only with the road lamps (%d / %d)" % [dark.size(), lit.size()]
	)
	if lit.size() >= 3:
		tv.rig.position = tv.world_to_scene(AMMAN)
		tv.rig.position.y = 1500.0
		var r2 := {"retry": true}
		var t2 := Time.get_ticks_msec()
		while not r2.has("near") and Time.get_ticks_msec() - t2 < 40000:
			if r2.has("retry"):
				IafCityLights.request(lit[0], lit[1], true)
			await frames(10)
			r2 = IafCityLights.take(lit[0], lit[1])
		var n2: int = 0 if not r2.has("near") else r2.far[0].size() + r2.near[0].size()
		check(n2 > 500, "Amman's road lamps: %d" % n2)

	# A night flight over Tel Aviv: switching Roads adds or removes the lamps at once; Night lights Original hides them.
	tv = await start_mission(231)
	tv.frozen = true
	tv.fm_stopped = true
	tv.runtime.misc["0x460"] = 22.0 * 3600.0 - tv.runtime.now
	tv._tod_t = -INF
	tv.rig.position = tv.world_to_scene(TEL_AVIV)
	tv.rig.position.y = 3000.0
	await frames(10)
	var cl: Node3D = tv.get_node_or_null("CityLights")
	check(cl != null and cl._road_lamps, "night: the city lights, made with the road lamps")
	if cl != null:
		var with_lamps := await _settled(cl)
		settings().ground_roads = "original"
		tv.apply_render_options()  # as the in-flight Preferences do
		var without := await _settled(cl)
		settings().ground_roads = "detailed"
		tv.apply_render_options()
		var again := await _settled(cl)
		check(
			without < with_lamps and again > without,
			"Roads switched in flight: %d → %d → %d lights" % [with_lamps, without, again]
		)
		settings().night_lights = "original"
		tv._tod_t = -INF
		await frames(5)
		check(not cl.visible, "Night lights switched to Original in flight: the city lights hidden")
		settings().night_lights = "detailed"

	# Back to Original: the switch off.
	settings().ground_roads = "original"
	roads.apply()
	check(not roads._on and roads._tex == null, "original again: the mask released")


## The made mask around engine point `at` (waits up to 20 s), else null.
func _mask(at: Vector2) -> Image:
	var t := Time.get_ticks_msec()
	while (
		(roads._tex == null or (roads._nw + Vector2(1, -1) * roads._side * 0.5).distance_to(at) > roads.MOVE)
		and Time.get_ticks_msec() - t < 20000
	):
		await frames(5)
	await frames(2)  # its marking mask, a frame later
	return roads._tex.get_image() if roads._tex != null else null


## The city lights' points once no block is asked or to be made again (waits up to 60 s).
func _settled(cl: Node3D) -> int:
	await frames(5)
	var t := Time.get_ticks_msec()
	while (
		Time.get_ticks_msec() - t < 60000
		and (cl._blocks.is_empty() or cl._blocks.values().any(func(b): return b.asking or b.stale))
	):
		await frames(10)
	var n := 0
	for b: Dictionary in cl._blocks.values():
		for m in [b.far, b.near]:
			if m != null and m.mesh != null:
				n += m.mesh.surface_get_array_len(0)
	return n


## The texel of a mask image (the road mask, or the marking mask at `scale` of its side) at engine point p.
func _px(img: Image, p: Vector2, scale := 1.0) -> Color:
	var side: float = roads._side * scale
	var nw: Vector2 = roads._nw + Vector2(1, -1) * (roads._side - side) * 0.5
	var ij := Vector2i(int((p.x - nw.x) / side * img.get_width()), int((nw.y - p.y) / side * img.get_height()))
	if ij.x < 0 or ij.y < 0 or ij.x >= img.get_width() or ij.y >= img.get_height():
		return Color(1, 0, 0, 0)
	return img.get_pixel(ij.x, ij.y)


## The mask's signed distance (m) at engine point p (positive off the roads).
func _sd(img: Image, p: Vector2) -> float:
	var nw: Vector2 = roads._nw
	var side: float = roads._side
	var ij := Vector2i(int((p.x - nw.x) / side * img.get_width()), int((nw.y - p.y) / side * img.get_height()))
	if ij.x < 0 or ij.y < 0 or ij.x >= img.get_width() or ij.y >= img.get_height():
		return INF
	return (img.get_pixel(ij.x, ij.y).r * 255.0 - 128.0) / 16.0
