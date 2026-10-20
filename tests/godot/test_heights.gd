# The Rust height field (IafHeights, crates/iaf-avionics/src/heights.rs) answers what terrain.gd height_at does: the
# same streamed full-detail nodes and triangle interpolation, so the weapons' and sensors' terrain lookups through
# mission_ground (world::terrain) need no call into GDScript per sample. Mission 313 at the start: random points over
# the loaded ground, GDScript vs Rust heights (float32 world_to_scene in the GDScript path: cm), and the line of sight
# from ground sites to low jets, the GDScript path (a lambda, not mission_ground) vs the field: the same answers.
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().jet_id = -1
	var tv = await start_mission(313)
	await frames(10)
	tv.frozen = true
	var p0: Vector3 = tv.runtime.player_entity().world
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	var n := 0
	var both_null := 0
	var worst := 0.0
	var mismatch := 0
	for i in 5000:
		var p := p0 + Vector3(rng.randf_range(-15000, 15000), rng.randf_range(-15000, 15000), 0)
		var g = tv.terrain.height_at(tv.world_to_scene(p))
		var r = IafHeights.height(p)
		if g == null or r == null:
			if g != null or r != null:
				mismatch += 1
			both_null += 1
			continue
		n += 1
		worst = maxf(worst, absf(float(g) - float(r)))
	check(
		n > 3000 and mismatch == 0,
		"heights: %d points compared, %d unloaded on both sides, %d loaded on one side only" % [n, both_null, mismatch]
	)
	check(
		worst < 0.05,
		"heights: Rust = GDScript within %.4f m (the GDScript path rounds the world point to float32)" % worst
	)
	# Line of sight: ground sites (+1.5 m) to jets 30..300 m over the ground, 2..15 km away.
	var old := func(q: Vector3) -> Variant: return tv.mission_ground(q)
	var pairs := 0
	var differ := 0
	var masked := 0
	var t_old := 0
	var t_new := 0
	while pairs < 400:
		var a := p0 + Vector3(rng.randf_range(-12000, 12000), rng.randf_range(-12000, 12000), 0)
		var d := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2000, 15000)
		var b := a + Vector3(d.x, d.y, 0)
		var ga = IafHeights.height(a)
		var gb = IafHeights.height(b)
		if ga == null or gb == null:
			continue
		a.z = float(ga) + 1.5
		b.z = float(gb) + rng.randf_range(30, 300)
		pairs += 1
		var t0 := Time.get_ticks_usec()
		var los_old: bool = IafRadar.line_of_sight(a, b, old)
		var t1 := Time.get_ticks_usec()
		var los_new: bool = IafRadar.line_of_sight(a, b, tv.mission_ground)
		var t2 := Time.get_ticks_usec()
		t_old += t1 - t0
		t_new += t2 - t1
		differ += int(los_old != los_new)
		masked += int(not los_new)
	check(differ == 0, "line of sight: %d site-to-jet pairs (%d masked), %d differ" % [pairs, masked, differ])
	print(
		(
			"  line of sight: GDScript heights %.1f ms, Rust field %.1f ms for %d pairs"
			% [t_old / 1000.0, t_new / 1000.0, pairs]
		)
	)
	check(t_new * 3 < t_old, "the Rust field is much faster")
