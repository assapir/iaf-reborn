# The Graphics preferences and the effect sprites (docs/front-end.md §12.4, docs/damage.md §6.1):
# VISUAL EFFECTS sets the smoke column's puff count (33 / (4 − L)); explosion sprites are centred on
# their position; OBJECT DETAIL switches the units' _h / _m / _l models by the original's pixel
# thresholds and sets point-sampled textures at level 1; SMOKE TRAILS draws the missile trails (with the
# motor glow) and the wingtip vortices, none when off.
extends "res://../tests/godot/base.gd"


func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


func run() -> void:
	var FX: GDScript = load("res://mission/damage_effects.gd")
	check(FX.effects_level(0.0) == 1 and FX.effects_level(0.5) == 2 and FX.effects_level(1.0) == 3, "effects level 1 + 2·slider")
	for v in [0.0, 0.5, 1.0]:
		Settings().visual_effects = v
		var fx = FX.new()
		root.add_child(fx)
		fx.explosion(Vector3(0, 100, 0), FX.F_COLUMN, 4.0, 95.0, 0.0)
		var want: int = [11, 16, 33][FX.effects_level(v)- 1]
		check(fx._columns.size() == 1 and fx._columns[0].n == want, "visual effects %.1f: column of %d puffs (%d)" % [v, want, fx._columns[0].n])
		fx.queue_free()
	Settings().visual_effects = 1.0
	# A fireball is centred on the explosion point (sprite flag +0x178 = 1).
	var fx = FX.new()
	root.add_child(fx)
	var at := Vector3(10, 200, -30)
	fx.explosion(at, FX.F_FIREBALL, 4.0, 95.0, 0.0)
	var xf: Transform3D = FX.puff_transform(fx._puffs[0])
	check(fx._puffs.size() == 1 and xf.origin.is_equal_approx(at) and is_equal_approx(xf.basis.get_scale().y, FX.FIREBALL_WIDTH), "fireball centred on its point, %.0f m (%s)" % [xf.basis.get_scale().y, str(xf.origin)])
	fx.queue_free()

	# SMOKE TRAILS: one point per owner frame, the glow while growing, a gap of > 3 frames restarts.
	var Trails: GDScript = load("res://mission/trails.gd")
	var tr = Trails.new()
	root.add_child(tr)
	for i in 10:
		tr.emit("m", Vector3(0, 100, -i * 5.0), Trails.MISSILE)
		await process_frame
	check(tr.counts().trails == 1 and tr.counts().points == 10 and tr.counts().glows == 1, "missile trail: 10 points, motor glow (%s)" % str(tr.counts()))
	for i in 5:
		await process_frame
	check(tr.counts().glows == 0, "no new point: the glow goes out")
	tr.emit("m", Vector3(0, 100, -60), Trails.MISSILE)
	check(tr.counts().trails == 2, "owner unseen for > 3 frames: a new trail")
	var w: PackedFloat32Array = Trails.widths(21, Trails.MISSILE)
	check(is_equal_approx(w[0], 0.6) and w[3] > w[0] and w[20] < 0.05 and w[17] > w[20], "width: 0.6 at the head, growing 15 %%, tapering to 0 (%s)" % str(w))
	await seconds(4.0)
	check(tr.counts().points == 0, "points older than 3.5 s are gone")
	tr.queue_free()

	# OBJECT DETAIL: levels and switch distances (F·extent·0.7 / px, F = 640 / tan 25°).
	var TV: GDScript = load("res://terrain/terrain_view.gd")
	var Gltf: GDScript = load("res://util/gltf.gd")
	check(Gltf.detail_level(0.0) == 1 and Gltf.detail_level(1.0) == 3, "object level 1 + 2·slider")
	var d3: Vector2 = TV.lod_distances(3, 10.0)
	check(absf(d3.x - 240.2) < 0.5 and absf(d3.y - 384.3) < 0.5, "level 3, 10 m model: _m beyond 240 m, _l beyond 384 m (%s)" % str(d3))
	var d1: Vector2 = TV.lod_distances(1, 10.0)
	check(d1.x < d3.x and d1.y < d3.y, "lower detail switches nearer (%s)" % str(d1))
	# 231's tanks have a t62_m model: drawn beyond the switch distance instead of t62_h.
	var tv = await start_mission(231)
	var tank: Dictionary = {}
	for e in tv.runtime.entities.values():
		if e.name == "t62_0":
			tank = e
	var lod: Array = tank.node.get_children().filter(func(c): return c.has_meta("lod")) if not tank.is_empty() else []
	var h_end := 0.0
	for g in tank.node.find_children("*", "GeometryInstance3D", true, false) if not tank.is_empty() else []:
		if not g.get_parent().has_meta("lod") and g.visibility_range_end > 0.0:
			h_end = g.visibility_range_end
	check(lod.size() == 1 and h_end > 0.0, "t62: one _m copy, _h drawn to %.0f m" % h_end)
	# Level 1: point-sampled textures; a destroyed unit drops its copies.
	Gltf.object_level = 1
	var m = Gltf.open(Settings().assets_dir().path_join("converted/objects/groundforces/t62/t62_h.gltf"))
	var mats: Array = m[1].get_materials().filter(func(x): return x is BaseMaterial3D)
	check(mats.size() > 0 and mats.all(func(x): return x.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST), "object detail level 1: nearest texture filter")
	Gltf.object_level = 3
	tv._drop_lods(tank.node)
	await process_frame
	check(tank.node.get_children().filter(func(c): return c.has_meta("lod")).is_empty(), "fatally hit / destroyed: LOD copies dropped")
	check(tv.trails != null and tv.flight.state().has("vortex"), "smoke trails on: the trail layer exists, the FM gives the vortex flag")
	# TEXTURED SKY: the cloud layer, a dome from the zenith at 7000 m down to height 0 at 0.73·30000 m.
	check(tv.clouds != null and tv.clouds._dome.visible and not tv.clouds._flat.visible, "textured sky: cloud dome seen from below")
	var e: Array = tv.clouds.ring_edges()
	check(e.size() == 16 and e[0] == Vector2(0, 7000) and absf(e[15].x - 21900.0) < 1.0 and absf(e[15].y) < 1.0 and e[7].y < 7000.0 and e[7].y > 0.0, "cloud rings: zenith 7000 m to 21.9 km at 0 (%s)" % str(e[7]))
	tv.clouds.update_view(Vector3(0, 6800, 0), 0.016)
	check(tv.clouds.whiteout_alpha > 0.7, "whiteout 200 m below the layer (%.2f)" % tv.clouds.whiteout_alpha)
	tv.clouds.update_view(Vector3(0, 8500, 0), 0.016)
	check(tv.clouds.whiteout_alpha == 0.0 and tv.clouds._flat.visible, "above the layer: flat clouds, no whiteout beyond 1000 m")
	Settings().smoke_trails = false
	Settings().textured_sky = false
	tv = await start_mission(231)
	check(tv.trails == null, "smoke trails off: no trails")
	check(tv.clouds == null, "textured sky off: no cloud layer")
	Settings().smoke_trails = true
	Settings().textured_sky = true
