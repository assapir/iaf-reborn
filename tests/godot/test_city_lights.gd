# City lights (docs/rendering.md §5.1): with Night lights = Detailed, at night over Tel Aviv the towns get their
# lights from the installed scenery's buildings (city_lights.gd, IafCityLights): far points for every block in range,
# near points for the near blocks, lights in the kept Tel Aviv inset too, every light a little above the ground, the
# colours and ranks in range, the haze on. By day they hide and the haze is off; with Night lights = Original there
# are none. Needs setup's scenery (skips without it).
extends "res://../tests/godot/base.gd"

## Tel Aviv (engine metres).
const TEL_AVIV := Vector3(318500.0, 540500.0, 0.0)
## Inside the kept Tel Aviv inset (no Survey photo, no scenery cell there).
const INSET := Vector3(315000.0, 541700.0, 0.0)


func run() -> void:
	await require_data()
	var CityLights: GDScript = load("res://terrain/city_lights.gd")
	if not CityLights.available():
		print("SKIP: no scenery (tools/setup-cli.sh --scenery): the city lights need its buildings")
		return
	settings().night_lights = "detailed"
	var tv: Node = await _over_tel_aviv(22.0)
	var cl: Node3D = tv.get_node_or_null("CityLights")
	check(cl != null and cl.visible, "detailed, night: the city lights")
	if cl == null:
		return
	var t := Time.get_ticks_msec()
	while (
		Time.get_ticks_msec() - t < 30000
		and (_meshes(cl, "near").is_empty() or cl._blocks.values().any(func(b): return b.asking))
	):
		await frames(10)
	var far := _meshes(cl, "far")
	var near := _meshes(cl, "near")
	check(far.size() >= 4 and near.size() >= 1, "blocks drawn: %d far, %d near" % [far.size(), near.size()])
	var n := 0
	var ok_rank := true
	var ok_col := true
	var ok_h := true
	for which in [["far", far], ["near", near]]:
		for mi: MeshInstance3D in which[1]:
			var a: Array = mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
			n += v.size()
			for k in range(0, v.size(), 997):
				var is_far: bool = c[k].a < CityLights.FAR_SHARE
				ok_rank = ok_rank and is_far == (which[0] == "far")
				ok_col = ok_col and maxf(c[k].r, maxf(c[k].g, c[k].b)) <= 1.0 and c[k].r > 0.0
				var p: Vector3 = mi.position + v[k]
				var g = tv.terrain.height_at(Vector3(p.x, 0.0, p.z))
				if g != null:
					ok_h = ok_h and p.y - float(g) > 0.5 and p.y - float(g) < 400.0
	check(n > 100000, "%d lights in the drawn blocks" % n)
	# Tel Aviv's coast is a kept target inset: no scenery there, its lights from setup's light cells (lights/L1).
	var inset: Vector3 = tv.world_to_scene(INSET)
	var lit_inset := 0
	for mi: MeshInstance3D in far + near:
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			lit_inset += int(Vector2(mi.position.x + v.x - inset.x, mi.position.z + v.z - inset.z).length() < 500.0)
	check(lit_inset > 50, "lights in the Tel Aviv inset: %d within 500 m" % lit_inset)
	check(ok_rank, "far points rank below %.2f, near ones above" % CityLights.FAR_SHARE)
	check(ok_col, "colours in 0..1")
	check(ok_h, "every sampled light stands a little above the ground")
	while Time.get_ticks_msec() - t < 40000 and cl._glow == null:
		await frames(10)
	check(cl._glow != null and cl.glow_k > 0.0, "the haze over the towns")
	var mat: ShaderMaterial = far[0].material_override
	check(float(mat.get_shader_parameter("vp_h")) > 0.0, "the shader has the render's rows")

	# By day they hide.
	tv.runtime.misc["0x460"] = 11.0 * 3600.0 - tv.runtime.now
	tv._tod_t = -INF
	await frames(5)
	check(not cl.visible and cl.glow_k == 0.0, "detailed, day: no city lights, no glow")

	# Night lights Original: none.
	settings().night_lights = "original"
	tv = await _over_tel_aviv(22.0)
	await frames(30)
	check(tv.get_node_or_null("CityLights") == null, "original, night: no city lights")


## Mission 231 frozen 3000 m over Tel Aviv at `hour`.
func _over_tel_aviv(hour: float) -> Node:
	var tv: Node = await start_mission(231)
	tv.frozen = true
	tv.fm_stopped = true
	tv.runtime.misc["0x460"] = hour * 3600.0 - tv.runtime.now
	tv._tod_t = -INF
	tv.rig.position = tv.world_to_scene(TEL_AVIV)
	var g = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = (float(g) if g != null else 0.0) + 3000.0
	await frames(10)
	return tv


static func _meshes(cl: Node3D, which: String) -> Array:
	var out := []
	for b: Dictionary in cl._blocks.values():
		if b[which] != null and b[which].mesh != null:
			out.append(b[which])
	return out
