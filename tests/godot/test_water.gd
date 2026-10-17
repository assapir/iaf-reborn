# Extras "Water" (docs/rendering.md §1.3): off (the default) keeps the original terrain material and builds no surface
# raster; on sets the water in the terrain shader and rasterises terraintype.dat around the camera (IafSurface, Rust)
# even with the close up off, matching terrain.gd surface_at(); the switch is saved and loaded.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var RO: GDScript = load("res://terrain/render_options.gd")
	var shader: Shader = load("res://terrain/terrain.gdshader")
	check(not Settings().water and Settings().default_value("water") == false, "water defaults to the original")
	var tv = await start_mission(311)
	await frames(10)
	var drawn: Array = tv.terrain.find_children("*", "MeshInstance3D", false, false)
	var terrain_shader := func() -> bool:
		return not drawn.is_empty() and drawn.all(func(m): return m.material_override is ShaderMaterial and m.material_override.shader == shader)
	check(RO.terrain_water == 0.0 and not Settings().terrain_closeup and RO._surf_tex == null and terrain_shader.call(),
			"off: the original terrain material, water 0, no surface raster")

	Settings().water = true
	tv.apply_render_options()
	await frames(3)
	check(RO.terrain_water == 1.0 and terrain_shader.call() and shader.code.contains("global uniform float terrain_water"),
			"on: the terrain shader's water on")
	check(RO._surf_tex != null and RO._surf_img.get_width() == RO.SURF_N, "on: the surface raster built with the close up off")
	# The Rust raster against the GDScript lookup at every 9th texel centre.
	var bad := 0
	var n := 0
	var wet := 0
	for j in range(0, RO.SURF_N, 9):
		for i in range(0, RO.SURF_N, 9):
			var c: Vector2 = RO._surf_origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * RO.SURF_CELL
			var f: int = tv.terrain.surface_at(Vector3(c.x, 0.0, c.y))
			var px: Color = RO._surf_img.get_pixel(i, j)
			if (px.r > 0.5) != ((f & 0x6) != 0 and (f & 0x8) == 0) or (px.g > 0.5) != ((f & 0x10) != 0):
				bad += 1
			n += 1
			wet += int(px.r > 0.5)
	check(bad == 0 and wet > 0, "surface raster = surface_at at %d texels, %d of them water (%d differ)" % [n, wet, bad])
	# And across the coast at Tel Aviv (engine metres 309000..315144 east, 543568 north): 64 × 64 texels of 96 m.
	var o: Vector2 = tv.terrain.world_origin
	var t0 := Time.get_ticks_usec()
	IafSurface.raster_rg8(309000.0, 546640.0, RO.SURF_CELL, RO.SURF_N)
	print("surface raster %d² in %.2f ms" % [RO.SURF_N, (Time.get_ticks_usec() - t0) / 1000.0])
	var rg: PackedByteArray = IafSurface.raster_rg8(309000.0, 546640.0, 96.0, 64)
	bad = 0
	wet = 0
	for k in 64 * 64:
		var e := Vector2(309000.0 + (k % 64 + 0.5) * 96.0, 546640.0 - (k / 64 + 0.5) * 96.0)
		var f: int = tv.terrain.surface_at(Vector3(e.x - o.x, 0.0, -(e.y - o.y)))
		if (rg[2 * k] > 0) != ((f & 0x6) != 0 and (f & 0x8) == 0):
			bad += 1
		wet += int(rg[2 * k] > 0)
	check(bad == 0 and wet > 500 and wet < 64 * 64 - 500, "Tel Aviv coast raster = surface_at (%d of 4096 water, %d differ)" % [wet, bad])
	var cfg: ConfigFile = Settings().write_config()
	Settings().water = false
	Settings().read_config(cfg)
	check(Settings().water, "water saved and loaded")

	Settings().water = false
	tv.apply_render_options()
	check(RO.terrain_water == 0.0 and RO._surf_tex == null and terrain_shader.call(), "off again: water 0, raster dropped")
