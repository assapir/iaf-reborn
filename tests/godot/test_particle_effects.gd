# Preferences > Graphics > MORE "Particle effects" (docs/rendering.md §6): with Original the damage effects, trails and
# afterburners build the original billboards / ribbons and no GPU particles; with Detailed the same events (same seed,
# same steps) spawn exactly as many puffs, drawn by the GPU particle pools (mission/gpu_fx.gd), missile trails as smoke
# ribbons with a motor flame (mission/missile_fx.gd) while wingtip trails stay the original ribbons, and each
# afterburner gets its heat haze.
extends "res://../tests/godot/base.gd"

const STEP := 1.0 / 30.0


func _effects(detailed: bool) -> Node3D:
	settings().particle_effects = detailed
	var fx: Node3D = load("res://mission/damage_effects.gd").new()
	root.add_child(fx)
	fx.set_process(false)
	fx._rng.seed = 1234
	# Every explosion kind of explosion_for, a missile hit, a bomb, a cluster, damage smoke.
	var p := Vector3(0, 100, 0)
	for k in [
		[1, 0, false, false],
		[1, 0, true, false],
		[1, 0, true, true],
		[5, 0, true, false],
		[8, 0, true, false],
		[0xc, 410, true, false],
		[0xc, 420, true, false],
		[0xc, 0, true, false],
		[0xf, 0, true, false]
	]:
		var e: Dictionary = fx.explosion_for(k[0], k[1], k[2], k[3])
		fx.explosion(p, e.flags, e.scale, e.duration, 0.0, 6.0)
		p.x += 50.0
	fx.explosion(p, fx.F_FIREBALL | fx.F_PUFF, 1.0, 5.0, 0.0)
	fx.explosion(p, fx.F_FLASH | fx.F_SMOKE_TRAILS, 4.0, 95.0, 0.0)
	fx.explosion(p, fx.F_CLUSTER, 4.0, 3.0, 0.0, 100.0)
	var smoker := Node3D.new()
	fx.add_child(smoker)
	fx.set_smoke(smoker, true)
	return fx


func _run(fx: Node3D, steps: int) -> int:
	var shown := 0
	for i in steps:
		fx._process(STEP)
		shown = maxi(shown, fx._mm_smoke.multimesh.instance_count + fx._mm_fire.multimesh.instance_count)
	return shown


func run() -> void:
	var a := _effects(false)
	var b := _effects(true)
	var t0 := Time.get_ticks_usec()
	var shown_a := _run(a, 300)
	var t1 := Time.get_ticks_usec()
	var shown_b := _run(b, 300)
	var t2 := Time.get_ticks_usec()
	print("CPU per step: original %.3f ms, detailed %.3f ms" % [(t1 - t0) / 300000.0, (t2 - t1) / 300000.0])
	check(
		a.gpu == null and a.find_children("*", "GPUParticles3D", true, false).is_empty(), "Original: no GPU particles"
	)
	check(shown_a > 0, "Original: the puffs are drawn as billboards (%d at most)" % shown_a)
	check(
		b.gpu != null and b.find_children("*", "GPUParticles3D", true, false).size() == 3,
		"Detailed: the three GPU pools"
	)
	check(a.spawned > 100 and a.spawned == b.spawned, "the same puffs spawn in both (%d / %d)" % [a.spawned, b.spawned])
	var ca: Dictionary = a.counts()
	var cb: Dictionary = b.counts()
	ca.erase("puffs")
	cb.erase("puffs")
	check(ca == cb, "the same pieces, columns, clusters, smokers in both (%s)" % [cb])
	check(shown_b == 0 and b.counts().puffs == 0, "Detailed: no billboards")
	var em: Dictionary = b.gpu.emitted
	check(em.smoke > 0 and em.fire > 0 and em.sparks > 0, "Detailed: smoke, fire and sparks emitted (%s)" % [em])

	# Trails: the same bookkeeping; missile trails become GPU smoke, wingtip trails stay ribbons.
	var trails_script: GDScript = load("res://mission/trails.gd")
	var ta: Node3D = trails_script.new()
	var tb: Node3D = trails_script.new()
	root.add_child(ta)
	root.add_child(tb)
	ta.set_process(false)
	tb.set_process(false)
	tb.gpu = b.gpu
	var mfx: Node3D = b.gpu.missiles
	mfx.set_process(false)
	for i in 60:
		for t in [ta, tb]:
			t.emit("missile", Vector3(i * 10.0, 500, 0), t.MISSILE)
			t._process(STEP)
		mfx._process(STEP)
	check(ta.counts() == tb.counts(), "trails: the same points and glows (%s)" % [tb.counts()])
	check(
		ta._mesh.get_surface_count() == 1 and tb._mesh.get_surface_count() == 0,
		"missile trail: the original ribbon / none with Detailed"
	)
	check(
		ta._glows.multimesh.instance_count == 1 and tb._glows.multimesh.instance_count == 0,
		"motor glow: missFLR / Detailed's own flame"
	)
	var mc: Dictionary = mfx.counts()
	check(mc.ribbons == 1 and mc.points == 60 and mc.flames == 1, "Detailed: one smoke ribbon, a flame (%s)" % [mc])
	var head: Node3D = mfx._flames[0].root
	check(
		head.global_position.distance_to(Vector3(590 + mfx.NOZZLE, 500, 0)) < 1e-3,
		"the flame sits at the nozzle, 1 m ahead of the trail head (%s)" % [head.global_position]
	)
	# Burnout or the missile gone: no more points; the flame goes out, the smoke stays until it fades.
	for i in 3:
		tb._process(STEP)
		mfx._process(STEP)
	mc = mfx.counts()
	check(mc.ribbons == 1 and mc.flames == 0, "after burnout: the smoke stays, no flame (%s)" % [mc])
	mfx._process(mfx.LIFE)
	check(mfx.counts().ribbons == 0, "the smoke is gone after %d s" % mfx.LIFE)
	for t in [ta, tb]:
		for i in 3:
			t.emit("tip", Vector3(i, 300, 0), t.WINGTIP)
			t._process(STEP)
	check(tb._mesh.get_surface_count() == 1, "wingtip trail: still a ribbon with Detailed")

	# Better physics wind: trail points and smoke puffs drift with the air mass (gpu_fx.gd `wind`, scene m/s).
	var gpu_fx: GDScript = load("res://mission/gpu_fx.gd")
	gpu_fx.wind = Vector3(10, 0, 0)
	var pt: Array = ta._trails[-1].pts[-1]
	var x0: float = pt[0].x
	ta._process(0.1)
	check(absf(pt[0].x - x0 - 1.0) < 1e-4, "wind: a trail point drifts 10 m/s × 0.1 s (%.4f m)" % (pt[0].x - x0))
	a.explosion(Vector3(0, 100, 0), a.F_FIREBALL | a.F_PUFF, 1.0, 5.0, 0.0)
	var puff: Dictionary = a._puffs[-1]
	var want: Vector3 = puff.pos + (puff.vel + gpu_fx.wind) * STEP
	a._process(STEP)
	check(puff.pos.is_equal_approx(want), "wind: a smoke puff moves with the air (%s)" % [puff.pos - want])
	gpu_fx.wind = Vector3.ZERO

	# Contrails (Detailed only): from each nozzle above the contrail altitude, none below.
	var model_script := GDScript.new()
	model_script.source_code = "extends Node3D\nvar flames: Array = []\n"
	model_script.reload()
	var jet := Node3D.new()
	jet.set_script(model_script)
	root.add_child(jet)
	var afterburner_script: GDScript = load("res://aircraft/afterburner.gd")
	var noz: MeshInstance3D = afterburner_script.new()
	jet.add_child(noz)
	jet.flames.append(noz)
	var s0: int = b.gpu.emitted.smoke
	jet.position = Vector3(0, 5000, 0)
	b.gpu.contrail(jet)
	jet.position.x += 100.0
	b.gpu.contrail(jet)
	var s1: int = b.gpu.emitted.smoke
	jet.position = Vector3(0, b.gpu.CONTRAIL_ALT + 500.0, 0)
	b.gpu.contrail(jet)
	jet.position.x += 100.0
	b.gpu.contrail(jet)
	check(s1 == s0 and b.gpu.emitted.smoke > s1, "contrails above %d m only" % b.gpu.CONTRAIL_ALT)

	# Afterburner heat haze.
	for detailed in [false, true]:
		settings().particle_effects = detailed
		var holder := Node3D.new()
		root.add_child(holder)
		var f: MeshInstance3D = afterburner_script.new()
		f.nozzle = Vector3(0.3, -0.2, 7.5)
		f.radius = 0.45
		holder.scale = Vector3.ONE * 0.2  # a model's clump scale
		holder.position = Vector3(100, 2000, -50)
		holder.add_child(f)
		await frames(2)
		f.level = 100
		f.rebuild()
		if detailed:
			check(
				f.haze != null and f.haze.get_parent() == holder and f.haze.visible,
				"Detailed: the afterburner's heat haze"
			)
			# The haze's near end (the cylinder's bottom ring centre) sits on the nozzle, in the model's frame.
			var near: Vector3 = f.haze.global_transform * Vector3(0, -0.5, 0)
			var nz: Vector3 = f.global_transform * f.nozzle
			check(near.distance_to(nz) < 0.03, "the heat haze starts at the nozzle (%.3f m off)" % near.distance_to(nz))
		else:
			check(f.haze == null and holder.get_child_count() == 1, "Original: no heat haze")
	# On real jets the haze starts at the model's EngineL / EngineR helper, also with the jet moved and turned.
	settings().particle_effects = true
	var AM = load("res://aircraft/aircraft_model.gd")
	for case in [["f16", "original"], ["mig29", "original"], ["f16", "detailed"]]:
		var plane: String = case[0]
		settings().models = case[1]
		var m: Node3D = AM.create(plane, -1, false)
		root.add_child(m)
		m.position = Vector3(1500, 3000, -800)
		m.rotation = Vector3(0.2, 1.1, -0.4)
		await frames(2)
		var worst := 0.0
		var n := 0
		for f in m.flames:
			var helper: Node3D = m.find_child("EngineR" if f.name.ends_with("right") else "EngineL", true, false)
			worst = maxf(worst, (f.haze.global_transform * Vector3(0, -0.5, 0)).distance_to(helper.global_position))
			n += 1
		check(
			n > 0 and worst < 0.03,
			(
				"%s (%s model): the heat haze starts at the Engine helper (%d nozzles, %.3f m off)"
				% [plane, case[1], n, worst]
			)
		)
		m.free()
	# Condensation (vapour_fx.gd): wingtip and LEX streamers in a hard turn low down, none in 1 G flight; the vapour
	# shell near Mach 1.
	settings().models = "original"
	var jet16: Node3D = AM.create("f16", -1, false)
	root.add_child(jet16)
	jet16.position = Vector3(0, 300, 0)
	var eye := Camera3D.new()
	root.add_child(eye)
	eye.position = Vector3(0, 310, 40)
	eye.make_current()
	var vf: Node3D = b.gpu.vapour
	var calm := {"g": 1.0, "aoa": 3.0, "mach": 0.5, "speed": 170.0, "alt_ft": 1000.0}
	await _feed(vf, jet16, calm)
	var j = vf._jets[jet16.root_frame]
	var lit := func() -> int: return j.trails.reduce(func(n, t): return n + t.size(), 0)
	check(j.tips.size() == 2 and lit.call() == 0, "vapour: no streamers at 1 G (%d points)" % lit.call())
	var turn := {"g": 7.5, "aoa": 22.0, "mach": 0.6, "speed": 200.0, "alt_ft": 1000.0}
	await _feed(vf, jet16, turn)
	check(j.k_tip > 0.9 and lit.call() >= 20, "vapour: wingtip streamers in a 7.5 G turn (%d)" % lit.call())
	check(j.plume.visible and j.k_lex > 0.5, "vapour: the LEX plume at 22° AoA (%.2f)" % j.k_lex)
	check(not j.shell.visible or j.k_cone < 0.01, "vapour: no cone at Mach 0.6")
	# The vortex strength n·CL: a 4.5 G pull at 120 m/s condenses as much; 4 G at 250 m/s hardly.
	await _feed(vf, jet16, {"g": 4.5, "aoa": 18.0, "mach": 0.36, "speed": 120.0, "alt_ft": 1000.0})
	check(j.k_tip > 0.9, "vapour: wingtip streamers in a 4.5 G pull at 120 m/s (%.2f)" % j.k_tip)
	await _feed(vf, jet16, {"g": 4.0, "aoa": 6.0, "mach": 0.75, "speed": 250.0, "alt_ft": 1000.0})
	check(j.k_tip < 0.05, "vapour: none at 4 G and 250 m/s (%.2f)" % j.k_tip)
	# The cockpit views: the streamers leave the drawn frame's own wingtips (terrain_view.gd vapour_state).
	var bc: Node3D = AM.create("f16", -1, false)
	root.add_child(bc)
	bc.position = jet16.position + Vector3(0, 1, 5)
	bc.scale = Vector3.ONE * 1.5
	await _feed(vf, jet16, turn.merged({"frame": bc.root_frame}))
	var jb = vf._jets.get(bc.root_frame)
	check(
		(
			jb != null
			and jb.trails[0].size() > 0
			and jb.trails[0][-1][0].distance_to(bc.root_frame.global_transform * jb.tips[0]) < 0.01
		),
		"vapour: the cockpit frame's own wingtips"
	)
	bc.free()
	await _feed(vf, jet16, {"g": 1.0, "aoa": 2.0, "mach": 0.95, "speed": 320.0, "alt_ft": 300.0})
	check(j.shell.visible and j.k_cone > 0.9, "vapour: the shell at Mach 0.95 low down (%.2f)" % j.k_cone)
	jet16.free()
	# The emitters on each model: the tips at the model's span (the game's F-16 spans ≈ 7 m), and a LEX plume.
	for case in [["f16", "original"], ["f16", "detailed"], ["f35i", "original"]]:
		settings().models = case[1]
		var mj: Node3D = AM.create(case[0], -1, false)
		root.add_child(mj)
		await frames(1)
		var geo: Array = vf._geometry(mj.root_frame, case[0])
		var pts: Array = geo[0]
		var span := 0.0
		if pts.size() >= 2:
			span = mj.root_frame.to_global(pts[0]).distance_to(mj.root_frame.to_global(pts[1]))
		check(
			pts.size() == 2 and span > 6.0 and span < 12.0 and geo[2] != null,
			"vapour: %s (%s model) wingtips %.2f m apart" % [case[0], case[1], span]
		)
		mj.free()
	eye.free()
	settings().particle_effects = false
	settings().models = "original"


## Feeds vapour_fx.gd one jet's flight `state` every frame for 0.8 s of frame time (the fades are timed, not counted).
func _feed(vf: Node3D, jet: Node3D, state: Dictionary) -> void:
	var t := 0.0
	while t < 0.8:
		vf.update(jet, state)
		await frames(1)
		t += vf.get_process_delta_time()
