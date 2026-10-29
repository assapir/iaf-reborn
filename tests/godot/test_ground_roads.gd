# Roads (Preferences → Graphics → MORE → Roads; docs/rendering.md §1.8): Original asks no mask and leaves the shader
# off; Detailed makes the road mask around the camera: road texels on the roads drawn on the ground (in the mask's own
# frame, as the shader reads it), none on the runway the flight starts on (Ramat David) and none on the sea (Tel
# Aviv). With Night lights Detailed the city lights' blocks get lamps along the lit roads. Needs setup's road layer
# (skips without it).
extends "res://../tests/godot/base.gd"

## Tel Aviv (engine metres): its coast in the 1998 map (the sea west of x ≈ 311.2 km), and the city.
const COAST := Vector3(312000.0, 540500.0, 0.0)
const TEL_AVIV := Vector3(317000.0, 540500.0, 0.0)

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
	return roads._tex.get_image() if roads._tex != null else null


## The mask's signed distance (m) at engine point p (positive off the roads).
func _sd(img: Image, p: Vector2) -> float:
	var nw: Vector2 = roads._nw
	var side: float = roads._side
	var ij := Vector2i(int((p.x - nw.x) / side * img.get_width()), int((nw.y - p.y) / side * img.get_height()))
	if ij.x < 0 or ij.y < 0 or ij.x >= img.get_width() or ij.y >= img.get_height():
		return INF
	return (img.get_pixel(ij.x, ij.y).r * 255.0 - 128.0) / 16.0
