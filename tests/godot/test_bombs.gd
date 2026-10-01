# Bombs and rockets (docs/weapons.md §9): the impact prediction, the falling store's solver and
# impact checks, the ripple line / quantity / interval, and in mission 231 a level release on a tank
# (CCIP), a ripple, the delayed release off the HUD, a cluster bomb, rockets and the jettisons. The
# flight model is frozen; the test moves the jet along its velocity on a scripted sim time.
extends "res://../tests/godot/base.gd"

var tv: Node
var w
var t := 1.0
var vel_scene := Vector3(0, 0, -200)  # 200 m/s north


func run() -> void:
	var B = load("res://weapons/bombs.gd")
	var flat := func(_p): return 0.0
	# --- pure ----------------------------------------------------------------------------------
	var p := Vector3(0, 0, 1000)
	var v := Vector3(0, 200, 0)
	var t_fall := sqrt(1000.0 / 4.903)
	var i0: Vector3 = B.predict_impact(p, v, Vector3(0, 1, 0), 0.0, 0.0, flat).point
	check(absf(i0.y - 200.0 * t_fall) < 0.01 and absf(i0.z) < 0.01, "level release from 1000 m at 200 m/s: impact %.1f m ahead" % i0.y)
	var i1: Vector3 = B.predict_impact(p, v, Vector3(0, 1, 0), 23.0, 0.0, flat).point
	check(absf(i1.y - 177.0 * t_fall) < 0.01, "the HUD prediction takes the MK-82's drag 23 as m/s off the nose: %.1f m" % i1.y)
	var b: Dictionary = B.launch(0.0, p, v, i1, 15.0)
	check(absf(b.acc.y - 2.0 * (i1.y - 200.0 * t_fall) / (t_fall * t_fall)) < 1e-3 and absf(b.end - t_fall) < 1e-3,
		"solver: along-track %.2f m/s² lands it on the aim at t = %.2f s" % [b.acc.y, b.end])
	check(B.position(b, b.end).distance_to(i1) < 0.05, "the bomb meets the predicted point")
	var b2: Dictionary = b.duplicate(true)
	var burst: Dictionary = B.check(b, 30.0, flat)
	check(not burst.is_empty() and is_equal_approx(burst.t, 14.5) and burst.pos.z < -20.0,
		"original: the 0.5 s checks burst it under the ground (z %.1f at t %.1f)" % [burst.pos.z, burst.t])
	var burst2: Dictionary = B.check(b2, 30.0, flat, true)
	check(absf(burst2.pos.z) < 0.01 and burst2.pos.distance_to(i1) < 0.5, "fix: burst on the ground at the aim (%.2f m off)" % burst2.pos.distance_to(i1))
	var far: Dictionary = B.launch(0.0, p, v, Vector3(0, 6000, 0), 15.0)
	check(is_equal_approx(far.acc.y, 15.0), "the player's correction is clamped to ±15 m/s² (_debugParam016)")
	var line: Array = B.ripple_line(Vector3(0, 1000, 0), 4, 10.0, 0.0, flat)
	check(line.size() == 4 and is_equal_approx(line[0].y, 980.0) and is_equal_approx(line[3].y, 1010.0), "ripple line: 4 points 10 m apart along the heading, index 2 on the aim")

	# --- in flight: mission 231 ---------------------------------------------------------------
	var MR = load("res://mission/mission_runtime.gd")
	var bdb: Dictionary = MR.load_bdb(MR.mission_files(231)[0].data)
	var f16: Dictionary = MR.bdb_objects(bdb)[1]
	var desc: Dictionary = load("res://aircraft/aircraft_model.gd").load_descriptor("f16")
	tv = await start_mission(231)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	var load := {"armament": {"hardpoints": [14, 4, 0, 0, 31, 1, 15, 3, 28, 1, 15, 3, 31, 1, 0, 0, 14, 4, 25, 235, 33, 90, 34, 60]}}
	w = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w)
	w.setup(tv, load, f16, bdb, desc)
	tv.cockpit.on_ripple_event = w.ripple_event
	var tanks: Array = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("t55"))
	check(tanks.size() >= 4, "mission 231 has T-55 tanks")
	var tank0: Dictionary = tanks[0]
	_start_over(tv.runtime._world_of(tank0))
	check(w.stores.total(500, "MK-82") == 6 and w.stores.type_of(0) == 560 and w.stores.type_of(2) == 510, "MK-82 x6, CBU-87, ZUNNI pods loaded")
	w.stores.cur = 3
	w._master_from_type(false)
	check(w.hud_mode == 5 and w.master == 1, "a bomb selected: master mode 1, HUD mode 5")
	# Put the CCIP impact on the tank (move the jet, not the tank).
	for k in 3:
		w.update(t)
		var d: Vector3 = tv.runtime._world_of(tank0) - w.ag.impact
		tv.rig.position += Vector3(d.x, 0, -d.y)
	w.update(t)
	check(tv.cockpit.weapons.ag.pipper != null and not tv.cockpit.weapons.ag.off, "CCIP pipper published (on the HUD)")
	check(_hd(w.ag.impact, tv.runtime._world_of(tank0)) < 2.0, "CCIP on the tank")
	var mass0: float = w.stores.fm_mass
	# Quantity 1 (stores page OSB 0xf: quantity −1).
	tv.cockpit.mfds[0].page = 1
	tv.cockpit.mfds[0].press(0xf)
	check(w.ripple_qty == 1, "stores OSB 0xf: quantity 2 -> 1")
	w.fire_selected()
	_fly(0.05)
	w.release_selected()
	check(w.bombs.size() == 1 and w.stores.total(500, "MK-82") == 5, "Space: one bomb released (quantity 1)")
	check(w.stores.fm_mass < mass0, "stores weight dropped")
	var aim0: Vector3 = w.bombs[0].b.aim
	await _until_landed()
	check(int(tank0.state) == 5, "the MK-82 destroyed the tank (state %d, damage %.2f)" % [tank0.state, tank0.damage])
	check(_hd(aim0, tv.runtime._world_of(tank0)) < 2.0, "it aimed at the CCIP point")

	# Ripple: quantity 4, interval 200 (200 m apart, a bomb every 0.2 s), stations alternating.
	_start_over(tv.runtime._world_of(tanks[1]) + Vector3(0, -3000, 0))
	w.ripple_qty = 1
	for k in 3:
		w.ripple_event(0x4a, true)
	for k in 19:
		w.ripple_event(0x4b, true)
	check(w.ripple_qty == 4 and w.ripple_int == 200 and is_equal_approx(w.ripple_period, 0.2), "quantity 4, interval 200, period 0.2 s")
	w.update(t)
	var times := []
	var n0: int = w.bombs.size()
	w.fire_selected()
	for k in 30:
		_fly(0.05)
		if w.bombs.size() > n0 + times.size():
			times.append(t)
	w.release_selected()
	check(times.size() == 4, "ripple: 4 bombs (%d)" % times.size())
	if times.size() == 4:
		# The first bomb goes on the timer's first tick (the next update), then one per period.
		check(absf(times[3] - times[1] - 0.4) < 0.01 and times[0] - times[1] < 0.0, "one every 0.2 s (%.2f s from the 2nd to the 4th)" % (times[3] - times[1]))
		var aims: Array = w.bombs.slice(n0).map(func(x): return x.b.aim)
		check(absf(_hd(aims[0], aims[3]) - 600.0) < 1.0, "ripple aims 200 m apart along the heading (%.0f m over 3)" % _hd(aims[0], aims[3]))
	check(w.stores.displayed(3) == 0 and w.stores.displayed(5) == 1, "stations 3 / 5 alternate (left %d / %d)" % [w.stores.displayed(3), w.stores.displayed(5)])
	await _until_landed()
	# Holding Space shorter stops the ripple.
	w.ripple_qty = 4
	w.stores.cur = 2
	w._master_from_type(false)
	w.update(t)
	n0 = w.bombs.size()
	w.fire_selected()
	_fly(0.05)
	w.release_selected()
	_fly(0.5)
	check(w.bombs.size() == n0 + 1, "Space up ends the ripple (1 of 4)")

	# Cluster bomb (510): the 0x2000 bursts, damage over its radius.
	var c0: int = tv.effects.counts().get("clusters", 0)
	var cl: Array = []
	await _until_landed(func(): cl.append(tv.effects.counts().get("clusters", 0)))
	check(cl.max() > c0, "CBU-87: the cluster bursts (48 small fires in 3 rings)")

	# The delayed release: the pipper off the HUD (a fake HUD test: off, ray 10° down ahead).
	_start_over(tv.runtime._world_of(tanks[2]) + Vector3(0, -6000, 0))
	w.ripple_qty = 1
	w.stores.cur = 5
	w._master_from_type(false)
	w.hud_clip = func(_wp): return {"off": true, "origin": tv.rig.position, "dir": Vector3(0, -0.1736, -0.9848)}
	w.update(t)
	var tgt: Vector3 = w.ag.target
	check(w.ag.off and w.ag.ttg > 5.0, "off the HUD: target ahead, time-to-go %.1f s" % w.ag.ttg)
	w.fire_selected()
	_fly(0.5)
	check(w.stores.displayed(5) == 1 and w.ag.frozen, "Space: no bomb before the cue, the target frozen")
	var released := false
	for k in 400:
		_fly(0.05)
		if w.stores.displayed(5) == 0:
			released = true
			break
	w.release_selected()
	w.hud_clip = Callable()
	check(released and w.ag.ttg <= 0.9 + 0.05, "released at time-to-go %.2f s" % w.ag.ttg)
	var aim2: Vector3 = w.bombs[-1].b.aim
	await _until_landed()
	check(_hd(aim2, tgt) < 1.0, "the delayed bomb aimed at the frozen target")

	# Rockets (560): the fixed-weapon flight to the aim, the blast there.
	_start_over(tv.runtime._world_of(tanks[3]) + Vector3(0, -3000, 0))
	w.stores.cur = 0
	w._master_from_type(false)
	w.update(t)
	check(w.hud_mode == 5, "rockets: HUD mode 5")
	var tank3: Dictionary = tanks[3]
	var r_aim: Vector3 = w.ag.impact
	tank3.world = r_aim
	tv.mission_entity_moved(tank3)
	var z0: int = w.stores.total(560, "ZUNNI")
	w.fire_selected()
	_fly(0.05)
	w.release_selected()
	check(w.stores.total(560, "ZUNNI") == z0 - 1 and w.rockets.flying_count() == 1, "Space: one rocket away")
	for k in 600:
		_fly(0.05)
		if w.rockets.flying_count() == 0:
			break
	check(w.rockets.flying_count() == 0 and int(tank3.state) == 5, "the rocket hit the tank at its aim (state %d)" % tank3.state)

	# Jettison: the tank first (it falls), then the bombs (rockets stay).
	n0 = w.bombs.size()
	w.jettison()
	check(w.tanks_jettisoned and w.bombs.size() == n0 + 1 and w.stores.displayed(4) == 0, "first jettison: the tank falls")
	w.jettison()
	check(w.bombs_jettisoned and w.stores.total(500, "MK-82") == 0 and w.stores.total(510, "CBU-87") == 0
		and w.stores.total(560, "ZUNNI") == z0 - 1, "second jettison: every bomb, not the rockets")
	await _until_landed()
	check(w.bombs.is_empty(), "jettisoned stores reached the ground")
	w.queue_free()
	await frames(2)


## A fresh airborne flight-model start 1000 m above `ground_pt` (world) heading north at 200 m/s;
## the frozen rig carries the position, the flight model the velocity.
func _start_over(ground_pt: Vector3) -> void:
	var g = tv.mission_ground(ground_pt)
	var sp: Vector3 = tv.world_to_scene(Vector3(ground_pt.x, ground_pt.y, float(g if g != null else 0.0) + 1000.0))
	tv.rig.position = sp
	tv.rig.basis = Basis()
	tv.flight.start(Settings().assets_dir().path_join("install"), "F-16", sp, 0.0, 0.0, 0.0, vel_scene, true, true, false)
	w._push_stores()


func _fly(dt: float) -> void:
	tv.rig.position += vel_scene * dt
	t += dt
	w.update(t)


## Flies on until every falling store has burst (at most 40 s); `each` runs after every step.
func _until_landed(each := Callable()) -> void:
	for k in 800:
		_fly(0.05)
		if each.is_valid():
			each.call()
		if w.bombs.is_empty() and (w.rockets == null or w.rockets.flying_count() == 0):
			break
	await frames(1)


static func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()
