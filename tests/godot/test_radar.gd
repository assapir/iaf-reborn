# The player's radar (docs/radar.md) in mission 221 (F-16, alpha_1): R turns it on in LRS, an AI jet
# ahead shows at its range and bearing, a lock goes to STT (auto-range), the IR seeker follows the
# radar target, the HUD gets the target box, Backspace drops the lock. Plus the pure rules: the
# detection range, the 60° cone, the Real F-16 range. The weapons run on a scripted sim time.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var Radar = load("res://weapons/radar.gd")
	# --- pure: range, cone ------------------------------------------------------------------------
	var r = Radar.new()
	r.setup(100)
	check(r.mode == r.OFF and r.modes[r.LRS].nm == 45.0 and r.modes[r.LRS].idx == 4, "F-16: off, LRS 45 NM, range 40 NM")
	var tgt := {"key": "t", "pos": Vector3(0, 30000, 5000), "vel": Vector3(0, 200, 0), "ent": {"klass": 1, "heading": 0.0}}
	var far := {"key": "u", "pos": Vector3(0, 50 * 1854.0, 5000), "vel": Vector3.ZERO, "ent": {"klass": 1}}
	r.units = func(): return [tgt, far]
	r.own = func(): return {"pos": Vector3(0, 0, 5000), "vel": Vector3(0, 200, 0), "fwd": Vector3(0, 1, 0), "up": Vector3(0, 0, 1), "yaw": 0.0}
	r.toggle_aa_ag(0.0)
	check(r.mode == r.LRS and r.contacts.size() == 1 and r.contacts[0].key == "t", "R: LRS, the unit 30 km ahead is a contact, the one at 50 NM not")
	check(absf(r.contacts[0].aspect) < 0.01, "flying away: aspect 0 (tail)")
	tgt.pos = Vector3(0, 45 * 1854.0 + 500.0, 5000)
	r.step_range(2, 1.0)
	check(r.contacts.size() == 1 and r.contacts[0].key == "t", "the selected unit beyond 45 NM is kept (re-tested without the range)")
	tgt.pos = Vector3(30000 * sin(deg_to_rad(65)), 30000 * cos(deg_to_rad(65)), 5000)
	r.scan(2.0)
	check(r.contacts.is_empty(), "65° off the nose: outside the 60° cone")
	check(absf(load("res://weapons/real_weapons.gd").radar_nm(100) * 1854.0 - 80000.0) < 1.0, "Real F-16 (APG-68): 80 km")

	# --- mission 221 ------------------------------------------------------------------------------
	var tv = await start_mission(221)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.rig.position.y += 3000.0
	var w = tv.weapons
	var o: Dictionary = w.own()
	var pilot = tv.ai.pilots[0]
	var ent: Dictionary = pilot.ent
	for e in tv.runtime.entities.values():
		if e != ent and not e.player:
			e.visible = false
	# 20 km ahead, 20° right of the nose, level.
	var az := deg_to_rad(20.0)
	var dir: Vector3 = (o.fwd * Vector3(1, 1, 0)).normalized().rotated(Vector3(0, 0, 1), -az)
	var tp: Vector3 = o.pos + dir * 20000.0
	ent.world = tp
	ent.alt = tp.z
	var t := 1.0
	w.update(t)
	check(w.radar.mode == 0, "the radar starts OFF")
	w.radar_event(0x2b)  # R
	check(w.radar.mode == w.radar.LRS, "R: LRS")
	var c: Array = w.radar.contacts.filter(func(x): return x.key == ent.key)
	check(c.size() == 1, "%s is a contact" % ent.name)
	if c.is_empty():
		return
	check(absf(c[0].dist - 20000.0) < 1.0, "range 20 km (%.0f m)" % c[0].dist)
	check(absf(c[0].az - az) < 0.01, "bearing 20° right (%.1f°)" % rad_to_deg(c[0].az))
	# MFD B-scope: R 40 NM = 112 px from y 115.
	w.radar_event(0x2a, ent.key)  # a click on the blip
	t += 0.05
	w.update(t)
	check(w.radar.mode == w.radar.STT and w.radar.locked().get("key", "") == ent.key, "lock: STT on %s" % ent.name)
	check(w.radar.range_index() == 3, "STT auto-range: 20 km -> 20 NM scale (index %d)" % w.radar.range_index())
	# The IR seeker follows the radar target.
	var aim := -1
	for i in 9:
		if w.stores.type_of(i) in [570, 580]:
			aim = i
	w.stores.cur = aim
	w.select_aa()
	for i in 4:
		t += 0.05
		w.update(t)
	check(w.hud_mode == 1 and w.seeker.target_key == ent.key and w.seeker.slaved(), "the IR seeker is slaved to the radar target")
	# HUD: the target box.
	var lk: Dictionary = tv.cockpit.radar.get("lock", {})
	check(lk.get("key", "") == ent.key, "the cockpit gets the lock")
	var box: Dictionary = tv.cockpit.hud.target_box(tv.cockpit.ui_scale())
	check(not box.is_empty() and box.p.x > tv.cockpit.hud.size.x / 2 and box.edge, "HUD target box held at the right edge (20° off the nose)")
	check(not box.get("hostile", true), "a friendly (alpha_2): the box gets the X")
	# Backspace: the lock drops, back to LRS.
	w.radar_event(0x31)
	t += 0.05
	w.update(t)
	check(w.radar.mode == w.radar.LRS and w.radar.locked().is_empty(), "Backspace: unlocked, LRS")
	w.radar_event(0x2c)
	check(w.radar.mode == w.radar.STBY and w.radar.contacts.is_empty(), "S: standby, no contacts")
	await frames(2)
