# A bombing mission end to end (docs/mission-coverage.md: 315 "Cold Steel" became playable with the
# bombs): with its default MK-83 load, a CCIP release over each target (jet 1000 m above it, 200 m/s,
# the pipper on the target) until every target is destroyed. The flight model
# is frozen; the test moves the jet along its velocity on a scripted sim time. Original burst rule.
extends "res://../tests/godot/base.gd"

var tv: Node
var w
var t := 1.0
var vel_scene := Vector3(0, 0, -200)


func run() -> void:
	tv = await start_mission(315)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	w = tv.weapons
	var rt = tv.runtime
	var targets: Array = rt.entities.values().filter(func(e): return int(e.role) == rt.ROLE_TARGET)
	check(targets.size() == rt.targets_left and targets.size() > 0, "mission 315: %d targets" % targets.size())
	var bomb_station := -1
	for i in 9:
		if w.stores.type_of(i) == 500:
			bomb_station = i
	check(bomb_station >= 0, "default load has bombs (%s)" % w.stores.name_of(bomb_station))
	w.stores.cur = bomb_station
	w._master_from_type(false)
	w.ripple_qty = 1
	var used := 0
	for tgt in targets:
		var tries := 0
		while int(tgt.state) < 4 and w.stores.total(500, w.stores.current_name()) > 0 and tries < 3:
			tries += 1
			used += 1
			_start_over(rt._world_of(tgt))
			for k in 3:
				w.update(t)
				var d: Vector3 = rt._world_of(tgt) - w.ag.impact
				tv.rig.position += Vector3(d.x, 0, -d.y)
			w.update(t)
			w.fire_selected()
			_fly(0.05)
			w.release_selected()
			for k in 800:
				_fly(0.05)
				if w.bombs.is_empty():
					break
		print("target %s: state %d after %d bomb(s)" % [tgt.name, tgt.state, tries])
	await frames(2)
	for e in rt.entities.values():
		if int(e.state) >= 4 and int(e.role) != rt.ROLE_TARGET:
			print("also destroyed: %s (role %d)" % [e.name, e.role])
	check(targets.all(func(e): return int(e.state) >= 4) and rt.targets_left == 0, "every target destroyed (%d bombs)" % used)
	# Not checked: rt.passed. The jet is lost at the spawn already (with schacha3, its shelter: a
	# pre-existing start problem of 315), and a bomb on "runway ccip2" also takes the "Start motion
	# sensor" (role survive) next to it — either fails the mission.


func _start_over(ground_pt: Vector3) -> void:
	var g = tv.mission_ground(ground_pt)
	var sp: Vector3 = tv.world_to_scene(Vector3(ground_pt.x, ground_pt.y, float(g if g != null else 0.0) + 1000.0))
	tv.rig.position = sp
	tv.rig.basis = Basis()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, sp, 0.0, 0.0, 0.0, vel_scene, true, true, false)
	w._push_stores()


func _fly(dt: float) -> void:
	tv.rig.position += vel_scene * dt
	t += dt
	w.update(t)
