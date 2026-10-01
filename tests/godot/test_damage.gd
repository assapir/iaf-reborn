# Damage and destruction (docs/damage.md): the blast formula and level thresholds, the systems-damage
# pick, then mission 231 "License" through the runtime: destroying both role-1 tanks passes the
# mission (explosion, destroy events, "Mission Accomplished!"); a partial hit smokes nothing and keeps
# the unit alive, >= 0.8 fatally hits it (state 3); destroying the role-0 HermonPost fails it. The
# player's jet: a hit breaks systems (damage page, master caution), a fatal hit takes the controls,
# the destruction motion brings the jet down and it explodes (flight ends into the debrief).
extends "res://../tests/godot/base.gd"

const DamageModel := preload("res://mission/damage_model.gd")


func unit(rt, name: String) -> Dictionary:
	for e in rt.entities.values():
		if e.name == name:
			return e
	return {}


func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


func run() -> void:
	# Blast (FUN_004642f0): full power at the centre, falling off per axis, nothing outside R.
	check(is_equal_approx(DamageModel.blast(Vector3.ZERO, 0.0, Vector3.ZERO, 100.0, 50.0), 100.0), "blast at the centre = power")
	check(is_equal_approx(DamageModel.blast(Vector3(25, 0, 0), 0.0, Vector3.ZERO, 100.0, 50.0), 50.0), "half the radius on one axis = half")
	check(is_equal_approx(DamageModel.blast(Vector3(30, 0, 0), 10.0, Vector3.ZERO, 100.0, 40.0), 50.0), "the unit's size shortens the distance")
	check(DamageModel.blast(Vector3(0, 60, 0), 0.0, Vector3.ZERO, 100.0, 50.0) == 0.0, "outside the radius: nothing")
	check(DamageModel.level_for(0.79) == -1 and DamageModel.level_for(0.8) == 3 and DamageModel.level_for(1.0) == 5, "levels: 0.8 hit, 1.0 destroyed")
	var r: Array = DamageModel.add_damage(0.0, 50.0, 100.0, true, 0)
	check(is_equal_approx(r[0], 0.4) and not r[1], "Rookie: an enemy takes 0.8 of the damage (%.2f)" % r[0])
	r = DamageModel.add_damage(0.5, 60.0, 100.0, false, 0)
	check(is_equal_approx(r[0], 1.0) and r[1], "accumulated damage reaching 1 destroys")
	# Systems pick (FUN_0045cd80): a light hit breaks one of the first systems; an engine cut-out never happens.
	var flags := []
	flags.resize(25)
	flags.fill(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 400:
		var p: Array = DamageModel.pick_system(0.2 + 0.7 * (i % 3) / 2.0, flags, false, true, false, false, func(): return rng.randi() & 0x7fff)
		seen[p[0]] = true
	check(not seen.has(2) and not seen.has(3), "engine cut-out never picked (quirk kept)")
	check(not seen.has(9) and not seen.has(17) and not seen.has(23), "single engine: no right-engine systems")

	# 231: two role-1 tanks, a role-0 post.
	Settings().invulnerable = false
	var tv = await start_mission(231)
	var rt = tv.runtime
	var p0: Dictionary = rt.player_entity()
	var t0: Dictionary = unit(rt, "t62_0")
	var t1: Dictionary = unit(rt, "t62_1")
	check(rt.targets_left == 2 and not t0.is_empty() and not t1.is_empty(), "231: two role-1 tanks")
	check(t0.strength > 0.0, "tank strength from the bdb (%.0f)" % t0.strength)
	# A small hit: stored, still alive (an enemy of the player takes 0.9 of it at the Normal AI level).
	rt.apply_damage(t0, t0.strength * 0.3, "blast", p0)
	check(t0.state == 1 and is_equal_approx(t0.damage, 0.27), "30 %% hit at Normal: alive, damage 0.27 (%.2f)" % t0.damage)
	# Past 0.8: fatally hit (state 3), the unit stays where it is (no end check for ground units).
	rt.apply_damage(t0, t0.strength * 0.65, "blast", p0)
	check(t0.state == 3, "0.855: fatally hit, state 3 (%d)" % t0.state)
	# A blast on the tank destroys it: explosion, the second one too -> mission passed.
	rt.area_damage(rt._world_of(t0), t0.strength * 2.0, 20.0, p0)
	check(t0.state == 5 and rt.targets_left == 1, "blast destroys the first tank (state %d)" % t0.state)
	check(tv.effects.counts().pieces > 0 or tv.effects.counts().columns > 0, "explosion effect spawned (%s)" % str(tv.effects.counts()))
	rt.apply_damage(t1, t1.strength * 5.0, "blast", p0)
	check(t1.state == 5 and rt.passed, "second tank destroyed: mission passed")
	await seconds(10.5)
	check(tv._msgbox != null and tv._msgbox.buttons == ["deb", "fly"], "Mission Accomplished box after 10 s")

	# A low aircraft explosion (0x58ba, pieces rest) 8 m above the ground: every resting piece lies on
	# the terrain under it, none in the air.
	var fx = tv.effects
	var at: Vector3 = tv.rig.global_position
	var gy: float = tv.terrain.height_at(at)
	fx.explosion(Vector3(at.x, gy + 8.0, at.z), 0x58ba, 4.0, 95.0, gy, 6.0)
	await seconds(4.0)
	var resting: Array = fx._pieces.filter(func(p): return p.resting)
	var off: Array = resting.filter(func(p): return absf(p.node.position.y - tv.terrain.height_at(p.node.position)) > 0.05)
	check(resting.size() > 0 and off.is_empty(), "debris rests on the terrain (%d resting, %d off)" % [resting.size(), off.size()])

	# With the unit's model the pieces are its polygons (FUN_004172b0): one shatter mesh; the resting
	# ones (0x1000) end on the terrain under their landing point.
	fx.explosion(Vector3(at.x, gy + 8.0, at.z), 0x58ba, 4.0, 95.0, gy, 6.0, tv.aircraft)
	var sh: Dictionary = fx._shards.back()
	var bad := 0
	for p in sh.large:
		var q: Vector3 = p.c + p.vel * p.stop + Vector3(0, -0.5 * fx.PIECE_G * p.stop * p.stop, 0)
		if p.stop < p.end and absf(q.y - tv.terrain.height_at(q)) > 0.5:
			bad += 1
	check(fx.counts().shards >= 1 and sh.large.size() > 0 and bad == 0, "model shatter: %d large pieces, %d not on the terrain" % [sh.large.size(), bad])

	# Destroying the must-survive post fails the mission.
	tv = await start_mission(231)
	rt = tv.runtime
	var post: Dictionary = unit(rt, "HermonPost")
	check(post.role == 0, "HermonPost must survive")
	rt.apply_damage(post, post.strength * 5.0, "blast", rt.player_entity())
	check(post.state == 5 and rt.failed and not rt.passed, "post destroyed: mission failed")

	# The player's jet (324, airborne at 2000 m): a hit breaks a system; Invulnerable takes nothing.
	tv = await start_mission(324)
	rt = tv.runtime
	post = unit(rt, "Mig21 leader")
	var me: Dictionary = rt.player_entity()
	Settings().invulnerable = true
	rt.apply_damage(me, me.strength * 0.5, "missile", post)
	check(me.damage == 0.0, "Invulnerable: no damage")
	Settings().invulnerable = false
	rt.apply_damage(me, me.strength * 0.5, "missile", post)
	check(me.state == 1 and is_equal_approx(me.damage, 0.5), "player hit: damage 0.5")
	check(tv.player_damage.flags.has(true) and tv.cockpit.indicators[0], "a system broke, master caution on")
	check(tv.sounds.played.has("SFX_AIRCRAFT_DAMAGED/DAMAGED_MISSILE_HIT"), "missile-hit thump")
	# Fatal hit: controls gone, "Eject! Eject!", the jet falls and explodes at the ground.
	rt.apply_damage(me, me.strength * 0.4, "missile", post)
	check(me.state == 3 and tv.fatal_hit and tv.fm_stopped, "fatal hit: state 3, flight model stopped")
	check(tv.sounds.played.has("VOC_WINGMAN/WINGMAN_EJECT_EJECT"), "Eject! Eject!")
	var alt0: float = tv.rig.position.y
	await seconds(1.0)
	check(tv.rig.position.y < alt0 - 5.0, "the jet falls (%.0f -> %.0f m)" % [alt0, tv.rig.position.y])
	var t := Time.get_ticks_msec()
	while me.state != 5 and Time.get_ticks_msec() - t < 30000:
		await process_frame
	check(me.state == 5, "hits the ground and explodes")
	t = Time.get_ticks_msec()
	while current_scene == tv and Time.get_ticks_msec() - t < 8000:
		await process_frame
	check(current_scene != tv, "flight ends 5 s later (event 0x82)")
